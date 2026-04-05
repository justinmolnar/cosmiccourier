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

    -- City trips only spawn once a vehicle exists that can leave its district.
    local city_trips_available = false
    for _, v in ipairs(game.entities.vehicles) do
        local vcfg = game.C.VEHICLES[v.type_upper]
        if vcfg and vcfg.locked_to_zone ~= "district" then
            city_trips_available = true
            break
        end
    end

    local available = getAvailableTripTypes(city_trips_available)
    local selected  = weightedRandom(available)
    local creator   = TRIP_CREATORS[selected.type]
    return creator(client_plot, base_payout, speed_bonus, game)
end

local function toUnified(plot, cmap)
    return { x = (cmap.world_mn_x - 1) * 3 + plot.x, y = (cmap.world_mn_y - 1) * 3 + plot.y }
end

function TripGenerator._createDowntownTrip(client_plot, base_payout, speed_bonus, game)
    local cmap = game.maps.city
    local end_plot_local = cmap:getRandomDowntownBuildingPlot()
    if not end_plot_local then return nil end
    local end_plot = toUnified(end_plot_local, cmap)
    if end_plot.x == client_plot.x and end_plot.y == client_plot.y then return nil end

    local new_trip = Trip:new(base_payout, speed_bonus)
    new_trip:addLeg(client_plot, end_plot, 1, "road")

    return new_trip
end

function TripGenerator._createCityTrip(client_plot, base_payout, speed_bonus, game)
    local C_GAMEPLAY = game.C.GAMEPLAY
    local cmap = game.maps.city

    local start_plot_local = cmap:getRandomDowntownBuildingPlot()
    local dest_plot_local  = cmap:getRandomCityBuildingPlot()

    if not start_plot_local or not dest_plot_local or not game.entities.depot_plot then
        return nil
    end

    base_payout = base_payout * C_GAMEPLAY.CITY_TRIP_PAYOUT_MULTIPLIER
    speed_bonus = speed_bonus * C_GAMEPLAY.CITY_TRIP_BONUS_MULTIPLIER

    local start_plot = toUnified(start_plot_local, cmap)
    local dest_plot  = toUnified(dest_plot_local,  cmap)

    local new_trip = Trip:new(base_payout, speed_bonus)
    -- leg 1: pickup to depot (small cargo, bike-eligible)
    new_trip:addLeg(start_plot, game.entities.depot_plot, 1, "road")
    new_trip:addLeg(game.entities.depot_plot, dest_plot, 1, "road")
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