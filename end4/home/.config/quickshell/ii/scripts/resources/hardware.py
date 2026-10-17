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
    groups = {key: [] for key in ('cpu', 'board', 'storage')}
    gpu_groups = {}

    def gpu_for(device, fallback_label):
        key = str(device.resolve())
        if key not in gpu_groups:
            gpu_groups[key] = {'label': fallback_label, 'rows': []}
        return gpu_groups[key]['rows']

    cards = []
    for card in sorted((sys / 'class/drm').glob('card[0-9]*')):
        if '-' in card.name:
            continue
        device = card / 'device'
        cards.append((card, device, 'GPU'))

    if len(cards) > 1:
        # Linux has no universal integrated/discrete flag. Prefer the card with
        # the largest local VRAM; use the sole non-boot adapter as a fallback.
        with_vram = []
        for entry in cards:
            total = number(entry[1] / 'mem_info_vram_total')
            if total is not None and total > 0:
                with_vram.append((total, entry))
        if with_vram:
            selected = max(with_vram, key=lambda item: item[0])[1]
        else:
            non_boot = [entry for entry in cards if read(entry[1] / 'boot_vga') == '0']
            selected = non_boot[0] if len(non_boot) == 1 else cards[0]
        cards = [selected]

    for _, device, label in cards:
        gpu_for(device, label)

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
            device = hw / 'device'
            card_label = next((label for _, card_device, label in cards if device.resolve() == card_device.resolve()), None)
            if card_label is None:
                continue
            gpu_rows = gpu_for(device, card_label)
            for p in sorted(hw.glob('temp*_input')):
                label = read(p.with_name(p.name.replace('_input', '_label')))
                title = {'edge': 'Temperature:', 'junction': 'Hotspot:', 'mem': 'Memory temp:'}.get(label, (label or p.stem.replace('_input', '')) + ':')
                row(gpu_rows, title, number(p, 1000), ' °C')
            power = number(hw / 'power1_average', 1e6)
            if power is None:
                power = number(hw / 'power1_input', 1e6)
            row(gpu_rows, 'Power:', power, ' W', 'bolt')
            for p in sorted(hw.glob('fan*_input')):
                row(gpu_rows, 'Fan:', number(p), ' RPM', 'mode_fan')
        elif name == 'nvme':
            # Composite is the drive temperature; internal sensors are not interchangeable.
            p = hw / 'temp1_input'
            address = hw.resolve().parent.name
            row(groups['storage'], f'NVMe {address}:', number(p, 1000), ' °C')
        elif name in ('gigabyte_wmi', 'nct6775', 'nct6798', 'it87') or name.startswith(('nct67', 'nct68', 'it86', 'it87')):
            for p in sorted(hw.glob('temp*_input')):
                temperature = number(p, 1000)
                # IT87 reports -55 °C for an unconnected thermistor input.
                if name.startswith('it87') and temperature == -55:
                    continue
                label = read(p.with_name(p.name.replace('_input', '_label')))
                # Firmware often gives no location names. Keep sensor numbers honest.
                label = label or 'Sensor ' + p.stem.removeprefix('temp').removesuffix('_input')
                row(groups['board'], label + ':', temperature, ' °C')
            for p in sorted(hw.glob('fan*_input')):
                row(groups['board'], p.stem.replace('_input', '') + ':', number(p), ' RPM', 'mode_fan')
    for card, device, label in cards:
        gpu_rows = gpu_for(device, label)
        row(gpu_rows, 'Load:', number(device / 'gpu_busy_percent'), '%', 'speed')
        used = number(device / 'mem_info_vram_used', 1024**3)
        total = number(device / 'mem_info_vram_total', 1024**3)
        if used is not None and total is not None:
            gpu_rows.append({'label': 'VRAM:', 'value': f'{used:.1f} / {total:.1f} GB', 'icon': 'memory'})
    frequencies = [number(p, 1e6) for p in (sys / 'devices/system/cpu').glob('cpu[0-9]*/cpufreq/scaling_cur_freq')]
    frequencies = [v for v in frequencies if v is not None]
    if frequencies:
        row(groups['cpu'], 'Frequency:', sum(frequencies) / len(frequencies), ' GHz', 'speed', 2)
    disk = shutil.disk_usage('/')
    groups['storage'].append({'label': '/ free:', 'value': f'{disk.free / 1024**3:.0f} / {disk.total / 1024**3:.0f} GB', 'icon': 'hard_drive'})
    groups['gpu'] = list(gpu_groups.values())
    return groups


if __name__ == '__main__':
    print(json.dumps(collect()))
