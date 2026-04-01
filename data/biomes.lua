-- data/biomes.lua
-- Ordered list of biome definitions used by WorldSandboxView legend
-- and WorldNoiseService color lookup.
-- Each entry: { name, r, g, b }
-- Biomes.getName(h, temp, wet, p) → biome name string
-- Biomes.getColor(h, temp, wet, p) → {r, g, b}

local json = require("lib.json")

local raw    = love.filesystem.read("data/biomes.json")
local Biomes = json.decode(raw)

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
