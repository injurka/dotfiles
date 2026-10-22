#!/usr/bin/env bash
# Acquire the logind inhibitor before starting the power-key listener.
if [[ "${END4_SESSION_INHIBITED:-0}" != "1" ]]; then
    exec systemd-inhibit --what=handle-power-key --mode=block \
        --who="end-4 Session" --why="Show the Session menu on power button press" \
        env END4_SESSION_INHIBITED=1 "$0"
fi

# Start the new shell after releasing the old notification server.
if systemctl --user is-active --quiet swaync.service; then
    systemctl --user stop swaync.service
fi

# Some firmware sends KEY_POWER to evdev without dispatching XF86PowerOff in
# Hyprland. Listen for that button while this shell session is available.
python3 "$HOME/.config/hypr/custom/scripts/power-button-session.py" &
power_button_listener=$!
cleanup_power_button_listener() {
    kill "$power_button_listener" 2>/dev/null || true
    wait "$power_button_listener" 2>/dev/null || true
}
trap cleanup_power_button_listener EXIT

qs -n -c "${qsConfig:-ii}"
