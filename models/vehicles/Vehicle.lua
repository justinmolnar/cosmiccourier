-- models/vehicles/Vehicle.lua
local Vehicle = {}
Vehicle.__index = Vehicle

function Vehicle:new(id, depot_plot, game, vehicleType, properties, operational_map_key)
    local States = require("models.vehicles.vehicle_states")
    
    local instance = setmetatable({}, Vehicle)
    
    instance.id = id
    instance.type = vehicleType or "vehicle"
    instance.properties = properties or {}
    instance.depot_plot = depot_plot
    
    -- Vehicle now knows its operational map.
    instance.operational_map_key = operational_map_key or "city"
    local home_map = game.maps[instance.operational_map_key]

    instance.px, instance.py = home_map:getPixelCoords(depot_plot.x, depot_plot.y)
    
    instance.trip_queue = {}
    instance.cargo = {}
    instance.path = {}
    
    instance.grid_anchor = {x = depot_plot.x, y = depot_plot.y}
    
    instance.state = nil
    instance:changeState(States.Idle, game)

    instance.visible = true

    return instance
end

function Vehicle:getMovementCostFor(tileType)
    -- Default behavior: return a high cost for unknown tiles
    return self.properties.pathfinding_costs[tileType] or 9999
end

function Vehicle:getIcon()
    -- Default behavior: return a generic icon
    return "❓"
end

function Vehicle:canTravelTo(destination)
    -- Default behavior: all vehicles can travel anywhere.
    -- This could be overridden later for vehicles with range limits, etc.
    return true
end

function Vehicle:recalculatePixelPosition(game)
    -- This function now uses the vehicle's operational_map_key to calculate its position.
    local home_map = game.maps[self.operational_map_key]
    if home_map then
        self.px, self.py = home_map:getPixelCoords(self.grid_anchor.x, self.grid_anchor.y)
    end
end

function Vehicle:_getRegionDrawPosition(game)
    local region_map = game.maps.region
    local tile_size = region_map.C.MAP.TILE_SIZE

    -- Get the region grid coordinates where the city map begins.
    local city_start_in_region_x = region_map.main_city_offset.x
    local city_start_in_region_y = region_map.main_city_offset.y
    
    -- Calculate the pixel coordinate of the top-left corner of the city's area within the region map.
    local city_top_left_px_in_region = (city_start_in_region_x - 1) * tile_size
    local city_top_left_py_in_region = (city_start_in_region_y - 1) * tile_size

    -- The vehicle's self.px and self.py are its pixel coordinates relative to the city map's origin.
    -- We add them to the city's top-left pixel position within the region to get the final, smooth draw position.
    local final_draw_px = city_top_left_px_in_region + self.px
    local final_draw_py = city_top_left_py_in_region + self.py
    
    return final_draw_px, final_draw_py
end


function Vehicle:shouldDrawAtCurrentScale(game)
    local current_scale = game.state.current_map_scale
    local C_MAP = game.C.MAP
    
    if self.type == "bike" then
        -- Bikes only show at downtown and city scales
        return current_scale == C_MAP.SCALES.DOWNTOWN or current_scale == C_MAP.SCALES.CITY
    elseif self.type == "truck" then
        -- Trucks show at all scales
        return true
    end
    
    return true
end

function Vehicle:changeState(newState, game)
    if self.state and self.state.exit then
        self.state:exit(self, game)
    end
    self.state = newState
    if self.state and self.state.enter then
        self.state:enter(self, game)
    end
end

function Vehicle:assignTrip(trip, game)
    if not self:isAvailable(game) then return end

    print("Queuing trip for " .. self.type .. " " .. self.id)
    table.insert(self.trip_queue, trip)
end

