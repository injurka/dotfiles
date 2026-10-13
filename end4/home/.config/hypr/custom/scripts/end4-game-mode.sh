#!/usr/bin/env bash
# Share end-4's override file with the sidebar game-mode button.
set -euo pipefail
config_root="${XDG_CONFIG_HOME:-$HOME/.config}"
script="$config_root/quickshell/ii/scripts/hyprland/hyprconfigurator.py"
overrides="$config_root/hypr/hyprland/shellOverrides/main.lua"
mode=$(hyprctl getoption animations:enabled -j | jq -r 'if has("bool") then if .bool then 1 else 0 end else .int end')
keys=(animations:enabled decoration:shadow:enabled decoration:blur:enabled general:gaps_in general:gaps_out general:border_size decoration:rounding general:allow_tearing)
args=()
if [[ "$mode" == "0" ]]; then
    for key in "${keys[@]}"; do args+=(--reset "$key"); done
else
    values=(false false false 0 0 1 0 true)
    for i in "${!keys[@]}"; do args+=(--set "${keys[$i]}" "${values[$i]}"); done
fi
python3 "$script" --file "$overrides" "${args[@]}"
hyprctl reload config-only -q
