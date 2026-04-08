-- services/DispatchRuleEngine.lua
-- Generic dispatch rule evaluation engine.
-- Evaluates rule.stack (tree format) recursively.
-- Block metadata  → data/dispatch_blocks.lua
-- Evaluator code  → services/DispatchEvaluators.lua
-- Player rules    → game.state.dispatch_rules

local RuleEngine = {}

-- ── Block definition registry (loaded once) ───────────────────────────────────

local _defs_by_id          = nil
local _evaluators          = nil
local _reporter_evaluators = nil

local function getDefs()
    if not _defs_by_id then
        _defs_by_id = {}
        for _, def in ipairs(require("data.dispatch_blocks")) do
            _defs_by_id[def.id] = def
        end
    end
    return _defs_by_id
end

local function getEvaluators()
    if not _evaluators then
        _evaluators = require("services.DispatchEvaluators")
    end
    return _evaluators
end

local function getReporterEvaluators()
    if not _reporter_evaluators then
        _reporter_evaluators = require("services.ReporterEvaluators")
    end
    return _reporter_evaluators
end

-- Evaluate a reporter node recursively. Returns number | string.
local function evalReporter(node, ctx)
    if not node then return 0 end
    local def = getDefs()[node.def_id]
    local fn  = def and def.evaluator and getReporterEvaluators()[def.evaluator]
    return fn and fn(node, ctx) or 0
end

-- Exposed so ReporterEvaluators (and DispatchEvaluators) can call it for nesting.
RuleEngine.evalReporter = evalReporter
RuleEngine.evalBoolNode = evalBoolNode

function RuleEngine.getDefById(id)  return getDefs()[id] end
function RuleEngine.getAllDefs()    return require("data.dispatch_blocks") end

-- ── Rule construction helpers ─────────────────────────────────────────────────

function RuleEngine.newRule()
    return require("services.RuleTreeUtils").newRule()
end

-- Creates a new node instance with default slot values.
-- Returns a node table ready to insert into rule.stack or a bool tree.
function RuleEngine.newBlockInst(def_id, game)
    local RTU = require("services.RuleTreeUtils")
    local def = getDefs()[def_id]
    if not def then return nil end
    local slots = RTU.defaultSlots(def, game)
    local cat   = def.category
    if def.node_kind == "find" then
        return RTU.newFindNode(def_id, slots)
    elseif cat == "hat" then
        return RTU.newHatNode(def_id, slots)
    elseif cat == "boolean" then
        return RTU.newBoolLeaf(def_id, slots)
    elseif cat == "control" then
        return RTU.newControlNode(def_id, nil, {}, nil)
    elseif cat == "loop" then
        return RTU.newLoopNode(def_id, slots)
    elseif cat == "reporter" then
        return { kind = "reporter", def_id = def_id, slots = slots }
    else
        -- "stack" (effect / action)
        return RTU.newStackNode(def_id, slots)
    end
end

-- ── Recursive boolean evaluation ─────────────────────────────────────────────

local function evalBoolNode(node, ctx)
    if not node then return false end
    local id = node.def_id
    if id == "bool_and" then
        return evalBoolNode(node.left, ctx) and evalBoolNode(node.right, ctx)
    elseif id == "bool_or" then
        return evalBoolNode(node.left, ctx) or evalBoolNode(node.right, ctx)
    elseif id == "bool_not" then
        return not evalBoolNode(node.operand, ctx)
    else
        -- Leaf condition block
        local def = getDefs()[id]
        local fn  = def and def.evaluator and getEvaluators()[def.evaluator]
        return fn and fn(node, ctx) or false
    end
end

-- ── Recursive stack evaluation ────────────────────────────────────────────────
-- Returns "claimed" | "skip" | "cancel" | nil
-- nil means the stack ran to completion with no terminal result.

