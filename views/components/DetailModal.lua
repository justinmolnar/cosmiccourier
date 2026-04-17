-- views/components/DetailModal.lua
-- Agnostic entity detail modal. Renders whatever a descriptor tells it to:
-- field rows, action buttons, sub-item lists. Knows nothing about entity
-- types — the descriptor (pure data + callbacks) drives everything.
--
-- Plugs into modal_manager via the same draw/handle_mouse_down contract
-- as the existing Modal.lua (upgrade tech-tree).

local DetailModal = {}
DetailModal.__index = DetailModal

local TITLE_H      = 36
local CLOSE_BTN_SZ = 24
local SECTION_PAD  = 10
local FIELD_ROW_H  = 22
local ACTION_BTN_H = 30
local ACTION_GAP   = 6
local LIST_ROW_H   = 20
local SECTION_HDR  = 24
local MARGIN       = 16

function DetailModal:new(descriptor, item, game, on_close)
    local inst = setmetatable({}, DetailModal)
    inst.descriptor = descriptor
    inst.item       = item
    inst.game       = game
    inst.on_close   = on_close
    inst.width      = descriptor.width or 420
    inst.scroll_y   = 0
    inst._action_rects = {}
    return inst
end

function DetailModal:update(dt, game) end

-- ─── Drawing ────────────────────────────────────────────────────────────────

function DetailModal:draw(game)
    game = game or self.game
    local g = love.graphics
    local sw, sh = g.getDimensions()
    local w = self.width
    local content_h = self:_contentHeight(game)
    local h = math.min(sh - 80, TITLE_H + content_h + MARGIN * 2)
    local x = math.floor((sw - w) / 2)
    local y = math.floor((sh - h) / 2)
    self._x, self._y, self._w, self._h = x, y, w, h

    -- Dim background
    g.setColor(0, 0, 0, 0.55)
    g.rectangle("fill", 0, 0, sw, sh)

    -- Panel
    g.setColor(0.12, 0.12, 0.16, 0.98)
    g.rectangle("fill", x, y, w, h, 6)
    g.setColor(0.35, 0.45, 0.70, 0.9)
    g.rectangle("line", x, y, w, h, 6)

    -- Title
    g.setColor(0.16, 0.18, 0.24)
    g.rectangle("fill", x, y, w, TITLE_H, 6, 6)
    g.setFont(game.fonts.ui)
    g.setColor(1, 1, 1)
    local title = self.descriptor.title_fn
                  and self.descriptor.title_fn(self.item, game)
                  or "Details"
    g.printf(title, x + MARGIN, y + (TITLE_H - game.fonts.ui:getHeight()) * 0.5,
             w - MARGIN * 2 - CLOSE_BTN_SZ, "left")

    -- Close button
    local cbx = x + w - CLOSE_BTN_SZ - 6
    local cby = y + 6
    self._close_rect = { x = cbx, y = cby, w = CLOSE_BTN_SZ, h = CLOSE_BTN_SZ }
    g.setColor(0.6, 0.25, 0.25)
    g.rectangle("fill", cbx, cby, CLOSE_BTN_SZ, CLOSE_BTN_SZ, 3)
    g.setColor(1, 1, 1)
    g.printf("×", cbx, cby + 2, CLOSE_BTN_SZ, "center")

    -- Content (scissored + scrollable)
    local cx = x + MARGIN
    local cy_start = y + TITLE_H + MARGIN
    local cw = w - MARGIN * 2
    local ch = h - TITLE_H - MARGIN * 2
    g.setScissor(cx - 2, cy_start, cw + 4, ch)

    local cursor_y = cy_start - self.scroll_y
    self._action_rects = {}
    for _, section in ipairs(self.descriptor.sections or {}) do
        cursor_y = self:_drawSection(section, cx, cursor_y, cw, game)
        cursor_y = cursor_y + SECTION_PAD
    end

    g.setScissor()
    g.setColor(1, 1, 1)
end

function DetailModal:_contentHeight(game)
    local h = 0
    for _, section in ipairs(self.descriptor.sections or {}) do
        h = h + self:_sectionHeight(section, game) + SECTION_PAD
    end
    return h
end

