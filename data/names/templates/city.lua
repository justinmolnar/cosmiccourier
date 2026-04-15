-- data/names/templates/city.lua
-- City templates. Uses parent region/continent names + local geography + dominant district.

return {
    { t = "{city_base}",                                 weight = 5 },
    { t = "{city_base}",                                 weight = 2, requires = { has_region_name = true } },
    -- Geography-driven
    { t = "Lake {city_base}",                            weight = 3, requires = { near_lake = true } },
    { t = "{city_base} Lake",                            weight = 2, requires = { near_lake = true } },
    { t = "Port {city_base}",                            weight = 3, requires = { coastal = true } },
    { t = "{city_base} Harbor",                          weight = 3, requires = { coastal = true } },
    { t = "{city_base} Bay",                             weight = 2, requires = { coastal = true } },
    { t = "{city_base} Falls",                           weight = 2, requires = { near_river = true } },
    { t = "{city_base} Ford",                            weight = 2, requires = { near_river = true } },
    { t = "{city_base} Heights",                         weight = 2, requires = { highland = true } },
    { t = "{city_base} Ridge",                           weight = 2, requires = { highland = true } },
    { t = "{city_base} Flats",                           weight = 2, requires = { lowland = true } },
    -- Climate
    { t = "{climate_adj} {city_base}",                   weight = 2, requires = { cold = true } },
    { t = "{climate_adj} {city_base}",                   weight = 2, requires = { hot = true } },
    -- Dominant-district compounds (Gasland-style). {district_stem} resolves
    -- from pools/district_stems.lua keyed by dominant_district value.
    { t = "{district_stem}land",                         weight = 3, requires = { dominant_district = "fuel" } },
    { t = "{district_stem}land",                         weight = 2, requires = { dominant_district = "warehouse_zone" } },
    { t = "{district_stem}land",                         weight = 2, requires = { dominant_district = "factory" } },
    { t = "{district_stem}ville",                        weight = 2, requires = { dominant_district = "freight_yard" } },
    { t = "{district_stem}town",                         weight = 2, requires = { dominant_district = "commercial" } },
    { t = "{district_stem} City",                        weight = 2, requires = { dominant_district = "downtown" } },
    -- Parent-region borrow
    { t = "New {region_name}",                           weight = 1, requires = { has_region_name = true } },
    -- Generic geography fallbacks
    { t = "{city_base} City",                            weight = 1 },
    { t = "Fort {city_base}",                            weight = 1 },
}
