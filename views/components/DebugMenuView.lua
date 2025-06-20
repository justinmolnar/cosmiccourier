-- views/components/DebugMenuView.lua
-- View component for the debug menu that integrates with the MVC architecture

local DebugMenuView = {}
DebugMenuView.__index = DebugMenuView

function DebugMenuView:new(debug_controller, game)
    local instance = setmetatable({}, DebugMenuView)
    instance.controller = debug_controller
    instance.game = game
    return instance
end

function DebugMenuView:draw()
    if not self.controller:isVisible() then return end
    
    love.graphics.push()
    
    local x, y, w, h = self.controller.x, self.controller.y, self.controller.w, self.controller.h
    local scroll_y = self.controller.scroll_y
    local content_height = self.controller.content_height
    local hovered_button = self.controller.hovered_button
    local params = self.controller.params
    local buttons = self.controller.buttons
    
    -- Draw main menu background
    love.graphics.setColor(0.1, 0.1, 0.15, 0.95)
    love.graphics.rectangle("fill", x, y, w, h)
    
    -- Draw border
    love.graphics.setColor(0.4, 0.4, 0.5)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", x, y, w, h)
    
    -- Draw title bar
    love.graphics.setColor(0.2, 0.2, 0.3)
    love.graphics.rectangle("fill", x, y, w, 25)
    love.graphics.setColor(1, 1, 1)
    love.graphics.setFont(self.game.fonts.ui)
    love.graphics.print("Map Generation Debug", x + 10, y + 5)
    
    -- Draw close button
    love.graphics.setColor(0.8, 0.3, 0.3)
    love.graphics.rectangle("fill", x + w - 25, y + 2, 21, 21)
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf("×", x + w - 25, y + 5, 21, "center")
    
    -- Set up scrollable content area
    love.graphics.setScissor(x, y + 25, w, h - 25)
    love.graphics.push()
    love.graphics.translate(0, -scroll_y)
    
    local content_y = y + 35
    love.graphics.setFont(self.game.fonts.ui_small)
    
    -- Draw parameters section
    love.graphics.setColor(1, 1, 0.8)
    love.graphics.print("Parameters:", x + 10, content_y)
    content_y = content_y + 20
    
    for param_name, value in pairs(params) do
        if type(value) == "number" then
            -- Draw parameter with +/- buttons on the right
            local bg_color = (hovered_button == param_name) and {0.3, 0.3, 0.4} or {0.15, 0.15, 0.2}
            love.graphics.setColor(bg_color)
            love.graphics.rectangle("fill", x + 5, content_y - 2, w - 10, 22)
            
            -- Parameter name
            love.graphics.setColor(1, 1, 1)
            love.graphics.print(param_name, x + 10, content_y + 3)
            
            -- Value area (clickable for text input)
            local value_text = value
            local text_input_active = self.controller.text_input_active
            if text_input_active == param_name then
                value_text = self.controller.text_input_value
                -- Show cursor
                local cursor_time = love.timer.getTime() * 2
                if math.floor(cursor_time) % 2 == 0 then
                    value_text = value_text .. "|"
                end
                -- Highlight the input area
                love.graphics.setColor(0.2, 0.4, 0.6)
                love.graphics.rectangle("fill", x + 35, content_y - 1, w - 140, 22)
            end
            
            love.graphics.setColor(1, 1, 1)
            love.graphics.printf(string.format("%.3f", type(value_text) == "string" and (tonumber(value_text) or 0) or value_text), 
                               x + 35, content_y + 3, w - 140, "right")
            
            -- Minus button (left of plus button)
            love.graphics.setColor(0.8, 0.4, 0.4)
            love.graphics.rectangle("fill", x + w - 70, content_y, 20, 20)
            love.graphics.setColor(1, 1, 1)
            love.graphics.printf("-", x + w - 70, content_y + 3, 20, "center")
            
            -- Plus button (far right)
            love.graphics.setColor(0.4, 0.8, 0.4)
            love.graphics.rectangle("fill", x + w - 50, content_y, 20, 20)
            love.graphics.setColor(1, 1, 1)
            love.graphics.printf("+", x + w - 50, content_y + 3, 20, "center")
            
        elseif type(value) == "boolean" then
            -- Draw boolean toggle
            local bg_color = (hovered_button == param_name) and {0.3, 0.3, 0.4} or {0.15, 0.15, 0.2}
            love.graphics.setColor(bg_color)
            love.graphics.rectangle("fill", x + 5, content_y - 2, w - 10, 22)
            
            local toggle_color = value and {0.4, 0.8, 0.4} or {0.8, 0.4, 0.4}
            love.graphics.setColor(toggle_color)
            love.graphics.rectangle("fill", x + 10, content_y, 20, 20)
            love.graphics.setColor(1, 1, 1)
            love.graphics.printf(value and "✓" or "✗", x + 10, content_y + 2, 20, "center")
            
            love.graphics.print(param_name, x + 35, content_y + 3)
            love.graphics.printf(tostring(value), x + 35, content_y + 3, w - 70, "right")
        end
        
        content_y = content_y + 25
    end
    
    -- Draw actions section
    content_y = content_y + 10
    love.graphics.setColor(1, 1, 0.8)
    love.graphics.print("Actions:", x + 10, content_y)
    content_y = content_y + 20
    
    for i, btn in ipairs(buttons) do
        local btn_y = content_y + (i - 1) * 35
        local bg_color = (hovered_button == btn.id) and {btn.color[1] * 1.3, btn.color[2] * 1.3, btn.color[3] * 1.3} or btn.color
        
        love.graphics.setColor(bg_color)
        love.graphics.rectangle("fill", x + 10, btn_y, w - 20, 30)
        love.graphics.setColor(1, 1, 1)
        love.graphics.rectangle("line", x + 10, btn_y, w - 20, 30)
        love.graphics.printf(btn.text, x + 10, btn_y + 8, w - 20, "center")
    end
    
    love.graphics.pop()
    love.graphics.setScissor()
    
    -- Draw scrollbar
    if content_height > h - 60 then
        local scrollbar_h = (h - 30) * ((h - 60) / content_height)
        local scrollbar_y = y + 30 + (scroll_y / content_height) * (h - 60 - scrollbar_h)
        
        love.graphics.setColor(0.3, 0.3, 0.4)
        love.graphics.rectangle("fill", x + w - 15, y + 30, 10, h - 60)
        love.graphics.setColor(0.6, 0.6, 0.7)
        love.graphics.rectangle("fill", x + w - 15, scrollbar_y, 10, scrollbar_h)
    end
    
    love.graphics.pop()
    love.graphics.setColor(1, 1, 1)
    love.graphics.setLineWidth(1)
end

return DebugMenuView