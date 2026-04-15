-- data/names/templates/depot.lua
-- Depot name templates. Uses parent city name + generic depot pool.

return {
    { t = "{depot_base} {depot_suffix}",                 weight = 4 },
    { t = "{city_name} {depot_suffix}",                  weight = 3, requires = { has_city_name = true } },
    { t = "{depot_base} Yard",                           weight = 2 },
    { t = "Central {depot_suffix}",                      weight = 1 },
    { t = "North {depot_suffix}",                        weight = 1 },
    { t = "South {depot_suffix}",                        weight = 1 },
    { t = "Harbor {depot_suffix}",                       weight = 1, requires = { coastal = true } },
}
