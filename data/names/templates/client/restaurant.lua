-- data/names/templates/client/restaurant.lua
-- Restaurant / eatery templates.

return {
    -- District-membership driven
    { t = "{district_descriptor} {food_noun}",           weight = 3, requires = { in_district = "waterfront" } },
    { t = "{district_descriptor} {food_place}",          weight = 2, requires = { in_district = "fine_dining" } },
    { t = "{district_descriptor} {food_noun}",           weight = 2, requires = { in_district = "restaurant_row" } },
    -- Local geography driven
    { t = "{food_noun} by the Lake",                     weight = 3, requires = { near_lake = true } },
    { t = "Lakeside {food_place}",                       weight = 2, requires = { near_lake = true } },
    { t = "Harborside {food_place}",                     weight = 2, requires = { coastal = true } },
    { t = "Riverside {food_noun}",                       weight = 2, requires = { near_river = true } },
    -- City-name borrow
    { t = "Best {food_noun} in {city_name}",             weight = 2, requires = { has_city_name = true } },
    { t = "{city_name} {food_place}",                    weight = 2, requires = { has_city_name = true } },
    { t = "{city_name}'s {food_noun}",                   weight = 1, requires = { has_city_name = true } },
    -- Generic
    { t = "{first}'s {food_place}",                      weight = 2 },
    { t = "{last}'s {food_noun}",                        weight = 2 },
    { t = "The {food_adj} {food_noun}",                  weight = 2 },
    { t = "{food_adj} {food_place}",                     weight = 2 },
    { t = "Casa {last}",                                 weight = 1 },
    { t = "{food_noun} Haus",                            weight = 1 },
}
