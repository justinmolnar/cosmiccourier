-- data/WorldGenConfig.lua
-- Magic numbers for the world/city generation pipeline.
-- Every value has a comment explaining what it controls and what breaks if you change it.

local WorldGenConfig = {
    -- WfcBlockService: weight applied to WFC tiles adjacent to an arterial road.
    -- Must be effectively infinite so arterials always force road-connected tiles.
    -- Lower values let non-road tiles appear next to arterials; higher values have no effect.
    ARTERIAL_MULTIPLIER = 1e9,

    -- PathfindingService: cost returned for impassable nodes (road nodes that don't exist,
    -- or tiles the vehicle type cannot traverse). Must exceed any real path cost.
    IMPASSABLE_COST = 9999,

    -- PathfindingService: BFS iteration cap for road-node and sandbox snap searches.
    -- Prevents infinite loops on degenerate maps. 1000 is generous for any city grid.
    SNAP_SEARCH_CAP = 1000,
}

return WorldGenConfig
