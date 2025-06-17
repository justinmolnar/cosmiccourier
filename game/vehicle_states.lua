-- game/vehicle_states.lua
-- Contains all the individual state objects for the Vehicle state machine.

local States = {}

--------------------------------------------------------------------------------
-- A shared function for any state that needs to move along a path.
-- This encapsulates the movement logic so we don't repeat it.
--------------------------------------------------------------------------------
local function moveAlongPath(dt, vehicle, game)
    if not vehicle.path or #vehicle.path == 0 then return end

    local target_node = vehicle.path[1]
    local target_px, target_py = game.map:getPixelCoords(target_node.x, target_node.y)

    local angle = math.atan2(target_py - vehicle.py, target_px - vehicle.px)
    local speed = game.state.upgrades.bike_speed
    
    -- Calculate distance to target
    local dist_x = target_px - vehicle.px
    local dist_y = target_py - vehicle.py
    local dist_sq = dist_x * dist_x + dist_y * dist_y

    -- The distance we will travel this frame
    local travel_dist = speed * dt

    -- Check for arrival BEFORE moving
    -- If the distance we are about to travel is greater than the distance remaining,
    -- we have arrived.
    if dist_sq < travel_dist * travel_dist then
        -- DEFINITIVE FIX: Snap position directly to the target node's center.
        vehicle.px = target_px
        vehicle.py = target_py
        -- Now that we are exactly at the node, remove it from the path.
        table.remove(vehicle.path, 1)
    else
        -- If we have not arrived, move normally.
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
    print(string.format("Bike %d returning to depot.", vehicle.id))
    local current_pos = vehicle:getCurrentGridPos(game)
    if current_pos.x == vehicle.depot_plot.x and current_pos.y == vehicle.depot_plot.y then
        vehicle.path = {} 
        return
    end
    local start_node = game.map:findNearestRoadTile(current_pos)
    local end_node = game.map:findNearestRoadTile(vehicle.depot_plot)
    vehicle.path = game.pathfinder.findPath(game.map.grid, start_node, end_node)
    if vehicle.path then table.remove(vehicle.path, 1) end
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
    print(string.format("Bike %d going to pickup.", vehicle.id))
    local current_pos = vehicle:getCurrentGridPos(game)
    local start_node = game.map:findNearestRoadTile(current_pos)
    
    -- Get the start plot from the current leg of the trip
    local current_trip = vehicle.trip_queue[1]
    local end_node = game.map:findNearestRoadTile(current_trip.legs[current_trip.current_leg].start_plot)

    vehicle.path = game.pathfinder.findPath(game.map.grid, start_node, end_node)
    if vehicle.path then table.remove(vehicle.path, 1) end
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
        table.insert(vehicle.cargo, trip)
    end
    print(string.format("Bike %d picked up %d packages.", vehicle.id, #trips_to_pickup))
    
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
    print(string.format("Bike %d going to dropoff.", vehicle.id))
    local current_pos = vehicle:getCurrentGridPos(game)
    local start_node = game.map:findNearestRoadTile(current_pos)
    local best_path, shortest_len = nil, math.huge
    
    for _, trip in ipairs(vehicle.cargo) do
        local leg = trip.legs[trip.current_leg]
        local end_node = game.map:findNearestRoadTile(leg.end_plot)
        if not start_node or not end_node then break end
        if end_node.x ~= start_node.x or end_node.y ~= start_node.y then
            local path = game.pathfinder.findPath(game.map.grid, start_node, end_node)
            if path and #path < shortest_len then
                shortest_len = #path
                best_path = path
            end
        end
    end
    -- FIX: Ensure path is never nil. If no path was found, it becomes an empty table.
    vehicle.path = best_path or {}
    if #vehicle.path > 0 then 
        table.remove(vehicle.path, 1) 
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
    local current_pos = vehicle:getCurrentGridPos(game)
    
    for i, trip in ipairs(vehicle.cargo) do
        local leg = trip.legs[trip.current_leg]
        local plot = leg.end_plot
        local destination_road_tile = game.map:findNearestRoadTile(plot)

        if destination_road_tile and current_pos.x == destination_road_tile.x and current_pos.y == destination_road_tile.y then
            -- Calculate the final total payout
            local final_payout = trip.base_payout + trip.speed_bonus
            
            -- Publish an event with all the relevant data from the delivery
            local event_data = {
                payout = final_payout,
                bonus = trip.speed_bonus,
                base = trip.base_payout,
                x = vehicle.px,
                y = vehicle.py,
                vehicle_id = vehicle.id
            }
            game.EventBus:publish("package_delivered", event_data)

            print(string.format("Bike %d delivered a package! Payout: $%d ($%d base + $%d bonus)", vehicle.id, math.floor(final_payout), trip.base_payout, math.floor(trip.speed_bonus)))
            
            trip_index_to_remove = i
            break
        end
    end

    if trip_index_to_remove then
        table.remove(vehicle.cargo, trip_index_to_remove)
    end

    -- This state was added in the bugfix step. It should remain.
    if not States.DecideNextAction then
        States.DecideNextAction = State:new()
        States.DecideNextAction.name = "Deciding"
        function States.DecideNextAction:enter(v, g)
            if #v.cargo > 0 then v:changeState(States.GoToDropoff, g)
            elseif #v.trip_queue > 0 then v:changeState(States.GoToPickup, g)
            else v:changeState(States.ReturningToDepot, g) end
        end
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

return States