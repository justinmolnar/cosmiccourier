-- ui/zoom_controls.lua
-- Google Maps style zoom buttons with unlock progression

local ZoomControls = {}
ZoomControls.__index = ZoomControls

function ZoomControls:new(C)
    local instance = setmetatable({}, ZoomControls)
    instance.C = C
    instance.zoom_in_button = { x = 0, y = 0, w = C.ZOOM.ZOOM_BUTTON_SIZE, h = C.ZOOM.ZOOM_BUTTON_SIZE }
    instance.zoom_out_button = { x = 0, y = 0, w = C.ZOOM.ZOOM_BUTTON_SIZE, h = C.ZOOM.ZOOM_BUTTON_SIZE }
    instance.hovered_button = nil
    instance.tooltip_text = ""
    return instance
end

function ZoomControls:update(game)
    local C = self.C
    local screen_w, screen_h = love.graphics.getDimensions()
    local sidebar_w = C.UI.SIDEBAR_WIDTH
    
    -- Position buttons in bottom-right of game world area
    local button_x = screen_w - C.ZOOM.ZOOM_BUTTON_SIZE - C.ZOOM.ZOOM_BUTTON_MARGIN
    local button_spacing = C.ZOOM.ZOOM_BUTTON_SIZE + 5
    
    self.zoom_out_button.x = button_x
    self.zoom_out_button.y = screen_h - (button_spacing * 2) - C.ZOOM.ZOOM_BUTTON_MARGIN
    
    self.zoom_in_button.x = button_x  
    self.zoom_in_button.y = screen_h - button_spacing - C.ZOOM.ZOOM_BUTTON_MARGIN
    
    -- Check for hover and set tooltip
    local mx, my = love.mouse.getPosition()
    self.hovered_button = nil
    self.tooltip_text = ""
    
    -- Don't allow interaction during transitions
    if game.map.transition_state.active then
        return
    end
    
    if self:shouldShowButtons(game) then
        if self:pointInButton(mx, my, self.zoom_out_button) then
            self.hovered_button = "zoom_out"
            if not game.state.metro_license_unlocked then
                if game.state.money >= C.ZOOM.PRICE_REVEAL_THRESHOLD then
                    self.tooltip_text = "Metropolitan Expansion License - $" .. C.ZOOM.METRO_LICENSE_COST
                else
                    self.tooltip_text = "Metropolitan Expansion License Required"
                end
            else
                self.tooltip_text = "Zoom out to city view"
            end
        elseif self:pointInButton(mx, my, self.zoom_in_button) then
            self.hovered_button = "zoom_in"
            if game.map:getCurrentScale() == C.MAP.SCALES.CITY then
                self.tooltip_text = "Zoom in to downtown view"
            end
        end
    end
end

function ZoomControls:shouldShowButtons(game)
    -- Show buttons if we've reached the threshold OR if the license is already unlocked
    return game.state.money >= self.C.ZOOM.BUTTONS_APPEAR_THRESHOLD or game.state.metro_license_unlocked
end

function ZoomControls:pointInButton(mx, my, button)
    return mx >= button.x and mx <= button.x + button.w and my >= button.y and my <= button.y + button.h
end

