-- services/TripGenerator.lua with debug logging
local Trip = require("models.Trip")
local GameplayConfig = require("data.GameplayConfig")

local TripGenerator = {}

-- Maps trip type string → creator function.
-- Adding a new trip type is adding one entry here and one entry in getAvailableTripTypes.
local TRIP_CREATORS = {
    downtown = function(client_plot, base_payout, speed_bonus, game)
        return TripGenerator._createDowntownTrip(client_plot, base_payout, speed_bonus, game)
    end,
    city = function(client_plot, base_payout, speed_bonus, game)
        return TripGenerator._createCityTrip(client_plot, base_payout, speed_bonus, game)
    end,
    -- intercity = function(...) end  -- add here when region map is implemented
}

-- Returns a weighted list of available trip types given the current game state.
-- Branching logic lives here; generateTrip does not know which types are available.
local function getAvailableTripTypes(trucks_exist)
    if not trucks_exist then
        return { { type = "downtown", weight = 1.0 } }
    end
    return {
        { type = "downtown", weight = GameplayConfig.DOWNTOWN_TRIP_CHANCE },
        { type = "city",     weight = 1.0 - GameplayConfig.DOWNTOWN_TRIP_CHANCE },
        -- { type = "intercity", weight = ... }  -- add here when region map is implemented
    }
end

-- Picks a random entry from a weighted list { { type, weight }, ... }.
local function weightedRandom(entries)
    local total = 0
    for _, e in ipairs(entries) do total = total + e.weight end
    local r = love.math.random() * total
    local cumulative = 0
    for _, e in ipairs(entries) do
        cumulative = cumulative + e.weight
        if r <= cumulative then return e end
    end
    return entries[#entries]
end

function TripGenerator.generateTrip(client_plot, game)
    local C_GAMEPLAY = game.C.GAMEPLAY
    local upgrades = game.state.upgrades

    -- Check if we're at the trip limit
    if #game.entities.trips.pending >= upgrades.max_pending_trips then
        return nil
    end

    local base_payout = C_GAMEPLAY.BASE_TRIP_PAYOUT
    local speed_bonus = C_GAMEPLAY.INITIAL_SPEED_BONUS

    local trucks_exist = false
    for _, v in ipairs(game.entities.vehicles) do
        if v.type == "truck" then trucks_exist = true; break end
    end

    local available = getAvailableTripTypes(trucks_exist)
    local selected  = weightedRandom(available)
    local creator   = TRIP_CREATORS[selected.type]
    return creator(client_plot, base_payout, speed_bonus, game)
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


function TripGenerator.calculateNextTripTime(game)
    local C_GAMEPLAY = game.C.GAMEPLAY
    local upgrades = game.state.upgrades
    
    local min_time = C_GAMEPLAY.TRIP_GENERATION_MIN_SEC * upgrades.trip_gen_min_mult
    local max_time = C_GAMEPLAY.TRIP_GENERATION_MAX_SEC * upgrades.trip_gen_max_mult
    
    return love.math.random(min_time, max_time)
end

return TripGenerator