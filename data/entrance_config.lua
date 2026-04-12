-- data/entrance_config.lua
-- Pure configuration for the entrance/routing system.
-- Adding a new transport mode = adding an entry here + a building JSON + a vehicle JSON.

return {
    -- Cost penalty applied when cargo transfers between modes at the same city.
    -- Units: estimated seconds of travel time. Prevents gratuitous mode switches.
    TRANSFER_COST = 30,

    -- Multiplier on local and transfer edge costs relative to trunks. Trunks
    -- use fast highways; local/transfer driving uses slower city streets.
    -- Without this penalty, Dijkstra can't tell the difference and may route
    -- through a distant road entrance when a closer one exists, because the
    -- cheaper trunk cost outweighs the longer local leg in total Manhattan.
    LOCAL_COST_FACTOR = 3,

    -- Base speed per mode for edge-cost estimation (travel time = distance / speed).
    -- Used when no specific vehicle speed is available.
    MODE_SPEEDS = {
        road  = 60,
        water = 40,
        rail  = 80,
        air   = 120,
    },

    -- Rendering colors per mode (trip preview in GameView).
    MODE_COLORS = {
        road     = {0.2, 0.8, 1.0, 0.85},
        water    = {0.3, 0.5, 1.0, 0.85},
        rail     = {1.0, 0.6, 0.2, 0.85},
        air      = {1.0, 1.0, 1.0, 0.85},
        transfer = {0.8, 0.8, 0.3, 0.60},
    },
}
