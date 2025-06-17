-- game/upgrades.lua
local Upgrades = {
    -- Existing Upgrades
    {
        id = "bike_speed_1", name = "Improved Tire Pressure", description = "+15% Bike Speed", icon = "🚲", cost = 75, max_level = 5, cost_multiplier = 1.6, prerequisites = {},
        effect = function(state, C) state.upgrades.bike_speed = state.upgrades.bike_speed * 1.15 end
    },
    {
        id = "vehicle_capacity_1", name = "Bigger Backpack", description = "+1 Vehicle Capacity", icon = "🎒", cost = 2500, max_level = 2, cost_multiplier = 3, prerequisites = {},
        effect = function(state, C) state.upgrades.vehicle_capacity = state.upgrades.vehicle_capacity + 1 end
    },
    {
        id = "frenzy_duration_1", name = "Better Call Center", description = "+5s Frenzy Duration", icon = "☎️", cost = 5000, max_level = 10, cost_multiplier = 2.5, prerequisites = {},
        effect = function(state, C) state.upgrades.frenzy_duration = state.upgrades.frenzy_duration + C.EVENTS.DURATION_UPGRADE_AMOUNT end
    },
    {
        id = "auto_dispatch_1", name = "Auto-Dispatcher", description = "Automatically assign pending trips.", icon = "🤖", cost = 1000, max_level = 1, cost_multiplier = 1, prerequisites = {},
        effect = function(state, C) state.upgrades.auto_dispatch_unlocked = true end
    },

    -- NEW UPGRADES TO ADDRESS TRIP BOTTLENECK
    {
        id = "logistics_optimization",
        name = "Logistics Optimization",
        description = "-10% time between new trip offers",
        icon = "📉", cost = 500, max_level = 10, cost_multiplier = 2.2, prerequisites = {},
        effect = function(state, C)
            state.upgrades.trip_gen_min_mult = state.upgrades.trip_gen_min_mult * 0.9
            state.upgrades.trip_gen_max_mult = state.upgrades.trip_gen_max_mult * 0.9
        end
    },
    {
        id = "bulk_contracts",
        name = "Bulk Contracts",
        description = "+5% chance for a client to offer multiple trips",
        icon = "📦", cost = 1200, max_level = 10, cost_multiplier = 3, prerequisites = {},
        effect = function(state, C)
            state.upgrades.multi_trip_chance = state.upgrades.multi_trip_chance + 0.05
        end
    },
    {
        id = "efficient_routing",
        name = "Efficient Routing",
        description = "+1 to number of trips in a bulk offer",
        icon = "🗺️", cost = 2500, max_level = 5, cost_multiplier = 4, prerequisites = {"bulk_contracts"}, -- Requires "Bulk Contracts"
        effect = function(state, C)
            state.upgrades.multi_trip_amount = state.upgrades.multi_trip_amount + 1
        end
    },
    {
        id = "warehouse_expansion",
        name = "Warehouse Expansion",
        description = "+5 to max pending trips",
        icon = "🏢", cost = 800, max_level = 5, cost_multiplier = 2.5, prerequisites = {},
        effect = function(state, C)
            state.upgrades.max_pending_trips = state.upgrades.max_pending_trips + 5
        end
    },
    {
        id = "client_relations",
        name = "Client Relations Dept.",
        description = "-25% time between new trip offers",
        icon = "🤝", cost = 10000, max_level = 1, cost_multiplier = 1, prerequisites = {"logistics_optimization"}, -- Requires "Logistics Optimization"
        effect = function(state, C)
            state.upgrades.trip_gen_min_mult = state.upgrades.trip_gen_min_mult * 0.75
            state.upgrades.trip_gen_max_mult = state.upgrades.trip_gen_max_mult * 0.75
        end
    },
}

local UpgradeMap = {}
for _, upgrade in ipairs(Upgrades) do
    UpgradeMap[upgrade.id] = upgrade
end

return UpgradeMap