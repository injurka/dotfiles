#!/usr/bin/env bash

set -euo pipefail

app_id="org.waywallen.waywallen"

has_desktop_entry() {
    local desktop_dir
    local data_dirs="${XDG_DATA_HOME:-$HOME/.local/share}:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
    local -a search_dirs

    IFS=: read -r -a search_dirs <<< "$data_dirs"
    for desktop_dir in "${search_dirs[@]}"; do
        if [[ -f "$desktop_dir/applications/$app_id.desktop" ]]; then
            return 0
        fi
    done

    return 1
}

find_appimage() {
    local appimage

    if [[ -n "${WAYWALLEN_APPIMAGE:-}" && -x "$WAYWALLEN_APPIMAGE" ]]; then
        printf '%s\n' "$WAYWALLEN_APPIMAGE"
        return 0
    fi

    for appimage in \
        "$HOME"/Applications/*[Ww]aywallen*.AppImage \
        "$HOME"/.local/bin/*[Ww]aywallen*.AppImage; do
        if [[ -x "$appimage" ]]; then
            printf '%s\n' "$appimage"
            return 0
        fi
    done

    return 1
}

is_installed() {
    pgrep -f "[/]waywallen-layer-shell" >/dev/null 2>&1 && return 0
    find_appimage >/dev/null 2>&1 && return 0
    command -v waywallen >/dev/null 2>&1 && return 0
    command -v flatpak >/dev/null 2>&1 && flatpak info "$app_id" >/dev/null 2>&1 && return 0
    has_desktop_entry
}

open_waywallen() {
    local appimage

    if appimage="$(find_appimage)"; then
        exec "$appimage"
    fi

    if command -v waywallen >/dev/null 2>&1; then
        exec waywallen
    fi

    if command -v flatpak >/dev/null 2>&1 && flatpak info "$app_id" >/dev/null 2>&1; then
        exec flatpak run "$app_id"
    fi

    if command -v gtk-launch >/dev/null 2>&1 && has_desktop_entry; then
        exec gtk-launch "$app_id"
    fi

    return 1
}

case "${1:-}" in
    --check)
        is_installed
        ;;
    --open|"")
        open_waywallen
        ;;
    *)
        exit 2
        ;;
esac
