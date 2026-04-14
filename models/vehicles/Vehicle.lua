-- models/vehicles/Vehicle.lua
local Vehicle = {}
Vehicle.__index = Vehicle

local _States
local PathfindingService = require("services.PathfindingService")
local FuelService        = require("services.FuelService")

function Vehicle:new(id, depot, game, vehicleType)
    if not _States then _States = require("models.vehicles.vehicle_states") end

    local instance = setmetatable({}, Vehicle)

    instance.id         = id
    instance.type       = vehicleType or "vehicle"
    instance.type_upper = (vehicleType or ""):upper()

    local vcfg = game.C.VEHICLES[instance.type_upper]
    instance.icon              = vcfg and vcfg.icon            or "❓"
    instance.base_speed        = vcfg and vcfg.base_speed       or 80
    instance.pathfinding_costs = vcfg and vcfg.pathfinding_costs or {}
    instance.transport_mode    = vcfg and vcfg.transport_mode   or "road"
    instance.path_fuel_cost    = 0

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

    instance.last_trip_end_time = 0
    instance.trips_completed    = 0

    instance.state = nil
    instance:changeState(_States.Idle, game)
    instance.visible = true

    return instance
end

function Vehicle:getSpeed()
    return self.base_speed * self.speed_modifier
end

function Vehicle:returnToDepot(game)
    if not _States then _States = require("models.vehicles.vehicle_states") end
    if self.state and self.state.name ~= "Idle" and self.state.name ~= "Returning" then
        self:changeState(_States.ReturningToDepot, game)
    end
end

function Vehicle:getMovementCostFor(tileType)
    return self.pathfinding_costs[tileType] or 9999
end

function Vehicle:getIcon()
    return self.icon_override or self.icon or "❓"
end

function Vehicle:getEffectiveCapacity(game)
    local vcfg = game.C.VEHICLES[self.type_upper]
    local base = vcfg and vcfg.base_capacity or 1
    -- Per-vehicle capacity upgrades accumulate in state.upgrades[type.."_capacity"]
    local upgraded = game.state.upgrades[self.type .. "_capacity"]
    return upgraded or base
end

function Vehicle:getEffectiveFuelRate(game)
    local vcfg = game.C.VEHICLES[self.type_upper]
    local base = (vcfg and vcfg.fuel_rate) or 0
    -- Fuel-efficiency upgrades accumulate as a multiplier in state.upgrades[type.."_fuel_rate"]
    local mult = game.state.upgrades[self.type .. "_fuel_rate"] or 1.0
    return base * mult
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
    -- Track when vehicle enters/leaves Idle for hat_vehicle_idle_for
    if newState and newState.name == "Idle" then
        self.idle_since = love.timer.getTime()
    elseif self.idle_since then
        self.idle_since = nil
    end
end

function Vehicle:assignTrip(trip, game)
    if not self:isAvailable(game) then return end
    table.insert(self.trip_queue, trip)
end

function Vehicle:unassign(game)
    if not _States then _States = require("models.vehicles.vehicle_states") end
    local BS = require("services.BuildingService")
    -- Return trips to the building at their current leg's start_plot.
    local function returnTrip(trip)
        local leg = trip.legs and trip.legs[trip.current_leg]
        local sp  = leg and leg.start_plot
        local building = sp and BS.findAtPlot(sp.x, sp.y, game)
        if building then
            BS.depositTrip(building, trip, game)
        else
            table.insert(game.entities.trips.pending, trip)
        end
    end
    for _, trip in ipairs(self.trip_queue) do returnTrip(trip) end
    for _, trip in ipairs(self.cargo) do
        trip:thaw()
        returnTrip(trip)
    end
    self.trip_queue     = {}
    self.cargo          = {}
    self.path           = {}
    self.path_i         = 1
    self.path_fuel_cost = 0
    self:changeState(_States.Idle, game)
end

function Vehicle:isAvailable(game)
    local total_load = #self.trip_queue + #self.cargo
    return total_load < self:getEffectiveCapacity(game)
end

function Vehicle:_resolveOffScreenState(game)
    local States = _States

    local TRAVEL_STATES = {
        ["To Pickup"] = true, ["To Dropoff"] = true, ["Returning"] = true,
        ["To Highway"] = true, ["On Highway"] = true, ["Exiting Highway"] = true,
    }

    local STATE_RESOLUTION = {
        ["To Pickup"]  = function(v, g)
            FuelService.consume(v, g)
            v:changeState(States.DoPickup, g)
        end,
        ["To Dropoff"] = function(v, g)
            FuelService.consume(v, g)
            v:changeState(States.DoDropoff, g)
        end,
        ["Returning"]  = function(v, g)
            FuelService.consume(v, g)
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
    -- Decay visual timers
    if self.speech_bubble and self.speech_bubble.timer > 0 then
        self.speech_bubble.timer = self.speech_bubble.timer - dt
        if self.speech_bubble.timer <= 0 then self.speech_bubble = nil end
    end
    if self.flash and self.flash.timer > 0 then
        self.flash.timer = self.flash.timer - dt
        if self.flash.timer <= 0 then self.flash = nil end
    end

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
            -- If a path is already set (e.g. vehicle enters abstraction mid-travel),
            -- just estimate the remaining time without forcing a state transition.
            if self.path and (self.path_i or 1) <= #self.path then
                self.current_path_eta = PathfindingService.estimatePathTravelTime(self.path, self, game, game.maps.city)
            elseif self.state and (self.state.name == "Picking Up" or
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


return Vehicle
