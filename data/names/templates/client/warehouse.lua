-- data/names/templates/client/warehouse.lua

return {
    -- District / dominance
    { t = "{district_descriptor} {warehouse_noun}",      weight = 3, requires = { in_district = "warehouse_zone" } },
    { t = "{district_descriptor} {warehouse_noun}",      weight = 3, requires = { in_district = "freight_yard" } },
    -- Geography
    { t = "Port {warehouse_noun}",                       weight = 2, requires = { coastal = true } },
    { t = "Harborside {warehouse_noun}",                 weight = 2, requires = { coastal = true } },
    { t = "Riverside {warehouse_noun}",                  weight = 1, requires = { near_river = true } },
    -- City-name borrow
    { t = "{city_name} {warehouse_noun}",                weight = 2, requires = { has_city_name = true } },
    { t = "{city_name} Freight Hub",                     weight = 1, requires = { has_city_name = true } },
    -- Generic
    { t = "{industry_adj} {warehouse_noun}",             weight = 3 },
    { t = "{last} {warehouse_noun}",                     weight = 2 },
    { t = "{industry_adj} Co.",                          weight = 1 },
}
