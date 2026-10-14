-- 4. ГОРЯЧИЕ КЛАВИШИ (KEYBINDINGS)
-- --------------------------------------------------------------------

-- Системные действия и управление окнами
hl.bind("SUPER + Delete", hl.dsp.exit())
hl.bind("SUPER + S", hl.dsp.window.float({ action = "toggle" }))
hl.bind("SUPER + F", hl.dsp.window.fullscreen())
hl.bind("SUPER + L", hl.dsp.exec_cmd("swaylock"))

-- Приложения
hl.bind("SUPER + Return", hl.dsp.exec_cmd("kitty"))
hl.bind("SUPER + E", hl.dsp.exec_cmd("dolphin"))
hl.bind("SUPER + ALT + Return", hl.dsp.exec_cmd("code"))

-- Меню Rofi
hl.bind("SUPER + D", hl.dsp.exec_cmd("pkill -x rofi || hyde-shell rofilaunch d"))
hl.bind("SUPER + Tab", hl.dsp.exec_cmd("pkill -x rofi || hyde-shell rofilaunch w"))
hl.bind("SUPER + SHIFT + E", hl.dsp.exec_cmd("pkill -x rofi || hyde-shell rofilaunch f"))

-- Скриншоты
hl.bind("SUPER + SHIFT + S", hl.dsp.global("quickshell:regionScreenshot"), { description = "Utilities: Screen snip" })
hl.bind("SUPER + ALT + S", hl.dsp.exec_cmd("hyde-shell screenshot m"))

-- Переключение профилей монитора (HDR / Размер)
hl.bind("SUPER + ALT + H", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.config/hypr/scripts/switch_monitors_profile.sh"))
hl.bind("SUPER + ALT + M", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.config/hypr/scripts/switch_monitors_size.sh"))


-- Специальный воркспейс
hl.bind("SUPER + A", hl.dsp.workspace.toggle_special())
hl.bind("SUPER + SHIFT + A", hl.dsp.window.move({ workspace = "special" }))

-- Save full-monitor screenshots to the same personal directory.
hl.unbind("CTRL + Print")
hl.bind("CTRL + Print", hl.dsp.exec_cmd("hyprshot --mode output --mode active --output-folder /home/injurka/Pictures/Screenshot/"), { locked = true, description = "Screenshot: active monitor to Screenshot folder" })
