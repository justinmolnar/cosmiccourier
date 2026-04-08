-- services/DispatchEvaluators.lua
-- All block evaluator functions, keyed by the "evaluator" field in dispatch_blocks.lua.
--
-- Condition evaluator: function(block_inst, ctx) → bool
-- Effect evaluator:    function(block_inst, ctx) → false   (side-effect; trip not claimed)
-- Action evaluator:    function(block_inst, ctx) → "claimed" | "skip" | "cancel" | false

local TripEligibility = require("services.TripEligibilityService")

-- ── Helpers ───────────────────────────────────────────────────────────────────

-- Resolve a slot value: if it's a reporter node, evaluate it; otherwise return raw.
local function evalSlot(val, ctx)
    if type(val) == "table" and val.kind == "reporter" then
        return require("services.DispatchRuleEngine").evalReporter(val.node, ctx)
    end
    return val
end

-- Unified variable system access
local function getVar(game, key)
    return game.state.vars[key]
end

local function setVar(game, key, val)
    game.state.vars[key] = val
end

-- Generic comparison operator. Supports all 6 operators.
local function cmp(a, op, b)
    if     op == ">"  then return a >  b
    elseif op == "<"  then return a <  b
    elseif op == ">=" then return a >= b
    elseif op == "<=" then return a <= b
    elseif op == "!=" then return a ~= b
    else                   return a == b   -- "="
    end
end

-- ── Find ──────────────────────────────────────────────────────────────────────

