-- services/DispatchValidator.lua
-- Validates dispatch rule trees against structural and semantic rules.
-- Structural rules come from slot_accepts / category fields on block defs.
-- Semantic rules come from the `assertion` and `constraint` fields on block defs.
-- This module knows NOTHING about the UI — it only returns validity tables.

local Validator = {}

-- ── Named constraint checkers ─────────────────────────────────────────────────
-- Keyed by the `constraint` field on action block defs.
-- Each receives (action_node, rule, game) and returns a warning string or nil.

local SCOPE_ORDER = { district = 1, city = 2, region = 3, continent = 4, world = 5 }

local CONSTRAINTS = {

    vehicle_covers_trip_scope = function(action_node, rule, game)
        local RE    = require("services.DispatchRuleEngine")
        local RTU   = require("services.RuleTreeUtils")
        local def   = RE.getDefById(action_node.def_id)
        local vtype = def and def.vehicle_slot_key and action_node.slots[def.vehicle_slot_key]
        if not vtype then return nil end

        local vcfg = game.C.VEHICLES[vtype:upper()]
        if not vcfg or not vcfg.locked_to_zone then return nil end

        local vmax = SCOPE_ORDER[vcfg.locked_to_zone] or 999

        -- Walk all bool trees in the rule looking for scope "eq" leaves
        local function checkBool(bool_node)
            if not bool_node then return nil end
            local id = bool_node.def_id
            if id == "bool_and" or id == "bool_or" then
                return checkBool(bool_node.left) or checkBool(bool_node.right)
            elseif id == "bool_not" then
                return checkBool(bool_node.operand)
            else
                local bdef = RE.getDefById(id)
                if bdef and bdef.assertion
                   and bdef.assertion.subject  == "trip"
                   and bdef.assertion.property == "scope"
                   and (bdef.assertion.op == "eq" or bdef.assertion.op_from_slot) then
                    local resolved_op = bdef.assertion.op
                    if bdef.assertion.op_from_slot then
                        local raw = bool_node.slots[bdef.assertion.op_from_slot]
                        resolved_op = (raw == "=") and "eq" or nil
                    end
                    if resolved_op ~= "eq" then goto skip_scope_check end
                    local scope = bool_node.slots[bdef.assertion.slot]
                    local srank = SCOPE_ORDER[scope] or 0
                    if srank > vmax then
                        return string.format("%s is locked to '%s' — can't handle '%s' trips",
                            vcfg.display_name or vtype, vcfg.locked_to_zone, scope)
                    end
                    ::skip_scope_check::
                end
            end
            return nil
        end

        -- Walk the whole stack tree looking for control nodes
        local warning = nil
        RTU.walkTree(rule.stack or {}, function(node, _path)
            if warning then return end
            if node.kind == "control" and node.condition then
                warning = checkBool(node.condition)
            end
        end)

        return warning
    end,

}

-- ── Palette validity ──────────────────────────────────────────────────────────
-- Returns { [def_id] = { valid=bool, reason=string } } for every block def.
-- context:
--   dropping_into  = "stack" | "boolean" | nil   — what slot type is the target
--   rule           = rule table (to check max_per_rule and hat presence)

function Validator.getPaletteValidity(context, game)
    local RE       = require("services.DispatchRuleEngine")
    local RTU      = require("services.RuleTreeUtils")
    local all_defs = RE.getAllDefs()
    local result   = {}

    local rule         = context and context.rule
    local drop_type    = context and context.dropping_into  -- "stack" | "boolean" | nil

    -- Count existing nodes in the rule tree for max_per_rule checks
    local count_by_id = {}
    local has_hat     = false
    if rule and rule.stack then
        RTU.walkTree(rule.stack, function(node, _path)
            count_by_id[node.def_id] = (count_by_id[node.def_id] or 0) + 1
            if node.kind == "hat" then has_hat = true end
        end)
        -- Also count bool nodes inside control conditions
        RTU.walkTree(rule.stack, function(node, _path)
            if node.kind == "control" and node.condition then
                RTU.walkBoolTree(node.condition, function(bn, _bp)
                    count_by_id[bn.def_id] = (count_by_id[bn.def_id] or 0) + 1
                end, {})
            end
        end)
    end

    for _, def in ipairs(all_defs) do
        local ok  = true
        local why = nil

        -- Slot-type context: if we know where this block is being dropped,
        -- only allow compatible categories.
        if drop_type == "boolean" and def.category ~= "boolean" then
            ok = false; why = "only boolean blocks go here"
        elseif drop_type == "stack"
               and def.category ~= "stack" and def.category ~= "control" then
            ok = false; why = "only stack/control blocks go here"
        end

        -- Hat block: only valid if rule has no hat yet
        if ok and def.category == "hat" and has_hat then
            ok = false; why = "rule already has a trigger"
        end

        -- must_be_first: only valid as first block in a fresh rule / empty stack
        -- (when palette is opened for an empty stack)
        if ok and def.must_be_first and has_hat then
            ok = false; why = "must be the first block"
        end

        -- max_per_rule
        if ok and def.max_per_rule then
            if (count_by_id[def.id] or 0) >= def.max_per_rule then
                ok = false; why = "already in this rule"
            end
        end

        result[def.id] = { valid = ok, reason = why }
    end

    return result
end

-- ── Tree warning collection ───────────────────────────────────────────────────
-- Returns a table keyed by NODE REFERENCE (the node table itself):
--   { [node] = { warning = "string" } }
--
-- Walks the entire rule.stack tree, collecting assertion-based contradictions
-- and named constraint warnings.

