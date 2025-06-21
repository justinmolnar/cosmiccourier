-- game/vehicle_states.lua
-- Contains all the individual state objects for the Vehicle state machine.

local States = {}

--------------------------------------------------------------------------------
-- A shared function for any state that needs to move along a path.
-- This encapsulates the movement logic so we don't repeat it.
--------------------------------------------------------------------------------
function moveAlongPath(dt, vehicle, game)
    if not vehicle.path or #vehicle.path == 0 then return end

    local active_map = game.maps[game.active_map_key]
    if not active_map then return end

    local target_node = vehicle.path[1]
    local target_px, target_py = active_map:getPixelCoords(target_node.x, target_node.y)

    local angle = math.atan2(target_py - vehicle.py, target_px - vehicle.px)

    -- Step 1: Get the correct base speed for the vehicle type from the vehicle's properties
    local base_speed = vehicle.properties.speed

    -- Step 2: Normalize the speed. The original speed was balanced for a visual
    -- tile size of 16. Our new world tile size is 2. So we must scale it down.
    local speed_normalization_factor = game.C.GAMEPLAY.BASE_TILE_SIZE / game.C.MAP.TILE_SIZE
    local normalized_speed = base_speed / speed_normalization_factor

    -- Step 3: Calculate the distance to travel in world units using the normalized speed
    local travel_dist = normalized_speed * dt

    local dist_x = target_px - vehicle.px
    local dist_y = target_py - vehicle.py
    local dist_sq = dist_x * dist_x + dist_y * dist_y

    if dist_sq < travel_dist * travel_dist then
        vehicle.grid_anchor = {x = target_node.x, y = target_node.y}
        vehicle:recalculatePixelPosition(game)
        table.remove(vehicle.path, 1)
    else
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
    vehicle.path = {} -- An idle vehicle has no path.
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
    local PathfindingService = require("services.PathfindingService")
    
    print(string.format("%s %d returning to depot.", vehicle.type, vehicle.id))
    
    vehicle.path = PathfindingService.findPathToDepot(vehicle, game)
    
    if not vehicle.path then
        vehicle:changeState(States.Stuck, game)
        return
    end
end

function States.ReturningToDepot:update(dt, vehicle, game)
    if #vehicle.trip_queue > 0 then
        vehicle:changeState(States.GoToPickup, game)
        return
    end
    if not vehicle.path or #vehicle.path == 0 then
        vehicle:changeState(States.Idle, game)
        return
    end
    moveAlongPath(dt, vehicle, game)
end

--------------------------------------------------------------------------------
-- State: Go To Pickup
--------------------------------------------------------------------------------
States.GoToPickup = State:new()
States.GoToPickup.name = "To Pickup"
function States.GoToPickup:enter(vehicle, game)
    local PathfindingService = require("services.PathfindingService")
    
    print(string.format("%s %d going to pickup.", vehicle.type, vehicle.id))
    
    local trip_to_get = vehicle.trip_queue[1]
    if not trip_to_get then
        vehicle:changeState(States.Stuck, game)
        return
    end
    
    vehicle.path = PathfindingService.findPathToPickup(vehicle, trip_to_get, game)
    
    if not vehicle.path then
        vehicle:changeState(States.Stuck, game)
        return
    end
end


