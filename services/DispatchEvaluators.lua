-- services/DispatchEvaluators.lua
-- All block evaluator functions, keyed by the "evaluator" field in dispatch_blocks.lua.
--
-- Condition evaluator: function(block_inst, ctx) → bool
-- Effect evaluator:    function(block_inst, ctx) → false   (side-effect; trip not claimed)
-- Action evaluator:    function(block_inst, ctx) → "claimed" | "skip" | "cancel" | false

local TripEligibility = require("services.TripEligibilityService")

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function counters(game) return game.state.counters end
local function flags(game)    return game.state.flags    end
local function text_vars(game) return game.state.text_vars end

-- Resolve a slot value: if it's a reporter node, evaluate it; otherwise return raw.
local function evalSlot(val, ctx)
    if type(val) == "table" and val.kind == "reporter" then
        return require("services.DispatchRuleEngine").evalReporter(val.node, ctx)
    end
    return val
end

-- Generic comparison: op is ">", "<", or "="
local function cmp(a, op, b)
    if op == ">" then return a > b
    elseif op == "<" then return a < b
    else return a == b
    end
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
    local want  = (block.slots.vehicle_type or ""):lower()
    local count = 0
    for _, v in ipairs(ctx.game.entities.vehicles) do
        if (v.type or ""):lower() == want
           and TripEligibility.canAssign(v, ctx.trip, ctx.game) then
            count = count + 1
        end
    end
    return cmp(count, block.slots.op or ">", evalSlot(block.slots.n, ctx) or 0)
end

-- ── Conditions: Fleet ────────────────────────────────────────────────────────

