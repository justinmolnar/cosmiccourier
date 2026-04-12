-- data/rule_templates.lua
-- Single source of truth for all unlockable rule templates.
-- Each entry defines a complete dispatch rule the player can receive from a pack.
--
-- Fields:
--   id         — unique string
--   name       — display name shown to player
--   desc       — short description of what the rule does
--   tags       — used by packs to query matching templates
--   complexity — 1–5; packs can filter by range
--   rarity     — weight for random selection (higher = rarer = less likely)
--   unlocks    — explicit extra keys to grant (e.g. "prefab:..." ids)
--               block/action/enum keys are derived automatically from build() output
--   build      — function() returning a rule stack (array of nodes)

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function hat(def_id, slots)
    return { kind = "hat", def_id = def_id, slots = slots or {} }
end

local function call(action_id, extra)
    local slots = { action = action_id }
    if extra then for k, v in pairs(extra) do slots[k] = v end end
    return { kind = "stack", def_id = "block_call", slots = slots }
end

local function find_assign(sorter, vehicle_type)
    local node = {
        kind   = "find", def_id = "find_match",
        slots  = { collection = "vehicles", sorter = sorter },
        condition = nil,
        body   = { call("assign_ctx") },
    }
    if vehicle_type then
        node.condition = {
            kind = "bool", def_id = "bool_compare",
            slots = {
                left = { kind = "reporter", node = {
                    def_id = "rep_get_property",
                    slots = { source = "vehicle", property = "type" },
                }},
                op = "=", right = vehicle_type,
            },
        }
    end
    return node
end

local function ctrl_if(condition, body, else_body)
    return {
        kind = "control", def_id = else_body and "ctrl_if_else" or "ctrl_if",
        slots = {}, condition = condition, body = body, else_body = else_body,
    }
end

local function cond_scope(scope_val)
    return { kind = "bool", def_id = "cond_scope", slots = { scope = scope_val } }
end

local function cond_scope_not(scope_val)
    return { kind = "bool", def_id = "cond_scope_not", slots = { scope = scope_val } }
end

local function compare(source, property, op, right, extra_slots)
    local rep_slots = { source = source, property = property }
    if extra_slots then for k, v in pairs(extra_slots) do rep_slots[k] = v end end
    return {
        kind = "bool", def_id = "bool_compare",
        slots = {
            left = { kind = "reporter", node = { def_id = "rep_get_property", slots = rep_slots } },
            op = op, right = right,
        },
    }
end

local function cond_no_idle(vtype)
    return { kind = "bool", def_id = "cond_vehicle_none", slots = { vehicle_type = vtype or "any" } }
end

local function set_leg_dest(building_type, prop)
    return call("set_leg_destination", {
        pos = { kind = "reporter", node = {
            def_id = "rep_get_property",
            slots = { source = "building", property = prop or "nearest_pos", building_type = building_type },
        }},
    })
end

local function find_assign_from_building(sorter, vehicle_type)
    local node = {
        kind   = "find", def_id = "find_match",
        slots  = { collection = "vehicles", sorter = sorter },
        condition = nil,
        body   = { call("assign_from_building") },
    }
    if vehicle_type then
        node.condition = {
            kind = "bool", def_id = "bool_compare",
            slots = {
                left = { kind = "reporter", node = {
                    def_id = "rep_get_property",
                    slots = { source = "vehicle", property = "type" },
                }},
                op = "=", right = vehicle_type,
            },
        }
    end
    return node
end

-- ── Templates ────────────────────────────────────────────────────────────────

