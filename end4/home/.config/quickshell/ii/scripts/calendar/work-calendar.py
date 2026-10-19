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

STATE = Path(os.environ.get('XDG_STATE_HOME', str(Path.home() / '.local/state'))) / 'ii/work-calendar'


def read(name, default):
    try:
        return json.loads((STATE / name).read_text())
    except FileNotFoundError:
        return default


def write(name, value):
    STATE.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, temporary = tempfile.mkstemp(dir=STATE)
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump(value, stream, ensure_ascii=False)
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


def expand(payload, begin, finish):
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
        result.append({'id': 'work-' + hashlib.sha256(identity.encode()).hexdigest()[:24],
                       'title': str(event.get('SUMMARY', 'Busy')), 'startAt': start.isoformat(),
                       'endAt': end.isoformat(), 'allDay': all_day, **details(event)})
    return result


def sync(url):
    secure_url(url)
    opener = urllib.request.build_opener(HTTPSRedirect())
    with opener.open(urllib.request.Request(url, headers={'Accept': 'text/calendar'}), timeout=30) as response:
        payload = response.read(10 * 1024 * 1024 + 1)
    if len(payload) > 10 * 1024 * 1024 or b'BEGIN:VCALENDAR' not in payload:
        raise ValueError('The link did not return an ICS calendar (or the calendar is too large).')
    today = dt.datetime.now().astimezone().date()
    begin = dt.datetime.combine(today - dt.timedelta(days=90), dt.time())
    finish = dt.datetime.combine(today + dt.timedelta(days=366), dt.time())
    return {'events': expand(payload, begin, finish), 'updatedAt': dt.datetime.now().astimezone().isoformat(),
            'rangeStart': begin.date().isoformat(), 'rangeEnd': finish.date().isoformat()}


def main():
    action = sys.argv[1] if len(sys.argv) > 1 else 'load'
    try:
        config = read('config.json', {})
        cache = read('cache.json', {})
    except Exception:
        print(json.dumps({'error': 'Could not read work calendar settings. Files were left unchanged.'}))
        return
    error = ''
    try:
        if action == 'disconnect':
            for name in ('config.json', 'cache.json'):
                (STATE / name).unlink(missing_ok=True)
            config, cache = {}, {}
        elif action in ('connect', 'sync'):
            url = json.load(sys.stdin)['url'].strip() if action == 'connect' else config.get('url', '')
            if url:
                new_cache = sync(url)
                write('cache.json', new_cache)
                write('config.json', {'url': url})
                config, cache = {'url': url}, new_cache
        elif action != 'load':
            raise ValueError('Unknown calendar action')
    except ModuleNotFoundError:
        error = 'Install python-icalendar and python-recurring-ical-events; see the calendar README.'
    except ValueError as exception:
        error = str(exception) if 'ICS' in str(exception) or 'HTTPS' in str(exception) else 'Could not parse the ICS calendar.'
    except Exception:
        # Never expose the subscription token, server response or meeting details in errors/logs.
        error = 'Work calendar could not be refreshed. Check the link and network. Previous events were kept.'
    print(json.dumps(dict(cache, configured=bool(config.get('url')), error=error), ensure_ascii=False))


if __name__ == '__main__':
    main()