local function fleet_util(block, ctx)
    local vehicles = ctx.game.entities.vehicles
    local threshold = evalSlot(block.slots.value, ctx) or 50
    if #vehicles == 0 then
        return cmp(0, block.slots.op or ">", threshold)
    end
    local non_idle = 0
    for _, v in ipairs(vehicles) do
        if (v.state or "Idle") ~= "Idle" then non_idle = non_idle + 1 end
    end
    local pct = math.floor(non_idle / #vehicles * 100)
    return cmp(pct, block.slots.op or ">", threshold)
end

-- ── Conditions: Game state ────────────────────────────────────────────────────

local function queue_compare(block, ctx)
    return cmp(#ctx.game.entities.trips.pending, block.slots.op or ">", evalSlot(block.slots.value, ctx) or 0)
end

local function money_compare(block, ctx)
    return cmp(ctx.game.state.money, block.slots.op or ">", evalSlot(block.slots.value, ctx) or 0)
end

local function rush_hour_active(block, ctx)
    local rh = ctx.game.state.rush_hour
    return rh and rh.active or false
end

local function upgrade_purchased(block, ctx)
    local name = block.slots.name or ""
    return (ctx.game.state.upgrades_purchased or {})[name] and true or false
end

-- ── Conditions: Counters & Flags ──────────────────────────────────────────────

local function counter_compare(block, ctx)
    local k = block.slots.key or "A"
    return cmp(counters(ctx.game)[k] or 0, block.slots.op or ">", evalSlot(block.slots.value, ctx) or 0)
end

local function flag_is_set(block, ctx)
    local k = block.slots.key or "X"
    return flags(ctx.game)[k] == true
end

local function flag_is_clear(block, ctx)
    local k = block.slots.key or "X"
    return not flags(ctx.game)[k]
end

local function random_chance(block, ctx)
    return love.math.random(100) <= (block.slots.pct or 50)
end

local function always_true(block, ctx)  return true  end
local function always_false(block, ctx) return false end

local function counter_mod(block, ctx)
    local k = block.slots.key or "A"
    local m = tonumber(evalSlot(block.slots.m, ctx)) or 2
    local r = tonumber(evalSlot(block.slots.r, ctx)) or 0
    if m == 0 then return false end
    return (counters(ctx.game)[k] or 0) % m == r
end

-- ── Effects: Trip mutation ────────────────────────────────────────────────────

local function set_payout(block, ctx)
    ctx.trip.base_payout = math.max(0, tonumber(evalSlot(block.slots.value, ctx)) or 100)
    return false
end

local function add_bonus(block, ctx)
    ctx.trip.speed_bonus = (ctx.trip.speed_bonus or 0) + (tonumber(evalSlot(block.slots.value, ctx)) or 50)
    return false
end

-- ── Effects: Economy ─────────────────────────────────────────────────────────

local function add_money(block, ctx)
    ctx.game.state.money = ctx.game.state.money + (tonumber(evalSlot(block.slots.amount, ctx)) or 100)
    return false
end

local function subtract_money(block, ctx)
    ctx.game.state.money = math.max(0, ctx.game.state.money - (tonumber(evalSlot(block.slots.amount, ctx)) or 100))
    return false
end

local function trigger_rush_hour(block, ctx)
    local rh = ctx.game.state.rush_hour or {}
    rh.active = true
    rh.timer  = tonumber(evalSlot(block.slots.seconds, ctx)) or 30
    ctx.game.state.rush_hour = rh
    return false
end

local function end_rush_hour(block, ctx)
    if ctx.game.state.rush_hour then
        ctx.game.state.rush_hour.active = false
    end
    return false
end

local function pause_trip_gen(block, ctx)
    ctx.game.entities.pause_trip_generation = true
    return false
end

local function resume_trip_gen(block, ctx)
    ctx.game.entities.pause_trip_generation = false
    return false
end

local function set_trip_gen_rate(block, ctx)
    local m = (tonumber(evalSlot(block.slots.pct, ctx)) or 100) / 100
    ctx.game.state.upgrades.trip_gen_min_mult = m
    ctx.game.state.upgrades.trip_gen_max_mult = m
    return false
end

-- ── Effects: Counters & Flags ─────────────────────────────────────────────────

local function counter_change(block, ctx)
    local k  = block.slots.key or "A"
    local op = block.slots.op  or "+="
    local nv = tonumber(evalSlot(block.slots.amount, ctx)) or 1
    local c  = counters(ctx.game)
    if op == "+=" then
        c[k] = (c[k] or 0) + nv
    else
        c[k] = (c[k] or 0) - nv
    end
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

local function set_counter(block, ctx)
    local k = block.slots.key or "A"
    counters(ctx.game)[k] = tonumber(evalSlot(block.slots.value, ctx)) or 0
    return false
end

local function reset_all_counters(block, ctx)
    local c = counters(ctx.game)
    for k in pairs(c) do c[k] = 0 end
    return false
end

local function toggle_flag(block, ctx)
    local k = block.slots.key or "X"
    local f = flags(ctx.game)
    f[k] = not (f[k] or false)
    return false
end

local function swap_counters(block, ctx)
    local a = block.slots.a or "A"
    local b = block.slots.b or "B"
    local c = counters(ctx.game)
    c[a], c[b] = c[b] or 0, c[a] or 0
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

-- ── Actions: Queue manipulation ──────────────────────────────────────────────

local function prioritize_trip(block, ctx)
    local pending = ctx.game.entities.trips.pending
    for i = 2, #pending do
        if pending[i] == ctx.trip then
            table.remove(pending, i)
            table.insert(pending, 1, ctx.trip)
            break
        end
    end
    return false
end

local function deprioritize_trip(block, ctx)
    local pending = ctx.game.entities.trips.pending
    for i = 1, #pending - 1 do
        if pending[i] == ctx.trip then
            table.remove(pending, i)
            table.insert(pending, ctx.trip)
            break
        end
    end
    return false
end

local function sort_queue(block, ctx)
    local field   = block.slots.field or "payout"
    local pending = ctx.game.entities.trips.pending
    if field == "payout" then
        table.sort(pending, function(a, b)
            return (a.base_payout or 0) > (b.base_payout or 0)
        end)
    elseif field == "wait" then
        table.sort(pending, function(a, b)
            return (a.wait_time or 0) > (b.wait_time or 0)
        end)
    elseif field == "scope" then
        table.sort(pending, function(a, b)
            return (SCOPE_RANK[a.scope] or 0) < (SCOPE_RANK[b.scope] or 0)
        end)
    elseif field == "cargo" then
        table.sort(pending, function(a, b)
            local la = a.legs and a.legs[a.current_leg or 1]
            local lb = b.legs and b.legs[b.current_leg or 1]
            return (la and la.cargo_size or 0) > (lb and lb.cargo_size or 0)
        end)
    end
    return false
end

local function cancel_all_scope(block, ctx)
    local scope   = block.slots.scope or "district"
    local pending = ctx.game.entities.trips.pending
    for i = #pending, 1, -1 do
        if pending[i] ~= ctx.trip and (pending[i].scope or "") == scope then
            table.remove(pending, i)
        end
    end
    return (ctx.trip.scope or "") == scope and "cancel" or false
end

local function cancel_all_wait(block, ctx)
    local op   = block.slots.op or ">"
    local secs = tonumber(evalSlot(block.slots.seconds, ctx)) or 30
    local pending = ctx.game.entities.trips.pending
    for i = #pending, 1, -1 do
        if pending[i] ~= ctx.trip and cmp(pending[i].wait_time or 0, op, secs) then
            table.remove(pending, i)
        end
    end
    return cmp(ctx.trip.wait_time or 0, op, secs) and "cancel" or false
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

-- ── Reporter comparison condition ─────────────────────────────────────────────

local function reporter_compare(block, ctx)
    local lv = tonumber(evalSlot(block.slots.left,  ctx)) or 0
    local rv = tonumber(evalSlot(block.slots.right, ctx)) or 0
    return cmp(lv, block.slots.op or ">", rv)
end

-- ── Text variable helpers ─────────────────────────────────────────────────────

local function text_vars(game) return game.state.text_vars end

-- ── Conditions: text variables ────────────────────────────────────────────────

local function text_var_eq(block, ctx)
    local k = block.slots.key or "A"
    return (text_vars(ctx.game)[k] or "") == (block.slots.value or "")
end

local function text_var_contains(block, ctx)
    local k   = block.slots.key or "A"
    local hay = text_vars(ctx.game)[k] or ""
    local ndl = block.slots.value or ""
    return ndl == "" or hay:find(ndl, 1, true) ~= nil
end

-- ── Effects: text variables ───────────────────────────────────────────────────

local function set_text_var(block, ctx)
    text_vars(ctx.game)[block.slots.key or "A"] = tostring(block.slots.value or "")
    return false
end

local function append_text_var(block, ctx)
    local k  = block.slots.key or "A"
    local tv = text_vars(ctx.game)
    tv[k] = (tv[k] or "") .. tostring(block.slots.value or "")
    return false
end

local function clear_text_var(block, ctx)
    text_vars(ctx.game)[block.slots.key or "A"] = ""
    return false
end

-- ── Broadcast ─────────────────────────────────────────────────────────────────

local function broadcast_message(block, ctx)
    local name = tostring(block.slots.name or "event")
    local bq   = ctx.game.state.broadcast_queue
    if bq then bq[#bq+1] = name end
    return false
end

-- ── Hat poll evaluators ───────────────────────────────────────────────────────
-- These receive the hat node (not a stack block) and ctx = { game = game }.

local function hat_money_below(hat, ctx)
    return ctx.game.state.money < (hat.slots.value or 500)
end

local function hat_money_above(hat, ctx)
    return ctx.game.state.money > (hat.slots.value or 500)
end

local function hat_queue_reaches(hat, ctx)
    return #ctx.game.entities.trips.pending >= (hat.slots.n or 1)
end

local function hat_queue_empties(hat, ctx)
    return #ctx.game.entities.trips.pending == 0
end

local function hat_all_busy(hat, ctx)
    local want = (hat.slots.vehicle_type or ""):lower()
    for _, v in ipairs(ctx.game.entities.vehicles) do
        if (v.type or ""):lower() == want and v.state and v.state.name == "Idle" then
            return false
        end
    end
    return true
end

local function hat_all_idle(hat, ctx)
    local want = (hat.slots.vehicle_type or ""):lower()
    local has_any = false
    for _, v in ipairs(ctx.game.entities.vehicles) do
        if (v.type or ""):lower() == want then
            has_any = true
            if not (v.state and v.state.name == "Idle") then return false end
        end
    end
    return has_any
end

local function hat_counter_reaches(hat, ctx)
    local k = hat.slots.key or "A"
    return (counters(ctx.game)[k] or 0) >= (hat.slots.value or 0)
end

local function hat_counter_drops(hat, ctx)
    local k = hat.slots.key or "A"
    return (counters(ctx.game)[k] or 0) < (hat.slots.value or 0)
end

local function hat_flag_set_poll(hat, ctx)
    return flags(ctx.game)[hat.slots.key or "X"] == true
end

local function hat_flag_cleared_poll(hat, ctx)
    return not flags(ctx.game)[hat.slots.key or "X"]
end

-- ── Conditions: per-vehicle context ──────────────────────────────────────────

local function this_vehicle_type(block, ctx)
    if not ctx.vehicle then return false end
    return (ctx.vehicle.type or ""):lower() == (block.slots.vehicle_type or ""):lower()
end

local function this_vehicle_idle(block, ctx)
    if not ctx.vehicle then return false end
    return ctx.vehicle.state and ctx.vehicle.state.name == "Idle"
end

local function this_vehicle_speed(block, ctx)
    if not ctx.vehicle then return false end
    return cmp(ctx.vehicle:getSpeed(), block.slots.op or ">", evalSlot(block.slots.value, ctx) or 0)
end

local function this_vehicle_trips(block, ctx)
    if not ctx.vehicle then return false end
    return cmp(ctx.vehicle.trips_completed or 0, block.slots.op or ">", evalSlot(block.slots.value, ctx) or 0)
end

-- ── Actions: per-vehicle context ──────────────────────────────────────────────

local function unassign_vehicle(block, ctx)
    if ctx.vehicle then ctx.vehicle:unassign(ctx.game) end
    return false
end

local function send_to_depot(block, ctx)
    if ctx.vehicle then ctx.vehicle:returnToDepot(ctx.game) end
    return false
end

local function set_speed_mult(block, ctx)
    if ctx.vehicle then
        ctx.vehicle.speed_modifier = (block.slots.value or 100) / 100
    end
    return false
end

local function fire_vehicle(block, ctx)
    if ctx.vehicle and ctx.game.entities.removeVehicle then
        ctx.game.entities:removeVehicle(ctx.vehicle, ctx.game)
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

local function stop_rule(block, ctx)    return "stop_rule"    end
local function stop_all(block, ctx)     return "stop_all"     end
local function action_break(block, ctx) return "break"        end
local function action_continue(block, ctx) return "continue"  end

-- ── Actions: Visual / Looks ────────────────────────────────────────────────────

local function set_vehicle_color(block, ctx)
    if not ctx.vehicle then return false end
    ctx.vehicle.color_override = {
        tonumber(block.slots.r) or 1.0,
        tonumber(block.slots.g) or 0.5,
        tonumber(block.slots.b) or 0.1,
    }
    return false
end

local function reset_vehicle_color(block, ctx)
    if ctx.vehicle then ctx.vehicle.color_override = nil end
    return false
end

local function set_vehicle_icon(block, ctx)
    if not ctx.vehicle then return false end
    local icon = tostring(block.slots.icon or "")
    ctx.vehicle.icon_override = (icon ~= "") and icon or nil
    return false
end

local function show_speech_bubble(block, ctx)
    if not ctx.vehicle then return false end
    local secs = math.max(0.1, tonumber(evalSlot(block.slots.seconds, ctx)) or 3)
    local text = tostring(block.slots.text or "!")
    ctx.vehicle.speech_bubble = { text = text, timer = secs, max_time = secs }
    return false
end

local function flash_vehicle(block, ctx)
    if not ctx.vehicle then return false end
    local secs = math.max(0.1, tonumber(evalSlot(block.slots.seconds, ctx)) or 1)
    ctx.vehicle.flash = { timer = secs, max_time = secs, color = { 1, 1, 0 } }
    return false
end

local function show_vehicle_label(block, ctx)
    if not ctx.vehicle then return false end
    ctx.vehicle.show_label = tostring(block.slots.text or "")
    return false
end

local function hide_vehicle_label(block, ctx)
    if ctx.vehicle then ctx.vehicle.show_label = nil end
    return false
end

local function show_vehicle(block, ctx)
    if ctx.vehicle then ctx.vehicle.visible = true end
    return false
end

local function hide_vehicle(block, ctx)
    if ctx.vehicle then ctx.vehicle.visible = false end
    return false
end

local function zoom_to_vehicle(block, ctx)
    if not ctx.vehicle then return false end
    ctx.game.camera.x = ctx.vehicle.px
    ctx.game.camera.y = ctx.vehicle.py
    return false
end

local function pan_to_depot(block, ctx)
    local v = ctx.vehicle
    if not v or not v.depot_plot then return false end
    local umap = ctx.game.maps and ctx.game.maps.unified
    local ts   = (umap and umap.tile_pixel_size) or ctx.game.C.MAP.TILE_SIZE
    ctx.game.camera.x = (v.depot_plot.x - 0.5) * ts
    ctx.game.camera.y = (v.depot_plot.y - 0.5) * ts
    return false
end

local function set_zoom(block, ctx)
    local scale = tonumber(evalSlot(block.slots.scale, ctx)) or 1
    ctx.game.camera.scale = math.max(0.1, math.min(80, scale))
    return false
end

local function shake_screen(block, ctx)
    local cfg_ss = ctx.game.C and ctx.game.C.graphics and ctx.game.C.graphics.screen_shake
    if cfg_ss == false then return false end
    local secs = math.max(0.05, tonumber(evalSlot(block.slots.seconds,   ctx)) or 0.5)
    local mag  = math.max(1,    tonumber(evalSlot(block.slots.magnitude, ctx)) or 8)
    ctx.game.screen_shake = { timer = secs, max_time = secs, magnitude = mag }
    return false
end

-- ── Actions: Sound ────────────────────────────────────────────────────────────

local function play_sound(block, ctx)
    local name = block.slots.sound or "beep"
    local ok, SS = pcall(require, "services.SoundService")
    if ok and SS then SS.play(name) end
    return false
end

local function stop_all_sounds(block, ctx)
    local ok, SS = pcall(require, "services.SoundService")
    if ok and SS then SS.stopAll() end
    return false
end

local function set_volume(block, ctx)
    local vol = (tonumber(evalSlot(block.slots.value, ctx)) or 100) / 100
    local ok, SS = pcall(require, "services.SoundService")
    if ok and SS then SS.setMasterVolume(vol) end
    return false
end

-- ── Actions: UI Notifications ─────────────────────────────────────────────────

local TOAST_COLORS = {
    yellow = { 1.0, 0.90, 0.3  },
    green  = { 0.3, 1.0,  0.45 },
    blue   = { 0.6, 0.75, 1.0  },
    red    = { 1.0, 0.4,  0.3  },
    white  = { 1.0, 1.0,  1.0  },
}

local function show_toast(block, ctx)
    local feed = ctx.game.info_feed
    if not feed then return false end
    local text  = tostring(evalSlot(block.slots.text,  ctx) or "")
    local color = TOAST_COLORS[block.slots.color or "yellow"] or TOAST_COLORS.yellow
    if text ~= "" then
        feed:push({ text = text, color = color })
    end
    return false
end

local function show_alert(block, ctx)
    local feed = ctx.game.info_feed
    if not feed then return false end
    local text = tostring(evalSlot(block.slots.text, ctx) or "Alert")
    feed:push({ text = "⚠ " .. text, color = { 1.0, 0.4, 0.3 } })
    return false
end

local function add_to_log(block, ctx)
    local feed = ctx.game.info_feed
    if not feed then return false end
    local text = tostring(evalSlot(block.slots.text, ctx) or "")
    if text ~= "" then
        feed:push({ text = text, color = { 0.78, 0.78, 0.82 } })
    end
    return false
end

-- ── Conditions: depot ────────────────────────────────────────────────────────

local function getDepot(ctx)
    local depots = ctx.game.entities.depots
    return depots and depots[1]
end

local function depot_open(block, ctx)
    local d = getDepot(ctx)
    return d ~= nil and d.open == true
end

local function depot_vehicle_count(block, ctx)
    local d = getDepot(ctx)
    if not d then return false end
    return cmp(#d.assigned_vehicles, block.slots.op or ">", evalSlot(block.slots.value, ctx) or 0)
end

-- ── Actions: depot ────────────────────────────────────────────────────────────

local function open_depot(block, ctx)
    local d = getDepot(ctx)
    if d then d.open = true end
    return false
end

local function close_depot(block, ctx)
    local d = getDepot(ctx)
    if d then d.open = false end
    return false
end

local function rename_depot(block, ctx)
    local d = getDepot(ctx)
    if d then
        local name = tostring(evalSlot(block.slots.name, ctx) or "Depot")
        if name ~= "" then d.name = name end
    end
    return false
end

local function set_depot_capacity(block, ctx)
    local d = getDepot(ctx)
    if d then
        local n = math.max(0, math.floor(tonumber(evalSlot(block.slots.value, ctx)) or 0))
        d.capacity = n > 0 and n or nil
    end
    return false
end

local function send_vehicles_to_depot(block, ctx)
    local want = ((block.slots.vehicle_type) or ""):lower()
    for _, v in ipairs(ctx.game.entities.vehicles) do
        if want == "" or (v.type or ""):lower() == want then
            if v.returnToDepot then v:returnToDepot(ctx.game) end
        end
    end
    return false
end

-- ── Conditions: clients ───────────────────────────────────────────────────────

local function client_count(block, ctx)
    local n = #(ctx.game.entities.clients or {})
    return cmp(n, block.slots.op or ">", evalSlot(block.slots.value, ctx) or 0)
end

local function active_client_count(block, ctx)
    local n = 0
    for _, c in ipairs(ctx.game.entities.clients or {}) do
        if c.active then n = n + 1 end
    end
    return cmp(n, block.slots.op or ">", evalSlot(block.slots.value, ctx) or 0)
end

-- ── Actions: clients ─────────────────────────────────────────────────────────

local function pause_all_clients(block, ctx)
    for _, c in ipairs(ctx.game.entities.clients or {}) do c.active = false end
    return false
end

local function resume_all_clients(block, ctx)
    for _, c in ipairs(ctx.game.entities.clients or {}) do c.active = true end
    return false
end

local function set_client_freq(block, ctx)
    local pct  = tonumber(evalSlot(block.slots.pct, ctx)) or 100
    local mult = math.max(0.1, pct / 100)
    for _, c in ipairs(ctx.game.entities.clients or {}) do c.freq_mult = mult end
    return false
end

local function add_client(block, ctx)
    local ents = ctx.game.entities
    if ents.addClient then
        ents:addClient(ctx.game, ents.depots and ents.depots[1])
    end
    return false
end

local function remove_client(block, ctx)
    local clients = ctx.game.entities.clients or {}
    if #clients > 1 then
        table.remove(clients, #clients)
    end
    return false
end

-- ── Utility ───────────────────────────────────────────────────────────────────

local function action_comment(block, ctx)
    return false  -- no-op label block
end

local function set_rule_name(block, ctx)
    local name = tostring(evalSlot(block.slots.name, ctx) or "")
    if name ~= "" and ctx._rule_id then
        for _, r in ipairs(ctx.game.state.dispatch_rules or {}) do
            if r.id == ctx._rule_id then r.display_name = name; break end
        end
    end
    return false
end

local function benchmark(block, ctx)
    local feed = ctx.game.info_feed
    if feed then
        feed:push({ text = string.format("benchmark: t=%.3f", love.timer.getTime()),
                    color = { 0.60, 0.90, 0.60 } })
    end
    return false
end

-- Hat poll evaluators: timer-based hats ───────────────────────────────────────

local function hat_vehicle_idle_for(hat_node, ctx)
    local want    = ((hat_node.slots and hat_node.slots.vehicle_type) or ""):lower()
    local min_sec = tonumber(hat_node.slots and hat_node.slots.seconds) or 10
    local now     = love.timer.getTime()
    for _, v in ipairs(ctx.game.entities.vehicles or {}) do
        if want == "" or (v.type or ""):lower() == want then
            if v.idle_since and (now - v.idle_since) >= min_sec then
                ctx.vehicle = v  -- inject for body blocks
                return true
            end
        end
    end
    return false
end

local function hat_every_n_seconds(hat_node, ctx)
    local n       = tonumber(hat_node.slots and hat_node.slots.seconds) or 5
    if not ctx.game.state.rule_timers then ctx.game.state.rule_timers = {} end
    local timers  = ctx.game.state.rule_timers
    local key     = ctx._rule_id
    if not key then return false end
    local last    = timers[key] or 0
    local now     = love.timer.getTime()
    if now - last >= n then
        timers[key] = now
        return true
    end
    return false
end

local function hat_after_n_seconds(hat_node, ctx)
    local n      = tonumber(hat_node.slots and hat_node.slots.seconds) or 5
    if not ctx.game.state.rule_timers then ctx.game.state.rule_timers = {} end
    local timers = ctx.game.state.rule_timers
    local key    = ctx._rule_id
    if not key then return false end
    local fired_key = key .. "_once"
    if timers[fired_key] then return false end  -- already fired
    local start_key = key .. "_start"
    if not timers[start_key] then timers[start_key] = love.timer.getTime() end
    local now = love.timer.getTime()
    if now - timers[start_key] >= n then
        timers[fired_key] = true
        return true
    end
    return false
end

-- ─────────────────────────────────────────────────────────────────────────────

return {
    -- Conditions: trip
    scope_equals         = scope_equals,
    scope_not_equals     = scope_not_equals,
    payout_compare       = payout_compare,
    wait_compare         = wait_compare,
    is_multi_leg         = is_multi_leg,
    leg_count            = leg_count,
    cargo_size           = cargo_size,
    trip_bonus           = trip_bonus,

    -- Conditions: fleet
    fleet_util           = fleet_util,
    vehicle_idle_any     = vehicle_idle_any,
    vehicle_idle_none    = vehicle_idle_none,
    idle_count_compare   = idle_count_compare,

    -- Conditions: game state
    queue_compare        = queue_compare,
    money_compare        = money_compare,
    rush_hour_active     = rush_hour_active,
    upgrade_purchased    = upgrade_purchased,

    -- Conditions: logic / utility
    random_chance        = random_chance,
    always_true          = always_true,
    always_false         = always_false,
    counter_mod          = counter_mod,

    -- Conditions: counters & flags
    counter_compare      = counter_compare,
    flag_is_set          = flag_is_set,
    flag_is_clear        = flag_is_clear,

    -- Effects: trip
    set_payout           = set_payout,
    add_bonus            = add_bonus,

    -- Effects: economy
    add_money            = add_money,
    subtract_money       = subtract_money,
    trigger_rush_hour    = trigger_rush_hour,
    end_rush_hour        = end_rush_hour,
    pause_trip_gen       = pause_trip_gen,
    resume_trip_gen      = resume_trip_gen,
    set_trip_gen_rate    = set_trip_gen_rate,

    -- Effects: counters & flags
    counter_change       = counter_change,
    counter_reset        = counter_reset,
    flag_set             = flag_set,
    flag_clear           = flag_clear,
    set_counter          = set_counter,
    reset_all_counters   = reset_all_counters,
    toggle_flag          = toggle_flag,
    swap_counters        = swap_counters,

    -- Actions: queue
    prioritize_trip      = prioritize_trip,
    deprioritize_trip    = deprioritize_trip,
    sort_queue           = sort_queue,
    cancel_all_scope     = cancel_all_scope,
    cancel_all_wait      = cancel_all_wait,

    -- Actions: smart assignment
    assign_fastest       = assign_fastest,
    assign_most_capacity = assign_most_capacity,
    assign_least_recent  = assign_least_recent,

    -- Actions: standard
    assign_vehicle_type  = assign_vehicle_type,
    assign_any           = assign_any,
    assign_nearest       = assign_nearest,
    skip                 = skip,
    cancel_trip          = cancel_trip,

    -- Actions: flow / loops
    stop_rule            = stop_rule,
    stop_all             = stop_all,
    action_break         = action_break,
    action_continue      = action_continue,

    -- Actions: visual / looks
    set_vehicle_color    = set_vehicle_color,
    reset_vehicle_color  = reset_vehicle_color,
    set_vehicle_icon     = set_vehicle_icon,
    show_speech_bubble   = show_speech_bubble,
    flash_vehicle        = flash_vehicle,
    show_vehicle_label   = show_vehicle_label,
    hide_vehicle_label   = hide_vehicle_label,
    show_vehicle         = show_vehicle,
    hide_vehicle         = hide_vehicle,
    zoom_to_vehicle      = zoom_to_vehicle,
    pan_to_depot         = pan_to_depot,
    set_zoom             = set_zoom,
    shake_screen         = shake_screen,

    -- Reporter comparison
    reporter_compare     = reporter_compare,

    -- Text variables
    text_var_eq          = text_var_eq,
    text_var_contains    = text_var_contains,
    set_text_var         = set_text_var,
    append_text_var      = append_text_var,
    clear_text_var       = clear_text_var,

    -- Broadcast
    broadcast_message    = broadcast_message,

    -- Hat poll evaluators
    hat_money_below       = hat_money_below,
    hat_money_above       = hat_money_above,
    hat_queue_reaches     = hat_queue_reaches,
    hat_queue_empties     = hat_queue_empties,
    hat_all_busy          = hat_all_busy,
    hat_all_idle          = hat_all_idle,
    hat_counter_reaches   = hat_counter_reaches,
    hat_counter_drops     = hat_counter_drops,
    hat_flag_set_poll     = hat_flag_set_poll,
    hat_flag_cleared_poll = hat_flag_cleared_poll,

    -- Conditions: per-vehicle
    this_vehicle_type    = this_vehicle_type,
    this_vehicle_idle    = this_vehicle_idle,
    this_vehicle_speed   = this_vehicle_speed,
    this_vehicle_trips   = this_vehicle_trips,

    -- Actions: per-vehicle
    unassign_vehicle     = unassign_vehicle,
    send_to_depot        = send_to_depot,
    set_speed_mult       = set_speed_mult,
    fire_vehicle         = fire_vehicle,

    -- Actions: sound
    play_sound           = play_sound,
    stop_all_sounds      = stop_all_sounds,
    set_volume           = set_volume,

    -- Actions: UI notifications
    show_toast           = show_toast,
    show_alert           = show_alert,
    add_to_log           = add_to_log,

    -- Conditions: depot
    depot_open           = depot_open,
    depot_vehicle_count  = depot_vehicle_count,

    -- Actions: depot
    open_depot           = open_depot,
    close_depot          = close_depot,
    rename_depot         = rename_depot,
    set_depot_capacity   = set_depot_capacity,
    send_vehicles_to_depot = send_vehicles_to_depot,

    -- Procedures (action_call is handled directly in RuleEngine; stub here for completeness)
    action_call          = function() return false end,

    -- Conditions: clients
    client_count         = client_count,
    active_client_count  = active_client_count,

    -- Actions: clients
    pause_all_clients    = pause_all_clients,
    resume_all_clients   = resume_all_clients,
    set_client_freq      = set_client_freq,
    add_client           = add_client,
    remove_client        = remove_client,

    -- Utility
    action_comment       = action_comment,
    set_rule_name        = set_rule_name,
    benchmark            = benchmark,

    -- Timer hat poll evaluators
    hat_every_n_seconds  = hat_every_n_seconds,
    hat_after_n_seconds  = hat_after_n_seconds,
    hat_vehicle_idle_for = hat_vehicle_idle_for,
}
