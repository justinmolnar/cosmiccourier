-- data/names/templates/client/factory.lua

return {
    -- District / dominance
    { t = "{district_descriptor} {factory_noun}",        weight = 3, requires = { in_district = "factory" } },
    { t = "{district_descriptor} {factory_noun}",        weight = 2, requires = { in_district = "industrial" } },
    -- Geography
    { t = "Riverside {factory_noun}",                    weight = 2, requires = { near_river = true } },
    { t = "Highland {factory_noun}",                     weight = 1, requires = { highland = true } },
    -- City-name borrow
    { t = "{city_name} {factory_noun}",                  weight = 2, requires = { has_city_name = true } },
    -- Generic
    { t = "{industry_adj} {factory_noun}",               weight = 3 },
    { t = "{last} {factory_noun}",                       weight = 2 },
    { t = "{industry_adj} & Co.",                        weight = 1 },
    { t = "{industry_adj} Metalworks",                   weight = 1 },
}
