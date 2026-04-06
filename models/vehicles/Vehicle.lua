-- models/vehicles/Vehicle.lua
local Vehicle = {}
Vehicle.__index = Vehicle

local _States
local PathfindingService = require("services.PathfindingService")

function Vehicle:new(id, depot, game, vehicleType)
    if not _States then _States = require("models.vehicles.vehicle_states") end

    local instance = setmetatable({}, Vehicle)

    instance.id         = id
    instance.type       = vehicleType or "vehicle"
    instance.type_upper = (vehicleType or ""):upper()

    local vcfg = game.C.VEHICLES[instance.type_upper]
    instance.icon              = vcfg and vcfg.icon       or "❓"
    instance.base_speed        = vcfg and vcfg.base_speed or 80
    instance.pathfinding_costs = vcfg and vcfg.pathfinding_costs or {}

    -- Speed modifier: accumulates upgrade multipliers on top of base_speed.
    instance.speed_modifier = game.state.upgrades[instance.type .. "_speed"] or 1.0

    instance.depot              = depot
    instance.depot_plot         = depot.plot
    instance.trip_queue         = {}
    instance.cargo              = {}
    instance.path               = {}
    instance.path_i             = 1
    instance.pathfinding_bounds = nil

    -- Determine starting anchor (trucks snap to nearest road tile).
    local anchor = depot.plot
    if vcfg and vcfg.anchor_to_road then
        local city_map = game.maps and game.maps.city
        if city_map and city_map.findNearestRoadTile then
            local road_anchor = city_map:findNearestRoadTile(depot.plot)
            if road_anchor then anchor = road_anchor end
        end
    end

    local umap = game.maps and game.maps.unified
    if umap then
        instance.operational_map_key = "unified"
        local uts = umap.tile_pixel_size
        instance.grid_anchor = { x = anchor.x, y = anchor.y }
        instance.px = (anchor.x - 0.5) * uts
        instance.py = (anchor.y - 0.5) * uts
    else
        instance.operational_map_key = "city"
        local home_map = game.maps["city"]
        instance.grid_anchor = { x = anchor.x, y = anchor.y }
        instance.px, instance.py = home_map:getPixelCoords(anchor.x, anchor.y)
    end

    instance.state = nil
    instance:changeState(_States.Idle, game)
    instance.visible = true

    return instance
end

function Vehicle:getSpeed()
    return self.base_speed * self.speed_modifier
end

function Vehicle:getMovementCostFor(tileType)
    return self.pathfinding_costs[tileType] or 9999
end

function Vehicle:getIcon()
    return self.icon or "❓"
end

function Vehicle:getEffectiveCapacity(game)
    local vcfg = game.C.VEHICLES[self.type_upper]
    local base = vcfg and vcfg.base_capacity or 1
    -- Per-vehicle capacity upgrades accumulate in state.upgrades[type.."_capacity"]
    local upgraded = game.state.upgrades[self.type .. "_capacity"]
    return upgraded or base
end

function Vehicle:recalculatePixelPosition(game)
    local map = game.maps[self.operational_map_key]
    if map then
        if self.operational_map_key == "unified" then
            local uts = map.tile_pixel_size
            self.px = (self.grid_anchor.x - 0.5) * uts
            self.py = (self.grid_anchor.y - 0.5) * uts
        else
            self.px, self.py = map:getPixelCoords(self.grid_anchor.x, self.grid_anchor.y)
        end
    end
end

function Vehicle:shouldDrawAtCameraScale(game)
    local cs   = game.camera.scale
    local vcfg = game.C.VEHICLES[self.type_upper]
    if not vcfg then return true end
    return cs >= vcfg.rendering.render_zoom_threshold
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

function Vehicle:unassign(game)
    if not _States then _States = require("models.vehicles.vehicle_states") end
    for _, trip in ipairs(self.trip_queue) do
        table.insert(game.entities.trips.pending, trip)
    end
    for _, trip in ipairs(self.cargo) do
        table.insert(game.entities.trips.pending, trip)
    end
    self.trip_queue = {}
    self.cargo      = {}
    self.path       = {}
    self.path_i     = 1
    self:changeState(_States.Idle, game)
end

function Vehicle:isAvailable(game)
    local total_load = #self.trip_queue + #self.cargo
    return total_load < game.state.upgrades.vehicle_capacity
end

