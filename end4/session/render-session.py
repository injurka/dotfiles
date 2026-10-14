#!/usr/bin/env python3
"""Render the user-specific Exec path into the portable Wayland session entry."""
from pathlib import Path
import sys

source, launcher, destination = map(Path, sys.argv[1:])
text = source.read_text()
marker = "@END4_LAUNCHER@"
if text.count(marker) != 1:
    raise SystemExit("Invalid portable session template.")
value = str(launcher).replace("%", "%%").replace("\\", "\\\\").replace('"', '\\"')
quoted = '"' + value + '"'
destination.write_text(text.replace(marker, quoted))
