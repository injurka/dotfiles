-- ГЛАВНЫЙ МОНИТОР (слева, X = 0) — HDR
hl.monitor({
    output = "DP-1",
    mode = "3840x2160@240",
    position = "0x936",
    scale = 1.5,
    bitdepth = 10,
    cm = "hdr",
    supports_hdr = true,
    supports_wide_color = true,
    sdrbrightness = 1.35,
    sdrsaturation = 1.0,
    sdr_min_luminance = 0.0005,
    sdr_max_luminance = 220,
    min_luminance = 0,
    max_luminance = 1000,
    max_avg_luminance = 250,
})

-- ВЕРТИКАЛЬНЫЙ МОНИТОР (справа)
hl.monitor({
    output = "DP-2",
    mode = "2560x1440@144",
    position = "2560x800",
    scale = 1,
    transform = 1,
})
