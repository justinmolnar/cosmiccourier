-- data/names/pools/place_names.lua
-- Base place-name pools used when a template pulls a standalone toponym
-- (no parent/context interpolation). Templates may still wrap these,
-- e.g. "{city_base} Heights".

return {
    continent_bases = {
        "Tamarind", "Aurelia", "Meridian", "Cascadia", "Pangaea", "Avalon",
        "Solara", "Nyra", "Veridia", "Halcyon", "Zephyr", "Oriana", "Vestal",
        "Calderon", "Teramar", "Kelaino", "Ophira", "Tanno", "Corvena",
        "Marador",
    },
    region_bases = {
        "Northwood", "Summerset", "Fairhaven", "Redfield", "Whitestone",
        "Ironvale", "Gladewater", "Rosewood", "Elmbrook", "Claywood",
        "Stonehollow", "Oakmere", "Mirefield", "Brightmoor", "Ashford",
        "Bellbrook", "Millbrook", "Wolfwood", "Highgarden", "Larkspur",
    },
    city_bases = {
        "Portland", "Fairview", "Kingsford", "Ashville", "Belmont", "Clifton",
        "Dover", "Easton", "Fremont", "Glenwood", "Hartford", "Ironton",
        "Jameston", "Kingston", "Lanford", "Marston", "Newbury", "Oakdale",
        "Parkville", "Queensberry", "Rockport", "Salem", "Tanno", "Upland",
        "Vernon", "Westwood", "Yorkton", "Zanesville", "Bridgewater", "Cedarbrook",
        "Danbury", "Elmira", "Fayette", "Greenfield", "Havenwood", "Inglewood",
        "Jefferson", "Kenwood", "Lakewood", "Marlow", "Norwalk", "Orford",
        "Pinehurst", "Ridgeway", "Silverton", "Thornton", "Valmont", "Waverly",
        "Amberton", "Briarfield", "Creston", "Driftwood", "Edenbrook",
        "Foxridge", "Grantham", "Hollybrook", "Ivywood", "Juniper",
        "Kilbride", "Linden", "Montrose", "Northbridge", "Oakhurst",
        "Pemberton", "Quailwood", "Redbrook", "Stratford", "Thistledown",
        "Underwood", "Vinewood", "Whitfield", "Yellowstone", "Zephyrton",
    },
    depot_bases = {
        "Central", "North", "South", "East", "West", "Harbor",
        "Riverside", "Lakeside", "Hillside", "Sunset", "Market", "Midtown",
        "Old Town", "Uptown", "Downtown", "Ashford", "Pine", "Elm",
    },
    depot_suffixes = {
        "Depot", "Hub", "Yard", "Station", "Terminal", "Exchange", "Post", "Works",
    },
}
