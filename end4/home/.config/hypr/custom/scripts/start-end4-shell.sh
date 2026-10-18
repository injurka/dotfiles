#!/usr/bin/env bash
# Start the new shell after releasing the old notification server.
if systemctl --user is-active --quiet swaync.service; then
    systemctl --user stop swaync.service
fi
# Own the physical power key only while the session menu is available.
# This inhibits logind's key handler, not shutdown selected in the menu.
exec systemd-inhibit --what=handle-power-key --mode=block \
    --who="end-4 Session" --why="Show the Session menu on power button press" \
    qs -n -c "${qsConfig:-ii}"
