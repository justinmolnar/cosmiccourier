-- data/names/pools/district_stems.lua
-- Stems used in compound city/region names like "Gasland" or "Dockside".
-- Keyed by district id. Keep keys aligned with data/districts.json.

return {
    downtown        = { stem = "Central",    adj = "Downtown" },
    residential     = { stem = "Hill",       adj = "Suburban" },
    commercial      = { stem = "Market",     adj = "Commerce" },
    industrial      = { stem = "Forge",      adj = "Industrial" },
    warehouse_zone  = { stem = "Freight",    adj = "Freight" },
    freight_yard    = { stem = "Rail",       adj = "Rail" },
    factory         = { stem = "Mill",       adj = "Factory" },
    government      = { stem = "Capitol",    adj = "Capitol" },
    courthouse      = { stem = "Justice",    adj = "Justice" },
    restaurant_row  = { stem = "Kitchen",    adj = "Dining" },
    fine_dining     = { stem = "Table",      adj = "Culinary" },
    fast_food_strip = { stem = "Drive",      adj = "Roadside" },
    retail_strip    = { stem = "Shop",       adj = "Retail" },
    shopping_mall   = { stem = "Plaza",      adj = "Plaza" },
    boutique_shops  = { stem = "Boutique",   adj = "Boutique" },
    luxury_retail   = { stem = "Crown",      adj = "Luxury" },
    market          = { stem = "Market",     adj = "Market" },
    farmers_market  = { stem = "Grange",     adj = "Farmers" },
    fuel            = { stem = "Gas",        adj = "Fuel" },
    waterfront      = { stem = "Dock",       adj = "Waterfront" },
    park            = { stem = "Green",      adj = "Park" },
    port            = { stem = "Port",       adj = "Port" },
}
