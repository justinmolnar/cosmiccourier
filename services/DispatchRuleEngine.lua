-- services/DispatchRuleEngine.lua
-- Pure data-driven rule evaluation engine. Under 80 lines.
local RuleEngine = {}
local _defs, _evals, _reps = nil, nil, nil

local function getDefs()
    if not _defs then _defs = {} for _, d in ipairs(require("data.dispatch_blocks")) do _defs[d.id] = d end end
    return _defs
end
local function getEvaluators() _evals = _evals or require("services.DispatchEvaluators"); return _evals end
local function getReporterEvaluators() _reps = _reps or require("services.ReporterEvaluators"); return _reps end

local function evalReporter(node, ctx)
    if not node then return 0 end
    local def = getDefs()[node.def_id]
    local fn  = def and def.evaluator and getReporterEvaluators()[def.evaluator]
    return fn and fn(node, ctx) or 0
end

local function evalBoolNode(node, ctx)
    if not node then return false end
    local id = node.def_id
    if id == "bool_and" then return evalBoolNode(node.left, ctx) and evalBoolNode(node.right, ctx)
    elseif id == "bool_or" then return evalBoolNode(node.left, ctx) or evalBoolNode(node.right, ctx)
    elseif id == "bool_not" then return not evalBoolNode(node.operand, ctx)
    else
        local def = getDefs()[id]
        local fn  = def and def.evaluator and getEvaluators()[def.evaluator]
        return fn and fn(node, ctx) or false
    end
end

local function evalStack(stack, ctx)
    for _, node in ipairs(stack or {}) do
        local def = getDefs()[node.def_id]
        if node.kind == "control" then
            local res = evalStack(((not node.condition) or evalBoolNode(node.condition, ctx)) and node.body or node.else_body, ctx)
            if res then return res end
        elseif node.kind == "loop" then
            local fn = def and def.loop_handler and getEvaluators()[def.loop_handler]
            if fn then local res = fn(node, ctx, evalStack); if res then return res end end
        elseif node.kind == "stack" or node.kind == "find" then
            local fn = def and def.evaluator and getEvaluators()[def.evaluator]
            if fn then local res = fn(node, ctx); if res then return res end end
        end
    end
end

RuleEngine.evalReporter = evalReporter
RuleEngine.evalBoolNode = evalBoolNode
RuleEngine.evalStack    = evalStack
RuleEngine.getDefById   = function(id) return getDefs()[id] end
RuleEngine.getAllDefs   = function() return require("data.dispatch_blocks") end
RuleEngine.newRule      = function() return require("services.RuleTreeUtils").newRule() end
RuleEngine.newBlockInst = function(id, game) local d = getDefs()[id]; return d and require("services.RuleTreeUtils").newNode(d, game) end

function RuleEngine.fireEvent(rules, event_type, ctx)
    for _, r in ipairs(rules or {}) do
        local hat = r.enabled and r.stack and r.stack[1]
        local def = hat and hat.kind == "hat" and getDefs()[hat.def_id]
        if def and def.event_type == event_type then
            if hat.slots and hat.slots.vehicle_type and ctx.vehicle and hat.slots.vehicle_type:lower() ~= "" and hat.slots.vehicle_type:lower() ~= ctx.vehicle.type:lower() then goto next_r end
            if event_type == "broadcast" and (hat.slots and hat.slots.name or "") ~= ctx.broadcast_name then goto next_r end
            if event_type == "hotkey" and (hat.slots and hat.slots.key or "") ~= ctx.key then goto next_r end
            ctx._rule_id = r.id; evalStack(r.stack, ctx)
        end
        ::next_r::
    end
end

function RuleEngine.evaluatePoll(rules, game)
    local evs = getEvaluators()
    for _, r in ipairs(rules or {}) do
        local hat = r.enabled and r.stack and r.stack[1]
        local def = hat and hat.kind == "hat" and getDefs()[hat.def_id]
        if def and def.event_type == "poll" then
            local ctx = { game = game, _rule_id = r.id }
            if (not def.hat_evaluator) or evs[def.hat_evaluator](hat, ctx) then evalStack(r.stack, ctx) end
        end
    end
end

function RuleEngine.evaluate(rules, game, p)
    p = p or (game.entities and game.entities.trips.pending) or {}
    local cl, sk, ca = {}, {}, {}
    for _, t in ipairs(p) do
        for _, r in ipairs(rules or {}) do
            local hat = r.enabled and r.stack and r.stack[1]
            if hat and hat.kind == "hat" and not getDefs()[hat.def_id].event_type then
                local res = evalStack(r.stack, { trip = t, game = game, _rule_id = r.id })
                if res == "claimed" then cl[t] = true; goto next_t
                elseif res == "skip" then sk[t] = true; goto next_t
                elseif res == "cancel" then ca[t] = true; goto next_t
                elseif res == "stop_all" then return cl, sk, ca end
            end
        end
        ::next_t::
    end
    return cl, sk, ca
end

return RuleEngine
