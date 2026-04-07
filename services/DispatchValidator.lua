-- services/DispatchValidator.lua
-- Validates dispatch rule blocks against structural and semantic rules.
-- Structural rules come from data/dispatch_blocks.lua (validation fields).
-- Semantic rules come from the `assertion` and `constraint` fields on block defs.
-- This module knows NOTHING about the UI — it only returns validity tables.

local Validator = {}

-- ── Named constraint checkers ─────────────────────────────────────────────────
-- Keyed by the `constraint` field on action block defs.
-- Each receives (action_block, all_blocks, game) and returns a warning string or nil.

local SCOPE_ORDER = { district = 1, city = 2, region = 3, continent = 4, world = 5 }

local CONSTRAINTS = {

    vehicle_covers_trip_scope = function(action_block, blocks, game)
        local RE    = require("services.DispatchRuleEngine")
        local def   = RE.getDefById(action_block.def_id)
        local vtype = def and def.vehicle_slot_key and action_block.slots[def.vehicle_slot_key]
        if not vtype then return nil end

        local vcfg = game.C.VEHICLES[vtype:upper()]
        if not vcfg or not vcfg.locked_to_zone then return nil end

        local vmax = SCOPE_ORDER[vcfg.locked_to_zone] or 999

        -- Find any scope "eq" assertions in the rule
        for _, b in ipairs(blocks) do
            local bdef = RE.getDefById(b.def_id)
            if bdef and bdef.assertion
               and bdef.assertion.subject   == "trip"
               and bdef.assertion.property  == "scope"
               and bdef.assertion.op        == "eq" then
                local scope  = b.slots[bdef.assertion.slot]
                local srank  = SCOPE_ORDER[scope] or 0
                if srank > vmax then
                    return string.format("%s is locked to '%s' — can't handle '%s' trips",
                        vcfg.display_name or vtype, vcfg.locked_to_zone, scope)
                end
            end
        end
        return nil
    end,

}

-- ── Palette validity ──────────────────────────────────────────────────────────
-- Returns { [def_id] = { valid=bool, reason=string } } for every block def.

local function contains(t, v)
    for _, x in ipairs(t) do if x == v then return true end end
    return false
end

