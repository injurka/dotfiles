#!/bin/bash

STATE_DIR="$HOME/.config/hypr/.state"
mkdir -p "$STATE_DIR"
SIZE_FILE="$STATE_DIR/size_profile"

[ -f "$SIZE_FILE" ] || echo "32" > "$SIZE_FILE"
STATE=$(cat "$SIZE_FILE")

if [ "$STATE" = "32" ]; then
    echo "27" > "$SIZE_FILE"
    notify-send "Монитор" "Режим: 27\" (2560x1440 @ 240Hz, Масштаб 100%)" -t 2500 -i video-display
else
    echo "32" > "$SIZE_FILE"
    notify-send "Монитор" "Режим: 32\" (3840x2160 @ 240Hz, Масштаб 150%)" -t 2500 -i video-display
fi

"$HOME/.config/hypr/scripts/apply_monitors.sh"
