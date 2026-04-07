-- services/DispatchEvaluators.lua
-- All block evaluator functions, keyed by the "evaluator" field in dispatch_blocks.lua.
-- This is the ONLY file that knows about specific block behaviour.
-- The engine (DispatchRuleEngine) calls these generically by key.
--
-- Condition evaluator: function(block_inst, ctx) → bool
-- Effect evaluator:    function(block_inst, ctx) → false   (side-effect; trip not claimed)
-- Action evaluator:    function(block_inst, ctx) → "claimed" | "skip" | "cancel" | false

local TripEligibility = require("services.TripEligibilityService")

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function counters(game) return game.state.counters end
local function flags(game)    return game.state.flags    end

local function idle_of_type(game, vtype)
    local list = {}
    for _, v in ipairs(game.entities.vehicles) do
        if (v.type or ""):lower() == vtype and v.state and v.state.name == "Idle" then
            list[#list + 1] = v
        end
    end
    return list
end

-- ── Conditions: Trip ─────────────────────────────────────────────────────────

local function scope_equals(block, ctx)
    return ctx.trip.scope == (block.slots.scope or "district")
end

local function scope_not_equals(block, ctx)
    return ctx.trip.scope ~= (block.slots.scope or "district")
end

local function payout_gt(block, ctx)
    return ctx.trip.base_payout > (block.slots.value or 0)
end

local function payout_lt(block, ctx)
    return ctx.trip.base_payout < (block.slots.value or 0)
end

local function payout_between(block, ctx)
    local p = ctx.trip.base_payout
    return p >= (block.slots.min or 0) and p <= (block.slots.max or math.huge)
end

local function wait_gt(block, ctx)
    return (ctx.trip.wait_time or 0) > (block.slots.seconds or 0)
end

local function wait_lt(block, ctx)
    return (ctx.trip.wait_time or 0) < (block.slots.seconds or 0)
end

local function is_multi_leg(block, ctx)
    return #ctx.trip.legs > 1
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

local function vehicle_idle_count_gt(block, ctx)
    local want = (block.slots.vehicle_type or ""):lower()
    local n    = block.slots.n or 0
    local count = 0
    for _, v in ipairs(ctx.game.entities.vehicles) do
        if (v.type or ""):lower() == want
           and TripEligibility.canAssign(v, ctx.trip, ctx.game) then
            count = count + 1
            if count > n then return true end
        end
    end
    return false
end

-- ── Conditions: Game state ────────────────────────────────────────────────────

local function queue_gt(block, ctx)
    return #ctx.game.entities.trips.pending > (block.slots.value or 0)
end

local function queue_lt(block, ctx)
    return #ctx.game.entities.trips.pending < (block.slots.value or 0)
end

local function money_gt(block, ctx)
    return ctx.game.state.money > (block.slots.value or 0)
end

local function money_lt(block, ctx)
    return ctx.game.state.money < (block.slots.value or 0)
end

local function rush_hour_active(block, ctx)
    local rh = ctx.game.state.rush_hour
    return rh and rh.active or false
end

-- ── Conditions: Counters & Flags ──────────────────────────────────────────────

local function counter_gt(block, ctx)
    local k = block.slots.key or "A"
    return (counters(ctx.game)[k] or 0) > (block.slots.value or 0)
end

local function counter_lt(block, ctx)
    local k = block.slots.key or "A"
    return (counters(ctx.game)[k] or 0) < (block.slots.value or 0)
end

local function counter_eq(block, ctx)
    local k = block.slots.key or "A"
    return (counters(ctx.game)[k] or 0) == (block.slots.value or 0)
end

local function flag_is_set(block, ctx)
    local k = block.slots.key or "X"
    return flags(ctx.game)[k] == true
end

local function flag_is_clear(block, ctx)
    local k = block.slots.key or "X"
    return not flags(ctx.game)[k]
end

-- ── Effects: Counters & Flags ─────────────────────────────────────────────────
-- These return false so the rule continues to the next block.

local function counter_add(block, ctx)
    local k = block.slots.key or "A"
    local n = block.slots.amount or 1
    local c = counters(ctx.game)
    c[k] = (c[k] or 0) + n
    return false
end

local function counter_sub(block, ctx)
    local k = block.slots.key or "A"
    local n = block.slots.amount or 1
    local c = counters(ctx.game)
    c[k] = (c[k] or 0) - n
    return false
end

local function counter_reset(block, ctx)
    local k = block.slots.key or "A"
    counters(ctx.game)[k] = 0
    return false
end

local function flag_set(block, ctx)
    local k = block.slots.key or "X"
    flags(ctx.game)[k] = true
    return false
end

local function flag_clear(block, ctx)
    local k = block.slots.key or "X"
    flags(ctx.game)[k] = false
    return false
end

-- ── Actions: Assignment ───────────────────────────────────────────────────────

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

-- Assign the eligible vehicle of the given type that is closest to the pickup.
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

-- ── Actions: Flow ─────────────────────────────────────────────────────────────

local function skip(block, ctx)
    return "skip"
end

local function cancel_trip(block, ctx)
    return "cancel"
end

-- ─────────────────────────────────────────────────────────────────────────────

return {
    -- Conditions: trip
    scope_equals        = scope_equals,
    scope_not_equals    = scope_not_equals,
    payout_gt           = payout_gt,
    payout_lt           = payout_lt,
    payout_between      = payout_between,
    wait_gt             = wait_gt,
    wait_lt             = wait_lt,
    is_multi_leg        = is_multi_leg,

    -- Conditions: vehicles
    vehicle_idle_any    = vehicle_idle_any,
    vehicle_idle_none   = vehicle_idle_none,
    vehicle_idle_count_gt = vehicle_idle_count_gt,

    -- Conditions: game state
    queue_gt            = queue_gt,
    queue_lt            = queue_lt,
    money_gt            = money_gt,
    money_lt            = money_lt,
    rush_hour_active    = rush_hour_active,

    -- Conditions: counters & flags
    counter_gt          = counter_gt,
    counter_lt          = counter_lt,
    counter_eq          = counter_eq,
    flag_is_set         = flag_is_set,
    flag_is_clear       = flag_is_clear,

    -- Effects: counters & flags
    counter_add         = counter_add,
    counter_sub         = counter_sub,
    counter_reset       = counter_reset,
    flag_set            = flag_set,
    flag_clear          = flag_clear,

    -- Actions
    assign_vehicle_type = assign_vehicle_type,
    assign_any          = assign_any,
    assign_nearest      = assign_nearest,
    skip                = skip,
    cancel_trip         = cancel_trip,
}
