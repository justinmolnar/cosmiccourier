-- data/names/templates/client/lawyer.lua

return {
    -- Climate / region driven
    { t = "{climate_adj} {law_noun}",                    weight = 3, requires = { cold = true } },
    { t = "{climate_adj} {law_noun}",                    weight = 2, requires = { hot = true } },
    -- District-membership
    { t = "Capitol {law_suffix}",                        weight = 2, requires = { in_district = "government" } },
    { t = "{district_descriptor} {law_noun}",            weight = 2, requires = { in_district = "courthouse" } },
    -- City name borrow
    { t = "{city_name} Legal Group",                     weight = 2, requires = { has_city_name = true } },
    { t = "{city_name} {law_noun}",                      weight = 2, requires = { has_city_name = true } },
    -- Generic
    { t = "{last} {law_suffix}",                         weight = 4 },
    { t = "{last} & {last} {law_suffix}",                weight = 3 },
    { t = "{last}, {last} & {last} LLP",                 weight = 2 },
    { t = "{law_adj} {law_suffix}",                      weight = 2 },
    { t = "{last} Law",                                  weight = 2 },
}