function ZoomControls:draw(game)
    if not self:shouldShowButtons(game) then 
        return 
    end
    
    local C = self.C
    love.graphics.setFont(game.fonts.ui)
    
    -- Gray out buttons during transitions
    local transition_alpha = game.map.transition_state.active and 0.4 or 1.0
    
    -- Draw zoom out button (+)
    local zoom_out_enabled = game.state.metro_license_unlocked and game.map:getCurrentScale() == C.MAP.SCALES.DOWNTOWN
    local zoom_out_color = zoom_out_enabled and {1, 1, 1, transition_alpha} or {0.5, 0.5, 0.5, transition_alpha}
    
    love.graphics.setColor(0, 0, 0, 0.7 * transition_alpha)
    love.graphics.rectangle("fill", self.zoom_out_button.x, self.zoom_out_button.y, self.zoom_out_button.w, self.zoom_out_button.h)
    love.graphics.setColor(zoom_out_color)
    love.graphics.rectangle("line", self.zoom_out_button.x, self.zoom_out_button.y, self.zoom_out_button.w, self.zoom_out_button.h)
    love.graphics.printf("+", self.zoom_out_button.x, self.zoom_out_button.y + 7, self.zoom_out_button.w, "center")
    
    -- Draw zoom in button (-)
    local zoom_in_enabled = game.map:getCurrentScale() == C.MAP.SCALES.CITY
    local zoom_in_color = zoom_in_enabled and {1, 1, 1, transition_alpha} or {0.5, 0.5, 0.5, transition_alpha}
    
    love.graphics.setColor(0, 0, 0, 0.7 * transition_alpha)
    love.graphics.rectangle("fill", self.zoom_in_button.x, self.zoom_in_button.y, self.zoom_in_button.w, self.zoom_in_button.h)
    love.graphics.setColor(zoom_in_color)
    love.graphics.rectangle("line", self.zoom_in_button.x, self.zoom_in_button.y, self.zoom_in_button.w, self.zoom_in_button.h)
    love.graphics.printf("-", self.zoom_in_button.x, self.zoom_in_button.y + 7, self.zoom_in_button.w, "center")
    
    -- Draw price indicator if at price reveal threshold
    if not game.state.metro_license_unlocked and game.state.money >= C.ZOOM.PRICE_REVEAL_THRESHOLD then
        love.graphics.setColor(1, 1, 0, transition_alpha)
        love.graphics.setFont(game.fonts.ui_small)
        local price_text = "$" .. C.ZOOM.METRO_LICENSE_COST
        love.graphics.print(price_text, self.zoom_out_button.x - 60, self.zoom_out_button.y + 8)
    end
    
    -- Draw current scale indicator
    love.graphics.setColor(1, 1, 1, 0.8 * transition_alpha)
    love.graphics.setFont(game.fonts.ui_small)
    local scale_text = game.map:getScaleName()
    if game.map.transition_state.active then
        local from_name = C.MAP.SCALE_NAMES[game.map.transition_state.from_scale]
        local to_name = C.MAP.SCALE_NAMES[game.map.transition_state.to_scale]
        scale_text = from_name .. " → " .. to_name
    end
    love.graphics.print(scale_text, self.zoom_out_button.x - 120, self.zoom_out_button.y - 20)
    
    -- Draw transition progress bar
    if game.map.transition_state.active then
        local progress = game.map.transition_state.progress
        local bar_w = 100
        local bar_h = 4
        local bar_x = self.zoom_out_button.x - bar_w - 10
        local bar_y = self.zoom_out_button.y + 35
        
        love.graphics.setColor(0, 0, 0, 0.7)
        love.graphics.rectangle("fill", bar_x, bar_y, bar_w, bar_h)
        love.graphics.setColor(1, 1, 0)
        love.graphics.rectangle("fill", bar_x, bar_y, bar_w * progress, bar_h)
        love.graphics.setColor(1, 1, 1)
        love.graphics.rectangle("line", bar_x, bar_y, bar_w, bar_h)
    end
    
    -- Draw tooltip (only if not transitioning)
    if self.tooltip_text ~= "" and self.hovered_button and not game.map.transition_state.active then
        local mx, my = love.mouse.getPosition()
        love.graphics.setFont(game.fonts.ui_small)
        local tooltip_w = game.fonts.ui_small:getWidth(self.tooltip_text) + 10
        local tooltip_h = 20
        local tooltip_x = mx - tooltip_w - 10
        local tooltip_y = my - tooltip_h - 5
        
        love.graphics.setColor(0, 0, 0, 0.9)
        love.graphics.rectangle("fill", tooltip_x, tooltip_y, tooltip_w, tooltip_h)
        love.graphics.setColor(1, 1, 1)
        love.graphics.rectangle("line", tooltip_x, tooltip_y, tooltip_w, tooltip_h)
        love.graphics.print(self.tooltip_text, tooltip_x + 5, tooltip_y + 3)
    end
    
    love.graphics.setColor(1, 1, 1)
end

function ZoomControls:handle_click(x, y, game)
    if not self:shouldShowButtons(game) then return false end
    
    -- Don't allow clicks during transitions
    if game.map.transition_state.active then return false end
    
    local C = self.C
    
    if self:pointInButton(x, y, self.zoom_out_button) then
        if not game.state.metro_license_unlocked then
            if game.state.money >= C.ZOOM.METRO_LICENSE_COST then
                game.EventBus:publish("ui_purchase_metro_license_clicked")
                return true
            end
        else
            if game.map:getCurrentScale() == C.MAP.SCALES.DOWNTOWN then
                game.EventBus:publish("ui_zoom_out_clicked")
                return true
            end
        end
    elseif self:pointInButton(x, y, self.zoom_in_button) then
        if game.map:getCurrentScale() == C.MAP.SCALES.CITY then
            game.EventBus:publish("ui_zoom_in_clicked")
            return true
        end
    end
    
    return false
end

return ZoomControls