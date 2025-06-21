-- models/vehicles/Vehicle.lua
local Vehicle = {}
Vehicle.__index = Vehicle

function Vehicle:drawIconAt(game, px, py, icon)
    love.graphics.setFont(game.fonts.emoji)
    love.graphics.setColor(0, 0, 0) -- Black

    love.graphics.push()
    love.graphics.translate(px, py)
    love.graphics.scale(1 / game.camera.scale, 1 / game.camera.scale)
    love.graphics.print(icon, -14, -14) -- Center the emoji
    love.graphics.pop()

    love.graphics.setFont(game.fonts.ui) -- Switch back to default UI font
end

function Vehicle:new(id, depot_plot, game, vehicleType, properties)
    local States = require("models.vehicles.vehicle_states")
    
    local instance = setmetatable({}, Vehicle)
    
    instance.id = id
    instance.type = vehicleType or "vehicle"
    instance.properties = properties or {}
    instance.depot_plot = depot_plot
    instance.px, instance.py = game.maps.city:getPixelCoords(depot_plot.x, depot_plot.y)
    
    instance.trip_queue = {}
    instance.cargo = {}
    instance.path = {}
    
    instance.grid_anchor = {x = depot_plot.x, y = depot_plot.y}
    
    instance.state = nil
    instance:changeState(States.Idle, game)

    instance.visible = true

    return instance
end

function Vehicle:recalculatePixelPosition(game)
    -- This function now ONLY ever calculates position based on the city map,
    -- ensuring self.px/py are always in a consistent coordinate system.
    local city_map = game.maps.city
    if city_map then
        self.px, self.py = city_map:getPixelCoords(self.grid_anchor.x, self.grid_anchor.y)
    end
end

function Vehicle:_getRegionDrawPosition(game)
    local region_map = game.maps.region
    local city_map = game.maps.city

    -- Use the stored main city offset from when the region was generated
    local city_start_in_region_x = region_map.main_city_offset.x
    local city_start_in_region_y = region_map.main_city_offset.y

    -- Find which city grid tile the vehicle is on
    local city_grid_x, city_grid_y = city_map:pixelToGrid(self.px, self.py)
    
    -- Transform the vehicle's city grid position to region grid position
    local region_grid_x = city_start_in_region_x + city_grid_x
    local region_grid_y = city_start_in_region_y + city_grid_y
    
    -- Convert region grid coordinates to region-world pixel coordinates for drawing
    return region_map:getPixelCoords(region_grid_x, region_grid_y)
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
            if #self.trip_queue > 0 then
                self:changeState(States.GoToPickup, game)
            else
                self:changeState(States.Idle, game)
            end
        elseif state_name == "Picking Up" or state_name == "Dropping Off" or state_name == "Deciding" then
            -- These states transition automatically in their enter methods
        elseif state_name == "Idle" then
            if #self.trip_queue > 0 then
                self:changeState(States.GoToPickup, game)
            else
                break
            end
        else
            break
        end
        
        iterations = iterations + 1
        if self.state.name == old_state then
            break
        end
        if self.state.name == "To Pickup" or 
           self.state.name == "To Dropoff" or 
           self.state.name == "Returning" or
           self.state.name == "Traveling (Region)" then
            break
        end
    end
    
    if iterations >= max_iterations then
        print(string.format("ERROR: Vehicle %d hit max iterations in state resolution!", self.id))
    end
end

function Vehicle:update(dt, game)
    local current_scale = game.state.current_map_scale
    local C_MAP = game.C.MAP
    
    if self.state and self.state.name == "Traveling (Region)" then
        self.state:update(dt, self, game)
        return
    end

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
    local CoordinateSystem = require("utils.CoordinateSystem")
    local coord_system = CoordinateSystem.new(game.C)
    local screen_x, screen_y = coord_system:worldToScreen(self.px, self.py, game.camera)

    local line_h = 15
    local state_name = self.state and self.state.name or "N/A"
    local path_count = self.path and #self.path or 0
    local target_text = "None"
    if self.path and self.path[1] then
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
    
    local menu_x = screen_x + 20
    local menu_y = screen_y - 20
    
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", menu_x - 5, menu_y - 5, 200, #debug_lines * line_h + 10)
    
    local old_font = love.graphics.getFont()
    love.graphics.setFont(game.fonts.ui_small)
    
    love.graphics.setColor(0, 1, 0)
    for i, line in ipairs(debug_lines) do
        love.graphics.print(line, menu_x, menu_y + (i-1) * line_h)
    end
    
    love.graphics.setFont(old_font)
    love.graphics.setColor(1, 1, 1)
end

function Vehicle:draw(game)
    if not self:shouldDrawAtCurrentScale(game) then return end
    if not self.visible then return end

    local draw_px, draw_py
    local current_scale = game.state.current_map_scale

    if current_scale == game.C.MAP.SCALES.REGION then
        -- On the region map, transform city-world coordinates to region-world coordinates for drawing.
        draw_px, draw_py = self:_getRegionDrawPosition(game)
    else
        -- On city/downtown maps, the vehicle's internal px/py are already correct.
        draw_px, draw_py = self.px, self.py
    end

    -- Draw selection circle
    if self == game.entities.selected_vehicle then
        love.graphics.setColor(1, 1, 0)
        local radius = 16 / game.camera.scale
        love.graphics.setLineWidth(2 / game.camera.scale)
        love.graphics.circle("line", draw_px, draw_py, radius)
        love.graphics.setLineWidth(1)
    end
    
    -- Draw the vehicle's icon at the correct position
    self:drawIconAt(game, draw_px, draw_py, self.type == "bike" and "🚲" or "🚚")
end

return Vehicle