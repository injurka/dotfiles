import datetime as dt
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('work_calendar', Path(__file__).parents[1] / 'home/.config/quickshell/ii/scripts/calendar/work-calendar.py')
calendar = importlib.util.module_from_spec(spec)
spec.loader.exec_module(calendar)

ICS = b'''BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Tests//EN
BEGIN:VEVENT
UID:weekly
DTSTART;TZID=Europe/Moscow:20261019T100000
DTEND;TZID=Europe/Moscow:20261019T110000
RRULE:FREQ=DAILY;COUNT=4
EXDATE;TZID=Europe/Moscow:20261020T100000
SUMMARY:Team meeting
END:VEVENT
BEGIN:VEVENT
UID:weekly
RECURRENCE-ID;TZID=Europe/Moscow:20261021T100000
DTSTART;TZID=Europe/Moscow:20261021T120000
DTEND;TZID=Europe/Moscow:20261021T130000
SUMMARY:Moved meeting
END:VEVENT
BEGIN:VEVENT
UID:cancelled
DTSTART:20261019T090000Z
DTEND:20261019T100000Z
STATUS:CANCELLED
SUMMARY:Cancelled
END:VEVENT
BEGIN:VEVENT
UID:day
DTSTART;VALUE=DATE:20261019
DTEND;VALUE=DATE:20261021
SUMMARY:All day
END:VEVENT
END:VCALENDAR
'''

class CalendarTests(unittest.TestCase):
    def test_recurrence_and_timezone(self):
        events = calendar.expand(ICS, dt.datetime(2026,10,18), dt.datetime(2026,10,24))
        self.assertEqual(len(events), 4)
        self.assertFalse(any(e['title'] == 'Cancelled' for e in events))
        meetings = [e for e in events if not e['allDay']]
        self.assertEqual([dt.datetime.fromisoformat(e['startAt']).day for e in meetings], [19,21,22])
        moved = next(e for e in events if e['title'] == 'Moved meeting')
        self.assertEqual(dt.datetime.fromisoformat(moved['startAt']).astimezone(dt.timezone.utc).hour, 9)
        self.assertEqual(len({e['id'] for e in events}), 4)
    def test_description_and_links(self):
        from icalendar import Calendar
        payload = b'''BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:details
DTSTART:20261019T090000Z
DTEND:20261019T100000Z
SUMMARY:Call
DESCRIPTION:Join https://meet.example.org/room?id=1&key=2\\nAgenda
LOCATION:https://meet.example.org/room?id=1&key=2
URL:https://example.org/event
X-ALT-DESC;FMTTYPE=text/html:<p>Agenda</p><a href="https://teams.example.org/join?a=1&amp;b=2">Join</a>
END:VEVENT
END:VCALENDAR
'''
        event = Calendar.from_ical(payload).walk('VEVENT')[0]
        result = calendar.details(event)
        self.assertIn('Agenda', result['description'])
        self.assertEqual(result['location'], 'https://meet.example.org/room?id=1&key=2')
        self.assertEqual(result['links'], ['https://example.org/event', 'https://teams.example.org/join?a=1&b=2', 'https://meet.example.org/room?id=1&key=2'])
        expanded = calendar.expand(payload, dt.datetime(2026,10,18), dt.datetime(2026,10,20))[0]
        self.assertEqual(expanded['links'], result['links'])

    def test_html_only_and_unsafe_links(self):
        result = calendar.details({'X-ALT-DESC': '<p>Hello</p><script>hidden</script><a href="javascript:alert(1)">bad</a><a href="https://meet.example.org/call?a=1&amp;b=2">Join</a>', 'URL':'file:///tmp/no'})
        self.assertIn('Hello', result['description'])
        self.assertNotIn('hidden', result['description'])
        self.assertNotIn('<', result['description'])
        self.assertEqual(result['links'], ['https://meet.example.org/call?a=1&b=2'])
        result = calendar.details({'DESCRIPTION': '<div>Call <a href="https://meet.example.org">here</a></div>'})
        self.assertEqual(result['description'], 'Call here')
        self.assertEqual(result['links'], ['https://meet.example.org'])

    def test_https(self):
        for url in ['http://example.com/feed.ics', 'https://user:password@example.com/feed.ics', 'file:///tmp/feed.ics']:
            with self.assertRaises(ValueError): calendar.secure_url(url)
    def test_private_atomic_storage(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(calendar, 'STATE', Path(folder)):
            calendar.write('config.json', {'url':'https://example.com/secret'})
            self.assertEqual((Path(folder)/'config.json').stat().st_mode & 0o777, 0o600)
            self.assertEqual(calendar.read('config.json', {})['url'], 'https://example.com/secret')
    def test_failed_sync_preserves_cache_and_hides_url(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(calendar, 'STATE', Path(folder)):
            calendar.write('config.json', {'url':'https://example.com/secret'})
            calendar.write('cache.json', {'events':[{'title':'Saved meeting'}]})
            with patch.object(calendar, 'sync', side_effect=OSError('https://example.com/secret')), patch('sys.argv', ['calendar','sync']), patch('builtins.print') as output:
                calendar.main()
                response = output.call_args.args[0]
            self.assertNotIn('secret', response)
            self.assertIn('Saved meeting', response)
            self.assertIn('Previous events were kept', response)

if __name__ == '__main__': unittest.main()
