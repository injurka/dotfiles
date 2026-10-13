-- Your Hyprland configuration. HyDE never overwrites this file.

-- --------------------------------------------------------------------
-- 1. НАСТРОЙКИ МОНИТОРОВ
-- --------------------------------------------------------------------
-- Профили мониторов (SDR/HDR) переключаются скриптом
-- scripts/switch_monitors_profile.sh (SUPER + ALT + H),
-- который подменяет содержимое monitors.lua.


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
        rounding = 20,
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

hl.config({ general = { layout = "dwindle" } })
