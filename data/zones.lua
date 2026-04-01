-- data/zones.lua
-- Zone type definitions for city WFC generation.
-- Adjacency is fully permissive (no hard constraints) — clustering comes
-- entirely from per-cell weights derived from district type + biome.

local Zones = {}

Zones.STATES = {"residential", "commercial", "industrial", "park", "none"}

-- Muted earthy palette — similar tones, subtle hue differences
Zones.COLORS = {
    residential = {0.50, 0.64, 0.46},   -- sage green
    commercial  = {0.44, 0.54, 0.66},   -- dusty slate blue
    industrial  = {0.60, 0.55, 0.40},   -- warm khaki
    park        = {0.36, 0.56, 0.40},   -- forest green
    -- "none" → not rendered
}
Zones.COLOR_ALPHA = 0.78

-- Adjacency: fully permissive — see module comment above.
local function dirs(t) return {N=t, S=t, E=t, W=t} end
local all = {residential=true, commercial=true, industrial=true, park=true, none=true}
Zones.ADJACENCY = {
    residential = dirs(all),
    commercial  = dirs(all),
    industrial  = dirs(all),
    park        = dirs(all),
    none        = dirs(all),
}

-- Base weights per district type.
-- poi 1 is always "downtown"; other pois get a randomly assigned type.
Zones.DISTRICT_WEIGHTS = {
    downtown    = {residential=2, commercial=9, industrial=1, park=3, none=0},
    residential = {residential=9, commercial=2, industrial=1, park=3, none=0},
    commercial  = {residential=3, commercial=9, industrial=2, park=2, none=0},
    industrial  = {residential=1, commercial=2, industrial=9, park=1, none=0},
}

-- Random assignable types for non-downtown district pois
Zones.RANDOM_DISTRICT_TYPES = {"residential", "commercial", "industrial"}

-- Per-biome weight multipliers (applied on top of district base weights)
Zones.BIOME_MULTS = {
    ["Boreal / Taiga"]     = {park=3.0, industrial=0.5},
    ["Temp. Rainforest"]   = {park=3.0},
    ["Temp. Forest"]       = {park=2.0},
    ["Subtropical Forest"] = {park=1.8},
    ["Tropical Forest"]    = {park=1.8},
    ["Jungle"]             = {park=2.5, industrial=0.4},
    ["Woodland"]           = {park=1.5},
    ["Swamp"]              = {park=1.5, residential=0.5},
    ["Tropical Swamp"]     = {park=1.5, residential=0.4},
    ["Grassland"]          = {residential=1.5},
    ["Savanna"]            = {residential=1.3},
    ["Tropical Savanna"]   = {residential=1.2},
    ["Shrubland"]          = {residential=1.2},
    ["Tundra"]             = {industrial=1.5, residential=0.5, park=0.3},
    ["Cold Highland"]      = {industrial=1.4, residential=0.6},
    ["Boreal Highland"]    = {park=1.5, industrial=1.2},
    ["Highland"]           = {industrial=1.3},
    ["Desert"]             = {industrial=2.0, park=0.2, residential=0.5},
    ["Semi-arid"]          = {industrial=1.5, park=0.4},
    ["Beach"]              = {commercial=2.0, residential=1.3},
    -- River/lake handled separately in generator (bd.is_river / bd.is_lake)
}

-- Returns true if zone_type matches the given category string.
-- Categories: "residential", "commercial", "industrial", "park"
function Zones.isType(zone_type, category)
    return zone_type == category
end

-- Returns the category of a zone type (same as the type for this 5-zone system).
function Zones.getCategory(zone_type)
    return zone_type
end

return Zones
