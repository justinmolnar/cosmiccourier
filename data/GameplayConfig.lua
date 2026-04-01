-- data/GameplayConfig.lua
-- Magic numbers for gameplay systems.
-- Every value has a comment explaining what it controls and what breaks if you change it.

local GameplayConfig = {
    -- TripGenerator: probability of generating a downtown trip vs a city trip.
    -- Must be in [0, 1]. Higher = more downtown trips. At 0 all trips are city trips.
    DOWNTOWN_TRIP_CHANCE = 0.4,

    -- Map.lua getPlotsFromGrid: minimum connected road tiles to count as a valid network.
    -- Road islands smaller than this are discarded. Lower = more fragmented plots accepted;
    -- much lower risks placing depots on disconnected 1-2 tile stubs.
    MIN_NETWORK_SIZE = 10,
}

return GameplayConfig
