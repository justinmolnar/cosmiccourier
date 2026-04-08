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
    
    -- Internal state
    instance.is_open = true -- Dropdowns are usually created when opened
    instance.hovered_idx = nil

    return instance
end

function Dropdown:update(dt)
    local mx, my = love.mouse.getPosition()
    self.hovered_idx = nil
    
    if mx >= self.x and mx <= self.x + self.w then
        local relative_y = my - self.y
        if relative_y >= 0 and relative_y <= #self.options * self.item_h then
            self.hovered_idx = math.floor(relative_y / self.item_h) + 1
        end
    end
end

function Dropdown:draw(override_x, override_y, override_w)
    local x = override_x or self.x
    local y = override_y or self.y
    local w = override_w or self.w
    local h = #self.options * self.item_h
    
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

    -- Options
    for i, opt in ipairs(self.options) do
        local iy = y + (i - 1) * self.item_h
        
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
end

function Dropdown:mousepressed(x, y, button)
    if button == 1 and self.hovered_idx then
        local selected = self.options[self.hovered_idx]
        if self.on_select then
            self.on_select(selected)
        end
        return true -- Consumed
    end
    return false
end

return Dropdown
