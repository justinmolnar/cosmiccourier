-- services/NameContextService.lua
-- Builds a {tags, slots} context profile for a named entity. Consumed by
-- NameService.generate to pick / fill a template.
--
-- Purely derivative — reads existing world data, never generates names or
-- rolls dice. The NameService does all randomness; this service is
-- deterministic given the same world state.

local NameContextService = {}

local Tags = require("data.names.tags")
local DistrictStems = require("data.names.pools.district_stems")
local Climate       = require("data.names.pools.climate")
local Geography     = require("data.names.pools.geography")

-- ─── Tile-type constants (mirror services/GameBridgeService.lua) ─────────────
local TILE = {
    grass = 0, road = 1, downtown_road = 2, arterial = 3, highway = 4,
    water = 5, mountain = 6, river = 7, plot = 8, downtown_plot = 9,
    coastal_water = 10, deep_water = 11, open_ocean = 12,
}

-- ─── Small helpers ───────────────────────────────────────────────────────────

-- `rng` is an optional callable matching love.math.random's (lo, hi) signature.
-- Defaulting to love.math.random keeps backwards-compat for runtime callers
-- that don't care about determinism. The naming pass passes a dedicated rng
-- so its picks are independent of the global RNG state.
local function pickFromPool(pool, rng)
    if not pool or #pool == 0 then return nil end
    rng = rng or love.math.random
    return pool[rng(1, #pool)]
end

local function climateFromTemp(temp)
    local T = Tags.thresholds
    if not temp then return "temperate" end
    if temp <= T.climate_cold_max then return "cold" end
    if temp >= T.climate_hot_min  then return "hot"  end
    return "temperate"
end

-- Tally the most-common value in a table-keyed-by-something or a flat array.
-- Returns (key, count) for the max entry, or (nil, 0) if empty.
local function mode(tally)
    local best_k, best_n = nil, 0
    for k, n in pairs(tally) do
        if n > best_n then best_k, best_n = k, n end
    end
    return best_k, best_n
end

-- ─── Continent ───────────────────────────────────────────────────────────────

function NameContextService.forContinent(continent, game, rng)
    local tags, slots = {}, {}
    local T = Tags.thresholds

    if continent.frac then
        if continent.frac <= T.continent_small_max_frac then tags.size_small = true end
        if continent.frac >= T.continent_large_min_frac then tags.size_large = true end
    end

    -- Feature tags come from whatever the worldgen pass attached (optional).
    if continent.mountainous then tags.mountainous = true end
    if continent.forest      then tags.forest      = true end
    if continent.desert      then tags.desert      = true end
    if continent.cold        then tags.cold        = true end
    if continent.hot         then tags.hot         = true end

    slots.climate_adj          = pickFromPool(Climate[tags.cold and "cold" or tags.hot and "hot" or "temperate"], rng)
    slots.highland_descriptor  = pickFromPool(Geography.highland, rng)
    slots.lowland_descriptor   = pickFromPool(Geography.lowland,  rng)
    slots.forest_descriptor    = pickFromPool(Geography.forest,   rng)
    slots.desert_descriptor    = pickFromPool(Geography.desert,   rng)

    return { tags = tags, slots = slots }
end

-- ─── Region ──────────────────────────────────────────────────────────────────

function NameContextService.forRegion(region, game, rng)
    local tags, slots = {}, {}

    if region.continent_name then
        tags.has_continent_name = true
        slots.continent_name    = region.continent_name
    end

    if region.mountainous then tags.mountainous = true end
    if region.forest      then tags.forest      = true end
    if region.desert      then tags.desert      = true end
    if region.coastal     then tags.coastal     = true end
    if region.near_lake   then tags.near_lake   = true end
    if region.near_river  then tags.near_river  = true end
    if region.cold        then tags.cold        = true end
    if region.hot         then tags.hot         = true end
    if region.lowland     then tags.lowland     = true end

    slots.climate_adj          = pickFromPool(Climate[tags.cold and "cold" or tags.hot and "hot" or "temperate"], rng)
    slots.highland_descriptor  = pickFromPool(Geography.highland, rng)
    slots.lowland_descriptor   = pickFromPool(Geography.lowland,  rng)
    slots.forest_descriptor    = pickFromPool(Geography.forest,   rng)
    slots.desert_descriptor    = pickFromPool(Geography.desert,   rng)

    return { tags = tags, slots = slots }
end

-- ─── City ────────────────────────────────────────────────────────────────────

-- Scan the unified FFI grid around a world-coord point to detect water
-- proximity. Returns {coastal, near_water} booleans.
local function detectCityWater(city_map, game)
    local umap = game.maps and game.maps.unified
    if not (umap and umap.ffi_grid and umap._w and umap._h) then
        return { coastal = false, near_water = false }
    end
    local R = Tags.thresholds.adjacency_search_radius
    local ox = (city_map.world_mn_x - 1) * 3
    local oy = (city_map.world_mn_y - 1) * 3
    local gw = (city_map.grid and #(city_map.grid[1] or {})) or 0
    local gh = (city_map.grid and #city_map.grid) or 0
    local x0, x1 = math.max(1, ox - R), math.min(umap._w, ox + gw + R)
    local y0, y1 = math.max(1, oy - R), math.min(umap._h, oy + gh + R)
    local coastal, near_water = false, false
    for y = y0, y1 do
        local base = (y - 1) * umap._w
        for x = x0, x1 do
            local t = umap.ffi_grid[base + (x - 1)].type
            if t == TILE.coastal_water or t == TILE.deep_water or t == TILE.open_ocean then
                coastal = true
            elseif t == TILE.water or t == TILE.river then
                near_water = true
            end
            if coastal and near_water then return { coastal = true, near_water = true } end
        end
    end
    return { coastal = coastal, near_water = near_water }
end

-- Tally dominant district id across the city's district_map.
local function dominantDistrict(city_map)
    local dmap, dtypes = city_map.district_map, city_map.district_types
    if not dmap or not dtypes then return nil end
    local tally = {}
    for _, poi_idx in pairs(dmap) do
        local id = dtypes[poi_idx]
        if id then tally[id] = (tally[id] or 0) + 1 end
    end
    local best = mode(tally)
    return best
end

-- Pull the parent region and continent names off the world hierarchy.
local function parentNames(city_map, game)
    local rid = city_map.region_id
    local cid = city_map.continent_id
    local rby = game.world_regions_by_id
    local cby = game.world_continents_by_id
    local region_name    = rby and rid and rby[rid] and rby[rid].name or nil
    local continent_name = cby and cid and cby[cid] and cby[cid].name or nil
    return region_name, continent_name
end

function NameContextService.forCity(city_map, game, rng)
    local tags, slots = {}, {}

    local water = detectCityWater(city_map, game)
    if water.coastal    then tags.coastal    = true end
    if water.near_water then
        -- We can't cheaply separate lake vs river — treat as near_lake for
        -- naming flavour (plan acknowledges this simplification).
        tags.near_lake  = true
    end

    local region_name, continent_name = parentNames(city_map, game)
    if region_name    then tags.has_region_name    = true; slots.region_name    = region_name end
    if continent_name then tags.has_continent_name = true; slots.continent_name = continent_name end

    local dd = dominantDistrict(city_map)
    if dd then
        tags.dominant_district = dd
        local stem = DistrictStems[dd]
        if stem then slots.district_stem = stem.stem end
    end

    -- Climate: derive from city's own biome data if available. biome_data is
    -- a flat map indexed by i = (y-1)*world_w + x.
    local temp
    if city_map.world_biome_data and city_map.world_mn_x then
        local bd = city_map.world_biome_data
        local ww = city_map.world_w or game.world_w or 1
        local cx = city_map.world_mn_x + math.floor((city_map.city_grid_width  or 3) / 6)
        local cy = city_map.world_mn_y + math.floor((city_map.city_grid_height or 3) / 6)
        local i  = (cy - 1) * ww + cx
        if bd[i] and bd[i].temp then temp = bd[i].temp end
    end
    local climate = climateFromTemp(temp)
    if climate ~= "temperate" then tags[climate] = true end
    slots.climate_adj = pickFromPool(Climate[climate], rng)

    return { tags = tags, slots = slots }
end

-- ─── Building (client / depot / placed) ─────────────────────────────────────

-- Look up the district of a specific plot inside a city.
local function plotDistrict(city_map, plot_x, plot_y, game)
    if not (city_map.district_map and city_map.district_types) then return nil end
    local sub_w = (game.world_w or 0) * 3
    if sub_w == 0 then return nil end
    local sci = (plot_y - 1) * sub_w + plot_x
    local poi_idx = city_map.district_map[sci]
    if poi_idx then return city_map.district_types[poi_idx] end
    return nil
end

-- Probe a few sub-cells around (px, py) in the unified FFI grid.
local function detectBuildingWater(px, py, game)
    local umap = game.maps and game.maps.unified
    if not (umap and umap.ffi_grid and umap._w and umap._h) then
        return { coastal = false, near_water = false }
    end
    local R = Tags.thresholds.adjacency_search_radius
    local x0, x1 = math.max(1, px - R), math.min(umap._w, px + R)
    local y0, y1 = math.max(1, py - R), math.min(umap._h, py + R)
    local coastal, near_water = false, false
    for y = y0, y1 do
        local base = (y - 1) * umap._w
        for x = x0, x1 do
            local t = umap.ffi_grid[base + (x - 1)].type
            if t == TILE.coastal_water or t == TILE.deep_water or t == TILE.open_ocean then
                coastal = true
            elseif t == TILE.water or t == TILE.river then
                near_water = true
            end
            if coastal and near_water then return { coastal = true, near_water = true } end
        end
    end
    return { coastal = coastal, near_water = near_water }
end

-- Build a building-scope context. The caller supplies the parent city_map
-- explicitly so it works for clients, depots, and placed buildings uniformly.
function NameContextService.forBuilding(plot, city_map, game, kind_override, rng)
    local tags, slots = {}, {}

    if city_map then
        local city_ctx = NameContextService.forCity(city_map, game, rng)
        -- Inherit city-level tags/slots as the starting point.
        for k, v in pairs(city_ctx.tags  or {}) do tags[k]  = v end
        for k, v in pairs(city_ctx.slots or {}) do slots[k] = v end

        if city_map.name then
            tags.has_city_name = true
            slots.city_name    = city_map.name
        end
    end

    -- Local district (overrides city-level dominant_district feel for this building).
    if plot and city_map then
        local district_id = plotDistrict(city_map, plot.x, plot.y, game)
        if district_id then
            tags.in_district = district_id
            local stem = DistrictStems[district_id]
            if stem then slots.district_descriptor = stem.adj end
        end

        -- Local water adjacency can override the city-level flag.
        local water = detectBuildingWater(plot.x, plot.y, game)
        if water.coastal    then tags.coastal   = true end
        if water.near_water then tags.near_lake = true end
    end

    if kind_override then slots.kind = kind_override end

    return { tags = tags, slots = slots }
end

return NameContextService
