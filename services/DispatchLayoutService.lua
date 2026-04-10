-- services/DispatchLayoutService.lua
-- Pure block dimension measurement for the dispatch rule editor.
-- No love.* calls.
--
-- All functions take a ctx table:
--   ctx = {
--     font       = love.Font,           -- ui_small font
--     slot_input = state.slot_input,    -- active slot input (may be nil)
--     panel_w    = number,              -- panel width (for bool-node wrap)
--   }
-- Assembled once per draw entry in DispatchTab, passed through.

local Validator = require("services.DispatchValidator")

local DispatchLayoutService = {}

-- ── Constants ─────────────────────────────────────────────────────────────────
-- MUST stay in sync with the matching constants at the top of DispatchTab.lua.

local STACK_H    = 36
local BOOL_H     = 26
local BOOL_ANGLE = 8
local CAP_H      = 16
local MIN_BODY_H = 36
local STACK_W_MAX = 260
local C_INDENT   = 22

-- ── Internal helpers ──────────────────────────────────────────────────────────

-- Returns the display string for a slot value (measurement version).
-- Uses ctx.slot_input for the live text buffer when the slot is focused.
local function pillDisplay_m(val, is_foc, placeholder, ctx)
    if type(val) == "table" and val.kind == "reporter" then
        local RE  = require("services.DispatchRuleEngine")
        local def = RE.getDefById(val.node and val.node.def_id)
        return "[" .. (def and def.label or "?") .. "]"
    end
    if is_foc and ctx.slot_input then
        return ctx.slot_input.input.text_buffer
    end
    local s = tostring(val or "")
    if s == "" and placeholder then return "<" .. placeholder .. ">" end
    return s
end

local function isFocused(node, key, ctx)
    return ctx.slot_input ~= nil
        and ctx.slot_input.node == node
        and ctx.slot_input.slot_key == key
end

-- ── Forward declarations ──────────────────────────────────────────────────────

local measureNode
local measureStack
local boolNodeW
local boolNodeSize
local inlineRepW
local pillWidth

-- ── inlineRepW ────────────────────────────────────────────────────────────────

inlineRepW = function(rep_node, ctx)
    local RE  = require("services.DispatchRuleEngine")
    local def = RE.getDefById(rep_node.def_id)
    if not def then return 40 end
    local w = 8 + ctx.font:getWidth(def.label or "?") + 6
    local vis = Validator.getSlotVisibility(rep_node)
    for _, sd in ipairs(def.slots or {}) do
        if vis[sd.key] ~= false then
            local v      = rep_node.slots and rep_node.slots[sd.key]
            local is_foc = isFocused(rep_node, sd.key, ctx)
            local vstr   = pillDisplay_m(v, is_foc, sd.key, ctx)
            w = w + math.max(ctx.font:getWidth(vstr) + 16, is_foc and 36 or 0) + 4
        end
    end

    -- Variadic params from registry (rep_get_property)
    if rep_node.def_id == "rep_get_property"
       and rep_node.slots.source and rep_node.slots.property then
        local PROPS = require("data.dispatch_properties")
        local entry = nil
        for _, p in ipairs(PROPS) do
            if p.source == rep_node.slots.source and p.key == rep_node.slots.property then
                entry = p; break
            end
        end
        if entry and entry.params then
            for _, psd in ipairs(entry.params) do
                local v      = rep_node.slots[psd.key]
                local is_foc = isFocused(rep_node, psd.key, ctx)
                local vstr   = pillDisplay_m(v, is_foc, psd.key, ctx)
                w = w + math.max(ctx.font:getWidth(vstr) + 16, is_foc and 36 or 0) + 4
            end
        end
    end

    return math.max(w + 4, 40)
end

DispatchLayoutService.inlineRepW = inlineRepW

-- ── pillWidth ─────────────────────────────────────────────────────────────────

