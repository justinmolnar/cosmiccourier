-- services/TripGenerator.lua
local Trip = require("models.Trip")
local GameplayConfig = require("data.GameplayConfig")

local TripGenerator = {}

-- Resolve the district name for a unified-coord plot on the given city map.
local function plotDistrict(plot, cmap)
    if not cmap or not cmap.district_map or not cmap.district_types then return nil end
    local sub_w = (cmap.world_w or 1) * 3
    local sci   = (plot.y - 1) * sub_w + plot.x
    local poi   = cmap.district_map[sci]
    return poi and cmap.district_types[poi]
end

local function toUnified(plot, cmap)
    return { x = (cmap.world_mn_x - 1) * 3 + plot.x, y = (cmap.world_mn_y - 1) * 3 + plot.y }
end

function TripGenerator.generateTrip(client_plot, game, city_map)
    local C_GAMEPLAY = game.C.GAMEPLAY
    local upgrades   = game.state.upgrades

    if #game.entities.trips.pending >= upgrades.max_pending_trips then return nil end

    local cmap        = city_map or game.maps.city
    local base_payout = C_GAMEPLAY.BASE_TRIP_PAYOUT
    local speed_bonus = C_GAMEPLAY.INITIAL_SPEED_BONUS

    -- Destination: same district as client, must be a can_receive zone.
    local district   = plotDistrict(client_plot, cmap)
    local dest_local = district and cmap:getRandomBuildingPlotForDistrict(district, "can_receive")
                       or cmap:getRandomReceivingPlot()
    if not dest_local then return nil end

    local dest_plot = toUnified(dest_local, cmap)
    if dest_plot.x == client_plot.x and dest_plot.y == client_plot.y then return nil end

    local new_trip = Trip:new(base_payout, speed_bonus)
    new_trip.scope = "district"
    new_trip:addLeg(client_plot, dest_plot, 1, "road")
    return new_trip
end

function TripGenerator.calculateNextTripTime(game)
    local C_GAMEPLAY = game.C.GAMEPLAY
    local upgrades   = game.state.upgrades
    local min_time   = C_GAMEPLAY.TRIP_GENERATION_MIN_SEC * upgrades.trip_gen_min_mult
    local max_time   = C_GAMEPLAY.TRIP_GENERATION_MAX_SEC * upgrades.trip_gen_max_mult
    return love.math.random(min_time, max_time)
end

return TripGenerator
