#!/usr/bin/env bash
# Start the new shell after releasing the old notification server.
if systemctl --user is-active --quiet swaync.service; then
    systemctl --user stop swaync.service
fi
exec qs -n -c "${qsConfig:-ii}"
