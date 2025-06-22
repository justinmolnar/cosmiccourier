-- models/vehicles/vehicle_states.lua
-- Contains all the individual state objects for the Vehicle state machine.

local States = {}

--------------------------------------------------------------------------------
-- A shared function for any state that needs to move along a path.
-- This encapsulates the movement logic so we don't repeat it.
--------------------------------------------------------------------------------
function moveAlongPath(dt, vehicle, game)
    if not vehicle.path or #vehicle.path == 0 then return end

    -- Use the vehicle's operational map, not a hard-coded one.
    local map_for_pathing = game.maps[vehicle.operational_map_key]
    if not map_for_pathing then return end

    local target_node = vehicle.path[1]
    local target_px, target_py = map_for_pathing:getPixelCoords(target_node.x, target_node.y)

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

    vehicle.current_path_eta = PathfindingService.estimatePathTravelTime(vehicle.path, vehicle, game, game.maps.city)
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

    vehicle.current_path_eta = PathfindingService.estimatePathTravelTime(vehicle.path, vehicle, game, game.maps.city)
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
    
    print(string.format("%s %d picked up %d packages (frozen %d timers).", vehicle.type, vehicle.id, #trips_to_pickup, #trips_to_pickup))
    
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
    local PathfindingService = require("services.PathfindingService")

    print(string.format("DEBUG: %s %d deciding dropoff", vehicle.type, vehicle.id))

    -- Check if the primary trip in cargo requires long-distance travel
    local trip = vehicle.cargo[1]
    
    -- THE FIX: If it's a long-distance truck trip, bypass the broken "GoToNetworkEntry"
    -- state and go DIRECTLY to "TravelingOnNetwork".
    if trip and trip.is_long_distance and vehicle.type == "truck" then
        print(string.format("DEBUG: %s %d has a long-distance trip, transitioning directly to TravelingOnNetwork", vehicle.type, vehicle.id))
        
        vehicle:changeState(States.TravelingOnNetwork, game, { 
            network_type = "highway", 
            destination_map = "region",
            destination_plot = trip.legs[#trip.legs].end_plot 
        })
        return
    end
    
    -- If not long distance, proceed with normal local dropoff logic
    vehicle.path = PathfindingService.findPathToDropoff(vehicle, game)
    
    if not vehicle.path then
        print(string.format("DEBUG: %s %d failed to find dropoff path, entering Stuck state", vehicle.type, vehicle.id))
        vehicle:changeState(States.Stuck, game)
        return
    end

    vehicle.current_path_eta = PathfindingService.estimatePathTravelTime(vehicle, game)
    print(string.format("DEBUG: %s %d path to dropoff: %d nodes, ETA: %.2fs", vehicle.type, vehicle.id, #vehicle.path, vehicle.current_path_eta))
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
    local active_map = game.maps[vehicle.operational_map_key]
    if not active_map then return end
    
    local is_abstracted_mode = (game.active_map_key ~= "city")
    
    print(string.format("DEBUG: %s %d starting dropoff at (%d,%d), abstracted: %s, cargo: %d", 
          vehicle.type, vehicle.id, current_pos.x, current_pos.y, tostring(is_abstracted_mode), #vehicle.cargo))
    
    for i, trip in ipairs(vehicle.cargo) do
        local leg = trip.legs[trip.current_leg]
        
        print(string.format("DEBUG: Processing trip leg %d/%d - vehicle type needed: %s, current vehicle: %s", 
              trip.current_leg, #trip.legs, leg.vehicleType, vehicle.type))
        
        local destination_road_tile = nil

        -- Determine which grid to use for finding the destination
        destination_road_tile = active_map:findNearestRoadTile(leg.end_plot)

        local at_destination = false
        if is_abstracted_mode then
            at_destination = true
            print(string.format("DEBUG: %s %d: Abstracted dropoff assumed at destination", vehicle.type, vehicle.id))
        else
            at_destination = destination_road_tile and 
                           current_pos.x == destination_road_tile.x and 
                           current_pos.y == destination_road_tile.y
            print(string.format("DEBUG: %s %d: Detailed dropoff position check - at_destination: %s", vehicle.type, vehicle.id, tostring(at_destination)))
        end

        if at_destination then
            trip:thaw()
            local is_final_destination = trip.current_leg >= #trip.legs
            
            print(string.format("DEBUG: %s %d dropoff SUCCESS - current_leg: %d, total_legs: %d, is_final: %s, is_long_distance: %s", 
                  vehicle.type, vehicle.id, trip.current_leg, #trip.legs, tostring(is_final_destination), tostring(trip.is_long_distance)))
            
            if is_final_destination then
                -- FINAL DELIVERY
                local final_payout = trip.base_payout + trip.speed_bonus
                local event_data = { payout = final_payout, bonus = trip.speed_bonus, base = trip.base_payout, x = vehicle.px, y = vehicle.py }
                game.EventBus:publish("package_delivered", event_data)
                print(string.format("DEBUG: %s %d completed FINAL delivery! $%d", 
                      vehicle.type, vehicle.id, math.floor(final_payout)))
                trip_index_to_remove = i
            else
                -- INTERMEDIATE STOP (HUB/DEPOT) - this should happen for bikes completing leg 1
                local old_leg = trip.current_leg
                trip.current_leg = trip.current_leg + 1
                local new_leg = trip.legs[trip.current_leg]
                
                print(string.format("DEBUG: %s %d completed INTERMEDIATE stop (leg %d). Trip now needs %s for leg %d/%d", 
                      vehicle.type, vehicle.id, old_leg, new_leg.vehicleType, trip.current_leg, #trip.legs))
                
                -- Put it back in the main pending list for the next vehicle type
                table.insert(game.entities.trips.pending, trip)
                print(string.format("DEBUG: Trip added back to pending queue for %s (now %d pending trips)", 
                      new_leg.vehicleType, #game.entities.trips.pending))
                trip_index_to_remove = i
            end
            
            break
        else
            print(string.format("DEBUG: %s %d NOT at destination: current=(%d,%d), target=(%d,%d)", 
                  vehicle.type, vehicle.id, current_pos.x, current_pos.y, 
                  destination_road_tile and destination_road_tile.x or -1, 
                  destination_road_tile and destination_road_tile.y or -1))
        end
    end

    if trip_index_to_remove then
        table.remove(vehicle.cargo, trip_index_to_remove)
        print(string.format("DEBUG: %s %d removed trip from cargo, %d remaining", vehicle.type, vehicle.id, #vehicle.cargo))
    else
        print(string.format("DEBUG: %s %d: No trip was dropped off!", vehicle.type, vehicle.id))
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
-- State: GoToNetworkEntry (Generic)
--------------------------------------------------------------------------------
States.GoToNetworkEntry = State:new()
States.GoToNetworkEntry.name = "Going to Network Entry"
function States.GoToNetworkEntry:enter(vehicle, game, params)
    local PathfindingService = require("services.PathfindingService")
    params = params or {}
    local network_type = params.network_type or "highway"

    print(string.format("DEBUG: %s %d finding path to nearest '%s' entry.", vehicle.type, vehicle.id, network_type))

    -- THE FIX: Get a path from the depot to a random highway tile on the city map.
    -- This forces the truck to travel across the city before changing to the regional map.
    vehicle.path = PathfindingService.findPathToRandomHighway(vehicle, game)
    
    if not vehicle.path or #vehicle.path == 0 then
        print("ERROR: GoToNetworkEntry failed to find a path to the highway.")
        vehicle:changeState(States.Stuck, game)
        return
    end

    -- Store the parameters so we can pass them to the next state upon arrival.
    vehicle.network_travel_params = params
end

function States.GoToNetworkEntry:update(dt, vehicle, game)
    if not vehicle.path or #vehicle.path == 0 then
        -- Arrived at the network entry point. Now, begin the main journey.
        vehicle:changeState(States.TravelingOnNetwork, game, vehicle.network_travel_params)
        vehicle.network_travel_params = nil -- Clean up stored params
        return
    end
    moveAlongPath(dt, vehicle, game)
end

--------------------------------------------------------------------------------
-- State: TravelingOnNetwork (Generic)
--------------------------------------------------------------------------------
States.TravelingOnNetwork = State:new()
States.TravelingOnNetwork.name = "Traveling on Network"
function States.TravelingOnNetwork:enter(vehicle, game, params)
    params = params or {}
    local destination_map_key = params.destination_map or "region"
    local final_destination_plot = params.destination_plot or vehicle.cargo[1].legs[#vehicle.cargo[1].legs].end_plot

    print(string.format("DEBUG: %s %d entering '%s' network. Destination map: %s", 
          vehicle.type, vehicle.id, params.network_type or "unknown", destination_map_key))
    
    -- Translate the vehicle's grid anchor from city-local to region-global coordinates
    local city_offset = game.maps.region.main_city_offset
    if city_offset then
        vehicle.grid_anchor.x = vehicle.grid_anchor.x + city_offset.x
        vehicle.grid_anchor.y = vehicle.grid_anchor.y + city_offset.y
    end

    -- Switch the operational map and recalculate pixel position
    vehicle.operational_map_key = destination_map_key
    vehicle:recalculatePixelPosition(game)

    -- Find the destination city's depot on the regional map
    local destination_on_network = nil
    local destination_city_data = nil
    for _, city_data in ipairs(game.maps.region.cities_data) do
        if city_data.center_x ~= game.maps.region.main_city_offset.x + (game.C.MAP.CITY_GRID_WIDTH / 2) then
             destination_city_data = city_data
             -- THE FIX: Find the road tile nearest the depot, not just the center.
             local depot_plot = {
                 x = city_data.center_x,
                 y = city_data.center_y
             }
             destination_on_network = game.maps.region:findNearestRoadTile(depot_plot)
             break
        end
    end

    if not destination_on_network then
        print("ERROR: Could not find destination city for plot!", final_destination_plot.x, final_destination_plot.y)
        vehicle:changeState(States.Stuck, game)
        return
    end

    -- Pathfind on the regional map
    local PathfindingService = require("services.PathfindingService")
    vehicle.path = PathfindingService.findVehiclePath(vehicle, vehicle.grid_anchor, destination_on_network, game)

    if not vehicle.path then
        print("ERROR: Could not find regional path to city entrance!")
        vehicle:changeState(States.Stuck, game)
        return
    end

    -- Store data needed for the return trip to the city map
    vehicle.final_destination_plot = final_destination_plot
    vehicle.destination_city_data = destination_city_data
end

function States.TravelingOnNetwork:update(dt, vehicle, game)
    if not vehicle.path or #vehicle.path == 0 then
        -- Arrived at the network exit point. Time to switch back to a local map.
        vehicle:changeState(States.ExitingNetwork, game)
        return
    end
    moveAlongPath(dt, vehicle, game)
end

--------------------------------------------------------------------------------
-- State: ExitingNetwork (Generic)
--------------------------------------------------------------------------------
States.ExitingNetwork = State:new()
States.ExitingNetwork.name = "Exiting Network"
function States.ExitingNetwork:enter(vehicle, game)
    print(string.format("DEBUG: %s %d is exiting network, returning to city logic.", vehicle.type, vehicle.id))
    
    local final_plot = vehicle.final_destination_plot
    local dest_city_data = vehicle.destination_city_data
    
    if not final_plot or not dest_city_data then
        print("ERROR: Exiting network but final_destination_plot or city_data is nil!")
        vehicle:changeState(States.Stuck, game)
        return
    end

    -- THE FIX: We must generate and use a temporary, local grid for the destination city.
    local temp_city_map = require("models.Map"):new(game.C)
    local city_w = game.C.MAP.CITY_GRID_WIDTH
    local city_h = game.C.MAP.CITY_GRID_HEIGHT
    local city_offset_x = dest_city_data.center_x - (city_w / 2)
    local city_offset_y = dest_city_data.center_y - (city_h / 2)

    -- Populate the temporary map with the destination city's grid data from the region
    for y=1, city_h do
        for x=1, city_w do
            local reg_x, reg_y = x + city_offset_x, y + city_offset_y
            if game.maps.region.grid[reg_y] and game.maps.region.grid[reg_y][reg_x] then
                temp_city_map.grid[y][x] = game.maps.region.grid[reg_y][reg_x]
            else
                temp_city_map.grid[y][x] = {type = "grass"}
            end
        end
    end
    
    -- Translate the vehicle's grid_anchor from regional coordinates back to local city coordinates.
    vehicle.grid_anchor.x = vehicle.grid_anchor.x - city_offset_x
    vehicle.grid_anchor.y = vehicle.grid_anchor.y - city_offset_y

    -- Switch the operational map and recalculate the vehicle's pixel position on the local grid.
    vehicle.operational_map_key = "city" 
    vehicle:recalculatePixelPosition(game)
    
    -- Translate the final destination plot to local coordinates.
    local local_final_plot = {
        x = final_plot.x - city_offset_x,
        y = final_plot.y - city_offset_y
    }
    
    -- Now, pathfind on the newly created local city map.
    local PathfindingService = require("services.PathfindingService")
    print(string.format("DEBUG: Finding final path on new local map to (%d, %d)", local_final_plot.x, local_final_plot.y))
    vehicle.path = PathfindingService.findVehiclePath(vehicle, vehicle.grid_anchor, local_final_plot, game)

    if not vehicle.path then
        print("ERROR: Could not find path from depot area to final destination on local map.")
        vehicle:changeState(States.Stuck, game)
        return
    end

    -- Clear the stored destination data.
    vehicle.final_destination_plot = nil
    vehicle.destination_city_data = nil
end

function States.ExitingNetwork:update(dt, vehicle, game)
     if not vehicle.path or #vehicle.path == 0 then
        -- Arrived at the final destination.
        vehicle:changeState(States.DoDropoff, game)
        return
    end
    moveAlongPath(dt, vehicle, game)
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