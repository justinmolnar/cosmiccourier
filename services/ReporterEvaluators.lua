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

-- ── Get Property reporter ─────────────────────────────────────────────────────
-- Generic reporter: Get(source, property). Replaces all hard-coded data reporters.
-- source:   "trip" | "vehicle" | "game" | "fleet"
-- property: key string from data/dispatch_properties.lua

local _prop_cache = nil
local function getPropCache()
    if not _prop_cache then
        _prop_cache = {}
        for _, p in ipairs(require("data.dispatch_properties")) do
            _prop_cache[p.source .. "." .. p.key] = p
        end
    end
    return _prop_cache
end

local function rep_get_property(node, ctx)
    local source = node.slots and node.slots.source
    local key    = node.slots and node.slots.property
    local prop   = (source and key) and getPropCache()[source .. "." .. key]

    -- Pure pass-through: the registry entry handles context safety and params.
    return prop and prop.read(ctx, node.slots or {}) or 0
end

-- Get Variable reporter: returns the value of a named variable.
-- Replaces rep_counter, rep_flag, and rep_text_var (all three read the same vars table).
local function rep_get_var(node, ctx)
    return getVar(ctx.game, node.slots and node.slots.key or "my_var")
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
    rep_get_property        = rep_get_property,
    rep_get_var             = rep_get_var,
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
