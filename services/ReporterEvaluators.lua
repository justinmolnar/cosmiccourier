-- services/ReporterEvaluators.lua
-- Evaluator functions for reporter blocks.
-- Reporter evaluator: function(node, ctx) → number | string
-- Use evalSlot() to allow inputs to themselves be reporters.

local function evalSlot(val, ctx)
    if type(val) == "table" and val.kind == "reporter" then
        return require("services.DispatchRuleEngine").evalReporter(val.node, ctx)
    end
    return val
end

local function n(v) return tonumber(v) or 0 end
local function s(v) return tostring(v or "") end

-- ── Game / global reporters ───────────────────────────────────────────────────

local function rep_money(node, ctx)
    return ctx.game.state.money or 0
end

local function rep_queue_count(node, ctx)
    return #ctx.game.entities.trips.pending
end

local function rep_trips_completed(node, ctx)
    return ctx.game.state.trips_completed or 0
end

local function rep_rush_hour_remaining(node, ctx)
    local rh = ctx.game.state.rush_hour
    return (rh and rh.active and rh.timer) or 0
end

local function rep_counter(node, ctx)
    return ctx.game.state.counters[node.slots.key or "A"] or 0
end

local function rep_flag(node, ctx)
    return ctx.game.state.flags[node.slots.key or "X"] and 1 or 0
end

local function rep_text_var(node, ctx)
    return ctx.game.state.text_vars[node.slots.key or "A"] or ""
end

-- ── Fleet reporters ───────────────────────────────────────────────────────────

local function rep_vehicle_count(node, ctx)
    local want  = (node.slots.vehicle_type or ""):lower()
    local count = 0
    for _, v in ipairs(ctx.game.entities.vehicles) do
        if (v.type or ""):lower() == want then count = count + 1 end
    end
    return count
end

local function rep_idle_count(node, ctx)
    local want  = (node.slots.vehicle_type or ""):lower()
    local count = 0
    for _, v in ipairs(ctx.game.entities.vehicles) do
        if (v.type or ""):lower() == want and v.state and v.state.name == "Idle" then
            count = count + 1
        end
    end
    return count
end

-- ── Trip context reporters ────────────────────────────────────────────────────

local function rep_trip_payout(node, ctx)
    return (ctx.trip and ctx.trip.base_payout) or 0
end

local function rep_trip_wait(node, ctx)
    return (ctx.trip and ctx.trip.wait_time) or 0
end

local function rep_trip_bonus(node, ctx)
    return (ctx.trip and ctx.trip.speed_bonus) or 0
end

local function rep_trip_leg_count(node, ctx)
    return (ctx.trip and #ctx.trip.legs) or 0
end

-- ── Vehicle context reporters ─────────────────────────────────────────────────

local function rep_this_vehicle_speed(node, ctx)
    return (ctx.vehicle and ctx.vehicle:getSpeed()) or 0
end

local function rep_this_vehicle_trips(node, ctx)
    return (ctx.vehicle and ctx.vehicle.trips_completed) or 0
end

-- ── Math operators ────────────────────────────────────────────────────────────

local function rep_add(node, ctx)
    return n(evalSlot(node.slots.a, ctx)) + n(evalSlot(node.slots.b, ctx))
end

local function rep_sub(node, ctx)
    return n(evalSlot(node.slots.a, ctx)) - n(evalSlot(node.slots.b, ctx))
end

local function rep_mul(node, ctx)
    return n(evalSlot(node.slots.a, ctx)) * n(evalSlot(node.slots.b, ctx))
end

local function rep_div(node, ctx)
    local bv = n(evalSlot(node.slots.b, ctx))
    if bv == 0 then return 0 end
    return n(evalSlot(node.slots.a, ctx)) / bv
end

local function rep_mod(node, ctx)
    local bv = n(evalSlot(node.slots.b, ctx))
    if bv == 0 then return 0 end
    return n(evalSlot(node.slots.a, ctx)) % bv
end

local function rep_round(node, ctx)
    return math.floor(n(evalSlot(node.slots.a, ctx)) + 0.5)
end

local function rep_abs(node, ctx)
    return math.abs(n(evalSlot(node.slots.a, ctx)))
end

local function rep_min(node, ctx)
    return math.min(n(evalSlot(node.slots.a, ctx)), n(evalSlot(node.slots.b, ctx)))
end

local function rep_max(node, ctx)
    return math.max(n(evalSlot(node.slots.a, ctx)), n(evalSlot(node.slots.b, ctx)))
end

local function rep_random(node, ctx)
    local a = math.max(1, math.floor(n(evalSlot(node.slots.a, ctx))))
    local b = math.max(1, math.floor(n(evalSlot(node.slots.b, ctx))))
    if a > b then a, b = b, a end
    return love.math.random(a, b)
end

-- ── String operators ──────────────────────────────────────────────────────────

local function rep_join(node, ctx)
    return s(evalSlot(node.slots.a, ctx)) .. s(evalSlot(node.slots.b, ctx))
end

local function rep_length(node, ctx)
    return #s(evalSlot(node.slots.a, ctx))
end

local function rep_num_to_text(node, ctx)
    return tostring(n(evalSlot(node.slots.a, ctx)))
end

local function rep_text_to_num(node, ctx)
    return tonumber(s(evalSlot(node.slots.a, ctx))) or 0
end

local function rep_upper(node, ctx)
    return s(evalSlot(node.slots.a, ctx)):upper()
end

local function rep_lower(node, ctx)
    return s(evalSlot(node.slots.a, ctx)):lower()
end

-- ─────────────────────────────────────────────────────────────────────────────

return {
    rep_money               = rep_money,
    rep_queue_count         = rep_queue_count,
    rep_trips_completed     = rep_trips_completed,
    rep_rush_hour_remaining = rep_rush_hour_remaining,
    rep_counter             = rep_counter,
    rep_flag                = rep_flag,
    rep_text_var            = rep_text_var,
    rep_vehicle_count       = rep_vehicle_count,
    rep_idle_count          = rep_idle_count,
    rep_trip_payout         = rep_trip_payout,
    rep_trip_wait           = rep_trip_wait,
    rep_trip_bonus          = rep_trip_bonus,
    rep_trip_leg_count      = rep_trip_leg_count,
    rep_this_vehicle_speed  = rep_this_vehicle_speed,
    rep_this_vehicle_trips  = rep_this_vehicle_trips,
    rep_add                 = rep_add,
    rep_sub                 = rep_sub,
    rep_mul                 = rep_mul,
    rep_div                 = rep_div,
    rep_mod                 = rep_mod,
    rep_round               = rep_round,
    rep_abs                 = rep_abs,
    rep_min                 = rep_min,
    rep_max                 = rep_max,
    rep_random              = rep_random,
    rep_join                = rep_join,
    rep_length              = rep_length,
    rep_num_to_text         = rep_num_to_text,
    rep_text_to_num         = rep_text_to_num,
    rep_upper               = rep_upper,
    rep_lower               = rep_lower,
}
