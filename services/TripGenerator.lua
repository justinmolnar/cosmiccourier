-- services/TripGenerator.lua with debug logging
local Trip = require("models.Trip")

local TripGenerator = {}

function TripGenerator.generateTrip(client_plot, game)
    local C_GAMEPLAY = game.C.GAMEPLAY
    local upgrades = game.state.upgrades
    
    -- Check if we're at the trip limit
    if #game.entities.trips.pending >= upgrades.max_pending_trips then
        return nil
    end
    
    local base_payout = C_GAMEPLAY.BASE_TRIP_PAYOUT
    local speed_bonus = C_GAMEPLAY.INITIAL_SPEED_BONUS
    
    -- Determine if this should be a multi-leg city trip
    local should_create_city_trip = TripGenerator._shouldCreateCityTrip(game)
    
    print(string.format("DEBUG: Generating trip - should_create_city_trip: %s", tostring(should_create_city_trip)))
    
    if should_create_city_trip then
        return TripGenerator._createCityTrip(client_plot, base_payout, speed_bonus, game)
    else
        return TripGenerator._createLocalTrip(client_plot, base_payout, speed_bonus, game)
    end
end

function TripGenerator._shouldCreateCityTrip(game)
    -- Check if trucks exist
    local trucks_exist = false
    local truck_count = 0
    for _, v in ipairs(game.entities.vehicles) do
        if v.type == "truck" then
            trucks_exist = true
            truck_count = truck_count + 1
        end
    end
    
    local should_create = trucks_exist and love.math.random() < 0.3
    print(string.format("DEBUG: City trip check - trucks_exist: %s (count: %d), random < 0.3: %s, result: %s", 
          tostring(trucks_exist), truck_count, tostring(love.math.random() < 0.3), tostring(should_create)))
    
    return should_create
end

function TripGenerator._createCityTrip(client_plot, base_payout, speed_bonus, game)
    local C_GAMEPLAY = game.C.GAMEPLAY
    
    print("DEBUG: Starting city trip creation")
    
    -- FIX: For now, only create trips within the same city (downtown → city outskirts)
    -- Use the city map to find a plot outside of downtown instead of the region map
    local destination_plot = game.maps.city:getRandomCityBuildingPlot()
    
    -- DEBUG: Log destination plot details
    print(string.format("DEBUG: City map destination_plot: (%d,%d)", 
          destination_plot and destination_plot.x or -1, 
          destination_plot and destination_plot.y or -1))
    
    -- Failsafe: if for some reason we can't get a plot from the city map, create a local trip instead.
    if not destination_plot or destination_plot == client_plot then
        print("DEBUG: City trip failed - no valid destination or same as client, creating local trip instead")
        return TripGenerator._createLocalTrip(client_plot, base_payout, speed_bonus, game)
    end
    
    -- Check if depot exists
    if not game.entities.depot_plot then
        print("DEBUG: City trip failed - no depot_plot available")
        return TripGenerator._createLocalTrip(client_plot, base_payout, speed_bonus, game)
    end
    
    print("DEBUG: Created intra-city trip (downtown to city outskirts)!")
    
    base_payout = base_payout * C_GAMEPLAY.CITY_TRIP_PAYOUT_MULTIPLIER
    speed_bonus = speed_bonus * C_GAMEPLAY.CITY_TRIP_BONUS_MULTIPLIER
    
    print(string.format("DEBUG: City trip payout: base=%d, speed_bonus=%d", base_payout, speed_bonus))
    
    local new_trip = Trip:new(base_payout, speed_bonus)
    -- FIX: This is no longer a long distance trip since it's within the same city
    -- new_trip.is_long_distance = true -- REMOVED
    
    -- Leg 1: Bike from downtown client to the main city depot
    new_trip:addLeg(client_plot, game.entities.depot_plot, "bike")
    -- Leg 2: Truck from the main city depot to city outskirts (within same city)
    new_trip:addLeg(game.entities.depot_plot, destination_plot, "truck")
    
    print(string.format("DEBUG: Trip legs created:"))
    print(string.format("  Leg 1: bike (%d,%d) -> (%d,%d)", 
          client_plot.x, client_plot.y, 
          game.entities.depot_plot.x, game.entities.depot_plot.y))
    print(string.format("  Leg 2: truck (%d,%d) -> (%d,%d)", 
          game.entities.depot_plot.x, game.entities.depot_plot.y,
          destination_plot.x, destination_plot.y))
    print(string.format("  is_long_distance: %s", tostring(new_trip.is_long_distance)))
    
    return new_trip
end

function TripGenerator._createLocalTrip(client_plot, base_payout, speed_bonus, game)
    print("DEBUG: Creating local trip")
    
    -- MODIFIED: Use game.maps.city
    local end_plot = game.maps.city:getRandomDowntownBuildingPlot()
    if not end_plot then
        print("DEBUG: Local trip failed - no end plot available")
        return nil
    end
    
    print(string.format("DEBUG: Local trip: bike (%d,%d) -> (%d,%d)", 
          client_plot.x, client_plot.y, end_plot.x, end_plot.y))
    
    local new_trip = Trip:new(base_payout, speed_bonus)
    new_trip:addLeg(client_plot, end_plot, "bike")
    
    return new_trip
end

function TripGenerator.calculateNextTripTime(game)
    local C_GAMEPLAY = game.C.GAMEPLAY
    local upgrades = game.state.upgrades
    
    local min_time = C_GAMEPLAY.TRIP_GENERATION_MIN_SEC * upgrades.trip_gen_min_mult
    local max_time = C_GAMEPLAY.TRIP_GENERATION_MAX_SEC * upgrades.trip_gen_max_mult
    
    return love.math.random(min_time, max_time)
end

return TripGenerator