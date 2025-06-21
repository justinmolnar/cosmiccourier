-- models/vehicles/Vehicle.lua
local Vehicle = {}
Vehicle.__index = Vehicle

function Vehicle:drawIcon(game, icon)
    love.graphics.setFont(game.fonts.emoji)
    love.graphics.setColor(0, 0, 0) -- Black

    love.graphics.push()
    love.graphics.translate(self.px, self.py)
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

    -- ADD THIS LINE: All vehicles start as visible
    instance.visible = true

    return instance
end

function Vehicle:recalculatePixelPosition(game)
    local current_scale = game.state.current_map_scale
    local active_map = game.maps[game.active_map_key]
    
    print(string.format("DEBUG: Vehicle %d recalculatePixelPosition called - scale: %d, active_map_key: %s", 
          self.id, current_scale, game.active_map_key))
    
    if current_scale == game.C.MAP.SCALES.REGION then
        print(string.format("DEBUG: Vehicle %d using region position calculation", self.id))
        -- At region scale, we need to transform coordinates from city space to region space
        self:_calculateRegionPosition(game)
    else
        print(string.format("DEBUG: Vehicle %d using normal position calculation", self.id))
        -- At city/downtown scale, use the active map directly
        if active_map then
            self.px, self.py = active_map:getPixelCoords(self.grid_anchor.x, self.grid_anchor.y)
            print(string.format("DEBUG: Vehicle %d normal pixels: (%.1f, %.1f)", self.id, self.px, self.py))
        end
    end
end

function Vehicle:_calculateRegionPosition(game)
    local C_MAP = game.C.MAP
    local region_map = game.maps.region
    
    -- Get the vehicle's grid position in city coordinates (relative to city map 0,0)
    local city_grid_x = self.grid_anchor.x
    local city_grid_y = self.grid_anchor.y
    
    -- Use the stored main city offset from when the region was generated
    local city_start_in_region_x = region_map.main_city_offset.x
    local city_start_in_region_y = region_map.main_city_offset.y
    
    -- Transform the vehicle's city grid position to region grid position
    local region_grid_x = city_start_in_region_x + city_grid_x
    local region_grid_y = city_start_in_region_y + city_grid_y
    
    -- Convert region grid coordinates to pixel coordinates
    self.px = (region_grid_x - 0.5) * C_MAP.TILE_SIZE
    self.py = (region_grid_y - 0.5) * C_MAP.TILE_SIZE
    
    -- DEBUG OUTPUT
    print(string.format("DEBUG: Vehicle %d DYNAMIC position transformation:", self.id))
    print(string.format("  City grid (relative to city 0,0): (%d, %d)", city_grid_x, city_grid_y))
    print(string.format("  City starts at region grid: (%.1f, %.1f)", city_start_in_region_x, city_start_in_region_y))
    print(string.format("  Final region grid: (%.1f, %.1f)", region_grid_x, region_grid_y))
    print(string.format("  Final pixels: (%.1f, %.1f)", self.px, self.py))
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
    
    -- Default: show at all scales
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
            -- Arrived at pickup location, start picking up
            self:changeState(States.DoPickup, game)
            
        elseif state_name == "To Dropoff" then
            -- Arrived at dropoff location, start dropping off
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
        
        -- If we're now in a travel state, we're done
        if self.state.name == "To Pickup" or 
           self.state.name == "To Dropoff" or 
           self.state.name == "Returning" or
           self.state.name == "Traveling (Region)" then
            print(string.format("Vehicle %d reached travel state: %s", self.id, self.state.name))
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
    
    -- If the vehicle is on a special long-distance trip, let its state handle it.
    if self.state and self.state.name == "Traveling (Region)" then
        self.state:update(dt, self, game)
        return
    end

    -- Determine if this vehicle should run in detailed or abstracted mode
    local should_abstract = self:shouldUseAbstractedSimulation(game)
    
    if should_abstract then
        self:updateAbstracted(dt, game)
    else
        self:updateDetailed(dt, game)
    end
end

function Vehicle:updateDetailed(dt, game)
    -- Run the full, detailed simulation
    if self.state and self.state.update then
        self.state:update(dt, self, game)
    end
end