function Vehicle:_resolveOffScreenState(game)
    local States = _States

    local TRAVEL_STATES = {
        ["To Pickup"] = true, ["To Dropoff"] = true, ["Returning"] = true,
        ["To Highway"] = true, ["On Highway"] = true, ["Exiting Highway"] = true,
    }

    local STATE_RESOLUTION = {
        ["To Pickup"]  = function(v, g) v:changeState(States.DoPickup, g) end,
        ["To Dropoff"] = function(v, g) v:changeState(States.DoDropoff, g) end,
        ["Returning"]  = function(v, g)
            if #v.trip_queue > 0 then
                v:changeState(States.GoToPickup, g)
            else
                v:changeState(States.Idle, g)
            end
        end,
        ["Idle"] = function(v, g)
            if #v.trip_queue > 0 then v:changeState(States.GoToPickup, g) end
        end,
    }

    for _ = 1, 10 do
        local name    = self.state.name
        local handler = STATE_RESOLUTION[name]
        if not handler then break end
        local prev = name
        handler(self, game)
        if self.state.name == prev then break end
        if TRAVEL_STATES[self.state.name] then break end
    end
end

function Vehicle:shouldUseAbstractedSimulation(game)
    local cs   = game.camera.scale
    local vcfg = game.C.VEHICLES[self.type_upper]

    local vp = game._vp
    if vp then
        if self.px < vp.left or self.px > vp.right
        or self.py < vp.top  or self.py > vp.bot then
            return true
        end
    end

    if vcfg then
        if cs < vcfg.rendering.abstract_zoom_threshold then return true end
    end

    if self.path and (self.path_i or 1) <= #self.path then return false end
    if self.smooth_path and self.smooth_path_i and self.smooth_path_i <= #self.smooth_path then return false end

    return false
end

function Vehicle:update(dt, game)
    if self:shouldUseAbstractedSimulation(game) then
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
                if self.path and (self.path_i or 1) <= #self.path then
                    self.current_path_eta = PathfindingService.estimatePathTravelTime(self.path, self, game, game.maps.city)
                end
            elseif self.state and self.state.name == "Idle" and #self.trip_queue > 0 then
                self:changeState(_States.GoToPickup, game)
                if self.path and (self.path_i or 1) <= #self.path then
                    self.current_path_eta = PathfindingService.estimatePathTravelTime(self.path, self, game, game.maps.city)
                end
            end
        end
        return
    end

    if self.current_path_eta and self.current_path_eta > 0 then
        if self.state and self.state.name == "Returning" and #self.trip_queue > 0 then
            self:changeState(_States.GoToPickup, game)
            if self.path and (self.path_i or 1) <= #self.path then
                self.current_path_eta = PathfindingService.estimatePathTravelTime(self.path, self, game, game.maps.city)
            end
            return
        end
    end

    self.current_path_eta = self.current_path_eta - dt

    if self.current_path_eta <= 0 then
        if self.path and (self.path_i or 1) <= #self.path then
            local final_node = self.path[#self.path]
            self.grid_anchor = { x = final_node.x, y = final_node.y, is_tile = final_node.is_tile }
            self:recalculatePixelPosition(game)
            self.path = {}; self.path_i = 1
        end

        self:_resolveOffScreenState(game)

        if self.path and (self.path_i or 1) <= #self.path then
            self.current_path_eta = PathfindingService.estimatePathTravelTime(self.path, self, game, game.maps.city)
        else
            self.current_path_eta = nil
        end
    end
end

function Vehicle:drawDebug(game)
    local screen_x, screen_y = self.px, self.py
    local _pi = self.path_i or 1
    if self.path and _pi <= #self.path then
        love.graphics.setColor(0, 0, 1, 0.7)
        love.graphics.setLineWidth(2 / game.camera.scale)
        local pixel_path = {}
        table.insert(pixel_path, self.px)
        table.insert(pixel_path, self.py)
        local path_map = game.maps[self.operational_map_key]
        local path_tps = path_map.tile_pixel_size or game.C.MAP.TILE_SIZE
        for i = _pi, #self.path do
            local node = self.path[i]
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

    local scale  = 1 / game.camera.scale
    local line_h = 15 * scale
    local menu_x = screen_x + (20 * scale)
    local menu_y = screen_y - (20 * scale)

    local state_name  = self.state and self.state.name or "N/A"
    local pi          = self.path_i or 1
    local path_count  = self.path and math.max(0, #self.path - pi + 1) or 0
    local target_text = "None"
    if self.path and pi <= #self.path then
        target_text = string.format("(%d, %d)", self.path[pi].x, self.path[pi].y)
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

    DrawingUtils.drawWorldIcon(game, self:getIcon(), draw_px, draw_py)
end

return Vehicle