pillWidth = function(val, node, key, ctx)
    if type(val) == "table" and val.kind == "reporter" and val.node then
        return inlineRepW(val.node, ctx)
    end
    local is_foc = isFocused(node, key, ctx)
    local s      = pillDisplay_m(val, is_foc, key, ctx)
    return math.max(ctx.font:getWidth(s) + 16, is_foc and 36 or 0)
end

DispatchLayoutService.pillWidth = pillWidth

-- ── boolNodeW ─────────────────────────────────────────────────────────────────

boolNodeW = function(node, ctx)
    if not node then return 60 end
    local id  = node.def_id
    local RE  = require("services.DispatchRuleEngine")
    local def = RE.getDefById(id)
    if id == "bool_and" or id == "bool_or" then
        local lbl_w = ctx.font:getWidth(def and def.label or id) + 16
        return BOOL_ANGLE + boolNodeW(node.left, ctx) + lbl_w + boolNodeW(node.right, ctx) + BOOL_ANGLE
    elseif id == "bool_not" then
        local lbl_w = ctx.font:getWidth("not") + 16
        return BOOL_ANGLE + lbl_w + boolNodeW(node.operand, ctx) + BOOL_ANGLE
    else
        if not def then return 60 end
        local w = BOOL_ANGLE * 2 + ctx.font:getWidth(def.label or "") + 16
        for _, sd in ipairs(def.slots or {}) do
            local val = node.slots and node.slots[sd.key] or sd.default or ""
            w = w + pillWidth(val, node, sd.key, ctx) + 4
        end
        return math.max(60, w)
    end
end

DispatchLayoutService.boolNodeW = boolNodeW

-- ── boolNodeSize ──────────────────────────────────────────────────────────────

boolNodeSize = function(node, ctx)
    if not node then return 60, BOOL_H end
    local id     = node.def_id
    local RE     = require("services.DispatchRuleEngine")
    local def    = RE.getDefById(id)
    local wrap_x = (ctx.panel_w or 400) - 40

    if id == "bool_and" or id == "bool_or" then
        local lbl_w      = ctx.font:getWidth(def and def.label or id) + 16
        local lw, lh     = boolNodeSize(node.left,  ctx)
        local rw, rh     = boolNodeSize(node.right, ctx)
        local total_no_wrap = BOOL_ANGLE + lw + lbl_w + rw + BOOL_ANGLE
        if total_no_wrap > wrap_x then
            local max_w = math.max(lw, lbl_w + rw) + BOOL_ANGLE * 2
            return max_w, lh + rh
        else
            return total_no_wrap, BOOL_H
        end
    elseif id == "bool_not" then
        local lbl_w  = ctx.font:getWidth("not") + 16
        local ow, oh = boolNodeSize(node.operand, ctx)
        return BOOL_ANGLE + lbl_w + ow + BOOL_ANGLE, BOOL_H
    else
        return boolNodeW(node, ctx), BOOL_H
    end
end

DispatchLayoutService.boolNodeSize = boolNodeSize

-- ── measureNode / measureStack ────────────────────────────────────────────────

measureNode = function(node, ctx)
    local cond_h   = BOOL_H
    if node.condition then
        local _, ch = boolNodeSize(node.condition, ctx)
        cond_h = ch
    end
    local header_h = math.max(STACK_H, cond_h + 10)

    if node.kind == "find" then
        header_h = STACK_H + math.max(STACK_H, cond_h + 6)
    end

    if node.kind == "hat" or node.kind == "stack" then
        return STACK_H
    elseif node.kind == "control" then
        local bh = math.max(MIN_BODY_H, measureStack(node.body or {}, ctx))
        local h  = header_h + bh + CAP_H
        if node.else_body then
            local eh = math.max(MIN_BODY_H, measureStack(node.else_body or {}, ctx))
            h = h + eh + CAP_H
        end
        return h
    elseif node.kind == "loop" or node.kind == "find" then
        local bh = math.max(MIN_BODY_H, measureStack(node.body or {}, ctx))
        return header_h + bh + CAP_H
    end
    return STACK_H