function States.GoToPickup:update(dt, vehicle, game)
    if not vehicle.path or #vehicle.path == 0 then
        vehicle:changeState(States.DoPickup, game)
        return
    end
    moveAlongPath(dt, vehicle, game)
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
    
    print(string.format("Bike %d picked up %d packages (frozen %d timers).", vehicle.id, #trips_to_pickup, #trips_to_pickup))
    
    -- FIX: After picking up, immediately decide the next state here.
    if #vehicle.cargo > 0 then
        vehicle:changeState(States.GoToDropoff, game)
    else
        vehicle:changeState(States.ReturningToDepot, game)
    end
end

--------------------------------------------------------------------------------
-- State: Go To Dropoff
--------------------------------------------------------------------------------
States.GoToDropoff = State:new()
States.GoToDropoff.name = "To Dropoff"
function States.GoToDropoff:enter(vehicle, game)
    local PathfindingService = require("services.PathfindingService")
    
    print(string.format("%s %d going to dropoff.", vehicle.type, vehicle.id))
    
    vehicle.path = PathfindingService.findPathToDropoff(vehicle, game)
    
    if not vehicle.path then
        vehicle:changeState(States.Stuck, game)
        return
    end
end


function States.GoToDropoff:update(dt, vehicle, game)
    if not vehicle.path or #vehicle.path == 0 then
        vehicle:changeState(States.DoDropoff, game)
        return
    end
    moveAlongPath(dt, vehicle, game)
end

--------------------------------------------------------------------------------
-- State: Do Dropoff (Instantaneous)
--------------------------------------------------------------------------------
States.DoDropoff = State:new()
States.DoDropoff.name = "Dropping Off"
function States.DoDropoff:enter(vehicle, game)
    local C = game.C
    local trip_index_to_remove = nil
    
    local current_pos = vehicle.grid_anchor
    local active_map = game.maps[game.active_map_key]
    if not active_map then return end
    
    for i, trip in ipairs(vehicle.cargo) do
        local leg = trip.legs[trip.current_leg]
        local destination_road_tile = nil

        -- Determine which grid to use for finding the destination
        if leg.vehicleType == "bike" then
            destination_road_tile = active_map:findNearestRoadTile(leg.end_plot)
        else -- For trucks and future vehicles, use the city-scale finder
            destination_road_tile = active_map:findNearestRoadTile(leg.end_plot)
        end

        if destination_road_tile and current_pos.x == destination_road_tile.x and current_pos.y == destination_road_tile.y then
            trip:thaw()
            local is_final_destination = trip.current_leg >= #trip.legs
            
            if is_final_destination then
                -- FINAL DELIVERY
                local final_payout = trip.base_payout + trip.speed_bonus
                local event_data = { payout = final_payout, bonus = trip.speed_bonus, base = trip.base_payout, x = vehicle.px, y = vehicle.py }
                game.EventBus:publish("package_delivered", event_data)
                print(string.format("%s %d delivered package! $%d", vehicle.type, vehicle.id, math.floor(final_payout)))
                trip_index_to_remove = i
            else
                -- INTERMEDIATE STOP (HUB/DEPOT)
                trip.current_leg = trip.current_leg + 1
                print(string.format("Trip transferred to leg %d/%d. Vehicle: %s", trip.current_leg, #trip.legs, trip.legs[trip.current_leg].vehicleType))
                
                -- TODO: In the future, this would go to a specific hub's inventory.
                -- For now, we put it back in the main pending list.
                table.insert(game.entities.trips.pending, trip)
                trip_index_to_remove = i
            end
            
            break
        end
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
        -- If we still have packages to deliver, go find the next one.
        vehicle:changeState(States.GoToDropoff, game)
    elseif #vehicle.trip_queue > 0 then
        -- If we have pending pickups, go get them.
        vehicle:changeState(States.GoToPickup, game)
    else
        -- If we have no work to do, go home.
        vehicle:changeState(States.ReturningToDepot, game)
    end
end

--------------------------------------------------------------------------------
-- State: Stuck (Failsafe)
--------------------------------------------------------------------------------
States.Stuck = State:new()
States.Stuck.name = "Stuck"
function States.Stuck:enter(vehicle, game)
    -- When a vehicle gets stuck, remember what it was trying to do.
    vehicle.last_state_before_stuck = vehicle.state
    vehicle.stuck_timer = 15 -- Wait 15 seconds before retrying
    print(string.format("WARNING: %s %d is stuck, will retry pathfinding in %ds.", vehicle.type, vehicle.id, vehicle.stuck_timer))
end

function States.Stuck:update(dt, vehicle, game)
    vehicle.stuck_timer = vehicle.stuck_timer - dt
    if vehicle.stuck_timer <= 0 then
        -- Timer is up, try to do the last action again.
        local previous_state = vehicle.last_state_before_stuck or States.DecideNextAction
        vehicle:changeState(previous_state, game)
    end
end


return States