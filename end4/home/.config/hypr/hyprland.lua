-- Your Hyprland configuration. HyDE never overwrites this file.

-- --------------------------------------------------------------------
-- 1. НАСТРОЙКИ МОНИТОРОВ
-- --------------------------------------------------------------------
-- Профили мониторов (SDR/HDR) переключаются скриптом
-- scripts/switch_monitors_profile.sh (SUPER + ALT + H),
-- который подменяет содержимое monitors.lua.
dofile(os.getenv("HOME") .. "/.config/hypr/monitors.lua")

-- --------------------------------------------------------------------
-- 2. ГЛОБАЛЬНЫЕ НАСТРОЙКИ (DECORATION, DWINDLE, MASTER, MISC, INPUT)
-- --------------------------------------------------------------------
hl.config({
    input = {
        kb_layout = "us,ru",
        kb_options = "grp:win_space_toggle",
        sensitivity = 0.35,
        accel_profile = "flat",
        force_no_accel = false,
        touchpad = { natural_scroll = false },
    },
    general = {
        allow_tearing = true,
    },
    xwayland = { force_zero_scaling = true },

    decoration = {
        rounding = 10,
        rounding_power = 2,
        active_opacity = 1.0,
    },

    misc = {
        vrr = 0,
    },

    render = {
        direct_scanout = true,
    },
})

-- Привязка воркспейсов к мониторам
hl.workspace_rule({ workspace = "1", monitor = "DP-1", default = true })
hl.workspace_rule({ workspace = "2", monitor = "DP-1" })
hl.workspace_rule({ workspace = "3", monitor = "DP-2" })
hl.workspace_rule({ workspace = "4", monitor = "DP-2" })
hl.workspace_rule({ workspace = "5", monitor = "DP-1" })
hl.workspace_rule({ workspace = "6", monitor = "DP-1" })
hl.workspace_rule({ workspace = "7", monitor = "DP-1" })
hl.workspace_rule({ workspace = "8", monitor = "DP-1" })
hl.workspace_rule({ workspace = "9", monitor = "DP-1" })
hl.workspace_rule({ workspace = "10", monitor = "DP-1" })

-- --------------------------------------------------------------------
-- 3. ПРАВИЛА ОКОН (WINDOW RULES)
-- --------------------------------------------------------------------

-- Функция передает opacity в виде строки "0.90 0.90"
local function opacity(cls, act, inact)
    inact = inact or act
    hl.window_rule({
        match = { class = cls },
        opacity = string.format("%.2f override %.2f override", act, inact)
    })
end

-- --- Прозрачность для приложений ---
opacity("^(firefox)$", 0.98, 0.95)
opacity("^(Google-chrome)$", 0.98, 0.95)
opacity("^(zen)$", 0.98, 0.95)
opacity("^(dev\\.zed\\.Zed)$", 0.98, 0.95)
opacity("^([Cc]ode)$", 0.98, 0.95)
opacity("^(code-url-handler)$", 0.95, 0.90)
opacity("^(kitty)$", 0.80, 0.80)
opacity("^(org.kde.dolphin)$", 0.9, 0.85)
opacity("^([Ss]team)$", 0.95, 0.80)
opacity("^(steamwebhelper)$", 0.70, 0.70)
opacity("^(discord)$", 0.90, 0.85)
opacity("^(md.Obsidian)$", 0.98, 0.95)
-- --- MPV (HDR / Видео) ---
-- force_rgbx принудительно игнорирует альфа-канал буфера (исправляет прозрачность черного цвета в HDR/Vulkan)
hl.window_rule({
    match = { class = "^(mpv)$" },
    force_rgbx = true,
    opaque = true,
    no_blur = true,
    no_dim = true,
})

hl.window_rule({
    match = { class = "^(org.kde.dolphin)$" },
    float = true,
    size = "1000 650",
    center = true,
})

hl.window_rule({
    match = { class = "^(kitty)$" },
    float = true,
    size = "1000 600",
    center = true,
    fullscreen = false,
    fullscreen_state = "0 0",
})

-- --- Плавающие окна (Float) ---
hl.window_rule({ match = { class = "^(org.kde.dolphin)$", title = "^(Progress Dialog — Dolphin)$" }, float = true })
hl.window_rule({ match = { class = "^(org.kde.dolphin)$", title = "^(Copying — Dolphin)$" }, float = true })
hl.window_rule({ match = { title = "^(About Mozilla Firefox)$" }, float = true })
hl.window_rule({ match = { class = "^(firefox)$", title = "^(Picture-in-Picture)$" }, float = true })
hl.window_rule({ match = { class = "^(firefox)$", title = "^(Library)$" }, float = true })

-- --- Игры: минимальный инпут-лаг (Direct Scanout / Immediate Mode) ---
hl.window_rule({ match = { class = "^(steam_app_.*|deadlock|deadlock.exe|project8|cs2)$" }, immediate = true })

-- --------------------------------------------------------------------
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
hl.bind("SUPER + P", hl.dsp.exec_cmd("hyde-shell screenshot s"))
hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd("hyde-shell screenshot sf"))
hl.bind("SUPER + ALT + S", hl.dsp.exec_cmd("hyde-shell screenshot m"))

-- Переключение профилей монитора (HDR / Размер)
hl.bind("SUPER + ALT + H", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.config/hypr/scripts/switch_monitors_profile.sh"))
hl.bind("SUPER + ALT + M", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.config/hypr/scripts/switch_monitors_size.sh"))

-- Ваш скрипт "Interview Hypr Assistant"
hl.bind("SUPER + SHIFT + I", hl.dsp.exec_cmd([[kitty --title "Interview Hypr Assistant" -e bash -c "cd /home/injurka/my/interview-hypr-assistant && ./deploy.sh"]]))

-- Специальный воркспейс
hl.bind("SUPER + A", hl.dsp.workspace.toggle_special())
hl.bind("SUPER + SHIFT + A", hl.dsp.window.move({ workspace = "special" }))
