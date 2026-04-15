-- data/names/map_label_config.lua
-- Zoom thresholds, font scales, fade ranges, colors, and toggle default for
-- map labels. All numeric tuning for MapLabels lives here — view code has
-- zero magic numbers.
--
-- `cs` is the camera.scale value used throughout rendering. Each scope has
-- an [in, out] visibility range; opacity eases to full inside the inner band
-- and fades to zero over the outer edges.
--
--   visible_cs_min / visible_cs_max: label is fully invisible below min and above max
--   fade_low  / fade_high:           full opacity band
--
--   0                visible_cs_min   fade_low       fade_high       visible_cs_max
--   |── hidden ──────|── fade-in ──|── full ──|── fade-out ──|────── hidden ───────|
--
-- Per-scope fields:
--   font_scale   — multiplier on the base UI font size for this scope's cached font
--   color        — {r,g,b,a} label color
--   shadow       — {r,g,b,a} drop-shadow color (4-direction outline for readability)
--   uppercase    — true to force UPPERCASE labels at draw time
--   proportional_to_city_size (city only) — when true, each city scales by
--                  clamp(city.city_grid_width / city_size_ref, city_size_min, city_size_max)

return {
    toggle_default = true,

    -- fog_cull: all label scopes respect fog of war — a name only appears for
    -- territory the player has actually revealed.

    continent = {
        visible_cs_min = 0.0,
        fade_low       = 0.4,
        fade_high      = 1.2,
        visible_cs_max = 2.5,
        font_scale     = 1.4,
        color          = { 1.00, 0.82, 0.30, 1.0 },   -- warm gold
        shadow         = { 0.10, 0.05, 0.00, 0.95 },
        uppercase      = true,
        fog_cull       = true,
    },
    region = {
        visible_cs_min = 0.4,
        fade_low       = 0.8,
        fade_high      = 3.0,
        visible_cs_max = 6.0,
        font_scale     = 1.0,
        color          = { 1.00, 0.60, 0.35, 1.0 },   -- amber
        shadow         = { 0.08, 0.03, 0.00, 0.90 },
        uppercase      = false,
        fog_cull       = true,
    },
    city = {
        visible_cs_min = 1.0,
        fade_low       = 1.8,
        fade_high      = 4.5,
        visible_cs_max = 8.0,
        font_scale     = 0.85,
        color          = { 1.00, 1.00, 1.00, 1.0 },   -- bright white
        shadow         = { 0.00, 0.00, 0.00, 0.85 },
        uppercase      = false,
        fog_cull       = true,

        -- Per-city proportional scaling — bigger cities get bigger labels.
        proportional_to_city_size = true,
        city_size_ref  = 60,    -- city_grid_width that maps to 1.0x scale
        city_size_min  = 0.70,  -- hard floor so tiny cities stay readable
        city_size_max  = 1.40,  -- hard ceiling so huge cities don't dominate
    },
}
