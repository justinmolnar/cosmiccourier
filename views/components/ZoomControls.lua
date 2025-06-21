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
    
    -- Safety checks for active map
    if not game.maps or not game.active_map_key then return end
    local active_map = game.maps[game.active_map_key]
    if not active_map then return end

    -- Don't allow interaction during transitions
    if active_map.transition_state.active then
        return
    end
    
    if self:shouldShowButtons(game) then
        local current_scale = game.state.current_map_scale
        if self:pointInButton(mx, my, self.zoom_out_button) then
            self.hovered_button = "zoom_out"
            if current_scale == C.MAP.SCALES.DOWNTOWN then
                if not game.state.metro_license_unlocked then
                    self.tooltip_text = "Metropolitan Expansion License Required"
                else
                    self.tooltip_text = "Zoom out to City View"
                end
            elseif current_scale == C.MAP.SCALES.CITY then
                 self.tooltip_text = "Zoom out to Region View"
            end
        elseif self:pointInButton(mx, my, self.zoom_in_button) then
            self.hovered_button = "zoom_in"
            if current_scale == C.MAP.SCALES.CITY then
                self.tooltip_text = "Zoom in to Downtown View"
            elseif current_scale == C.MAP.SCALES.REGION then
                self.tooltip_text = "Zoom in to City View"
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
    local current_scale = game.state.current_map_scale
    local active_map = game.maps[game.active_map_key]
    
    love.graphics.setFont(game.fonts.ui)
    
    local transition_alpha = active_map.transition_state.active and 0.4 or 1.0
    
    -- === Zoom Out Button ('+') LOGIC ===
    local can_afford_license = game.state.money >= C.ZOOM.METRO_LICENSE_COST
    local is_hovered_out = self.hovered_button == "zoom_out"
    
    -- MODIFIED: New logic to determine if the button should be enabled
    local zoom_out_enabled = (current_scale == C.MAP.SCALES.CITY) or 
                             (current_scale == C.MAP.SCALES.DOWNTOWN and game.state.metro_license_unlocked) or
                             (current_scale == C.MAP.SCALES.DOWNTOWN and not game.state.metro_license_unlocked and can_afford_license)

    love.graphics.setColor(0, 0, 0, 0.7 * transition_alpha)
    love.graphics.rectangle("fill", self.zoom_out_button.x, self.zoom_out_button.y, self.zoom_out_button.w, self.zoom_out_button.h)
    
    if zoom_out_enabled and is_hovered_out then
        love.graphics.setColor(1, 1, 0, transition_alpha) -- Hover color
    elseif zoom_out_enabled then
        love.graphics.setColor(1, 1, 1, transition_alpha) -- Enabled color
    else
        love.graphics.setColor(0.5, 0.5, 0.5, transition_alpha) -- Disabled color
    end
    love.graphics.rectangle("line", self.zoom_out_button.x, self.zoom_out_button.y, self.zoom_out_button.w, self.zoom_out_button.h)
    love.graphics.printf("+", self.zoom_out_button.x, self.zoom_out_button.y + 7, self.zoom_out_button.w, "center")
    
    -- === Zoom In Button ('-') LOGIC ===
    local zoom_in_enabled = current_scale == C.MAP.SCALES.CITY or current_scale == C.MAP.SCALES.REGION
    local is_hovered_in = self.hovered_button == "zoom_in"

    love.graphics.setColor(0, 0, 0, 0.7 * transition_alpha)
    love.graphics.rectangle("fill", self.zoom_in_button.x, self.zoom_in_button.y, self.zoom_in_button.w, self.zoom_in_button.h)
    
    if zoom_in_enabled and is_hovered_in then
        love.graphics.setColor(1, 1, 0, transition_alpha) -- Hover color
    elseif zoom_in_enabled then
        love.graphics.setColor(1, 1, 1, transition_alpha) -- Enabled color
    else
        love.graphics.setColor(0.5, 0.5, 0.5, transition_alpha) -- Disabled color
    end
    love.graphics.rectangle("line", self.zoom_in_button.x, self.zoom_in_button.y, self.zoom_in_button.w, self.zoom_in_button.h)
    love.graphics.printf("-", self.zoom_in_button.x, self.zoom_in_button.y + 7, self.zoom_in_button.w, "center")
    
    -- Price indicator logic (this part is correct)
    if current_scale == C.MAP.SCALES.DOWNTOWN and not game.state.metro_license_unlocked and game.state.money >= C.ZOOM.PRICE_REVEAL_THRESHOLD then
        love.graphics.setColor(1, 1, 0, transition_alpha)
        love.graphics.setFont(game.fonts.ui_small)
        local price_text = "$" .. C.ZOOM.METRO_LICENSE_COST
        love.graphics.print(price_text, self.zoom_out_button.x - 60, self.zoom_out_button.y + 8)
    end
    
    -- Draw current scale indicator and tooltip...
    love.graphics.setColor(1, 1, 1, 0.8 * transition_alpha)
    love.graphics.setFont(game.fonts.ui_small)
    love.graphics.print(active_map:getScaleName(), self.zoom_out_button.x - 120, self.zoom_out_button.y - 20)
    
    if self.tooltip_text ~= "" and self.hovered_button and not active_map.transition_state.active then
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
    
    local active_map = game.maps[game.active_map_key]
    if not active_map or active_map.transition_state.active then return false end
    
    local C = game.C
    local state = game.state
    local current_scale = state.current_map_scale
    
    -- === Zoom Out Button Click Logic ===
    if self:pointInButton(x, y, self.zoom_out_button) then
        -- Case 1: In Downtown, license not owned, but can afford it.
        if current_scale == C.MAP.SCALES.DOWNTOWN and not state.metro_license_unlocked and state.money >= C.ZOOM.METRO_LICENSE_COST then
            game.EventBus:publish("ui_purchase_metro_license_clicked")
            return true
        -- Case 2: In Downtown and license is owned, OR in City view.
        elseif (current_scale == C.MAP.SCALES.DOWNTOWN and state.metro_license_unlocked) or (current_scale == C.MAP.SCALES.CITY) then
            game.EventBus:publish("ui_zoom_out_clicked")
            return true
        end
    
    -- === Zoom In Button Click Logic ===
    elseif self:pointInButton(x, y, self.zoom_in_button) then
        local zoom_in_enabled = (current_scale == C.MAP.SCALES.CITY or current_scale == C.MAP.SCALES.REGION)
        if zoom_in_enabled then
            game.EventBus:publish("ui_zoom_in_clicked")
            return true
        end
    end
    
    return false
end

return ZoomControls