end

measureStack = function(stack, ctx)
    local h = 0
    for _, n in ipairs(stack or {}) do h = h + measureNode(n, ctx) end
    return h
end

DispatchLayoutService.measureNode  = measureNode
DispatchLayoutService.measureStack = measureStack

-- ── stackNaturalW ─────────────────────────────────────────────────────────────

function DispatchLayoutService.stackNaturalW(node, ctx)
    local RE  = require("services.DispatchRuleEngine")
    local def = RE.getDefById(node.def_id)
    local w   = ctx.font:getWidth((def and def.label) or "") + 24

    if node.def_id == "block_call" and node.slots.action then
        local ACTIONS    = require("data.dispatch_actions")
        local action_def = nil
        for _, a in ipairs(ACTIONS) do
            if a.id == node.slots.action then action_def = a; break end
        end
        if action_def and action_def.params then
            for _, psd in ipairs(action_def.params) do
                local val = node.slots[psd.key] or psd.default or ""
                w = w + pillWidth(val, node, psd.key, ctx) + 6
            end
        end
    end

    for _, sd in ipairs((def and def.slots) or {}) do
        local val = (node.slots and node.slots[sd.key]) or sd.default or ""
        w = w + pillWidth(val, node, sd.key, ctx) + 6
    end
    return math.max(160, w)
end

-- ── controlNaturalW ───────────────────────────────────────────────────────────

function DispatchLayoutService.controlNaturalW(node, ctx)
    local RE  = require("services.DispatchRuleEngine")
    local def = RE.getDefById(node.def_id)
    if not def then return 220 end

    local cond_w = node.condition and boolNodeSize(node.condition, ctx) or 60

    local lbl_w   = ctx.font:getWidth(def.label or node.def_id)
    local total_w = 10 + lbl_w + 10

    if def.slots then
        for _, sd in ipairs(def.slots) do
            if node.def_id == "find_match" then
                if sd.key == "sorter" then
                    total_w = total_w + ctx.font:getWidth("sorted by") + 12
                elseif sd.key == "variable" then
                    total_w = total_w + ctx.font:getWidth("as") + 12
                end
            end
            local val  = (node.slots and node.slots[sd.key]) or sd.default
            local vstr = pillDisplay_m(val, isFocused(node, sd.key, ctx), sd.key, ctx)
            local pw   = math.max(ctx.font:getWidth(vstr) + 16, isFocused(node, sd.key, ctx) and 36 or 0)
            total_w    = total_w + pw + 6
        end
    end

    if node.kind == "find" then
        total_w = total_w + ctx.font:getWidth("where") + 12
    end

    total_w = total_w + cond_w + 20
    local header_w = math.max(220, total_w)

    -- Measure body children so the control block expands to fit them.
    local body_w = 0
    for _, child in ipairs(node.body or {}) do
        local cw
        if child.kind == "hat" or child.kind == "stack" then
            cw = DispatchLayoutService.stackNaturalW(child, ctx)
        elseif child.kind == "control" or child.kind == "find" then
            cw = DispatchLayoutService.controlNaturalW(child, ctx)
        else
            cw = 200
        end
        if cw > body_w then body_w = cw end
    end

    return math.max(header_w, body_w + C_INDENT)
end

-- ── loopNaturalW ──────────────────────────────────────────────────────────────

function DispatchLayoutService.loopNaturalW(node, ctx)
    if node.def_id == "ctrl_repeat_until" then
        local cond_w = 70
        if node.condition then
            local cw, _ = boolNodeSize(node.condition, ctx)
            cond_w = cw
        end
        return math.max(200, 8 + ctx.font:getWidth("repeat until") + 8 + cond_w + 8)
    end
    return DispatchLayoutService.controlNaturalW(node, ctx)
end

return DispatchLayoutService