function Validator.getTreeWarnings(rule, game)
    local RE       = require("services.DispatchRuleEngine")
    local RTU      = require("services.RuleTreeUtils")
    local warnings = {}  -- keyed by node reference

    -- ── Bool-tree assertion pass ─────────────────────────────────────────────
    -- Walk a bool subtree, collecting leaf assertions into by_prop.
    -- is_or_branch = true means this subtree is inside an OR node —
    -- so contradictions within it don't get flagged (they may be intentional).

    -- Map operator string (">","<","=") to assertion op name (gt/lt/eq)
    local function mapOpStr(s)
        if s == ">" then return "gt"
        elseif s == "<" then return "lt"
        else return "eq"
        end
    end

    local function collectBoolAssertions(node, by_prop, is_or_branch)
        if not node then return end
        local id = node.def_id
        if id == "bool_and" then
            collectBoolAssertions(node.left,    by_prop, is_or_branch)
            collectBoolAssertions(node.right,   by_prop, is_or_branch)
        elseif id == "bool_or" then
            -- Children of OR are in separate branches — mark as or_branch
            collectBoolAssertions(node.left,    by_prop, true)
            collectBoolAssertions(node.right,   by_prop, true)
        elseif id == "bool_not" then
            collectBoolAssertions(node.operand, by_prop, is_or_branch)
        else
            -- Leaf condition block
            local def = RE.getDefById(id)
            if def and def.assertion then
                local a   = def.assertion
                local key = a.subject .. "." .. a.property
                if a.key_slot then
                    key = key .. "." .. (node.slots[a.key_slot] or "")
                end
                -- Resolve op: static or dynamic (op_from_slot)
                local op = a.op
                if a.op_from_slot then
                    op = mapOpStr(node.slots and node.slots[a.op_from_slot] or ">")
                end
                by_prop[key] = by_prop[key] or {}
                table.insert(by_prop[key], {
                    op        = op,
                    value     = a.slot and node.slots[a.slot],
                    node      = node,
                    or_branch = is_or_branch,
                })
            end
        end
    end

    -- Run contradiction checks on a by_prop group.
    -- Entries with or_branch=true are excluded from AND-chain checks.
    local function checkContradictions(list)
        local any_e, none_e   = nil, nil
        local set_e, clear_e  = nil, nil
        local first_eq        = nil
        local gt_e, lt_e      = nil, nil

        for _, a in ipairs(list) do
            if a.or_branch then goto skip_entry end
            if     a.op == "any"   then any_e   = a
            elseif a.op == "none"  then none_e  = a
            elseif a.op == "set"   then set_e   = a
            elseif a.op == "clear" then clear_e = a
            elseif a.op == "eq"    then if not first_eq then first_eq = a end
            elseif a.op == "gt"    then gt_e    = a
            elseif a.op == "lt"    then lt_e    = a
            end
            ::skip_entry::
        end

        -- any idle + no idle (same vehicle type, same AND-chain)
        if any_e and none_e then
            warnings[none_e.node] = { warning = "contradicts 'any idle' — can't both be true" }
        end

        -- flag set + flag clear
        if set_e and clear_e then
            warnings[clear_e.node] = { warning = "flag can't be both set and clear" }
        end

        if first_eq then
            for _, a in ipairs(list) do
                if a.or_branch then goto skip_eq end

                -- eq + eq (different values)
                if a.op == "eq" and a.node ~= first_eq.node and a.value ~= first_eq.value then
                    warnings[a.node] = { warning = string.format(
                        "can't equal both '%s' and '%s'",
                        tostring(first_eq.value), tostring(a.value)) }
                end

                -- eq + neq (same value) → always false
                if a.op == "neq" and a.value == first_eq.value then
                    warnings[a.node] = { warning = string.format(
                        "value is '%s' but this excludes it — rule never fires",
                        tostring(first_eq.value)) }
                end

                ::skip_eq::
            end

            -- eq + gt: eq value ≤ threshold → never > threshold
            if gt_e and first_eq.value <= gt_e.value then
                warnings[gt_e.node] = { warning = string.format(
                    "= %s can't also be > %s",
                    tostring(first_eq.value), tostring(gt_e.value)) }
            end

            -- eq + lt: eq value ≥ threshold → never < threshold
            if lt_e and first_eq.value >= lt_e.value then
                warnings[lt_e.node] = { warning = string.format(
                    "= %s can't also be < %s",
                    tostring(first_eq.value), tostring(lt_e.value)) }
            end
        end

        -- gt X + lt Y where X ≥ Y → impossible range
        if gt_e and lt_e and gt_e.value >= lt_e.value then
            warnings[gt_e.node] = { warning = string.format(
                "impossible range: can't be > %s AND < %s",
                tostring(gt_e.value), tostring(lt_e.value)) }
        end
    end

    -- Walk all control nodes in the rule tree and check their bool conditions
    RTU.walkTree(rule.stack or {}, function(node, _path)
        if node.kind == "control" and node.condition then
            local by_prop = {}
            collectBoolAssertions(node.condition, by_prop, false)
            for _, list in pairs(by_prop) do
                checkContradictions(list)
            end
        end
    end)

    -- ── Named constraint checks on action nodes ──────────────────────────────
    RTU.walkTree(rule.stack or {}, function(node, _path)
        if node.kind ~= "stack" then return end
        local def = RE.getDefById(node.def_id)
        if def and def.constraint then
            local fn = CONSTRAINTS[def.constraint]
            if fn then
                local w = fn(node, rule, game)
                if w and not warnings[node] then
                    warnings[node] = { warning = w }
                end
            end
        end
    end)

    return warnings
end

return Validator