function Vehicle:updateAbstracted(dt, game)
    -- Simplified simulation for abstracted vehicles
    
    -- Handle vehicles that don't have a path (idle, or in instantaneous states)
    if not self.current_path_eta or self.current_path_eta <= 0 then
        if not self.current_path_eta then
            -- Vehicle is in an instantaneous state - resolve it immediately
            if self.state and (self.state.name == "Picking Up" or 
                              self.state.name == "Dropping Off" or 
                              self.state.name == "Deciding") then
                self:_resolveOffScreenState(game)
                -- After resolving, set up the new ETA if there's a path
                if self.path and #self.path > 0 then
                    local PathfindingService = require("services.PathfindingService")
                    self.current_path_eta = PathfindingService.estimatePathTravelTime(self.path, self, game, game.maps.city)
                end
            elseif self.state and self.state.name == "Idle" and #self.trip_queue > 0 then
                -- Trigger the state change to start working
                local States = require("models.vehicles.vehicle_states")
                self:changeState(States.GoToPickup, game)
                -- Set up ETA for the new journey
                if self.path and #self.path > 0 then
                    local PathfindingService = require("services.PathfindingService")
                    self.current_path_eta = PathfindingService.estimatePathTravelTime(self.path, self, game, game.maps.city)
                end
            end
        end
        return
    end

    -- Handle vehicles that are traveling but get new assignments
    if self.current_path_eta and self.current_path_eta > 0 then
        if self.state and self.state.name == "Returning" and #self.trip_queue > 0 then
            print(string.format("Vehicle %d canceling return journey to take new assignment", self.id))
            -- Cancel the return journey and go directly to pickup
            local States = require("models.vehicles.vehicle_states")
            self:changeState(States.GoToPickup, game)
            -- Set up ETA for the new pickup journey
            if self.path and #self.path > 0 then
                local PathfindingService = require("services.PathfindingService")
                self.current_path_eta = PathfindingService.estimatePathTravelTime(self.path, self, game, game.maps.city)
            end
            return
        end
    end

    -- Continue with existing travel simulation
    self.current_path_eta = self.current_path_eta - dt

    if self.current_path_eta <= 0 then
        -- The abstracted journey is complete. Teleport to the destination.
        if self.path and #self.path > 0 then
            local final_node = self.path[#self.path]
            self.grid_anchor = {x = final_node.x, y = final_node.y}
            self:recalculatePixelPosition(game)
            self.path = {}
            print(string.format("Vehicle %d completed abstracted journey, now at (%d,%d)", 
                  self.id, self.grid_anchor.x, self.grid_anchor.y))
        end

        -- Resolve all instantaneous state changes
        self:_resolveOffScreenState(game)
        
        -- After all actions are resolved, get the ETA for the new path.
        if self.path and #self.path > 0 then
            local PathfindingService = require("services.PathfindingService")
            self.current_path_eta = PathfindingService.estimatePathTravelTime(self.path, self, game, game.maps.city)
        else
            self.current_path_eta = nil
        end
        
        print(string.format("Vehicle %d finished abstracted action chain. New state: %s. New ETA: %.2f", 
              self.id, self.state.name, self.current_path_eta or 0))
    end
end



function Vehicle:isAvailable(game)
    local total_load = #self.trip_queue + #self.cargo
    return total_load < game.state.upgrades.vehicle_capacity
end

function Vehicle:shouldUseAbstractedSimulation(game)
    local current_scale = game.state.current_map_scale
    local C_MAP = game.C.MAP
    
    -- Bikes are abstracted when player is viewing region scale
    if self.type == "bike" and current_scale == C_MAP.SCALES.REGION then
        return true
    end
    
    -- Trucks always run detailed simulation (for now)
    -- In the future, you might want to abstract trucks at planetary scale
    
    return false
end

function Vehicle:drawDebug(game)
    -- MODIFIED: This function now draws in screen-space to avoid scaling issues.
    local CoordinateSystem = require("utils.CoordinateSystem")
    local coord_system = CoordinateSystem.new(game.C)

    -- 1. Convert the vehicle's world position to screen coordinates.
    local screen_x, screen_y = coord_system:worldToScreen(self.px, self.py, game.camera)

    -- 2. Define the content of the debug menu.
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
    
    -- 3. Draw the menu directly using screen coordinates.
    -- No push, pop, translate, or scale needed for the menu itself.
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
    -- Check if this vehicle should be drawn at the current scale
    if not self:shouldDrawAtCurrentScale(game) then
        return
    end
    
    local current_scale = game.state.current_map_scale
    
    -- Handle abstracted drawing for bikes at region level
    if self.type == "bike" and current_scale == game.C.MAP.SCALES.REGION then
        -- Bikes are abstracted at region level - don't draw them
        return
    end
    
    -- Continue with normal drawing for visible vehicles
    if not self.visible then
        return
    end
    
    -- DEBUG: Print camera and vehicle info
    if current_scale == game.C.MAP.SCALES.REGION then
        print(string.format("DEBUG: Drawing vehicle %d at scale %d", self.id, current_scale))
        print(string.format("  Vehicle pixels: (%.1f, %.1f)", self.px, self.py))
        print(string.format("  Camera: x=%.1f, y=%.1f, scale=%.3f", game.camera.x, game.camera.y, game.camera.scale))
        print(string.format("  Active map key: %s", game.active_map_key))
    end

    -- Draw selection circle
    if self == game.entities.selected_vehicle then
        love.graphics.setColor(1, 1, 0)
        local radius = 16 / game.camera.scale
        love.graphics.setLineWidth(2 / game.camera.scale)
        love.graphics.circle("line", self.px, self.py, radius)
        love.graphics.setLineWidth(1)
    end
    
    -- Draw the vehicle's icon
    self:drawIcon(game, self.type == "bike" and "🚲" or "🚚")
end

return Vehicle