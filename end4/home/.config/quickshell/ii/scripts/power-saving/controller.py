#!/usr/bin/env python3
"""Reversible laptop power saving. No root, shell interpolation or config reloads."""
import fcntl
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

DEFAULTS = dict(profile=True, dim=True, brightness=35, refresh=False, hz=60,
                animations=True, blur=True, autoBattery=False, restoreAC=False)
CONFIG = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config')) / 'illogical-impulse/power-saving.json'
STATE = Path(os.environ.get('XDG_STATE_HOME', Path.home() / '.local/state')) / 'end4-power-saving/state.json'
SESSION = os.environ.get('HYPRLAND_INSTANCE_SIGNATURE', '')


def run(*args):
    result = subprocess.run(args, capture_output=True, text=True, timeout=8)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip() or f'{args[0]} failed')
    return result.stdout.strip()


def read(path, default):
    if not path.exists():
        return default.copy()
    return json.loads(path.read_text())


def save(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix('.tmp')
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
    tmp.chmod(0o600)
    tmp.replace(path)


def battery():
    devices = []
    online = []
    for p in Path('/sys/class/power_supply').glob('*'):
        try:
            kind = (p / 'type').read_text().strip()
            if kind == 'Battery' and (not (p / 'scope').exists() or (p / 'scope').read_text().strip() != 'Device'):
                devices.append((p / 'status').read_text().strip())
            elif (p / 'online').exists():
                online.append((p / 'online').read_text().strip() == '1')
        except OSError:
            continue
    return bool(devices), any(online) if online else any(x in ('Charging', 'Full') for x in devices)


def monitors():
    return json.loads(run('hyprctl', '-j', 'monitors'))


def backlight():
    if not shutil.which('brightnessctl'):
        return None
    for p in sorted(Path('/sys/class/backlight').glob('*')):
        try:
            if int((p / 'max_brightness').read_text()) > 0:
                return p.name
        except OSError:
            pass
    return None


def get_value(kind, target):
    if kind == 'profile':
        return run('powerprofilesctl', 'get')
    if kind == 'brightness':
        return int(run('brightnessctl', '-d', target, 'get'))
    if kind == 'option':
        value = json.loads(run('hyprctl', '-j', 'getoption', target))
        if 'bool' not in value and 'int' not in value:
            raise RuntimeError(f'Cannot read {target}')
        return bool(value.get('bool', value.get('int')))
    for m in monitors():
        if m['name'] == target:
            return f"{m['width']}x{m['height']}@{m['refreshRate']:.3f}"
    raise RuntimeError(f'Display {target} is disconnected')


def set_value(kind, target, value):
    if kind == 'profile':
        run('powerprofilesctl', 'set', value)
    elif kind == 'brightness':
        run('brightnessctl', '-d', target, 'set', str(value))
    elif kind == 'option':
        # This snapshot uses Lua Hyprland. Only change the requested option.
        nested = 'true' if value else 'false'
        for part in reversed(target.split(':')):
            nested = '{' + part + '=' + nested + '}'
        output = run('hyprctl', 'eval', 'hl.config(' + nested + ')')
        if output and output.lower() != 'ok':
            raise RuntimeError(output)
    else:
        # Lua monitor rules merge supplied fields into an existing named rule.
        # Also retain current geometry for panels using an automatic output rule.
        # https://github.com/hyprwm/Hyprland/blob/main/src/config/lua/bindings/LuaBindingsConfigRules.cpp
        m = next((x for x in monitors() if x['name'] == target), None)
        if not m:
            raise RuntimeError(f'Display {target} is disconnected')
        fields = dict(output=target, mode=value, position=f"{m['x']}x{m['y']}",
                      scale=m['scale'], transform=m.get('transform', 0))
        if 'currentFormat' in m:
            fields['bitdepth'] = 10 if '2101010' in m['currentFormat'] else 8
        args = ','.join(k + '=' + json.dumps(v) for k, v in fields.items())
        output = run('hyprctl', 'eval', 'hl.monitor({' + args + '})')
        if output and output.lower() != 'ok':
            raise RuntimeError(output)


def equal(kind, left, right):
    if kind != 'monitor':
        return left == right
    a, b = left.split('@'), right.split('@')
    return a[0] == b[0] and abs(float(a[1]) - float(b[1])) < 0.5


def verify(kind, target, expected):
    # Monitor modesets are scheduled asynchronously after the IPC reply.
    deadline = time.monotonic() + 3
    while True:
        actual = get_value(kind, target)
        if equal(kind, actual, expected):
            return actual
        if time.monotonic() >= deadline:
            raise RuntimeError(f'{target or kind}: requested value was not applied')
        time.sleep(0.15)


def capabilities():
    caps = dict(profile=False, brightness=False, refresh=False, effects=False)
    if shutil.which('powerprofilesctl'):
        try:
            caps['profile'] = 'power-saver' in run('powerprofilesctl', 'list')
        except (OSError, RuntimeError, subprocess.TimeoutExpired):
            pass
    caps['brightness'] = bool(backlight())
    if SESSION:
        try:
            outputs = monitors()
            caps['effects'] = True
            caps['refresh'] = any(re.match(r'^(eDP|LVDS|DSI)-', m['name']) and m.get('availableModes') for m in outputs)
        except (OSError, RuntimeError, ValueError, subprocess.TimeoutExpired):
            pass
    return caps


class Controller:
    def __init__(self):
        self.config = DEFAULTS | read(CONFIG, {})
        self.state = read(STATE, dict(active=False, changes=[], errors=[], session=SESSION))
        # Never replay saved display/brightness settings into a different login session.
        if self.state.get('session') != SESSION:
            self.state = dict(active=False, changes=[], errors=[], session=SESSION)

    def persist(self):
        save(STATE, self.state)

    def change(self, kind, target, value):
        before = get_value(kind, target)
        if before == value:
            return
        entry = dict(kind=kind, target=target, before=before, applied=value)
        self.state['changes'].append(entry)
        self.persist()  # Recovery journal exists before touching hardware.
        try:
            set_value(kind, target, value)
        except Exception:
            # A failed command that left the value untouched needs no rollback.
            if get_value(kind, target) == before:
                self.state['changes'].remove(entry)
                self.persist()
            raise
        actual = verify(kind, target, value)
        entry['applied'] = actual
        self.persist()

    def enable(self):
        if self.state['active']:
            return
        if not battery()[0]:
            raise RuntimeError('Laptop battery not detected')
        self.state.update(active=True, errors=[], changes=[], session=SESSION)
        self.persist()
        c = self.config
        actions = []
        if c['profile']:
            actions.append(('profile', '', 'power-saver'))
        if c['dim']:
            dev = backlight()
            if dev:
                maximum = int(run('brightnessctl', '-d', dev, 'max'))
                current = get_value('brightness', dev)
                actions.append(('brightness', dev, min(current, max(1, round(maximum * c['brightness'] / 100)))))
            else:
                self.state['errors'].append('Подсветка: brightnessctl или встроенный экран недоступны')
        if c['refresh']:
            try:
                found = False
                for m in monitors():
                    if not re.match(r'^(eDP|LVDS|DSI)-', m['name']):
                        continue
                    found = True
                    modes = []
                    for mode in m.get('availableModes', []):
                        match = re.fullmatch(r'(\d+)x(\d+)@(\d+(?:\.\d+)?)Hz', mode)
                        if match and int(match[1]) == m['width'] and int(match[2]) == m['height']:
                            rate = float(match[3])
                            if rate <= c['hz'] + 0.1 and rate < m['refreshRate'] - 0.5:
                                modes.append(rate)
                    if modes:
                        actions.append(('monitor', m['name'], f"{m['width']}x{m['height']}@{max(modes):.3f}"))
                    elif m['refreshRate'] > c['hz'] + 0.1:
                        self.state['errors'].append(f"{m['name']}: подходящая частота не поддерживается")
                if not found:
                    self.state['errors'].append('Встроенный монитор не найден')
            except Exception as e:
                self.state['errors'].append(f'Частота: {e}')
        for key, option in [('animations', 'animations:enabled'), ('blur', 'decoration:blur:enabled')]:
            if c[key]:
                actions.append(('option', option, False))
        for kind, target, value in actions:
            try:
                self.change(kind, target, value)
            except Exception as e:
                self.state['errors'].append(f'{target or kind}: {e}')
        # An empty/failed plan must not pretend to have enabled power saving.
        self.state['active'] = bool(self.state['changes'])
        if not self.state['changes'] and not self.state['errors']:
            self.state['errors'].append('Параметры уже экономные либо действия не выбраны')
        self.persist()

    def disable(self):
        remaining = []
        self.state['errors'] = []
        for entry in reversed(self.state['changes']):
            try:
                current = get_value(entry['kind'], entry['target'])
                # A later manual edit wins over restoring our original value.
                if equal(entry['kind'], current, entry['applied']):
                    set_value(entry['kind'], entry['target'], entry['before'])
                    verify(entry['kind'], entry['target'], entry['before'])
            except Exception as e:
                remaining.append(entry)
                self.state['errors'].append(f"{entry['target'] or entry['kind']}: {e}")
        self.state.update(changes=list(reversed(remaining)), active=bool(remaining))
        self.persist()

    def tick(self):
        laptop, ac = battery()
        previous = self.state.get('ac')
        self.state['ac'] = ac
        # Transition only: manual override lasts until the next plug/unplug.
        if laptop and previous is not None and previous != ac:
            if not ac and self.config['autoBattery']:
                self.enable()
            elif ac and self.config['restoreAC']:
                self.disable()
        if previous != ac:
            self.persist()

    def status(self):
        return dict(available=battery()[0], active=self.state['active'], config=self.config,
                    capabilities=capabilities(), errors=self.state['errors'])


def main():
    STATE.parent.mkdir(parents=True, exist_ok=True)
    with (STATE.parent / 'lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        controller = Controller()
        action = sys.argv[1] if len(sys.argv) > 1 else 'status'
        try:
            if action == 'toggle':
                controller.disable() if controller.state['active'] else controller.enable()
            elif action == 'tick':
                controller.tick()
            elif action == 'configure':
                patch = json.loads(sys.argv[2])
                for key, value in patch.items():
                    if key not in DEFAULTS:
                        raise ValueError('Unknown setting')
                    if key in ('brightness', 'hz'):
                        low, high = (5, 100) if key == 'brightness' else (30, 240)
                        if type(value) not in (int, float) or not low <= value <= high:
                            raise ValueError('Setting outside supported range')
                    elif type(value) is not bool:
                        raise ValueError('Expected boolean')
                controller.config.update(patch)
                save(CONFIG, controller.config)
            elif action != 'status':
                raise ValueError('Unknown action')
        except Exception as e:
            controller.state['errors'] = [str(e)]
            controller.persist()
        print(json.dumps(controller.status(), ensure_ascii=False))


if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        print(json.dumps(dict(available=False, active=False, errors=[str(e)])))
        sys.exit(1)
