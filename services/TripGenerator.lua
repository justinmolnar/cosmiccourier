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
    
    -- Check if trucks exist
    local trucks_exist = false
    for _, v in ipairs(game.entities.vehicles) do
        if v.type == "truck" then
            trucks_exist = true
            break
        end
    end

    if not trucks_exist then
        return TripGenerator._createDowntownTrip(client_plot, base_payout, speed_bonus, game)
    else
        local rand = love.math.random()
        if rand < 0.5 then
            return TripGenerator._createInterCityTrip(client_plot, base_payout, speed_bonus, game)
        elseif rand < 0.75 then
            return TripGenerator._createDowntownTrip(client_plot, base_payout, speed_bonus, game)
        else
            return TripGenerator._createCityTrip(client_plot, base_payout, speed_bonus, game)
        end
    end
end

function TripGenerator._createDowntownTrip(client_plot, base_payout, speed_bonus, game)
    print("DEBUG: Creating downtown trip")
    
    local end_plot = game.maps.city:getRandomDowntownBuildingPlot()
    if not end_plot or end_plot == client_plot then
        print("DEBUG: Downtown trip failed - no valid destination, trying again next time.")
        return nil
    end
    
    print(string.format("DEBUG: Downtown trip: bike (%d,%d) -> (%d,%d)", 
          client_plot.x, client_plot.y, end_plot.x, end_plot.y))
    
    local new_trip = Trip:new(base_payout, speed_bonus)
    new_trip:addLeg(client_plot, end_plot, "bike")
    
    return new_trip
end

function TripGenerator._createCityTrip(client_plot, base_payout, speed_bonus, game)
    print("DEBUG: Creating city trip")
    local C_GAMEPLAY = game.C.GAMEPLAY

    local start_plot = game.maps.city:getRandomDowntownBuildingPlot()
    local destination_plot = game.maps.city:getRandomCityBuildingPlot()
    
    if not start_plot or not destination_plot or not game.entities.depot_plot then
        print("DEBUG: City trip creation failed - missing plots.")
        return nil
    end

    -- Increase payout for a longer trip
    base_payout = base_payout * C_GAMEPLAY.CITY_TRIP_PAYOUT_MULTIPLIER
    speed_bonus = speed_bonus * C_GAMEPLAY.CITY_TRIP_BONUS_MULTIPLIER

    local new_trip = Trip:new(base_payout, speed_bonus)
    new_trip.is_long_distance = false -- Explicitly not long distance
    
    -- Leg 1: Bike from client to depot
    new_trip:addLeg(start_plot, game.entities.depot_plot, "bike")
    -- Leg 2: Truck from depot to city destination
    new_trip:addLeg(game.entities.depot_plot, destination_plot, "truck")
    
    print("DEBUG: City trip created (Bike -> Depot -> Truck)")
    return new_trip
end

function TripGenerator._createInterCityTrip(client_plot, base_payout, speed_bonus, game)
    print("DEBUG: Creating INTER-CITY trip")
    local C_GAMEPLAY = game.C.GAMEPLAY
    local MapGenerationService = require("services.MapGenerationService")

    local start_plot = game.maps.city:getRandomDowntownBuildingPlot()
    
    -- THE FIX: Get a plot from the destination city's pre-generated data.
    -- This plot will have coordinates that are LOCAL to that city's grid.
    local final_destination_plot = MapGenerationService.getPlotInAnotherCity(game, 1)

    if not start_plot or not final_destination_plot or not game.entities.depot_plot then
        print("DEBUG: Inter-city trip creation failed - missing plots or not enough cities.")
        return nil
    end

    -- Significantly increase payout for long-distance trips
    base_payout = base_payout * C_GAMEPLAY.CITY_TRIP_PAYOUT_MULTIPLIER * 5 
    speed_bonus = speed_bonus * C_GAMEPLAY.CITY_TRIP_BONUS_MULTIPLIER * 5

    local new_trip = Trip:new(base_payout, speed_bonus)
    new_trip.is_long_distance = true -- CRITICAL FLAG
    
    -- Build the multi-leg itinerary
    new_trip:addLeg(start_plot, game.entities.depot_plot, "bike")
    -- The final destination plot is now correctly local to the destination city.
    new_trip:addLeg(game.entities.depot_plot, final_destination_plot, "truck")

    print("DEBUG: Inter-city trip created to a new city with a LOCAL destination plot.")
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