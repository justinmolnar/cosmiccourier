-- data/WorldGenConfig.lua
-- Magic numbers for the world/city generation pipeline.
-- Every value has a comment explaining what it controls and what breaks if you change it.

local WorldGenConfig = {
    -- WfcBlockService: weight applied to WFC tiles adjacent to an arterial road.
    -- Must be effectively infinite so arterials always force road-connected tiles.
    -- Lower values let non-road tiles appear next to arterials; higher values have no effect.
    ARTERIAL_MULTIPLIER = 1e9,
}

return WorldGenConfig
