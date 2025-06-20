-- controllers/DebugMenuController.lua
-- Debug menu controller that integrates with the current MVC architecture

local DebugMenuController = {}
DebugMenuController.__index = DebugMenuController

function DebugMenuController:new(game)
    local instance = setmetatable({}, DebugMenuController)
    instance.game = game
    instance.visible = false
    instance.x = 100
    instance.y = 50
    instance.w = 400
    instance.h = 600
    instance.dragging = false
    instance.drag_offset_x = 0
    instance.drag_offset_y = 0
    instance.scroll_y = 0
    instance.content_height = 0
    instance.dragging_scrollbar = false
    instance.text_input_active = nil -- Which parameter is being edited
    instance.text_input_value = "" -- Current text being typed
    
    -- Debug parameters that can be tweaked
    instance.params = {
        -- Highway Generation
        highway_merge_distance = 50,
        highway_merge_strength = 0.8,
        highway_parallel_merge_distance = 80,
        highway_curve_distance = 50,
        highway_step_size = 30,
        highway_buffer = 35,
        num_ns_highways = 2,
        num_ew_highways = 2,
        
        -- Ring Road Generation
        ring_min_angle = 45, -- degrees
        ring_min_arc_distance = 30,
        ring_edge_threshold = 0.1, -- percentage of map
        ring_center_distance_threshold = 0.15, -- percentage of map
        
        -- District Generation
        num_districts = 10,
        district_min_size = 40,
        district_max_size = 80,
        district_placement_attempts = 500,
        downtown_roads = 40,
        district_roads_min = 15,
        district_roads_max = 30,
        
        -- Connecting Roads
        walker_connection_distance = 25,
        walker_split_chance = 0.05,
        walker_turn_chance = 0.15,
        walker_max_active = 3,
        walker_death_rules_enabled = true,
        
        -- Path Smoothing
        smoothing_max_angle = 126, -- degrees
        smoothing_enabled = true,
    }
    
    -- Button definitions
    instance.buttons = {
        {id = "regen_all", text = "Regenerate All", color = {0.8, 0.2, 0.2}},
        {id = "clear_all", text = "Clear All", color = {0.6, 0.6, 0.6}},
        {id = "regen_districts", text = "Regen Districts", color = {0.2, 0.6, 0.8}},
        {id = "regen_ring", text = "Regen Ring Road", color = {0.2, 0.4, 0.8}},
        {id = "regen_highways", text = "Regen Highways", color = {0.6, 0.8, 0.2}},
        {id = "regen_connections", text = "Regen Connections", color = {0.8, 0.6, 0.2}},
        {id = "test_pathfinding", text = "Test Pathfinding", color = {0.8, 0.2, 0.8}},
        {id = "reset_params", text = "Reset Parameters", color = {0.4, 0.4, 0.4}},
    }
    
    return instance
end

function DebugMenuController:toggle()
    self.visible = not self.visible
    if self.visible then
        self.game.error_service.logInfo("DebugMenu", "Debug menu opened")
    else
        self.game.error_service.logInfo("DebugMenu", "Debug menu closed")
    end
end

function DebugMenuController:isVisible()
    return self.visible
end

