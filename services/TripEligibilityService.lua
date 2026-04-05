-- services/TripEligibilityService.lua
-- Single authority for trip assignment eligibility.

local TripEligibilityService = {}

-- Returns the city map that contains the given unified-coord plot.
-- Falls back to game.maps.city if no unified map exists or no match found.
local function getCityMapForPlot(plot, game)
    if not game.maps.unified then return game.maps.city end
    for key, m in pairs(game.maps) do
        if m.world_mn_x and m.city_grid_width then
            local ox = (m.world_mn_x - 1) * 3
            local oy = (m.world_mn_y - 1) * 3
            if plot.x > ox and plot.x <= ox + m.city_grid_width and
               plot.y > oy and plot.y <= oy + m.city_grid_height then
                return m
            end
        end
    end
    return game.maps.city
end

local function isInDistrict(plot, city_map)
    if not city_map or not city_map.downtown_offset then return false end
    local ox = city_map.world_mn_x and (city_map.world_mn_x - 1) * 3 or 0
    local oy = city_map.world_mn_y and (city_map.world_mn_y - 1) * 3 or 0
    local x_min = ox + city_map.downtown_offset.x
    local y_min = oy + city_map.downtown_offset.y
    local x_max = x_min + city_map.downtown_grid_width
    local y_max = y_min + city_map.downtown_grid_height
    return plot.x >= x_min and plot.x < x_max and plot.y >= y_min and plot.y < y_max
end

local function isInCity(plot, city_map)
    if not city_map then return false end
    if not city_map.world_mn_x then return true end  -- single-city mode
    local ox = (city_map.world_mn_x - 1) * 3
    local oy = (city_map.world_mn_y - 1) * 3
    return plot.x > ox and plot.x <= ox + city_map.city_grid_width and
           plot.y > oy and plot.y <= oy + city_map.city_grid_height
end

-- Returns true if vehicle can be assigned the given trip right now.
function TripEligibilityService.canAssign(vehicle, trip, game)
    local leg = trip.legs[trip.current_leg]
    if not leg then return false end

    local vcfg = game.C.VEHICLES[vehicle.type_upper]
    if not vcfg then return false end

    -- 1. Cargo capacity
    if vehicle:getEffectiveCapacity(game) < (leg.cargo_size or 1) then
        return false
    end

    -- 2. Zone restriction — both leg endpoints must be within the vehicle's zone.
    -- A bike can carry downtown→depot (both in district). It cannot carry depot→far city.
    local zone = vcfg.locked_to_zone
    if zone then
        local home = getCityMapForPlot(game.entities.depot_plot, game)
        local a, b = leg.start_plot, leg.end_plot
        if zone == "district" then
            if not isInDistrict(a, home) or not isInDistrict(b, home) then
                return false
            end
        elseif zone == "city" then
            if not isInCity(a, home) or not isInCity(b, home) then
                return false
            end
        end
    end

    -- 3. Transport mode
    if vcfg.transport_mode ~= (leg.transport_mode or "road") then
        return false
    end

    return vehicle:isAvailable(game)
end

return TripEligibilityService
