-- data/biomes.lua
-- Ordered list of biome definitions used by WorldSandboxView legend
-- and WorldNoiseService color lookup.
-- Each entry: { name, r, g, b }
-- Biomes.getName(h, temp, wet, p) → biome name string
-- Biomes.getColor(h, temp, wet, p) → {r, g, b}

local Biomes = {
    { name="Deep Ocean",         r=0.04, g=0.08, b=0.30 },
    { name="Ocean",              r=0.07, g=0.15, b=0.45 },
    { name="Beach",              r=0.76, g=0.70, b=0.48 },
    { name="Tundra",             r=0.60, g=0.64, b=0.52 },
    { name="Boreal / Taiga",     r=0.22, g=0.38, b=0.24 },
    { name="Temp. Forest",       r=0.24, g=0.46, b=0.18 },
    { name="Temp. Rainforest",   r=0.18, g=0.40, b=0.16 },
    { name="Grassland",          r=0.42, g=0.58, b=0.22 },
    { name="Shrubland",          r=0.52, g=0.46, b=0.24 },
    { name="Subtropical Forest", r=0.16, g=0.44, b=0.12 },
    { name="Woodland",           r=0.34, g=0.54, b=0.20 },
    { name="Savanna",            r=0.65, g=0.60, b=0.24 },
    { name="Semi-arid",          r=0.76, g=0.64, b=0.32 },
    { name="Jungle",             r=0.08, g=0.30, b=0.06 },
    { name="Tropical Forest",    r=0.20, g=0.48, b=0.12 },
    { name="Tropical Savanna",   r=0.68, g=0.62, b=0.22 },
    { name="Desert",             r=0.80, g=0.66, b=0.28 },
    { name="Swamp",              r=0.22, g=0.30, b=0.16 },
    { name="Tropical Swamp",     r=0.18, g=0.26, b=0.12 },
    { name="Highland",           r=0.40, g=0.44, b=0.26 },
    { name="Cold Highland",      r=0.58, g=0.62, b=0.55 },
    { name="Boreal Highland",    r=0.30, g=0.42, b=0.24 },
    { name="Frozen Rock",        r=0.65, g=0.66, b=0.70 },
    { name="Mountain Rock",      r=0.52, g=0.48, b=0.42 },
    { name="Snow Cap",           r=0.88, g=0.90, b=0.95 },
    { name="River",              r=0.22, g=0.52, b=0.88 },
    { name="Lake",               r=0.07, g=0.20, b=0.55 },
}

-- O(1) name→color lookup (built once at module load)
Biomes.colorByName = {}
for _, b in ipairs(Biomes) do Biomes.colorByName[b.name] = {b.r, b.g, b.b} end

-- Climate-driven biome name from elevation/temperature/wetness.
-- p must contain: deep_ocean_max, ocean_max, coast_max, plains_max, forest_max,
--                 highland_max, mountain_max
function Biomes.getName(h, temp, wet, p)
    if h < p.deep_ocean_max then return "Deep Ocean" end
    if h < p.ocean_max      then return "Ocean" end
    if h < p.coast_max      then return "Beach" end
    if h >= p.mountain_max  then return "Snow Cap" end
    if h >= p.highland_max  then
        if temp < 0.25 then return "Frozen Rock" end
        return "Mountain Rock"
    end
    if h >= p.forest_max then
        if temp < 0.22 then return "Cold Highland" end
        if temp < 0.45 then return "Boreal Highland" end
        return "Highland"
    end
    if h < p.plains_max and wet > 0.72 and temp > 0.35 then
        if temp > 0.62 then return "Tropical Swamp" end
        return "Swamp"
    end
    if temp < 0.22 then
        if wet > 0.50 then return "Boreal / Taiga" end
        return "Tundra"
    elseif temp < 0.45 then
        if wet > 0.60 then return "Temp. Rainforest" end
        if wet > 0.35 then return "Temp. Forest" end
        if wet > 0.15 then return "Grassland" end
        return "Shrubland"
    elseif temp < 0.68 then
        if wet > 0.60 then return "Subtropical Forest" end
        if wet > 0.35 then return "Woodland" end
        if wet > 0.15 then return "Savanna" end
        return "Semi-arid"
    else
        if wet > 0.55 then return "Jungle" end
        if wet > 0.30 then return "Tropical Forest" end
        if wet > 0.12 then return "Tropical Savanna" end
        return "Desert"
    end
end

function Biomes.getColor(h, temp, wet, p)
    return Biomes.colorByName[Biomes.getName(h, temp, wet, p)] or {0.5, 0.5, 0.5}
end

return Biomes