function DebugMenuController:handle_mouse_down(x, y, button)
    if not self.visible then return false end
    
    -- First check if click is even within menu bounds - if not, return false immediately
    if not (x >= self.x and x <= self.x + self.w and y >= self.y and y <= self.y + self.h) then
        -- Click is outside menu - cancel any text input and don't consume the click
        self.text_input_active = nil
        return false
    end
    
    -- Check if click is within menu bounds
    if x >= self.x and x <= self.x + self.w and y >= self.y and y <= self.y + self.h then
        
        -- Check scrollbar first
        if self.content_height > self.h - 60 then
            local scrollbar_x = self.x + self.w - 15
            local scrollbar_w = 10
            local scrollbar_y_start = self.y + 30
            local scrollbar_h = self.h - 60
            
            if x >= scrollbar_x and x <= scrollbar_x + scrollbar_w and 
               y >= scrollbar_y_start and y <= scrollbar_y_start + scrollbar_h then
                
                -- Check if clicking on the scrollbar handle for dragging
                local scrollbar_handle_h = scrollbar_h * ((self.h - 60) / self.content_height)
                scrollbar_handle_h = math.max(scrollbar_handle_h, 15)
                local scroll_percentage = self.scroll_y / math.max(1, self.content_height - (self.h - 60))
                local handle_y = scrollbar_y_start + ((scrollbar_h - scrollbar_handle_h) * scroll_percentage)
                
                if y >= handle_y and y <= handle_y + scrollbar_handle_h then
                    -- Start dragging the handle
                    self.dragging_scrollbar = true
                    self.scrollbar_drag_start_y = y
                    self.scroll_y_at_drag_start = self.scroll_y
                    return true
                else
                    -- Click elsewhere on scrollbar track - jump to that position
                    local click_position = (y - scrollbar_y_start) / scrollbar_h
                    self.scroll_y = click_position * math.max(0, self.content_height - (self.h - 60))
                    self.scroll_y = math.max(0, math.min(self.scroll_y, math.max(0, self.content_height - (self.h - 60))))
                    return true
                end
            end
        end
        -- Check title bar for dragging
        if y <= self.y + 25 then
            self.dragging = true
            self.drag_offset_x = x - self.x
            self.drag_offset_y = y - self.y
            return true
        end
        
        -- Check close button
        if x >= self.x + self.w - 25 and x <= self.x + self.w - 4 and y >= self.y + 2 and y <= self.y + 23 then
            self.visible = false
            return true
        end
        
        -- Check buttons
        local content_y = self.y + 35 - self.scroll_y
        
        -- Parameter adjustment buttons (both on the right side now)
        local param_y = content_y + 20 -- Skip header
        for param_name, value in pairs(self.params) do
            if type(value) == "number" then
                -- Check if clicking on the value text (to start editing)
                local value_x = self.x + 35
                local value_w = self.w - 120
                if x >= value_x and x <= value_x + value_w and y >= param_y and y <= param_y + 20 then
                    self.text_input_active = param_name
                    self.text_input_value = tostring(value)
                    return true
                end
                
                -- Minus button (now on the right, left of plus)
                if x >= self.x + self.w - 70 and x <= self.x + self.w - 50 and y >= param_y and y <= param_y + 20 then
                    self:adjustParameter(param_name, -1)
                    return true
                end
                -- Plus button (far right)
                if x >= self.x + self.w - 50 and x <= self.x + self.w - 30 and y >= param_y and y <= param_y + 20 then
                    self:adjustParameter(param_name, 1)
                    return true
                end
                param_y = param_y + 25
            elseif type(value) == "boolean" then
                -- Toggle button
                if x >= self.x + 10 and x <= self.x + self.w - 10 and y >= param_y and y <= param_y + 20 then
                    self.params[param_name] = not self.params[param_name]
                    self.game.error_service.logInfo("DebugMenu", "Toggled " .. param_name .. " to " .. tostring(self.params[param_name]))
                    return true
                end
                param_y = param_y + 25
            end
        end
        
        -- Action buttons
        param_y = param_y + 20
        for i, btn in ipairs(self.buttons) do
            local btn_y = param_y + (i - 1) * 35
            if x >= self.x + 10 and x <= self.x + self.w - 10 and y >= btn_y and y <= btn_y + 30 then
                self:executeAction(btn.id)
                return true
            end
        end
        
        return true -- Consume click even if not on specific element
    end
    
    return false
end

function DebugMenuController:handle_text_input(text)
    if self.text_input_active then
        self.text_input_value = self.text_input_value .. text
        return true
    end
    return false
end

function DebugMenuController:handle_key_pressed(key)
    if self.text_input_active then
        if key == "return" or key == "enter" then
            -- Apply the typed value
            local value = tonumber(self.text_input_value)
            if value then
                self.params[self.text_input_active] = value
                self.game.error_service.logInfo("DebugMenu", 
                    string.format("Set %s to %.3f", self.text_input_active, value))
            end
            self.text_input_active = nil
            self.text_input_value = ""
            return true
        elseif key == "escape" then
            -- Cancel editing
            self.text_input_active = nil
            self.text_input_value = ""
            return true
        elseif key == "backspace" then
            -- Remove last character
            if #self.text_input_value > 0 then
                self.text_input_value = self.text_input_value:sub(1, -2)
            end
            return true
        end
    end
    return false
end

function DebugMenuController:handle_mouse_up(x, y, button)
    self.dragging = false
    self.dragging_scrollbar = false
end

function DebugMenuController:handle_scroll(mx, my, dy)
    if not self.visible then return false end
    
    if mx >= self.x and mx <= self.x + self.w and my >= self.y and my <= self.y + self.h then
        self.scroll_y = self.scroll_y - (dy * 20)
        self.scroll_y = math.max(0, math.min(self.scroll_y, math.max(0, self.content_height - (self.h - 60))))
        return true
    end
    
    return false
