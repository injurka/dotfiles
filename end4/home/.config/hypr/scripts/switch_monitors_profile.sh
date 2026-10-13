#!/bin/bash

STATE_DIR="$HOME/.config/hypr/.state"
mkdir -p "$STATE_DIR"
COLOR_FILE="$STATE_DIR/color_profile"

[ -f "$COLOR_FILE" ] || echo "sdr" > "$COLOR_FILE"
STATE=$(cat "$COLOR_FILE")

if [ "$STATE" = "sdr" ]; then
    echo "hdr" > "$COLOR_FILE"
    notify-send "Монитор" "Режим цвета: HDR" -t 2000 -i video-display
else
    echo "sdr" > "$COLOR_FILE"
    notify-send "Монитор" "Режим цвета: SDR" -t 2000 -i video-display
fi

"$HOME/.config/hypr/scripts/apply_monitors.sh"