function Vehicle:_resolveOffScreenState(game)
    -- This function will continue to process instantaneous state changes
    -- until the vehicle is in a state that involves travel (and has an ETA).
    local States = require("models.vehicles.vehicle_states")
    local max_iterations = 10  -- Prevent infinite loops
    local iterations = 0
    
    while iterations < max_iterations do
        local state_name = self.state.name
        local old_state = state_name
        
        print(string.format("Vehicle %d resolving off-screen state: %s (iteration %d)", self.id, state_name, iterations + 1))

        if state_name == "To Pickup" then
            self:changeState(States.DoPickup, game)
            
        elseif state_name == "To Dropoff" then
            self:changeState(States.DoDropoff, game)
            
        elseif state_name == "Returning" then
            -- Check if we got new work while returning - if so, go to pickup instead
            if #self.trip_queue > 0 then
                print(string.format("Vehicle %d got new work while returning, switching to pickup", self.id))
                self:changeState(States.GoToPickup, game)
            else
                -- No new work, arrived back at depot, go idle
                self:changeState(States.Idle, game)
            end
            
        elseif state_name == "Picking Up" then
            -- The DoPickup state's enter method handles the logic and transitions automatically
            -- No need to call enter again, it was already called by changeState
            print(string.format("Vehicle %d completed pickup, should be in new state: %s", self.id, self.state.name))
            
        elseif state_name == "Dropping Off" then
            -- The DoDropoff state's enter method handles the logic and transitions automatically
            -- No need to call enter again, it was already called by changeState
            print(string.format("Vehicle %d completed dropoff, should be in new state: %s", self.id, self.state.name))
            
        elseif state_name == "Deciding" then
            -- The DecideNextAction state's enter method handles the logic and transitions automatically
            print(string.format("Vehicle %d completed decision, should be in new state: %s", self.id, self.state.name))
            
        elseif state_name == "Idle" then
            -- Check if we have new work to do
            if #self.trip_queue > 0 then
                self:changeState(States.GoToPickup, game)
            else
                -- Truly idle, no more state changes needed
                print(string.format("Vehicle %d is truly idle with no work", self.id))
                break
            end
            
        else
            -- Vehicle is in a travel state or unknown state, stop resolving
            print(string.format("Vehicle %d in travel/final state: %s", self.id, state_name))
            break
        end
        
        iterations = iterations + 1
        
        -- If state didn't change, we're stuck - break out
        if self.state.name == old_state then
            print(string.format("WARNING: Vehicle %d state didn't change from %s, breaking loop", self.id, old_state))
            break
        end
        
        -- If we're now in a travel state, we're done.
        -- Updated this check to include the new highway states.
        if self.state.name == "To Pickup" or 
           self.state.name == "To Dropoff" or 
           self.state.name == "Returning" or
           self.state.name == "To Highway" or
           self.state.name == "On Highway" or
           self.state.name == "Exiting Highway" then
            print(string.format("Vehicle %d reached travel state: %s", self.id, self.state.name))
            break
        end
    end
    
    if iterations >= max_iterations then
        print(string.format("ERROR: Vehicle %d hit max iterations in state resolution!", self.id))
    end
end

function Vehicle:update(dt, game)
    -- This special check is now obsolete. The logic below handles all states correctly.
    --[[
    if self.state and self.state.name == "Traveling (Region)" then
        self.state:update(dt, self, game)
        return
    end
    ]]

    -- Determine if this vehicle should run in detailed or abstracted mode
    local should_abstract = self:shouldUseAbstractedSimulation(game)
    
    if should_abstract then
        self:updateAbstracted(dt, game)
    else
        self:updateDetailed(dt, game)
    end
end

function Vehicle:updateDetailed(dt, game)
    if self.state and self.state.update then
        self.state:update(dt, self, game)
    end
end

