-- data/names/map_label_config.lua
-- Zoom thresholds, font scales, fade ranges, and toggle default for map labels.
-- All numeric tuning for MapLabels lives here — view code has zero magic numbers.
--
-- `cs` below is the camera.scale value used throughout rendering.
-- Each scope has an [in, out] visibility range; opacity eases to full inside the
-- inner band and fades to zero over the outer edges.
--
--   visible_cs_min / visible_cs_max: label is fully invisible below min and above max
--   fade_low  / fade_high:           linear ease bands inside the window
--
--   0                         visible_cs_min        fade_low       fade_high        visible_cs_max
--   |──────── hidden ─────────|── fade-in ──|── full ──|── fade-out ──|──── hidden ───|

return {
    toggle_default = true,

    continent = {
        visible_cs_min = 0.0,
        fade_low       = 0.05,
        fade_high      = 0.15,
        visible_cs_max = 0.35,
        font_scale     = 2.4,
        color          = { 1.0, 1.0, 1.0, 1.0 },
        shadow         = { 0.0, 0.0, 0.0, 0.8 },
    },
    region = {
        visible_cs_min = 0.15,
        fade_low       = 0.25,
        fade_high      = 0.75,
        visible_cs_max = 1.10,
        font_scale     = 1.4,
        color          = { 1.0, 1.0, 0.92, 1.0 },
        shadow         = { 0.0, 0.0, 0.0, 0.75 },
    },
    city = {
        visible_cs_min = 0.60,
        fade_low       = 1.00,
        fade_high      = 2.50,
        visible_cs_max = 4.00,
        font_scale     = 1.0,
        color          = { 1.0, 0.96, 0.80, 1.0 },
        shadow         = { 0.0, 0.0, 0.0, 0.75 },
    },
}
