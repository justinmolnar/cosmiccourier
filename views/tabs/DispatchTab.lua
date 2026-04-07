-- views/tabs/DispatchTab.lua
-- Scratch-style visual dispatch rule editor.
-- Vertical puzzle-piece block layout with C-shaped control blocks,
-- inline bool reporters, and full drag-and-drop from palette to tree position.

local DispatchTab = {}

local Validator = require("services.DispatchValidator")

-- ── Visual constants ──────────────────────────────────────────────────────────

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
    -- populated each draw frame:
    node_rects      = {},
    drop_targets    = {},
    palette_rects   = {},
    rule_card_tops  = {},
    rule_card_bots  = {},
}

-- ── Hover / tooltip state ─────────────────────────────────────────────────────

local hover = {
    id           = nil,    -- unique string identifying hovered element
    timer        = 0,
    tooltip_text = nil,
    mx           = 0,
    my           = 0,
}

function DispatchTab.getState() return state end

-- ── Polygon helpers ───────────────────────────────────────────────────────────

local function polyHat(x, y, w, h)
    local nx, nxr = x + NOTCH_X, x + NOTCH_X + NOTCH_W
    return { x, y,  x+w, y,  x+w, y+h,  nxr, y+h,  nxr, y+h+NOTCH_H,  nx, y+h+NOTCH_H,  nx, y+h,  x, y+h }
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

local function polyCBlock(x, y, w, body_h)
    local SH, CH, NH, CI = STACK_H, CAP_H, NOTCH_H, C_INDENT
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

local function polyCElseBlock(x, y, w, body_h, else_h)
    local SH, CH, NH, CI = STACK_H, CAP_H, NOTCH_H, C_INDENT
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
local function measureNode(node)
    if node.kind == "hat" or node.kind == "stack" then
        return STACK_H
    elseif node.kind == "control" then
        local bh = math.max(MIN_BODY_H, measureStack(node.body or {}))
        local h  = STACK_H + bh + CAP_H
        if node.else_body then
            local eh = math.max(MIN_BODY_H, measureStack(node.else_body or {}))
            h = h + eh + CAP_H
        end
        return h
    end
    return STACK_H
end

measureStack = function(stack)
    local h = 0
    for _, n in ipairs(stack or {}) do h = h + measureNode(n) end
    return h
end

-- ── Bool node width ───────────────────────────────────────────────────────────

local function boolNodeW(node, font)
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
            local val = tostring(node.slots and node.slots[sd.key] or sd.default or "")
            w = w + font:getWidth(val) + 18
        end
        return math.max(60, w)
    end
end

local function stackNaturalW(node, font)
    local RE  = require("services.DispatchRuleEngine")
    local def = RE.getDefById(node.def_id)
    local w   = font:getWidth((def and def.label) or "") + 24
    for _, sd in ipairs((def and def.slots) or {}) do
        local val = tostring((node.slots and node.slots[sd.key]) or sd.default or "")
        w = w + font:getWidth(val) + 22
    end
    return math.max(160, math.min(STACK_W_MAX, w))
end

local function controlNaturalW(node, font)
    local cond_w = node.condition and boolNodeW(node.condition, font) or 80
    return math.max(220, C_INDENT + 16 + cond_w + 16)
end

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

-- ── Slot pill helper ──────────────────────────────────────────────────────────

-- Returns the display string and pixel width for a slot pill.
local function pillDisplay(val, focused)
    local s = focused and (state.input_focus and state.input_focus.text or tostring(val)) or tostring(val)
    return s
end

