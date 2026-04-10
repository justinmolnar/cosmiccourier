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

local function scope_equals(block, ctx)
    return ctx.trip.scope == (block.slots.scope or "district")
end

local function scope_not_equals(block, ctx)
    return ctx.trip.scope ~= (block.slots.scope or "district")
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

-- ── Conditions: Game state ───────────────────────────────────────────────────

local function upgrade_purchased(block, ctx)
    local name = block.slots.name or ""
    return (ctx.game.state.upgrades_purchased or {})[name] ~= nil
end

local function flag_is_set(block, ctx)
    return getVar(ctx.game, block.slots.key or "") == true
end

local function flag_is_clear(block, ctx)
    return getVar(ctx.game, block.slots.key or "") ~= true
end

local function random_chance(block, ctx)
    local pct = tonumber(evalSlot(block.slots.pct or block.slots.percent, ctx)) or 50
    return (math.random() * 100) < pct
end

local function rush_hour_active(block, ctx)
    local rh = ctx.game.state.rush_hour
    return rh and rh.active or false
end

local function always_true(block, ctx)  return true end
local function always_false(block, ctx) return false end

-- ── Actions: Trip mutation ───────────────────────────────────────────────────

local function set_payout(block, ctx)
    if ctx.trip then
        ctx.trip.base_payout = tonumber(evalSlot(block.slots.value, ctx)) or 0
    end
    return false
end

local function add_bonus(block, ctx)
    if ctx.trip then
        local amt = tonumber(evalSlot(block.slots.amount, ctx)) or 0
        ctx.trip.speed_bonus = (ctx.trip.speed_bonus or 0) + amt
    end
    return false
end

-- ── Actions: Counter/var mutations (new-style, match dispatch_actions.lua) ───

local function counter_inc(block, ctx)
    local key = block.slots.var or ""
    local val = tonumber(getVar(ctx.game, key)) or 0
    local amt = tonumber(evalSlot(block.slots.amount, ctx)) or 1
    setVar(ctx.game, key, val + amt)
    return false
end

local function counter_dec(block, ctx)
    local key = block.slots.var or ""
    local val = tonumber(getVar(ctx.game, key)) or 0
    local amt = tonumber(evalSlot(block.slots.amount, ctx)) or 1
    setVar(ctx.game, key, val - amt)
    return false
end

local function counter_set(block, ctx)
    local key = block.slots.var or ""
    local val = tonumber(evalSlot(block.slots.value, ctx)) or 0
    setVar(ctx.game, key, val)
    return false
end

-- ── Actions: Effects ─────────────────────────────────────────────────────────

local function add_money(block, ctx)
    local amt = tonumber(evalSlot(block.slots.amount, ctx)) or 100
    ctx.game.state.money = ctx.game.state.money + amt
    return false
end

local function subtract_money(block, ctx)
    local amt = tonumber(evalSlot(block.slots.amount, ctx)) or 100
    ctx.game.state.money = math.max(0, ctx.game.state.money - amt)
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
    local mod = tonumber(evalSlot(block.slots.m, ctx)) or 1
    local res = tonumber(evalSlot(block.slots.r, ctx)) or 0
    if mod == 0 then return false end
    return (val % mod) == res
end

local function text_var_set(block, ctx)
    local val = evalSlot(block.slots.value, ctx)
    setVar(ctx.game, block.slots.key or "", tostring(val or ""))
    return false
end

-- Mapping effect_set_text_var to text_var_set
local set_text_var = text_var_set

local function text_var_append(block, ctx)
    local key = block.slots.key or ""
    local cur = tostring(getVar(ctx.game, key) or "")
    local val = evalSlot(block.slots.value, ctx)
    setVar(ctx.game, key, cur .. tostring(val or ""))
    return false
end

-- Mapping effect_append_text_var to text_var_append
local append_text_var = text_var_append

local function text_var_eq(block, ctx)
    local cur = tostring(getVar(ctx.game, block.slots.key or "") or "")
    local val = tostring(evalSlot(block.slots.value, ctx) or "")
    return cur == val
end

local function text_var_contains(block, ctx)
    local cur = tostring(getVar(ctx.game, block.slots.key or "") or "")
    local val = tostring(evalSlot(block.slots.value, ctx) or "")
    return val == "" or cur:find(val, 1, true) ~= nil
end

local function play_sound(block, ctx)
    local name = block.slots.sound or "beep"
    local ok, SS = pcall(require, "services.SoundService")
    if ok and SS then SS.play(name) end
    return false
