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
    -- MODIFIED: Get coordinates from the active map
    local active_map = game.maps[game.active_map_key]
    if active_map then
        self.px, self.py = active_map:getPixelCoords(self.grid_anchor.x, self.grid_anchor.y)
    end
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
    -- If the vehicle is on a special long-distance trip, let its state handle it.
    if self.state and self.state.name == "Traveling (Region)" then
        self.state:update(dt, self, game)
        return
    end

    -- If the player is watching the city, run the full, detailed simulation.
    if game.active_map_key == "city" then
        if self.state and self.state.update then
            self.state:update(dt, self, game)
        end
        return
    end

    -- ABSTRACTED MODE: We reach here when player is zoomed out
    
    -- FIX: For now, trucks should always run in detailed mode regardless of zoom level
    -- This is temporary until we implement proper truck abstraction
    if self.type == "truck" then
        print(string.format("DEBUG: Truck %d running in detailed mode despite zoom level %d", self.id, game.state.current_map_scale))
        if self.state and self.state.update then
            self.state:update(dt, self, game)
        end
        return
    end
    
    -- ABSTRACTED MODE continues for bikes only...
    
    -- FIX 1: Handle vehicles that don't have a path (idle, or in instantaneous states)
    if not self.current_path_eta or self.current_path_eta <= 0 then
        -- If vehicle has no active journey, check if it needs to start one
        if not self.current_path_eta then
            -- Vehicle is in an instantaneous state - resolve it immediately
            if self.state and (self.state.name == "Picking Up" or 
                              self.state.name == "Dropping Off" or 
                              self.state.name == "Deciding") then
                self:_resolveOffScreenState(game)
                -- After resolving, set up the new ETA if there's a path
                if self.path and #self.path > 0 then
                    self.current_path_eta = require("services.PathfindingService").estimatePathTravelTime(self.path, self, game, game.maps.city)
                end
            -- FIX 2: Handle idle vehicles that get new assignments
            elseif self.state and self.state.name == "Idle" and #self.trip_queue > 0 then
                -- Trigger the state change to start working
                self:changeState(require("models.vehicles.vehicle_states").GoToPickup, game)
                -- Set up ETA for the new journey
                if self.path and #self.path > 0 then
                    self.current_path_eta = require("services.PathfindingService").estimatePathTravelTime(self.path, self, game, game.maps.city)
                end
            end
        end
        return
    end

    -- FIX 2.5: Handle vehicles that are traveling but get new assignments
    -- This covers the case where a vehicle is returning to depot but gets new work
    if self.current_path_eta and self.current_path_eta > 0 then
        if self.state and self.state.name == "Returning" and #self.trip_queue > 0 then
            print(string.format("Vehicle %d canceling return journey to take new assignment", self.id))
            -- Cancel the return journey and go directly to pickup
            self:changeState(require("models.vehicles.vehicle_states").GoToPickup, game)
            -- Set up ETA for the new pickup journey
            if self.path and #self.path > 0 then
                self.current_path_eta = require("services.PathfindingService").estimatePathTravelTime(self.path, self, game, game.maps.city)
            end
            return -- Exit early since we've started a new journey
        end
    end

    -- FIX 3: Continue with existing travel simulation
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

        -- FIX 4: Resolve all instantaneous state changes
        self:_resolveOffScreenState(game)
        
        -- After all actions are resolved, get the ETA for the new path.
        if self.path and #self.path > 0 then
            self.current_path_eta = require("services.PathfindingService").estimatePathTravelTime(self.path, self, game, game.maps.city)
        else
            self.current_path_eta = nil -- FIX 5: Clear ETA when no path
        end
        
        print(string.format("Vehicle %d finished abstracted action chain. New state: %s. New ETA: %.2f", 
              self.id, self.state.name, self.current_path_eta or 0))
    end
end

function Vehicle:isAvailable(game)
    local total_load = #self.trip_queue + #self.cargo
    return total_load < game.state.upgrades.vehicle_capacity
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
    local should_draw = false
    local current_scale = game.state.current_map_scale
    
    -- FIX: Trucks should be drawn at all zoom levels since they're not abstracted
    if self.type == "truck" then
        should_draw = true
        print(string.format("DEBUG: Drawing truck %d at zoom level %d", self.id, current_scale))
    elseif current_scale == game.C.MAP.SCALES.DOWNTOWN or current_scale == game.C.MAP.SCALES.CITY then
        -- Bikes and other vehicles only draw at downtown and city scales
        should_draw = true
    end

    if not should_draw then
        return
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