local function drawSlotPill(val, x, y, block_h, font, alpha, focused)
    local s   = pillDisplay(val, focused)
    local fw  = font:getWidth(s)
    local pw  = math.max(fw + 14, focused and 36 or (fw + 14))
    local fh  = font:getHeight()
    local py  = y + (block_h - 16) / 2

    if focused then
        love.graphics.setColor(0.05, 0.06, 0.15, 0.95 * alpha)
        love.graphics.rectangle("fill", x, py, pw, 16, 3, 3)
        love.graphics.setColor(0.45, 0.65, 1.0, alpha)
        love.graphics.setLineWidth(1.5)
        love.graphics.rectangle("line", x, py, pw, 16, 3, 3)
        love.graphics.setLineWidth(1)
    else
        love.graphics.setColor(0, 0, 0, 0.35 * alpha)
        love.graphics.rectangle("fill", x, py, pw, 16, 3, 3)
        love.graphics.setColor(1, 1, 1, 0.18 * alpha)
        love.graphics.rectangle("line", x, py, pw, 16, 3, 3)
    end

    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.print(s, x + 7, py + (16 - fh) / 2)

    -- Blinking cursor
    if focused then
        local cux = x + 7 + font:getWidth(s)
        if math.floor(love.timer.getTime() * 2) % 2 == 0 then
            love.graphics.setColor(1, 1, 1, alpha)
            love.graphics.setLineWidth(1)
            love.graphics.line(cux, py + 2, cux, py + 13)
            love.graphics.setLineWidth(1)
        end
    end

    return pw
end

-- Compute pill width without drawing (for layout of right-aligned slots).
local function pillWidth(val, font, focused)
    local s = pillDisplay(val, focused)
    return math.max(font:getWidth(s) + 14, focused and 36 or 0)
end

-- ── Forward declarations ──────────────────────────────────────────────────────

local drawBoolNode
local drawNodeList
local drawControlNode

-- ── drawBoolNode ──────────────────────────────────────────────────────────────

