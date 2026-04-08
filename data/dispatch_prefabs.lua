-- data/dispatch_prefabs.lua
-- Registry of prefab templates. Each prefab expands into one or more generic
-- primitive nodes (Get, Compare, Find, Call) when inserted from the palette.
--
-- IMPORTANT: reporter values stored in slots must be wrapped:
--   { kind = "reporter", node = { def_id = "...", slots = {...} } }
-- This matches what the drag-drop system stores at UIController.lua:402.

-- ── Helpers ───────────────────────────────────────────────────────────────────

-- Slot value wrapping a rep_get_property reporter node.
local function get_slot(source, property, extra_slots)
    local s = { source = source, property = property }
    if extra_slots then for k, v in pairs(extra_slots) do s[k] = v end end
    return { kind = "reporter", node = { def_id = "rep_get_property", slots = s } }
end

-- Slot value wrapping a rep_get_var reporter node.
local function var_slot(key)
    return { kind = "reporter", node = { def_id = "rep_get_var", slots = { key = key } } }
end

-- bool_compare node: Compare(left_slot, op, right_val)
local function compare_node(left_slot, op, right_val)
    return {
        kind   = "bool",
        def_id = "bool_compare",
        slots  = { left = left_slot, op = op or ">", right = right_val or 0 },
    }
end

-- Pre-configured Call stack node.
local function call_node(action_id, extra_slots)
    local slots = { action = action_id }
    if extra_slots then for k, v in pairs(extra_slots) do slots[k] = v end end
    return { kind = "stack", def_id = "block_call", slots = slots }
end

-- Find-then-assign node with optional vehicle type filter.
local function find_assign_node(sorter, vehicle_type)
    local node = {
        kind      = "find",
        def_id    = "find_match",
        slots     = { collection = "vehicles", sorter = sorter },
        condition = nil,
        body      = { call_node("assign_ctx") },
    }
    if vehicle_type and vehicle_type ~= "any" and vehicle_type ~= "" then
        node.condition = {
            kind   = "bool",
            def_id = "bool_compare",
            slots  = {
                left  = get_slot("vehicle", "type"),
                op    = "=",
                right = vehicle_type,
            },
        }
    end
    return node
end

-- ── Registry ──────────────────────────────────────────────────────────────────

