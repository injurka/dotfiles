#!/usr/bin/env python3
"""VPN control via NetworkManager and the clients' public tray menus. No secrets."""
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import time
from gi.repository import Gio, GLib

NAMES = ['Prosebya', 'AmneziaVPN', 'Browsec']
CONFIG = Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home() / '.config'))) / 'illogical-impulse/vpn.json'
BUS = Gio.bus_get_sync(Gio.BusType.SESSION, None)

def call(dest, path, interface, method, signature, args):
    return BUS.call_sync(dest, path, interface, method, GLib.Variant(signature, args), None, Gio.DBusCallFlags.NONE, 2500, None).unpack()

def order():
    try:
        saved = json.loads(CONFIG.read_text())['priority']
        return list(dict.fromkeys([n for n in saved if n in NAMES] + NAMES))
    except (OSError, ValueError, KeyError, TypeError):
        return NAMES.copy()

def nm(active=False):
    args = ['nmcli', '-t', '--escape', 'no', '-f', 'UUID,NAME,TYPE', 'connection', 'show']
    if active:
        args.append('--active')
    out = subprocess.run(args, capture_output=True, text=True, timeout=5)
    if out.returncode:
        raise RuntimeError('NetworkManager недоступен')
    return [s.split(':', 2) for s in out.stdout.splitlines()]

def trays():
    result = {}
    entries = call('org.kde.StatusNotifierWatcher', '/StatusNotifierWatcher', 'org.freedesktop.DBus.Properties', 'Get', '(ss)', ('org.kde.StatusNotifierWatcher', 'RegisteredStatusNotifierItems'))[0]
    for entry in entries:
        dest, path = entry.split('/', 1)
        try:
            props = call(dest, '/' + path, 'org.freedesktop.DBus.Properties', 'GetAll', '(s)', ('org.kde.StatusNotifierItem',))[0]
            ident = props.get('Id', '').lower()
            name = 'AmneziaVPN' if ident == 'amneziavpn' else 'Browsec' if ident.startswith('browsec-desktop') else None
            if not name:
                continue
            menu = props['Menu']
            call(dest, menu, 'com.canonical.dbusmenu', 'AboutToShow', '(i)', (0,))
            layout = call(dest, menu, 'com.canonical.dbusmenu', 'GetLayout', '(iias)', (0, 3, ['label', 'enabled', 'visible']))[1]
            actions = {}
            def walk(node):
                ident, properties, children = node
                label = properties.get('label', '').replace('&', '').strip().lower()
                if properties.get('enabled', True) and properties.get('visible', True):
                    if label in ('connect', 'start vpn', 'подключиться', 'подключить'):
                        actions['connect'] = ident
                    elif label in ('disconnect', 'stop vpn', 'отключиться', 'отключить'):
                        actions['disconnect'] = ident
                for child in children:
                    walk(child)
            walk(layout)
            result[name] = (dest, menu, actions)
        except GLib.Error:
            continue
    return result

def state():
    clients = trays()
    active = [name for name, (_, _, actions) in clients.items() if 'disconnect' in actions]
    profiles = nm()
    ids = {row[0] for row in nm(True)}
    profile = next((r for r in profiles if r[1:] == ['Prosebya', 'vpn']), None)
    if profile and profile[0] in ids:
        active.insert(0, 'Prosebya')
    return clients, profile, active

def notify(message):
    subprocess.run(['notify-send', 'VPN', message], check=False)

def ensure_available(name, action, clients, profile):
    if name not in NAMES:
        raise ValueError('Неизвестный VPN')
    if name == 'Prosebya':
        if not profile:
            raise RuntimeError('Профиль Prosebya не найден в NetworkManager')
    elif name not in clients or action not in clients[name][2]:
        launch(name)
        raise RuntimeError(f'Открыт {name}. Дождитесь появления меню в трее и выберите сервер в приложении, затем нажмите VPN снова.')


def perform(name, action):
    clients, profile, active = state()
    ensure_available(name, action, clients, profile)
    if name == 'Prosebya':
        result = subprocess.run(['nmcli', '--wait', '25', 'connection', 'down' if action == 'disconnect' else 'up', 'uuid', profile[0]], capture_output=True, text=True, timeout=30)
        if result.returncode:
            raise RuntimeError('NetworkManager не смог выполнить действие. Проверьте профиль Prosebya в настройках сети.')
    else:
        dest, menu, actions = clients[name]
        call(dest, menu, 'com.canonical.dbusmenu', 'Event', '(isvu)', (actions[action], 'clicked', GLib.Variant('i', 0), 0))
    for _ in range(12):
        time.sleep(1)
        _, _, current = state()
        if (name in current) == (action == 'connect'):
            return
    raise RuntimeError(f'{name}: состояние ещё не подтверждено. Проверьте окно клиента.')


def toggle(name=None):
    clients, profile, active = state()
    if name is None:
        perform(active[0] if active else order()[0], 'disconnect' if active else 'connect')
        return
    # Validate the selected client before interrupting an existing connection.
    action = 'disconnect' if name in active else 'connect'
    ensure_available(name, action, clients, profile)
    if action == 'connect':
        for other in active:
            perform(other, 'disconnect')
    perform(name, action)

def launch(name):
    command = {'Prosebya': ['nm-connection-editor'], 'AmneziaVPN': ['AmneziaVPN'], 'Browsec': ['/opt/Browsec/browsec-desktop', '--ozone-platform=x11']}[name]
    subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)

def save_priority(value):
    priority = json.loads(value)
    if not isinstance(priority, list) or len(priority) != len(NAMES) or set(priority) != set(NAMES):
        raise ValueError('Некорректный порядок VPN')
    CONFIG.parent.mkdir(parents=True, exist_ok=True)
    temp = CONFIG.with_suffix('.tmp')
    temp.write_text(json.dumps({'priority': priority}, ensure_ascii=False, indent=2) + '\n')
    temp.replace(CONFIG)

if __name__ == '__main__':
    try:
        mode = sys.argv[1] if len(sys.argv) > 1 else 'status'
        if mode == 'status':
            _, _, active = state()
            print(json.dumps({'active': active, 'preferred': order()[0], 'priority': order(), 'error': ''}))
        elif mode == 'priority':
            print(json.dumps({'priority': order()}))
        elif mode == 'save-priority':
            save_priority(sys.argv[2])
        elif mode == 'launch':
            launch(sys.argv[2])
        elif mode in ('toggle', 'toggle-provider'):
            lock = open(Path(os.environ.get('XDG_RUNTIME_DIR', '/tmp')) / f'end4-vpn-{os.getuid()}.lock', 'w')
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                sys.exit(0)
            toggle(sys.argv[2] if mode == 'toggle-provider' else None)
    except Exception as error:
        if len(sys.argv) < 2 or sys.argv[1] == 'status':
            print(json.dumps({'active': [], 'preferred': order()[0], 'error': str(error)}))
        else:
            notify(str(error))
        sys.exit(1)
