-- views/tabs/DispatchTab.lua
-- Scratch-style visual dispatch rule editor.
-- Vertical puzzle-piece block layout with C-shaped control blocks,
-- inline bool reporters, and full drag-and-drop from palette to tree position.

local DispatchTab = {}

local Validator = require("services.DispatchValidator")
local TextInput = require("views.components.TextInput")
local Dropdown  = require("views.components.Dropdown")

-- ── Visual constants ──────────────────────────────────────────────────────────

-- ── Filter / search constants ─────────────────────────────────────────────────
local TAG_PILL_H   = 20   -- height of each topic-tag filter pill
local TAG_PILL_PAD = 7    -- horizontal padding inside each pill
local TAG_GAP      = 5    -- gap between pills
local SEARCH_H     = 22   -- height of the search input field

-- ── Topic-tag definitions (order = display order in palette) ──────────────────
local TAG_DEFS = {
    { id="trigger", label="Trigger", color={0.85,0.65,0.10} },
    { id="logic",   label="Logic",   color={0.82,0.78,0.15} },
    { id="trip",    label="Trip",    color={0.22,0.68,0.32} },
    { id="vehicle", label="Vehicle", color={0.28,0.72,0.58} },
    { id="game",    label="Game",    color={0.35,0.65,0.72} },
    { id="counter", label="Counter", color={0.55,0.38,0.80} },
    { id="depot",   label="Depot",   color={0.55,0.38,0.18} },
    { id="sound",   label="Sound",   color={0.75,0.30,0.65} },
    { id="ui",      label="UI",      color={0.25,0.65,0.85} },
    { id="client",  label="Client",  color={0.30,0.60,0.50} },
}

local NOTCH_X    = 14    -- notch left offset from block left edge
local NOTCH_W    = 20    -- notch width
local NOTCH_H    = 6     -- notch height (protrusion/indent depth)
local STACK_H    = 36    -- height of hat/stack block body
local BOOL_H     = 26    -- height of boolean reporter
local BOOL_ANGLE = 8     -- hexagonal side cut
local C_INDENT   = 22    -- C-block inner left indentation
local CAP_H      = 16    -- C-block cap strip height
local MIN_BODY_H = 36    -- minimum C-block inner body height
local STACK_W_MAX = 260  -- max width for hat/stack blocks
local RULE_PAD   = 8     -- padding inside rule card
local HDR_H      = 30    -- rule card header height
local ADDBTN_H   = 22    -- "Add Blocks" palette toggle strip height
local PAL_PAD    = 8     -- palette inner padding
local PAL_BLOCK_H = 28   -- height of palette block preview body (total = +NOTCH_H for stack)
local PAL_GAP    = 6     -- gap between palette blocks
local CAT_HDR_H  = 16    -- palette category header label height

-- ── Module-level state ────────────────────────────────────────────────────────

local state = {
    selected_rule   = nil,
    palette_open    = false,
    drag            = nil,
    collapsed_rules = {},   -- keyed by rule.id → bool
    input_focus     = nil,  -- { node_ref, slot_key, text, original, sd } when a number slot is focused
    -- Palette filter state
    palette_filter  = {
        active_tags    = {},    -- map tag_id → true when active
        search         = "",
        search_focused = false,
    },
    -- New componentized inputs
    search_input = nil,
    slot_input   = nil, -- { node, slot_key, input_component }
    active_dropdown = nil, -- Dropdown instance

    -- populated each draw frame:
    node_rects           = {},
    drop_targets         = {},
    palette_rects        = {},
    palette_filter_rects = {},  -- array of { tag=id, x,y,w,h }
    palette_prefab_rects = nil, -- rects for prefab palette entries
    palette_search_rect  = nil,
    rule_card_tops       = {},
    rule_card_bots       = {},
}

-- ── Hover / tooltip state ─────────────────────────────────────────────────────

local hover = {
    id           = nil,    -- unique string identifying hovered element
    timer        = 0,
    tooltip_text = nil,
    tooltip_tags = nil,    -- array of tag strings for pill rendering
    mx           = 0,
    my           = 0,
}

function DispatchTab.getState() return state end

-- ── Polygon helpers ───────────────────────────────────────────────────────────

local function polyHat(x, y, w, h)
    local nx, nxr = x + NOTCH_X, x + NOTCH_X + NOTCH_W
    return { x, y,  x+w, y,  x+w, y+h,  nxr, y+h,  nxr, y+h+NOTCH_H,  nx, y+h+NOTCH_H,  nx, y+h,  x, y+h }
end

-- Shadow variants: flat bottom (no bump) so the shadow of block N
-- doesn't bleed into the top-notch area of block N+1.
local function polyHatShadow(x, y, w, h)
    return { x, y,  x+w, y,  x+w, y+h,  x, y+h }
end

local function polyStackShadow(x, y, w, h)
    local nx, nxr = x + NOTCH_X, x + NOTCH_X + NOTCH_W
    return {
        x, y,   nx, y,   nx, y+NOTCH_H,   nxr, y+NOTCH_H,   nxr, y,   x+w, y,
        x+w, y+h,   x, y+h
    }
end

local function polyStack(x, y, w, h)
    local nx, nxr = x + NOTCH_X, x + NOTCH_X + NOTCH_W
    return {
        x, y,   nx, y,   nx, y+NOTCH_H,   nxr, y+NOTCH_H,   nxr, y,   x+w, y,
        x+w, y+h,   nxr, y+h,   nxr, y+h+NOTCH_H,   nx, y+h+NOTCH_H,   nx, y+h,   x, y+h
    }
end

local function polyBool(x, y, w, h)
    local a = BOOL_ANGLE
    return { x+a, y,  x+w-a, y,  x+w, y+h/2,  x+w-a, y+h,  x+a, y+h,  x, y+h/2 }
end

local function polyCBlock(x, y, w, body_h, sh)
    local SH, CH, NH, CI = sh or STACK_H, CAP_H, NOTCH_H, C_INDENT
    local NX, NW = NOTCH_X, NOTCH_W
    local r  = x + w
    local th = SH + body_h + CH
    local b  = y + th
    local nx1, nx2   = x + NX,      x + NX + NW
    local inx1, inx2 = x + CI + NX, x + CI + NX + NW
    return {
        x, y,   nx1, y,   nx1, y+NH,   nx2, y+NH,   nx2, y,   r, y,
        r, b,
        nx2, b,   nx2, b+NH,   nx1, b+NH,   nx1, b,   x, b,
        x, y+SH+body_h,
        x+CI, y+SH+body_h,
        inx1, y+SH+body_h,   inx1, y+SH+body_h+NH,
        inx2, y+SH+body_h+NH,   inx2, y+SH+body_h,
        r, y+SH+body_h,
        r, y+SH,
        inx2, y+SH,   inx2, y+SH+NH,   inx1, y+SH+NH,   inx1, y+SH,
        x+CI, y+SH,
        x, y+SH,
    }
end

local function polyCElseBlock(x, y, w, body_h, else_h, sh)
    local SH, CH, NH, CI = sh or STACK_H, CAP_H, NOTCH_H, C_INDENT
    local NX, NW = NOTCH_X, NOTCH_W
    local r   = x + w
    local mid = y + SH + body_h + CH
    local th  = SH + body_h + CH + else_h + CH
    local b   = y + th
    local nx1, nx2   = x + NX,    x + NX + NW
    local inx1, inx2 = x + CI + NX, x + CI + NX + NW
    return {
        x, y,   nx1, y,   nx1, y+NH,   nx2, y+NH,   nx2, y,   r, y,
        r, b,
        nx2, b,   nx2, b+NH,   nx1, b+NH,   nx1, b,   x, b,
        x, mid+else_h,
        x+CI, mid+else_h,
        inx1, mid+else_h,   inx1, mid+else_h+NH,   inx2, mid+else_h+NH,   inx2, mid+else_h,
        r, mid+else_h,
        r, mid,
        inx2, mid,   inx2, mid+NH,   inx1, mid+NH,   inx1, mid,   x+CI, mid,
        x, mid,
        x, y+SH+body_h,
        x+CI, y+SH+body_h,
        inx1, y+SH+body_h,   inx1, y+SH+body_h+NH,   inx2, y+SH+body_h+NH,   inx2, y+SH+body_h,
        r, y+SH+body_h,
        r, y+SH,
        inx2, y+SH,   inx2, y+SH+NH,   inx1, y+SH+NH,   inx1, y+SH,   x+CI, y+SH,
        x, y+SH,
    }
end

-- ── Height measurement ────────────────────────────────────────────────────────

local measureStack
local measureNode
local boolNodeW
local boolNodeSize

measureNode = function(node, game, panel_w)
    local font = game.fonts.ui_small
    local cond_h = BOOL_H
    if node.condition then
        local _, ch = boolNodeSize(node.condition, font, panel_w)
        cond_h = ch
    end
    local header_h = math.max(STACK_H, cond_h + 10)
    
    -- Special: Find block has a two-row header
    if node.kind == "find" then
        header_h = STACK_H + math.max(STACK_H, cond_h + 6)
    end

    if node.kind == "hat" or node.kind == "stack" then
        return STACK_H
    elseif node.kind == "control" then
        local bh = math.max(MIN_BODY_H, measureStack(node.body or {}, game, panel_w))
        local h  = header_h + bh + CAP_H
        if node.else_body then
            local eh = math.max(MIN_BODY_H, measureStack(node.else_body or {}, game, panel_w))
            h = h + eh + CAP_H
        end
        return h
    elseif node.kind == "loop" or node.kind == "find" then
        local bh = math.max(MIN_BODY_H, measureStack(node.body or {}, game, panel_w))
        return header_h + bh + CAP_H
    end
    return STACK_H
end

measureStack = function(stack, game, panel_w)
    local h = 0
    for _, n in ipairs(stack or {}) do h = h + measureNode(n, game, panel_w) end
    return h
end

-- ── Slot pill helper ──────────────────────────────────────────────────────────

-- Convert a slot value to its display string (handles reporter nodes).
local function slotStr(val)
    if type(val) == "table" and val.kind == "reporter" then
        local RE  = require("services.DispatchRuleEngine")
        local def = RE.getDefById(val.node and val.node.def_id)
        return "[" .. (def and def.label or "?") .. "]"
    end
    return tostring(val)
end

-- Returns the display string for a slot pill (respects active text input and placeholders).
local function pillDisplay(val, focused, placeholder)
    if type(val) == "table" and val.kind == "reporter" then
        return slotStr(val)
    end
    if focused and state.slot_input then
        return state.slot_input.input.text_buffer
    end
    local s = tostring(val or "")
    if s == "" and placeholder then return "<" .. placeholder .. ">" end
    return s
end

local function drawSlotPill(val, x, y, block_h, font, alpha, focused, placeholder)
    local s   = pillDisplay(val, focused, placeholder)
    local fw  = font:getWidth(s)
    local pw  = math.max(fw + 16, focused and 36 or (fw + 16))
    local fh  = font:getHeight()
    local py  = y + (block_h - 16) / 2

    local is_reporter = type(val) == "table" and val.kind == "reporter"
    if focused and state.slot_input then
        state.slot_input.input:draw(x, py, pw, 16)
    elseif is_reporter then
        love.graphics.setColor(0.22, 0.48, 0.55, 0.90 * alpha)
        love.graphics.rectangle("fill", x, py, pw, 16, 3, 3)
        love.graphics.setColor(0.40, 0.85, 0.90, 0.60 * alpha)
        love.graphics.rectangle("line", x, py, pw, 16, 3, 3)
        love.graphics.setColor(1, 1, 1, alpha)
        love.graphics.print(s, x + 7, py + (16 - fh) / 2)
    else
        local is_placeholder = (tostring(val or "") == "" and placeholder ~= nil)
        love.graphics.setColor(0, 0, 0, 0.35 * alpha)
        love.graphics.rectangle("fill", x, py, pw, 16, 3, 3)
        
        if is_placeholder then
            love.graphics.setColor(1, 1, 1, 0.30 * alpha)
        else
            love.graphics.setColor(1, 1, 1, 0.18 * alpha)
        end
        love.graphics.rectangle("line", x, py, pw, 16, 3, 3)
        
        if is_placeholder then
            love.graphics.setColor(1, 1, 1, 0.40 * alpha)
        else
            love.graphics.setColor(1, 1, 1, alpha)
        end
        love.graphics.print(s, x + 7, py + (16 - fh) / 2)
    end

    return pw
end

-- Measures the total width of an inline-expanded reporter (label + inner slot pills).
local function inlineRepW(rep_node, font)
    local RE  = require("services.DispatchRuleEngine")
    local def = RE.getDefById(rep_node.def_id)
    if not def then return 40 end
    local w = 8 + font:getWidth(def.label or "?") + 6
    for _, sd in ipairs(def.slots or {}) do
        -- ── Cascading visibility for rep_get_property ────────────────────────
        local visible = true
        if rep_node.def_id == "rep_get_property" then
            if sd.key == "property" then
                visible = (rep_node.slots and rep_node.slots.source ~= nil)
            elseif sd.key == "vehicle_type" then
                visible = (rep_node.slots and rep_node.slots.source == "fleet" and rep_node.slots.property ~= nil)
            end
        end

        if visible then
            local v = rep_node.slots and rep_node.slots[sd.key]
            local is_foc = state.slot_input
                           and state.slot_input.node == rep_node
                           and state.slot_input.slot_key == sd.key
            local vstr = pillDisplay(v, is_foc, sd.key)
            w = w + math.max(font:getWidth(vstr) + 16, is_foc and 36 or 0) + 4
        end
    end

    -- ── Variadic params from registry ────────────────────────────────────────
    if rep_node.def_id == "rep_get_property" and rep_node.slots.source and rep_node.slots.property then
        local PROPS = require("data.dispatch_properties")
        local entry = nil
        for _, p in ipairs(PROPS) do
            if p.source == rep_node.slots.source and p.key == rep_node.slots.property then
                entry = p; break
            end
        end
        if entry and entry.params then
            for _, psd in ipairs(entry.params) do
                local v = rep_node.slots[psd.key]
                local is_foc = state.slot_input
                               and state.slot_input.node == rep_node
                               and state.slot_input.slot_key == psd.key
                local vstr = pillDisplay(v, is_foc, psd.key)
                w = w + math.max(font:getWidth(vstr) + 16, is_foc and 36 or 0) + 4
            end
        end
    end

    return math.max(w + 4, 40)
