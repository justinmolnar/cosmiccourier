-- services/DebugTripFactory.lua
-- Debug utility: spawn trips of various geographic scopes from the selected depot.
-- Scopes: "district" | "city" | "region" | "continent" | "world"
--
-- Hierarchy (built in WorldSandboxController.sendToGame):
--   game.world_continents[continent_id].regions[region_id].cities = { cmap, ... }
--   cmap.region_id    = region_id
--   cmap.continent_id = continent_id

local DebugTripFactory = {}

local PAYOUT_MULT = { district = 1.0, city = 1.5, region = 3.0, continent = 5.0, world = 8.0 }

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function toUnified(pl, cmap)
    return { x = (cmap.world_mn_x - 1) * 3 + pl.x, y = (cmap.world_mn_y - 1) * 3 + pl.y }
end

local function randomDestInCity(cmap)
    local pl = cmap:getRandomReceivingPlot()
    if not pl then
        local bp = cmap.building_plots
        if bp and #bp > 0 then pl = bp[love.math.random(#bp)] end
    end
    return pl and toUnified(pl, cmap) or nil
end

-- All cities in the world except `exclude`.
local function allOtherCities(exclude, game)
    local out = {}
    for _, city in ipairs(game.maps.all_cities or {}) do
        if city ~= exclude then out[#out + 1] = city end
    end
    return out
end

-- All cities in the same region as `origin_city`, except itself.
local function citiesInRegion(origin_city, game)
    local cont = game.world_continents
        and game.world_continents[origin_city.continent_id]
    local reg  = cont and cont.regions[origin_city.region_id]
    if not reg then return {} end
    local out = {}
    for _, city in ipairs(reg.cities) do
        if city ~= origin_city then out[#out + 1] = city end
    end
    return out
end

-- All cities on the same continent as `origin_city`, in a different region.
local function citiesInContinent(origin_city, game)
    local cont = game.world_continents
        and game.world_continents[origin_city.continent_id]
    if not cont then return {} end
    local out = {}
    for rid, reg in pairs(cont.regions) do
        if rid ~= origin_city.region_id then
            for _, city in ipairs(reg.cities) do
                out[#out + 1] = city
            end
        end
    end
    return out
end

-- Cities on a different continent entirely.
local function citiesOnOtherContinents(origin_city, game)
    local out = {}
    for cid, cont in pairs(game.world_continents or {}) do
        if cid ~= origin_city.continent_id then
            for _, reg in pairs(cont.regions) do
                for _, city in ipairs(reg.cities) do
                    out[#out + 1] = city
                end
            end
        end
    end
    return out
end

local function pickRandom(t)
    if #t == 0 then return nil end
    return t[love.math.random(#t)]
end

-- ── Public API ────────────────────────────────────────────────────────────────

function DebugTripFactory.pickDestination(scope, depot, game)
    local origin_city = depot:getCity(game)
    if not origin_city then return nil end

    if scope == "district" then
        local district = depot:getDistrict(game)
        local pl = district and origin_city:getRandomBuildingPlotForDistrict(district, "can_receive")
        if not pl then pl = origin_city:getRandomReceivingPlot() end
        return pl and toUnified(pl, origin_city) or nil

    elseif scope == "city" then
        return randomDestInCity(origin_city)

    elseif scope == "region" then
        local pool = citiesInRegion(origin_city, game)
        local city = pickRandom(pool)
        if city then
            return randomDestInCity(city)
        else
            -- Only one city in this region — intra-city trip instead
            return randomDestInCity(origin_city)
        end

    elseif scope == "continent" then
        local pool = citiesInContinent(origin_city, game)
        local city = pickRandom(pool)
        if city then
            return randomDestInCity(city)
        else
            -- Whole continent is one region — pick any other city
            city = pickRandom(allOtherCities(origin_city, game))
            return city and randomDestInCity(city) or randomDestInCity(origin_city)
        end

    elseif scope == "world" then
        local pool = citiesOnOtherContinents(origin_city, game)
        if #pool == 0 then pool = allOtherCities(origin_city, game) end
        local city = pickRandom(pool)
        return city and randomDestInCity(city) or randomDestInCity(origin_city)
    end

    return nil
end

-- Look up the district name for a unified-coord plot on a given city map.
local function plotDistrict(plot, cmap, game)
    if not cmap or not cmap.district_map or not cmap.district_types then return nil end
    local sub_w = (game.world_w or 0) * 3
    if sub_w == 0 then return nil end
    local sci = (plot.y - 1) * sub_w + plot.x
    local poi = cmap.district_map[sci]
    return poi and cmap.district_types[poi]
end

-- Pick a client plot that belongs to the depot's city (and ideally its district).
local function pickClientPlot(depot, game)
    local origin_city    = depot:getCity(game)
    local depot_district = depot:getDistrict(game)

    local same_district = {}
    local same_city     = {}
    for _, client in ipairs(game.entities.clients or {}) do
        if client.city_map == origin_city then
            same_city[#same_city + 1] = client
            if depot_district and plotDistrict(client.plot, origin_city, game) == depot_district then
                same_district[#same_district + 1] = client
            end
        end
    end

    local pool = same_district  -- origin must be in the depot's own district
    local c    = pickRandom(pool)
    return c and c.plot or nil
end

function DebugTripFactory.create(scope, depot, game)
    local Trip = require("models.Trip")
    if not depot then return nil end

    -- Origin: a client in the depot's city/district, falling back to depot plot.
    local src  = pickClientPlot(depot, game) or depot.plot
    if not src then return nil end

    local dest = DebugTripFactory.pickDestination(scope, depot, game)
    if not dest then return nil end
    if dest.x == src.x and dest.y == src.y then return nil end

    local base  = math.floor((game.C.GAMEPLAY.BASE_TRIP_PAYOUT or 200) * (PAYOUT_MULT[scope] or 1))
    local bonus = game.C.GAMEPLAY.INITIAL_SPEED_BONUS or 100

    local t = Trip:new(base, bonus)
    t.scope = scope
    t:addLeg(src, dest, 1, "road")
    return t
end

return DebugTripFactory
