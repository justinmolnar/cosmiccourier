-- services/DispatchRuleEngine.lua
-- Generic dispatch rule evaluation engine.
-- Evaluates rule.stack (tree format) recursively.
-- Block metadata  → data/dispatch_blocks.lua
-- Evaluator code  → services/DispatchEvaluators.lua
-- Player rules    → game.state.dispatch_rules

local RuleEngine = {}

-- ── Block definition registry (loaded once) ───────────────────────────────────

local _defs_by_id = nil
local _evaluators = nil

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
    if cat == "hat" then
        return RTU.newHatNode(def_id, slots)
    elseif cat == "boolean" then
        return RTU.newBoolLeaf(def_id, slots)
    elseif cat == "control" then
        return RTU.newControlNode(def_id, nil, {}, nil)
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

        elseif node.kind == "stack" then
            local def = getDefs()[node.def_id]
            local fn  = def and def.evaluator and getEvaluators()[def.evaluator]
            if fn then
                local result = fn(node, ctx)
                if result == "claimed" or result == "skip" or result == "cancel" then
                    return result
                end
                -- false / nil → side-effect block; continue
            end

        -- hat: no-op during evaluation (fires when rule is selected)
        end
    end
    return nil
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
            if not rule.enabled then goto next_rule end

            local ctx    = { trip = trip, game = game }
            local result = nil

            if rule.stack then
                -- Tree format: a hat node is required for the rule to fire.
                local has_hat = false
                for _, node in ipairs(rule.stack) do
                    if node.kind == "hat" then has_hat = true; break end
                end
                if has_hat then
                    result = evalStack(rule.stack, ctx)
                end
            end

            if result == "claimed" then
                claimed[trip] = true; goto next_trip
            elseif result == "skip" then
                skipped[trip] = true; goto next_trip
            elseif result == "cancel" then
                cancelled[trip] = true; goto next_trip
            end

            ::next_rule::
        end
        ::next_trip::
    end

    return claimed, skipped, cancelled
end

return RuleEngine
