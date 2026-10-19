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
opacity("^([Ss]team)$", 0.95, 0.90)
opacity("^(steamwebhelper)$", 0.95, 0.90)
-- Discord: subtle transparency with blur, overriding end-4's global no_blur.
opacity("^(discord)$", 0.95, 0.90)
hl.window_rule({ match = { class = "^(discord)$" }, no_blur = false })
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

-- Calendar is a regular window so native Hyprland move/resize bindings apply.
hl.window_rule({ match = { title = "^(Calendar — end4)$" }, float = true, center = true })
