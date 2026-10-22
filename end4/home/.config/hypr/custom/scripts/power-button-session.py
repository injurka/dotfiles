#!/usr/bin/env python3
"""Open the end-4 session menu for ACPI power-button events."""

import glob
import os
import struct
import subprocess
import time


POWER_BUTTON_GLOB = "/dev/input/by-path/platform-PNP0C0C*:00-event"
EVENT = struct.Struct("@llHHi")
EV_KEY = 1
KEY_POWER = 116
qs_config = os.environ.get("qsConfig") or "ii"


def watch_device(path):
    try:
        fd = os.open(path, os.O_RDONLY | os.O_CLOEXEC)
    except OSError:
        return False

    try:
        pending = b""
        while True:
            chunk = os.read(fd, EVENT.size * 32)
            if not chunk:
                return False

            pending += chunk
            complete_size = len(pending) - len(pending) % EVENT.size
            for offset in range(0, complete_size, EVENT.size):
                _, _, event_type, code, value = EVENT.unpack_from(pending, offset)
                if event_type == EV_KEY and code == KEY_POWER and value == 1:
                    subprocess.Popen(
                        ["qs", "-c", qs_config, "ipc", "call", "session", "open"],
                        stdin=subprocess.DEVNULL,
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                        close_fds=True,
                    )
            pending = pending[complete_size:]
    except OSError:
        return False
    finally:
        os.close(fd)


while True:
    devices = sorted(glob.glob(POWER_BUTTON_GLOB))
    if not devices:
        time.sleep(2)
        continue

    if not watch_device(devices[0]):
        time.sleep(1)