local function evalStack(stack, ctx)
    for _, node in ipairs(stack or {}) do
        if node.kind == "control" then
            -- Evaluate condition (nil condition = always true)
            local cond_ok = (not node.condition) or evalBoolNode(node.condition, ctx)
            local branch  = cond_ok and node.body or node.else_body
            local result  = evalStack(branch, ctx)
            if result then return result end

        elseif node.kind == "loop" then
            local id  = node.def_id
            local result = nil
            if id == "ctrl_repeat_n" then
                local n = math.min(100, math.max(1, math.floor(tonumber(node.slots and node.slots.n) or 3)))
                for _ = 1, n do
                    result = evalStack(node.body, ctx)
                    if result == "break" then result = nil; break
                    elseif result == "continue" then result = nil
                    elseif result then break end
                end
            elseif id == "ctrl_repeat_until" then
                for _ = 1, 100 do
                    if evalBoolNode(node.condition, ctx) then break end
                    result = evalStack(node.body, ctx)
                    if result == "break" then result = nil; break
                    elseif result == "continue" then result = nil
                    elseif result then break end
                end
            elseif id == "ctrl_for_each_vehicle" then
                local want = ((node.slots and node.slots.vehicle_type) or ""):lower()
                local snapshot = {}
                for _, v in ipairs(ctx.game.entities.vehicles) do
                    if want == "" or (v.type or ""):lower() == want then
                        snapshot[#snapshot+1] = v
                    end
                end
                for _, v in ipairs(snapshot) do
                    local inner = { game = ctx.game, trip = ctx.trip, vehicle = v }
                    result = evalStack(node.body, inner)
                    if result == "break" then result = nil; break
                    elseif result == "continue" then result = nil
                    elseif result then break end
                end
            elseif id == "ctrl_for_each_trip" then
                local snapshot = {}
                for _, t in ipairs(ctx.game.entities.trips.pending) do
                    snapshot[#snapshot+1] = t
                end
                for _, t in ipairs(snapshot) do
                    local inner = { game = ctx.game, trip = t, vehicle = ctx.vehicle }
                    result = evalStack(node.body, inner)
                    if result == "break" then result = nil; break
                    elseif result == "continue" then result = nil
                    elseif result then break end
                end
            end
            -- Propagate terminal results that escaped the loop (claimed/skip/cancel/stop_*)
            if result then return result end

        elseif node.kind == "find" then
            local def = getDefs()[node.def_id]
            local fn  = def and def.evaluator and getEvaluators()[def.evaluator]
            if fn then 
                local res = fn(node, ctx)
                -- If the evaluator returns a terminal status, propagate it.
                -- Most 'find' evaluators will return false after setting a variable.
                if res then return res end
            end

        elseif node.kind == "stack" then
            -- Special: procedure call (handled in engine to avoid circular deps)
            if node.def_id == "action_call" then
                local name  = node.slots and node.slots.name or ""
                local depth = ctx._call_depth or 0
                if depth < 10 and name ~= "" then
                    local rules = ctx.game.state.dispatch_rules or {}
                    for _, proc in ipairs(rules) do
                        if not proc.stack then goto next_proc end
                        local hat = proc.stack[1]
                        if hat and hat.kind == "hat" and hat.def_id == "hat_define"
                           and (hat.slots and hat.slots.name or "") == name then
                            local inner = {}
                            for k, v in pairs(ctx) do inner[k] = v end
                            inner._call_depth = depth + 1
                            local result = evalStack(proc.stack, inner)
                            -- Propagate terminal results except stop_rule (scoped to callee)
                            if result == "claimed" or result == "skip" or result == "cancel"
                               or result == "stop_all" then
                                return result
                            end
                            break
                        end
                        ::next_proc::
                    end
                end
            else
                local def = getDefs()[node.def_id]
                local fn  = def and def.evaluator and getEvaluators()[def.evaluator]
                if fn then
                    local result = fn(node, ctx)
                    if result == "claimed" or result == "skip" or result == "cancel"
                       or result == "stop_rule" or result == "stop_all"
                       or result == "break"    or result == "continue" then
                        return result
                    end
                    -- false / nil → side-effect block; continue
                end
            end

        -- hat: no-op during evaluation (fires when rule is selected)
        end
    end
    return nil
end

-- Returns true if a rule is a procedure (has a hat_define hat) — procedures
-- are never auto-triggered; they're only called explicitly via action_call.
local function isProcedureRule(rule)
    if not rule.stack then return false end
    local hat = rule.stack[1]
    return hat and hat.kind == "hat" and hat.def_id == "hat_define"
end

-- ── Event / poll evaluation ───────────────────────────────────────────────────
-- Fires rules whose hat has event_type matching the given string.
-- ctx = { game = game } or { game = game, vehicle = vehicle }
-- These rules run their stack but cannot claim/skip/cancel trips.
function RuleEngine.fireEvent(rules, event_type, ctx)
    if not rules then return end
    local defs = getDefs()
    for _, rule in ipairs(rules) do
        if not rule.enabled          then goto next_rule end
        if not rule.stack            then goto next_rule end
        if isProcedureRule(rule)     then goto next_rule end

        local hat_node = nil
        for _, node in ipairs(rule.stack) do
            if node.kind == "hat" then hat_node = node; break end
        end
        if not hat_node then goto next_rule end

        local def = defs[hat_node.def_id]
        if not def or def.event_type ~= event_type then goto next_rule end

        -- Optional vehicle_type filter on hat slot
        if hat_node.slots and hat_node.slots.vehicle_type and ctx.vehicle then
            local want = (hat_node.slots.vehicle_type or ""):lower()
            if want ~= "" and want ~= (ctx.vehicle.type or ""):lower() then
                goto next_rule
            end
        end

        -- Broadcast: match hat's name slot against ctx.broadcast_name
        if event_type == "broadcast" and ctx.broadcast_name then
            if (hat_node.slots and hat_node.slots.name or "") ~= ctx.broadcast_name then
                goto next_rule
            end
        end

        -- Hotkey: match hat's key slot against ctx.key
        if event_type == "hotkey" and ctx.key then
            if (hat_node.slots and hat_node.slots.key or "") ~= ctx.key then
                goto next_rule
            end
        end

        ctx._rule_id = rule.id
        evalStack(rule.stack, ctx)

        ::next_rule::
    end
end

-- Fires rules with event_type = "poll" if their hat_evaluator passes.
-- Called each dispatch tick for game-state polling triggers.
function RuleEngine.evaluatePoll(rules, game)
    if not rules then return end
    local defs  = getDefs()
    local evals = getEvaluators()
    local ctx   = { game = game }
    for _, rule in ipairs(rules) do
        if not rule.enabled      then goto next_rule end
        if not rule.stack        then goto next_rule end
        if isProcedureRule(rule) then goto next_rule end

        local hat_node = nil
        for _, node in ipairs(rule.stack) do
            if node.kind == "hat" then hat_node = node; break end
        end
        if not hat_node then goto next_rule end

        local def = defs[hat_node.def_id]
        if not def or def.event_type ~= "poll" then goto next_rule end

        ctx._rule_id = rule.id
        if def.hat_evaluator then
            local fn = evals[def.hat_evaluator]
            if fn and not fn(hat_node, ctx) then goto next_rule end
        end

        evalStack(rule.stack, ctx)

        ::next_rule::
    end
end

-- ── Main evaluate loop ────────────────────────────────────────────────────────
-- Returns three sets keyed by TRIP OBJECT:
--   claimed[trip]   = true  → vehicle assigned; remove from pending
--   skipped[trip]   = true  → "skip" fired; stay pending, try next tick
--   cancelled[trip] = true  → "cancel" fired; remove from pending without assigning

function RuleEngine.evaluate(rules, game)
    local pending = game.entities.trips.pending
    if #pending == 0 or not rules or #rules == 0 then return {}, {}, {} end

    local claimed   = {}
    local skipped   = {}
    local cancelled = {}

    for _, trip in ipairs(pending) do
        for _, rule in ipairs(rules) do
            if not rule.enabled      then goto next_rule end
            if isProcedureRule(rule) then goto next_rule end

            local ctx    = { trip = trip, game = game }
            local result = nil

            if rule.stack then
                -- Tree format: only fire trip-trigger hats (no event_type field).
                local has_hat = false
                for _, node in ipairs(rule.stack) do
                    if node.kind == "hat" then
                        local hdef = getDefs()[node.def_id]
                        if not (hdef and hdef.event_type) then
                            has_hat = true
                        end
                        break
                    end
                end
                if has_hat then
                    ctx._rule_id = rule.id
                    result = evalStack(rule.stack, ctx)
                end
            end

            if result == "claimed" then
                claimed[trip] = true; goto next_trip
            elseif result == "skip" then
                skipped[trip] = true; goto next_trip
            elseif result == "cancel" then
                cancelled[trip] = true; goto next_trip
            elseif result == "stop_all" then
                goto done
            end
            -- "stop_rule" falls through to next rule (same as nil)

            ::next_rule::
        end
        ::next_trip::
    end
    ::done::

    return claimed, skipped, cancelled
end

return RuleEngine