function DetailModal:_sectionHeight(section, game)
    local h = SECTION_HDR
    if section.type == "fields" then
        h = h + #(section.rows or {}) * FIELD_ROW_H
    elseif section.type == "actions" then
        h = h + #(section.items or {}) * (ACTION_BTN_H + ACTION_GAP)
    elseif section.type == "list" then
        local items = section.items_fn and section.items_fn(self.item, game) or {}
        h = h + math.max(1, #items) * LIST_ROW_H
    end
    return h
end

function DetailModal:_drawSection(section, x, y, w, game)
    local g = love.graphics

    -- Section header
    g.setFont(game.fonts.ui)
    g.setColor(0.70, 0.72, 0.85)
    g.print(section.label or "", x, y + 2)
    g.setColor(0.30, 0.30, 0.40)
    g.rectangle("fill", x, y + SECTION_HDR - 2, w, 1)
    y = y + SECTION_HDR

    g.setFont(game.fonts.ui_small)

    if section.type == "fields" then
        for _, row in ipairs(section.rows or {}) do
            g.setColor(0.65, 0.65, 0.75)
            g.print(row.label or "", x, y + 3)
            local val = row.value_fn and row.value_fn(self.item, game) or "—"
            g.setColor(1, 1, 1)
            g.printf(tostring(val), x, y + 3, w, "right")
            y = y + FIELD_ROW_H
        end

    elseif section.type == "actions" then
        for _, act in ipairs(section.items or {}) do
            local enabled = not act.enabled_fn or act.enabled_fn(self.item, game)
            if enabled then
                g.setColor(0.20, 0.35, 0.55)
            else
                g.setColor(0.15, 0.15, 0.20)
            end
            g.rectangle("fill", x, y, w, ACTION_BTN_H, 4)
            if enabled then
                g.setColor(0.40, 0.60, 0.90)
            else
                g.setColor(0.25, 0.25, 0.30)
            end
            g.rectangle("line", x, y, w, ACTION_BTN_H, 4)
            g.setColor(enabled and {1, 1, 1} or {0.45, 0.45, 0.50})
            g.printf(act.label or "Action", x, y + (ACTION_BTN_H - game.fonts.ui_small:getHeight()) * 0.5,
                     w, "center")
            self._action_rects[#self._action_rects + 1] = {
                x = x, y = y, w = w, h = ACTION_BTN_H,
                action_fn = act.action_fn, enabled = enabled,
                closes = act.closes,
            }
            y = y + ACTION_BTN_H + ACTION_GAP
        end

    elseif section.type == "list" then
        local items = section.items_fn and section.items_fn(self.item, game) or {}
        if #items == 0 then
            g.setColor(0.50, 0.50, 0.55)
            g.print(section.empty or "None", x, y + 2)
            y = y + LIST_ROW_H
        else
            for _, sub in ipairs(items) do
                local text = section.format_fn and section.format_fn(sub, game) or tostring(sub)
                g.setColor(0.90, 0.90, 0.95)
                g.print(text, x + 4, y + 2)
                y = y + LIST_ROW_H
            end
        end
    end

    return y
end

-- ─── Input ──────────────────────────────────────────────────────────────────

function DetailModal:handle_mouse_down(mx, my, game)
    game = game or self.game
    -- Close button
    local cb = self._close_rect
    if cb and mx >= cb.x and mx < cb.x + cb.w and my >= cb.y and my < cb.y + cb.h then
        if self.on_close then self.on_close() end
        return true
    end
    -- Outside modal
    if not self._x or mx < self._x or mx >= self._x + self._w
                    or my < self._y or my >= self._y + self._h then
        if self.on_close then self.on_close() end
        return true
    end
    -- Action buttons
    for _, r in ipairs(self._action_rects or {}) do
        if r.enabled and mx >= r.x and mx < r.x + r.w
                      and my >= r.y and my < r.y + r.h then
            if r.action_fn then r.action_fn(self.item, game) end
            if r.closes and self.on_close then self.on_close() end
            return true
        end
    end
    return true
end

function DetailModal:handle_mouse_up(mx, my) return true end

function DetailModal:wheelmoved(x, y)
    local content_h = self:_contentHeight(self.game)
    local view_h    = (self._h or 400) - TITLE_H - MARGIN * 2
    local max_scroll = math.max(0, content_h - view_h)
    self.scroll_y = math.max(0, math.min(max_scroll, self.scroll_y - y * 20))
    return true
end

return DetailModal
