#!/usr/bin/env python3
"""Install or roll back an experimental workaround for injurkapc only."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile

ROOT = Path(__file__).resolve().parent
LEGACY = Path('/etc/systemd/sleep.conf.d/70-suspend-s2idle.conf')
LEGACY_HASH = '9de38bcc5bd0c8649eb332138f0056e8cba9f5f3a8561083ec0596e6b556a6e5'
TARGETS = [Path('/etc/systemd/sleep.conf.d/70-suspend-injurkapc.conf'),
           Path('/etc/tmpfiles.d/70-suspend-injurkapc.conf')]
KNOBS = {'pm_async': '0', 'pm_debug_messages': '1', 'pm_print_times': '1', 'mem_sleep': 'deep'}

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def current(name):
    value = (Path('/sys/power') / name).read_text().strip()
    return next(x[1:-1] for x in value.split() if x.startswith('[')) if name == 'mem_sleep' else value

def atomic(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp = tempfile.mkstemp(dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data)
        os.chmod(temp, 0o644)
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)

def restore(backup, state, check=True):
    if check:
        for entry in state['files']:
            path = Path(entry['path'])
            if (digest(path) if path.exists() else None) != entry['installed_hash']:
                raise RuntimeError(f'File changed since installation: {path}')
    for entry in state['files']:
        path = Path(entry['path'])
        if entry['backup']:
            atomic(path, (backup / entry['backup']).read_bytes())
        else:
            path.unlink(missing_ok=True)
    for name, value in state['knobs'].items():
        (Path('/sys/power') / name).write_text(value + '\n')

def main():
    if os.geteuid() != 0:
        raise RuntimeError('Run with pkexec or sudo')
    if len(sys.argv) == 3 and sys.argv[1] == '--rollback':
        backup = Path(sys.argv[2])
        restore(backup, json.loads((backup / 'state.json').read_text()))
        print('Restored configuration and runtime power settings')
        return
    if len(sys.argv) != 1:
        raise RuntimeError('Usage: install-suspend-workaround.py [--rollback BACKUP]')
    if Path('/sys/class/dmi/id/board_name').read_text().strip() != 'X870E AORUS PRO X3D':
        raise RuntimeError('This workaround is scoped to X870E AORUS PRO X3D')
    if not LEGACY.exists() or digest(LEGACY) != LEGACY_HASH:
        raise RuntimeError('Legacy sleep configuration differs from inspected baseline')
    if any(path.exists() for path in TARGETS):
        raise RuntimeError('A target already exists; inspect before merging')
    payloads = {str(path): (ROOT / str(path).lstrip('/')).read_bytes() for path in TARGETS}
    backup = Path('/var/lib/dotfiles-suspend-workaround') / datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    backup.mkdir(parents=True, mode=0o700)
    state = {'source': str(ROOT), 'dirty': True, 'files': [], 'knobs': {name: current(name) for name in KNOBS}}
    for i, path in enumerate([LEGACY] + TARGETS):
        filename = str(i) if path.exists() else None
        if filename:
            shutil.copy2(path, backup / filename)
        data = payloads.get(str(path))
        state['files'].append({'path': str(path), 'backup': filename,
            'baseline_hash': digest(path) if path.exists() else None,
            'installed_hash': hashlib.sha256(data).hexdigest() if data is not None else None})
    (backup / 'state.json').write_text(json.dumps(state, indent=2) + '\n')
    if digest(LEGACY) != LEGACY_HASH or any(path.exists() for path in TARGETS):
        raise RuntimeError('Configuration changed during preparation')
    try:
        for path in TARGETS:
            atomic(path, payloads[str(path)])
        LEGACY.unlink()
        for name, value in KNOBS.items():
            (Path('/sys/power') / name).write_text(value + '\n')
            if current(name) != value:
                raise RuntimeError(f'Runtime setting was not accepted: {name}')
    except Exception:
        restore(backup, state, check=False)
        raise
    print(f'BACKUP={backup}')
    for name in KNOBS:
        print(f'{name}={current(name)}')
    print('Sleep configuration applies on the next suspend. No reboot required.')
    print(f'Rollback: sudo python3 {Path(__file__).resolve()} --rollback {backup}')

if __name__ == '__main__':
    main()
