-- data/biomes.lua
-- Ordered list of biome definitions used by WorldSandboxView legend
-- and WorldNoiseService color lookup.
-- Names must match the strings returned by biome_name_climate() in WorldNoiseService.lua.
-- Each entry: { name, r, g, b }

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

return Biomes