end

function DebugMenuController:update(dt)
    if not self.visible then return end
    
    -- Handle dragging
    if self.dragging then
        local mx, my = love.mouse.getPosition()
        self.x = mx - self.drag_offset_x
        self.y = my - self.drag_offset_y
        
        -- Keep menu on screen
        local screen_w, screen_h = love.graphics.getDimensions()
        self.x = math.max(0, math.min(self.x, screen_w - self.w))
        self.y = math.max(0, math.min(self.y, screen_h - self.h))
    end
    
    -- Handle scrollbar dragging
    if self.dragging_scrollbar then
        local mx, my = love.mouse.getPosition()
        local drag_delta = my - self.scrollbar_drag_start_y
        
        -- Convert drag delta to scroll delta
        local scrollbar_h = self.h - 60
        local scrollbar_handle_h = scrollbar_h * ((self.h - 60) / self.content_height)
        scrollbar_handle_h = math.max(scrollbar_handle_h, 15)
        local usable_track_h = scrollbar_h - scrollbar_handle_h
        
        if usable_track_h > 0 then
            local scroll_range = math.max(0, self.content_height - (self.h - 60))
            local scroll_per_pixel = scroll_range / usable_track_h
            self.scroll_y = self.scroll_y_at_drag_start + (drag_delta * scroll_per_pixel)
            self.scroll_y = math.max(0, math.min(self.scroll_y, scroll_range))
        end
    end
    
    -- Calculate content height for scrolling
    local param_count = 0
    for _, _ in pairs(self.params) do param_count = param_count + 1 end
    self.content_height = (param_count * 25) + (#self.buttons * 35) + 100
    
    -- Update hovered button
    local mx, my = love.mouse.getPosition()
    self.hovered_button = nil
    
    if mx >= self.x and mx <= self.x + self.w and my >= self.y + 35 and my <= self.y + self.h then
        local content_y = self.y + 35 - self.scroll_y
        
        -- Check parameter buttons
        local param_y = content_y + 20
        for param_name, value in pairs(self.params) do
            if type(value) == "number" then
                if ((mx >= self.x + 10 and mx <= self.x + 30) or (mx >= self.x + self.w - 50 and mx <= self.x + self.w - 30)) and 
                   my >= param_y and my <= param_y + 20 then
                    self.hovered_button = param_name
                end
                param_y = param_y + 25
            elseif type(value) == "boolean" then
                if mx >= self.x + 10 and mx <= self.x + self.w - 10 and my >= param_y and my <= param_y + 20 then
                    self.hovered_button = param_name
                end
                param_y = param_y + 25
            end
        end
        
        -- Check action buttons
        param_y = param_y + 20
        for i, btn in ipairs(self.buttons) do
            local btn_y = param_y + (i - 1) * 35
            if mx >= self.x + 10 and mx <= self.x + self.w - 10 and my >= btn_y and my <= btn_y + 30 then
                self.hovered_button = btn.id
            end
        end
    end
end

function DebugMenuController:adjustParameter(param_name, direction)
    local value = self.params[param_name]
    local increment = 1
    
    -- Different increments for different types of parameters
    if param_name:find("distance") or param_name:find("size") or param_name:find("step") then
        increment = 5
    elseif param_name:find("angle") then
        increment = 5
    elseif param_name:find("strength") or param_name:find("chance") or param_name:find("threshold") then
        increment = 0.05
    elseif param_name:find("num_") then
        increment = 1
    end
    
    local new_value = value + (direction * increment)
    
    -- Apply reasonable bounds
    if param_name:find("chance") or param_name:find("strength") or param_name:find("threshold") then
        new_value = math.max(0, math.min(1, new_value))
    elseif param_name:find("angle") then
        new_value = math.max(0, math.min(180, new_value))
    elseif param_name:find("num_") then
        new_value = math.max(1, math.min(6, new_value))
    elseif param_name:find("distance") or param_name:find("size") then
        new_value = math.max(1, new_value)
    end
    
    self.params[param_name] = new_value
    self.game.error_service.logInfo("DebugMenu", string.format("Adjusted %s: %.3f", param_name, new_value))
    
    -- Auto-apply certain parameter changes
    if param_name:find("highway") then
        self:executeAction("regen_highways")
    elseif param_name:find("ring") then
        self:executeAction("regen_ring")
    elseif param_name:find("walker") or param_name:find("connection") then
        self:executeAction("regen_connections")
    end
end

function DebugMenuController:executeAction(action_id)
    self.game.error_service.logInfo("DebugMenu", "Executing action: " .. action_id)
    
    local function safeExecute(func, action_name)
        self.game.error_service.withErrorHandling(func, "Debug Menu: " .. action_name)
    end
    
    if action_id == "regen_all" then
        safeExecute(function()
            self:applyParametersToModules()
            -- Force map to regenerate with new parameters
            self.game.map.debug_params = self.params
            self.game.map:generate()
            self.game.error_service.logInfo("DebugMenu", "Regenerated entire map with current parameters")
        end, "Regenerate All")
        
    elseif action_id == "clear_all" then
        safeExecute(function()
            self:clearAllRoads()
            self.game.error_service.logInfo("DebugMenu", "Cleared all roads and structures")
        end, "Clear All")
        
    elseif action_id == "regen_districts" then
        safeExecute(function()
            self:applyParametersToModules()
            self:regenerateDistricts()
            self.game.error_service.logInfo("DebugMenu", "Regenerated districts")
        end, "Regenerate Districts")
        
    elseif action_id == "regen_ring" then
        safeExecute(function()
            self:applyParametersToModules()
            self:regenerateRingRoad()
            self.game.error_service.logInfo("DebugMenu", "Regenerated ring road")
        end, "Regenerate Ring Road")
        
    elseif action_id == "regen_highways" then
        safeExecute(function()
            self:applyParametersToModules()
            self:regenerateHighways()
            self.game.error_service.logInfo("DebugMenu", "Regenerated highways")
        end, "Regenerate Highways")
        
    elseif action_id == "regen_connections" then
        safeExecute(function()
            self:applyParametersToModules()
            self:regenerateConnections()
            self.game.error_service.logInfo("DebugMenu", "Regenerated connecting roads")
        end, "Regenerate Connections")
        
    elseif action_id == "test_pathfinding" then
        safeExecute(function()
            self:testPathfinding()
        end, "Test Pathfinding")
        
    elseif action_id == "reset_params" then
        self:resetParameters()
        self.game.error_service.logInfo("DebugMenu", "Reset all parameters to defaults")
    end
end

function DebugMenuController:applyParametersToModules()
    -- Store debug parameters in the map object so generators can access them
    self.game.map.debug_params = self.params
    self.game.error_service.logInfo("DebugMenu", "Applied debug parameters to map generation modules")
    
    -- Log the current parameters being applied
    for param_name, value in pairs(self.params) do
        self.game.error_service.logInfo("DebugMenu", string.format("  %s: %s", param_name, tostring(value)))
    end
end

function DebugMenuController:clearAllRoads()
    -- Clear roads from both city and downtown scales
    local scales_to_clear = {self.game.C.MAP.SCALES.DOWNTOWN, self.game.C.MAP.SCALES.CITY}
    
    for _, scale in ipairs(scales_to_clear) do
        local grid = self.game.map.scale_grids[scale]
        if grid then
            for y = 1, #grid do
                for x = 1, #grid[1] do
                    local current_type = grid[y][x].type
                    if current_type ~= "plot" and current_type ~= "grass" then
                        grid[y][x].type = "grass"
                    end
                end
            end
        end
    end
    self:refreshMapDisplay()
end

function DebugMenuController:regenerateDistricts()
    self.game.error_service.logInfo("DebugMenu", "Regenerating districts with parameters:")
    for k, v in pairs(self.params) do
        if k:find("district") or k:find("downtown") then
            self.game.error_service.logInfo("DebugMenu", string.format("  %s: %s", k, tostring(v)))
        end
    end
    
    -- Force full regeneration since districts are fundamental
    self.game.map.debug_params = self.params
    self.game.map:generate()
end

function DebugMenuController:regenerateRingRoad()
    self.game.error_service.logInfo("DebugMenu", "Regenerating ring road with parameters:")
    for k, v in pairs(self.params) do
        if k:find("ring") then
            self.game.error_service.logInfo("DebugMenu", string.format("  %s: %s", k, tostring(v)))
        end
    end
    
    -- This would need specific ring road regeneration logic
    -- For now, regenerate the whole city scale
    self.game.map.debug_params = self.params
    local downtown_grid = self.game.map.scale_grids[self.game.C.MAP.SCALES.DOWNTOWN]
    if downtown_grid then
        local city_grid = self.game.map:generateCityModuleModular(downtown_grid)
        self.game.map.scale_grids[self.game.C.MAP.SCALES.CITY] = city_grid
        self.game.map.scale_building_plots[self.game.C.MAP.SCALES.CITY] = self.game.map:getPlotsFromGrid(city_grid)
        self:refreshMapDisplay()
    end
end

function DebugMenuController:regenerateHighways()
    self.game.error_service.logInfo("DebugMenu", "Regenerating highways with parameters:")
    for k, v in pairs(self.params) do
        if k:find("highway") then
            self.game.error_service.logInfo("DebugMenu", string.format("  %s: %s", k, tostring(v)))
        end
    end
    
    -- This would need specific highway regeneration logic
    -- For now, regenerate the whole city scale
    self.game.map.debug_params = self.params
    local downtown_grid = self.game.map.scale_grids[self.game.C.MAP.SCALES.DOWNTOWN]
    if downtown_grid then
        local city_grid = self.game.map:generateCityModuleModular(downtown_grid)
        self.game.map.scale_grids[self.game.C.MAP.SCALES.CITY] = city_grid
        self.game.map.scale_building_plots[self.game.C.MAP.SCALES.CITY] = self.game.map:getPlotsFromGrid(city_grid)
        self:refreshMapDisplay()
    end
end

function DebugMenuController:regenerateConnections()
    self.game.error_service.logInfo("DebugMenu", "Regenerating connections with parameters:")
    for k, v in pairs(self.params) do
        if k:find("walker") or k:find("connection") or k:find("smoothing") then
            self.game.error_service.logInfo("DebugMenu", string.format("  %s: %s", k, tostring(v)))
        end
    end
    
    -- This would need specific connecting roads regeneration logic
    -- For now, regenerate the whole city scale
    self.game.map.debug_params = self.params
    local downtown_grid = self.game.map.scale_grids[self.game.C.MAP.SCALES.DOWNTOWN]
    if downtown_grid then
        local city_grid = self.game.map:generateCityModuleModular(downtown_grid)
        self.game.map.scale_grids[self.game.C.MAP.SCALES.CITY] = city_grid
        self.game.map.scale_building_plots[self.game.C.MAP.SCALES.CITY] = self.game.map:getPlotsFromGrid(city_grid)
        self:refreshMapDisplay()
    end
end

function DebugMenuController:testPathfinding()
    local grid = self.game.map.grid
    if grid and #grid > 0 then
        local plots = self.game.map.building_plots
        if #plots >= 2 then
            local start_plot = plots[love.math.random(1, #plots)]
            local end_plot = plots[love.math.random(1, #plots)]
            local start_node = self.game.map:findNearestRoadTile(start_plot)
            local end_node = self.game.map:findNearestRoadTile(end_plot)
            
            if start_node and end_node then
                local path = self.game.pathfinder.findPath(grid, start_node, end_node)
                if path then
                    self.game.error_service.logInfo("DebugMenu", 
                        string.format("Test path found: %d nodes from (%d,%d) to (%d,%d)", 
                                    #path, start_node.x, start_node.y, end_node.x, end_node.y))
                else
                    self.game.error_service.logWarning("DebugMenu", "Test pathfinding failed - no path found")
                end
            else
                self.game.error_service.logWarning("DebugMenu", "Test pathfinding failed - couldn't find road nodes")
            end
        end
    end
end

function DebugMenuController:resetParameters()
    self.params = {
        highway_merge_distance = 50,
        highway_merge_strength = 0.8,
        highway_parallel_merge_distance = 80,
        highway_curve_distance = 50,
        highway_step_size = 30,
        highway_buffer = 35,
        num_ns_highways = 2,
        num_ew_highways = 2,
        ring_min_angle = 45,
        ring_min_arc_distance = 30,
        ring_edge_threshold = 0.1,
        ring_center_distance_threshold = 0.15,
        num_districts = 10,
        district_min_size = 40,
        district_max_size = 80,
        district_placement_attempts = 500,
        downtown_roads = 40,
        district_roads_min = 15,
        district_roads_max = 30,
        walker_connection_distance = 25,
        walker_split_chance = 0.05,
        walker_turn_chance = 0.15,
        walker_max_active = 3,
        walker_death_rules_enabled = true,
        smoothing_max_angle = 126,
        smoothing_enabled = true,
    }
end

function DebugMenuController:refreshMapDisplay()
    -- Refresh the map display
    self.game.map.grid = self.game.map.scale_grids[self.game.map.current_scale]
    self.game.map.building_plots = self.game.map.scale_building_plots[self.game.map.current_scale]
end

return DebugMenuController