return {

-- ═════════════════════════════════════════════════════════════════════════════
-- STARTER — granted with auto_dispatch_1
-- ═════════════════════════════════════════════════════════════════════════════

    {   id         = "assign_any_vehicle",
        name       = "Assign Any Vehicle",
        desc       = "Assigns the nearest idle vehicle to each pending trip.",
        tags       = { "starter", "assignment" },
        complexity = 1,
        rarity     = 1,
        unlocks    = {
            "prefab:pref_assign_nearest", "prefab:pref_assign_any",
        },
        build = function()
            return {
                hat("trigger_trip"),
                find_assign("nearest"),
            }
        end,
    },

    {   id         = "assign_nearest_bike",
        name       = "Assign Nearest Bike",
        desc       = "Assigns the nearest idle bike to each pending trip.",
        tags       = { "starter", "assignment" },
        complexity = 1,
        rarity     = 1,
        unlocks    = {},
        build = function()
            return {
                hat("trigger_trip"),
                find_assign("nearest", "bike"),
            }
        end,
    },

    {   id         = "cancel_expired_trips",
        name       = "Cancel Expired Trips",
        desc       = "Cancels trips that have been waiting longer than 60 seconds.",
        tags       = { "starter", "queue" },
        complexity = 1,
        rarity     = 1,
        unlocks    = {
            "prefab:pref_cancel_trip", "prefab:pref_check_wait",
        },
        build = function()
            return {
                hat("trigger_trip"),
                ctrl_if(
                    compare("trip", "wait_time", ">", 60),
                    { call("cancel_trip") }
                ),
            }
        end,
    },

    {   id         = "skip_low_payouts",
        name       = "Skip Low Payouts",
        desc       = "Skips trips worth less than $50 so better rules can handle them.",
        tags       = { "starter", "filter" },
        complexity = 1,
        rarity     = 1,
        unlocks    = {
            "prefab:pref_skip_trip", "prefab:pref_check_payout",
        },
        build = function()
            return {
                hat("trigger_trip"),
                ctrl_if(
                    compare("trip", "payout", "<", 50),
                    { call("skip") }
                ),
            }
        end,
    },

-- ═════════════════════════════════════════════════════════════════════════════
-- ASSIGNMENT — different vehicle selection strategies
-- ═════════════════════════════════════════════════════════════════════════════

    {   id         = "assign_fastest",
        name       = "Assign Fastest Vehicle",
        desc       = "Picks the fastest idle vehicle for each trip.",
        tags       = { "assignment" },
        complexity = 1,
        rarity     = 2,
        unlocks    = {
            "prefab:pref_assign_fastest",
        },
        build = function()
            return {
                hat("trigger_trip"),
                find_assign("fastest"),
            }
        end,
    },

    {   id         = "assign_most_capacity",
        name       = "Assign Most Capacity",
        desc       = "Picks the vehicle with the most cargo space.",
        tags       = { "assignment" },
        complexity = 1,
        rarity     = 2,
        unlocks    = {
            "prefab:pref_assign_most_capacity",
        },
        build = function()
            return {
                hat("trigger_trip"),
                find_assign("most_capacity"),
            }
        end,
    },

    {   id         = "prioritize_expensive",
        name       = "Prioritize Expensive Trips",
        desc       = "Moves high-payout trips to the front of the queue.",
        tags       = { "assignment", "queue" },
        complexity = 1,
        rarity     = 2,
        unlocks    = {
            "prefab:pref_prioritize_trip", "prefab:pref_check_payout",
        },
        build = function()
            return {
                hat("trigger_trip"),
                ctrl_if(
                    compare("trip", "payout", ">", 200),
                    { call("prioritize_trip") }
                ),
            }
        end,
    },

-- ═════════════════════════════════════════════════════════════════════════════
-- ROUTING — scope-based vehicle matching
-- ═════════════════════════════════════════════════════════════════════════════

    {   id         = "cars_for_city",
        name       = "Cars for City Trips",
        desc       = "Assigns cars to city-scope trips.",
        tags       = { "routing", "assignment" },
        complexity = 2,
        rarity     = 2,
        unlocks    = {},
        build = function()
            return {
                hat("trigger_trip"),
                ctrl_if(cond_scope("city"), {
                    find_assign("nearest", "car"),
                }),
            }
        end,
    },

    {   id         = "trucks_not_district",
        name       = "Trucks for Long Haul",
        desc       = "Assigns trucks to any trip that isn't district-local.",
        tags       = { "routing", "assignment" },
        complexity = 2,
        rarity     = 2,
        unlocks    = {},
        build = function()
            return {
                hat("trigger_trip"),
                ctrl_if(cond_scope_not("district"), {
                    find_assign("nearest", "truck"),
                }),
            }
        end,
    },

    {   id         = "ships_for_world",
        name       = "Ships for Overseas",
        desc       = "Assigns ships to world-scope trips.",
        tags       = { "routing", "assignment" },
        complexity = 2,
        rarity     = 3,
        unlocks    = {},
        build = function()
            return {
                hat("trigger_trip"),
                ctrl_if(cond_scope("world"), {
                    find_assign("nearest", "ship"),
                }),
            }
        end,
    },

    {   id         = "tiered_assignment",
        name       = "Tiered Assignment",
        desc       = "Bikes for district, cars for city, trucks for everything else.",
        tags       = { "routing", "assignment" },
        complexity = 3,
        rarity     = 3,
        unlocks    = {},
        build = function()
            return {
                hat("trigger_trip"),
                ctrl_if(cond_scope("district"), {
                    find_assign("nearest", "bike"),
                }, {
                    ctrl_if(cond_scope("city"), {
                        find_assign("nearest", "car"),
                    }, {
                        find_assign("nearest", "truck"),
                    }),
                }),
            }
        end,
    },

-- ═════════════════════════════════════════════════════════════════════════════
-- HUB ROUTING — dock/building transfers
-- ═════════════════════════════════════════════════════════════════════════════

    {   id         = "route_to_dock",
        name       = "Route to Nearest Dock",
        desc       = "Reroutes non-district trips to the nearest dock for transfer.",
        tags       = { "routing", "hub" },
        complexity = 2,
        rarity     = 3,
        unlocks    = {},
        build = function()
            return {
                hat("trigger_trip"),
                ctrl_if(cond_scope_not("district"), {
                    set_leg_dest("dock", "nearest_pos"),
                    find_assign("nearest", "truck"),
                }),
            }
        end,
    },

    {   id         = "ship_from_dock",
        name       = "Ship From Dock",
        desc       = "When cargo arrives at a building, ships it to the dock nearest its destination.",
        tags       = { "routing", "hub" },
        complexity = 3,
        rarity     = 3,
        unlocks    = {},
        build = function()
            return {
                hat("hat_trip_deposited"),
                set_leg_dest("dock", "nearest_to_dest_pos"),
                find_assign_from_building("nearest", "ship"),
            }
        end,
    },

-- ═════════════════════════════════════════════════════════════════════════════
-- VEHICLE MANAGEMENT
-- ═════════════════════════════════════════════════════════════════════════════

    {   id         = "send_idle_home",
        name       = "Send Idle Vehicles Home",
        desc       = "Vehicles idle for 30 seconds are sent back to depot.",
        tags       = { "vehicle", "management" },
        complexity = 1,
        rarity     = 2,
        unlocks    = {
            "prefab:pref_send_to_depot",
        },
        build = function()
            return {
                hat("hat_vehicle_idle_for", { vehicle_type = "any", seconds = 30 }),
                call("send_to_depot"),
            }
        end,
    },

    {   id         = "skip_when_all_busy",
        name       = "Skip When All Busy",
        desc       = "Skips trip assignment when no vehicles are idle.",
        tags       = { "filter", "vehicle" },
        complexity = 2,
        rarity     = 2,
        unlocks    = {
            "prefab:pref_skip_trip",
        },
        build = function()
            return {
                hat("trigger_trip"),
                ctrl_if(cond_no_idle("any"), {
                    call("skip"),
                }),
            }
        end,
    },

-- ═════════════════════════════════════════════════════════════════════════════
-- ECONOMY
-- ═════════════════════════════════════════════════════════════════════════════

    {   id         = "save_money_when_broke",
        name       = "Economy Mode",
        desc       = "Only runs cheap local trips when money is low.",
        tags       = { "economy", "filter" },
        complexity = 2,
        rarity     = 3,
        unlocks    = {},
        build = function()
            return {
                hat("trigger_trip"),
                ctrl_if(compare("game", "money", "<", 200), {
                    ctrl_if(cond_scope_not("district"), {
                        call("skip"),
                    }),
                }),
            }
        end,
    },

}
