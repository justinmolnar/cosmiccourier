-- data/upgrades.lua
-- Pure data structure for game upgrades - no business logic

local Upgrades = {
    categories = {
        -- =============================================================================
        -- == VEHICLES CATEGORY
        -- =============================================================================
        {
            id = "vehicles",
            name = "Vehicles",
            sub_types = {
                {
                    id = "bike",
                    name = "Bike",
                    icon = "🚲",
                    tree = {
                        -- Speed Branch
                        {
                            id = "bike_speed_1", 
                            name = "Improved Tire Pressure", 
                            description = "+15% Bike Speed", 
                            icon = "🚲", 
                            cost = 75, 
                            max_level = 5, 
                            cost_multiplier = 1.6, 
                            prerequisites = {},
                            position = { x = 0, y = 0 },
                            effect_type = "multiply_stat",
                            effect_target = "bike_speed",
                            effect_value = 1.15
                        },
                        {
                            id = "bike_frame", 
                            name = "Lighter Frame", 
                            description = "+20% Bike Speed", 
                            icon = "🚲", 
                            cost = 500, 
                            max_level = 3, 
                            cost_multiplier = 2.0, 
                            prerequisites = {"bike_speed_1"},
                            position = { x = 0, y = 1 },
                            effect_type = "multiply_stat",
                            effect_target = "bike_speed",
                            effect_value = 1.20
                        },
                        {
                            id = "aerodynamic_helmet", 
                            name = "Aerodynamic Helmet", 
                            description = "+25% Bike Speed", 
                            icon = "🚲", 
                            cost = 2500, 
                            max_level = 2, 
                            cost_multiplier = 2.5, 
                            prerequisites = {"bike_frame"},
                            position = { x = 0, y = 2 },
                            effect_type = "multiply_stat",
                            effect_target = "bike_speed",
                            effect_value = 1.25
                        },
                        {
                            id = "electric_assist", 
                            name = "Electric-Assist Motor", 
                            description = "+50% Bike Speed, but increases cost.", 
                            icon = "⚡", 
                            cost = 150000, 
                            max_level = 1, 
                            cost_multiplier = 1, 
                            prerequisites = {"aerodynamic_helmet"},
                            position = { x = 0, y = 3 },
                            effect_type = "multiply_stat",
                            effect_target = "bike_speed",
                            effect_value = 1.5
                        },

                        -- Capacity Branch
                        {
                            id = "vehicle_capacity_1", 
                            name = "Bigger Backpack", 
                            description = "+1 Vehicle Capacity", 
                            icon = "🎒", 
                            cost = 2500, 
                            max_level = 2, 
                            cost_multiplier = 3, 
                            prerequisites = {},
                            position = { x = 2, y = 0 },
                            effect_type = "add_stat",
                            effect_target = "vehicle_capacity",
                            effect_value = 1
                        },
                        {
                            id = "cargo_racks", 
                            name = "Install Cargo Racks", 
                            description = "+2 Vehicle Capacity", 
                            icon = "🎒", 
                            cost = 10000, 
                            max_level = 2, 
                            cost_multiplier = 4, 
                            prerequisites = {"vehicle_capacity_1"},
                            position = { x = 2, y = 1 },
                            effect_type = "add_stat",
                            effect_target = "vehicle_capacity",
                            effect_value = 2
                        },
                        {
                            id = "bike_trailer", 
                            name = "Cargo Trailer", 
                            description = "+4 Vehicle Capacity", 
                            icon = "🎒", 
                            cost = 80000, 
                            max_level = 1, 
                            cost_multiplier = 1, 
                            prerequisites = {"cargo_racks"},
                            position = { x = 2, y = 2 },
                            effect_type = "add_stat",
                            effect_target = "vehicle_capacity",
                            effect_value = 4
                        },

                        -- Efficiency Branch
                        {
                            id = "bike_maintenance", 
                            name = "Routine Maintenance", 
                            description = "Bikes have a 5% chance to move 50% faster.", 
                            icon = "🔧", 
                            cost = 800, 
                            max_level = 5, 
                            cost_multiplier = 1.8, 
                            prerequisites = {"bike_speed_1"},
                            position = { x = -1, y = 1 },
                            effect_type = "special",
                            effect_target = "bike_maintenance_chance",
                            effect_value = 0.05
                        },
                        {
                            id = "gps_routing", 
                            name = "GPS Routing", 
                            description = "Bikes find slightly shorter paths.", 
                            icon = "🗺️", 
                            cost = 12000, 
                            max_level = 3, 
                            cost_multiplier = 2.2, 
                            prerequisites = {"bike_maintenance"},
                            position = { x = -1, y = 2 },
                            effect_type = "special",
                            effect_target = "bike_gps_routing",
                            effect_value = true
                        },
                        {
                            id = "shortcuts", 
                            name = "Alleyway Shortcuts", 
                            description = "Bikes can now use special paths.", 
                            icon = "🏙️", 
                            cost = 75000, 
                            max_level = 1, 
                            cost_multiplier = 1, 
                            prerequisites = {"gps_routing"},
                            position = { x = -1, y = 3 },
                            effect_type = "special",
                            effect_target = "bike_shortcuts",
                            effect_value = true
                        },

                        -- Cost Branch
                        {
                            id = "bulk_bike_parts", 
                            name = "Bulk Bike Parts", 
                            description = "-10% cost for new bikes.", 
                            icon = "🔩", 
                            cost = 2000, 
                            max_level = 5, 
                            cost_multiplier = 2.0, 
                            prerequisites = {"vehicle_capacity_1"},
                            position = { x = 3, y = 1 },
                            effect_type = "special",
                            effect_target = "bike_cost_reduction",
                            effect_value = 0.10
                        },
                        {
                            id = "mechanic_deal", 
                            name = "Deal with Mechanic", 
                            description = "-25% cost for all bike upgrades.", 
                            icon = "🤝", 
                            cost = 25000, 
                            max_level = 1, 
                            cost_multiplier = 1, 
                            prerequisites = {"bulk_bike_parts"},
                            position = { x = 3, y = 2 },
                            effect_type = "special",
                            effect_target = "bike_upgrade_discount",
                            effect_value = 0.25
                        },
                    }
                },
                {
                    id = "truck",
                    name = "Truck",
                    icon = "🚚",
                    tree = {
                        {
                            id = "truck_speed_1", 
                            name = "Engine Tuning", 
                            description = "+10% Truck Speed", 
                            icon = "🚚", 
                            cost = 5000, 
                            max_level = 5, 
                            cost_multiplier = 1.8, 
                            prerequisites = {},
                            position = { x = 1, y = 1 },
                            effect_type = "multiply_stat",
                            effect_target = "truck_speed",
                            effect_value = 1.10
                        },
                        {
                            id = "turbocharger", 
                            name = "Turbocharger", 
                            description = "+15% Truck Speed", 
                            icon = "🚚", 
                            cost = 45000, 
                            max_level = 3, 
                            cost_multiplier = 2.1, 
                            prerequisites = {"truck_speed_1"},
                            position = { x = 1, y = 2 },
                            effect_type = "multiply_stat",
                            effect_target = "truck_speed",
                            effect_value = 1.15
                        },
                        {
                            id = "truck_capacity_1", 
                            name = "Expanded Trailer", 
                            description = "+5 Truck-only Capacity", 
                            icon = "📦", 
                            cost = 20000, 
                            max_level = 3, 
                            cost_multiplier = 2.5, 
                            prerequisites = {},
                            position = { x = 2, y = 1 },
                            effect_type = "special",
                            effect_target = "truck_capacity",
                            effect_value = 5
                        },
                        {
                            id = "double_trailer", 
                            name = "Double Trailer", 
                            description = "+10 Truck-only Capacity", 
                            icon = "📦", 
                            cost = 120000, 
                            max_level = 2, 
                            cost_multiplier = 3.0, 
                            prerequisites = {"truck_capacity_1"},
                            position = { x = 2, y = 2 },
                            effect_type = "special",
                            effect_target = "truck_capacity",
                            effect_value = 10
                        },
                        {
                            id = "highway_tires", 
                            name = "Highway Tires", 
                            description = "Trucks move 20% faster on highways.", 
                            icon = "🛣️", 
                            cost = 15000, 
                            max_level = 1, 
                            cost_multiplier = 1, 
                            prerequisites = {"truck_speed_1"},
                            position = { x = 0, y = 2 },
                            effect_type = "special",
                            effect_target = "highway_speed_bonus",
                            effect_value = 1.20
                        },
                        {
                            id = "refrigeration_unit", 
                            name = "Refrigeration", 
                            description = "Unlocks high-value perishable goods trips.", 
                            icon = "❄️", 
                            cost = 50000, 
                            max_level = 1, 
                            cost_multiplier = 1, 
                            prerequisites = {"truck_capacity_1"},
                            position = { x = 3, y = 2 },
                            effect_type = "special",
                            effect_target = "refrigeration_unlocked",
                            effect_value = true
                        },
                    }
                }
            }
        },
        -- =============================================================================
        -- == CLIENTS CATEGORY
        -- =============================================================================
        {
            id = "clients",
            name = "Clients",
            sub_types = {
                {
                    id = "downtown_clients",
                    name = "Downtown",
                    icon = "🏢",
                    tree = {
                        {
                            id = "logistics_optimization", 
                            name = "Logistics Optimization", 
                            description = "-10% time between new trip offers", 
                            icon = "📉", 
                            cost = 500, 
                            max_level = 10, 
                            cost_multiplier = 2.2, 
                            prerequisites = {},
                            position = { x = 1, y = 1 },
                            effect_type = "multiply_stat",
                            effect_target = "trip_gen_min_mult",
                            effect_value = 0.9
                        },
                        {
                            id = "client_relations", 
                            name = "Client Relations Dept.", 
                            description = "-25% time between new trip offers", 
                            icon = "🤝", 
                            cost = 10000, 
                            max_level = 1, 
                            cost_multiplier = 1, 
                            prerequisites = {"logistics_optimization"},
                            position = { x = 1, y = 2 },
                            effect_type = "multiply_stats",
                            effect_targets = {"trip_gen_min_mult", "trip_gen_max_mult"},
                            effect_value = 0.75
                        },
                        {
                            id = "downtown_payouts_1", 
                            name = "Premium Service", 
                            description = "+10% base payout for Downtown trips.", 
                            icon = "💵", 
                            cost = 1200, 
                            max_level = 10, 
                            cost_multiplier = 1.9, 
                            prerequisites = {},
                            position = { x = 2, y = 1 },
                            effect_type = "special",
                            effect_target = "downtown_payout_bonus",
                            effect_value = 1.10
                        },
                        {
                            id = "downtown_bonus_1", 
                            name = "Express Courier", 
                            description = "+15% speed bonus for Downtown trips.", 
                            icon = "⏱️", 
                            cost = 1500, 
                            max_level = 10, 
                            cost_multiplier = 2.0, 
                            prerequisites = {"downtown_payouts_1"},
                            position = { x = 2, y = 2 },
                            effect_type = "special",
                            effect_target = "downtown_speed_bonus",
                            effect_value = 1.15
                        },
                        {
                            id = "corporate_sponsorship", 
                            name = "Corporate Sponsorship", 
                            description = "+50% payout from all Downtown trips.", 
                            icon = "💼", 
                            cost = 125000, 
                            max_level = 1, 
                            cost_multiplier = 1.0, 
                            prerequisites = {"downtown_bonus_1", "client_relations"},
                            position = { x = 1.5, y = 3 },
                            effect_type = "special",
                            effect_target = "downtown_payout_bonus",
                            effect_value = 1.50
                        },
                    }
                },
                {
                    id = "city_clients",
                    name = "City",
                    icon = "🏙️",
                    tree = {
                        {
                            id = "bulk_contracts", 
                            name = "Bulk Contracts", 
                            description = "+5% chance for a client to offer multiple trips", 
                            icon = "📦", 
                            cost = 1200, 
                            max_level = 10, 
                            cost_multiplier = 3, 
                            prerequisites = {},
                            position = { x = 1, y = 1 },
                            effect_type = "add_stat",
                            effect_target = "multi_trip_chance",
                            effect_value = 0.05
                        },
                        {
                            id = "efficient_routing", 
                            name = "Efficient Routing", 
                            description = "+1 to number of trips in a bulk offer", 
                            icon = "🗺️", 
                            cost = 2500, 
                            max_level = 5, 
                            cost_multiplier = 4, 
                            prerequisites = {"bulk_contracts"},
                            position = { x = 1, y = 2 },
                            effect_type = "add_stat",
                            effect_target = "multi_trip_amount",
                            effect_value = 1
                        },
                        {
                            id = "city_payouts_1", 
                            name = "Long Haul Bonus", 
                            description = "+25% base payout for City-scale trips.", 
                            icon = "💰", 
                            cost = 25000, 
                            max_level = 5, 
                            cost_multiplier = 2.2, 
                            prerequisites = {},
                            position = { x = 2, y = 1 },
                            effect_type = "special",
                            effect_target = "city_payout_bonus",
                            effect_value = 1.25
                        },
                        {
                            id = "interchange_planning", 
                            name = "Interchange Planning", 
                            description = "Trucks transition from depots 15% faster.", 
                            icon = "🔄", 
                            cost = 40000, 
                            max_level = 5, 
                            cost_multiplier = 2.5, 
                            prerequisites = {"city_payouts_1"},
                            position = { x = 2, y = 2 },
                            effect_type = "special",
                            effect_target = "depot_transition_speed",
                            effect_value = 1.15
                        },
                        {
                            id = "regional_depots", 
                            name = "Regional Depots", 
                            description = "Unlock depots outside of the downtown core.", 
                            icon = "🏭", 
                            cost = 250000, 
                            max_level = 1, 
                            cost_multiplier = 1, 
                            prerequisites = {"interchange_planning", "efficient_routing"},
                            position = { x = 1.5, y = 3 },
                            effect_type = "special",
                            effect_target = "regional_depots_unlocked",
                            effect_value = true
                        },
                    }
                }
            }
        },
        -- =============================================================================
        -- == OPERATIONS CATEGORY
        -- =============================================================================
        {
            id = "operations",
            name = "Operations",
            sub_types = {
                {
                    id = "dispatch",
                    name = "Dispatch",
                    icon = "🤖",
                    tree = {
                        {
                            id = "auto_dispatch_1", 
                            name = "Auto-Dispatcher", 
                            description = "Automatically assign pending trips.", 
                            icon = "🤖", 
                            cost = 1000, 
                            max_level = 1, 
                            cost_multiplier = 1, 
                            prerequisites = {},
                            position = { x = 1, y = 0 },
                            effect_type = "set_flag",
                            effect_target = "auto_dispatch_unlocked",
                            effect_value = true
                        },
                        {
                            id = "warehouse_expansion", 
                            name = "Warehouse Expansion", 
                            description = "+5 to max pending trips", 
                            icon = "🏗️", 
                            cost = 800, 
                            max_level = 5, 
                            cost_multiplier = 2.5, 
                            prerequisites = {"auto_dispatch_1"},
                            position = { x = 1, y = 1 },
                            effect_type = "add_stat",
                            effect_target = "max_pending_trips",
                            effect_value = 5
                        },
                        {
                            id = "dispatch_algorithm", 
                            name = "Dispatch Algorithm", 
                            description = "Auto-dispatcher assigns trips 10% faster.", 
                            icon = "💡", 
                            cost = 5000, 
                            max_level = 5, 
                            cost_multiplier = 1.9, 
                            prerequisites = {"warehouse_expansion"},
                            position = { x = 1, y = 2 },
                            effect_type = "special",
                            effect_target = "dispatch_speed_bonus",
                            effect_value = 1.10
                        },
                        {
                            id = "predictive_dispatch", 
                            name = "Predictive Dispatch", 
                            description = "Assigns vehicles before trips are even ready.", 
                            icon = "🔮", 
                            cost = 50000, 
                            max_level = 1, 
                            cost_multiplier = 1, 
                            prerequisites = {"dispatch_algorithm"},
                            position = { x = 1, y = 3 },
                            effect_type = "special",
                            effect_target = "predictive_dispatch_unlocked",
                            effect_value = true
                        },
                        {
                            id = "depot_sorting", 
                            name = "Depot Sorting System", 
                            description = "Vehicles find paths from depot 5% faster.", 
                            icon = "🏭", 
                            cost = 7500, 
                            max_level = 5, 
                            cost_multiplier = 2.1, 
                            prerequisites = {"warehouse_expansion"},
                            position = { x = 2, y = 2 },
                            effect_type = "special",
                            effect_target = "depot_pathfinding_bonus",
                            effect_value = 1.05
                        },
                        {
                            id = "automated_loading", 
                            name = "Automated Loading", 
                            description = "Reduce pickup/dropoff times by 50%.", 
                            icon = "🦾", 
                            cost = 95000, 
                            max_level = 1, 
                            cost_multiplier = 1, 
                            prerequisites = {"depot_sorting","dispatch_algorithm"},
                            position = { x = 1.5, y = 4 },
                            effect_type = "special",
                            effect_target = "loading_speed_bonus",
                            effect_value = 0.50
                        },
                    }
                },
                {
                    id = "call_center",
                    name = "Call Center",
                    icon = "☎️",
                    tree = {
                        {
                            id = "frenzy_duration_1", 
                            name = "Better Call Center", 
                            description = "+5s Frenzy Duration", 
                            icon = "☎️", 
                            cost = 5000, 
                            max_level = 10, 
                            cost_multiplier = 2.5, 
                            prerequisites = {},
                            position = { x = 1, y = 1 },
                            effect_type = "add_stat",
                            effect_target = "frenzy_duration",
                            effect_value = 5
                        },
                        {
                            id = "frenzy_spawn_rate", 
                            name = "Marketing Dept.", 
                            description = "Rush Hour events appear 10% more often.", 
                            icon = "📈", 
                            cost = 15000, 
                            max_level = 4, 
                            cost_multiplier = 3.0, 
                            prerequisites = {"frenzy_duration_1"},
                            position = { x = 0, y = 2 },
                            effect_type = "special",
                            effect_target = "frenzy_spawn_rate_bonus",
                            effect_value = 1.10
                        },
                        {
                            id = "frenzy_trip_bonus", 
                            name = "Dedicated Phone Lines", 
                            description = "Trips during Rush Hour are worth 20% more.", 
                            icon = "📞", 
                            cost = 25000, 
                            max_level = 5, 
                            cost_multiplier = 2.8, 
                            prerequisites = {"frenzy_duration_1"},
                            position = { x = 2, y = 2 },
                            effect_type = "special",
                            effect_target = "frenzy_trip_bonus",
                            effect_value = 1.20
                        },
                        {
                            id = "rush_hour_synergy", 
                            name = "Rush Hour Synergy", 
                            description = "All vehicles move 10% faster during Rush Hour.", 
                            icon = "💨", 
                            cost = 70000, 
                            max_level = 3, 
                            cost_multiplier = 2.0, 
                            prerequisites = {"frenzy_spawn_rate", "frenzy_trip_bonus"},
                            position = { x = 1, y = 3 },
                            effect_type = "special",
                            effect_target = "rush_hour_speed_bonus",
                            effect_value = 1.10
                        },
                    }
                }
            }
        }
    }
}

-- Create a flat map for easy lookup by ID
local AllUpgrades = {}
for _, category in ipairs(Upgrades.categories) do
    for _, sub_type in ipairs(category.sub_types) do
        for _, upgrade in ipairs(sub_type.tree) do
            AllUpgrades[upgrade.id] = upgrade
        end
    end
end

Upgrades.AllUpgrades = AllUpgrades
return Upgrades