-- data/names/templates/region.lua
-- Region templates. Regions resolve {continent_name} from context.slots.

return {
    { t = "{region_base}",                                  weight = 2 },
    { t = "{continent_name} {highland_descriptor}",         weight = 3, requires = { mountainous = true } },
    { t = "{continent_name} {forest_descriptor}",           weight = 2, requires = { forest = true } },
    { t = "{continent_name} {lowland_descriptor}",          weight = 2, requires = { lowland = true } },
    { t = "{continent_name} Coast",                         weight = 2, requires = { coastal = true } },
    { t = "{continent_name} {desert_descriptor}",           weight = 2, requires = { desert = true } },
    { t = "{region_base} {highland_descriptor}",            weight = 1, requires = { mountainous = true } },
    { t = "{region_base} Lake",                             weight = 2, requires = { near_lake = true } },
    { t = "{region_base} Falls",                            weight = 1, requires = { near_river = true },
      slot_overrides = {} },
    { t = "{climate_adj} {region_base}",                    weight = 2, requires = { cold = true } },
    { t = "{climate_adj} {region_base}",                    weight = 2, requires = { hot = true } },
    { t = "Old {region_base}",                              weight = 1 },
    { t = "New {region_base}",                              weight = 1 },
}
