#!/bin/bash

STATE_DIR="$HOME/.config/hypr/.state"
mkdir -p "$STATE_DIR"

COLOR_FILE="$STATE_DIR/color_profile"
SIZE_FILE="$STATE_DIR/size_profile"

[ -f "$COLOR_FILE" ] || echo "sdr" > "$COLOR_FILE"
[ -f "$SIZE_FILE" ] || echo "32" > "$SIZE_FILE"

COLOR_STATE=$(cat "$COLOR_FILE")
SIZE_STATE=$(cat "$SIZE_FILE")

ACTIVE="$HOME/.config/hypr/monitors.lua"

if [ "$SIZE_STATE" = "27" ]; then
    MODE="2560x1440@240"
    SCALE=1
    SIZE_LABEL="27\" (1440p)"
else
    MODE="3840x2160@240"
    SCALE=1.5
    SIZE_LABEL="32\" (4K)"
fi

if [ "$COLOR_STATE" = "hdr" ]; then
    COLOR_CONF='    bitdepth = 10,
    cm = "hdr",
    supports_hdr = true,
    supports_wide_color = true,
    sdrbrightness = 1.35,
    sdrsaturation = 1.0,
    sdr_min_luminance = 0.0005,
    sdr_max_luminance = 220,
    min_luminance = 0,
    max_luminance = 1000,
    max_avg_luminance = 250,'
    COLOR_LABEL="HDR"
else
    COLOR_CONF='    bitdepth = 8,
    cm = "srgb",
    supports_hdr = false,
    supports_wide_color = false,
    sdrbrightness = 1,
    sdrsaturation = 1,'
    COLOR_LABEL="SDR"
fi

cat <<EOF > "$ACTIVE"
-- Автоматически сгенерировано скриптом ($SIZE_LABEL, $COLOR_LABEL)
hl.monitor({
    output = "DP-1",
    mode = "$MODE",
    position = "0x936",
    scale = $SCALE,
$COLOR_CONF
})

hl.monitor({
    output = "DP-2",
    mode = "2560x1440@144",
    position = "2560x800",
    scale = 1,
    transform = 1,
})
EOF

hyprctl reload