local function analyzeBlocks(blocks)
    local RE = require("services.DispatchRuleEngine")
    local last_def           = nil
    local categories_present = {}
    local count_by_id        = {}
    local has_terminal       = false

    for _, block in ipairs(blocks) do
        local def = RE.getDefById(block.def_id)
        if def then
            last_def = def
            categories_present[def.category] = true
            count_by_id[def.id] = (count_by_id[def.id] or 0) + 1
            if def.terminal then has_terminal = true end
        end
    end

    return {
        last_def    = last_def,
        categories  = categories_present,
        counts      = count_by_id,
        has_terminal = has_terminal,
        is_empty    = (#blocks == 0),
    }
end

function Validator.getPaletteValidity(blocks, game)
    local RE       = require("services.DispatchRuleEngine")
    local all_defs = RE.getAllDefs()
    local ctx      = analyzeBlocks(blocks)
    local result   = {}

    for _, def in ipairs(all_defs) do
        local ok  = true
        local why = nil

        if ctx.has_terminal then
            ok = false; why = "nothing follows a terminal block"

        elseif def.must_be_first and not ctx.is_empty then
            ok = false; why = "must be the first block"

        elseif def.valid_after_categories and ctx.is_empty then
            ok = false; why = "needs a block before it"

        elseif def.valid_after_categories and ctx.last_def
               and not contains(def.valid_after_categories, ctx.last_def.category) then
            ok  = false
            why = string.format("can't follow '%s'",
                ctx.last_def.label or ctx.last_def.category)
        end

        if ok and def.requires_category_before then
            for _, cat in ipairs(def.requires_category_before) do
                if not ctx.categories[cat] then
                    ok  = false
                    why = string.format("needs a %s block first", cat)
                    break
                end
            end
        end

        if ok and def.max_per_rule then
            if (ctx.counts[def.id] or 0) >= def.max_per_rule then
                ok = false; why = "already in this rule"
            end
        end

        result[def.id] = { valid = ok, reason = why }
    end

    return result
end

-- ── Block warnings ────────────────────────────────────────────────────────────
-- Three-pass semantic check on blocks already in a rule.
-- Returns { [block_index] = { warning=string } }.
--
-- Pass 1 — record positions of OR blocks
-- Pass 2 — collect `assertion` fields, check contradictions and impossible ranges
--          (two conditions only conflict if no OR block sits between them)
-- Pass 3 — run named `constraint` checks on action blocks

function Validator.getBlockWarnings(blocks, game)
    local RE       = require("services.DispatchRuleEngine")
    local warnings = {}

    -- ── Pass 1: record OR positions ──────────────────────────────────────────
    -- Used to determine whether two conflicting blocks are in the same AND-chain.
    local or_positions = {}
    for i, block in ipairs(blocks) do
        local def = RE.getDefById(block.def_id)
        if def and def.category == "logic" and def.op == "or" then
            or_positions[#or_positions + 1] = i
        end
    end

    local function or_between(i, j)
        local lo, hi = math.min(i, j), math.max(i, j)
        for _, pos in ipairs(or_positions) do
            if pos > lo and pos < hi then return true end
        end
        return false
    end

    -- ── Pass 2: assertion-based contradiction / range checks ─────────────────
    -- Collect assertions grouped by subject.property (+ key_slot value when present).
    -- key_slot lets vehicle/counter/flag assertions be scoped to a specific key
    -- (e.g. "fleet.idle.bike" vs "fleet.idle.truck").

    local by_prop = {}
    for i, block in ipairs(blocks) do
        local def = RE.getDefById(block.def_id)
        if def and def.assertion and def.category == "condition" then
            local a   = def.assertion
            local key = a.subject .. "." .. a.property
            if a.key_slot then
                key = key .. "." .. (block.slots[a.key_slot] or "")
            end
            by_prop[key] = by_prop[key] or {}
            table.insert(by_prop[key], {
                op      = a.op,
                value   = a.slot and block.slots[a.slot],
                block_i = i,
            })
        end
    end

    -- Unified contradiction check — one loop over all grouped assertion sets.
    for _, list in pairs(by_prop) do
        local any_e, none_e       = nil, nil   -- fleet idle: "any" vs "none"
        local set_e, clear_e      = nil, nil   -- flags: "set" vs "clear"
        local first_eq            = nil         -- first eq assertion seen
        local gt_e, lt_e          = nil, nil   -- numeric range

        for _, a in ipairs(list) do
            if     a.op == "any"   then any_e   = a
            elseif a.op == "none"  then none_e  = a
            elseif a.op == "set"   then set_e   = a
            elseif a.op == "clear" then clear_e = a
            elseif a.op == "eq"    then if not first_eq then first_eq = a end
            elseif a.op == "gt"    then gt_e    = a
            elseif a.op == "lt"    then lt_e    = a
            end
        end

        -- any idle + no idle (same vehicle type, no OR between) → contradiction
        if any_e and none_e and not or_between(any_e.block_i, none_e.block_i) then
            warnings[none_e.block_i] = { warning = "contradicts 'any idle' — can't both be true" }
        end

        -- flag set + flag clear (same flag, no OR between) → contradiction
        if set_e and clear_e and not or_between(set_e.block_i, clear_e.block_i) then
            warnings[clear_e.block_i] = { warning = "flag can't be both set and clear" }
        end

        -- eq + eq (different values, no OR between) → contradiction
        if first_eq then
            for _, a in ipairs(list) do
                if a.op == "eq" and a.block_i ~= first_eq.block_i
                   and a.value ~= first_eq.value
                   and not or_between(first_eq.block_i, a.block_i) then
                    warnings[a.block_i] = { warning = string.format(
                        "can't equal both '%s' and '%s'",
                        tostring(first_eq.value), tostring(a.value)) }
                end
            end

            -- eq + neq (same value, no OR between) → always false
            for _, a in ipairs(list) do
                if a.op == "neq" and a.value == first_eq.value
                   and not or_between(first_eq.block_i, a.block_i) then
                    warnings[a.block_i] = { warning = string.format(
                        "value is '%s' but this excludes it — rule never fires",
                        tostring(first_eq.value)) }
                end
            end

            -- eq + gt: eq value <= threshold → can never be > threshold
            if gt_e and first_eq.value <= gt_e.value
               and not or_between(first_eq.block_i, gt_e.block_i) then
                warnings[gt_e.block_i] = { warning = string.format(
                    "= %s can't also be > %s", tostring(first_eq.value), tostring(gt_e.value)) }
            end

            -- eq + lt: eq value >= threshold → can never be < threshold
            if lt_e and first_eq.value >= lt_e.value
               and not or_between(first_eq.block_i, lt_e.block_i) then
                warnings[lt_e.block_i] = { warning = string.format(
                    "= %s can't also be < %s", tostring(first_eq.value), tostring(lt_e.value)) }
            end
        end

        -- gt X + lt Y where X >= Y (no OR between) → impossible range
        if gt_e and lt_e and gt_e.value >= lt_e.value
           and not or_between(gt_e.block_i, lt_e.block_i) then
            warnings[gt_e.block_i] = { warning = string.format(
                "impossible range: can't be > %s AND < %s",
                tostring(gt_e.value), tostring(lt_e.value)) }
        end
    end

    -- ── Pass 3: named constraint checks on action blocks ─────────────────────
    for i, block in ipairs(blocks) do
        local def = RE.getDefById(block.def_id)
        if def and def.constraint then
            local fn = CONSTRAINTS[def.constraint]
            if fn then
                local w = fn(block, blocks, game)
                if w and not warnings[i] then
                    warnings[i] = { warning = w }
                end
            end
        end
    end

    return warnings
end

return Validator
