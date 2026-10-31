#!/usr/bin/env python3
"""Read-only ICS subscription. URLs and event data stay on this computer."""
import datetime as dt
import hashlib
import html
from html.parser import HTMLParser
import re
import json
import os
from pathlib import Path
import sys
import tempfile
import urllib.parse
import urllib.request
import unicodedata

STATE = Path(os.environ.get('XDG_STATE_HOME', str(Path.home() / '.local/state'))) / 'ii/calendars'
LEGACY_STATE = Path(os.environ.get('XDG_STATE_HOME', str(Path.home() / '.local/state'))) / 'ii/work-calendar'


def read(name, default):
    try:
        return json.loads((STATE / name).read_text())
    except FileNotFoundError:
        return default


def write(name, value):
    STATE.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(STATE, 0o700)
    fd, temporary = tempfile.mkstemp(dir=STATE)
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump(value, stream, ensure_ascii=False, separators=(',', ':'))
        os.replace(temporary, STATE / name)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def secure_url(url):
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password:
        raise ValueError('Use an HTTPS ICS subscription link without a login/password.')
    return url


class HTTPSRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        secure_url(newurl)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def category_key(value):
    return unicodedata.normalize('NFKC', value).strip().casefold()


def read_legacy(name, default):
    try:
        return json.loads((LEGACY_STATE / name).read_text())
    except FileNotFoundError:
        return default


def load_state():
    config = read('config.json', None)
    cache = read('cache.json', {})
    if config is not None:
        if isinstance(config, dict) and 'url' in config and 'calendars' not in config:
            calendars = []
            caches = {}
            if config.get('url'):
                calendars.append({'id': 'work', 'name': 'Work calendar', 'category': 'Work',
                                  'url': secure_url(str(config['url']).strip())})
                if isinstance(cache, dict):
                    caches['work'] = cache
            config = {'version': 1, 'calendars': calendars}
            cache = caches
            write('cache.json', cache)
            write('config.json', config)
        if not isinstance(config, dict) or not isinstance(config.get('calendars'), list):
            raise ValueError('Invalid calendar settings')
        return config, cache if isinstance(cache, dict) else {}

    legacy = read_legacy('config.json', {})
    legacy_cache = read_legacy('cache.json', {})
    calendars = []
    caches = {}
    if isinstance(legacy, dict) and legacy.get('url'):
        calendars.append({'id': 'work', 'name': 'Work calendar', 'category': 'Work',
                          'url': secure_url(str(legacy['url']).strip())})
        if isinstance(legacy_cache, dict):
            caches['work'] = legacy_cache
    config = {'version': 1, 'calendars': calendars}
    if calendars:
        write('cache.json', caches)
        write('config.json', config)
    return config, caches


def validate_calendar(calendar):
    if not isinstance(calendar, dict):
        raise ValueError('Invalid calendar settings')
    identity = str(calendar.get('id', '')).strip()
    name = str(calendar.get('name', '')).strip()
    category = str(calendar.get('category', '')).strip()
    if not re.fullmatch(r'[a-z0-9][a-z0-9-]{0,63}', identity):
        raise ValueError('Invalid calendar ID')
    if not name or len(name) > 64 or any(ord(char) < 32 for char in name):
        raise ValueError('Enter a calendar name up to 64 characters')
    if not category or len(category) > 48 or any(ord(char) < 32 for char in category):
        raise ValueError('Enter a category up to 48 characters')
    return {'id': identity, 'name': name, 'category': category}