function Vehicle:updateAbstracted(dt, game)
    if not self.current_path_eta or self.current_path_eta <= 0 then
        if not self.current_path_eta then
            if self.state and (self.state.name == "Picking Up" or 
                              self.state.name == "Dropping Off" or 
                              self.state.name == "Deciding") then
                self:_resolveOffScreenState(game)
                if self.path and #self.path > 0 then
                    local PathfindingService = require("services.PathfindingService")
                    self.current_path_eta = PathfindingService.estimatePathTravelTime(self.path, self, game, game.maps.city)
                end
            elseif self.state and self.state.name == "Idle" and #self.trip_queue > 0 then
                local States = require("models.vehicles.vehicle_states")
                self:changeState(States.GoToPickup, game)
                if self.path and #self.path > 0 then
                    local PathfindingService = require("services.PathfindingService")
                    self.current_path_eta = PathfindingService.estimatePathTravelTime(self.path, self, game, game.maps.city)
                end
            end
        end
        return
    end

    if self.current_path_eta and self.current_path_eta > 0 then
        if self.state and self.state.name == "Returning" and #self.trip_queue > 0 then
            local States = require("models.vehicles.vehicle_states")
            self:changeState(States.GoToPickup, game)
            if self.path and #self.path > 0 then
                local PathfindingService = require("services.PathfindingService")
                self.current_path_eta = PathfindingService.estimatePathTravelTime(self.path, self, game, game.maps.city)
            end
            return
        end
    end

    self.current_path_eta = self.current_path_eta - dt

    if self.current_path_eta <= 0 then
        if self.path and #self.path > 0 then
            local final_node = self.path[#self.path]
            self.grid_anchor = {x = final_node.x, y = final_node.y}
            self:recalculatePixelPosition(game)
            self.path = {}
        end

        self:_resolveOffScreenState(game)
        
        if self.path and #self.path > 0 then
            local PathfindingService = require("services.PathfindingService")
            self.current_path_eta = PathfindingService.estimatePathTravelTime(self.path, self, game, game.maps.city)
        else
            self.current_path_eta = nil
        end
    end
end

function Vehicle:isAvailable(game)
    local total_load = #self.trip_queue + #self.cargo
    return total_load < game.state.upgrades.vehicle_capacity
end

function Vehicle:shouldUseAbstractedSimulation(game)
    local current_scale = game.state.current_map_scale
    local C_MAP = game.C.MAP
    
    if self.type == "bike" and current_scale == C_MAP.SCALES.REGION then
        return true
    end
    
    return false
end

function Vehicle:drawDebug(game)
    -- This function is called from within the camera's transformed view.
    -- All coordinates are relative to the vehicle's world pixel position (self.px, self.py).
    local screen_x, screen_y = self.px, self.py

    -- Draw the vehicle's current path
    if self.path and #self.path > 0 then
        love.graphics.setColor(0, 0, 1, 0.7) -- Blue for path
        love.graphics.setLineWidth(2 / game.camera.scale)
        local pixel_path = {}
        table.insert(pixel_path, self.px)
        table.insert(pixel_path, self.py)
        for _, node in ipairs(self.path) do
            local px, py = game.maps[self.operational_map_key]:getPixelCoords(node.x, node.y)
            table.insert(pixel_path, px)
            table.insert(pixel_path, py)
        end
        love.graphics.line(pixel_path)
        love.graphics.setLineWidth(1)
    end

    -- THE FIX: All drawing operations for the debug box must be scaled by the camera zoom.
    local scale = 1 / game.camera.scale
    local line_h = 15 * scale
    local menu_x = screen_x + (20 * scale)
    local menu_y = screen_y - (20 * scale)

    local state_name = self.state and self.state.name or "N/A"
    local path_count = self.path and #self.path or 0
    local target_text = "None"
    if self.path and #self.path > 0 then
        target_text = string.format("(%d, %d)", self.path[1].x, self.path[1].y)
    end
    local debug_lines = {
        string.format("ID: %d | Type: %s", self.id, self.type),
        string.format("State: %s", state_name),
        string.format("Path Nodes: %d", path_count),
        string.format("Target: %s", target_text),
        string.format("Cargo: %d | Queue: %d", #self.cargo, #self.trip_queue),
        string.format("Pos: %d, %d", math.floor(self.px), math.floor(self.py))
    }
    
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", menu_x - (5*scale), menu_y - (5*scale), (200*scale), #debug_lines * line_h + (10*scale))
    
    local old_font = love.graphics.getFont()
    love.graphics.setFont(game.fonts.ui_small)
    love.graphics.setColor(0, 1, 0)

    for i, line in ipairs(debug_lines) do
        love.graphics.push()
        love.graphics.translate(menu_x, menu_y + (i-1) * line_h)
        love.graphics.scale(scale, scale)
        love.graphics.print(line, 0, 0)
        love.graphics.pop()
    end
    
    love.graphics.setFont(old_font)
    love.graphics.setColor(1, 1, 1)
end

function Vehicle:draw(game)
    if not self:shouldDrawAtCurrentScale(game) then return end
    if not self.visible then return end

    local draw_px, draw_py
    local active_map_key = game.active_map_key
    local DrawingUtils = require("utils.DrawingUtils")

    if self.operational_map_key == active_map_key then
        draw_px, draw_py = self.px, self.py
    else
        if self.operational_map_key == "city" and active_map_key == "region" then
            draw_px, draw_py = self:_getRegionDrawPosition(game)
        else
            draw_px, draw_py = self.px, self.py
        end
    end

    if self == game.entities.selected_vehicle then
        love.graphics.setColor(1, 1, 0, 0.8)
        local radius = 16 / game.camera.scale
        love.graphics.setLineWidth(2 / game.camera.scale)
        love.graphics.circle("line", draw_px, draw_py, radius)
        love.graphics.setLineWidth(1)
    end
    
    -- Use the new utility function
    DrawingUtils.drawWorldIcon(game, self:getIcon(), draw_px, draw_py)
end

return Vehicle