end

-- Compute pill width without drawing (for layout of right-aligned slots).
local function pillWidth(val, font, focused, placeholder)
    if type(val) == "table" and val.kind == "reporter" and val.node then
        return inlineRepW(val.node, font)
    end
    local s = pillDisplay(val, focused, placeholder)
    return math.max(font:getWidth(s) + 16, focused and 36 or 0)
end

-- Draws an inline-expanded reporter node: label + each inner slot pill side-by-side.
-- Appends inner slot rects (higher priority) then the outer container rect to slot_rects_out.
-- Returns the total width drawn.
local function drawInlineReporter(rep_val, x, y, block_h, font, alpha, slot_rects_out, outer_key, outer_sd_type)
    local rep_node = rep_val.node
    local RE  = require("services.DispatchRuleEngine")
    local def = rep_node and RE.getDefById(rep_node.def_id)
    if not def then
        local pw = drawSlotPill(rep_val, x, y, block_h, font, alpha, false, outer_key)
        slot_rects_out[#slot_rects_out+1] = { key = outer_key, x = x, w = pw, sd_type = outer_sd_type }
        return pw
    end

    local total_w = inlineRepW(rep_node, font)
    local fh      = font:getHeight()
    local py      = y + (block_h - 16) / 2

    -- Outer teal reporter background
    love.graphics.setColor(0.22, 0.48, 0.55, 0.90 * alpha)
    love.graphics.rectangle("fill", x, py, total_w, 16, 3, 3)
    love.graphics.setColor(0.40, 0.85, 0.90, 0.60 * alpha)
    love.graphics.rectangle("line", x, py, total_w, 16, 3, 3)

    -- Reporter label
    local lbl   = def.label or "?"
    local lbl_x = x + 8
    love.graphics.setFont(font)
    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.print(lbl, lbl_x, py + (16 - fh) / 2)

    -- Inner slot sub-pills
    local inner_x = lbl_x + font:getWidth(lbl) + 6
    for _, sd in ipairs(def.slots or {}) do
        -- ── Cascading visibility for rep_get_property ────────────────────────
        local visible = true
        if rep_node.def_id == "rep_get_property" then
            if sd.key == "property" then
                visible = (rep_node.slots and rep_node.slots.source ~= nil)
            elseif sd.key == "vehicle_type" then
                visible = (rep_node.slots and rep_node.slots.source == "fleet" and rep_node.slots.property ~= nil)
            end
        end

        if visible then
            local v = rep_node.slots and rep_node.slots[sd.key]
            local is_foc = state.slot_input
                           and state.slot_input.node == rep_node
                           and state.slot_input.slot_key == sd.key
            local vstr = pillDisplay(v, is_foc, sd.key)
            local vpw = math.max(font:getWidth(vstr) + 16, is_foc and 36 or 0)

            if is_foc and state.slot_input then
                state.slot_input.input:draw(inner_x, py + 2, vpw, 12)
            else
                local is_placeholder = (tostring(v or "") == "" and sd.key ~= nil)
                love.graphics.setColor(0, 0, 0, 0.40 * alpha)
                love.graphics.rectangle("fill", inner_x, py + 2, vpw, 12, 2, 2)
                
                if is_placeholder then
                    love.graphics.setColor(1, 1, 1, 0.10 * alpha)
                else
                    love.graphics.setColor(1, 1, 1, 0.20 * alpha)
                end
                love.graphics.rectangle("line", inner_x, py + 2, vpw, 12, 2, 2)
                
                if is_placeholder then
                    love.graphics.setColor(1, 1, 1, 0.40 * alpha)
                else
                    love.graphics.setColor(1, 1, 1, alpha)
                end
                love.graphics.print(vstr, inner_x + 7, py + 2 + (12 - fh) / 2)
            end

            -- Inner slot rect (higher priority — checked before outer)
            slot_rects_out[#slot_rects_out+1] = {
                key      = outer_key,
                x        = inner_x,
                y        = py + 2,
                w        = vpw,
                h        = 12,
                sd_type  = "rep_inner",
                rep_node = rep_node,
                rep_key  = sd.key,
                rep_sd   = sd,
            }
            inner_x = inner_x + vpw + 4
        end
    end

    -- ── Variadic params from registry ────────────────────────────────────────
    if rep_node.def_id == "rep_get_property" and rep_node.slots.source and rep_node.slots.property then
        local PROPS = require("data.dispatch_properties")
        local entry = nil
        for _, p in ipairs(PROPS) do
            if p.source == rep_node.slots.source and p.key == rep_node.slots.property then
                entry = p; break
            end
        end
        if entry and entry.params then
            for _, psd in ipairs(entry.params) do
                local v = rep_node.slots[psd.key]
                local is_foc = state.slot_input
                               and state.slot_input.node == rep_node
                               and state.slot_input.slot_key == psd.key
                local vstr = pillDisplay(v, is_foc, psd.key)
                local vpw = math.max(font:getWidth(vstr) + 16, is_foc and 36 or 0)

                if is_foc and state.slot_input then
                    state.slot_input.input:draw(inner_x, py + 2, vpw, 12)
                else
                    local is_placeholder = (tostring(v or "") == "" and psd.key ~= nil)
                    love.graphics.setColor(0, 0, 0, 0.40 * alpha)
                    love.graphics.rectangle("fill", inner_x, py + 2, vpw, 12, 2, 2)
                    
                    if is_placeholder then
                        love.graphics.setColor(1, 1, 1, 0.10 * alpha)
                    else
                        love.graphics.setColor(1, 1, 1, 0.20 * alpha)
                    end
                    love.graphics.rectangle("line", inner_x, py + 2, vpw, 12, 2, 2)
                    
                    if is_placeholder then
                        love.graphics.setColor(1, 1, 1, 0.40 * alpha)
                    else
                        love.graphics.setColor(1, 1, 1, alpha)
                    end
                    love.graphics.print(vstr, inner_x + 7, py + 2 + (12 - fh) / 2)
                end

                slot_rects_out[#slot_rects_out+1] = {
                    key      = outer_key,
                    x        = inner_x,
                    y        = py + 2,
                    w        = vpw,
                    h        = 12,
                    sd_type  = "rep_inner",
                    rep_node = rep_node,
                    rep_key  = psd.key,
                    rep_sd   = psd,
                }
                inner_x = inner_x + vpw + 4
            end
        end
    end

    -- Outer container rect (lower priority — catches label-area clicks to clear)
    slot_rects_out[#slot_rects_out+1] = {
        key     = outer_key,
        x       = x,
        y       = py,
        w       = total_w,
        h       = 16,
        sd_type = outer_sd_type,
    }

    return total_w
end

boolNodeW = function(node, font)
    if not node then return 60 end
    local id  = node.def_id
    local RE  = require("services.DispatchRuleEngine")
    local def = RE.getDefById(id)
    if id == "bool_and" or id == "bool_or" then
        local lbl_w = font:getWidth(def and def.label or id) + 16
        return BOOL_ANGLE + boolNodeW(node.left, font) + lbl_w + boolNodeW(node.right, font) + BOOL_ANGLE
    elseif id == "bool_not" then
        local lbl_w = font:getWidth("not") + 16
        return BOOL_ANGLE + lbl_w + boolNodeW(node.operand, font) + BOOL_ANGLE
    else
        if not def then return 60 end
        local w = BOOL_ANGLE * 2 + font:getWidth(def.label or "") + 16
        for _, sd in ipairs(def.slots or {}) do
            local val    = node.slots and node.slots[sd.key] or sd.default or ""
            local is_foc = (sd.type == "number" or sd.type == "string" or sd.type == "text_var_enum" or sd.type == "reporter")
                           and state.slot_input
                           and state.slot_input.node == node
                           and state.slot_input.slot_key == sd.key
            w = w + pillWidth(val, font, is_foc, sd.key) + 4
        end
        return math.max(60, w)
    end
end

boolNodeSize = function(node, font, panel_w)
    if not node then return 60, BOOL_H end
    local id  = node.def_id
    local RE  = require("services.DispatchRuleEngine")
    local def = RE.getDefById(id)
    local wrap_x = (panel_w or 400) - 40

    if id == "bool_and" or id == "bool_or" then
        local lbl_w = font:getWidth(def and def.label or id) + 16
        local lw, lh = boolNodeSize(node.left, font, panel_w)
        local rw, rh = boolNodeSize(node.right, font, panel_w)
        
        -- Logic mirrors drawBoolNode: BOOL_ANGLE + LW + LBL + RW + BOOL_ANGLE
        local total_w_no_wrap = BOOL_ANGLE + lw + lbl_w + rw + BOOL_ANGLE
        
        if total_w_no_wrap > wrap_x then
            -- Wrapped: max of children widths, height is sum
            local max_w = math.max(lw, lbl_w + rw) + BOOL_ANGLE * 2
            return max_w, lh + rh
        else
            return total_w_no_wrap, BOOL_H
        end
    elseif id == "bool_not" then
        local lbl_w = font:getWidth("not") + 16
        local ow, oh = boolNodeSize(node.operand, font, panel_w)
        return BOOL_ANGLE + lbl_w + ow + BOOL_ANGLE, BOOL_H
    else
        return boolNodeW(node, font), BOOL_H
    end
end

local function stackNaturalW(node, font)
    local RE  = require("services.DispatchRuleEngine")
    local def = RE.getDefById(node.def_id)
    local w   = font:getWidth((def and def.label) or "") + 24
    
    -- ── Variadic params for block_call ──────────────────────────────────
    if node.def_id == "block_call" and node.slots.action then
        local ACTIONS = require("data.dispatch_actions")
        local action_def = nil
        for _, a in ipairs(ACTIONS) do
            if a.id == node.slots.action then action_def = a; break end
        end
        
        if action_def and action_def.params then
            for _, psd in ipairs(action_def.params) do
                local val    = node.slots[psd.key] or psd.default or ""
                local is_foc = (psd.type == "number" or psd.type == "string" or psd.type == "text_var_enum" or psd.type == "reporter")
                               and state.slot_input
                               and state.slot_input.node == node
                               and state.slot_input.slot_key == psd.key
                w = w + pillWidth(val, font, is_foc, psd.key) + 6
            end
        end
    end

    for _, sd in ipairs((def and def.slots) or {}) do
        local val    = (node.slots and node.slots[sd.key]) or sd.default or ""
        local is_foc = (sd.type == "number" or sd.type == "string" or sd.type == "text_var_enum")
                       and state.slot_input
                       and state.slot_input.node == node
                       and state.slot_input.slot_key == sd.key
        w = w + pillWidth(val, font, is_foc, sd.key) + 6
    end
    return math.max(160, math.min(STACK_W_MAX, w))
end

local function controlNaturalW(node, font, panel_w)
    local RE  = require("services.DispatchRuleEngine")
    local def = RE.getDefById(node.def_id)
    if not def then return 220 end
    
    local cond_w = 80
    if node.condition then
        local cw, _ = boolNodeSize(node.condition, font, panel_w)
        cond_w = cw
    else
        cond_w = 60
    end

    -- Base width includes the label
    local lbl_w = font:getWidth(def.label or node.def_id)
    local total_w = 10 + lbl_w + 10

    -- Add slots and extra labels for specific core blocks
    if def.slots then
        for _, sd in ipairs(def.slots) do
            -- Find block has extra labels between slots
            if node.def_id == "find_match" then
                if sd.key == "sorter" then
                    total_w = total_w + font:getWidth("sorted by") + 12
                elseif sd.key == "variable" then
                    total_w = total_w + font:getWidth("as") + 12
                end
            end

            local val    = (node.slots and node.slots[sd.key]) or sd.default
            local is_foc = (sd.type == "number" or sd.type == "string" or sd.type == "text_var_enum" or sd.type == "reporter")
                           and state.slot_input
                           and state.slot_input.node == node
                           and state.slot_input.slot_key == sd.key
            
            local vstr = pillDisplay(val, is_foc, sd.key)
            local pw = math.max(font:getWidth(vstr) + 16, is_foc and 36 or 0)
            total_w = total_w + pw + 6
        end
    end

    -- Special: Find block has extra 'where' label
    if node.kind == "find" then
        total_w = total_w + font:getWidth("where") + 12
    end

    -- Add condition
    total_w = total_w + cond_w + 20

    return math.max(220, total_w)
end

local function loopNaturalW(node, font, panel_w)
    if node.def_id == "ctrl_repeat_until" then
        local cond_w = 70
        if node.condition then
            local cw, _ = boolNodeSize(node.condition, font, panel_w)
            cond_w = cw
        end
        return math.max(200, 8 + font:getWidth("repeat until") + 8 + cond_w + 8)
    end
    return controlNaturalW(node, font, panel_w)
end

-- ── Forward declarations ──────────────────────────────────────────────────────

local drawBoolNode
local drawNodeList
local drawControlNode
local drawLoopNode
local drawFindNode

-- ── Path helpers ──────────────────────────────────────────────────────────────

local function pathsEqual(a, b)
    if not a or not b or #a ~= #b then return false end
    for i = 1, #a do if a[i] ~= b[i] then return false end end
    return true
end

local function appendPath(base, key)
    local p = {}
    for _, k in ipairs(base or {}) do p[#p+1] = k end
    p[#p+1] = key
    return p
end


-- ── drawBoolNode ──────────────────────────────────────────────────────────────

drawBoolNode = function(node, x, y, game, nrects, dtargets, path, warn_map, alpha)
    local font = game.fonts.ui_small
    local fh   = font:getHeight()
    alpha = alpha or 1.0

    -- Fetch panel width for wrapping
    local panel_w = game.ui_manager and game.ui_manager.panel and game.ui_manager.panel.w or 400
    local wrap_x  = panel_w - 40 -- Margin

    if node == nil then
        local w = 60
        love.graphics.setColor(0.4, 0.4, 0.5, 0.30 * alpha)
        love.graphics.polygon("fill", polyBool(x, y, w, BOOL_H))
        love.graphics.setColor(0.6, 0.6, 0.8, 0.50 * alpha)
        love.graphics.setLineWidth(1.5)
        love.graphics.polygon("line", polyBool(x, y, w, BOOL_H))
        love.graphics.setLineWidth(1)
        -- Register this empty slot as a drop target
        if dtargets and path and #path > 0 then
            local parent_path = {}
            for i = 1, #path - 1 do parent_path[#parent_path+1] = path[i] end
            local slot = path[#path]
            dtargets[#dtargets+1] = {
                parent_path = parent_path, slot = slot, accepts = "boolean",
                x = x, y = y, w = w, h = BOOL_H
            }
        end
        return w
    end

    local RE  = require("services.DispatchRuleEngine")
    local id  = node.def_id
    local def = RE.getDefById(id)
    local w, h = boolNodeSize(node, font, panel_w)

    if id == "bool_and" or id == "bool_or" then
        local lbl      = def and def.label or id
        local lbl_w    = font:getWidth(lbl) + 16
        local left_w, left_h = boolNodeSize(node.left, font, panel_w)
        local c        = def and def.color or { 0.82, 0.78, 0.15 }

        -- Decide if we should wrap
        local total_w_no_wrap = BOOL_ANGLE + left_w + lbl_w + boolNodeSize(node.right, font, panel_w) + BOOL_ANGLE
        local should_wrap = (x + total_w_no_wrap > wrap_x)

        love.graphics.setColor(c[1] * 0.85, c[2] * 0.85, c[3] * 0.85, 0.9 * alpha)
        love.graphics.polygon("fill", polyBool(x, y, w, h))
        if warn_map and warn_map[node] then
            love.graphics.setColor(0.95, 0.62, 0.12, alpha)
            love.graphics.setLineWidth(2)
        else
            love.graphics.setColor(0, 0, 0, 0.25 * alpha)
            love.graphics.setLineWidth(1)
        end
        love.graphics.polygon("line", polyBool(x, y, w, h))
        love.graphics.setLineWidth(1)

        local lx = x + BOOL_ANGLE
        drawBoolNode(node.left,  lx, y, game, nrects, dtargets, appendPath(path, "left"),  warn_map, alpha)
        
        local op_x, op_y, next_x, next_y
        if should_wrap then
            op_x = x + BOOL_ANGLE
            op_y = y + left_h
            next_x = op_x + lbl_w
            next_y = op_y
        else
            op_x = lx + left_w
            op_y = y
            next_x = op_x + lbl_w
            next_y = y
        end

        love.graphics.setFont(font)
        love.graphics.setColor(1, 1, 1, alpha)
        love.graphics.printf(lbl, op_x, op_y + (BOOL_H - fh) / 2, lbl_w, "center")
        drawBoolNode(node.right, next_x, next_y, game, nrects, dtargets, appendPath(path, "right"), warn_map, alpha)

        -- Register occupied slots as drop targets
        if dtargets and path then
            local lw, lh = boolNodeSize(node.left, font, panel_w)
            dtargets[#dtargets+1] = {
                parent_path = path, slot = "left", accepts = "boolean",
                x = lx, y = y, w = lw, h = lh
            }
            local rw, rh = boolNodeSize(node.right, font, panel_w)
            dtargets[#dtargets+1] = {
                parent_path = path, slot = "right", accepts = "boolean",
                x = next_x, y = next_y, w = rw, h = rh
            }
        end

        if nrects and path then
            nrects[#nrects+1] = { node=node, path=path, x=x, y=y, w=w, h=h, slot_rects={} }
        end

    elseif id == "bool_not" then
        local c     = def and def.color or { 0.88, 0.50, 0.18 }
        local lbl_w = font:getWidth("not") + 16

        love.graphics.setColor(c[1] * 0.85, c[2] * 0.85, c[3] * 0.85, 0.9 * alpha)
        love.graphics.polygon("fill", polyBool(x, y, w, BOOL_H))
        if warn_map and warn_map[node] then
            love.graphics.setColor(0.95, 0.62, 0.12, alpha)
            love.graphics.setLineWidth(2)
        else
            love.graphics.setColor(0, 0, 0, 0.25 * alpha)
            love.graphics.setLineWidth(1)
        end
        love.graphics.polygon("line", polyBool(x, y, w, BOOL_H))
        love.graphics.setLineWidth(1)

        love.graphics.setFont(font)
        love.graphics.setColor(1, 1, 1, alpha)
        local lbl_x = x + BOOL_ANGLE
        love.graphics.printf("not", lbl_x, y + (BOOL_H - fh) / 2, lbl_w, "center")
        local op_x = lbl_x + lbl_w
        drawBoolNode(node.operand, op_x, y, game, nrects, dtargets, appendPath(path, "operand"), warn_map, alpha)

        -- Register occupied slot as drop target
        if dtargets and path then
            local ow, oh = boolNodeSize(node.operand, font, panel_w)
            dtargets[#dtargets+1] = {
                parent_path = path, slot = "operand", accepts = "boolean",
                x = op_x, y = y, w = ow, h = oh
            }
        end

        if nrects and path then
            nrects[#nrects+1] = { node=node, path=path, x=x, y=y, w=w, h=BOOL_H, slot_rects={} }
        end

    else
        if not def then
            love.graphics.setColor(0.4, 0.4, 0.4, 0.5 * alpha)
            love.graphics.polygon("fill", polyBool(x, y, w, BOOL_H))
            return w
        end

        local c = def.color or { 0.22, 0.68, 0.32 }
        love.graphics.setColor(c[1], c[2], c[3], alpha)
        love.graphics.polygon("fill", polyBool(x, y, w, BOOL_H))

        local warned = warn_map and warn_map[node]
        if warned then
            love.graphics.setColor(0.95, 0.62, 0.12, alpha)
            love.graphics.setLineWidth(2)
        else
            love.graphics.setColor(0, 0, 0, 0.22 * alpha)
            love.graphics.setLineWidth(1)
        end
        love.graphics.polygon("line", polyBool(x, y, w, BOOL_H))
        love.graphics.setLineWidth(1)

        -- Warning badge
        if warned then
            love.graphics.setColor(0.95, 0.62, 0.12, alpha)
            love.graphics.print("⚠", x + w - BOOL_ANGLE - 12, y + (BOOL_H - fh) / 2)
        end

        love.graphics.setFont(font)
        love.graphics.setColor(1, 1, 1, alpha)
        local lbl   = def.label or ""
        local tx    = x + BOOL_ANGLE + 6
        love.graphics.print(lbl, tx, y + (BOOL_H - fh) / 2)

        local slot_rects = {}
        local px = tx + font:getWidth(lbl) + 6
        for _, sd in ipairs(def.slots or {}) do
            local val     = node.slots and node.slots[sd.key] or sd.default or ""
            local has_rep = type(val) == "table" and val.kind == "reporter"
            local is_foc  = not has_rep
                            and (sd.type == "number" or sd.type == "string" or sd.type == "text_var_enum" or sd.type == "reporter")
                            and state.slot_input
                            and state.slot_input.node == node
                            and state.slot_input.slot_key == sd.key
            local pill_x = px
            local pw
            if has_rep then
                pw = drawInlineReporter(val, px, y, BOOL_H, font, alpha, slot_rects, sd.key, sd.type)
            else
                pw = drawSlotPill(val, px, y, BOOL_H, font, alpha, is_foc, sd.key)
                slot_rects[#slot_rects+1] = { key = sd.key, x = pill_x, y = y, w = pw, h = BOOL_H, sd_type = sd.type }
            end
            px = px + pw + 4
        end

        if nrects and path then
            nrects[#nrects+1] = { node=node, path=path, x=x, y=y, w=w, h=BOOL_H, slot_rects=slot_rects }
        end
    end

    return w
end

-- ── drawHatNode ───────────────────────────────────────────────────────────────

local function drawHatNode(node, x, y, w, game, nrects, path, alpha)
    local font = game.fonts.ui_small
    local fh   = font:getHeight()
    alpha = alpha or 1.0

    local RE  = require("services.DispatchRuleEngine")
    local def = RE.getDefById(node.def_id)
    local c   = (def and def.color) or { 0.85, 0.65, 0.10 }

    -- Shadow
    love.graphics.setColor(0, 0, 0, 0.22 * alpha)
    love.graphics.polygon("fill", polyHatShadow(x + 2, y + 2, w, STACK_H))

    love.graphics.setColor(c[1], c[2], c[3], alpha)
    love.graphics.polygon("fill", polyHat(x, y, w, STACK_H))
    love.graphics.setColor(1, 1, 1, 0.18 * alpha)
    love.graphics.setLineWidth(1)
    love.graphics.polygon("line", polyHat(x, y, w, STACK_H))
    love.graphics.setLineWidth(1)

    love.graphics.setFont(font)
    love.graphics.setColor(1, 1, 1, alpha)
    local lbl = (def and def.label) or node.def_id
    love.graphics.print(lbl, x + 10, y + (STACK_H - fh) / 2)

    local slot_rects = {}
    if def then
        local px = x + w - 8
        for i = #(def.slots or {}), 1, -1 do
            local sd      = def.slots[i]
            local val     = node.slots and node.slots[sd.key] or sd.default or ""
            local is_foc  = (sd.type == "number" or sd.type == "string" or sd.type == "text_var_enum" or sd.type == "reporter")
                            and state.slot_input
                            and state.slot_input.node == node
                            and state.slot_input.slot_key == sd.key
            local pw = pillWidth(val, font, is_foc, sd.key)
            px = px - pw
            drawSlotPill(val, px, y, STACK_H, font, alpha, is_foc, sd.key)
            slot_rects[#slot_rects+1] = { key = sd.key, x = px, w = pw, sd_type = sd.type }
            px = px - 4
        end
    end

    if nrects and path then
        nrects[#nrects+1] = { node=node, path=path, x=x, y=y, w=w, h=STACK_H, slot_rects=slot_rects }
    end
end

-- ── drawStackNode ─────────────────────────────────────────────────────────────

local function drawStackNode(node, x, y, w, game, nrects, path, warn_map, alpha)
    local font = game.fonts.ui_small
    local fh   = font:getHeight()
    alpha = alpha or 1.0

    local RE  = require("services.DispatchRuleEngine")
    local def = RE.getDefById(node.def_id)
    local c   = (def and def.color) or { 0.28, 0.45, 0.88 }

    -- Shadow
    love.graphics.setColor(0, 0, 0, 0.22 * alpha)
    love.graphics.polygon("fill", polyStackShadow(x + 2, y + 2, w, STACK_H))

    love.graphics.setColor(c[1], c[2], c[3], alpha)
    love.graphics.polygon("fill", polyStack(x, y, w, STACK_H))

    local warned = warn_map and warn_map[node]
    if warned then
        love.graphics.setColor(0.95, 0.62, 0.12, alpha)
        love.graphics.setLineWidth(2)
    else
        love.graphics.setColor(1, 1, 1, 0.15 * alpha)
        love.graphics.setLineWidth(1)
    end
    love.graphics.polygon("line", polyStack(x, y, w, STACK_H))
    love.graphics.setLineWidth(1)

    love.graphics.setFont(font)
    love.graphics.setColor(1, 1, 1, alpha)
    local lbl = (def and def.label) or node.def_id
    love.graphics.print(lbl, x + 10, y + (STACK_H - fh) / 2)

    -- Warning badge
    if warned then
        love.graphics.setColor(0.95, 0.62, 0.12, alpha)
        love.graphics.print("⚠ " .. warn_map[node].warning, x + 10 + font:getWidth(lbl) + 8, y + (STACK_H - fh) / 2)
    end

    local slot_rects = {}
    if def then
        local px = x + w - 8
        
        -- ── Variadic params for block_call ──────────────────────────────────
        if node.def_id == "block_call" and node.slots.action then
            local ACTIONS = require("data.dispatch_actions")
            local action_def = nil
            for _, a in ipairs(ACTIONS) do
                if a.id == node.slots.action then action_def = a; break end
            end
            
            if action_def and action_def.params then
                for i = #action_def.params, 1, -1 do
                    local psd    = action_def.params[i]
                    local val    = node.slots[psd.key] or psd.default or ""
                    local has_rep = type(val) == "table" and val.kind == "reporter"
                    local is_foc = not has_rep
                                     and (psd.type == "number" or psd.type == "string" or psd.type == "text_var_enum" or psd.type == "reporter")
                                     and state.slot_input
                                     and state.slot_input.node == node
                                     and state.slot_input.slot_key == psd.key
                    local pw = pillWidth(val, font, is_foc, psd.key)
                    px = px - pw
                    if has_rep then
                        drawInlineReporter(val, px, y, STACK_H, font, alpha, slot_rects, psd.key, psd.type)
                    else
                        drawSlotPill(val, px, y, STACK_H, font, alpha, is_foc, psd.key)
                        slot_rects[#slot_rects+1] = { key = psd.key, x = px, w = pw, sd_type = psd.type }
                    end
                    px = px - 4
                end
            end
        end

        for i = #(def.slots or {}), 1, -1 do
            local sd       = def.slots[i]
            local val      = node.slots and node.slots[sd.key] or sd.default or ""
            local has_rep  = type(val) == "table" and val.kind == "reporter"
            local is_foc   = not has_rep
                             and (sd.type == "number" or sd.type == "string" or sd.type == "text_var_enum")
                             and state.slot_input
                             and state.slot_input.node == node
                             and state.slot_input.slot_key == sd.key
            local pw = pillWidth(val, font, is_foc, sd.key)
            px = px - pw
            if has_rep then
                drawInlineReporter(val, px, y, STACK_H, font, alpha, slot_rects, sd.key, sd.type)
            else
                drawSlotPill(val, px, y, STACK_H, font, alpha, is_foc, sd.key)
                slot_rects[#slot_rects+1] = { key = sd.key, x = px, w = pw, sd_type = sd.type }
            end
            px = px - 4
        end
    end

    if nrects and path then
        nrects[#nrects+1] = { node=node, path=path, x=x, y=y, w=w, h=STACK_H, slot_rects=slot_rects }
    end
end

-- ── drawControlNode ───────────────────────────────────────────────────────────

drawControlNode = function(node, x, y, w, game, nrects, dtargets, path, warn_map, alpha)
    local font = game.fonts.ui_small
    local fh   = font:getHeight()
    alpha = alpha or 1.0

    local RE  = require("services.DispatchRuleEngine")
    local def = RE.getDefById(node.def_id)

    -- Fetch panel width for wrapping
    local panel_w = game.ui_manager and game.ui_manager.panel and game.ui_manager.panel.w or 400

    local cond_h = BOOL_H
    if node.condition then
        local _, ch = boolNodeSize(node.condition, font, panel_w)
        cond_h = ch
    end
    local header_h = math.max(STACK_H, cond_h + 10)

    local body_h = math.max(MIN_BODY_H, measureStack(node.body or {}, game, panel_w))
    local else_h = nil
    if node.def_id == "ctrl_if_else" and node.else_body then
        else_h = math.max(MIN_BODY_H, measureStack(node.else_body or {}, game, panel_w))
    end

    local ctrl_c = { 0.75, 0.55, 0.08 }

    -- Shadow
    love.graphics.setColor(0, 0, 0, 0.20 * alpha)
    if else_h then
        love.graphics.polygon("fill", polyCElseBlock(x+2, y+2, w, body_h, else_h, header_h))
    else
        love.graphics.polygon("fill", polyCBlock(x+2, y+2, w, body_h, header_h))
    end

    love.graphics.setColor(ctrl_c[1], ctrl_c[2], ctrl_c[3], alpha)
    if else_h then
        love.graphics.polygon("fill", polyCElseBlock(x, y, w, body_h, else_h, header_h))
    else
        love.graphics.polygon("fill", polyCBlock(x, y, w, body_h, header_h))
    end

    if warn_map and warn_map[node] then
        love.graphics.setColor(0.95, 0.62, 0.12, alpha)
        love.graphics.setLineWidth(2)
    else
        love.graphics.setColor(1, 1, 1, 0.15 * alpha)
        love.graphics.setLineWidth(1)
    end
    if else_h then
        love.graphics.polygon("line", polyCElseBlock(x, y, w, body_h, else_h, header_h))
    else
        love.graphics.polygon("line", polyCBlock(x, y, w, body_h, header_h))
    end
    love.graphics.setLineWidth(1)

    -- Inner body background
    love.graphics.setColor(0, 0, 0, 0.20 * alpha)
    love.graphics.rectangle("fill", x + C_INDENT, y + header_h, w - C_INDENT, body_h)
    if else_h then
        local else_start = y + header_h + body_h + CAP_H
        love.graphics.rectangle("fill", x + C_INDENT, else_start, w - C_INDENT, else_h)
    end

    love.graphics.setFont(font)
    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.print("if", x + 8, y + (header_h - fh) / 2)

    -- Condition slot
    local cond_x  = x + C_INDENT + 8
    local cond_y  = y + (header_h - cond_h) / 2
    local cond_path = appendPath(path, "condition")

    if node.condition then
        drawBoolNode(node.condition, cond_x, cond_y, game, nrects, dtargets, cond_path, warn_map, alpha)
        if dtargets and path then
            local cw, ch = boolNodeSize(node.condition, font, panel_w)
            dtargets[#dtargets+1] = {
                parent_path = path, slot = "condition", accepts = "boolean",
                x = cond_x, y = cond_y, w = cw, h = ch
            }
        end
    else
        local ghost_w = 80
        love.graphics.setColor(0.3, 0.3, 0.4, 0.25 * alpha)
        love.graphics.polygon("fill", polyBool(cond_x, cond_y, ghost_w, BOOL_H))
        love.graphics.setColor(0.6, 0.6, 0.8, 0.55 * alpha)
        love.graphics.setLineWidth(1.5)
        love.graphics.polygon("line", polyBool(cond_x, cond_y, ghost_w, BOOL_H))
        love.graphics.setLineWidth(1)
        love.graphics.setColor(0.6, 0.6, 0.8, 0.60 * alpha)
        love.graphics.printf("<cond>", cond_x, cond_y + (BOOL_H - fh) / 2, ghost_w, "center")
        if dtargets and path then
            dtargets[#dtargets+1] = {
                parent_path = path, slot = "condition", accepts = "boolean",
                x = cond_x, y = cond_y, w = ghost_w, h = BOOL_H
            }
        end
    end

    -- Body
    local body_x   = x + C_INDENT
    local body_y   = y + header_h
    local body_w   = w - C_INDENT
    local body_path = appendPath(path, "body")

    if #(node.body or {}) == 0 then
        love.graphics.setColor(0.35, 0.35, 0.50, 0.70 * alpha)
        love.graphics.printf("drop here", body_x, body_y + 10, body_w, "center")
        if dtargets and body_path then
            dtargets[#dtargets+1] = {
                parent_path = body_path, slot = 1, accepts = "stack",
                x = body_x, y = body_y, w = body_w, h = MIN_BODY_H
            }
        end
    else
        drawNodeList(node.body, body_x, body_y, body_w, game, nrects, dtargets, body_path, warn_map, alpha)
    end

    -- Else body
    if else_h then
        local else_start = y + header_h + body_h + CAP_H
        love.graphics.setFont(font)
        love.graphics.setColor(1, 1, 1, alpha * 0.80)
        love.graphics.print("else", x + 8, y + header_h + body_h + (CAP_H - fh) / 2)

        local else_path = appendPath(path, "else_body")
        if #(node.else_body or {}) == 0 then
            love.graphics.setColor(0.35, 0.35, 0.50, 0.70 * alpha)
            love.graphics.printf("drop here", body_x, else_start + 10, body_w, "center")
            if dtargets and else_path then
                dtargets[#dtargets+1] = {
                    parent_path = else_path, slot = 1, accepts = "stack",
                    x = body_x, y = else_start, w = body_w, h = MIN_BODY_H
                }
            end
        else
            drawNodeList(node.else_body, body_x, else_start, body_w, game, nrects, dtargets, else_path, warn_map, alpha)
        end
    end

    if nrects and path then
        nrects[#nrects+1] = { node=node, path=path, x=x, y=y, w=w, h=measureNode(node, game, panel_w), slot_rects={} }
    end
end

-- ── drawLoopNode ──────────────────────────────────────────────────────────────

drawLoopNode = function(node, x, y, w, game, nrects, dtargets, path, warn_map, alpha)
    local font = game.fonts.ui_small
    local fh   = font:getHeight()
    alpha = alpha or 1.0

    local RE  = require("services.DispatchRuleEngine")
    local def = RE.getDefById(node.def_id)

    -- Fetch panel width for wrapping
    local panel_w = game.ui_manager and game.ui_manager.panel and game.ui_manager.panel.w or 400

    local cond_h = BOOL_H
    if node.condition then
        local _, ch = boolNodeSize(node.condition, font, panel_w)
        cond_h = ch
    end
    local header_h = math.max(STACK_H, cond_h + 10)

    local body_h  = math.max(MIN_BODY_H, measureStack(node.body or {}, game, panel_w))
    local loop_c  = { 0.20, 0.55, 0.75 }

    -- Shadow
    love.graphics.setColor(0, 0, 0, 0.20 * alpha)
    love.graphics.polygon("fill", polyCBlock(x+2, y+2, w, body_h, header_h))

    -- Fill
    love.graphics.setColor(loop_c[1], loop_c[2], loop_c[3], alpha)
    love.graphics.polygon("fill", polyCBlock(x, y, w, body_h, header_h))

    -- Outline
    love.graphics.setColor(1, 1, 1, 0.15 * alpha)
    love.graphics.setLineWidth(1)
    love.graphics.polygon("line", polyCBlock(x, y, w, body_h, header_h))
    love.graphics.setLineWidth(1)

    -- Inner body background
    love.graphics.setColor(0, 0, 0, 0.20 * alpha)
    love.graphics.rectangle("fill", x + C_INDENT, y + header_h, w - C_INDENT, body_h)

    -- Header content
    love.graphics.setFont(font)
    love.graphics.setColor(1, 1, 1, alpha)
    local lbl    = (def and def.label) or node.def_id
    local lbl_y  = y + (header_h - fh) / 2

    if node.def_id == "ctrl_repeat_until" then
        -- Label then condition slot
        love.graphics.print(lbl, x + 8, lbl_y)
        local cond_x    = x + 8 + font:getWidth(lbl) + 6
        local cond_y    = y + (header_h - cond_h) / 2
        local cond_path = appendPath(path, "condition")
        if node.condition then
            drawBoolNode(node.condition, cond_x, cond_y, game, nrects, dtargets, cond_path, warn_map, alpha)
            if dtargets and path then
                local cw, ch = boolNodeSize(node.condition, font, panel_w)
                dtargets[#dtargets+1] = {
                    parent_path = path, slot = "condition", accepts = "boolean",
                    x = cond_x, y = cond_y, w = cw, h = ch
                }
            end
        else
            local ghost_w = 70
            love.graphics.setColor(0.3, 0.3, 0.4, 0.25 * alpha)
            love.graphics.polygon("fill", polyBool(cond_x, cond_y, ghost_w, BOOL_H))
            love.graphics.setColor(0.6, 0.6, 0.8, 0.55 * alpha)
            love.graphics.setLineWidth(1.5)
            love.graphics.polygon("line", polyBool(cond_x, cond_y, ghost_w, BOOL_H))
            love.graphics.setLineWidth(1)
            love.graphics.setColor(0.6, 0.6, 0.8, 0.60 * alpha)
            love.graphics.printf("<cond>", cond_x, cond_y + (BOOL_H - fh) / 2, ghost_w, "center")
            if dtargets and path then
                dtargets[#dtargets+1] = {
                    parent_path = path, slot = "condition", accepts = "boolean",
                    x = cond_x, y = cond_y, w = ghost_w, h = BOOL_H
                }
            end
        end
    else
        -- Label + slot pills (right-aligned, like stack nodes)
        love.graphics.setColor(1, 1, 1, alpha)
        love.graphics.print(lbl, x + 8, lbl_y)
        local slot_rects = {}
        if def then
            local px = x + w - 8
            for i = #(def.slots or {}), 1, -1 do
                local sd      = def.slots[i]
                local val     = (node.slots and node.slots[sd.key]) or sd.default or ""
                local has_rep = type(val) == "table" and val.kind == "reporter"
                local is_foc  = not has_rep
                                and (sd.type == "number" or sd.type == "string" or sd.type == "text_var_enum")
                                and state.slot_input
                                and state.slot_input.node == node
                                and state.slot_input.slot_key == sd.key
                local pw  = pillWidth(val, font, is_foc, sd.key)
                px        = px - pw
                drawSlotPill(val, px, y, header_h, font, alpha, is_foc, sd.key)
                slot_rects[#slot_rects+1] = { key = sd.key, x = px, w = pw, sd_type = sd.type }
                px = px - 4
            end
        end
        if nrects and path then
            nrects[#nrects+1] = { node=node, path=path, x=x, y=y, w=w, h=header_h, slot_rects=slot_rects }
        end
    end

    -- Body
    local body_x    = x + C_INDENT
    local body_y    = y + header_h
    local body_w    = w - C_INDENT
    local body_path = appendPath(path, "body")

    if #(node.body or {}) == 0 then
        love.graphics.setColor(0.35, 0.35, 0.50, 0.70 * alpha)
        love.graphics.printf("drop here", body_x, body_y + 10, body_w, "center")
        if dtargets and body_path then
            dtargets[#dtargets+1] = {
                parent_path = body_path, slot = 1, accepts = "stack",
                x = body_x, y = body_y, w = body_w, h = MIN_BODY_H
            }
        end
    else
        drawNodeList(node.body, body_x, body_y, body_w, game, nrects, dtargets, body_path, warn_map, alpha)
    end

    -- Register full nrect (for ctrl_repeat_until which skips the slot_rects path above)
    if nrects and path then
        local already = false
        for _, r in ipairs(nrects) do
            if r.node == node then already = true; break end
        end
        if not already then
            nrects[#nrects+1] = { node=node, path=path, x=x, y=y, w=w, h=measureNode(node, game, panel_w), slot_rects={} }
        end
    end
end

-- ── drawFindNode ─────────────────────────────────────────────────────────────
-- C-block (teal-blue) with sort pills + condition slot in header.
drawFindNode = function(node, x, y, w, game, nrects, dtargets, path, warn_map, alpha)
    local font = game.fonts.ui_small
    local fh   = font:getHeight()
    alpha = alpha or 1.0

    local RE  = require("services.DispatchRuleEngine")
    local def = RE.getDefById(node.def_id)

    -- Fetch panel width for wrapping
    local panel_w = game.ui_manager and game.ui_manager.panel and game.ui_manager.panel.w or 400

    local cond_h = BOOL_H
    if node.condition then
        local _, ch = boolNodeSize(node.condition, font, panel_w)
        cond_h = ch
    end
    local header_h = STACK_H + math.max(STACK_H, cond_h + 6)

    local body_h  = math.max(MIN_BODY_H, measureStack(node.body or {}, game, panel_w))
    local find_c  = { 0.20, 0.55, 0.75 }
    -- Shadow + fill
    love.graphics.setColor(0, 0, 0, 0.20 * alpha)
    love.graphics.polygon("fill", polyCBlock(x+2, y+2, w, body_h, header_h))
    love.graphics.setColor(find_c[1], find_c[2], find_c[3], alpha)
    love.graphics.polygon("fill", polyCBlock(x, y, w, body_h, header_h))
    love.graphics.setColor(1, 1, 1, 0.15 * alpha)
    love.graphics.setLineWidth(1)
    love.graphics.polygon("line", polyCBlock(x, y, w, body_h, header_h))
    love.graphics.setLineWidth(1)

    -- Inner body background
    love.graphics.setColor(0, 0, 0, 0.20 * alpha)
    love.graphics.rectangle("fill", x + C_INDENT, y + header_h, w - C_INDENT, body_h)

    -- ── Header: Row 1 — Find [coll] sorted by [sort] as [var] ──────────
    love.graphics.setFont(font)
    local lbl        = (def and def.label) or node.def_id
    local slot_rects = {}
    local hx         = x + 10
    local hy         = y

    -- "Find" label
    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.print(lbl, hx, hy + (STACK_H - fh) / 2)
    hx = hx + font:getWidth(lbl) + 8

    local slots = def and def.slots or {}
    for _, sd in ipairs(slots) do
        -- Inter-slot labels
        if sd.key == "sorter" then
            love.graphics.setColor(1, 1, 1, 0.6 * alpha)
            love.graphics.print("sorted by", hx, hy + (STACK_H - fh) / 2)
            hx = hx + font:getWidth("sorted by") + 8
        elseif sd.key == "variable" then
            love.graphics.setColor(1, 1, 1, 0.6 * alpha)
            love.graphics.print("as", hx, hy + (STACK_H - fh) / 2)
            hx = hx + font:getWidth("as") + 8
        end

        local val    = (node.slots and node.slots[sd.key]) or sd.default
        local is_foc = (sd.type == "number" or sd.type == "string" or sd.type == "text_var_enum" or sd.type == "reporter")
                       and state.slot_input
                       and state.slot_input.node == node
                       and state.slot_input.slot_key == sd.key

        local vstr = pillDisplay(val, is_foc, sd.key)
        local fw = font:getWidth(vstr)
        local pw = math.max(fw + 16, is_foc and 36 or 0)
        local pill_x = hx

        if is_foc and state.slot_input then
            state.slot_input.input:draw(pill_x, hy + (STACK_H - 16) / 2, pw, 16)
        else
            -- Use distinct color for variable slot
            if sd.key == "variable" then
                love.graphics.setColor(0.40, 0.25, 0.60, 0.90 * alpha)
            else
                love.graphics.setColor(0, 0, 0, 0.35 * alpha)
            end
            love.graphics.rectangle("fill", pill_x, hy + (STACK_H - 16) / 2, pw, 16, 3, 3)
            
            if sd.key == "variable" then
                love.graphics.setColor(0.70, 0.50, 0.90, 0.40 * alpha)
            else
                love.graphics.setColor(1, 1, 1, 0.18 * alpha)
            end
            love.graphics.rectangle("line", pill_x, hy + (STACK_H - 16) / 2, pw, 16, 3, 3)
            
            love.graphics.setColor(1, 1, 1, alpha)
            love.graphics.print(vstr, pill_x + 7, hy + (STACK_H - fh) / 2)
        end

        slot_rects[#slot_rects+1] = { key = sd.key, x = pill_x, y = hy, w = pw, h = STACK_H, sd_type = sd.type }
        hx = hx + pw + 4
    end

    -- ── Header: Row 2 — where [cond] ──────────────────────────────────
    hx = x + 14 -- Indent slightly for the second row
    hy = y + STACK_H
    local row2_h = header_h - STACK_H

    love.graphics.setColor(1, 1, 1, 0.6 * alpha)
    love.graphics.print("where", hx, hy + (row2_h - fh) / 2)
    hx = hx + font:getWidth("where") + 10

    -- Condition slot
    local cond_path = path and appendPath(path, "condition") or nil
    local cond_y    = hy + (row2_h - cond_h) / 2
    drawBoolNode(node.condition, hx, cond_y, game, nrects, dtargets, cond_path, warn_map, alpha)

    if dtargets and path then
        local cw, ch = boolNodeSize(node.condition, font, panel_w)
        dtargets[#dtargets+1] = {
            parent_path = path, slot = "condition", accepts = "boolean",
            x = hx, y = cond_y, w = cw, h = ch
        }
    end

    -- ── Body ─────────────────────────────────────────────────────────────────
    local body_x    = x + C_INDENT
    local body_y    = y + header_h
    local body_w    = w - C_INDENT
    local body_path = path and appendPath(path, "body") or nil

    if not node.body or #node.body == 0 then
        love.graphics.setColor(1, 1, 1, 0.18 * alpha)
        love.graphics.printf("drop actions here", body_x, body_y + 10, body_w, "center")
        if dtargets and body_path then
            dtargets[#dtargets+1] = {
                parent_path = body_path, slot = 1, accepts = "stack",
                x = body_x, y = body_y, w = body_w, h = MIN_BODY_H
            }
        end
    else
        drawNodeList(node.body, body_x, body_y, body_w, game, nrects, dtargets, body_path, warn_map, alpha)
    end

    if nrects and path then
        nrects[#nrects+1] = { node=node, path=path, x=x, y=y, w=w, h=measureNode(node, game, panel_w), slot_rects=slot_rects }
    end
end

-- ── drawNodeList ──────────────────────────────────────────────────────────────

drawNodeList = function(stack, x, y, w, game, nrects, dtargets, path_prefix, warn_map, alpha)
    local cy = y

    if dtargets and path_prefix then
        dtargets[#dtargets+1] = {
            parent_path = path_prefix, slot = 1, accepts = "stack",
            x = x, y = cy - 10, w = w, h = 20
        }
    end

    -- Pass 1: compute layout, register drop targets
    local items = {}
    local font  = game.fonts.ui_small
    -- Fetch panel width for wrapping
    local panel_w = game.ui_manager and game.ui_manager.panel and game.ui_manager.panel.w or 400

    for i, node in ipairs(stack or {}) do
        local node_path = appendPath(path_prefix, i)
        local nh = measureNode(node, game, panel_w)
        local nw
        if node.kind == "hat" or node.kind == "stack" then
            nw = math.min(w, stackNaturalW(node, font))
        elseif node.kind == "control" then
            nw = math.min(w, controlNaturalW(node, font, panel_w))
        elseif node.kind == "loop" then
            nw = math.min(w, loopNaturalW(node, font, panel_w))
        elseif node.kind == "find" then
            nw = math.min(w, controlNaturalW(node, font, panel_w))
        else
            nw = math.min(w, 200)
        end
        items[i] = { node = node, node_path = node_path, cy = cy, nw = nw, nh = nh }
        cy = cy + nh
        if dtargets and path_prefix then
            dtargets[#dtargets+1] = {
                parent_path = path_prefix, slot = i + 1, accepts = "stack",
                x = x, y = cy - 10, w = w, h = 20
            }
        end
    end

    -- Pass 2: draw bottom-to-top so upper blocks paint over lower notches
    for i = #items, 1, -1 do
        local it   = items[i]
        local node = it.node
        if node.kind == "hat" then
            drawHatNode(node, x, it.cy, it.nw, game, nrects, it.node_path, alpha)
        elseif node.kind == "stack" then
            drawStackNode(node, x, it.cy, it.nw, game, nrects, it.node_path, warn_map, alpha)
        elseif node.kind == "control" then
            drawControlNode(node, x, it.cy, it.nw, game, nrects, dtargets, it.node_path, warn_map, alpha)
        elseif node.kind == "loop" then
            drawLoopNode(node, x, it.cy, it.nw, game, nrects, dtargets, it.node_path, warn_map, alpha)
        elseif node.kind == "find" then
            drawFindNode(node, x, it.cy, it.nw, game, nrects, dtargets, it.node_path, warn_map, alpha)
        end
    end

    return cy - y
end

-- ── Rule card component ───────────────────────────────────────────────────────

local function makeRuleCard(rule_i, rule, game, panel_w)
    local pad      = RULE_PAD
    local stack    = rule.stack or {}
    local font     = game.fonts.ui_small
    local stack_h  = measureStack(stack, game, panel_w)
    local inner_h  = math.max(MIN_BODY_H, stack_h)
    local is_open  = state.palette_open and state.selected_rule == rule_i
    local is_coll  = state.collapsed_rules[rule.id or ""]
    local total_h  = is_coll
                     and (pad + HDR_H + pad)
                     or  (pad + HDR_H + inner_h + ADDBTN_H + pad)

    return {
        type  = "custom",
        h     = total_h,

        draw_fn = function(px, y, pw, h, game)
            state.rule_card_tops[rule_i] = y
            state.rule_card_bots[rule_i] = y + h

            local font  = game.fonts.ui_small
            local fh    = font:getHeight()
            local inner = pw - pad * 2

            -- Card background
            love.graphics.setColor(0.12, 0.12, 0.18, 1)
            love.graphics.rectangle("fill", px + pad, y, inner, h, 6, 6)

            -- Colored left accent bar
            local accent = rule.enabled and { 0.35, 0.55, 1.0 } or { 0.28, 0.28, 0.38 }
            love.graphics.setColor(accent)
            love.graphics.rectangle("fill", px + pad, y, 4, h, 3, 3)

            -- Header background
            love.graphics.setColor(0.18, 0.18, 0.27)
            love.graphics.rectangle("fill", px + pad, y, inner, HDR_H)

            -- Enable dot + rule label
            love.graphics.setFont(font)
            local mark = rule.enabled and "● " or "○ "
            local en_c = rule.enabled and {0.45, 0.75, 1.0} or {0.40, 0.40, 0.55}
            love.graphics.setColor(en_c)
            love.graphics.print(string.format("%sRule %d", mark, rule_i), px + pad + 10, y + (HDR_H - fh) / 2)

            -- Collapse button (left of del)
            local col_lbl = is_coll and "▸" or "▾"
            local col_w   = font:getWidth(col_lbl) + 12
            -- Del button
            local del_lbl = "del"
            local del_w   = font:getWidth(del_lbl) + 12
            local del_x   = px + pw - pad - del_w - 4
            local del_y   = y + (HDR_H - 18) / 2
            local col_x   = del_x - col_w - 4

            love.graphics.setColor(0.50, 0.20, 0.20)
            love.graphics.rectangle("fill", del_x, del_y, del_w, 18, 3, 3)
            love.graphics.setColor(0.90, 0.50, 0.50)
            love.graphics.printf(del_lbl, del_x, del_y + (18 - fh) / 2, del_w, "center")

            love.graphics.setColor(0.20, 0.30, 0.50)
            love.graphics.rectangle("fill", col_x, del_y, col_w, 18, 3, 3)
            love.graphics.setColor(0.60, 0.70, 0.95)
            love.graphics.printf(col_lbl, col_x, del_y + (18 - fh) / 2, col_w, "center")

            -- Dim card when being dragged
            local drag = state.drag
            local is_dragging_this = drag and drag.active and drag.type == "rule" and drag.rule_i == rule_i
            if is_dragging_this then
                love.graphics.setColor(0, 0, 0, 0.55)
                love.graphics.rectangle("fill", px + pad, y, inner, h, 6, 6)
            end

            -- Rule reorder drop line
            if drag and drag.active and drag.type == "rule" and not is_dragging_this then
                local panel  = game.ui_manager.panel
                local cy     = panel:toContentY(drag.cy)
                if cy >= y - 12 and cy < y + h / 2 then
                    love.graphics.setColor(0.4, 0.6, 1.0, 0.9)
                    love.graphics.setLineWidth(2)
                    love.graphics.line(px + pad, y, px + pw - pad, y)
                    love.graphics.setLineWidth(1)
                elseif rule_i == #game.state.dispatch_rules and cy >= y + h / 2 then
                    love.graphics.setColor(0.4, 0.6, 1.0, 0.9)
                    love.graphics.setLineWidth(2)
                    love.graphics.line(px + pad, y + h, px + pw - pad, y + h)
                    love.graphics.setLineWidth(1)
                end
            end

            -- Skip body when collapsed
            if is_coll then
                love.graphics.setColor(1, 1, 1)
                return
            end

            -- Stack area
            local sx       = px + pad + 6
            local sy       = y + HDR_H + pad / 2
            local sw       = inner - 12
            local nrects   = {}
            local dtargets = {}
            state.node_rects[rule_i]   = nrects
            state.drop_targets[rule_i] = dtargets

            local warn_map = {}
            if #stack > 0 then
                local ok, w = pcall(require("services.DispatchValidator").getTreeWarnings, rule, game)
                if ok then warn_map = w end
            end

            if #stack == 0 then
                love.graphics.setFont(font)
                love.graphics.setColor(0.30, 0.30, 0.45)
                love.graphics.printf("drag blocks from palette", sx, sy + 8, sw, "center")
                dtargets[#dtargets+1] = {
                    parent_path = {}, slot = 1, accepts = "stack",
                    x = sx, y = sy, w = math.min(sw, STACK_W_MAX), h = MIN_BODY_H
                }
            else
                drawNodeList(stack, sx, sy, sw, game, nrects, dtargets, {}, warn_map, 1.0)

                -- Register reporter drop targets from slots in drawn nodes
                for _, nr in ipairs(nrects) do
                    for _, sr in ipairs(nr.slot_rects or {}) do
                        if sr.sd_type == "number" or sr.sd_type == "string" or sr.sd_type == "reporter" then
                            dtargets[#dtargets+1] = {
                                accepts     = "reporter",
                                x           = sr.x,
                                y           = nr.y,
                                w           = sr.w,
                                h           = nr.h,
                                parent_path = nr.path,
                                slot        = sr.key,
                            }
                        end
                    end
                end
            end

            -- "Add Blocks" toggle button
            local ab_y = y + h - pad - ADDBTN_H
            love.graphics.setColor(0.15, 0.15, 0.24)
            love.graphics.rectangle("fill", px + pad + 4, ab_y, inner - 8, ADDBTN_H, 3, 3)
            love.graphics.setColor(
                is_open and 0.4 or 0.25,
                is_open and 0.4 or 0.25,
                is_open and 0.72 or 0.45)
            love.graphics.rectangle("line", px + pad + 4, ab_y, inner - 8, ADDBTN_H, 3, 3)
            love.graphics.setColor(is_open and 0.80 or 0.55, is_open and 0.80 or 0.55, 1)
            love.graphics.printf(is_open and "▲ Close Palette" or "▼ Add Blocks",
                px + pad + 4, ab_y + (ADDBTN_H - fh) / 2, inner - 8, "center")

            love.graphics.setColor(1, 1, 1)
        end,

        hit_fn = function(px, cy_start, pw, h, mx, my)
            local font  = love.graphics.getFont()

            -- Header strip
            if my < cy_start + HDR_H then
                local del_lbl = "del"
                local del_w   = font:getWidth(del_lbl) + 12
                local del_x   = px + pw - pad - del_w - 4
                local col_lbl = "▾"
                local col_w   = font:getWidth(col_lbl) + 12
                local col_x   = del_x - col_w - 4
                if mx >= del_x then
                    return { id = "dispatch_delete_rule", data = { rule_i = rule_i } }
                end
                if mx >= col_x and mx < del_x then
                    return { id = "dispatch_toggle_collapse", data = { rule_i = rule_i } }
                end
                return { id = "dispatch_rule_header_press", data = { rule_i = rule_i } }
            end

            if is_coll then return nil end

            -- "Add Blocks" strip
            local ab_y = cy_start + h - pad - ADDBTN_H
            if my >= ab_y then
                return { id = "dispatch_toggle_palette", data = { rule_i = rule_i } }
            end

            -- Node rects
            local nrects = state.node_rects[rule_i] or {}
            for _, r in ipairs(nrects) do
                if mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h then
                    for _, sp in ipairs(r.slot_rects or {}) do
                        -- Use precise vertical check if available, else fallback to node y/h
                        local sy = sp.y or r.y
                        local sh = sp.h or r.h
                        if mx >= sp.x and mx <= sp.x + sp.w and my >= sy and my <= sy + sh then
                            -- Inner reporter sub-slot (cycle/edit the reporter node's own slot)
                            if sp.sd_type == "rep_inner" then
                                return { id = "dispatch_cycle_rep_inner_slot",
                                         data = { rep_node = sp.rep_node, rep_key = sp.rep_key, rep_sd = sp.rep_sd } }
                            end
                            if sp.sd_type == "number" or sp.sd_type == "string" or sp.sd_type == "reporter" then
                                return { id = "dispatch_focus_slot",
                                         data = { rule_i = rule_i, path = r.path,
                                                  slot_key = sp.key, node = r.node } }
                            end
                            return { id = "dispatch_cycle_slot",
                                     data = { rule_i = rule_i, path = r.path, slot_key = sp.key } }
                        end
                    end
                    return { id = "dispatch_node_press",
                             data = { rule_i = rule_i, path = r.path, node = r.node } }
                end
            end
            return nil
        end,
    }
end

-- ── Palette filter helpers ────────────────────────────────────────────────────

-- Returns the subset of `all` that passes the current tag + search filters.
-- Multi-tag: a block passes only if it has ALL active tags (AND semantics).
local function filterDefs(all, filter)
    local has_tags   = next(filter.active_tags) ~= nil
    local search     = filter.search:lower()
    local result     = {}
    for _, def in ipairs(all) do
        -- Tag: must have every active tag
        local tag_ok = true
        if has_tags then
            for t in pairs(filter.active_tags) do
                local found = false
                if def.tags then
                    for _, dt in ipairs(def.tags) do
                        if dt == t then found = true; break end
                    end
                end
                if not found then tag_ok = false; break end
            end
        end
        -- Search: pass if empty or matches label or tooltip text
        local search_ok = search == ""
            or (def.label   and def.label:lower():find(search, 1, true))
            or (def.tooltip and def.tooltip:lower():find(search, 1, true))
        if tag_ok and search_ok then result[#result+1] = def end
    end
    return result
end

-- Groups a flat list of defs by category, sorted by hue within each group.
-- Returns an array of { cat, defs } in the canonical category order.
local CAT_ORDER = { "hat", "control", "loop", "find", "boolean", "reporter", "stack" }

local function rgbHue(r, g, b)
    local mx = math.max(r, g, b)
    local mn = math.min(r, g, b)
    local d  = mx - mn
    if d < 0.001 then return 0 end  -- achromatic
    local h
    if mx == r then     h = (g - b) / d % 6
    elseif mx == g then h = (b - r) / d + 2
    else                h = (r - g) / d + 4
    end
    return h / 6  -- 0–1
end

local function groupDefs(visible)
    local by_cat  = {}
    local seen    = {}
    for _, def in ipairs(visible) do
        local c = def.category
        if not by_cat[c] then by_cat[c] = {}; seen[#seen+1] = c end
        by_cat[c][#by_cat[c]+1] = def
    end
    -- Sort each group by hue so same-coloured blocks cluster together
    for _, defs in pairs(by_cat) do
        table.sort(defs, function(a, b)
            local ca, cb = a.color or {0.5,0.5,0.5}, b.color or {0.5,0.5,0.5}
            return rgbHue(ca[1],ca[2],ca[3]) < rgbHue(cb[1],cb[2],cb[3])
        end)
    end
    local groups = {}
    for _, c in ipairs(CAT_ORDER) do
        if by_cat[c] then groups[#groups+1] = { cat=c, defs=by_cat[c] }; by_cat[c]=nil end
    end
    for _, c in ipairs(seen) do
        if by_cat[c] then groups[#groups+1] = { cat=c, defs=by_cat[c] } end
    end
    return groups
end

-- Returns tooltip text for a def (plain, no tags — tags rendered as pills separately).
local function defTooltip(def)
    if not def then return nil end
    return def.tooltip ~= "" and def.tooltip or nil
end

-- Computes the pixel height consumed by the filter header (tag pills + search field).
-- Mirrors the wrapping logic in draw_fn so height is accurate before drawing.
local function calcFilterHeaderH(font, pw, pad)
    local cx, rows = pad, 1
    for _, td in ipairs(TAG_DEFS) do
        local pill_w = font:getWidth(td.label) + TAG_PILL_PAD * 2
        if cx + pill_w > pw - pad and cx > pad then rows = rows + 1; cx = pad end
        cx = cx + pill_w + TAG_GAP
    end
    -- Clear-all pill — check if it wraps (treated as another pill)
    local clear_w = font:getWidth("✕ clear") + TAG_PILL_PAD * 2
    if cx + clear_w > pw - pad and cx > pad then rows = rows + 1 end
    return rows * (TAG_PILL_H + TAG_GAP) + PAL_GAP + SEARCH_H + PAL_GAP
end

-- ── Palette component ─────────────────────────────────────────────────────────

local function makePalette(rule_i, panel_w)
    local RE  = require("services.DispatchRuleEngine")
    local all = RE.getAllDefs()
    local pad = PAL_PAD

    -- Height per row accounts for stack shape protrusion
    local function rowH(cat)
        return (cat == "stack") and (PAL_BLOCK_H + NOTCH_H) or PAL_BLOCK_H
    end

    local function calcPrefabSectionH(font, pw, prefabs)
        if #prefabs == 0 then return 0 end
        local cy = CAT_HDR_H
        local cx = pad
        for _, pf in ipairs(prefabs) do
            local bw = math.max(70, font:getWidth(pf.label or "") + 24)
            if cx + bw > pw - pad and cx > pad then cx = pad; cy = cy + PAL_BLOCK_H + PAL_GAP end
            cx = cx + bw + PAL_GAP
        end
        return cy + PAL_BLOCK_H + PAL_GAP + 6
    end

    local function calcPaletteH(pw)
        local font     = love.graphics.getFont()
        local filter_h = calcFilterHeaderH(font, pw, pad)
        local prefabs  = require("data.dispatch_prefabs")
        local pref_h   = calcPrefabSectionH(font, pw, prefabs)
        local groups   = groupDefs(filterDefs(all, state.palette_filter))
        if #groups == 0 then
            return pad + filter_h + pref_h + 40 + pad
        end
        local cy = pad + filter_h + pref_h
        for _, g in ipairs(groups) do
            cy = cy + CAT_HDR_H  -- section header
            local cx = pad
            for _, def in ipairs(g.defs) do
                local bw = math.max(70, font:getWidth(def.label or "") + 24)
                if cx + bw > pw - pad and cx > pad then cx = pad; cy = cy + rowH(g.cat) + PAL_GAP end
                cx = cx + bw + PAL_GAP
            end
            cy = cy + rowH(g.cat) + PAL_GAP + 6  -- row + spacing after section
        end
        return cy + pad
    end

    local comp_h = calcPaletteH(panel_w)

    return {
        type = "custom",
        h    = comp_h,

        draw_fn = function(px, y, pw, h, game)
            love.graphics.setColor(0.09, 0.09, 0.14)
            love.graphics.rectangle("fill", px, y, pw, h)
            love.graphics.setColor(0.22, 0.22, 0.35)
            love.graphics.rectangle("line", px, y, pw, h)

            local font    = game.fonts.ui_small
            local fh      = font:getHeight()
            local rule    = (game.state.dispatch_rules or {})[rule_i]
            local validity = Validator.getPaletteValidity({ rule = rule, dropping_into = state.drag and state.drag.slot_type }, game)
            local filter  = state.palette_filter
            local has_any_filter = next(filter.active_tags) ~= nil or filter.search ~= ""

            -- ── Tag filter pills ────────────────────────────────────────────
            local frects = {}
            state.palette_filter_rects = frects

            local fcx = px + pad
            local fcy = y + pad
            love.graphics.setFont(font)

            for _, td in ipairs(TAG_DEFS) do
                local pill_w  = font:getWidth(td.label) + TAG_PILL_PAD * 2
                if fcx + pill_w > px + pw - pad and fcx > px + pad then
                    fcx = px + pad
                    fcy = fcy + TAG_PILL_H + TAG_GAP
                end
                local active = filter.active_tags[td.id]
                local c      = td.color

                if active then
                    love.graphics.setColor(c[1], c[2], c[3], 1.0)
                    love.graphics.rectangle("fill", fcx, fcy, pill_w, TAG_PILL_H, 3, 3)
                    love.graphics.setColor(1, 1, 1, 0.20)
                    love.graphics.rectangle("line", fcx, fcy, pill_w, TAG_PILL_H, 3, 3)
                    love.graphics.setColor(1, 1, 1, 1.0)
                else
                    love.graphics.setColor(0.14, 0.14, 0.22, 1.0)
                    love.graphics.rectangle("fill", fcx, fcy, pill_w, TAG_PILL_H, 3, 3)
                    -- Coloured left accent bar
                    love.graphics.setColor(c[1], c[2], c[3], 0.75)
                    love.graphics.rectangle("fill", fcx, fcy, 3, TAG_PILL_H, 3, 3)
                    love.graphics.setColor(0.55, 0.55, 0.70, 1.0)
                end
                love.graphics.printf(td.label, fcx, fcy + (TAG_PILL_H - fh) / 2, pill_w, "center")

                frects[#frects+1] = { tag=td.id, x=fcx, y=fcy, w=pill_w, h=TAG_PILL_H }
                fcx = fcx + pill_w + TAG_GAP
            end

            -- Clear-all pill (only when a filter is active)
            if has_any_filter then
                local cpill_w = font:getWidth("✕ clear") + TAG_PILL_PAD * 2
                if fcx + cpill_w > px + pw - pad and fcx > px + pad then
                    fcx = px + pad
                    fcy = fcy + TAG_PILL_H + TAG_GAP
                end
                love.graphics.setColor(0.35, 0.15, 0.15, 1.0)
                love.graphics.rectangle("fill", fcx, fcy, cpill_w, TAG_PILL_H, 3, 3)
                love.graphics.setColor(0.90, 0.55, 0.55, 1.0)
                love.graphics.printf("✕ clear", fcx, fcy + (TAG_PILL_H - fh) / 2, cpill_w, "center")
                frects[#frects+1] = { tag="_clear", x=fcx, y=fcy, w=cpill_w, h=TAG_PILL_H }
                fcx = fcx + cpill_w + TAG_GAP
            end

            -- Advance fcy past last pill row
            fcy = fcy + TAG_PILL_H + TAG_GAP

            -- ── Search field ────────────────────────────────────────────────
            local sf_x = px + pad
            local sf_y = fcy + PAL_GAP / 2
            local sf_w = pw - pad * 2
            local sf_h = SEARCH_H

            if not state.search_input then
                state.search_input = TextInput:new("", filter.search, "text", function(val)
                    filter.search = val
                end, game)
            end
            state.search_input.value = filter.search
            state.search_input.is_focused = filter.search_focused
            state.search_input:draw(sf_x, sf_y, sf_w, sf_h)

            local icon_w = font:getWidth("⌕") + 6
            love.graphics.setColor(0.45, 0.45, 0.62, 1.0)
            love.graphics.print("⌕", sf_x + 5, sf_y + (sf_h - fh) / 2)

            if filter.search == "" and not filter.search_focused then
                love.graphics.setColor(0.35, 0.35, 0.52, 1.0)
                love.graphics.print("search blocks...", sf_x + icon_w + 4, sf_y + (sf_h - fh) / 2)
            end

            state.palette_search_rect = { x=sf_x, y=sf_y, w=sf_w, h=sf_h }

            -- ── Prefabs section ──────────────────────────────────────────────
            local prefabs  = require("data.dispatch_prefabs")
            local prects   = {}
            local cy       = sf_y + sf_h + PAL_GAP

            if #prefabs > 0 then
                -- Section header
                love.graphics.setFont(font)
                love.graphics.setColor(0.75, 0.60, 0.25)
                love.graphics.print("PREFABS", px + pad, cy)
                cy = cy + CAT_HDR_H

                local cx = px + pad
                local pfab_rects = {}
                for _, pf in ipairs(prefabs) do
                    local bw = math.max(70, font:getWidth(pf.label or "") + 24)
                    if cx + bw > px + pw - pad and cx > px + pad then
                        cx = px + pad
                        cy = cy + PAL_BLOCK_H + PAL_GAP
                    end

                    local c = pf.color or { 0.75, 0.60, 0.25 }
                    -- Drop shadow
                    love.graphics.setColor(0, 0, 0, 0.25)
                    if pf.kind == "bool" then
                        love.graphics.polygon("fill", polyBool(cx+1, cy+2, bw, PAL_BLOCK_H))
                    else
                        love.graphics.polygon("fill", polyStack(cx+1, cy+2, bw, PAL_BLOCK_H - NOTCH_H))
                    end
                    -- Shape fill
                    love.graphics.setColor(c[1], c[2], c[3], 1.0)
                    if pf.kind == "bool" then
                        love.graphics.polygon("fill", polyBool(cx, cy, bw, PAL_BLOCK_H))
                    else
                        love.graphics.polygon("fill", polyStack(cx, cy, bw, PAL_BLOCK_H - NOTCH_H))
                    end
                    -- Border
                    love.graphics.setColor(1, 1, 1, 0.18)
                    love.graphics.setLineWidth(1)
                    if pf.kind == "bool" then
                        love.graphics.polygon("line", polyBool(cx, cy, bw, PAL_BLOCK_H))
                    else
                        love.graphics.polygon("line", polyStack(cx, cy, bw, PAL_BLOCK_H - NOTCH_H))
                    end
                    -- Label
                    love.graphics.setColor(1, 1, 1, 1.0)
                    local lbl_h = (pf.kind == "bool") and PAL_BLOCK_H or (PAL_BLOCK_H - NOTCH_H)
                    love.graphics.printf(pf.label or pf.id, cx, cy + (lbl_h - fh) / 2, bw, "center")
                    -- Star marker
                    love.graphics.setColor(1.0, 0.90, 0.40, 0.7)
                    love.graphics.circle("fill", cx + bw - 5, cy + 5, 2)

                    pfab_rects[pf.id] = { x=cx, y=cy, w=bw, h=lbl_h, pf=pf }
                    cx = cx + bw + PAL_GAP
                end
                state.palette_prefab_rects = pfab_rects
                cy = cy + PAL_BLOCK_H + PAL_GAP + 6
            end

            -- ── Block list (filtered + grouped by category) ──────────────────
            local groups = groupDefs(filterDefs(all, filter))
            local bprects = {}

            if #groups == 0 then
                love.graphics.setFont(font)
                love.graphics.setColor(0.38, 0.38, 0.55)
                love.graphics.printf("no blocks match", px, cy + 10, pw, "center")
            else
                for _, g in ipairs(groups) do
                    local cat = g.cat
                    -- Section header
                    love.graphics.setFont(font)
                    love.graphics.setColor(0.50, 0.50, 0.68)
                    love.graphics.print(cat:upper(), px + pad, cy)
                    cy = cy + CAT_HDR_H

                    local cx = px + pad
                    for _, def in ipairs(g.defs) do
                        love.graphics.setFont(font)
                        local bw = math.max(70, font:getWidth(def.label or "") + 24)
                        if cx + bw > px + pw - pad and cx > px + pad then
                            cx = px + pad
                            cy = cy + rowH(cat) + PAL_GAP
                        end

                        local v  = validity[def.id]
                        local ok = not v or v.valid
                        local a  = ok and 1.0 or 0.18
                        local c  = def.color or { 0.5, 0.5, 0.5 }

                        -- Drop shadow
                        if ok then
                            love.graphics.setColor(0, 0, 0, 0.25)
                            if cat == "hat" then
                                love.graphics.polygon("fill", polyHat(cx+1, cy+2, bw, PAL_BLOCK_H - NOTCH_H))
                            elseif cat == "boolean" then
                                love.graphics.polygon("fill", polyBool(cx+1, cy+2, bw, PAL_BLOCK_H))
                            elseif cat == "stack" then
                                love.graphics.polygon("fill", polyStack(cx+1, cy+2, bw, PAL_BLOCK_H - NOTCH_H))
                            end
                        end

                        -- Shape fill
                        love.graphics.setColor(c[1], c[2], c[3], a)
                        if cat == "hat" then
                            love.graphics.polygon("fill", polyHat(cx, cy, bw, PAL_BLOCK_H - NOTCH_H))
                        elseif cat == "boolean" then
                            love.graphics.polygon("fill", polyBool(cx, cy, bw, PAL_BLOCK_H))
                        elseif cat == "stack" then
                            love.graphics.polygon("fill", polyStack(cx, cy, bw, PAL_BLOCK_H - NOTCH_H))
                        else
                            love.graphics.polygon("fill", polyHat(cx, cy, bw, PAL_BLOCK_H - NOTCH_H))
                        end

                        -- Border
                        love.graphics.setColor(1, 1, 1, 0.18 * a)
                        love.graphics.setLineWidth(1)
                        if cat == "hat" then
                            love.graphics.polygon("line", polyHat(cx, cy, bw, PAL_BLOCK_H - NOTCH_H))
                        elseif cat == "boolean" then
                            love.graphics.polygon("line", polyBool(cx, cy, bw, PAL_BLOCK_H))
                        elseif cat == "stack" then
                            love.graphics.polygon("line", polyStack(cx, cy, bw, PAL_BLOCK_H - NOTCH_H))
                        else
                            love.graphics.polygon("line", polyHat(cx, cy, bw, PAL_BLOCK_H - NOTCH_H))
                        end
                        love.graphics.setLineWidth(1)

                        -- Label
                        love.graphics.setColor(1, 1, 1, a)
                        local lbl_h = (cat == "boolean") and PAL_BLOCK_H or (PAL_BLOCK_H - NOTCH_H)
                        love.graphics.printf(def.label or def.id, cx, cy + (lbl_h - fh) / 2, bw, "center")

                        -- Tooltip hint dot
                        if ok and def.tooltip then
                            love.graphics.setColor(0.55, 0.55, 0.75, 0.6)
                            love.graphics.circle("fill", cx + bw - 5, cy + 5, 2)
                        end

                        bprects[def.id] = { x=cx, y=cy, w=bw, h=lbl_h, def=def, valid=ok }
                        cx = cx + bw + PAL_GAP
                    end

                    cy = cy + rowH(cat) + PAL_GAP + 6  -- advance past last row + inter-section gap
                end
            end

            state.palette_rects = bprects
            love.graphics.setColor(1, 1, 1)
        end,

        hit_fn = function(px, cy_start, pw, h, mx, my)
            -- 1. Tag filter pills (checked first)
            for _, r in ipairs(state.palette_filter_rects or {}) do
                if mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h then
                    if r.tag == "_clear" then
                        return { id = "dispatch_palette_clear_filters", data = {} }
                    end
                    return { id = "dispatch_palette_filter_tag", data = { tag = r.tag } }
                end
            end
            -- 2. Search field
            local sr = state.palette_search_rect
            if sr and mx >= sr.x and mx <= sr.x + sr.w and my >= sr.y and my <= sr.y + sr.h then
                return { id = "dispatch_palette_search_focus", data = {} }
            end
            -- 3. Prefab entries
            for pf_id, r in pairs(state.palette_prefab_rects or {}) do
                if mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h then
                    return { id = "dispatch_palette_prefab_press",
                             data = { rule_i = rule_i, prefab_id = pf_id } }
                end
            end
            -- 4. Block pills
            for def_id, r in pairs(state.palette_rects or {}) do
                if mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h then
                    if r.valid then
                        return { id = "dispatch_palette_press",
                                 data = { rule_i = rule_i, def_id = def_id } }
                    end
                    return { id = "_noop", data = {} }
                end
            end
            return nil
        end,
    }
end

-- ── Build ─────────────────────────────────────────────────────────────────────

function DispatchTab.build(game, ui_manager)
    local comps = {}
    local rules = game.state.dispatch_rules or {}
    local pw    = ui_manager and ui_manager.panel and ui_manager.panel.w or 300
    state.rule_card_tops     = {}
    state.rule_card_bots     = {}
    state.palette_rects      = state.palette_rects or {}
    state.palette_prefab_rects = state.palette_prefab_rects or {}

    table.insert(comps, { type = "label", style = "heading", h = 26, text = "Dispatch Rules" })
    table.insert(comps, {
        type  = "button", id = "dispatch_add_rule", data = {},
        lines = {{ text = "+ New Rule", style = "body" }},
    })

    for rule_i, rule in ipairs(rules) do
        table.insert(comps, { type = "spacer", h = 6 })
        local is_open = state.palette_open and state.selected_rule == rule_i
        table.insert(comps, makeRuleCard(rule_i, rule, game, pw))
        if is_open and not state.collapsed_rules[rule.id or ""] then
            table.insert(comps, makePalette(rule_i, pw))
        end
    end

    -- ── Dropdown Overlay ─────────────────────────────────────────────────────
    if state.active_dropdown then
        table.insert(comps, {
            type = "custom",
            h = 0, -- Floating
            draw_fn = function(px, y, pw, h, game)
                -- We need to draw this in screen space, but draw_fn is translated
                -- by ComponentRenderer. We'll use love.graphics.push/pop or just
                -- inverse translate.
                love.graphics.push("all")
                love.graphics.origin() -- Draw in absolute screen space
                state.active_dropdown:update(0) -- dt is 0 for draw
                state.active_dropdown:draw()
                love.graphics.pop()
            end,
            hit_fn = function(px, cy, pw, h, mx, my)
                -- mx, my are in panel content space. Dropdown needs screen space.
                local screen_mx, screen_my = love.mouse.getPosition()
                if state.active_dropdown:mousepressed(screen_mx, screen_my, 1) then
                    state.active_dropdown = nil
                    return { id = "_noop", data = {} }
                end
                -- Close if clicked outside
                state.active_dropdown = nil
                return { id = "_noop", data = {} }
            end
        })
    end

    return comps
end

-- ── Find rule drop index ───────────────────────────────────────────────────────

function DispatchTab.getRuleDropIndex(content_y, num_rules)
    for i = 1, num_rules do
        local top = state.rule_card_tops[i]
        local bot = state.rule_card_bots[i]
        if top and bot then
            if content_y < (top + bot) / 2 then return i end
        end
    end
    return num_rules + 1
end

-- ── Update drop target during mousemove ───────────────────────────────────────

function DispatchTab.updateDropTarget(drag, game)
    if not drag or not drag.active then return end
    drag.drop_rule_i      = nil
    drag.drop_parent_path = nil
    drag.drop_slot        = nil
    drag.drop_valid       = false

    if drag.type == "rule" then return end

    local panel     = game.ui_manager.panel
    local content_y = panel:toContentY(drag.cy)
    local content_x = drag.cx
    local slot_type = drag.slot_type

    for rule_i, targets in pairs(state.drop_targets) do
        for _, t in ipairs(targets) do
            if t.accepts == slot_type then
                if content_x >= t.x and content_x <= t.x + t.w
                   and content_y >= t.y and content_y <= t.y + t.h then
                    drag.drop_rule_i      = rule_i
                    drag.drop_parent_path = t.parent_path
                    drag.drop_slot        = t.slot
                    drag.drop_valid       = true
                    return
                end
            end
        end
    end
end

-- ── Hover / tooltip update (called every frame from InputController.update) ───

function DispatchTab.updateHover(dt, mx, my, game)
    if not game or not game.ui_manager then return end
    local panel = game.ui_manager.panel
    local content_y = panel:toContentY(my)
    local content_x = mx

    local found_id   = nil
    local found_text = nil
    local found_tags = nil

    -- Check palette rects (content space)
    for def_id, r in pairs(state.palette_rects or {}) do
        if content_x >= r.x and content_x <= r.x + r.w
           and content_y >= r.y and content_y <= r.y + r.h then
            found_id   = "pal_" .. def_id
            found_text = defTooltip(r.def)
            found_tags = r.def and r.def.tags
            break
        end
    end

    -- Check node rects (content space)
    if not found_id then
        for rule_i, nrects in pairs(state.node_rects or {}) do
            for _, r in ipairs(nrects) do
                if content_x >= r.x and content_x <= r.x + r.w
                   and content_y >= r.y and content_y <= r.y + r.h then
                    local RE  = require("services.DispatchRuleEngine")
                    local def = RE.getDefById(r.node.def_id)
                    local path_str = tostring(rule_i)
                    for _, k in ipairs(r.path or {}) do path_str = path_str .. "/" .. tostring(k) end
                    found_id   = "node_" .. path_str
                    found_text = defTooltip(def)
                    found_tags = def and def.tags
                    break
                end
            end
            if found_id then break end
        end
    end

    if found_id == hover.id then
        hover.timer = hover.timer + dt
    else
        hover.id           = found_id
        hover.timer        = 0
        hover.tooltip_text = found_text
        hover.tooltip_tags = found_tags
        hover.mx           = mx
        hover.my           = my
    end
end

-- ── Draw floating drag ghost + drop indicators ────────────────────────────────

function DispatchTab.drawDragGhost(panel, game)
    local drag = state.drag
    if not drag or not drag.active then return end

    local mx, my = drag.cx, drag.cy
    local font   = game.fonts.ui_small
    local fh     = font:getHeight()
    love.graphics.setFont(font)

    if drag.type == "rule" then
        local rule  = game.state.dispatch_rules[drag.rule_i]
        if not rule then return end
        local gw = math.min(panel.w - 20, 200)
        local gh = HDR_H + RULE_PAD
        local gx = mx - gw / 2
        local gy = my - gh / 2
        love.graphics.setColor(0, 0, 0, 0.30)
        love.graphics.rectangle("fill", gx+3, gy+3, gw, gh, 5, 5)
        love.graphics.setColor(0.18, 0.28, 0.52, 0.90)
        love.graphics.rectangle("fill", gx, gy, gw, gh, 5, 5)
        love.graphics.setColor(0.4, 0.6, 1.0)
        love.graphics.rectangle("line", gx, gy, gw, gh, 5, 5)
        love.graphics.setColor(1, 1, 1, 0.9)
        local mark = rule.enabled and "● " or "○ "
        love.graphics.printf(string.format("%sRule %d", mark, drag.rule_i),
            gx + 8, gy + (gh - fh) / 2, gw - 16, "left")

    elseif drag.type == "node" or drag.type == "palette" then
        local node = drag.node
        if not node then return end
        local RE  = require("services.DispatchRuleEngine")
        local def = RE.getDefById(node.def_id)
        if not def then return end
        local gw = 160
        local gh = (node.kind == "control" or node.kind == "loop" or node.kind == "find") and (STACK_H + MIN_BODY_H + CAP_H) or
                   (node.kind == "bool")                            and BOOL_H or STACK_H
        local gx = mx - gw / 2
        local gy = my - gh / 2
        love.graphics.setColor(0, 0, 0, 0.30)
        love.graphics.rectangle("fill", gx+3, gy+3, gw, gh, 4, 4)
        local c = def.color or { 0.5, 0.5, 0.5 }
        love.graphics.setColor(c[1], c[2], c[3], 0.88)
        love.graphics.rectangle("fill", gx, gy, gw, gh, 4, 4)
        love.graphics.setColor(1, 1, 1, 0.22)
        love.graphics.rectangle("line", gx, gy, gw, gh, 4, 4)
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.printf(def.label or "", gx, gy + (gh - fh) / 2, gw, "center")

        -- Drop indicator
        if drag.drop_valid then
            local targets = state.drop_targets[drag.drop_rule_i] or {}
            local t = nil
            for _, dt in ipairs(targets) do
                if pathsEqual(dt.parent_path, drag.drop_parent_path) and dt.slot == drag.drop_slot then
                    t = dt; break
                end
            end
            if t then
                local s        = panel.scroll[panel.active_tab_id]
                local scroll_y = s and s.scroll_y or 0
                local sy       = t.y + panel.content_y - scroll_y

                if drag.slot_type == "stack" then
                    love.graphics.setColor(0.35, 0.65, 1.0, 0.95)
                    love.graphics.setLineWidth(3)
                    love.graphics.line(t.x, sy + t.h / 2, t.x + t.w, sy + t.h / 2)
                    love.graphics.setLineWidth(1)
                elseif drag.slot_type == "boolean" then
                    love.graphics.setColor(1.0, 0.85, 0.2, 0.80)
                    love.graphics.setLineWidth(2)
                    love.graphics.polygon("line", polyBool(t.x, sy, t.w, t.h))
                    love.graphics.setLineWidth(1)
                end
            end
        end
    end

    love.graphics.setColor(1, 1, 1)
end

-- ── Draw tooltip ──────────────────────────────────────────────────────────────

function DispatchTab.drawTooltip(game)
    if hover.timer < 2.0 or not hover.tooltip_text then return end

    local font   = game.fonts.ui_small
    local fh     = font:getHeight()
    local max_w  = 230
    local pad    = 9
    local text   = hover.tooltip_text
    local tags   = hover.tooltip_tags

    -- Build tag pill layout
    local PILL_H  = fh + 4
    local PILL_PX = 6
    local PILL_GAP = 4
    local tag_row_h = (tags and #tags > 0) and (PILL_H + 8) or 0  -- 8 = top separator gap

    -- Build colour lookup for tags
    local tag_color = {}
    for _, td in ipairs(TAG_DEFS) do tag_color[td.id] = td end

    -- Measure text height
    local _, lines = font:getWrap(text, max_w)
    local text_h   = #lines * (fh + 2)
    local th       = text_h + pad * 2 + tag_row_h

    local sw = love.graphics.getWidth()
    local sh = love.graphics.getHeight()
    local tx = math.min(hover.mx + 16, sw - max_w - pad * 2 - 4)
    local ty = math.max(4, math.min(hover.my - th / 2, sh - th - 4))
    local tw = max_w + pad * 2

    -- Shadow
    love.graphics.setColor(0, 0, 0, 0.40)
    love.graphics.rectangle("fill", tx + 3, ty + 3, tw, th, 5, 5)

    -- Background
    love.graphics.setColor(0.07, 0.07, 0.13, 0.97)
    love.graphics.rectangle("fill", tx, ty, tw, th, 5, 5)

    -- Border
    love.graphics.setColor(0.38, 0.38, 0.62, 1.0)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", tx, ty, tw, th, 5, 5)
    love.graphics.setLineWidth(1)

    -- Text
    love.graphics.setFont(font)
    love.graphics.setColor(0.88, 0.88, 1.0)
    love.graphics.printf(text, tx + pad, ty + pad, max_w, "left")

    -- Tag pills
    if tags and #tags > 0 then
        local pill_y = ty + pad + text_h + 6
        local pill_x = tx + pad
        for _, tag in ipairs(tags) do
            local td = tag_color[tag]
            local lbl = td and td.label or tag
            local c   = td and td.color or { 0.5, 0.5, 0.5 }
            local pw  = font:getWidth(lbl) + PILL_PX * 2
            love.graphics.setColor(c[1], c[2], c[3], 0.88)
            love.graphics.rectangle("fill", pill_x, pill_y, pw, PILL_H, 3, 3)
            love.graphics.setColor(1, 1, 1, 0.15)
            love.graphics.rectangle("line", pill_x, pill_y, pw, PILL_H, 3, 3)
            love.graphics.setColor(1, 1, 1, 0.95)
            love.graphics.printf(lbl, pill_x, pill_y + (PILL_H - fh) / 2, pw, "center")
            pill_x = pill_x + pw + PILL_GAP
        end
    end

    love.graphics.setColor(1, 1, 1)
end

-- ── Slot focus helpers (number and string slots) ──────────────────────────────

local function _isStringSlot(f)
    return f.sd and f.sd.type == "string"
end

-- Called when the user types a character (routed from InputController.textinput)
function DispatchTab.handleTextInput(char)
    if state.slot_input and state.slot_input.input.is_focused then
        return state.slot_input.input:handle_textinput(char)
    end
    return false
end

-- Called on keypressed (routed from InputController.keypressed when focused)
-- Returns true if the key was consumed.
function DispatchTab.handleKeyPressed(key)
    if state.slot_input and state.slot_input.input.is_focused then
        local consumed = state.slot_input.input:handle_keypressed(key)
        if state.slot_input.input.is_focused == false then
            state.slot_input = nil
        end
        return consumed
    end
    return false
end
-- Commit the current input value to the node slot.
function DispatchTab.commitFocus()
    if state.slot_input then
        state.slot_input.input:defocus()
        state.slot_input = nil
    end
    if state.search_input then
        state.search_input:defocus()
    end
end

-- Clear focus without committing (e.g., on drag start).
function DispatchTab.clearFocus()
    state.slot_input = nil
end

-- ── Palette filter / search exported functions ────────────────────────────────

function DispatchTab.toggleFilterTag(tag_id)
    local f = state.palette_filter
    if f.active_tags[tag_id] then
        f.active_tags[tag_id] = nil
    else
        f.active_tags[tag_id] = true
    end
end

function DispatchTab.blurPaletteSearch()
    if state.palette_filter then
        state.palette_filter.search_focused = false
    end
end

-- Returns true if the character was consumed (search field was focused).
function DispatchTab.handleSearchInput(char)
    if state.search_input and state.search_input.is_focused then
        return state.search_input:handle_textinput(char)
    end
    return false
end

-- Returns true if the key was consumed by the search field.
function DispatchTab.handleSearchKey(key)
    if state.search_input and state.search_input.is_focused then
        local consumed = state.search_input:handle_keypressed(key)
        if state.search_input.is_focused == false then
            state.palette_filter.search_focused = false
        end
        return consumed
    end
    return false
end

-- ── Cycle a slot value ────────────────────────────────────────────────────────

function DispatchTab.cycleSlot(rule_i, path, slot_key, game)
    local RTU  = require("services.RuleTreeUtils")
    local RE   = require("services.DispatchRuleEngine")
    local rule = (game.state.dispatch_rules or {})[rule_i]
    if not rule then return end
    local node = RTU.getNodeAtPath(rule.stack, path)
    if not node then return end
    local def  = RE.getDefById(node.def_id)
    if not def then return end

    local slots_to_check = {}
    for _, sd in ipairs(def.slots or {}) do slots_to_check[#slots_to_check+1] = sd end
    
    -- ── Check variadic params for block_call ───────────────────────────────
    if node.def_id == "block_call" and node.slots.action then
        local ACTIONS = require("data.dispatch_actions")
        local action_def = nil
        for _, a in ipairs(ACTIONS) do
            if a.id == node.slots.action then action_def = a; break end
        end
        if action_def and action_def.params then
            for _, psd in ipairs(action_def.params) do
                slots_to_check[#slots_to_check+1] = psd
            end
        end
    end

    for _, sd in ipairs(slots_to_check) do
        if sd.key == slot_key then
            local val = node.slots[slot_key]
            if sd.type == "enum" or sd.type == "vehicle_enum" then
                local opts = sd.options or {}

                -- ── Dynamic options for core blocks ──────────────────────────────
                if sd.options == "dynamic" then
                    if def.id == "find_match" then
                        if sd.key == "collection" then
                            local COLLECTIONS = require("data.dispatch_collections")
                            opts = {}
                            for _, c in ipairs(COLLECTIONS) do opts[#opts+1] = c.id end
                            table.sort(opts)
                        elseif sd.key == "sorter" then
                            local SORTERS = require("data.dispatch_sorters")
                            local col_id  = node.slots.collection or "vehicles"
                            opts = {}
                            for _, s in ipairs(SORTERS) do
                                if s.for_type == col_id then opts[#opts+1] = s.id end
                            end
                            table.sort(opts)
                        end
                    elseif def.id == "block_call" then
                        if sd.key == "action" then
                            local ACTIONS = require("data.dispatch_actions")
                            opts = {}
                            for _, a in ipairs(ACTIONS) do opts[#opts+1] = a.id end
                            table.sort(opts)
                        end
                    end
                elseif sd.type == "vehicle_enum" then
                    opts = {}
                    for id in pairs(game.C.VEHICLES or {}) do opts[#opts+1] = id:lower() end
                    table.sort(opts)
                end
                
                -- Calculate screen position
                local panel = game.ui_manager.panel
                local scroll_y = panel.scroll[panel.active_tab_id] and panel.scroll[panel.active_tab_id].scroll_y or 0
                -- Find the rect for this slot in state.node_rects
                local slot_rect = nil
                local nr_ref    = nil
                local nr_list   = state.node_rects[rule_i] or {}
                for _, nr in ipairs(nr_list) do
                    if pathsEqual(nr.path, path) then
                        nr_ref = nr
                        for _, sr in ipairs(nr.slot_rects or {}) do
                            if sr.key == slot_key then slot_rect = sr; break end
                        end
                        break
                    end
                end

                local drop_x = slot_rect and (panel.x + slot_rect.x) or (love.mouse.getX() - 60)
                local drop_y = (slot_rect and nr_ref) and (panel.content_y - scroll_y + nr_ref.y + 20) or love.mouse.getY()

                state.active_dropdown = Dropdown:new(opts, val, function(v)
                    local old_v = node.slots[slot_key]
                    node.slots[slot_key] = v
                    -- Cascading reset for Find block
                    if def.id == "find_match" and slot_key == "collection" and v ~= old_v then
                        node.slots.sorter = nil
                        node.slots.output_var = nil
                    end
                    state.active_dropdown = nil
                end, game)
                state.active_dropdown.x = drop_x
                state.active_dropdown.y = drop_y

            elseif sd.type == "text_var_enum" or sd.type == "string" or (sd.type == "reporter" and type(val) == "string") then
                state.slot_input = {
                    node     = node,
                    slot_key = slot_key,
                    input    = TextInput:new("", val, "text", function(v)
                        node.slots[slot_key] = v
                    end, game)
                }
                state.slot_input.input:focus()
            elseif sd.type == "number" or (sd.type == "reporter" and type(val) == "number") then
                state.slot_input = {
                    node     = node,
                    slot_key = slot_key,
                    input    = TextInput:new("", val, "number", function(v)
                        if sd.min then v = math.max(sd.min, v) end
                        node.slots[slot_key] = v
                    end, game)
                }
                state.slot_input.input:focus()
            end
            break
        end
    end
end

-- ── Cycle / edit an inner slot of an embedded reporter node ──────────────────

function DispatchTab.cycleRepInnerSlot(rep_node, rep_key, rep_sd, game)
    if not rep_node or not rep_key then return end
    local RE  = require("services.DispatchRuleEngine")
    local def = RE.getDefById(rep_node.def_id)
    if not def then return end

    -- Find the slot def (use rep_sd if provided, else look it up)
    local sd = rep_sd
    if not sd then
        for _, s in ipairs(def.slots or {}) do
            if s.key == rep_key then sd = s; break end
        end
    end
    if not sd then return end

    if sd.type == "enum" or sd.type == "vehicle_enum" then
        local opts = sd.options or {}

        -- ── Dynamic options for rep_get_property ─────────────────────────────
        if sd.options == "dynamic" and rep_node.def_id == "rep_get_property" then
            local PROPS = require("data.dispatch_properties")
            if sd.key == "source" then
                local seen = {}
                opts = {}
                for _, p in ipairs(PROPS) do
                    if not seen[p.source] then
                        opts[#opts+1] = p.source
                        seen[p.source] = true
                    end
                end
                table.sort(opts)
            elseif sd.key == "property" then
                local source = rep_node.slots.source
                opts = {}
                for _, p in ipairs(PROPS) do
                    if p.source == source then
                        opts[#opts+1] = p.key
                    end
                end
                table.sort(opts)
            end
        elseif sd.type == "vehicle_enum" then
            opts = {}
            for id in pairs(game.C.VEHICLES or {}) do opts[#opts+1] = id:lower() end
            table.sort(opts)
        end

        -- Calculate screen position
        local panel = game.ui_manager.panel
        local scroll_y = panel.scroll[panel.active_tab_id] and panel.scroll[panel.active_tab_id].scroll_y or 0
        -- We don't easily have the node's current drawn position here without searching state.node_rects
        -- but cycleRepInnerSlot is called from a hit_fn which has the info.
        -- Let's use mouse position as a fallback, but better to use hit rect if we can.
        local drop_x = love.mouse.getX() - 60
        local drop_y = love.mouse.getY()

        state.active_dropdown = Dropdown:new(opts, rep_node.slots[rep_key], function(val)
            local old_val = rep_node.slots[rep_key]
            rep_node.slots[rep_key] = val
            
            -- ── Cascading reset for rep_get_property ─────────────────────────────
            if rep_node.def_id == "rep_get_property" and sd.key == "source" and val ~= old_val then
                local PROPS = require("data.dispatch_properties")
                for _, p in ipairs(PROPS) do
                    if p.source == val then
                        rep_node.slots.property = p.key
                        break
                    end
                end
            end
            state.active_dropdown = nil
        end, game)
        state.active_dropdown.x = drop_x
        state.active_dropdown.y = drop_y

    elseif sd.type == "number" then
        state.slot_input = {
            node     = rep_node,
            slot_key = rep_key,
            input    = TextInput:new("", rep_node.slots[rep_key], "number", function(val)
                if sd.min then val = math.max(sd.min, val) end
                rep_node.slots[rep_key] = val
            end, game)
        }
        state.slot_input.input:focus()

    elseif sd.type == "string" or sd.type == "text_var_enum" then
        state.slot_input = {
            node     = rep_node,
            slot_key = rep_key,
            input    = TextInput:new("", rep_node.slots[rep_key], "text", function(val)
                rep_node.slots[rep_key] = val
            end, game)
        }
        state.slot_input.input:focus()
    end
end

return DispatchTab
