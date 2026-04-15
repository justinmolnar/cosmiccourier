-- data/names/slot_registry.lua
-- Maps template-slot names (e.g. {first}, {food_noun}) to the data-file pool
-- that should resolve them. Pure data — no logic.
--
-- Each entry: { module = "dotted.path", key = "optional_subkey" }
-- The module must return either the pool directly (key omitted) or a table
-- whose [key] is the pool.
--
-- Slots resolved from context.slots (e.g. {city_name}, {district_descriptor},
-- {climate_adj}) are NOT registered here — the context builder pre-fills them.
-- Unregistered slots that also aren't in context.slots will raise a loud error
-- from NameService, which is the intended failure mode (surface missing data).

return {
    first          = { module = "data.names.pools.person_firsts" },
    last           = { module = "data.names.pools.person_lasts"  },

    continent_base = { module = "data.names.pools.place_names", key = "continent_bases" },
    region_base    = { module = "data.names.pools.place_names", key = "region_bases"    },
    city_base      = { module = "data.names.pools.place_names", key = "city_bases"      },
    depot_base     = { module = "data.names.pools.place_names", key = "depot_bases"     },
    depot_suffix   = { module = "data.names.pools.place_names", key = "depot_suffixes"  },

    food_noun      = { module = "data.names.pools.food",     key = "food_noun"       },
    food_adj       = { module = "data.names.pools.food",     key = "food_adj"        },
    food_place     = { module = "data.names.pools.food",     key = "food_place"      },

    retail_adj     = { module = "data.names.pools.retail",   key = "retail_adj"      },
    retail_noun    = { module = "data.names.pools.retail",   key = "retail_noun"     },

    industry_adj   = { module = "data.names.pools.industry", key = "industry_adj"    },
    warehouse_noun = { module = "data.names.pools.industry", key = "warehouse_noun"  },
    factory_noun   = { module = "data.names.pools.industry", key = "factory_noun"    },

    law_adj        = { module = "data.names.pools.legal",    key = "law_adj"         },
    law_suffix     = { module = "data.names.pools.legal",    key = "law_suffix"      },
    law_noun       = { module = "data.names.pools.legal",    key = "law_noun"        },
}
