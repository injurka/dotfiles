-- Migrated from the current active HyDE configuration.
-- HyDE startup/config services are not loaded; utility scripts remain available.
hyde = { config = { app = {
 terminal = "kitty", explorer = "dolphin", editor = "code",
 browser = "hyde-shell open --fall firefox web-browser"
}, modifiers = { main = "SUPER" } } }
dofile(HOME .. "/.config/hypr/custom/legacy-bind-dedup.lua")
dofile(HOME .. "/.config/hypr/custom/legacy-dispatcher.lua")
local native_exec = hl.dsp.exec_cmd
local commands = {
 ["hyde-shell wallpaper --global '--next'"] = "python3 \"$HOME/.config/hypr/custom/scripts/end4-wallpaper-cycle.py\" next",
 ["hyde-shell wallpaper --global '--prev'"] = "python3 \"$HOME/.config/hypr/custom/scripts/end4-wallpaper-cycle.py\" prev",
 ["hyde-shell gamemode"] = "bash \"$HOME/.config/hypr/custom/scripts/end4-game-mode.sh\"",
 ["hyde-shell pypr toggle console"] = "\"$HOME/.local/state/hyde/python_env/bin/pypr\" toggle console",
 ["hyde-shell brightnesscontrol '-i'"] = "qs -c ii ipc call brightness increment",
 ["hyde-shell brightnesscontrol '-d'"] = "qs -c ii ipc call brightness decrement",

 ["hyde-shell theme.select"] = "qs -p \"$HOME/.config/quickshell/ii/settings.qml\"",
 ["hyde-shell animations --select"] = "qs -p \"$HOME/.config/quickshell/ii/settings.qml\"",
 ["hyde-shell hyprlock --select"] = "qs -p \"$HOME/.config/quickshell/ii/settings.qml\"",

 ["hyde-shell waybar '--hide'"] = "qs -c ii ipc call bar toggle",
 ["hyde-shell lock-session"] = "loginctl lock-session",
 ["hyde-shell screenshot s"] = "hyprshot --mode region --output-folder /home/injurka/Pictures/Screenshot/",
 ["hyde-shell screenshot sf"] = "hyprshot --freeze --mode region --output-folder /home/injurka/Pictures/Screenshot/",
 ["hyde-shell screenshot m"] = "hyprshot --mode output --output-folder /home/injurka/Pictures/Screenshot/",
 ["hyde-shell screenshot p"] = "hyprshot --mode output --output-folder /home/injurka/Pictures/Screenshot/",
 ["hyde-shell window.pin"] = "hyprctl dispatch pin",
 ["swaylock"] = "loginctl lock-session",
 ["hyde-shell keyboardswitch"] = "hyprctl switchxkblayout all next",
 ["hyde-shell volumecontrol '-o' 'm'"] = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle",
 ["hyde-shell volumecontrol '-i' 'm'"] = "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle",
 ["hyde-shell volumecontrol '-o' 'd'"] = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-",
 ["hyde-shell volumecontrol '-o' 'i'"] = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+ -l 1.5",
}
local globals = {
 ["hyde-shell screenshot sc"] = "quickshell:regionOcr",
 ["hyde-shell wallpaper -GS"] = "quickshell:wallpaperSelectorToggle",
 ["hyde-shell wallbashtoggle -m"] = "quickshell:toggleLightDark",
 ["hyde-shell waybar --next"] = "quickshell:panelFamilyCycle",
 ["hyde-shell waybar --prev"] = "quickshell:panelFamilyCycle",

 ["hyde-shell waybar '--hide'"] = "quickshell:barToggle",
 ["hyde-shell rofilaunch d"] = "quickshell:searchToggleRelease",
 ["pkill -x rofi || hyde-shell rofilaunch d"] = "quickshell:searchToggle",
 ["hyde-shell rofilaunch w"] = "quickshell:overviewWorkspacesToggle",
 ["pkill -x rofi || hyde-shell rofilaunch w"] = "quickshell:overviewWorkspacesToggle",
 ["hyde-shell keybinds_hint"] = "quickshell:cheatsheetToggle",
 ["hyde-shell emoji-picker"] = "quickshell:overviewEmojiToggle",
 ["hyde-shell glyph-picker"] = "quickshell:overviewEmojiToggle",
 ["hyde-shell cliphist -c"] = "quickshell:overviewClipboardToggle",
 ["hyde-shell cliphist"] = "quickshell:overviewClipboardToggle",
 ["hyde-shell logoutlaunch"] = "quickshell:sessionToggle",
}
hl.dsp.exec_cmd = function(command, ...)
 if globals[command] then return hl.dsp.global(globals[command]) end
 return native_exec(commands[command] or command, ...)
end
dofile(HOME .. "/.config/hypr/custom/legacy-keybinds.lua")
dofile(HOME .. "/.config/hypr/custom/personal-keybinds.lua")
hl.dsp.exec_cmd = native_exec