end

local function shake_screen(block, ctx)
    local secs = math.max(0.05, tonumber(evalSlot(block.slots.seconds,   ctx)) or 0.5)
    local mag  = math.max(1,    tonumber(evalSlot(block.slots.magnitude, ctx)) or 8)
    ctx.game.screen_shake = { timer = secs, max_time = secs, magnitude = mag }
    return false
end

-- ── Rush Hour ────────────────────────────────────────────────────────────────

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

-- ── Trip Generation ─────────────────────────────────────────────────────────

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

local function skip(block, ctx)
    return "skip"
end

local function cancel_trip(block, ctx)
    return "cancel"
end

-- ── Actions: Queue ───────────────────────────────────────────────────────────

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
    local SORTERS = require("data.dispatch_sorters")
    local metric  = block.slots.metric or "payout"
    local sorter  = nil
    for _, s in ipairs(SORTERS) do
        if s.for_type == "pending_trips" and s.id == metric then sorter = s; break end
    end
    if not sorter then return false end
    local pending = ctx.game.entities.trips.pending
    if sorter.order == "desc" then
        table.sort(pending, function(a, b)
            return (sorter.score(a, ctx) or 0) > (sorter.score(b, ctx) or 0)
        end)
    else
        table.sort(pending, function(a, b)
            return (sorter.score(a, ctx) or 0) < (sorter.score(b, ctx) or 0)
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

-- ── Counters/Flags ───────────────────────────────────────────────────────────

local function counter_reset(block, ctx)
    setVar(ctx.game, block.slots.key or "A", 0)
    return false
end

local function reset_all_counters(block, ctx)
    -- This ideally should only reset counters A-E if they are clearly distinct,
    -- but since we use a unified vars table, we can either clear everything
    -- or just the known counter keys.
    local keys = { "A", "B", "C", "D", "E" }
    for _, k in ipairs(keys) do setVar(ctx.game, k, 0) end
    return false
end

local function toggle_flag(block, ctx)
    local k = block.slots.key or "X"
    setVar(ctx.game, k, not (getVar(ctx.game, k) == true))
    return false
end

local function swap_counters(block, ctx)
    local a = block.slots.a or "A"
    local b = block.slots.b or "B"
    local va, vb = getVar(ctx.game, a), getVar(ctx.game, b)
    setVar(ctx.game, a, vb or 0)
    setVar(ctx.game, b, va or 0)
    return false
end

-- ── Vehicle ──────────────────────────────────────────────────────────────────

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
        ctx.vehicle.speed_modifier = (tonumber(evalSlot(block.slots.value, ctx)) or 100) / 100
    end
    return false
end

local function set_vehicle_color(block, ctx)
    if not ctx.vehicle then return false end
    ctx.vehicle.color_override = {
        tonumber(evalSlot(block.slots.r, ctx)) or 1.0,
        tonumber(evalSlot(block.slots.g, ctx)) or 0.5,
        tonumber(evalSlot(block.slots.b, ctx)) or 0.1,
    }
    return false
end

local function reset_vehicle_color(block, ctx)
    if ctx.vehicle then ctx.vehicle.color_override = nil end
    return false
end

local function set_vehicle_icon(block, ctx)
    if not ctx.vehicle then return false end
    local icon = tostring(evalSlot(block.slots.icon, ctx) or "")
    ctx.vehicle.icon_override = (icon ~= "") and icon or nil
    return false
end

local function show_speech_bubble(block, ctx)
    if not ctx.vehicle then return false end
    local secs = math.max(0.1, tonumber(evalSlot(block.slots.seconds, ctx)) or 3)
    local text = tostring(evalSlot(block.slots.text, ctx) or "!")
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
    ctx.vehicle.show_label = tostring(evalSlot(block.slots.text, ctx) or "")
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

-- ── Camera ───────────────────────────────────────────────────────────────────

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

-- ── Sound ────────────────────────────────────────────────────────────────────

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

-- ── UI ───────────────────────────────────────────────────────────────────────

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

local function action_comment(block, ctx)
    return false
end

-- ── Depot ────────────────────────────────────────────────────────────────────

local function set_depot_capacity(block, ctx)
    local d = ctx.game.entities.depots and ctx.game.entities.depots[1]
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

-- ── Clients ──────────────────────────────────────────────────────────────────

local function pause_all_clients(block, ctx)
    for _, c in ipairs(ctx.game.entities.clients or {}) do c.paused = true end
    return false
end

local function resume_all_clients(block, ctx)
    for _, c in ipairs(ctx.game.entities.clients or {}) do c.paused = false end
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

-- ── System ───────────────────────────────────────────────────────────────────

local function stop_rule(block, ctx) return "stop_rule" end
local function stop_all(block, ctx) return "stop_all" end
local function action_break(block, ctx) return "break" end
local function action_continue(block, ctx) return "continue" end

local function broadcast_message(block, ctx)
    local name = tostring(evalSlot(block.slots.name, ctx) or "event")
    local bq   = ctx.game.state.broadcast_queue
    if bq then bq[#bq+1] = name end
    return false
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

-- ── Text Vars ────────────────────────────────────────────────────────────────

local function clear_text_var(block, ctx)
    setVar(ctx.game, block.slots.key or "A", "")
    return false
end

-- ── Vehicle contexts ──────────────────────────────────────────────────────────

local function this_vehicle_type(block, ctx)
    if not ctx.vehicle then return false end
    return (ctx.vehicle.type or ""):lower() == (block.slots.type or block.slots.vehicle_type or ""):lower()
end

local function this_vehicle_idle(block, ctx)
    if not ctx.vehicle then return false end
    return ctx.vehicle.state and ctx.vehicle.state.name == "Idle"
end

local function assign_ctx(block, ctx)
    if not ctx.vehicle or not ctx.trip then return false end
    if TripEligibility.canAssign(ctx.vehicle, ctx.trip, ctx.game) then
        ctx.vehicle:assignTrip(ctx.trip, ctx.game)
        return "claimed"
    end
    return false
end

local function set_leg_destination(block, ctx)
    if not ctx.trip then return false end
    local leg = ctx.trip.legs[ctx.trip.current_leg]
    if not leg then return false end
    local pos = evalSlot(block.slots.pos, ctx)
    if type(pos) == "table" and pos.x and pos.y then
        -- Preserve the original final destination so DoDropoff knows when
        -- to pay out vs. deposit at an intermediate building.
        if not ctx.trip.final_destination then
            ctx.trip.final_destination = { x = leg.end_plot.x, y = leg.end_plot.y }
        end
        leg.end_plot = { x = pos.x, y = pos.y }
    end
    return false
end

local function assign_from_building(block, ctx)
    if not ctx.vehicle or not ctx.trip then return false end
    if not TripEligibility.canAssign(ctx.vehicle, ctx.trip, ctx.game) then return false end
    local BS = require("services.BuildingService")
    if not BS.withdrawTripFromAny(ctx.trip, ctx.game) then return false end
    ctx.vehicle:assignTrip(ctx.trip, ctx.game)
    return "claimed"
end

local function fire_vehicle(block, ctx)
    if not ctx.vehicle then return false end
    ctx.game.entities:removeVehicle(ctx.vehicle, ctx.game)
    return "cancel" -- If vehicle was fired while on a trip, cancel the trip
end

-- ── Depot context ────────────────────────────────────────────────────────────

local function depot_open(block, ctx)
    local d = ctx.game.entities.depots and ctx.game.entities.depots[1]
    return d ~= nil and d.open == true
end

local function open_depot(block, ctx)
    local d = ctx.game.entities.depots and ctx.game.entities.depots[1]
    if d then d.open = true end
    return false
end

local function close_depot(block, ctx)
    local d = ctx.game.entities.depots and ctx.game.entities.depots[1]
    if d then d.open = false end
    return false
end

local function rename_depot(block, ctx)
    local d = ctx.game.entities.depots and ctx.game.entities.depots[1]
    if d then
        d.name = tostring(evalSlot(block.slots.name, ctx))
    end
    return false
end

-- ── Procedures ───────────────────────────────────────────────────────────────

local function action_call(block, ctx)
    local name = block.slots.name or ""
    local RE   = require("services.DispatchRuleEngine")
    local depth = ctx._call_depth or 0
    if depth >= 10 or name == "" then return false end

    for _, rule in ipairs(ctx.game.state.dispatch_rules) do
        if rule.stack and rule.stack[1] and rule.stack[1].def_id == "hat_define" then
            if (rule.stack[1].slots and rule.stack[1].slots.name or "") == name then
                local inner = {}
                for k, v in pairs(ctx) do inner[k] = v end
                inner._call_depth = depth + 1
                local result = RE.evalStack(rule.stack, inner)
                if result == "claimed" or result == "skip" or result == "cancel" or result == "stop_all" then
                    return result
                end
                return false
            end
        end
    end
    return false
end

-- ── Loops ────────────────────────────────────────────────────────────────────

local function ctrl_repeat_n(node, ctx, evalStack)
    local n = math.min(100, math.max(1, math.floor(tonumber(evalSlot(node.slots and node.slots.n, ctx)) or 3)))
    for _ = 1, n do
        local result = evalStack(node.body, ctx)
        if result == "break" then return nil
        elseif result == "continue" then -- skip
        elseif result then return result end
    end
    return nil
end

local function ctrl_repeat_until(node, ctx, evalStack)
    local RE = require("services.DispatchRuleEngine")
    for _ = 1, 100 do
        if RE.evalBoolNode(node.condition, ctx) then break end
        local result = evalStack(node.body, ctx)
        if result == "break" then return nil
        elseif result == "continue" then -- skip
        elseif result then return result end
    end
    return nil
end

local function ctrl_for_each_vehicle(node, ctx, evalStack)
    local want = (evalSlot(node.slots and node.slots.vehicle_type, ctx) or ""):lower()
    local snapshot = {}
    for _, v in ipairs(ctx.game.entities.vehicles) do
        if want == "" or (v.type or ""):lower() == want then
            snapshot[#snapshot+1] = v
        end
    end
    for _, v in ipairs(snapshot) do
        local inner = {}
        for k, v2 in pairs(ctx) do inner[k] = v2 end
        inner.vehicle = v
        local result = evalStack(node.body, inner)
        if result == "break" then return nil
        elseif result == "continue" then -- skip
        elseif result then return result end
    end
    return nil
end

local function ctrl_for_each_trip(node, ctx, evalStack)
    local snapshot = {}
    for _, t in ipairs(ctx.game.entities.trips.pending) do
        snapshot[#snapshot+1] = t
    end
    for _, t in ipairs(snapshot) do
        local inner = {}
        for k, v2 in pairs(ctx) do inner[k] = v2 end
        inner.trip = t
        local result = evalStack(node.body, inner)
        if result == "break" then return nil
        elseif result == "continue" then -- skip
        elseif result then return result end
    end
    return nil
end

-- ── Internal math/string reporters (seed) ────────────────────────────────────

local function bool_compare(block, ctx)
    local lv = tonumber(evalSlot(block.slots.left,  ctx)) or 0
    local rv = tonumber(evalSlot(block.slots.right, ctx)) or 0
    return cmp(lv, block.slots.op or ">", rv)
end

local function block_call(block, ctx)
    local Actions = require("data.dispatch_actions")
    local id = block.slots.action or ""
    for _, a in ipairs(Actions) do
        if a.id == id then
            return a.fn(block, ctx)
        end
    end
    return false
end

-- ── Hat Poll Evaluators ──────────────────────────────────────────────────────

local function hat_money_below(hat, ctx)
    return ctx.game.state.money < (tonumber(evalSlot(hat.slots.value, ctx)) or 500)
end

local function hat_money_above(hat, ctx)
    return ctx.game.state.money > (tonumber(evalSlot(hat.slots.value, ctx)) or 500)
end

local function hat_queue_reaches(hat, ctx)
    return #ctx.game.entities.trips.pending >= (tonumber(evalSlot(hat.slots.n or hat.slots.value, ctx)) or 1)
end

local function hat_queue_empties(hat, ctx)
    return #ctx.game.entities.trips.pending == 0
end

local function hat_all_busy(hat, ctx)
    local want = (hat.slots.vehicle_type or ""):lower()
    for _, v in ipairs(ctx.game.entities.vehicles) do
        if (v.type or ""):lower() == want and (v.state and v.state.name == "Idle") then
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
    return (tonumber(getVar(ctx.game, k)) or 0) >= (tonumber(evalSlot(hat.slots.value, ctx)) or 0)
end

local function hat_counter_drops(hat, ctx)
    local k = hat.slots.key or "A"
    return (tonumber(getVar(ctx.game, k)) or 0) < (tonumber(evalSlot(hat.slots.value, ctx)) or 0)
end

local function hat_flag_set_poll(hat, ctx)
    return getVar(ctx.game, hat.slots.key or "X") == true
end

local function hat_flag_cleared_poll(hat, ctx)
    return getVar(ctx.game, hat.slots.key or "X") ~= true
end

local function hat_vehicle_idle_for(hat_node, ctx)
    local want    = ((hat_node.slots and hat_node.slots.vehicle_type) or ""):lower()
    local min_sec = tonumber(evalSlot(hat_node.slots and hat_node.slots.seconds, ctx)) or 10
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
    local n       = tonumber(evalSlot(hat_node.slots and hat_node.slots.seconds, ctx)) or 5
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
    local n      = tonumber(evalSlot(hat_node.slots and hat_node.slots.seconds, ctx)) or 5
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

-- ── Exports ──────────────────────────────────────────────────────────────────

return {
    scope_equals         = scope_equals,
    scope_not_equals     = scope_not_equals,
    is_multi_leg         = is_multi_leg,

    vehicle_idle_any     = vehicle_idle_any,
    vehicle_idle_none    = vehicle_idle_none,

    upgrade_purchased    = upgrade_purchased,
    flag_is_set          = flag_is_set,
    flag_is_clear        = flag_is_clear,
    random_chance        = random_chance,
    rush_hour_active     = rush_hour_active,
    always_true          = always_true,
    always_false         = always_false,

    set_payout           = set_payout,
    add_bonus            = add_bonus,
    counter_inc          = counter_inc,
    counter_dec          = counter_dec,
    counter_set          = counter_set,

    add_money            = add_money,
    subtract_money       = subtract_money,
    set_flag             = set_flag,
    clear_flag           = clear_flag,
    counter_mod          = counter_mod,
    set_text_var         = set_text_var,
    append_text_var      = append_text_var,
    text_var_eq          = text_var_eq,
    text_var_contains    = text_var_contains,
    play_sound           = play_sound,
    shake_screen         = shake_screen,

    skip                 = skip,
    cancel_trip          = cancel_trip,

    prioritize_trip      = prioritize_trip,
    deprioritize_trip    = deprioritize_trip,
    sort_queue           = sort_queue,
    cancel_all_scope     = cancel_all_scope,
    cancel_all_wait      = cancel_all_wait,

    find_match           = find_match,

    this_vehicle_type    = this_vehicle_type,
    this_vehicle_idle    = this_vehicle_idle,
    assign_ctx           = assign_ctx,
    set_leg_destination  = set_leg_destination,
    assign_from_building = assign_from_building,
    fire_vehicle         = fire_vehicle,

    depot_open           = depot_open,
    open_depot           = open_depot,
    close_depot          = close_depot,
    rename_depot         = rename_depot,

    action_call          = action_call,
    block_call           = block_call,
    ctrl_repeat_n        = ctrl_repeat_n,
    ctrl_repeat_until    = ctrl_repeat_until,
    ctrl_for_each_vehicle = ctrl_for_each_vehicle,
    ctrl_for_each_trip   = ctrl_for_each_trip,

    bool_compare         = bool_compare,

    trigger_rush_hour    = trigger_rush_hour,
    end_rush_hour        = end_rush_hour,
    pause_trip_gen       = pause_trip_gen,
    resume_trip_gen      = resume_trip_gen,
    set_trip_gen_rate    = set_trip_gen_rate,
    counter_reset        = counter_reset,
    reset_all_counters   = reset_all_counters,
    toggle_flag          = toggle_flag,
    swap_counters        = swap_counters,
    unassign_vehicle     = unassign_vehicle,
    send_to_depot        = send_to_depot,
    set_speed_mult       = set_speed_mult,
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
    stop_all_sounds      = stop_all_sounds,
    set_volume           = set_volume,
    show_alert           = show_alert,
    add_to_log           = add_to_log,
    action_comment       = action_comment,
    set_depot_capacity   = set_depot_capacity,
    send_vehicles_to_depot = send_vehicles_to_depot,
    pause_all_clients    = pause_all_clients,
    resume_all_clients   = resume_all_clients,
    set_client_freq      = set_client_freq,
    add_client           = add_client,
    remove_client        = remove_client,
    stop_rule            = stop_rule,
    stop_all             = stop_all,
    action_break         = action_break,
    action_continue      = action_continue,
    broadcast_message    = broadcast_message,
    set_rule_name        = set_rule_name,
    benchmark            = benchmark,
    clear_text_var       = clear_text_var,

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
    hat_every_n_seconds   = hat_every_n_seconds,
    hat_after_n_seconds   = hat_after_n_seconds,
    hat_vehicle_idle_for  = hat_vehicle_idle_for,
}
