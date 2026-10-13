#!/usr/bin/env python3
"""Print a privacy-conscious hardware profile for AI-assisted end-4 setup."""
from __future__ import annotations

import json
import os
import platform
import re
import shutil
import subprocess
from pathlib import Path
from typing import Any


def read_text(path: Path) -> str:
    try:
        return path.read_text(errors="replace").strip()
    except OSError:
        return ""


def run(command: list[str], timeout: float = 3.0) -> str:
    try:
        result = subprocess.run(command, check=True, capture_output=True, text=True, timeout=timeout)
        return result.stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def parse_os_release() -> dict[str, str]:
    values: dict[str, str] = {}
    for line in read_text(Path("/etc/os-release")).splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key] = value.strip().strip('"')
    return values


def edid_physical_size(edid: bytes) -> tuple[int, int] | None:
    # EDID 1.x stores physical size in centimeters in bytes 21 and 22.
    if len(edid) < 23 or edid[:8] != bytes.fromhex("00ffffffffffff00"):
        return None
    width_mm, height_mm = edid[21] * 10, edid[22] * 10
    if width_mm and height_mm:
        return width_mm, height_mm
    return None


def screens_from_hyprland() -> list[dict[str, Any]]:
    raw = run(["hyprctl", "monitors", "-j"])
    if not raw:
        return []
    try:
        monitors = json.loads(raw)
    except json.JSONDecodeError:
        return []
    screens: list[dict[str, Any]] = []
    for monitor in monitors if isinstance(monitors, list) else []:
        name = monitor.get("name")
        width, height = monitor.get("width"), monitor.get("height")
        if not isinstance(name, str) or not isinstance(width, int) or not isinstance(height, int):
            continue
        screen: dict[str, Any] = {
            "name": name,
            "width_px": width,
            "height_px": height,
            "refresh_hz": round(float(monitor["refreshRate"]), 2)
            if isinstance(monitor.get("refreshRate"), (int, float)) else None,
            "scale": float(monitor["scale"])
            if isinstance(monitor.get("scale"), (int, float)) else None,
            "focused": bool(monitor.get("focused", False)),
            "source": "hyprctl",
        }
        for key, output_key in (("physicalWidth", "width_mm"), ("physicalHeight", "height_mm")):
            value = monitor.get(key)
            if isinstance(value, (int, float)) and value > 0:
                screen[output_key] = int(value)
        screens.append(screen)
    return screens


def screens_from_drm() -> list[dict[str, Any]]:
    screens: list[dict[str, Any]] = []
    for connector in sorted(Path("/sys/class/drm").glob("card*-*")):
        if read_text(connector / "status") != "connected":
            continue
        modes = list(dict.fromkeys(line for line in read_text(connector / "modes").splitlines() if re.fullmatch(r"\d+x\d+", line)))
        if not modes:
            continue
        width, height = (int(value) for value in modes[0].split("x", 1))
        name = connector.name.split("-", 1)[1] if "-" in connector.name else connector.name
        screen: dict[str, Any] = {
            "name": name,
            "width_px": width,
            "height_px": height,
            "refresh_hz": None,
            "scale": None,
            "focused": None,
            "supported_modes": modes[:12],
            "source": "drm-sysfs",
        }
        try:
            physical_size = edid_physical_size((connector / "edid").read_bytes())
        except OSError:
            physical_size = None
        if physical_size:
            screen["width_mm"], screen["height_mm"] = physical_size
        screens.append(screen)
    return screens


def get_screens() -> tuple[list[dict[str, Any]], bool]:
    screens = screens_from_hyprland()
    if screens:
        return screens, True
    return screens_from_drm(), False


def get_gpus() -> list[str]:
    devices: list[str] = []
    controller = re.compile(
        r"\b(?:VGA compatible controller|3D controller|Display controller)"
        r"(?:\s+\[[0-9a-fA-F]{4}\])?:\s*(.+)$",
        re.I,
    )
    for line in run(["lspci", "-nn"]).splitlines():
        match = controller.search(line)
        if not match:
            continue
        description = re.sub(r"\s+\[[0-9a-fA-F]{4}:[0-9a-fA-F]{4}\]", "", match.group(1))
        description = re.sub(r"\s+\(rev [^)]+\)$", "", description).strip()
        if description and description not in devices:
            devices.append(description)
    return devices


def battery_present() -> bool:
    for supply in Path("/sys/class/power_supply").glob("*"):
        if read_text(supply / "type").lower() == "battery":
            present = read_text(supply / "present")
            if present in ("", "1"):
                return True
    return False


def touchpad_present() -> bool:
    devices = read_text(Path("/proc/bus/input/devices")).lower()
    return "touchpad" in devices or "trackpad" in devices


def total_memory_gib() -> float | None:
    for line in read_text(Path("/proc/meminfo")).splitlines():
        if line.startswith("MemTotal:"):
            try:
                kib = int(line.split()[1])
                return round(kib / 1024 / 1024, 1)
            except (IndexError, ValueError):
                return None
    return None


def main() -> None:
    os_release = parse_os_release()
    screens, hyprland_running = get_screens()
    battery = battery_present()
    internal_screen = any(re.match(r"^(eDP|DSI|LVDS)", str(screen.get("name", "")), re.I) for screen in screens)
    try:
        free_gib = round(shutil.disk_usage(Path.home()).free / 1024**3, 1)
    except OSError:
        free_gib = None

    profile = {
        "schema_version": 1,
        "system": {
            "distro_id": os_release.get("ID", ""),
            "distro_name": os_release.get("PRETTY_NAME", ""),
            "architecture": platform.machine(),
            "package_managers_available": [
                name for name in ("pacman", "paru", "yay", "apt", "dnf", "zypper")
                if shutil.which(name)
            ],
        },
        "device": {
            "battery_present": battery,
            "internal_screen_detected": internal_screen,
            "laptop_likely": battery or internal_screen,
            "touchpad_detected": touchpad_present(),
        },
        "hardware": {
            "cpu": next(
                (line.split(":", 1)[1].strip() for line in read_text(Path("/proc/cpuinfo")).splitlines()
                 if line.lower().startswith("model name")),
                platform.processor() or None,
            ),
            "memory_gib": total_memory_gib(),
            "gpus": get_gpus(),
            "screens": screens,
        },
        "session": {
            "wayland_session": bool(os.environ.get("WAYLAND_DISPLAY")),
            "hyprland_running": hyprland_running,
        },
        "storage": {"home_free_gib": free_gib},
    }
    print(json.dumps(profile, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
