#!/usr/bin/env bash
set -euo pipefail
calendar_python="${XDG_DATA_HOME:-$HOME/.local/share}/ii-calendar/venv/bin/python"
if [[ ! -x "$calendar_python" ]]; then
    calendar_python=python3
fi
exec "$calendar_python" "$(dirname -- "$0")/work-calendar.py" "$@"
