-- data/names/templates/client/retail.lua

return {
    -- District-membership
    { t = "{district_descriptor} {retail_noun}",         weight = 3, requires = { in_district = "shopping_mall" } },
    { t = "{district_descriptor} {retail_noun}",         weight = 2, requires = { in_district = "luxury_retail" } },
    { t = "{district_descriptor} {retail_noun}",         weight = 2, requires = { in_district = "boutique_shops" } },
    -- Geography
    { t = "Harbor {retail_noun}",                        weight = 2, requires = { coastal = true } },
    { t = "Lakeside {retail_noun}",                      weight = 2, requires = { near_lake = true } },
    -- City-name borrow
    { t = "{city_name} {retail_noun}",                   weight = 2, requires = { has_city_name = true } },
    { t = "{city_name} Outfitters",                      weight = 1, requires = { has_city_name = true } },
    -- Generic
    { t = "{last}'s {retail_noun}",                      weight = 3 },
    { t = "{first}'s {retail_noun}",                     weight = 2 },
    { t = "{retail_adj} {retail_noun}",                  weight = 3 },
    { t = "Corner {retail_noun}",                        weight = 1 },
    { t = "The {retail_adj} {retail_noun}",              weight = 1 },
}
