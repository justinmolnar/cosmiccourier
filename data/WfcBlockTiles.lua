-- data/WfcBlockTiles.lua
-- This file defines the "vocabulary" for the high-fidelity WFC block/road generator.
-- It programmatically creates every possible tile combination and their connection rules.

local WfcBlockTiles = {}

-- Define the full, correct list of zone types that can exist inside a block.
local ZONE_TYPES = {
    "downtown",
    "commercial",
    "residential_north",
    "residential_south",
    "industrial_heavy",
    "industrial_light",
    "university",
    "medical",
    "entertainment",
    "waterfront",
    "warehouse",
    "tech",
    "park_central",
    "park_nature",
    "empty" -- Represents a block with no zone, like a plaza or open green space.
}

-- These tables will hold the complete, generated data.
local TILESET = {}
local ADJACENCY_RULES = {}

-- This function generates the full vocabulary of tiles.
local function generateTileset()
    local tileId = 1
    for i = 0, 15 do
        local connections = {}
        local name_parts = {}

        connections.N = (math.floor(i / 8) % 2) == 1
        connections.E = (math.floor(i / 4) % 2) == 1
        connections.S = (math.floor(i / 2) % 2) == 1
        connections.W = (i % 2) == 1

        if connections.N then table.insert(name_parts, "N") end
        if connections.E then table.insert(name_parts, "E") end
        if connections.S then table.insert(name_parts, "S") end
        if connections.W then table.insert(name_parts, "W") end
        local pattern_name = #name_parts > 0 and table.concat(name_parts, "") or "Solid"

        for _, zone_type in ipairs(ZONE_TYPES) do
            local tile_name = zone_type .. "_" .. pattern_name
            table.insert(TILESET, {
                id = tileId,
                name = tile_name,
                zone = zone_type,
                connections = connections
            })
            tileId = tileId + 1
        end
    end
end

-- NEW FUNCTION: Generates the adjacency rules based on the tileset.
local function generateAdjacencyRules()
    -- Initialize the rules table for each tile ID.
    for _, tile in ipairs(TILESET) do
        ADJACENCY_RULES[tile.id] = { N = {}, E = {}, S = {}, W = {} }
    end

    -- Compare every tile against every other tile to find valid neighbors.
    for _, tileA in ipairs(TILESET) do
        for _, tileB in ipairs(TILESET) do
            -- Rule for North/South connection:
            -- TileB can be NORTH of TileA if TileA's North edge matches TileB's South edge.
            if tileA.connections.N == tileB.connections.S then
                ADJACENCY_RULES[tileA.id].N[tileB.id] = true
                ADJACENCY_RULES[tileB.id].S[tileA.id] = true
            end

            -- Rule for East/West connection:
            -- TileB can be EAST of TileA if TileA's East edge matches TileB's West edge.
            if tileA.connections.E == tileB.connections.W then
                ADJACENCY_RULES[tileA.id].E[tileB.id] = true
                ADJACENCY_RULES[tileB.id].W[tileA.id] = true
            end
        end
    end
end

-- Generate everything when the module is loaded.
generateTileset()
generateAdjacencyRules()

-- Expose the generated data to any other module that requires it.
WfcBlockTiles.getTileset = function()
    return TILESET
end

-- NEW FUNCTION to expose the rules
WfcBlockTiles.getAdjacencyRules = function()
    return ADJACENCY_RULES
end

-- A helper function for debugging.
WfcBlockTiles.debugPrintTileset = function()
    print("--- WFC Block Tileset Vocabulary (" .. #TILESET .. " total tiles) ---")
    -- (Debug print content is unchanged but still useful)
end

return WfcBlockTiles