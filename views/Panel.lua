-- views/Panel.lua
-- Tab-routed panel container. Knows nothing about game content.
-- Each tab provides a draw(game) function. Panel handles tab bar,
-- per-tab scroll, scrollbar rendering and input.

local Panel = {}
Panel.__index = Panel

Panel.TAB_BAR_H    = 32
Panel.SCROLLBAR_W  = 6
Panel.SCROLLBAR_MX = 8   -- margin from right edge of panel

function Panel:new(x, y, w, h)
    -- h = available height from y downward (typically screen_h - y)
    local instance = setmetatable({}, Panel)
    instance.x = x
    instance.y = y
    instance.w = w
    instance.h = h
    instance.content_y = y + Panel.TAB_BAR_H
    instance.content_h = h - Panel.TAB_BAR_H

    instance.tabs      = {}   -- id → def
    instance.tab_order = {}   -- sorted list of defs

    instance.active_tab_id = nil

    -- Per-tab scroll state
    instance.scroll = {}   -- id → { scroll_y, total_h, is_dragging, drag_start_y, scroll_at_drag }

    return instance
end

function Panel:registerTab(def)
    -- def: { id, label, icon, priority, draw }
    self.tabs[def.id] = def
    table.insert(self.tab_order, def)
    table.sort(self.tab_order, function(a, b)
        return (a.priority or 0) < (b.priority or 0)
    end)
    if not self.active_tab_id then
        self.active_tab_id = def.id
    end
    self.scroll[def.id] = {
        scroll_y      = 0,
        total_h       = 0,
        is_dragging   = false,
        drag_start_y  = 0,
        scroll_at_drag = 0,
    }
end

function Panel:setActiveTab(id)
    if self.tabs[id] then
        self.active_tab_id = id
    end
end

function Panel:getActiveTab()
    return self.tabs[self.active_tab_id]
end

function Panel:updateScrollTotalH(tab_id, total_h)
    local s = self.scroll[tab_id]
    if not s then return end
    s.total_h = total_h
    local max_scroll = math.max(0, total_h - self.content_h)
    if s.scroll_y > max_scroll then s.scroll_y = max_scroll end
    if s.scroll_y < 0 then s.scroll_y = 0 end
end

function Panel:handleScroll(dy)
    local s = self.scroll[self.active_tab_id]
    if not s then return end
    s.scroll_y = s.scroll_y - (dy * 20)
    local max_scroll = math.max(0, s.total_h - self.content_h)
    s.scroll_y = math.max(0, math.min(s.scroll_y, max_scroll))
end

function Panel:handleMouseDown(x, y, button)
    -- Tab bar click
    if y >= self.y and y < self.y + Panel.TAB_BAR_H then
        local n = #self.tab_order
        if n == 0 then return false end
        local tab_w = self.w / n
        for i, tab in ipairs(self.tab_order) do
            local tx = self.x + (i - 1) * tab_w
            if x >= tx and x < tx + tab_w then
                local prev = self.active_tab_id
                self:setActiveTab(tab.id)
                -- Reset scroll only when switching tabs
                if tab.id ~= prev then
                    local s = self.scroll[tab.id]
                    if s then s.scroll_y = 0 end
                end
                return true
            end
        end
    end

    -- Scrollbar interaction
    if self:isInContentArea(x, y) then
        local s = self.scroll[self.active_tab_id]
        if s and s.total_h > self.content_h then
            local hx, hy, hw, hh = self:_getScrollbarHandleBounds(s)
            if hx and x >= hx and x < hx + hw and y >= hy and y < hy + hh then
                s.is_dragging    = true
                s.drag_start_y   = y
                s.scroll_at_drag = s.scroll_y
                return true
            end
            -- Track click (page scroll)
            local track_x = self.x + self.w - Panel.SCROLLBAR_MX
            if x >= track_x and x < track_x + Panel.SCROLLBAR_W then
                if hy then
                    s.scroll_y = (y < hy)
                        and (s.scroll_y - self.content_h)
                        or  (s.scroll_y + self.content_h)
                end
                local max_scroll = math.max(0, s.total_h - self.content_h)
                s.scroll_y = math.max(0, math.min(s.scroll_y, max_scroll))
                return true
            end
        end
    end

    return false