class DescriptionHTML(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts, self.links = [], []
        self.hidden = 0

    def handle_starttag(self, tag, attrs):
        if tag in ('script', 'style'):
            self.hidden += 1
        if self.hidden:
            return
        if tag in ('br', 'p', 'div', 'li', 'tr'):
            self.parts.append("\n")
        if tag == 'a':
            self.links.extend(value for name, value in attrs if name == 'href' and value)

    def handle_endtag(self, tag):
        if tag in ('script', 'style'):
            self.hidden = max(0, self.hidden - 1)
        if not self.hidden and tag in ('p', 'div', 'li', 'tr'):
            self.parts.append("\n")

    def handle_data(self, data):
        if not self.hidden:
            self.parts.append(data)


def details(event):
    description = str(event.get('DESCRIPTION', '')).strip()
    location = str(event.get('LOCATION', '')).strip()
    rich = DescriptionHTML()
    rich.feed(str(event.get('X-ALT-DESC', '')))
    # Some Exchange feeds put HTML in DESCRIPTION rather than X-ALT-DESC.
    if re.search(r'<(?:html|body|div|p|br|a)\b', description, re.I):
        plain = DescriptionHTML()
        plain.feed(description)
        description = ''.join(plain.parts).strip()
        rich.links.extend(plain.links)
    if not description:
        description = ''.join(rich.parts).strip()
    candidates = [str(event.get('URL', ''))] + rich.links
    candidates.extend(re.findall(r"https?://[^\s<>\"']+", description + '\n' + location))
    links = []
    for value in candidates:
        url = html.unescape(value).strip().rstrip('.,;!')
        while url.endswith(')') and url.count(')') > url.count('('):
            url = url[:-1]
        while url.endswith(']') and url.count(']') > url.count('['):
            url = url[:-1]
        try:
            parsed = urllib.parse.urlsplit(url)
            valid = parsed.scheme.lower() in ('https', 'http') and parsed.hostname and not parsed.username and not parsed.password
        except ValueError:
            valid = False
        if valid and url not in links:
            links.append(url)
    return {'description': description, 'location': location, 'links': links}


def expand(payload, begin, finish, calendar_id='work'):
    from icalendar import Calendar
    import recurring_ical_events
    calendar = Calendar.from_ical(payload)
    # Floating timestamps use the machine's local timezone; TZID/UTC retain theirs.
    def local(value):
        if isinstance(value, dt.datetime):
            return value.astimezone()
        return dt.datetime.combine(value, dt.time()).astimezone()
    result = []
    for event in recurring_ical_events.of(calendar).between(begin, finish):
        if str(event.get('STATUS', '')).upper() == 'CANCELLED':
            continue
        start = event.decoded('DTSTART')
        end = event.decoded('DTEND', None)
        if end is None:
            end = start + event.decoded('DURATION', dt.timedelta(days=1) if not isinstance(start, dt.datetime) else dt.timedelta())
        all_day = not isinstance(start, dt.datetime)
        start, end = local(start), local(end)
        if end <= start:
            end = start + dt.timedelta(minutes=30)
        identity = str(event.get('UID', '')) + start.isoformat()
        result.append({'id': calendar_id + '-' + hashlib.sha256(identity.encode()).hexdigest()[:24],
                       'title': str(event.get('SUMMARY', 'Busy')), 'startAt': start.isoformat(),
                       'endAt': end.isoformat(), 'allDay': all_day, **details(event)})
    return result


def sync(url, calendar_id='work'):
    secure_url(url)
    opener = urllib.request.build_opener(HTTPSRedirect())
    with opener.open(urllib.request.Request(url, headers={'Accept': 'text/calendar'}), timeout=30) as response:
        payload = response.read(10 * 1024 * 1024 + 1)
    if len(payload) > 10 * 1024 * 1024 or b'BEGIN:VCALENDAR' not in payload:
        raise ValueError('The link did not return an ICS calendar (or the calendar is too large).')
    today = dt.datetime.now().astimezone().date()
    begin = dt.datetime.combine(today - dt.timedelta(days=90), dt.time())
    finish = dt.datetime.combine(today + dt.timedelta(days=366), dt.time())
    return {'events': expand(payload, begin, finish, calendar_id),
            'updatedAt': dt.datetime.now().astimezone().isoformat(),
            'rangeStart': begin.date().isoformat(), 'rangeEnd': finish.date().isoformat()}


def result_payload(config, cache, error=''):
    calendars = []
    events = []
    for raw in config.get('calendars', []):
        try:
            calendar = validate_calendar(raw)
        except ValueError:
            continue
        saved = cache.get(calendar['id'], {})
        saved = saved if isinstance(saved, dict) else {}
        saved_events = saved.get('events', [])
        if not isinstance(saved_events, list):
            saved_events = []
        key = category_key(calendar['category'])
        events.extend(dict(event, calendarId=calendar['id'], calendarName=calendar['name'],
                           category=calendar['category'], categoryKey=key, source='calendar',
                           readOnly=True)
                      for event in saved_events if isinstance(event, dict))
        calendars.append({
            **calendar,
            'categoryKey': key,
            'configured': bool(raw.get('url')),
            'eventCount': len(saved_events),
            'updatedAt': saved.get('updatedAt', ''),
            'rangeStart': saved.get('rangeStart', ''),
            'rangeEnd': saved.get('rangeEnd', ''),
            'error': saved.get('error', '')
        })
    return {'calendars': calendars, 'events': events, 'error': error}


def perform(action, payload):
    if action == 'connect':
        payload = {'id': 'work', 'name': 'Work calendar', 'category': 'Work',
                   'url': payload.get('url', '')}
        action = 'save'
    elif action == 'disconnect':
        payload = {'id': 'work'}
        action = 'delete'
    config, cache = load_state()
    config = {'version': 1, 'calendars': list(config.get('calendars', []))}
    cache = dict(cache)
    error = ''

    if action == 'save':
        submitted = validate_calendar(payload)
        index = next((i for i, item in enumerate(config['calendars'])
                      if item.get('id') == submitted['id']), -1)
        existing = config['calendars'][index] if index >= 0 else None
        new_url = str(payload.get('url', '')).strip()
        if existing is not None and not new_url:
            config['calendars'][index] = {**submitted, 'url': existing.get('url', '')}
            write('config.json', config)
        elif not new_url:
            raise ValueError('Paste an HTTPS ICS subscription link')
        else:
            url = secure_url(new_url)
            if existing is None and len(config['calendars']) >= 32:
                raise ValueError('A maximum of 32 calendars can be connected')
            updated = {**submitted, 'url': url}
            new_cache = sync(url, submitted['id'])
            if index >= 0:
                config['calendars'][index] = updated
            else:
                config['calendars'].append(updated)
            cache[submitted['id']] = new_cache
            write('cache.json', cache)
            write('config.json', config)

    elif action == 'delete':
        identity = str(payload.get('id', ''))
        config['calendars'] = [item for item in config['calendars'] if item.get('id') != identity]
        cache.pop(identity, None)
        write('cache.json', cache)
        write('config.json', config)

    elif action == 'sync':
        only_id = str(payload.get('id', ''))
        for calendar in config['calendars']:
            if only_id and calendar.get('id') != only_id:
                continue
            try:
                cache[calendar['id']] = sync(calendar['url'], calendar['id'])
            except ModuleNotFoundError:
                cache.setdefault(calendar['id'], {})['error'] = (
                    'Install python-icalendar and python-recurring-ical-events; see the calendar README.')
            except Exception:
                previous = cache.setdefault(calendar['id'], {})
                previous['error'] = (
                    'Calendar could not be refreshed. Check the link and network. Previous events were kept.')
        write('cache.json', cache)

    elif action != 'load':
        raise ValueError('Unknown calendar action')

    return result_payload(config, cache, error)


def main():
    action = sys.argv[1] if len(sys.argv) > 1 else 'load'
    try:
        raw = sys.stdin.read() if action in ('save', 'connect', 'delete', 'disconnect', 'sync') and not sys.stdin.isatty() else ''
        payload = json.loads(raw) if raw.strip() else {}
        if not isinstance(payload, dict):
            payload = {}
        result = perform(action, payload)
    except Exception:
        # Never expose subscription URLs, access tokens, server responses or meeting details.
        try:
            config, cache = load_state()
            result = result_payload(config, cache, 'Calendar settings could not be saved. Check the link and try again.')
        except Exception:
            result = {'calendars': [], 'events': [],
                      'error': 'Could not read calendar settings. Files were left unchanged.'}
        if action == 'save':
            result['error'] = 'Calendar could not be connected. Check the HTTPS ICS link and try again.'
        print(json.dumps(result, ensure_ascii=False))
        return
    print(json.dumps(result, ensure_ascii=False))


if __name__ == '__main__':
    main()
