#!/usr/bin/env python3
"""Read optional Linux hardware metrics without probing or configuring devices."""
import json
import math
from pathlib import Path
import shutil


def read(path):
    try:
        return Path(path).read_text().strip()
    except (OSError, ValueError):
        return ""


def number(path, scale=1):
    try:
        value = float(read(path)) / scale
        return value if math.isfinite(value) else None
    except ValueError:
        return None


def row(rows, label, value, unit, icon="device_thermostat", digits=0):
    if value is not None:
        rows.append({"label": label, "value": f"{value:.{digits}f}{unit}", "icon": icon})


def collect(sys=Path('/sys')):
    groups = {key: [] for key in ('cpu', 'gpu', 'board', 'storage')}
    for hw in sorted((sys / 'class/hwmon').glob('hwmon*')):
        name = read(hw / 'name')
        if name in ('k10temp', 'coretemp', 'zenpower'):
            # Prefer package/control temperature over dozens of per-core readings.
            temps = list(hw.glob('temp*_input'))
            preferred = [p for p in temps if read(p.with_name(p.name.replace('_input', '_label'))) in ('Tctl', 'Package id 0', 'Tdie')]
            selected = preferred[:1] or temps[:1]
            for p in selected:
                row(groups['cpu'], 'Temperature:', number(p, 1000), ' °C')
        elif name in ('amdgpu', 'nouveau', 'i915', 'xe'):
            for p in sorted(hw.glob('temp*_input')):
                label = read(p.with_name(p.name.replace('_input', '_label')))
                title = {'edge': 'Temperature:', 'junction': 'Hotspot:', 'mem': 'Memory temp:'}.get(label, (label or p.stem.replace('_input', '')) + ':')
                row(groups['gpu'], title, number(p, 1000), ' °C')
            power = number(hw / 'power1_average', 1e6)
            if power is None:
                power = number(hw / 'power1_input', 1e6)
            row(groups['gpu'], 'Power:', power, ' W', 'bolt')
            for p in sorted(hw.glob('fan*_input')):
                row(groups['gpu'], 'Fan:', number(p), ' RPM', 'mode_fan')
        elif name == 'nvme':
            # Composite is the drive temperature; internal sensors are not interchangeable.
            p = hw / 'temp1_input'
            address = hw.resolve().parent.name
            row(groups['storage'], f'NVMe {address}:', number(p, 1000), ' °C')
        elif name in ('gigabyte_wmi', 'nct6775', 'nct6798', 'it87') or name.startswith(('nct67', 'nct68', 'it86', 'it87')):
            for p in sorted(hw.glob('temp*_input')):
                label = read(p.with_name(p.name.replace('_input', '_label')))
                # Firmware often gives no location names. Keep sensor numbers honest.
                label = label or 'Sensor ' + p.stem.removeprefix('temp').removesuffix('_input')
                row(groups['board'], label + ':', number(p, 1000), ' °C')
            for p in sorted(hw.glob('fan*_input')):
                row(groups['board'], p.stem.replace('_input', '') + ':', number(p), ' RPM', 'mode_fan')
    for card in sorted((sys / 'class/drm').glob('card[0-9]*')):
        if '-' in card.name:
            continue
        device = card / 'device'
        row(groups['gpu'], 'Load:', number(device / 'gpu_busy_percent'), '%', 'speed')
        used = number(device / 'mem_info_vram_used', 1024**3)
        total = number(device / 'mem_info_vram_total', 1024**3)
        if used is not None and total is not None:
            groups['gpu'].append({'label': 'VRAM:', 'value': f'{used:.1f} / {total:.1f} GB', 'icon': 'memory'})
    frequencies = [number(p, 1e6) for p in (sys / 'devices/system/cpu').glob('cpu[0-9]*/cpufreq/scaling_cur_freq')]
    frequencies = [v for v in frequencies if v is not None]
    if frequencies:
        row(groups['cpu'], 'Frequency:', sum(frequencies) / len(frequencies), ' GHz', 'speed', 2)
    disk = shutil.disk_usage('/')
    groups['storage'].append({'label': '/ free:', 'value': f'{disk.free / 1024**3:.0f} / {disk.total / 1024**3:.0f} GB', 'icon': 'hard_drive'})
    return groups


if __name__ == '__main__':
    print(json.dumps(collect()))