return {

-- ═══════════════════════════════════════════════════════════════════════════
-- CONDITIONS — expand to bool_compare + rep_get_property
-- ═══════════════════════════════════════════════════════════════════════════

    {   id       = "pref_check_payout",
        label    = "Payout",
        kind     = "bool",
        category = "condition",
        tags     = { "trip" },
        color    = { 0.22, 0.68, 0.32 },
        tip      = "Compare trip base payout.",
        params   = {
            { key = "op",    type = "enum",   options = { ">", "<", ">=", "<=", "!=", "=" }, default = ">" },
            { key = "value", type = "number", default = 100, step = 50, min = 0 },
        },
        build = function(p)
            return compare_node(get_slot("trip", "payout"), p.op, p.value)
        end },

    {   id       = "pref_check_wait",
        label    = "Wait time",
        kind     = "bool",
        category = "condition",
        tags     = { "trip" },
        color    = { 0.22, 0.68, 0.32 },
        tip      = "Compare how long this trip has been waiting.",
        params   = {
            { key = "op",      type = "enum",   options = { ">", "<", ">=", "<=", "!=", "=" }, default = ">" },
            { key = "seconds", type = "number", default = 10, step = 5, min = 0 },
        },
        build = function(p)
            return compare_node(get_slot("trip", "wait_time"), p.op, p.seconds)
        end },

    {   id       = "pref_check_leg_count",
        label    = "Leg count",
        kind     = "bool",
        category = "condition",
        tags     = { "trip" },
        color    = { 0.22, 0.68, 0.32 },
        tip      = "Compare the number of legs in this trip.",
        params   = {
            { key = "op",    type = "enum",   options = { ">", "<", ">=", "<=", "!=", "=" }, default = ">" },
            { key = "value", type = "number", default = 1, step = 1, min = 1 },
        },
        build = function(p)
            return compare_node(get_slot("trip", "leg_count"), p.op, p.value)
        end },

    {   id       = "pref_check_cargo_size",
        label    = "Cargo size",
        kind     = "bool",
        category = "condition",
        tags     = { "trip" },
        color    = { 0.22, 0.68, 0.32 },
        tip      = "Compare the cargo size of the current trip leg.",
        params   = {
            { key = "op",    type = "enum",   options = { ">", "<", ">=", "<=", "!=", "=" }, default = ">" },
            { key = "value", type = "number", default = 1, step = 1, min = 0 },
        },
        build = function(p)
            return compare_node(get_slot("trip", "cargo_size"), p.op, p.value)
        end },

    {   id       = "pref_check_trip_bonus",
        label    = "Trip bonus",
        kind     = "bool",
        category = "condition",
        tags     = { "trip" },
        color    = { 0.22, 0.68, 0.32 },
        tip      = "Compare the speed bonus on this trip.",
        params   = {
            { key = "op",    type = "enum",   options = { ">", "<", ">=", "<=", "!=", "=" }, default = ">" },
            { key = "value", type = "number", default = 50, step = 10, min = 0 },
        },
        build = function(p)
            return compare_node(get_slot("trip", "bonus"), p.op, p.value)
        end },

    {   id       = "pref_check_idle_count",
        label    = "Idle count",
        kind     = "bool",
        category = "condition",
        tags     = { "vehicle", "game" },
        color    = { 0.28, 0.72, 0.58 },
        tip      = "Compare how many vehicles of a type are currently idle.",
        params   = {
            { key = "vehicle_type", type = "vehicle_enum", default = "any" },
            { key = "op",           type = "enum",   options = { ">", "<", ">=", "<=", "!=", "=" }, default = ">" },
            { key = "n",            type = "number", default = 1, step = 1, min = 0 },
        },
        build = function(p)
            return compare_node(
                get_slot("fleet", "idle_count", { vehicle_type = p.vehicle_type }),
                p.op, p.n)
        end },

    {   id       = "pref_check_fleet_util",
        label    = "Fleet util %",
        kind     = "bool",
        category = "condition",
        tags     = { "vehicle", "game" },
        color    = { 0.28, 0.72, 0.58 },
        tip      = "Compare what percentage of the fleet is currently busy.",
        params   = {
            { key = "op",    type = "enum",   options = { ">", "<", ">=", "<=", "!=", "=" }, default = ">" },
            { key = "value", type = "number", default = 50, step = 5, min = 0 },
        },
        build = function(p)
            return compare_node(get_slot("fleet", "utilization"), p.op, p.value)
        end },

    {   id       = "pref_check_queue",
        label    = "Queue size",
        kind     = "bool",
        category = "condition",
        tags     = { "game" },
        color    = { 0.60, 0.38, 0.72 },
        tip      = "Compare the number of pending trips in the queue.",
        params   = {
            { key = "op",    type = "enum",   options = { ">", "<", ">=", "<=", "!=", "=" }, default = ">" },
            { key = "value", type = "number", default = 5, step = 1, min = 0 },
        },
        build = function(p)
            return compare_node(get_slot("game", "queue_count"), p.op, p.value)
        end },

    {   id       = "pref_check_money",
        label    = "Money",
        kind     = "bool",
        category = "condition",
        tags     = { "game" },
        color    = { 0.60, 0.38, 0.72 },
        tip      = "Compare the player's current money.",
        params   = {
            { key = "op",    type = "enum",   options = { ">", "<", ">=", "<=", "!=", "=" }, default = ">" },
            { key = "value", type = "number", default = 500, step = 100, min = 0 },
        },
        build = function(p)
            return compare_node(get_slot("game", "money"), p.op, p.value)
        end },

    {   id       = "pref_check_counter",
        label    = "Counter",
        kind     = "bool",
        category = "condition",
        tags     = { "counter", "logic" },
        color    = { 0.72, 0.45, 0.20 },
        tip      = "Compare a named variable / counter.",
        params   = {
            { key = "key",   type = "string", default = "my_var" },
            { key = "op",    type = "enum",   options = { ">", "<", ">=", "<=", "!=", "=" }, default = ">" },
            { key = "value", type = "number", default = 0, step = 1, min = 0 },
        },
        build = function(p)
            return compare_node(var_slot(p.key), p.op, p.value)
        end },

    {   id       = "pref_check_vehicle_speed",
        label    = "Vehicle speed",
        kind     = "bool",
        category = "condition",
        tags     = { "vehicle" },
        color    = { 0.28, 0.72, 0.58 },
        tip      = "Compare this vehicle's speed (inside a Find or event context).",
        params   = {
            { key = "op",    type = "enum",   options = { ">", "<", ">=", "<=", "!=", "=" }, default = ">" },
            { key = "value", type = "number", default = 80, step = 10, min = 0 },
        },
        build = function(p)
            return compare_node(get_slot("vehicle", "speed"), p.op, p.value)
        end },

    {   id       = "pref_check_vehicle_trips",
        label    = "Vehicle trips done",
        kind     = "bool",
        category = "condition",
        tags     = { "vehicle" },
        color    = { 0.28, 0.72, 0.58 },
        tip      = "Compare how many trips this vehicle has completed.",
        params   = {
            { key = "op",    type = "enum",   options = { ">", "<", ">=", "<=", "!=", "=" }, default = ">" },
            { key = "value", type = "number", default = 10, step = 1, min = 0 },
        },
        build = function(p)
            return compare_node(get_slot("vehicle", "trips_completed"), p.op, p.value)
        end },

-- ═══════════════════════════════════════════════════════════════════════════
-- ASSIGNMENT — expand to find_match + block_call(assign_ctx)
-- ═══════════════════════════════════════════════════════════════════════════

    {   id       = "pref_assign_nearest",
        label    = "Assign nearest",
        kind     = "find",
        category = "assignment",
        tags     = { "vehicle", "trip" },
        color    = { 0.85, 0.50, 0.15 },
        tip      = "Find nearest idle vehicle and assign this trip.",
        params   = { { key = "vehicle_type", type = "vehicle_enum", default = "any" } },
        build = function(p) return find_assign_node("nearest", p.vehicle_type) end },

    {   id       = "pref_assign_fastest",
        label    = "Assign fastest",
        kind     = "find",
        category = "assignment",
        tags     = { "vehicle", "trip" },
        color    = { 0.85, 0.50, 0.15 },
        tip      = "Find fastest idle vehicle and assign this trip.",
        params   = { { key = "vehicle_type", type = "vehicle_enum", default = "any" } },
        build = function(p) return find_assign_node("fastest", p.vehicle_type) end },

    {   id       = "pref_assign_most_capacity",
        label    = "Assign most capacity",
        kind     = "find",
        category = "assignment",
        tags     = { "vehicle", "trip" },
        color    = { 0.85, 0.50, 0.15 },
        tip      = "Find idle vehicle with most capacity and assign this trip.",
        params   = { { key = "vehicle_type", type = "vehicle_enum", default = "any" } },
        build = function(p) return find_assign_node("most_capacity", p.vehicle_type) end },

    {   id       = "pref_assign_least_recent",
        label    = "Assign least recent",
        kind     = "find",
        category = "assignment",
        tags     = { "vehicle", "trip" },
        color    = { 0.85, 0.50, 0.15 },
        tip      = "Find idle vehicle that last had a trip the longest ago.",
        params   = { { key = "vehicle_type", type = "vehicle_enum", default = "any" } },
        build = function(p) return find_assign_node("least_recent", p.vehicle_type) end },

    {   id       = "pref_assign_any",
        label    = "Assign any",
        kind     = "find",
        category = "assignment",
        tags     = { "vehicle", "trip" },
        color    = { 0.85, 0.50, 0.15 },
        tip      = "Find any idle vehicle and assign this trip.",
        params   = {},
        build = function(p) return find_assign_node("nearest", nil) end },

-- ═══════════════════════════════════════════════════════════════════════════
-- TRIP ACTIONS
-- ═══════════════════════════════════════════════════════════════════════════

    {   id       = "pref_set_payout",
        label    = "Set payout",
        kind     = "stack",
        category = "trip",
        tags     = { "trip" },
        color    = { 0.22, 0.68, 0.32 },
        tip      = "Override this trip's base payout.",
        params   = { { key = "value", type = "number", default = 100, step = 50, min = 0 } },
        build = function(p) return call_node("set_payout", { value = p.value }) end },

    {   id       = "pref_add_bonus",
        label    = "Add bonus",
        kind     = "stack",
        category = "trip",
        tags     = { "trip" },
        color    = { 0.22, 0.68, 0.32 },
        tip      = "Add a speed bonus to this trip.",
        params   = { { key = "amount", type = "number", default = 50, step = 10, min = 0 } },
        build = function(p) return call_node("add_bonus", { amount = p.amount }) end },

    {   id       = "pref_cancel_trip",
        label    = "Cancel trip",
        kind     = "stack",
        category = "trip",
        tags     = { "trip" },
        color    = { 0.85, 0.28, 0.28 },
        tip      = "Cancel this trip and remove it from the queue.",
        params   = {},
        build = function(p) return call_node("cancel_trip") end },

    {   id       = "pref_prioritize_trip",
        label    = "Prioritize trip",
        kind     = "stack",
        category = "trip",
        tags     = { "trip", "game" },
        color    = { 0.60, 0.38, 0.72 },
        tip      = "Move this trip to the front of the pending queue.",
        params   = {},
        build = function(p) return call_node("prioritize_trip") end },

    {   id       = "pref_deprioritize_trip",
        label    = "Deprioritize trip",
        kind     = "stack",
        category = "trip",
        tags     = { "trip", "game" },
        color    = { 0.60, 0.38, 0.72 },
        tip      = "Move this trip to the back of the pending queue.",
        params   = {},
        build = function(p) return call_node("deprioritize_trip") end },

    {   id       = "pref_sort_queue",
        label    = "Sort queue",
        kind     = "stack",
        category = "trip",
        tags     = { "trip", "game" },
        color    = { 0.60, 0.38, 0.72 },
        tip      = "Re-sort the entire pending queue by the chosen field.",
        params   = { { key = "metric", type = "enum", options = { "payout", "wait", "bonus" }, default = "payout" } },
        build = function(p) return call_node("sort_queue", { metric = p.metric }) end },

    {   id       = "pref_cancel_all_scope",
        label    = "Cancel all (scope)",
        kind     = "stack",
        category = "trip",
        tags     = { "trip", "game" },
        color    = { 0.85, 0.28, 0.28 },
        tip      = "Cancel all pending trips matching a delivery scope.",
        params   = { { key = "scope", type = "enum", options = { "district", "city", "region", "continent", "world" }, default = "district" } },
        build = function(p) return call_node("cancel_all_scope", { scope = p.scope }) end },

    {   id       = "pref_cancel_all_wait",
        label    = "Cancel all (waited)",
        kind     = "stack",
        category = "trip",
        tags     = { "trip", "game" },
        color    = { 0.85, 0.28, 0.28 },
        tip      = "Cancel all pending trips that have waited too long.",
        params   = { { key = "seconds", type = "number", default = 60, step = 10, min = 0 } },
        build = function(p) return call_node("cancel_all_wait", { seconds = p.seconds }) end },

-- ═══════════════════════════════════════════════════════════════════════════
-- ECONOMY
-- ═══════════════════════════════════════════════════════════════════════════

    {   id       = "pref_add_money",
        label    = "Add money",
        kind     = "stack",
        category = "economy",
        tags     = { "game" },
        color    = { 0.30, 0.68, 0.45 },
        tip      = "Add money to the player's balance.",
        params   = { { key = "amount", type = "number", default = 100, step = 100, min = 0 } },
        build = function(p) return call_node("add_money", { amount = p.amount }) end },

    {   id       = "pref_subtract_money",
        label    = "Subtract money",
        kind     = "stack",
        category = "economy",
        tags     = { "game" },
        color    = { 0.30, 0.68, 0.45 },
        tip      = "Subtract money from the player's balance (clamped to 0).",
        params   = { { key = "amount", type = "number", default = 100, step = 100, min = 0 } },
        build = function(p) return call_node("subtract_money", { amount = p.amount }) end },

    {   id       = "pref_trigger_rush_hour",
        label    = "Trigger rush hour",
        kind     = "stack",
        category = "economy",
        tags     = { "game" },
        color    = { 0.80, 0.50, 0.15 },
        tip      = "Start a rush hour period for N seconds.",
        params   = { { key = "seconds", type = "number", default = 30, step = 5, min = 5 } },
        build = function(p) return call_node("trigger_rush_hour", { seconds = p.seconds }) end },

    {   id       = "pref_end_rush_hour",
        label    = "End rush hour",
        kind     = "stack",
        category = "economy",
        tags     = { "game" },
        color    = { 0.80, 0.50, 0.15 },
        tip      = "Immediately end the current rush hour.",
        params   = {},
        build = function(p) return call_node("end_rush_hour") end },

    {   id       = "pref_pause_trip_gen",
        label    = "Pause trip gen",
        kind     = "stack",
        category = "economy",
        tags     = { "game" },
        color    = { 0.50, 0.38, 0.65 },
        tip      = "Stop new trips from appearing.",
        params   = {},
        build = function(p) return call_node("pause_trip_gen") end },

    {   id       = "pref_resume_trip_gen",
        label    = "Resume trip gen",
        kind     = "stack",
        category = "economy",
        tags     = { "game" },
        color    = { 0.50, 0.38, 0.65 },
        tip      = "Resume trip generation after it was paused.",
        params   = {},
        build = function(p) return call_node("resume_trip_gen") end },

    {   id       = "pref_set_trip_gen_rate",
        label    = "Set trip gen rate",
        kind     = "stack",
        category = "economy",
        tags     = { "game" },
        color    = { 0.50, 0.38, 0.65 },
        tip      = "Set the trip generation rate multiplier (1.0 = normal).",
        params   = { { key = "multiplier", type = "number", default = 1.0, step = 0.1, min = 0.1 } },
        build = function(p) return call_node("set_trip_gen_rate", { multiplier = p.multiplier }) end },

-- ═══════════════════════════════════════════════════════════════════════════
-- COUNTERS & FLAGS
-- ═══════════════════════════════════════════════════════════════════════════

    {   id       = "pref_counter_inc",
        label    = "Counter +",
        kind     = "stack",
        category = "counter",
        tags     = { "counter" },
        color    = { 0.72, 0.45, 0.20 },
        tip      = "Increment a named variable by an amount.",
        params   = {
            { key = "var",    type = "string", default = "my_var" },
            { key = "amount", type = "number", default = 1, step = 1, min = 1 },
        },
        build = function(p) return call_node("counter_inc", { var = p.var, amount = p.amount }) end },

    {   id       = "pref_counter_dec",
        label    = "Counter -",
        kind     = "stack",
        category = "counter",
        tags     = { "counter" },
        color    = { 0.72, 0.45, 0.20 },
        tip      = "Decrement a named variable by an amount.",
        params   = {
            { key = "var",    type = "string", default = "my_var" },
            { key = "amount", type = "number", default = 1, step = 1, min = 1 },
        },
        build = function(p) return call_node("counter_dec", { var = p.var, amount = p.amount }) end },

    {   id       = "pref_counter_set",
        label    = "Counter set",
        kind     = "stack",
        category = "counter",
        tags     = { "counter" },
        color    = { 0.72, 0.45, 0.20 },
        tip      = "Set a named variable to an exact value.",
        params   = {
            { key = "var",   type = "string", default = "my_var" },
            { key = "value", type = "number", default = 0, step = 1, min = 0 },
        },
        build = function(p) return call_node("counter_set", { var = p.var, value = p.value }) end },

    {   id       = "pref_counter_reset",
        label    = "Counter reset",
        kind     = "stack",
        category = "counter",
        tags     = { "counter" },
        color    = { 0.72, 0.45, 0.20 },
        tip      = "Reset a named variable to 0.",
        params   = { { key = "var", type = "string", default = "my_var" } },
        build = function(p) return call_node("counter_reset", { var = p.var }) end },

    {   id       = "pref_reset_all_counters",
        label    = "Reset all counters",
        kind     = "stack",
        category = "counter",
        tags     = { "counter" },
        color    = { 0.72, 0.45, 0.20 },
        tip      = "Reset the legacy counters A-E to 0.",
        params   = {},
        build = function(p) return call_node("reset_all_counters") end },

    {   id       = "pref_set_flag",
        label    = "Set flag",
        kind     = "stack",
        category = "counter",
        tags     = { "counter" },
        color    = { 0.55, 0.35, 0.65 },
        tip      = "Set a flag variable to true.",
        params   = { { key = "var", type = "string", default = "my_flag" } },
        build = function(p) return call_node("set_flag", { var = p.var }) end },

    {   id       = "pref_clear_flag",
        label    = "Clear flag",
        kind     = "stack",
        category = "counter",
        tags     = { "counter" },
        color    = { 0.55, 0.35, 0.65 },
        tip      = "Set a flag variable to false.",
        params   = { { key = "var", type = "string", default = "my_flag" } },
        build = function(p) return call_node("clear_flag", { var = p.var }) end },

    {   id       = "pref_toggle_flag",
        label    = "Toggle flag",
        kind     = "stack",
        category = "counter",
        tags     = { "counter" },
        color    = { 0.55, 0.35, 0.65 },
        tip      = "Flip a flag variable between true and false.",
        params   = { { key = "var", type = "string", default = "my_flag" } },
        build = function(p) return call_node("toggle_flag", { var = p.var }) end },

-- ═══════════════════════════════════════════════════════════════════════════
-- VEHICLE ACTIONS
-- ═══════════════════════════════════════════════════════════════════════════

    {   id       = "pref_unassign_vehicle",
        label    = "Unassign vehicle",
        kind     = "stack",
        category = "vehicle",
        tags     = { "vehicle" },
        color    = { 0.28, 0.72, 0.58 },
        tip      = "Remove this vehicle's current trip assignment.",
        params   = {},
        build = function(p) return call_node("unassign_vehicle") end },

    {   id       = "pref_send_to_depot",
        label    = "Send to depot",
        kind     = "stack",
        category = "vehicle",
        tags     = { "vehicle" },
        color    = { 0.28, 0.72, 0.58 },
        tip      = "Send this vehicle back to its depot.",
        params   = {},
        build = function(p) return call_node("send_to_depot") end },

    {   id       = "pref_set_speed_mult",
        label    = "Set speed mult",
        kind     = "stack",
        category = "vehicle",
        tags     = { "vehicle" },
        color    = { 0.28, 0.72, 0.58 },
        tip      = "Multiply this vehicle's movement speed.",
        params   = { { key = "mult", type = "number", default = 1.2, step = 0.1, min = 0.1 } },
        build = function(p) return call_node("set_speed_mult", { mult = p.mult }) end },

    {   id       = "pref_fire_vehicle",
        label    = "Fire vehicle",
        kind     = "stack",
        category = "vehicle",
        tags     = { "vehicle" },
        color    = { 0.85, 0.28, 0.28 },
        tip      = "Permanently remove this vehicle from the fleet.",
        params   = {},
        build = function(p) return call_node("fire_vehicle") end },

    {   id       = "pref_flash_vehicle",
        label    = "Flash vehicle",
        kind     = "stack",
        category = "vehicle",
        tags     = { "vehicle" },
        color    = { 0.28, 0.72, 0.58 },
        tip      = "Flash this vehicle with a yellow highlight for N seconds.",
        params   = { { key = "duration", type = "number", default = 1, step = 0.5, min = 0.1 } },
        build = function(p) return call_node("flash_vehicle", { duration = p.duration }) end },

    {   id       = "pref_show_speech_bubble",
        label    = "Speech bubble",
        kind     = "stack",
        category = "vehicle",
        tags     = { "vehicle", "ui" },
        color    = { 0.28, 0.72, 0.58 },
        tip      = "Show a speech bubble above this vehicle.",
        params   = {
            { key = "text",     type = "string", default = "!" },
            { key = "duration", type = "number", default = 3, step = 1, min = 0.5 },
        },
        build = function(p)
            return call_node("show_speech_bubble", { text = p.text, duration = p.duration })
        end },

-- ═══════════════════════════════════════════════════════════════════════════
-- UI & NOTIFICATIONS
-- ═══════════════════════════════════════════════════════════════════════════

    {   id       = "pref_show_alert",
        label    = "Show alert",
        kind     = "stack",
        category = "ui",
        tags     = { "ui" },
        color    = { 0.65, 0.30, 0.30 },
        tip      = "Show a highlighted alert message in the info feed.",
        params   = { { key = "text", type = "string", default = "Alert!" } },
        build = function(p) return call_node("show_alert", { text = p.text }) end },

    {   id       = "pref_add_to_log",
        label    = "Add to log",
        kind     = "stack",
        category = "ui",
        tags     = { "ui" },
        color    = { 0.45, 0.45, 0.62 },
        tip      = "Add a message to the info feed log.",
        params   = { { key = "text", type = "string", default = "Entry" } },
        build = function(p) return call_node("add_to_log", { text = p.text }) end },

    {   id       = "pref_zoom_to_vehicle",
        label    = "Pan to vehicle",
        kind     = "stack",
        category = "ui",
        tags     = { "ui", "vehicle" },
        color    = { 0.35, 0.55, 0.75 },
        tip      = "Move the camera to this vehicle.",
        params   = {},
        build = function(p) return call_node("zoom_to_vehicle") end },

-- ═══════════════════════════════════════════════════════════════════════════
-- FLOW CONTROL (single-block shortcuts)
-- ═══════════════════════════════════════════════════════════════════════════

    {   id       = "pref_stop_rule",
        label    = "Stop rule",
        kind     = "stack",
        category = "logic",
        tags     = { "logic" },
        color    = { 0.50, 0.50, 0.50 },
        tip      = "Stop evaluating this rule (trip stays in queue).",
        params   = {},
        build = function(p) return call_node("stop_rule") end },

    {   id       = "pref_stop_all",
        label    = "Stop all rules",
        kind     = "stack",
        category = "logic",
        tags     = { "logic" },
        color    = { 0.50, 0.50, 0.50 },
        tip      = "Stop evaluating all rules for this trip.",
        params   = {},
        build = function(p) return call_node("stop_all") end },

    {   id       = "pref_skip_trip",
        label    = "Skip trip",
        kind     = "stack",
        category = "trip",
        tags     = { "trip" },
        color    = { 0.60, 0.38, 0.72 },
        tip      = "Skip this trip for this rule pass (try next rule).",
        params   = {},
        build = function(p) return call_node("skip") end },

-- ═══════════════════════════════════════════════════════════════════════════
-- VEHICLE VISUAL
-- ═══════════════════════════════════════════════════════════════════════════

    {   id       = "pref_set_vehicle_color",
        label    = "Set vehicle color",
        kind     = "stack",
        category = "vehicle",
        tags     = { "vehicle" },
        color    = { 0.28, 0.72, 0.58 },
        tip      = "Tint this vehicle's sprite with an RGB color (0–1 each channel).",
        params   = {
            { key = "r", type = "number", default = 1.0, step = 0.1, min = 0, max = 1 },
            { key = "g", type = "number", default = 0.5, step = 0.1, min = 0, max = 1 },
            { key = "b", type = "number", default = 0.0, step = 0.1, min = 0, max = 1 },
        },
        build = function(p)
            return call_node("set_vehicle_color", { r = p.r, g = p.g, b = p.b })
        end },

    {   id       = "pref_reset_vehicle_color",
        label    = "Reset vehicle color",
        kind     = "stack",
        category = "vehicle",
        tags     = { "vehicle" },
        color    = { 0.28, 0.72, 0.58 },
        tip      = "Restore this vehicle's default color.",
        params   = {},
        build = function(p) return call_node("reset_vehicle_color") end },

    {   id       = "pref_set_vehicle_icon",
        label    = "Set vehicle icon",
        kind     = "stack",
        category = "vehicle",
        tags     = { "vehicle" },
        color    = { 0.28, 0.72, 0.58 },
        tip      = "Override the icon drawn on this vehicle.",
        params   = { { key = "icon", type = "string", default = "star" } },
        build = function(p) return call_node("set_vehicle_icon", { icon = p.icon }) end },

    {   id       = "pref_show_vehicle_label",
        label    = "Show vehicle label",
        kind     = "stack",
        category = "vehicle",
        tags     = { "vehicle" },
        color    = { 0.28, 0.72, 0.58 },
        tip      = "Make this vehicle's name label visible.",
        params   = {},
        build = function(p) return call_node("show_vehicle_label") end },

    {   id       = "pref_hide_vehicle_label",
        label    = "Hide vehicle label",
        kind     = "stack",
        category = "vehicle",
        tags     = { "vehicle" },
        color    = { 0.28, 0.72, 0.58 },
        tip      = "Hide this vehicle's name label.",
        params   = {},
        build = function(p) return call_node("hide_vehicle_label") end },

    {   id       = "pref_show_vehicle",
        label    = "Show vehicle",
        kind     = "stack",
        category = "vehicle",
        tags     = { "vehicle" },
        color    = { 0.28, 0.72, 0.58 },
        tip      = "Make this vehicle visible on the map.",
        params   = {},
        build = function(p) return call_node("show_vehicle") end },

    {   id       = "pref_hide_vehicle",
        label    = "Hide vehicle",
        kind     = "stack",
        category = "vehicle",
        tags     = { "vehicle" },
        color    = { 0.28, 0.72, 0.58 },
        tip      = "Hide this vehicle from the map.",
        params   = {},
        build = function(p) return call_node("hide_vehicle") end },

-- ═══════════════════════════════════════════════════════════════════════════
-- CAMERA
-- ═══════════════════════════════════════════════════════════════════════════

    {   id       = "pref_pan_to_depot",
        label    = "Pan to depot",
        kind     = "stack",
        category = "ui",
        tags     = { "ui" },
        color    = { 0.35, 0.55, 0.75 },
        tip      = "Move the camera to a depot by ID.",
        params   = { { key = "depot_id", type = "string", default = "1" } },
        build = function(p) return call_node("pan_to_depot", { depot_id = p.depot_id }) end },

    {   id       = "pref_set_zoom",
        label    = "Set zoom",
        kind     = "stack",
        category = "ui",
        tags     = { "ui" },
        color    = { 0.35, 0.55, 0.75 },
        tip      = "Set the camera zoom level (1.0 = default).",
        params   = { { key = "level", type = "number", default = 1.5, step = 0.25, min = 0.25 } },
        build = function(p) return call_node("set_zoom", { level = p.level }) end },

    {   id       = "pref_shake_screen",
        label    = "Shake screen",
        kind     = "stack",
        category = "ui",
        tags     = { "ui" },
        color    = { 0.75, 0.40, 0.20 },
        tip      = "Shake the camera for a short duration.",
        params   = {
            { key = "seconds",   type = "number", default = 0.5, step = 0.1, min = 0.1 },
            { key = "magnitude", type = "number", default = 8,   step = 2,   min = 1   },
        },
        build = function(p)
            return call_node("shake_screen", { seconds = p.seconds, magnitude = p.magnitude })
        end },

-- ═══════════════════════════════════════════════════════════════════════════
-- SOUND
-- ═══════════════════════════════════════════════════════════════════════════

    {   id       = "pref_play_sound",
        label    = "Play sound",
        kind     = "stack",
        category = "ui",
        tags     = { "ui", "sound" },
        color    = { 0.45, 0.55, 0.72 },
        tip      = "Play a sound effect by name.",
        params   = { { key = "sound", type = "string", default = "alert" } },
        build = function(p) return call_node("play_sound", { sound = p.sound }) end },

    {   id       = "pref_stop_all_sounds",
        label    = "Stop all sounds",
        kind     = "stack",
        category = "ui",
        tags     = { "ui", "sound" },
        color    = { 0.45, 0.55, 0.72 },
        tip      = "Stop all currently playing sounds.",
        params   = {},
        build = function(p) return call_node("stop_all_sounds") end },

    {   id       = "pref_set_volume",
        label    = "Set volume",
        kind     = "stack",
        category = "ui",
        tags     = { "ui", "sound" },
        color    = { 0.45, 0.55, 0.72 },
        tip      = "Set the global sound volume (0–1).",
        params   = { { key = "level", type = "number", default = 0.5, step = 0.1, min = 0, max = 1 } },
        build = function(p) return call_node("set_volume", { level = p.level }) end },

-- ═══════════════════════════════════════════════════════════════════════════
-- TEXT VARIABLES
-- ═══════════════════════════════════════════════════════════════════════════

    {   id       = "pref_set_text_var",
        label    = "Set text var",
        kind     = "stack",
        category = "counter",
        tags     = { "counter" },
        color    = { 0.55, 0.42, 0.68 },
        tip      = "Set a named text variable to a string value.",
        params   = {
            { key = "key",   type = "string", default = "my_text" },
            { key = "value", type = "string", default = "Hello"   },
        },
        build = function(p)
            return call_node("set_text_var", { key = p.key, value = p.value })
        end },

    {   id       = "pref_append_text_var",
        label    = "Append text var",
        kind     = "stack",
        category = "counter",
        tags     = { "counter" },
        color    = { 0.55, 0.42, 0.68 },
        tip      = "Append a string to an existing text variable.",
        params   = {
            { key = "key",   type = "string", default = "my_text" },
            { key = "value", type = "string", default = " more"   },
        },
        build = function(p)
            return call_node("append_text_var", { key = p.key, value = p.value })
        end },

    {   id       = "pref_clear_text_var",
        label    = "Clear text var",
        kind     = "stack",
        category = "counter",
        tags     = { "counter" },
        color    = { 0.55, 0.42, 0.68 },
        tip      = "Clear a text variable (set to empty string).",
        params   = { { key = "key", type = "string", default = "my_text" } },
        build = function(p) return call_node("clear_text_var", { key = p.key }) end },

    {   id       = "pref_swap_counters",
        label    = "Swap counters",
        kind     = "stack",
        category = "counter",
        tags     = { "counter" },
        color    = { 0.72, 0.45, 0.20 },
        tip      = "Swap the values of two named variables.",
        params   = {
            { key = "var1", type = "string", default = "counter_a" },
            { key = "var2", type = "string", default = "counter_b" },
        },
        build = function(p)
            return call_node("swap_counters", { var1 = p.var1, var2 = p.var2 })
        end },

-- ═══════════════════════════════════════════════════════════════════════════
-- DEPOT
-- ═══════════════════════════════════════════════════════════════════════════

    {   id       = "pref_set_depot_capacity",
        label    = "Set depot capacity",
        kind     = "stack",
        category = "depot",
        tags     = { "depot" },
        color    = { 0.55, 0.45, 0.30 },
        tip      = "Set how many vehicles a depot can hold.",
        params   = { { key = "cap", type = "number", default = 10, step = 1, min = 1 } },
        build = function(p) return call_node("set_depot_capacity", { cap = p.cap }) end },

    {   id       = "pref_send_vehicles_to_depot",
        label    = "Send vehicles to depot",
        kind     = "stack",
        category = "depot",
        tags     = { "depot" },
        color    = { 0.55, 0.45, 0.30 },
        tip      = "Recall all vehicles back to their depots.",
        params   = {},
        build = function(p) return call_node("send_vehicles_to_depot") end },

    {   id       = "pref_open_depot",
        label    = "Open depot",
        kind     = "stack",
        category = "depot",
        tags     = { "depot" },
        color    = { 0.55, 0.45, 0.30 },
        tip      = "Open the depot (allow vehicles to depart).",
        params   = {},
        build = function(p) return call_node("open_depot") end },

    {   id       = "pref_close_depot",
        label    = "Close depot",
        kind     = "stack",
        category = "depot",
        tags     = { "depot" },
        color    = { 0.55, 0.45, 0.30 },
        tip      = "Close the depot (vehicles stay inside).",
        params   = {},
        build = function(p) return call_node("close_depot") end },

    {   id       = "pref_rename_depot",
        label    = "Rename depot",
        kind     = "stack",
        category = "depot",
        tags     = { "depot" },
        color    = { 0.55, 0.45, 0.30 },
        tip      = "Set a new display name for the depot.",
        params   = { { key = "name", type = "string", default = "HQ" } },
        build = function(p) return call_node("rename_depot", { name = p.name }) end },

-- ═══════════════════════════════════════════════════════════════════════════
-- CLIENTS
-- ═══════════════════════════════════════════════════════════════════════════

    {   id       = "pref_pause_all_clients",
        label    = "Pause all clients",
        kind     = "stack",
        category = "economy",
        tags     = { "game", "client" },
        color    = { 0.50, 0.38, 0.65 },
        tip      = "Stop all clients from generating new trips.",
        params   = {},
        build = function(p) return call_node("pause_all_clients") end },

    {   id       = "pref_resume_all_clients",
        label    = "Resume all clients",
        kind     = "stack",
        category = "economy",
        tags     = { "game", "client" },
        color    = { 0.50, 0.38, 0.65 },
        tip      = "Resume all clients generating trips.",
        params   = {},
        build = function(p) return call_node("resume_all_clients") end },

    {   id       = "pref_set_client_freq",
        label    = "Set client frequency",
        kind     = "stack",
        category = "economy",
        tags     = { "game", "client" },
        color    = { 0.50, 0.38, 0.65 },
        tip      = "Multiply all clients' trip generation rate.",
        params   = { { key = "mult", type = "number", default = 1.0, step = 0.1, min = 0.1 } },
        build = function(p) return call_node("set_client_freq", { mult = p.mult }) end },

    {   id       = "pref_add_client",
        label    = "Add client",
        kind     = "stack",
        category = "economy",
        tags     = { "game", "client" },
        color    = { 0.50, 0.38, 0.65 },
        tip      = "Spawn a new client by ID.",
        params   = { { key = "client_id", type = "string", default = "client1" } },
        build = function(p) return call_node("add_client", { client_id = p.client_id }) end },

    {   id       = "pref_remove_client",
        label    = "Remove client",
        kind     = "stack",
        category = "economy",
        tags     = { "game", "client" },
        color    = { 0.50, 0.38, 0.65 },
        tip      = "Remove a client by ID.",
        params   = { { key = "client_id", type = "string", default = "client1" } },
        build = function(p) return call_node("remove_client", { client_id = p.client_id }) end },

-- ═══════════════════════════════════════════════════════════════════════════
-- SYSTEM UTILITIES
-- ═══════════════════════════════════════════════════════════════════════════

    {   id       = "pref_action_break",
        label    = "Break (loop)",
        kind     = "stack",
        category = "logic",
        tags     = { "logic" },
        color    = { 0.50, 0.50, 0.50 },
        tip      = "Break out of the current loop block.",
        params   = {},
        build = function(p) return call_node("action_break") end },

    {   id       = "pref_action_continue",
        label    = "Continue (loop)",
        kind     = "stack",
        category = "logic",
        tags     = { "logic" },
        color    = { 0.50, 0.50, 0.50 },
        tip      = "Skip to the next iteration of the current loop.",
        params   = {},
        build = function(p) return call_node("action_continue") end },

    {   id       = "pref_broadcast_message",
        label    = "Broadcast message",
        kind     = "stack",
        category = "logic",
        tags     = { "logic" },
        color    = { 0.50, 0.50, 0.50 },
        tip      = "Broadcast a named event message to other rules.",
        params   = { { key = "msg", type = "string", default = "my_event" } },
        build = function(p) return call_node("broadcast_message", { msg = p.msg }) end },

    {   id       = "pref_set_rule_name",
        label    = "Set rule name",
        kind     = "stack",
        category = "logic",
        tags     = { "logic" },
        color    = { 0.50, 0.50, 0.50 },
        tip      = "Rename this rule at runtime.",
        params   = { { key = "name", type = "string", default = "New Name" } },
        build = function(p) return call_node("set_rule_name", { name = p.name }) end },

    {   id       = "pref_action_comment",
        label    = "Comment",
        kind     = "stack",
        category = "logic",
        tags     = { "logic" },
        color    = { 0.40, 0.40, 0.40 },
        tip      = "A no-op block for leaving notes inside a rule.",
        params   = { { key = "text", type = "string", default = "note..." } },
        build = function(p) return call_node("action_comment", { text = p.text }) end },

-- ═══════════════════════════════════════════════════════════════════════════
-- CONDITIONS — depot & client
-- ═══════════════════════════════════════════════════════════════════════════

    {   id       = "pref_check_depot_vehicles",
        label    = "Depot vehicle count",
        kind     = "bool",
        category = "condition",
        tags     = { "depot" },
        color    = { 0.55, 0.45, 0.30 },
        tip      = "Compare how many vehicles are currently at the depot.",
        params   = {
            { key = "op",    type = "enum",   options = { ">", "<", ">=", "<=", "!=", "=" }, default = ">" },
            { key = "value", type = "number", default = 3, step = 1, min = 0 },
        },
        build = function(p)
            return compare_node(get_slot("depot", "vehicle_count"), p.op, p.value)
        end },

    {   id       = "pref_check_client_count",
        label    = "Client count",
        kind     = "bool",
        category = "condition",
        tags     = { "client" },
        color    = { 0.50, 0.38, 0.65 },
        tip      = "Compare the total number of registered clients.",
        params   = {
            { key = "op",    type = "enum",   options = { ">", "<", ">=", "<=", "!=", "=" }, default = ">" },
            { key = "value", type = "number", default = 1, step = 1, min = 0 },
        },
        build = function(p)
            return compare_node(get_slot("client", "count"), p.op, p.value)
        end },

    {   id       = "pref_check_active_clients",
        label    = "Active client count",
        kind     = "bool",
        category = "condition",
        tags     = { "client" },
        color    = { 0.50, 0.38, 0.65 },
        tip      = "Compare how many clients are currently active (not paused).",
        params   = {
            { key = "op",    type = "enum",   options = { ">", "<", ">=", "<=", "!=", "=" }, default = ">" },
            { key = "value", type = "number", default = 1, step = 1, min = 0 },
        },
        build = function(p)
            return compare_node(get_slot("client", "active_count"), p.op, p.value)
        end },

    {   id       = "pref_check_fleet_count",
        label    = "Fleet count",
        kind     = "bool",
        category = "condition",
        tags     = { "vehicle", "game" },
        color    = { 0.28, 0.72, 0.58 },
        tip      = "Compare the total number of vehicles of a given type.",
        params   = {
            { key = "vehicle_type", type = "vehicle_enum", default = "any" },
            { key = "op",           type = "enum",   options = { ">", "<", ">=", "<=", "!=", "=" }, default = ">" },
            { key = "n",            type = "number", default = 1, step = 1, min = 0 },
        },
        build = function(p)
            return compare_node(
                get_slot("fleet", "count", { vehicle_type = p.vehicle_type }),
                p.op, p.n)
        end },

}