drawBoolNode = function(node, x, y, game, nrects, dtargets, path, warn_map, alpha)
    local font = game.fonts.ui_small
    local fh   = font:getHeight()
    alpha = alpha or 1.0

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
    local w   = boolNodeW(node, font)

    if id == "bool_and" or id == "bool_or" then
        local lbl      = def and def.label or id
        local lbl_w    = font:getWidth(lbl) + 16
        local left_w   = boolNodeW(node.left, font)
        local c        = def and def.color or { 0.82, 0.78, 0.15 }

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

        local lx = x + BOOL_ANGLE
        drawBoolNode(node.left,  lx, y, game, nrects, dtargets, appendPath(path, "left"),  warn_map, alpha)
        local op_x = lx + left_w
        love.graphics.setFont(font)
        love.graphics.setColor(1, 1, 1, alpha)
        love.graphics.printf(lbl, op_x, y + (BOOL_H - fh) / 2, lbl_w, "center")
        drawBoolNode(node.right, op_x + lbl_w, y, game, nrects, dtargets, appendPath(path, "right"), warn_map, alpha)

        if nrects and path then
            nrects[#nrects+1] = { node=node, path=path, x=x, y=y, w=w, h=BOOL_H, slot_rects={} }
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
        drawBoolNode(node.operand, lbl_x + lbl_w, y, game, nrects, dtargets, appendPath(path, "operand"), warn_map, alpha)

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
            local val    = node.slots and node.slots[sd.key] or sd.default or ""
            local is_foc = sd.type == "number"
                           and state.input_focus
                           and state.input_focus.node_ref == node
                           and state.input_focus.slot_key == sd.key
            local pill_x = px
            local pw     = drawSlotPill(val, px, y, BOOL_H, font, alpha, is_foc)
            slot_rects[#slot_rects+1] = { key = sd.key, x = pill_x, w = pw, sd_type = sd.type }
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
    love.graphics.polygon("fill", polyHat(x + 2, y + 2, w, STACK_H))

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
            local is_foc  = sd.type == "number"
                            and state.input_focus
                            and state.input_focus.node_ref == node
                            and state.input_focus.slot_key == sd.key
            local pw = pillWidth(val, font, is_foc)
            px = px - pw
            drawSlotPill(val, px, y, STACK_H, font, alpha, is_foc)
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
    love.graphics.polygon("fill", polyStack(x + 2, y + 2, w, STACK_H))

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
        for i = #(def.slots or {}), 1, -1 do
            local sd     = def.slots[i]
            local val    = node.slots and node.slots[sd.key] or sd.default or ""
            local is_foc = sd.type == "number"
                           and state.input_focus
                           and state.input_focus.node_ref == node
                           and state.input_focus.slot_key == sd.key
            local pw = pillWidth(val, font, is_foc)
            px = px - pw
            drawSlotPill(val, px, y, STACK_H, font, alpha, is_foc)
            slot_rects[#slot_rects+1] = { key = sd.key, x = px, w = pw, sd_type = sd.type }
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

    local body_h = math.max(MIN_BODY_H, measureStack(node.body or {}))
    local else_h = nil
    if node.def_id == "ctrl_if_else" and node.else_body then
        else_h = math.max(MIN_BODY_H, measureStack(node.else_body or {}))
    end

    local ctrl_c = { 0.75, 0.55, 0.08 }

    -- Shadow
    love.graphics.setColor(0, 0, 0, 0.20 * alpha)
    if else_h then
        love.graphics.polygon("fill", polyCElseBlock(x+2, y+2, w, body_h, else_h))
    else
        love.graphics.polygon("fill", polyCBlock(x+2, y+2, w, body_h))
    end

    love.graphics.setColor(ctrl_c[1], ctrl_c[2], ctrl_c[3], alpha)
    if else_h then
        love.graphics.polygon("fill", polyCElseBlock(x, y, w, body_h, else_h))
    else
        love.graphics.polygon("fill", polyCBlock(x, y, w, body_h))
    end

    if warn_map and warn_map[node] then
        love.graphics.setColor(0.95, 0.62, 0.12, alpha)
        love.graphics.setLineWidth(2)
    else
        love.graphics.setColor(1, 1, 1, 0.15 * alpha)
        love.graphics.setLineWidth(1)
    end
    if else_h then
        love.graphics.polygon("line", polyCElseBlock(x, y, w, body_h, else_h))
    else
        love.graphics.polygon("line", polyCBlock(x, y, w, body_h))
    end
    love.graphics.setLineWidth(1)

    -- Inner body background
    love.graphics.setColor(0, 0, 0, 0.20 * alpha)
    love.graphics.rectangle("fill", x + C_INDENT, y + STACK_H, w - C_INDENT, body_h)
    if else_h then
        local else_start = y + STACK_H + body_h + CAP_H
        love.graphics.rectangle("fill", x + C_INDENT, else_start, w - C_INDENT, else_h)
    end

    love.graphics.setFont(font)
    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.print("if", x + 8, y + (STACK_H - fh) / 2)

    -- Condition slot
    local cond_x  = x + C_INDENT + 8
    local cond_y  = y + (STACK_H - BOOL_H) / 2
    local cond_path = appendPath(path, "condition")

    if node.condition then
        drawBoolNode(node.condition, cond_x, cond_y, game, nrects, dtargets, cond_path, warn_map, alpha)
        if dtargets and path then
            local cw = boolNodeW(node.condition, font)
            dtargets[#dtargets+1] = {
                parent_path = path, slot = "condition", accepts = "boolean",
                x = cond_x, y = cond_y, w = cw, h = BOOL_H
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
    local body_y   = y + STACK_H
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
        local else_start = y + STACK_H + body_h + CAP_H
        love.graphics.setFont(font)
        love.graphics.setColor(1, 1, 1, alpha * 0.80)
        love.graphics.print("else", x + 8, y + STACK_H + body_h + (CAP_H - fh) / 2)

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
        nrects[#nrects+1] = { node=node, path=path, x=x, y=y, w=w, h=measureNode(node), slot_rects={} }
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

    for i, node in ipairs(stack or {}) do
        local node_path = appendPath(path_prefix, i)
        local nh   = measureNode(node)
        local font = game.fonts.ui_small
        local nw
        if node.kind == "hat" or node.kind == "stack" then
            nw = math.min(w, stackNaturalW(node, font))
        elseif node.kind == "control" then
            nw = math.min(w, controlNaturalW(node, font))
        else
            nw = math.min(w, 200)
        end

        if node.kind == "hat" then
            drawHatNode(node, x, cy, nw, game, nrects, node_path, alpha)
        elseif node.kind == "stack" then
            drawStackNode(node, x, cy, nw, game, nrects, node_path, warn_map, alpha)
        elseif node.kind == "control" then
            drawControlNode(node, x, cy, nw, game, nrects, dtargets, node_path, warn_map, alpha)
        end

        cy = cy + nh

        if dtargets and path_prefix then
            dtargets[#dtargets+1] = {
                parent_path = path_prefix, slot = i + 1, accepts = "stack",
                x = x, y = cy - 10, w = w, h = 20
            }
        end
    end

    return cy - y
end

-- ── Rule card component ───────────────────────────────────────────────────────

local function makeRuleCard(rule_i, rule, panel_w)
    local pad      = RULE_PAD
    local stack    = rule.stack or {}
    local stack_h  = measureStack(stack)
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
                        if mx >= sp.x and mx <= sp.x + sp.w then
                            if sp.sd_type == "number" then
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

-- ── Palette component ─────────────────────────────────────────────────────────

local function makePalette(rule_i, panel_w)
    local RE  = require("services.DispatchRuleEngine")
    local all = RE.getAllDefs()
    local pad = PAL_PAD

    -- Height per row accounts for stack shape protrusion
    local function rowH(cat)
        return (cat == "stack") and (PAL_BLOCK_H + NOTCH_H) or PAL_BLOCK_H
    end

    local function calcPaletteH(pw)
        local cx, cy  = pad, pad + CAT_HDR_H
        local last_cat = nil
        for _, def in ipairs(all) do
            if def.category ~= last_cat then
                if last_cat then cy = cy + rowH(last_cat) + PAL_GAP + 6 + CAT_HDR_H end
                cx = pad
                last_cat = def.category
            end
            local font = love.graphics.getFont()
            local bw = math.max(70, font:getWidth(def.label or "") + 24)
            if cx + bw > pw - pad and cx > pad then cx = pad; cy = cy + rowH(def.category) + PAL_GAP end
            cx = cx + bw + PAL_GAP
        end
        return cy + (last_cat and rowH(last_cat) or PAL_BLOCK_H) + pad + 8
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

            local font     = game.fonts.ui_small
            local fh       = font:getHeight()
            local rule     = (game.state.dispatch_rules or {})[rule_i]
            local validity = Validator.getPaletteValidity({ rule = rule, dropping_into = state.drag and state.drag.slot_type }, game)

            local cx, cy   = px + pad, y + pad
            local last_cat = nil
            local prects   = {}

            for _, def in ipairs(all) do
                if def.category ~= last_cat then
                    if last_cat then
                        cy = cy + rowH(last_cat) + PAL_GAP + 6
                    end
                    cx = px + pad
                    last_cat = def.category
                    love.graphics.setFont(font)
                    love.graphics.setColor(0.50, 0.50, 0.68)
                    love.graphics.print(def.category:upper(), cx, cy)
                    cy = cy + CAT_HDR_H
                end

                love.graphics.setFont(font)
                local bw = math.max(70, font:getWidth(def.label or "") + 24)
                if cx + bw > px + pw - pad and cx > px + pad then
                    cx = px + pad
                    cy = cy + rowH(def.category) + PAL_GAP
                end

                local v  = validity[def.id]
                local ok = not v or v.valid
                local a  = ok and 1.0 or 0.18
                local c  = def.color or { 0.5, 0.5, 0.5 }

                -- Drop shadow
                if ok then
                    love.graphics.setColor(0, 0, 0, 0.25)
                    if def.category == "hat" then
                        love.graphics.polygon("fill", polyHat(cx+1, cy+2, bw, PAL_BLOCK_H - NOTCH_H))
                    elseif def.category == "boolean" then
                        love.graphics.polygon("fill", polyBool(cx+1, cy+2, bw, PAL_BLOCK_H))
                    elseif def.category == "stack" then
                        love.graphics.polygon("fill", polyStack(cx+1, cy+2, bw, PAL_BLOCK_H - NOTCH_H))
                    end
                end

                -- Shape fill
                love.graphics.setColor(c[1], c[2], c[3], a)
                if def.category == "hat" then
                    love.graphics.polygon("fill", polyHat(cx, cy, bw, PAL_BLOCK_H - NOTCH_H))
                elseif def.category == "boolean" then
                    love.graphics.polygon("fill", polyBool(cx, cy, bw, PAL_BLOCK_H))
                elseif def.category == "stack" then
                    love.graphics.polygon("fill", polyStack(cx, cy, bw, PAL_BLOCK_H - NOTCH_H))
                else
                    -- control: use hat shape as compact stand-in
                    love.graphics.polygon("fill", polyHat(cx, cy, bw, PAL_BLOCK_H - NOTCH_H))
                end

                -- Border
                love.graphics.setColor(1, 1, 1, 0.18 * a)
                love.graphics.setLineWidth(1)
                if def.category == "hat" then
                    love.graphics.polygon("line", polyHat(cx, cy, bw, PAL_BLOCK_H - NOTCH_H))
                elseif def.category == "boolean" then
                    love.graphics.polygon("line", polyBool(cx, cy, bw, PAL_BLOCK_H))
                elseif def.category == "stack" then
                    love.graphics.polygon("line", polyStack(cx, cy, bw, PAL_BLOCK_H - NOTCH_H))
                else
                    love.graphics.polygon("line", polyHat(cx, cy, bw, PAL_BLOCK_H - NOTCH_H))
                end
                love.graphics.setLineWidth(1)

                -- Label
                love.graphics.setColor(1, 1, 1, a)
                local lbl_h = (def.category == "boolean") and PAL_BLOCK_H or (PAL_BLOCK_H - NOTCH_H)
                love.graphics.printf(def.label or def.id, cx, cy + (lbl_h - fh) / 2, bw, "center")

                -- Tooltip hint dot if has tooltip
                if ok and def.tooltip then
                    love.graphics.setColor(0.55, 0.55, 0.75, 0.6)
                    love.graphics.circle("fill", cx + bw - 5, cy + 5, 2)
                end

                prects[def.id] = { x = cx, y = cy, w = bw, h = lbl_h, def = def, valid = ok }

                cx = cx + bw + PAL_GAP
            end

            state.palette_rects = prects
            love.graphics.setColor(1, 1, 1)
        end,

        hit_fn = function(px, cy_start, pw, h, mx, my)
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
    state.rule_card_tops = {}
    state.rule_card_bots = {}
    state.palette_rects  = state.palette_rects or {}

    table.insert(comps, { type = "label", style = "heading", h = 26, text = "Dispatch Rules" })
    table.insert(comps, {
        type  = "button", id = "dispatch_add_rule", data = {},
        lines = {{ text = "+ New Rule", style = "body" }},
    })

    for rule_i, rule in ipairs(rules) do
        table.insert(comps, { type = "spacer", h = 6 })
        local is_open = state.palette_open and state.selected_rule == rule_i
        table.insert(comps, makeRuleCard(rule_i, rule, pw))
        if is_open and not state.collapsed_rules[rule.id or ""] then
            table.insert(comps, makePalette(rule_i, pw))
        end
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

    -- Check palette rects (content space)
    for def_id, r in pairs(state.palette_rects or {}) do
        if content_x >= r.x and content_x <= r.x + r.w
           and content_y >= r.y and content_y <= r.y + r.h then
            found_id   = "pal_" .. def_id
            found_text = r.def and r.def.tooltip
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
                    -- Stable ID: rule + path
                    local path_str = tostring(rule_i)
                    for _, k in ipairs(r.path or {}) do path_str = path_str .. "/" .. tostring(k) end
                    found_id   = "node_" .. path_str
                    found_text = def and def.tooltip
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
        local gh = (node.kind == "control") and (STACK_H + MIN_BODY_H + CAP_H) or
                   (node.kind == "bool")    and BOOL_H or STACK_H
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

    local font    = game.fonts.ui_small
    local fh      = font:getHeight()
    local max_w   = 230
    local pad     = 9
    local text    = hover.tooltip_text

    -- Measure wrapped height
    local _, lines = font:getWrap(text, max_w)
    local th = #lines * (fh + 2) + pad * 2

    local sw = love.graphics.getWidth()
    local sh = love.graphics.getHeight()
    local tx = math.min(hover.mx + 16, sw - max_w - pad * 2 - 4)
    local ty = math.max(4, math.min(hover.my - th / 2, sh - th - 4))

    -- Shadow
    love.graphics.setColor(0, 0, 0, 0.40)
    love.graphics.rectangle("fill", tx + 3, ty + 3, max_w + pad * 2, th, 5, 5)

    -- Background
    love.graphics.setColor(0.07, 0.07, 0.13, 0.97)
    love.graphics.rectangle("fill", tx, ty, max_w + pad * 2, th, 5, 5)

    -- Border
    love.graphics.setColor(0.38, 0.38, 0.62, 1.0)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", tx, ty, max_w + pad * 2, th, 5, 5)
    love.graphics.setLineWidth(1)

    -- Text
    love.graphics.setFont(font)
    love.graphics.setColor(0.88, 0.88, 1.0)
    love.graphics.printf(text, tx + pad, ty + pad, max_w, "left")

    love.graphics.setColor(1, 1, 1)
end

-- ── Number slot focus helpers ─────────────────────────────────────────────────

-- Called when the user types a character (routed from InputController.textinput)
function DispatchTab.handleTextInput(char)
    local f = state.input_focus
    if not f then return end
    -- Accept digits, minus (only at start), decimal not needed (int slots)
    if char:match("^%d$") then
        if f.text == "0" or f.text == "-0" then
            f.text = (f.text == "-0") and "-" .. char or char
        else
            f.text = f.text .. char
        end
    elseif char == "-" and f.text == "" then
        f.text = "-"
    end
end

-- Called on keypressed (routed from InputController.keypressed when focused)
-- Returns true if the key was consumed.
function DispatchTab.handleKeyPressed(key)
    local f = state.input_focus
    if not f then return false end

    if key == "backspace" then
        if #f.text > 0 then
            f.text = f.text:sub(1, -2)
            if f.text == "" or f.text == "-" then f.text = "0" end
        end
        return true
    elseif key == "return" or key == "kpenter" then
        DispatchTab.commitFocus()
        return true
    elseif key == "escape" then
        state.input_focus = nil
        return true
    elseif key == "up" then
        local val  = tonumber(f.text) or 0
        local step = f.sd and f.sd.step or 1
        f.text = tostring(val + step)
        return true
    elseif key == "down" then
        local val  = tonumber(f.text) or 0
        local step = f.sd and f.sd.step or 1
        local mn   = f.sd and f.sd.min
        val = val - step
        if mn then val = math.max(mn, val) end
        f.text = tostring(val)
        return true
    end
    return false
end

-- Commit the current text input value to the node slot.
function DispatchTab.commitFocus()
    local f = state.input_focus
    if not f then return end
    local val = tonumber(f.text)
    if val and f.node_ref then
        if f.sd and f.sd.min then val = math.max(f.sd.min, val) end
        f.node_ref.slots[f.slot_key] = val
    end
    state.input_focus = nil
end

-- Clear focus without committing (e.g., on drag start).
function DispatchTab.clearFocus()
    state.input_focus = nil
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

    for _, sd in ipairs(def.slots or {}) do
        if sd.key == slot_key then
            if sd.type == "enum" then
                local opts = sd.options or {}
                local idx  = 1
                for i, v in ipairs(opts) do if v == node.slots[slot_key] then idx = i; break end end
                node.slots[slot_key] = opts[(idx % #opts) + 1]
            elseif sd.type == "vehicle_enum" then
                local types = {}
                for id in pairs(game.C.VEHICLES or {}) do types[#types+1] = id:lower() end
                table.sort(types)
                local idx = 1
                for i, v in ipairs(types) do if v == node.slots[slot_key] then idx = i; break end end
                node.slots[slot_key] = types[(idx % #types) + 1]
            elseif sd.type == "number" then
                local step   = sd.step or 100
                local mn     = sd.min  or 0
                local next_v = (node.slots[slot_key] or sd.default or 0) + step
                node.slots[slot_key] = next_v > 9999 and mn or next_v
            end
            break
        end
    end
end

return DispatchTab