end

function Panel:handleMouseUp()
    for _, s in pairs(self.scroll) do
        s.is_dragging = false
    end
end

-- Called from UIManager:update with current mouse y
function Panel:update(my)
    local s = self.scroll[self.active_tab_id]
    if not s or not s.is_dragging then return end

    local _, _, _, hh = self:_getScrollbarHandleBounds(s)
    local track_h     = self.content_h - (hh or 0)
    local content_range = s.total_h - self.content_h

    if track_h > 0 and content_range > 0 then
        local scroll_per_px = content_range / track_h
        s.scroll_y = s.scroll_at_drag + (my - s.drag_start_y) * scroll_per_px
    end

    local max_scroll = math.max(0, s.total_h - self.content_h)
    s.scroll_y = math.max(0, math.min(s.scroll_y, max_scroll))
end

-- Convert screen-space y to content-space y for the active tab
function Panel:toContentY(screen_y)
    local s = self.scroll[self.active_tab_id]
    return screen_y - self.content_y + (s and s.scroll_y or 0)
end

function Panel:isInContentArea(screen_x, screen_y)
    return screen_x >= self.x and screen_x < self.x + self.w
       and screen_y >= self.content_y and screen_y < self.content_y + self.content_h
end

function Panel:_getScrollbarHandleBounds(s)
    if not s or s.total_h <= self.content_h then return nil end
    local handle_h    = math.max(15, self.content_h * (self.content_h / s.total_h))
    local scroll_range = s.total_h - self.content_h
    local pct          = (scroll_range > 0) and (s.scroll_y / scroll_range) or 0
    local track_h      = self.content_h - handle_h
    local hx = self.x + self.w - Panel.SCROLLBAR_MX
    local hy = self.content_y + track_h * pct
    return hx, hy, Panel.SCROLLBAR_W, handle_h
end

function Panel:draw(game)
    -- Tab bar
    local n     = #self.tab_order
    local tab_w = n > 0 and (self.w / n) or self.w

    love.graphics.setFont(game.fonts.ui)
    love.graphics.setScissor(self.x, self.y, self.w, Panel.TAB_BAR_H)
    for i, tab in ipairs(self.tab_order) do
        local tx = self.x + (i - 1) * tab_w
        if tab.id == self.active_tab_id then
            love.graphics.setColor(0.28, 0.28, 0.38)
        else
            love.graphics.setColor(0.12, 0.12, 0.18)
        end
        love.graphics.rectangle("fill", tx, self.y, tab_w, Panel.TAB_BAR_H)
        love.graphics.setColor(0.4, 0.4, 0.55)
        love.graphics.rectangle("line", tx, self.y, tab_w, Panel.TAB_BAR_H)
        love.graphics.setColor(1, 1, 1)
        local label = tab.icon and (tab.icon .. " " .. tab.label) or tab.label
        love.graphics.printf(label, tx + 2, self.y + 9, tab_w - 4, "center")
    end
    love.graphics.setScissor()

    -- Content area
    local active_tab = self.tabs[self.active_tab_id]
    if not active_tab or not active_tab.draw then return end

    local s = self.scroll[self.active_tab_id]

    love.graphics.setScissor(self.x, self.content_y, self.w, self.content_h)
    love.graphics.push()
    love.graphics.translate(0, self.content_y - (s and s.scroll_y or 0))

    active_tab.draw(game)

    love.graphics.pop()
    love.graphics.setScissor()

    -- Scrollbar
    if s then self:_drawScrollbar(s) end
end

function Panel:_drawScrollbar(s)
    if s.total_h <= self.content_h then return end
    local track_x = self.x + self.w - Panel.SCROLLBAR_MX
    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.rectangle("fill", track_x, self.content_y, Panel.SCROLLBAR_W, self.content_h)

    local hx, hy, hw, hh = self:_getScrollbarHandleBounds(s)
    if hx then
        love.graphics.setColor(0.8, 0.8, 0.8, 0.7)
        love.graphics.rectangle("fill", hx, hy, hw, hh)
    end
end

return Panel
