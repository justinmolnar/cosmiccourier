-- services/TripGenerator.lua
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
    
    if should_create_city_trip then
        return TripGenerator._createCityTrip(client_plot, base_payout, speed_bonus, game)
    else
        return TripGenerator._createLocalTrip(client_plot, base_payout, speed_bonus, game)
    end
end

function TripGenerator._shouldCreateCityTrip(game)
    -- Check if trucks exist
    local trucks_exist = false
    for _, v in ipairs(game.entities.vehicles) do
        if v.type == "truck" then
            trucks_exist = true
            break
        end
    end
    
    return trucks_exist and love.math.random() < 0.3
end

function TripGenerator._createCityTrip(client_plot, base_payout, speed_bonus, game)
    local C_GAMEPLAY = game.C.GAMEPLAY
    
    -- Use the region map to find a plot in the second city
    local destination_plot = game.maps.region:getRandomBuildingPlot()
    
    -- Failsafe: if for some reason we can't get a plot from the region map, create a local trip instead.
    if not destination_plot or destination_plot == client_plot then
        return TripGenerator._createLocalTrip(client_plot, base_payout, speed_bonus, game)
    end
    
    print("TripGenerator: Created a long-distance (inter-city) trip!")
    
    base_payout = base_payout * C_GAMEPLAY.CITY_TRIP_PAYOUT_MULTIPLIER
    speed_bonus = speed_bonus * C_GAMEPLAY.CITY_TRIP_BONUS_MULTIPLIER
    
    local new_trip = Trip:new(base_payout, speed_bonus)
    -- This flag tells the vehicle state machine to use the abstracted travel state
    new_trip.is_long_distance = true
    
    -- Leg 1: Bike from downtown client to the main city depot
    new_trip:addLeg(client_plot, game.entities.depot_plot, "bike")
    -- Leg 2: Truck from the main city depot to the other city's depot (destination_plot)
    new_trip:addLeg(game.entities.depot_plot, destination_plot, "truck")
    
    return new_trip
end

function TripGenerator._createLocalTrip(client_plot, base_payout, speed_bonus, game)
    -- MODIFIED: Use game.maps.city
    local end_plot = game.maps.city:getRandomDowntownBuildingPlot()
    if not end_plot then
        return nil
    end
    
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