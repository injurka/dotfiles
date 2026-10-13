#!/usr/bin/env bash
# Current Quickshell supports an existing KDE StatusNotifierWatcher.
# kded6 alone is not a conflicting tray UI; keep its KDE app services running.
# Notification servers still conflict because the D-Bus notification name is exclusive.
printf ';'
pidof mako dunst swaync || true
