-- services/DispatchRuleEngine.lua
-- Generic dispatch rule evaluation engine.
-- Knows NOTHING about specific block types or evaluator logic.
-- Block metadata  → data/dispatch_blocks.lua
-- Evaluator code  → services/DispatchEvaluators.lua
-- Player rules    → game.state.dispatch_rules

local RuleEngine = {}

-- ── Block definition registry (loaded once) ───────────────────────────────────

local _defs_by_id  = nil
local _evaluators  = nil

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

local function makeId()
    return string.format("rule_%d_%d",
        math.floor(love.timer.getTime() * 1000), love.math.random(1000, 9999))
end

function RuleEngine.newRule()
    return { id = makeId(), enabled = true, blocks = {} }
end

function RuleEngine.newBlockInst(def_id, game)
    local def = getDefs()[def_id]
    if not def then return nil end
    local inst = { def_id = def_id, slots = {} }
    for _, slot_def in ipairs(def.slots or {}) do
        if slot_def.type == "vehicle_enum" then
            -- Default to lexicographically first vehicle type
            local first = nil
            for id in pairs(game and game.C and game.C.VEHICLES or {}) do
                local low = id:lower()
                if not first or low < first then first = low end
            end
            inst.slots[slot_def.key] = first or slot_def.default or ""
        else
            inst.slots[slot_def.key] = slot_def.default
        end
    end
    return inst
end

-- ── Rule parsing ──────────────────────────────────────────────────────────────
-- Splits a rule's block list into trigger, flat condition+logic list, and actions.
-- The engine understands four categories (structural, not block-specific):
--   "trigger"   – must have exactly one; a rule without one is inert
--   "condition" – evaluated against the trip; must have an evaluator key
--   "logic"     – has an "op" field ("and"|"or") from the data file
--   "action"    – executed when conditions pass; must have an evaluator key

local function parseRule(rule)
    local defs    = getDefs()
    local trigger = nil
    local conds   = {}
    local actions = {}

    for _, block in ipairs(rule.blocks) do
        local def = defs[block.def_id]
        if def then
            local cat = def.category
            if     cat == "trigger"   then trigger = block
            elseif cat == "condition" then conds[#conds + 1] = { kind = "cond",   block = block }
            elseif cat == "effect"    then actions[#actions + 1] = block   -- effects run in action pass
            elseif cat == "logic" then
                if def.negate then
                    conds[#conds + 1] = { kind = "negate" }
                else
                    conds[#conds + 1] = { kind = "logic", op = def.op or "and" }
                end
            elseif cat == "action"    then actions[#actions + 1] = block
            end
        end
    end

    return trigger, conds, actions
end

-- ── Condition evaluation ──────────────────────────────────────────────────────

local function evalConditions(conds, ctx)
    if #conds == 0 then return true end

    local evals          = getEvaluators()
    local result         = nil
    local pending_op     = "and"
    local pending_negate = false   -- set by logic_not; flips the next condition

    for _, entry in ipairs(conds) do
        if entry.kind == "negate" then
            pending_negate = not pending_negate   -- double-not cancels out
        elseif entry.kind == "logic" then
            pending_op = entry.op
        elseif entry.kind == "cond" then
            local def = getDefs()[entry.block.def_id]
            local fn  = def and def.evaluator and evals[def.evaluator]
            local ok  = fn and fn(entry.block, ctx) or false

            if pending_negate then ok = not ok; pending_negate = false end

            if result == nil then
                result = ok
            elseif pending_op == "or" then
                result = result or ok
            else
                result = result and ok
            end
            pending_op = "and"
        end
    end

    return result ~= false
end

-- ── Main evaluate loop ────────────────────────────────────────────────────────
-- Returns three sets keyed by TRIP OBJECT:
--   claimed[trip]   = true  → vehicle assigned; remove from pending
--   skipped[trip]   = true  → "skip" fired; stay pending, try next tick
--   cancelled[trip] = true  → "cancel" fired; remove from pending without assigning

function RuleEngine.evaluate(rules, game)
    local pending = game.entities.trips.pending
    if #pending == 0 or not rules or #rules == 0 then return {}, {}, {} end

    local evals = getEvaluators()

    -- Rules are evaluated in array order: index 1 = highest priority.
    -- Use up/down buttons in the UI to reorder.
    local claimed   = {}
    local skipped   = {}
    local cancelled = {}

    for _, trip in ipairs(pending) do
        local handled = false
        for _, rule in ipairs(rules) do
            if handled then break end
            if rule.enabled then
                local trigger, conds, actions = parseRule(rule)
                local ctx = { trip = trip, game = game }
                if trigger and evalConditions(conds, ctx) then
                    for _, action_block in ipairs(actions) do
                        local def = getDefs()[action_block.def_id]
                        local fn  = def and def.evaluator and evals[def.evaluator]
                        if fn then
                            local result = fn(action_block, ctx)
                            if result == "claimed" then
                                claimed[trip]   = true
                                handled         = true
                                break
                            elseif result == "skip" then
                                skipped[trip]   = true
                                handled         = true
                                break
                            elseif result == "cancel" then
                                cancelled[trip] = true
                                handled         = true
                                break
                            end
                            -- false / nil → side-effect block; continue to next action
                        end
                    end
                end
            end
        end
    end

    return claimed, skipped, cancelled
end

return RuleEngine
