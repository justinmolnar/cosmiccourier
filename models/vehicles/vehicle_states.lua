-- models/vehicles/vehicle_states.lua
-- Contains all the individual state objects for the Vehicle state machine.

local States = {}

local buildSmoothPath = require("services.PathSmoothingService").buildSmoothPath


--------------------------------------------------------------------------------
-- A shared function for any state that needs to move along a path.
-- This encapsulates the movement logic so we don't repeat it.
--------------------------------------------------------------------------------
function moveAlongPath(dt, vehicle, game)
    local map_for_pathing = game.maps[vehicle.operational_map_key]
    if not map_for_pathing then return end

    local tps = map_for_pathing.tile_pixel_size or game.C.MAP.TILE_SIZE
    local base_speed = vehicle:getSpeed()
    local speed_normalization_factor = game.C.GAMEPLAY.BASE_TILE_SIZE / tps
    local normalized_speed = base_speed / speed_normalization_factor
    local vcfg = game.C.VEHICLES[vehicle.type:upper()]
    if vcfg and vcfg.needs_downtown_speed_scale then
        local city_map = game.maps and game.maps.city
        local dw = city_map and city_map.downtown_grid_width or game.C.MAP.DOWNTOWN_GRID_WIDTH
        normalized_speed = normalized_speed * (dw / 64)
    end
    local travel_dist = normalized_speed * dt

    -- Smooth visual movement along Chaikin-curved waypoints.
    local spi = vehicle.smooth_path_i
    if vehicle.smooth_path and spi and spi <= #vehicle.smooth_path then
        local target = vehicle.smooth_path[spi]
        local dx = target[1] - vehicle.px
        local dy = target[2] - vehicle.py
        local dist_sq = dx * dx + dy * dy
        if dist_sq <= travel_dist * travel_dist then
            vehicle.px, vehicle.py = target[1], target[2]
            spi = spi + 1
            vehicle.smooth_path_i = spi
            if spi > #vehicle.smooth_path then
                -- Smooth path exhausted: sync grid_anchor to last node and signal arrival.
                if vehicle.path and (vehicle.path_i or 1) <= #vehicle.path then
                    local last = vehicle.path[#vehicle.path]
                    vehicle.grid_anchor = {x = last.x, y = last.y}
                end
                vehicle.path = {}; vehicle.path_i = 1
                vehicle.smooth_path   = nil
                vehicle.smooth_path_i = nil
                vehicle.current_path_eta = nil  -- don't let abstracted sim delay the transition
            end
        else
            local dist = math.sqrt(dist_sq)
            vehicle.px = vehicle.px + (dx / dist) * travel_dist
            vehicle.py = vehicle.py + (dy / dist) * travel_dist
        end

        -- Keep grid_anchor walking forward so mid-path rerouting starts near the
        -- vehicle's actual position, not the stale start of the previous trip.
        -- We pop all but the last node so vehicle.path never empties prematurely.
        if vehicle.path and vehicle.path_i < #vehicle.path then
            local head = vehicle.path[vehicle.path_i]
            local hdx = (head.x - 0.5) * tps - vehicle.px
            local hdy = (head.y - 0.5) * tps - vehicle.py
            if hdx * hdx + hdy * hdy < (tps * 0.5) * (tps * 0.5) then
                vehicle.grid_anchor = {x = head.x, y = head.y}
                vehicle.path_i = vehicle.path_i + 1
            end
        end
        return
    end

    -- Fallback: straight-line movement between grid nodes (sandbox maps, or no smooth path).
    if not vehicle.path or (vehicle.path_i or 1) > #vehicle.path then return end

    local target_node = vehicle.path[vehicle.path_i]
    local target_px, target_py = map_for_pathing:getPixelCoords(target_node.x, target_node.y)

    local dist_x = target_px - vehicle.px
    local dist_y = target_py - vehicle.py
    local dist_sq = dist_x * dist_x + dist_y * dist_y

    if dist_sq <= travel_dist * travel_dist then
        vehicle.grid_anchor = {x = target_node.x, y = target_node.y}
        vehicle:recalculatePixelPosition(game)
        vehicle.path_i = vehicle.path_i + 1
    else
        local angle = math.atan2(dist_y, dist_x)
        vehicle.px = vehicle.px + math.cos(angle) * travel_dist
        vehicle.py = vehicle.py + math.sin(angle) * travel_dist
    end
end

--------------------------------------------------------------------------------
-- Base State (for other states to inherit from)
--------------------------------------------------------------------------------
local State = {}
State.__index = State
function State:new()
    return setmetatable({}, State)
end
function State:enter(vehicle, game) end
function State:update(dt, vehicle, game) end
function State:exit(vehicle, game) end

--------------------------------------------------------------------------------
-- State: Idle (At Depot)
--------------------------------------------------------------------------------
States.Idle = State:new()
States.Idle.name = "Idle"
function States.Idle:enter(vehicle, game)
    vehicle.path = {}; vehicle.path_i = 1
    vehicle.smooth_path   = nil
    vehicle.smooth_path_i = nil
end
function States.Idle:update(dt, vehicle, game)
    -- If we have been assigned work, change state.
    if #vehicle.trip_queue > 0 then
        vehicle:changeState(States.GoToPickup, game)
    end
end

--------------------------------------------------------------------------------
-- State: Returning To Depot
--------------------------------------------------------------------------------
States.ReturningToDepot = State:new()
States.ReturningToDepot.name = "Returning"
function States.ReturningToDepot:enter(vehicle, game)
    local PathScheduler = require("services.PathScheduler")
    PathScheduler.request(vehicle, function()
        local PathfindingService = require("services.PathfindingService")
        vehicle._path_pending = false
        vehicle.path = PathfindingService.findPathToDepot(vehicle, game)
        vehicle.path_i = 1
        if not vehicle.path then
            vehicle:changeState(States.Stuck, game)
            return
        end
        vehicle.current_path_eta = PathfindingService.estimatePathTravelTime(vehicle.path, vehicle, game)
        if game.debug_smooth_vehicle_movement then buildSmoothPath(vehicle, game) end
    end)
end

function States.ReturningToDepot:update(dt, vehicle, game)
    if vehicle._path_pending then return end
    if #vehicle.trip_queue > 0 then
        vehicle:changeState(States.GoToPickup, game)
        return
    end
    if (not vehicle.path) or ((vehicle.path_i or 1) > #vehicle.path) then
        vehicle:changeState(States.Idle, game)
        return
    end
    moveAlongPath(dt, vehicle, game)
    if (not vehicle.path) or ((vehicle.path_i or 1) > #vehicle.path) then
        vehicle:changeState(States.Idle, game)
    end
end

--------------------------------------------------------------------------------
-- State: Go To Pickup
--------------------------------------------------------------------------------
States.GoToPickup = State:new()
States.GoToPickup.name = "To Pickup"
function States.GoToPickup:enter(vehicle, game)
    local trip_to_get = vehicle.trip_queue[1]
    if not trip_to_get then
        vehicle:changeState(States.Stuck, game)
        return
    end
    local PathScheduler = require("services.PathScheduler")
    PathScheduler.request(vehicle, function()
        local PathfindingService = require("services.PathfindingService")
        vehicle._path_pending = false
        vehicle.path = PathfindingService.findPathToPickup(vehicle, trip_to_get, game)
        vehicle.path_i = 1
        if not vehicle.path then
            vehicle:changeState(States.Stuck, game)
            return
        end
        vehicle.current_path_eta = PathfindingService.estimatePathTravelTime(vehicle.path, vehicle, game)
        if game.debug_smooth_vehicle_movement then buildSmoothPath(vehicle, game) end
    end)
end

function States.GoToPickup:update(dt, vehicle, game)
    if vehicle._path_pending then return end
    if (not vehicle.path) or ((vehicle.path_i or 1) > #vehicle.path) then
        vehicle:changeState(States.DoPickup, game)
        return
    end
    moveAlongPath(dt, vehicle, game)
    if (not vehicle.path) or ((vehicle.path_i or 1) > #vehicle.path) then
        vehicle:changeState(States.DoPickup, game)
    end
end

--------------------------------------------------------------------------------
-- State: Do Pickup (Instantaneous)
--------------------------------------------------------------------------------
States.DoPickup = State:new()
States.DoPickup.name = "Picking Up"
function States.DoPickup:enter(vehicle, game)
    local current_trip_leg = vehicle.trip_queue[1].legs[vehicle.trip_queue[1].current_leg]
    local pickup_location = current_trip_leg.start_plot

    local trips_to_pickup, remaining_trips = {}, {}
    for _, trip in ipairs(vehicle.trip_queue) do
        local leg = trip.legs[trip.current_leg]
        if leg.start_plot.x == pickup_location.x and leg.start_plot.y == pickup_location.y then
            table.insert(trips_to_pickup, trip)
        else
            table.insert(remaining_trips, trip)
        end
    end
    vehicle.trip_queue = remaining_trips
    for _, trip in ipairs(trips_to_pickup) do
        -- FREEZE the trip as it enters vehicle cargo
        trip:freeze()
        table.insert(vehicle.cargo, trip)
    end
    
    
    -- After picking up, immediately decide the next state here.
    if #vehicle.cargo > 0 then
        vehicle:changeState(States.GoToDropoff, game)
    else
        vehicle:changeState(States.ReturningToDepot, game)
    end
end

--------------------------------------------------------------------------------
-- State: Go To Dropoff (Decision Point)
--------------------------------------------------------------------------------
States.GoToDropoff = State:new()
States.GoToDropoff.name = "To Dropoff"
function States.GoToDropoff:enter(vehicle, game)
    local PathScheduler = require("services.PathScheduler")
    PathScheduler.request(vehicle, function()
        local PathfindingService = require("services.PathfindingService")
        vehicle._path_pending = false
        local leg = vehicle.cargo[1] and vehicle.cargo[1].legs[vehicle.cargo[1].current_leg]
        if leg then
            print(string.format("DEBUG dropoff: %s %d anchor=(%d,%d) dest=(%d,%d) map=%s",
                vehicle.type, vehicle.id,
                vehicle.grid_anchor.x, vehicle.grid_anchor.y,
                leg.end_plot.x, leg.end_plot.y,
                vehicle.operational_map_key))
        end
        vehicle.path = PathfindingService.findPathToDropoff(vehicle, game)
        vehicle.path_i = 1
        if not vehicle.path then
            vehicle:changeState(States.Stuck, game)
            return
        end
        vehicle.current_path_eta = PathfindingService.estimatePathTravelTime(vehicle.path, vehicle, game)
        if game.debug_smooth_vehicle_movement then buildSmoothPath(vehicle, game) end
    end)
end

function States.GoToDropoff:update(dt, vehicle, game)
    if vehicle._path_pending then return end
    if (not vehicle.path) or ((vehicle.path_i or 1) > #vehicle.path) then
        vehicle:changeState(States.DoDropoff, game)
        return
    end
    moveAlongPath(dt, vehicle, game)
    if (not vehicle.path) or ((vehicle.path_i or 1) > #vehicle.path) then
        vehicle:changeState(States.DoDropoff, game)
    end
end

--------------------------------------------------------------------------------
-- State: Do Dropoff (Instantaneous)
--------------------------------------------------------------------------------
States.DoDropoff = State:new()
States.DoDropoff.name = "Dropping Off"
function States.DoDropoff:enter(vehicle, game)
    local trip_index_to_remove = nil

    for i, trip in ipairs(vehicle.cargo) do
        local leg = trip.legs[trip.current_leg]
        
        -- Vehicle completed its path to reach DoDropoff (or is off-screen abstracted),
        -- so it is at the destination by definition.
        trip:thaw()
        local is_final_destination = trip.current_leg >= #trip.legs

        if is_final_destination then
            -- FINAL DELIVERY
            local final_payout = trip.base_payout + trip.speed_bonus
            -- Convert city-local px/py to world-pixel coords so floating text
            -- renders at the right position regardless of which city this vehicle is in.
            local ts   = game.C.MAP.TILE_SIZE
            local vmap = game.maps and game.maps[vehicle.operational_map_key]
            local wx   = vehicle.px + ((vmap and vmap.world_mn_x or 1) - 1) * ts
            local wy   = vehicle.py + ((vmap and vmap.world_mn_y or 1) - 1) * ts
            local event_data = { payout = final_payout, bonus = trip.speed_bonus, base = trip.base_payout, x = wx, y = wy }
            game.EventBus:publish("package_delivered", event_data)
            trip_index_to_remove = i
        else
            -- INTERMEDIATE STOP (HUB/DEPOT) - bike completes leg 1, truck picks up leg 2
            trip.current_leg = trip.current_leg + 1
            table.insert(game.entities.trips.pending, trip)
            trip_index_to_remove = i
        end

        break
    end

    if trip_index_to_remove then
        table.remove(vehicle.cargo, trip_index_to_remove)
    end

    vehicle:changeState(States.DecideNextAction, game)
end

--------------------------------------------------------------------------------
-- State: Decide Next Action (Instantaneous)
--------------------------------------------------------------------------------
States.DecideNextAction = State:new()
States.DecideNextAction.name = "Deciding"
function States.DecideNextAction:enter(vehicle, game)
    if #vehicle.cargo > 0 then
        vehicle:changeState(States.GoToDropoff, game)
    elseif #vehicle.trip_queue > 0 then
        vehicle:changeState(States.GoToPickup, game)
    else
        vehicle:changeState(States.ReturningToDepot, game)
    end
end

--------------------------------------------------------------------------------
-- State: Stuck (Failsafe)
--------------------------------------------------------------------------------
States.Stuck = State:new()
States.Stuck.name = "Stuck"
function States.Stuck:enter(vehicle, game)
    vehicle.smooth_path   = nil
    vehicle.smooth_path_i = nil
    -- When a vehicle gets stuck, remember what it was trying to do.
    -- Use previous_state (saved before the transition) not vehicle.state (which is already Stuck).
    vehicle.last_state_before_stuck = vehicle.previous_state
    -- Use the new constant for the timer
    vehicle.stuck_timer = game.C.GAMEPLAY.VEHICLE_STUCK_TIMER
    print(string.format("WARNING: %s %d is stuck, will retry pathfinding in %ds.", vehicle.type, vehicle.id, vehicle.stuck_timer))
end

function States.Stuck:update(dt, vehicle, game)
    vehicle.stuck_timer = vehicle.stuck_timer - dt
    if vehicle.stuck_timer <= 0 then
        local previous_state = vehicle.last_state_before_stuck or States.DecideNextAction
        vehicle:changeState(previous_state, game)
    end
end

return States