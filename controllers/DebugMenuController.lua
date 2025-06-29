-- controllers/DebugMenuController.lua
-- Debug menu controller that integrates with the current MVC architecture
-- FIXED: Mouse position handling and scrollbar functionality

local DebugMenuController = {}
DebugMenuController.__index = DebugMenuController

function DebugMenuController:new(game)
    local instance = setmetatable({}, DebugMenuController)
    instance.game = game
    instance.visible = false
    instance.x = 100
    instance.y = 50
    instance.w = 450
    instance.h = 700
    instance.dragging = false
    instance.drag_offset_x = 0
    instance.drag_offset_y = 0
    instance.scroll_y = 0
    instance.content_height = 0
    instance.dragging_scrollbar = false
    instance.scrollbar_drag_start_y = 0
    instance.scroll_y_at_drag_start = 0
    instance.text_input_active = nil
    instance.text_input_value = ""
    
    instance.tabs = { "Generation", "Gameplay", "Stats" }
    instance.active_tab = "Generation"
    instance.hovered_tab = nil
    
    -- Load default parameters from the constants file
    instance.params = {}
    for k, v in pairs(game.C.MAP_GEN) do
        -- Converting to lowercase for the debug menu's internal use
        instance.params[string.lower(k)] = v
    end
    
    -- Button definitions
    instance.buttons = {
        {id = "regen_all", text = "Regenerate Everything", color = {0.8, 0.2, 0.2}, tab = "Generation"},
        {id = "clear_all", text = "Clear All Roads", color = {0.6, 0.6, 0.6}, tab = "Generation"},
        {id = "regen_downtown", text = "Regen Downtown Only", color = {0.2, 0.8, 0.2}, tab = "Generation"},
        {id = "regen_districts", text = "Regen Districts Only", color = {0.2, 0.6, 0.8}, tab = "Generation"},
        {id = "regen_ring", text = "Regen Ring Road Only", color = {0.2, 0.4, 0.8}, tab = "Generation"},
        {id = "regen_highways", text = "Regen Highways Only", color = {0.6, 0.8, 0.2}, tab = "Generation"},
        {id = "regen_connections", text = "Regen Connections Only", color = {0.8, 0.6, 0.2}, tab = "Generation"},
        {id = "test_pathfinding", text = "Test Pathfinding (Random)", color = {0.8, 0.2, 0.8}, tab = "Generation"},
        {id = "reset_params", text = "Reset All Parameters", color = {0.4, 0.4, 0.4}, tab = "Generation"},
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

    -- Check if click is outside the menu's main rectangle
    if not (x >= self.x and x <= self.x + self.w and y >= self.y and y <= self.y + self.h) then
        return false -- Click was outside, do not consume it
    end
    
    -- From here, we consume the click to prevent interaction with the game world
    
    -- 1. Handle Non-Scrolling UI (Title bar, Close button, Tabs)
    if y <= self.y + 25 then -- Title Bar Drag
        self.dragging = true
        self.drag_offset_x = x - self.x
        self.drag_offset_y = y - self.y
        return true
    end

    if x >= self.x + self.w - 25 and x <= self.x + self.w - 4 and y >= self.y + 2 and y <= self.y + 23 then -- Close Button
        self.visible = false
        return true
    end
    
    local tab_y = self.y + 25
    local tab_h = 25
    if y > tab_y and y < tab_y + tab_h then -- Tabs
        local tab_w = self.w / #self.tabs
        local tab_index = math.floor((x - self.x) / tab_w) + 1
        if tab_index >= 1 and tab_index <= #self.tabs then
            self.active_tab = self.tabs[tab_index]
            return true
        end
    end
    
    -- 2. Handle Scrollbar Interaction (FIXED)
    local content_area_y = self.y + 51
    local content_area_h = self.h - 52
    
    -- Check if we have a scrollbar
    if self.content_height > content_area_h then
        local scrollbar_x = self.x + self.w - 15
        local scrollbar_w = 10
        
        -- Check if click is on scrollbar
        if x >= scrollbar_x and x <= scrollbar_x + scrollbar_w and 
           y >= content_area_y and y <= content_area_y + content_area_h then
            
            -- Calculate scrollbar handle position and size
            local handle_h = content_area_h * (content_area_h / self.content_height)
            handle_h = math.max(handle_h, 15)
            
            local scroll_range = math.max(0, self.content_height - content_area_h)
            local scroll_percentage = scroll_range > 0 and (self.scroll_y / scroll_range) or 0
            
            local usable_track_h = content_area_h - handle_h
            local handle_y = content_area_y + (usable_track_h * scroll_percentage)
            
            -- Check if click is on the handle
            if y >= handle_y and y <= handle_y + handle_h then
                self.dragging_scrollbar = true
                self.scrollbar_drag_start_y = y
                self.scroll_y_at_drag_start = self.scroll_y
                return true
            else
                -- Click is on scrollbar track - jump to that position
                local relative_y = y - content_area_y
                local new_scroll_percentage = relative_y / content_area_h
                self.scroll_y = new_scroll_percentage * scroll_range
                self.scroll_y = math.max(0, math.min(self.scroll_y, scroll_range))
                return true
            end
        end
    end
    
    -- 3. Handle Scrolling UI Content (Buttons and Parameters) - FIXED
    if y > content_area_y and y < content_area_y + content_area_h then
        -- This is the crucial part: Convert mouse 'y' into the scrolled content's coordinate space
        local y_in_content = y - content_area_y + self.scroll_y

        if self.active_tab == "Generation" then
            -- Use a clean cursor that mirrors the draw function's logic
            local current_y_in_content = 10 
            
            -- Parameters Section
            current_y_in_content = current_y_in_content + 20 -- "Parameters:" header height
            for param_name, value in pairs(self.params) do
                if type(value) == "number" then
                    if y_in_content >= current_y_in_content and y_in_content < current_y_in_content + 25 then
                        -- Minus button
                        if x >= self.x + self.w - 70 and x <= self.x + self.w - 50 then
                            self:adjustParameter(param_name, -1)
                            return true
                        end
                        -- Plus button
                        if x >= self.x + self.w - 50 and x <= self.x + self.w - 30 then
                            self:adjustParameter(param_name, 1)
                            return true
                        end
                    end
                elseif type(value) == "boolean" then
                    if y_in_content >= current_y_in_content and y_in_content < current_y_in_content + 25 then
                        -- Toggle button (entire parameter row is clickable)
                        if x >= self.x + 10 and x <= self.x + self.w - 30 then
                            self.params[param_name] = not self.params[param_name]
                            self.game.error_service.logInfo("DebugMenu", 
                                string.format("Toggled %s to %s", param_name, tostring(self.params[param_name])))
                            return true
                        end
                    end
                end
                current_y_in_content = current_y_in_content + 25
            end

            -- Actions Section
            current_y_in_content = current_y_in_content + 10 + 20 -- Spacing + "Actions:" header height
            for _, btn in ipairs(self.buttons) do
                if btn.tab == self.active_tab then
                    if y_in_content >= current_y_in_content and y_in_content < current_y_in_content + 30 then
                        if x >= self.x + 10 and x <= self.x + self.w - 30 then -- Account for scrollbar space
                            self:executeAction(btn.id)
                            return true
                        end
                    end
                    current_y_in_content = current_y_in_content + 35
                end
            end
        end
    end

    return true -- Consume click
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
    
    -- Handle scrollbar dragging (FIXED)
    if self.dragging_scrollbar then
        local mx, my = love.mouse.getPosition()
        local drag_delta = my - self.scrollbar_drag_start_y
        
        -- Convert drag delta to scroll delta
        local content_area_h = self.h - 52
        local scrollbar_handle_h = content_area_h * (content_area_h / self.content_height)
        scrollbar_handle_h = math.max(scrollbar_handle_h, 15)
        local usable_track_h = content_area_h - scrollbar_handle_h
        
        if usable_track_h > 0 then
            local scroll_range = math.max(0, self.content_height - content_area_h)
            local scroll_per_pixel = scroll_range / usable_track_h
            self.scroll_y = self.scroll_y_at_drag_start + (drag_delta * scroll_per_pixel)
            self.scroll_y = math.max(0, math.min(self.scroll_y, scroll_range))
        end
    end
    
    -- Calculate content height for scrolling (IMPROVED)
    if self.active_tab == "Generation" then
        local param_count = 0
        for _, _ in pairs(self.params) do param_count = param_count + 1 end
        
        local button_count = 0
        for _, btn in ipairs(self.buttons) do
            if btn.tab == self.active_tab then
                button_count = button_count + 1
            end
        end
        
        self.content_height = 10 + 20 + (param_count * 25) + 10 + 20 + (button_count * 35) + 20
    else
        self.content_height = 100 -- Default for other tabs
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
end

function DebugMenuController:executeAction(action_id)
    self.game.error_service.logInfo("DebugMenu", "Executing action: " .. action_id)
    
    local function safeExecute(func, action_name)
        self.game.error_service.withErrorHandling(func, "Debug Menu: " .. action_name)
    end
    
    if action_id == "regen_all" then
        safeExecute(function()
            self:applyParametersToModules()
            
            -- REVERTED: Always use the original generation system for the debug menu
            print("DebugMenu: Using original legacy generation system")
            self.game.maps.city:generate()
            
            -- ADDED: Sync changes to region map so they're visible at region scale
            self:syncCityToRegion()
            
            self.game.error_service.logInfo("DebugMenu", "Regenerated entire map with current parameters")
        end, "Regenerate All")
        
    elseif action_id == "clear_all" then
        safeExecute(function()
            self:clearAllRoads()
            -- ADDED: Sync changes to region map
            self:syncCityToRegion()
            self.game.error_service.logInfo("DebugMenu", "Cleared all roads and structures")
        end, "Clear All")
        
    elseif action_id == "regen_downtown" then
        safeExecute(function()
            self:regenerateDowntownOnly()
            -- ADDED: Sync changes to region map
            self:syncCityToRegion()
        end, "Regenerate Downtown")
        
    elseif action_id == "regen_districts" then
        safeExecute(function()
            self:regenerateDistrictsOnly()
            -- ADDED: Sync changes to region map
            self:syncCityToRegion()
        end, "Regenerate Districts")
        
    elseif action_id == "regen_ring" then
        safeExecute(function()
            self:regenerateRingRoadOnly()
            -- ADDED: Sync changes to region map
            self:syncCityToRegion()
        end, "Regenerate Ring Road")
        
    elseif action_id == "regen_highways" then
        safeExecute(function()
            self:regenerateHighwaysOnly()
            -- ADDED: Sync changes to region map
            self:syncCityToRegion()
        end, "Regenerate Highways")
        
    elseif action_id == "regen_connections" then
        safeExecute(function()
            self:regenerateConnectionsOnly()
            -- ADDED: Sync changes to region map
            self:syncCityToRegion()
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
    self.game.maps.city.debug_params = self.params
    self.game.error_service.logInfo("DebugMenu", "Applied debug parameters to map generation modules")
    
    -- Log the current parameters being applied
    for param_name, value in pairs(self.params) do
        self.game.error_service.logInfo("DebugMenu", string.format("  %s: %s", param_name, tostring(value)))
    end
end

function DebugMenuController:syncCityToRegion()
    -- After modifying the city map, we need to copy those changes to the region map
    local region_map = self.game.maps.region
    local city_map = self.game.maps.city
    
    if not region_map or not city_map or not region_map.main_city_offset then
        return
    end
    
    local city_grid = city_map.grid
    local region_grid = region_map.grid
    
    if not city_grid or not region_grid or #city_grid == 0 then
        return
    end
    
    -- Get the offset where the main city is located in the region
    local offset_x = region_map.main_city_offset.x
    local offset_y = region_map.main_city_offset.y
    
    local city_w = self.game.C.MAP.CITY_GRID_WIDTH
    local city_h = self.game.C.MAP.CITY_GRID_HEIGHT
    
    -- Copy city grid changes to the corresponding area in the region grid
    for y = 1, math.min(city_h, #city_grid) do
        for x = 1, math.min(city_w, #city_grid[1]) do
            local region_x = offset_x + x
            local region_y = offset_y + y
            
            -- Make sure we're within the region grid bounds
            if region_y >= 1 and region_y <= #region_grid and 
               region_x >= 1 and region_x <= #region_grid[1] then
                region_grid[region_y][region_x] = city_grid[y][x]
            end
        end
    end
    
    self.game.error_service.logInfo("DebugMenu", "Synchronized city changes to region map")
end

function DebugMenuController:clearAllRoads()
    local grid = self.game.maps.city.grid
    if not grid or #grid == 0 then return end
    
    local grid_h, grid_w = #grid, #grid[1]
    
    for y = 1, grid_h do
        for x = 1, grid_w do
            local current_type = grid[y][x].type
            if current_type ~= "plot" and current_type ~= "grass" then
                grid[y][x].type = "grass"
            end
        end
    end
    
    -- Regenerate building plots after clearing
    self.game.maps.city.building_plots = self.game.maps.city:getPlotsFromGrid(grid)
    self.game.error_service.logInfo("DebugMenu", "Cleared all roads, regenerated building plots")
end

function DebugMenuController:regenerateDowntownOnly()
    self:applyParametersToModules()
    
    if not self.params.generate_downtown then
        self.game.error_service.logInfo("DebugMenu", "Downtown generation disabled, skipping")
        return
    end
    
    -- Clear only downtown area and regenerate it
    local downtown_offset = self.game.maps.city.downtown_offset
    local C_MAP = self.game.C.MAP
    
    local grid = self.game.maps.city.grid
    if not grid or not downtown_offset then return end
    
    -- Clear downtown area
    for y = downtown_offset.y, downtown_offset.y + C_MAP.DOWNTOWN_GRID_HEIGHT - 1 do
        for x = downtown_offset.x, downtown_offset.x + C_MAP.DOWNTOWN_GRID_WIDTH - 1 do
            if y >= 1 and y <= #grid and x >= 1 and x <= #grid[1] then
                grid[y][x].type = "plot"
            end
        end
    end
    
    -- Regenerate downtown
    local Downtown = require("models.generators.downtown")
    local downtown_district = {
        x = downtown_offset.x, 
        y = downtown_offset.y,
        w = C_MAP.DOWNTOWN_GRID_WIDTH, 
        h = C_MAP.DOWNTOWN_GRID_HEIGHT
    }
    
    Downtown.generateDowntownModule(grid, downtown_district, "road", "plot", self.params)
    
    -- Regenerate building plots
    self.game.maps.city.building_plots = self.game.maps.city:getPlotsFromGrid(grid)
    self.game.error_service.logInfo("DebugMenu", "Regenerated downtown only")
end

function DebugMenuController:regenerateDistrictsOnly()
    self:applyParametersToModules()
    
    if not self.params.generate_districts then
        self.game.error_service.logInfo("DebugMenu", "District generation disabled, skipping")
        return
    end
    
    -- This requires more complex logic to regenerate districts without affecting other elements
    -- For now, regenerate everything
    self.game.maps.city:generate()
    self.game.error_service.logInfo("DebugMenu", "Regenerated districts (full regen)")
end

function DebugMenuController:regenerateRingRoadOnly()
    self:applyParametersToModules()
    
    if not self.params.generate_ringroad then
        self.game.error_service.logInfo("DebugMenu", "Ring road generation disabled, skipping")
        return
    end
    
    local grid = self.game.maps.city.grid
    if not grid or #grid == 0 then return end
    
    -- Clear existing ring roads
    for y = 1, #grid do
        for x = 1, #grid[1] do
            if grid[y][x].type == "highway_ring" then
                grid[y][x].type = "grass"
            end
        end
    end
    
    -- Get current districts (we need them for ring road generation)
    local Districts = require("models.generators.districts")
    local RingRoad = require("models.generators.ringroad")
    
    -- Find existing districts by analyzing the map
    local existing_districts = self:findExistingDistricts()
    
    if #existing_districts > 0 then
        local C_MAP = self.game.C.MAP
        local ring_road_nodes = RingRoad.generatePath(existing_districts, C_MAP.CITY_GRID_WIDTH, C_MAP.CITY_GRID_HEIGHT, self.params)
        
        if #ring_road_nodes > 0 then
            local ring_road_curve = self.game.maps.city:generateSplinePoints(ring_road_nodes, 10)
            
            -- Draw the ring road
            if #ring_road_curve > 1 then
                for i = 1, #ring_road_curve - 1 do
                    self.game.maps.city:drawThickLineColored(grid, ring_road_curve[i].x, ring_road_curve[i].y, 
                                                     ring_road_curve[i+1].x, ring_road_curve[i+1].y, "highway_ring", 3)
                end
            end
        end
    end
    
    self.game.error_service.logInfo("DebugMenu", "Regenerated ring road only")
end

function DebugMenuController:regenerateHighwaysOnly()
    self:applyParametersToModules()
    
    if not self.params.generate_highways then
        self.game.error_service.logInfo("DebugMenu", "Highway generation disabled, skipping")
        return
    end
    
    local grid = self.game.maps.city.grid
    if not grid or #grid == 0 then return end
    
    -- Clear existing highways
    for y = 1, #grid do
        for x = 1, #grid[1] do
            if grid[y][x].type == "highway_ns" or grid[y][x].type == "highway_ew" then
                grid[y][x].type = "grass"
            end
        end
    end
    
    -- Regenerate highways
    local existing_districts = self:findExistingDistricts()
    
    if #existing_districts > 0 then
        local HighwayNS = require("models.generators.highway_ns")
        local HighwayEW = require("models.generators.highway_ew")
        local HighwayMerger = require("models.generators.highway_merger")
        local C_MAP = self.game.C.MAP
        
        local ns_highway_paths = HighwayNS.generatePaths(C_MAP.CITY_GRID_WIDTH, C_MAP.CITY_GRID_HEIGHT, existing_districts, self.params)
        local ew_highway_paths = HighwayEW.generatePaths(C_MAP.CITY_GRID_WIDTH, C_MAP.CITY_GRID_HEIGHT, existing_districts, self.params)
        
        local all_highway_paths = {}
        for _, path in ipairs(ns_highway_paths) do table.insert(all_highway_paths, path) end
        for _, path in ipairs(ew_highway_paths) do table.insert(all_highway_paths, path) end
        
        local merged_highway_paths = HighwayMerger.applyMergingLogic(all_highway_paths, {}, self.params)
        
        -- Draw highways
        local num_ns_highways = self.params.num_ns_highways or 2
        for highway_idx, path_nodes in ipairs(merged_highway_paths) do
            local highway_curve = self.game.maps.city:generateSplinePoints(path_nodes, 10)
            local highway_type = highway_idx <= num_ns_highways and "highway_ns" or "highway_ew"
            
            for i = 1, #highway_curve - 1 do
                self.game.maps.city:drawThickLineColored(grid, highway_curve[i].x, highway_curve[i].y, 
                                                 highway_curve[i+1].x, highway_curve[i+1].y, highway_type, 3)
            end
        end
    end
    
    self.game.error_service.logInfo("DebugMenu", "Regenerated highways only")
end

function DebugMenuController:regenerateConnectionsOnly()
    self:applyParametersToModules()
    
    if not self.params.generate_connections then
        self.game.error_service.logInfo("DebugMenu", "Connection generation disabled, skipping")
        return
    end
    
    local grid = self.game.maps.city.grid
    if not grid or #grid == 0 then return end
    
    -- Clear existing connection roads (keep highways and district roads)
    for y = 1, #grid do
        for x = 1, #grid[1] do
            local tile_type = grid[y][x].type
            if tile_type == "road" and not self:isInDistrictOrDowntown(x, y) then
                grid[y][x].type = "grass"
            end
        end
    end
    
    -- Regenerate connections
    local existing_districts = self:findExistingDistricts()
    local highway_points = self:findExistingHighwayPoints()
    
    if #existing_districts > 0 then
        local ConnectingRoads = require("models.generators.connecting_roads")
        local C_MAP = self.game.C.MAP
        
        local connections = ConnectingRoads.generateConnections(grid, existing_districts, highway_points, 
                                                               C_MAP.CITY_GRID_WIDTH, C_MAP.CITY_GRID_HEIGHT, self.params)
        ConnectingRoads.drawConnections(grid, connections, self.params)
    end
    
    self.game.error_service.logInfo("DebugMenu", "Regenerated connecting roads only")
end

function DebugMenuController:findExistingDistricts()
    -- Analyze the current map to find district boundaries
    -- This is a simplified approach - in a full implementation you'd want to store district data
    local districts = {}
    local grid = self.game.maps.city.grid
    if not grid or #grid == 0 then return districts end
    
    -- Add downtown district
    local downtown_offset = self.game.maps.city.downtown_offset
    local C_MAP = self.game.C.MAP
    if downtown_offset then
        table.insert(districts, {
            x = downtown_offset.x, 
            y = downtown_offset.y,
            w = C_MAP.DOWNTOWN_GRID_WIDTH, 
            h = C_MAP.DOWNTOWN_GRID_HEIGHT
        })
    end
    
    -- For other districts, we'd need more sophisticated analysis
    -- For now, create some placeholder districts
    for i = 1, (self.params.num_districts or 8) do
        local w = love.math.random(40, 80)
        local h = love.math.random(40, 80)
        local x = love.math.random(50, C_MAP.CITY_GRID_WIDTH - w - 50)
        local y = love.math.random(50, C_MAP.CITY_GRID_HEIGHT - h - 50)
        table.insert(districts, {x = x, y = y, w = w, h = h})
    end
    
    return districts
end

function DebugMenuController:findExistingHighwayPoints()
    local points = {}
    local grid = self.game.maps.city.grid
    if not grid or #grid == 0 then return points end
    
    -- Find all highway and ring road tiles
    for y = 1, #grid do
        for x = 1, #grid[1] do
            local tile_type = grid[y][x].type
            if tile_type == "highway_ring" or tile_type == "highway_ns" or tile_type == "highway_ew" then
                table.insert(points, {x = x, y = y})
            end
        end
    end
    
    return points
end

function DebugMenuController:isInDistrictOrDowntown(x, y)
    -- Check if a point is within downtown area
    local downtown_offset = self.game.maps.city.downtown_offset
    local C_MAP = self.game.C.MAP
    
    if downtown_offset then
        if x >= downtown_offset.x and x < downtown_offset.x + C_MAP.DOWNTOWN_GRID_WIDTH and
           y >= downtown_offset.y and y < downtown_offset.y + C_MAP.DOWNTOWN_GRID_HEIGHT then
            return true
        end
    end
    
    -- For other districts, we'd need to check against stored district boundaries
    -- For now, return false
    return false
end

function DebugMenuController:testPathfinding()
    local grid = self.game.maps.city.grid
    if grid and #grid > 0 then
        local plots = self.game.maps.city.building_plots
        if #plots >= 2 then
            local start_plot = plots[love.math.random(1, #plots)]
            local end_plot = plots[love.math.random(1, #plots)]
            local start_node = self.game.maps.city:findNearestRoadTile(start_plot)
            local end_node = self.game.maps.city:findNearestRoadTile(end_plot)
            
            if start_node and end_node then
                -- Use bike pathfinding costs for testing
                local costs = {
                    road = 5,
                    downtown_road = 8,
                    arterial = 3,
                    highway = 500,
                    highway_ring = 500,
                    highway_ns = 500,
                    highway_ew = 500,
                    grass = 1000,
                    plot = 1000
                }
                
                local path = self.game.pathfinder.findPath(grid, start_node, end_node, costs, self.game.maps.city)
                if path then
                    self.game.error_service.logInfo("DebugMenu", 
                        string.format("✓ Test path found: %d nodes from (%d,%d) to (%d,%d)", 
                                    #path, start_node.x, start_node.y, end_node.x, end_node.y))
                    
                    -- Optionally highlight the path temporarily
                    self:highlightTestPath(path)
                else
                    self.game.error_service.logWarning("DebugMenu", "✗ Test pathfinding failed - no path found")
                end
            else
                self.game.error_service.logWarning("DebugMenu", "✗ Test pathfinding failed - couldn't find road nodes")
            end
        else
            self.game.error_service.logWarning("DebugMenu", "✗ Test pathfinding failed - need at least 2 building plots")
        end
    else
        self.game.error_service.logWarning("DebugMenu", "✗ Test pathfinding failed - no map grid available")
    end
end

function DebugMenuController:highlightTestPath(path)
    -- Store the path for temporary visualization
    self.test_path = path
    self.test_path_timer = 5.0 -- Show for 5 seconds
end

function DebugMenuController:updateTestPath(dt)
    if self.test_path_timer then
        self.test_path_timer = self.test_path_timer - dt
        if self.test_path_timer <= 0 then
            self.test_path = nil
            self.test_path_timer = nil
        end
    end
end

function DebugMenuController:drawTestPath(game)
    if self.test_path and #self.test_path > 1 then
        love.graphics.setColor(1, 0, 1, 0.8) -- Magenta
        love.graphics.setLineWidth(3)
        
        local pixel_path = {}
        for _, node in ipairs(self.test_path) do
            local px, py = game.maps.city:getPixelCoords(node.x, node.y)
            table.insert(pixel_path, px)
            table.insert(pixel_path, py)
        end
        
        if #pixel_path >= 4 then
            love.graphics.line(pixel_path)
        end
        
        love.graphics.setLineWidth(1)
        love.graphics.setColor(1, 1, 1, 1)
    end
end

function DebugMenuController:resetParameters()
    self.params = {}
    for k, v in pairs(self.game.C.MAP_GEN) do
        self.params[string.lower(k)] = v
    end
end

return DebugMenuController