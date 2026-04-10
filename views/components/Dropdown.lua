-- views/components/Dropdown.lua
-- A generic dropdown selection widget for UI panels.

local Dropdown = {}
Dropdown.__index = Dropdown

function Dropdown:new(options, current_val, on_select, game)
    local instance = setmetatable({}, Dropdown)
    instance.options     = options or {}
    instance.value       = current_val
    instance.on_select   = on_select
    instance.game        = game

    -- Layout
    instance.x, instance.y = 0, 0
    instance.w = 120
    instance.item_h = 20
    instance.max_visible = 20  -- cap visible rows
    instance.scroll_offset = 0 -- first visible index - 1

    -- Internal state
    instance.is_open = true
    instance.hovered_idx = nil

    -- Auto-scroll so the current value is visible on open
    if current_val then
        for i, opt in ipairs(instance.options) do
            if opt == current_val then
                local max_off = math.max(0, #instance.options - instance.max_visible)
                instance.scroll_offset = math.min(math.max(0, i - math.floor(instance.max_visible / 2)), max_off)
                break
            end
        end
    end

    return instance
end

function Dropdown:update(dt)
    local mx, my = love.mouse.getPosition()
    self.hovered_idx = nil

    local vis = math.min(#self.options, self.max_visible)
    if mx >= self.x and mx <= self.x + self.w then
        local relative_y = my - self.y
        if relative_y >= 0 and relative_y <= vis * self.item_h then
            self.hovered_idx = math.floor(relative_y / self.item_h) + 1 + self.scroll_offset
            if self.hovered_idx > #self.options then self.hovered_idx = nil end
        end
    end
end

function Dropdown:draw(override_x, override_y, override_w)
    local x = override_x or self.x
    local y = override_y or self.y
    local w = override_w or self.w

    local vis = math.min(#self.options, self.max_visible)
    local h = vis * self.item_h

    -- Clamp Y so dropdown stays on screen
    local screen_h = love.graphics.getHeight()
    if y + h > screen_h - 4 then
        y = screen_h - h - 4
    end
    -- Store clamped position for hit-testing
    self.x = x
    self.y = y

    local game = self.game
    local font = game.fonts.ui_small
    local fh = font:getHeight()

    -- Background shadow
    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.rectangle("fill", x + 2, y + 2, w, h, 3)

    -- Main background
    love.graphics.setColor(0.15, 0.15, 0.2, 0.95)
    love.graphics.rectangle("fill", x, y, w, h, 3)

    -- Border
    love.graphics.setColor(0.4, 0.6, 1.0, 0.8)
    love.graphics.rectangle("line", x, y, w, h, 3)

    -- Scrollbar (if needed)
    if #self.options > self.max_visible then
        local sb_h = h * (vis / #self.options)
        local sb_y = y + (self.scroll_offset / (#self.options - vis)) * (h - sb_h)
        love.graphics.setColor(0.5, 0.5, 0.6, 0.4)
        love.graphics.rectangle("fill", x + w - 5, sb_y, 4, sb_h, 2)
    end

    -- Visible options
    love.graphics.setScissor(x, y, w, h)
    for vi = 1, vis do
        local i = vi + self.scroll_offset
        if i > #self.options then break end
        local opt = self.options[i]
        local iy = y + (vi - 1) * self.item_h

        if i == self.hovered_idx then
            love.graphics.setColor(0.3, 0.5, 0.8, 0.6)
            love.graphics.rectangle("fill", x + 1, iy + 1, w - 2, self.item_h - 2, 2)
        end

        if opt == self.value then
            love.graphics.setColor(1, 1, 0.4, 1)
        else
            love.graphics.setColor(1, 1, 1, 1)
        end

        love.graphics.print(tostring(opt), x + 8, iy + (self.item_h - fh) / 2)
    end
    love.graphics.setScissor()
end

function Dropdown:mousepressed(x, y, button)
    if button == 1 and self.hovered_idx then
        local selected = self.options[self.hovered_idx]
        if self.on_select then
            self.on_select(selected)
        end
        return true
    end
    return false
end

function Dropdown:wheelmoved(x, y)
    if #self.options <= self.max_visible then return false end
    local max_off = #self.options - self.max_visible
    self.scroll_offset = math.max(0, math.min(max_off, self.scroll_offset - y))
    return true
end

return Dropdown
