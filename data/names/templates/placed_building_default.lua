-- data/names/templates/placed_building_default.lua
-- Fallback templates for a placed building whose cfg.id has no dedicated file.
-- Uses the cfg's display_name as the suffix (resolved into {kind} at wire-up time).

return {
    { t = "{city_name} {kind}",                          weight = 3, requires = { has_city_name = true } },
    { t = "{district_descriptor} {kind}",                weight = 2, requires = { in_district = "waterfront" } },
    { t = "Harbor {kind}",                               weight = 2, requires = { coastal = true } },
    { t = "{kind}",                                      weight = 1 },
    { t = "{last}'s {kind}",                             weight = 1 },
}
