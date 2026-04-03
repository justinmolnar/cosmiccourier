-- models/vehicles/Vehicle.lua
local Vehicle = {}
Vehicle.__index = Vehicle

function Vehicle:new(id, depot_plot, game, vehicleType, properties, operational_map_key)
    local States = require("models.vehicles.vehicle_states")
    
    local instance = setmetatable({}, Vehicle)
    
    instance.id = id
    instance.type = vehicleType or "vehicle"
    instance.properties = properties or {}
    instance.icon = (properties or {}).icon or "❓"
    instance.depot_plot = depot_plot
    
    instance.trip_queue = {}
    instance.cargo = {}
    instance.path = {}
    instance.pathfinding_bounds = nil  -- nil = no restriction; set for bounded vehicles (future)

    -- Speed modifier accumulates upgrade multipliers; base speed stays constant.
    local vt = (vehicleType or ""):upper()
    if vt == "BIKE" then
        instance.speed_modifier = game.state.upgrades.bike_speed or 1.0
    elseif vt == "TRUCK" then
        instance.speed_modifier = game.state.upgrades.truck_speed or 1.0
    else
        instance.speed_modifier = 1.0
    end

    local umap = game.maps and game.maps.unified
    if umap then
        -- Unified map: depot_plot is already in unified sub-cell coords
        instance.operational_map_key = "unified"
        local uts = umap.tile_pixel_size
        instance.grid_anchor = {x = depot_plot.x, y = depot_plot.y}
        instance.px = (depot_plot.x - 0.5) * uts
        instance.py = (depot_plot.y - 0.5) * uts
    else
        -- Fallback: initial game state before world gen (unified map not yet built).
        -- Use sandbox (1-indexed sub-cell) coords; PathfindingService always runs in
        -- sandbox mode via the proxy map, so road-node coords are never needed.
        instance.operational_map_key = operational_map_key or "city"
        local home_map = game.maps[instance.operational_map_key]
        instance.grid_anchor = {x = depot_plot.x, y = depot_plot.y}
        instance.px, instance.py = home_map:getPixelCoords(depot_plot.x, depot_plot.y)
    end
    
    instance.state = nil
    instance:changeState(States.Idle, game)

    instance.visible = true

    return instance
end

function Vehicle:getSpeed()
    return self.properties.speed * self.speed_modifier
end

function Vehicle:getMovementCostFor(tileType)
    -- Default behavior: return a high cost for unknown tiles
    return self.properties.pathfinding_costs[tileType] or 9999
end

function Vehicle:getIcon()
    return self.icon or "❓"
end

function Vehicle:canTravelTo(destination)
    -- Default behavior: all vehicles can travel anywhere.
    -- This could be overridden later for vehicles with range limits, etc.
    return true
end

function Vehicle:recalculatePixelPosition(game)
    local map = game.maps[self.operational_map_key]
    if map then
        self.px, self.py = map:getPixelCoords(self.grid_anchor.x, self.grid_anchor.y)
    end
end

function Vehicle:shouldDrawAtCameraScale(game)
    local s    = game.camera.scale
    local Z    = game.C.ZOOM
    local vcfg = game.C.VEHICLES[self.type:upper()]
    if not vcfg then return true end
    if vcfg.downtown_only_sim then   -- bikes
        return s >= Z.BIKE_THRESHOLD
    end
    return s >= Z.ENTITY_THRESHOLD   -- trucks
end

function Vehicle:changeState(newState, game)
    if self.state and self.state.exit then
        self.state:exit(self, game)
    end
    self.previous_state = self.state
    self.state = newState
    if self.state and self.state.enter then
        self.state:enter(self, game)
    end
end

function Vehicle:assignTrip(trip, game)
    if not self:isAvailable(game) then return end

    table.insert(self.trip_queue, trip)
end

function Vehicle:_resolveOffScreenState(game)
    local States = require("models.vehicles.vehicle_states")

    -- States that require travel time — resolution stops when one is reached.
    local TRAVEL_STATES = {
        ["To Pickup"] = true, ["To Dropoff"] = true, ["Returning"] = true,
        ["To Highway"] = true, ["On Highway"] = true, ["Exiting Highway"] = true,
    }

    -- Dispatch table: instant transitions handled here; nil entry = travel/terminal state.
    local STATE_RESOLUTION = {
        ["To Pickup"]    = function(v, g) v:changeState(States.DoPickup, g) end,
        ["To Dropoff"]   = function(v, g) v:changeState(States.DoDropoff, g) end,
        ["Returning"]    = function(v, g)
            if #v.trip_queue > 0 then
                v:changeState(States.GoToPickup, g)
            else
                v:changeState(States.Idle, g)
            end
        end,
        ["Idle"]         = function(v, g)
            if #v.trip_queue > 0 then v:changeState(States.GoToPickup, g) end
        end,
        -- Picking Up / Dropping Off / Deciding: changeState already ran enter(); no-op here.
    }

    local max_iterations = 10
    for i = 1, max_iterations do
        local name = self.state.name
        print(string.format("Vehicle %d resolving off-screen state: %s (iteration %d)", self.id, name, i))

        local handler = STATE_RESOLUTION[name]
        if handler then
            local prev = name
            handler(self, game)
            if self.state.name == prev then
                print(string.format("WARNING: Vehicle %d state didn't change from %s", self.id, prev))
                break
            end
        else
            -- Travel state or unknown — stop resolving.
            print(string.format("Vehicle %d in travel/final state: %s", self.id, name))
            break
        end

        if TRAVEL_STATES[self.state.name] then
            print(string.format("Vehicle %d reached travel state: %s", self.id, self.state.name))
            break
        end

        if i == max_iterations then
            print(string.format("ERROR: Vehicle %d hit max iterations in state resolution!", self.id))
        end
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
            self.grid_anchor = {x = final_node.x, y = final_node.y, is_tile = final_node.is_tile}
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
    -- Always animate when there is an active path or smooth path to follow.
    if self.path and #self.path > 0 then return false end
    if self.smooth_path and self.smooth_path_i and self.smooth_path_i <= #self.smooth_path then return false end

    local vcfg = game.C.VEHICLES[self.type:upper()]
    if vcfg and vcfg.downtown_only_sim and game.camera.scale < game.C.ZOOM.BIKE_THRESHOLD then
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
        local path_map = game.maps[self.operational_map_key]
        local path_tps = path_map.tile_pixel_size or game.C.MAP.TILE_SIZE
        for _, node in ipairs(self.path) do
            local px, py
            if path_map.road_v_rxs then
                if node.is_tile then
                    px, py = (node.x + 0.5) * path_tps, (node.y + 0.5) * path_tps
                else
                    px, py = node.x * path_tps, node.y * path_tps
                end
            else
                px, py = path_map:getPixelCoords(node.x, node.y)
            end
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
    if not self:shouldDrawAtCameraScale(game) then return end
    if not self.visible then return end

    local draw_px, draw_py = self.px, self.py
    local DrawingUtils = require("utils.DrawingUtils")

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