local function find_match(block, ctx)
    local Collections = require("data.dispatch_collections")
    local Sorters     = require("data.dispatch_sorters")
    local RE          = require("services.DispatchRuleEngine")

    local col_id  = block.slots.collection
    local sort_id = block.slots.sorter
    local out_key = block.slots.output_var or "found"

    -- Find registries
    local col, sort = nil, nil
    for _, c in ipairs(Collections) do if c.id == col_id then col = c; break end end
    for _, s in ipairs(Sorters)     do if s.id == sort_id then sort = s; break end end

    if not col or not sort then return false end

    local items = col.read(ctx, block.slots)
    if not items then return false end

    -- Apply filter (the block's nested boolean condition)
    local filtered = {}
    for _, item in ipairs(items) do
        -- Bind the current item to the collection's ctx_key (e.g. 'vehicle' or 'trip')
        -- Preserve other context (game, current trip)
        local inner_ctx = { game = ctx.game, trip = ctx.trip }
        inner_ctx[col.ctx_key] = item

        if not block.condition or RE.evalBoolNode(block.condition, inner_ctx) then
            filtered[#filtered+1] = item
        end
    end

    if #filtered == 0 then return false end

    -- Sort and pick best
    table.sort(filtered, function(a, b)
        local sa = sort.score(a, ctx)
        local sb = sort.score(b, ctx)
        if sort.order == "asc" then
            return sa < sb
        else
            return sa > sb
        end
    end)

    local best = filtered[1]
    if out_key ~= "" then
        setVar(ctx.game, out_key, best)
    end

    -- ── Execute body with best match in context ─────────────────────────────
    local inner_ctx = { 
        game       = ctx.game, 
        trip       = ctx.trip, 
        vehicle    = ctx.vehicle,
        _rule_id   = ctx._rule_id, 
        _call_depth = (ctx._call_depth or 0) 
    }
    inner_ctx[col.ctx_key] = best

    return RE.evalStack(block.body, inner_ctx)
end

-- ── Conditions: Trip ─────────────────────────────────────────────────────────

local SCOPE_RANK = { district=1, city=2, region=3, continent=4, world=5 }

local function scope_equals(block, ctx)
    return ctx.trip.scope == (block.slots.scope or "district")
end

local function scope_not_equals(block, ctx)
    return ctx.trip.scope ~= (block.slots.scope or "district")
end

local function payout_compare(block, ctx)
    return cmp(ctx.trip.base_payout, block.slots.op or ">", evalSlot(block.slots.value, ctx) or 0)
end

local function wait_compare(block, ctx)
    return cmp(ctx.trip.wait_time or 0, block.slots.op or ">", evalSlot(block.slots.seconds, ctx) or 0)
end

local function is_multi_leg(block, ctx)
    return #ctx.trip.legs > 1
end

local function leg_count(block, ctx)
    return cmp(#ctx.trip.legs, block.slots.op or ">", evalSlot(block.slots.value, ctx) or 1)
end

local function cargo_size(block, ctx)
    local leg = ctx.trip.legs[ctx.trip.current_leg or 1]
    return cmp(leg and leg.cargo_size or 1, block.slots.op or ">", evalSlot(block.slots.value, ctx) or 1)
end

local function trip_bonus(block, ctx)
    return cmp(ctx.trip.speed_bonus or 0, block.slots.op or ">", evalSlot(block.slots.value, ctx) or 0)
end

-- ── Conditions: Vehicle availability ────────────────────────────────────────

local function vehicle_idle_any(block, ctx)
    local want = (block.slots.vehicle_type or ""):lower()
    for _, v in ipairs(ctx.game.entities.vehicles) do
        if (v.type or ""):lower() == want
           and TripEligibility.canAssign(v, ctx.trip, ctx.game) then
            return true
        end
    end
    return false
end

local function vehicle_idle_none(block, ctx)
    local want = (block.slots.vehicle_type or ""):lower()
    for _, v in ipairs(ctx.game.entities.vehicles) do
        if (v.type or ""):lower() == want
           and TripEligibility.canAssign(v, ctx.trip, ctx.game) then
            return false
        end
    end
    return true
end

local function idle_count_compare(block, ctx)
    local op = block.slots.op or ">"
    local n  = tonumber(evalSlot(block.slots.value, ctx)) or 0
    local idle_count = 0
    for _, v in ipairs(ctx.game.entities.vehicles) do
        if TripEligibility.canAssign(v, ctx.trip, ctx.game) then
            idle_count = idle_count + 1
        end
    end
    return cmp(idle_count, op, n)
end

local function fleet_util(block, ctx)
    local op = block.slots.op or ">"
    local val = tonumber(evalSlot(block.slots.value, ctx)) or 0
    local total = #ctx.game.entities.vehicles
    if total == 0 then return false end
    local idle = 0
    for _, v in ipairs(ctx.game.entities.vehicles) do
        if TripEligibility.canAssign(v, ctx.trip, ctx.game) then idle = idle + 1 end
    end
    local fleet_pct = (1 - (idle / total)) * 100
    return cmp(fleet_pct, op, val)
end

-- ── Conditions: Game state ───────────────────────────────────────────────────

local function queue_compare(block, ctx)
    return cmp(#ctx.game.entities.trips.pending, block.slots.op or ">", evalSlot(block.slots.value, ctx) or 0)
end

local function money_compare(block, ctx)
    return cmp(ctx.game.state.money, block.slots.op or ">", evalSlot(block.slots.value, ctx) or 0)
end

local function upgrade_purchased(block, ctx)
    local id = block.slots.upgrade_id or ""
    return ctx.game.state.upgrades[id] ~= nil
end

local function counter_compare(block, ctx)
    local val = getVar(ctx.game, block.slots.key or "") or 0
    return cmp(tonumber(val) or 0, block.slots.op or ">", evalSlot(block.slots.value, ctx) or 0)
end

local function flag_is_set(block, ctx)
    return getVar(ctx.game, block.slots.key or "") == true
end

local function flag_is_clear(block, ctx)
    return getVar(ctx.game, block.slots.key or "") ~= true
end

local function random_chance(block, ctx)
    local pct = tonumber(evalSlot(block.slots.percent, ctx)) or 50
    return (math.random() * 100) < pct
end

local function rush_hour_active(block, ctx)
    return ctx.game.world_sandbox and ctx.game.world_sandbox.is_rush_hour
end

local function always_true(block, ctx)  return true end
local function always_false(block, ctx) return false end

-- ── Actions: Effects ─────────────────────────────────────────────────────────

local function add_money(block, ctx)
    local amt = tonumber(evalSlot(block.slots.amount, ctx)) or 0
    ctx.game.state.money = ctx.game.state.money + amt
    return false
end

local function subtract_money(block, ctx)
    local amt = tonumber(evalSlot(block.slots.amount, ctx)) or 0
    ctx.game.state.money = ctx.game.state.money - amt
    return false
end

local function set_counter(block, ctx)
    local val = tonumber(evalSlot(block.slots.value, ctx)) or 0
    setVar(ctx.game, block.slots.key or "", val)
    return false
end

local function adjust_counter(block, ctx)
    local key = block.slots.key or ""
    local val = tonumber(getVar(ctx.game, key)) or 0
    local amt = tonumber(evalSlot(block.slots.amount, ctx)) or 0
    setVar(ctx.game, key, val + amt)
    return false
end

local function set_flag(block, ctx)
    setVar(ctx.game, block.slots.key or "", true)
    return false
end

local function clear_flag(block, ctx)
    setVar(ctx.game, block.slots.key or "", false)
    return false
end

local function counter_mod(block, ctx)
    local key = block.slots.key or ""
    local val = tonumber(getVar(ctx.game, key)) or 0
    local mod = tonumber(evalSlot(block.slots.mod, ctx)) or 1
    setVar(ctx.game, key, val % mod)
    return false
end

local function text_var_set(block, ctx)
    local val = evalSlot(block.slots.value, ctx)
    setVar(ctx.game, block.slots.key or "", tostring(val or ""))
    return false
end

local function text_var_append(block, ctx)
    local key = block.slots.key or ""
    local cur = tostring(getVar(ctx.game, key) or "")
    local val = evalSlot(block.slots.value, ctx)
    setVar(ctx.game, key, cur .. tostring(val or ""))
    return false
end

local function text_var_eq(block, ctx)
    local cur = tostring(getVar(ctx.game, block.slots.key or "") or "")
    local val = evalSlot(block.slots.value, ctx)
    return cur == tostring(val or "")
end

local function text_var_contains(block, ctx)
    local cur = tostring(getVar(ctx.game, block.slots.key or "") or "")
    local val = tostring(evalSlot(block.slots.value, ctx) or "")
    return cur:find(val, 1, true) ~= nil
end

local function play_sound(block, ctx)
    local Sound = require("services.SoundService")
    Sound.play(block.slots.sound or "click")
    return false
end

local function screen_shake(block, ctx)
    local amt = tonumber(evalSlot(block.slots.amount, ctx)) or 5
    if ctx.game.camera then ctx.game.camera:shake(amt) end
    return false
end

local function notify(block, ctx)
    local msg = tostring(evalSlot(block.slots.message, ctx))
    local EventService = require("services.EventService")
    EventService.publish("ui_notify", { text = msg, type = block.slots.type or "info" })
    return false
end

-- ── Actions: Standard ─────────────────────────────────────────────────────────

local function assign_vehicle_type(block, ctx)
    local want = (block.slots.vehicle_type or ""):lower()
    for _, v in ipairs(ctx.game.entities.vehicles) do
        if (v.type or ""):lower() == want
           and TripEligibility.canAssign(v, ctx.trip, ctx.game) then
            v:assignTrip(ctx.trip, ctx.game)
            return "claimed"
        end
    end
    return false
end

local function assign_any(block, ctx)
    for _, v in ipairs(ctx.game.entities.vehicles) do
        if TripEligibility.canAssign(v, ctx.trip, ctx.game) then
            v:assignTrip(ctx.trip, ctx.game)
            return "claimed"
        end
    end
    return false
end

local function assign_nearest(block, ctx)
    local want = (block.slots.vehicle_type or ""):lower()
    local leg  = ctx.trip.legs[ctx.trip.current_leg]
    local sx   = leg and leg.start_plot and leg.start_plot.x or 0
    local sy   = leg and leg.start_plot and leg.start_plot.y or 0

    local best_v, best_d2 = nil, math.huge
    for _, v in ipairs(ctx.game.entities.vehicles) do
        if (v.type or ""):lower() == want
           and TripEligibility.canAssign(v, ctx.trip, ctx.game) then
            local ax = v.grid_anchor and v.grid_anchor.x or 0
            local ay = v.grid_anchor and v.grid_anchor.y or 0
            local d2 = (ax - sx)^2 + (ay - sy)^2
            if d2 < best_d2 then best_d2 = d2; best_v = v end
        end
    end

    if best_v then
        best_v:assignTrip(ctx.trip, ctx.game)
        return "claimed"
    end
    return false
end

local function skip(block, ctx)
    return "skip"
end

-- ── Actions: Smart assignment ─────────────────────────────────────────────────

local function assign_fastest(block, ctx)
    local want = (block.slots.vehicle_type or ""):lower()
    local eligible = {}
    for _, v in ipairs(ctx.game.entities.vehicles) do
        if (v.type or ""):lower() == want
           and TripEligibility.canAssign(v, ctx.trip, ctx.game) then
            eligible[#eligible+1] = v
        end
    end
    if #eligible == 0 then return false end
    table.sort(eligible, function(a, b) return a:getSpeed() > b:getSpeed() end)
    eligible[1]:assignTrip(ctx.trip, ctx.game)
    return "claimed"
end

local function assign_most_capacity(block, ctx)
    local want = (block.slots.vehicle_type or ""):lower()
    local eligible = {}
    for _, v in ipairs(ctx.game.entities.vehicles) do
        if (v.type or ""):lower() == want
           and TripEligibility.canAssign(v, ctx.trip, ctx.game) then
            eligible[#eligible+1] = v
        end
    end
    if #eligible == 0 then return false end
    table.sort(eligible, function(a, b)
        return a:getEffectiveCapacity(ctx.game) > b:getEffectiveCapacity(ctx.game)
    end)
    eligible[1]:assignTrip(ctx.trip, ctx.game)
    return "claimed"
end

local function assign_least_recent(block, ctx)
    local want = (block.slots.vehicle_type or ""):lower()
    local eligible = {}
    for _, v in ipairs(ctx.game.entities.vehicles) do
        if (v.type or ""):lower() == want
           and TripEligibility.canAssign(v, ctx.trip, ctx.game) then
            eligible[#eligible+1] = v
        end
    end
    if #eligible == 0 then return false end
    table.sort(eligible, function(a, b)
        return (a.last_trip_end_time or 0) < (b.last_trip_end_time or 0)
    end)
    eligible[1]:assignTrip(ctx.trip, ctx.game)
    return "claimed"
end

-- ── Vehicle contexts ──────────────────────────────────────────────────────────

local function this_vehicle_type(block, ctx)
    if not ctx.vehicle then return false end
    return (ctx.vehicle.type or ""):lower() == (block.slots.type or ""):lower()
end

local function this_vehicle_speed(block, ctx)
    if not ctx.vehicle then return false end
    return cmp(ctx.vehicle:getSpeed(), block.slots.op or ">", evalSlot(block.slots.value, ctx) or 0)
end

local function this_vehicle_trips(block, ctx)
    if not ctx.vehicle then return false end
    return cmp(ctx.vehicle.trips_completed or 0, block.slots.op or ">", evalSlot(block.slots.value, ctx) or 0)
end

local function this_vehicle_idle(block, ctx)
    if not ctx.vehicle then return false end
    return ctx.vehicle.state == "idle"
end

local function assign_ctx(block, ctx)
    if not ctx.vehicle or not ctx.trip then return false end
    if TripEligibility.canAssign(ctx.vehicle, ctx.trip, ctx.game) then
        ctx.vehicle:assignTrip(ctx.trip, ctx.game)
        return "claimed"
    end
    return false
end

local function fire_vehicle(block, ctx)
    if not ctx.vehicle then return false end
    ctx.game.entities:removeVehicle(ctx.vehicle)
    return "cancel" -- If vehicle was fired while on a trip, cancel the trip
end

-- ── Depot context ────────────────────────────────────────────────────────────

local function depot_open(block, ctx)
    return ctx.game.state.depot_open == true
end

local function depot_vehicle_count(block, ctx)
    return cmp(#ctx.game.entities.vehicles, block.slots.op or ">", evalSlot(block.slots.value, ctx) or 0)
end

local function open_depot(block, ctx)
    ctx.game.state.depot_open = true
    return false
end

local function close_depot(block, ctx)
    ctx.game.state.depot_open = false
    return false
end

local function rename_depot(block, ctx)
    ctx.game.state.depot_name = tostring(evalSlot(block.slots.name, ctx))
    return false
end

-- ── Client contexts ──────────────────────────────────────────────────────────

local function client_count(block, ctx)
    return cmp(#ctx.game.entities.clients, block.slots.op or ">", evalSlot(block.slots.value, ctx) or 0)
end

local function active_client_count(block, ctx)
    local count = 0
    for _, c in ipairs(ctx.game.entities.clients) do if not c.paused then count = count + 1 end end
    return cmp(count, block.slots.op or ">", evalSlot(block.slots.value, ctx) or 0)
end

-- ── Procedures ───────────────────────────────────────────────────────────────

local function block_call_proc(block, ctx)
    local name = block.slots.name or ""
    local RE   = require("services.DispatchRuleEngine")
    for _, rule in ipairs(ctx.game.state.dispatch_rules) do
        if rule.isProcedure and rule.procedure_name == name then
            local result = RE.evaluate(rule, ctx.game, ctx.trip, ctx.vehicle)
            if result then return result end
        end
    end
    return false
end

-- ── Internal math/string reporters (seed) ────────────────────────────────────

local function bool_compare(block, ctx)
    local lv = tonumber(evalSlot(block.slots.left,  ctx)) or 0
    local rv = tonumber(evalSlot(block.slots.right, ctx)) or 0
    return cmp(lv, block.slots.op or ">", rv)
end

-- ── Exports ──────────────────────────────────────────────────────────────────

return {
    scope_equals         = scope_equals,
    scope_not_equals     = scope_not_equals,
    payout_compare       = payout_compare,
    wait_compare         = wait_compare,
    is_multi_leg         = is_multi_leg,
    leg_count            = leg_count,
    cargo_size           = cargo_size,
    trip_bonus           = trip_bonus,

    vehicle_idle_any     = vehicle_idle_any,
    vehicle_idle_none    = vehicle_idle_none,
    idle_count_compare   = idle_count_compare,
    fleet_util           = fleet_util,

    queue_compare        = queue_compare,
    money_compare        = money_compare,
    upgrade_purchased    = upgrade_purchased,
    counter_compare      = counter_compare,
    flag_is_set          = flag_is_set,
    flag_is_clear        = flag_is_clear,
    random_chance        = random_chance,
    rush_hour_active     = rush_hour_active,
    always_true          = always_true,
    always_false         = always_false,

    add_money            = add_money,
    subtract_money       = subtract_money,
    set_counter          = set_counter,
    adjust_counter       = adjust_counter,
    set_flag             = set_flag,
    clear_flag           = clear_flag,
    counter_mod          = counter_mod,
    text_var_set         = text_var_set,
    text_var_append      = text_var_append,
    text_var_eq          = text_var_eq,
    text_var_contains    = text_var_contains,
    play_sound           = play_sound,
    screen_shake         = screen_shake,
    notify               = notify,

    assign_vehicle_type  = assign_vehicle_type,
    assign_any           = assign_any,
    assign_nearest       = assign_nearest,
    skip                 = skip,

    prioritize_trip      = prioritize_trip,
    deprioritize_trip    = deprioritize_trip,
    sort_queue           = sort_queue,
    cancel_all_scope     = cancel_all_scope,
    cancel_all_wait      = cancel_all_wait,

    -- Actions: smart assignment
    assign_fastest       = assign_fastest,
    assign_most_capacity = assign_most_capacity,
    assign_least_recent  = assign_least_recent,

    find_match           = find_match,

    this_vehicle_type    = this_vehicle_type,
    this_vehicle_speed   = this_vehicle_speed,
    this_vehicle_trips   = this_vehicle_trips,
    this_vehicle_idle    = this_vehicle_idle,
    assign_ctx           = assign_ctx,
    fire_vehicle         = fire_vehicle,

    depot_open           = depot_open,
    depot_vehicle_count  = depot_vehicle_count,
    open_depot           = open_depot,
    close_depot          = close_depot,
    rename_depot         = rename_depot,

    client_count         = client_count,
    active_client_count  = active_client_count,

    block_call_proc      = block_call_proc,
    bool_compare         = bool_compare,
}
