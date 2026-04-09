-- services/CityStreetService.lua
-- Portable zone-boundary street generator: assigns world cells to zone blocks,
-- draws streets wherever adjacent cells cross zone boundaries.
-- Zero love.* imports. Zero game references (reads static data.zones only).

local ZT = require("data.zones")

local CityStreetService = {}

-- World cells per block side — controls block coarseness.
-- Streets appear wherever two adjacent world cells belong to blocks of
-- DIFFERENT zone type, giving SimCity-style irregular block layouts.
local ZONE_BLOCK = 2

-- Generate streets for a single city.
local function genStreetsForCity(city_idx, bounds, pois, district_map, w, h)
    if not bounds or not pois or #pois == 0 then return {v={},h={}} end

    local sw = w * 3
    local ZONE_STATES = {}
    for _, s in ipairs(ZT.STATES) do
        if s ~= "none" then ZONE_STATES[#ZONE_STATES + 1] = s end
    end

    local function sci_of(gscx, gscy) return gscy * sw + gscx + 1 end
    local function get_poi(wx, wy)
        if not district_map then return 0 end
        return district_map[sci_of((wx-1)*3+1, (wy-1)*3+1)] or 0
    end

    -- Deterministic district type for a poi index (mirrors sendToGame logic)
    local RDTYPES = ZT.RANDOM_DISTRICT_TYPES
    local function poi_dtype(poi_idx)
        if poi_idx <= 1 then return "downtown" end
        return RDTYPES[((city_idx * 7 + poi_idx * 13) % #RDTYPES) + 1]
    end

    -- Cache: zone type per (block_x, block_y, poi_idx) triple
    local block_cache = {}
    local function block_zone(bx, by, poi_idx)
        local key = bx * 1000000 + by * 1000 + poi_idx
        if block_cache[key] then return block_cache[key] end
        local dtype   = poi_dtype(poi_idx)
        local weights = ZT.DISTRICT_WEIGHTS[dtype] or ZT.DISTRICT_WEIGHTS["residential"]
        local total   = 0
        for _, z in ipairs(ZONE_STATES) do total = total + (weights[z] or 0) end
        -- Deterministic positional hash (no love.math.random dependency)
        local r = ((bx * 741455 + by * 1234577 + bx * by * 89137 + poi_idx * 531731) % 100000)
                  / 100000.0 * total
        if r < 0 then r = r + total end
        local zone = ZONE_STATES[#ZONE_STATES]
        local cum  = 0
        for _, z in ipairs(ZONE_STATES) do
            cum = cum + (weights[z] or 0)
            if r < cum then zone = z; break end
        end
        block_cache[key] = zone
        return zone
    end

    local function cell_zone(cx, cy)
        local bx = math.floor((cx - 1) / ZONE_BLOCK)
        local by = math.floor((cy - 1) / ZONE_BLOCK)
        return block_zone(bx, by, get_poi(cx, cy))
    end

    local sv, sh = {}, {}
    for ci in pairs(bounds) do
        local cx = (ci-1) % w + 1
        local cy = math.floor((ci-1) / w) + 1
        local z1 = cell_zone(cx, cy)

        -- Vertical boundary: right edge of (cx,cy) / left edge of (cx+1,cy)
        if cx < w then
            local r_ci = (cy-1)*w + (cx+1)
            if bounds[r_ci] and cell_zone(cx+1, cy) ~= z1 then
                sv[cx * 1000 + cy] = true
            end
        end
        -- Horizontal boundary: bottom of (cx,cy) / top of (cx,cy+1)
        if cy < h then
            local b_ci = cy*w + cx
            if bounds[b_ci] and cell_zone(cx, cy+1) ~= z1 then
                sh[cy * 1000 + cx] = true
            end
        end
    end

    return {v=sv, h=sh}
end

-- Generate street maps for all cities.
-- Returns: city_street_maps ([city_idx] = {v={...}, h={...}})
function CityStreetService.genAllStreets(
    city_locations, city_bounds_list, city_pois_list, city_district_maps, w, h
)
    local maps = {}
    for idx = 1, #(city_locations or {}) do
        local bounds   = city_bounds_list   and city_bounds_list[idx]
        local pois     = city_pois_list     and city_pois_list[idx]
        local dist_map = city_district_maps and city_district_maps[idx]
        maps[idx] = genStreetsForCity(idx, bounds, pois, dist_map, w, h)
    end
    return maps
end

return CityStreetService
