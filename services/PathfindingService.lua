-- services/PathfindingService.lua
local WGC            = require("data.WorldGenConfig")
local IMPASSABLE     = WGC.IMPASSABLE_COST
local SNAP_CAP       = WGC.SNAP_SEARCH_CAP
local PathCacheService    = require("services.PathCacheService")
local EntranceService     = require("services.EntranceService")
local RoutePlannerService = require("services.RoutePlannerService")

-- Integer → string tile type translation for FFI grid reads.
-- Indices match TILE_INT in WorldSandboxController and C.TILE in constants.lua.
local _TILE_NAMES = {
    [0]="grass", [1]="road", [2]="downtown_road", [3]="arterial", [4]="highway",
    [5]="water",  [6]="mountain", [7]="river", [8]="plot", [9]="downtown_plot",
    [10]="coastal_water", [11]="deep_water", [12]="open_ocean",
}

local PathfindingService = {}

-- ── HPA* helpers ──────────────────────────────────────────────────────────────

-- O(1) city membership lookup for a unified sub-cell position.
local function _cityOf(ux, uy, game)
    local umap = game.maps.unified
    if not umap or not umap.world_w then return nil end
    local wx = math.ceil(ux / 3)
    local wy = math.ceil(uy / 3)
    local ci = (wy - 1) * umap.world_w + wx
    return game.hw_all_claimed and game.hw_all_claimed[ci] or nil
end

-- ── Snap helper ───────────────────────────────────────────────────────────────

-- BFS snap to nearest traversable tile on a sandbox (sub-cell) map.
-- Accepts road-type tiles AND zone_seg-adjacent cells (city streets are edges, not tiles).
local function _snapToNearestTraversable(plot, map, path_grid, grid_w, grid_h, vehicle)
    local x, y = plot.x, plot.y
    local zsv = map.zone_seg_v
    local zsh = map.zone_seg_h
    local fgi = map.ffi_grid
    local fgw = grid_w
    local function inBounds(gx, gy) return gx>=1 and gx<=grid_w and gy>=1 and gy<=grid_h end
    local function getTileType(cx, cy)
        if fgi then return _TILE_NAMES[fgi[(cy-1)*fgw + (cx-1)].type] or "grass" end
        return path_grid[cy][cx].type
    end
    local function isTraversable(cx, cy)
        if not inBounds(cx, cy) then return false end
        local t = getTileType(cx, cy)
        -- Accept any tile the vehicle can actually traverse (covers water-mode vehicles too).
        if vehicle:getMovementCostFor(t) < IMPASSABLE then return true end
        -- Street-edge adjacency: zone_seg cells are traversable for road vehicles even
        -- when their tile type is plot/downtown_plot.
        if vehicle:getMovementCostFor("road") < IMPASSABLE then
            if (zsv and zsv[cy] and (zsv[cy][cx] or zsv[cy][cx-1]))
            or (zsh and zsh[cy]   and zsh[cy][cx])
            or (zsh and zsh[cy-1] and zsh[cy-1][cx]) then
                return true
            end
        end
        return false
    end
    if isTraversable(x, y) then return {x=x, y=y} end
    local visited = {[y*10000+x] = true}
    local q, qi = {{x, y}}, 1
    while qi <= #q and qi <= SNAP_CAP do
        local cx, cy = q[qi][1], q[qi][2]; qi = qi + 1
        if isTraversable(cx, cy) then return {x=cx, y=cy} end
        for _, d in ipairs({{0,-1},{0,1},{-1,0},{1,0}}) do
            local nx, ny = cx+d[1], cy+d[2]
            local k = ny*10000+nx
            if inBounds(nx, ny) and not visited[k] then
                visited[k] = true; q[#q+1] = {nx, ny}
            end
        end
    end
    return map:findNearestRoadTile(plot)
end

-- ── Sandbox A* (used for all vehicle pathfinding on the unified map) ──────────

local function findVehiclePathSandbox(vehicle, start_node, end_plot, map, game)
    local path_grid = map.grid  -- nil for unified map (FFI); Lua table for city maps
    local grid_h = map._h or (path_grid and #path_grid or 0)
    local grid_w = map._w or (path_grid and path_grid[1] and #path_grid[1] or 0)

    -- FFI tile type read (unified map) or Lua table read (city/sandbox maps).
    local fgi = map.ffi_grid
    local fgw = grid_w
    local function getTileType(gx, gy)
        if fgi then return _TILE_NAMES[fgi[(gy-1)*fgw + (gx-1)].type] or "grass" end
        return path_grid[gy][gx].type
    end

    local start_sub = _snapToNearestTraversable(start_node, map, path_grid, grid_w, grid_h, vehicle)
    if not start_sub then return nil end

    local bounds = vehicle.pathfinding_bounds
    local zsv = map.zone_seg_v
    local zsh = map.zone_seg_h
    local function get_cost(node_x, node_y)
        if bounds and (node_x < bounds.x1 or node_x > bounds.x2
                    or node_y < bounds.y1 or node_y > bounds.y2) then
            return IMPASSABLE
        end
        local t = getTileType(node_x, node_y)
        local cost = vehicle:getMovementCostFor(t)
        -- Streets are edges (zone_seg), not cells. A cell flanking a street edge is
        -- traversable at road cost even if its tile type is plot/downtown_plot/etc.
        if cost >= IMPASSABLE and (zsv or zsh) then
            local has_edge =
                (zsv and zsv[node_y] and (zsv[node_y][node_x] or zsv[node_y][node_x-1]))
             or (zsh and zsh[node_y]   and zsh[node_y][node_x])
             or (zsh and zsh[node_y-1] and zsh[node_y-1][node_x])
            if has_edge then return vehicle:getMovementCostFor("road") end
        end
        return cost
    end

    -- end_candidates: traversable cardinal neighbours of end_plot.
    -- Uses get_cost which handles both road tiles and zone_seg edge adjacency.
    local end_candidates, seen = {}, {}
    for _, d in ipairs({{0,-1},{0,1},{-1,0},{1,0}}) do
        local nx, ny = end_plot.x + d[1], end_plot.y + d[2]
        if nx >= 1 and nx <= grid_w and ny >= 1 and ny <= grid_h then
            if get_cost(nx, ny) < IMPASSABLE then
                local key = ny * 10000 + nx
                if not seen[key] then seen[key] = true; end_candidates[#end_candidates+1] = {x=nx, y=ny} end
            end
        end
    end
    if #end_candidates == 0 then
        local fallback = _snapToNearestTraversable(end_plot, map, path_grid, grid_w, grid_h, vehicle)
        if not fallback then return nil end
        end_candidates = {fallback}
    end

    -- Proxy map: forward everything from the real map but hide road_v_rxs so
    -- the pathfinder always uses sandbox (sub-cell) neighbor logic, even for
    -- city maps that also carry road-node data.
    local sandbox_proxy = setmetatable({road_v_rxs = false}, {__index = map})

    -- ── Entrance-graph inter-city routing ────────────────────────────────────
    -- Only runs for highway-capable vehicles (bikes cannot traverse highways).
    -- Falls through to direct A* on failure or same-city trips.
    -- _cityOf falls back to original start_node in case the snap moved the vehicle
    -- onto a highway cell just outside city bounds (e.g. city boundary highway tile).
    local can_highway = vehicle:getMovementCostFor("highway") < IMPASSABLE
    local start_city  = can_highway and (_cityOf(start_sub.x, start_sub.y, game)
                                      or _cityOf(start_node.x, start_node.y, game)) or nil
    local end_city    = can_highway and _cityOf(end_plot.x, end_plot.y, game) or nil

    local mode         = vehicle.transport_mode or "road"
    local city_bounds  = game.city_sc_bounds

    local is_cross_city = start_city and end_city and start_city ~= end_city
    if is_cross_city then
        -- Cross-city routing is handled exclusively by the entrance graph.
        -- If no route exists there, the trip is unroutable — we do not fall
        -- through to a direct grid-wide A*.
        local route = game.entrance_graph and RoutePlannerService.findRouteForMode(
            start_city, start_sub, end_city, end_plot, mode, game)

        if not route or #route == 0 then
            local now = love.timer.getTime()
            local lk  = "_pf_err_" .. vehicle.id
            if not vehicle[lk] or now - vehicle[lk] > 5 then
                vehicle[lk] = now
                print(string.format(
                    "ERROR: PathfindingService - No entrance-graph route for %s %d. start_city=%d end_city=%d mode=%s",
                    vehicle.type, vehicle.id, start_city, end_city, mode))
            end
            return nil
        end

        do
            local full = {}

            -- Trunk cost: vehicle-agnostic, highway-first. Trunk paths are shared
            -- across all highway-capable vehicle types so they stay in the cache.
            local _umap = game.maps.unified
            local _tfgi = _umap and _umap.ffi_grid
            local _tgw  = _umap and _umap._w or 0
            local trunk_proxy = setmetatable({road_v_rxs = false}, {__index = _umap or map})
            local function trunk_cost(x, y)
                if not _tfgi then return IMPASSABLE end
                local ti = _tfgi[(y-1)*_tgw + (x-1)].type
                if ti == 4 then return 1 end   -- highway
                if ti == 3 then return 5 end   -- arterial
                if ti == 1 or ti == 2 then return 10 end
                return IMPASSABLE
            end

            -- Bounded-cost wrapper: clamps A* to a city's sub-cell bounding
            -- box so local tiers don't wander across the world map.
            local function _boundedGetCost(bounds)
                if not bounds then return get_cost end
                return function(x, y)
                    if x < bounds.x1 or x > bounds.x2
                    or y < bounds.y1 or y > bounds.y2 then
                        return IMPASSABLE
                    end
                    return get_cost(x, y)
                end
            end

            -- Tier 1: local out — snapped start → first entrance in the route.
            local first_e = route[1]
            local seg1 = game.pathfinder.findPath(path_grid or {}, start_sub,
                {x=first_e.ux, y=first_e.uy},
                _boundedGetCost(city_bounds and city_bounds[start_city]),
                sandbox_proxy)
            if seg1 then for _, n in ipairs(seg1) do full[#full+1] = n end end

            -- Walk the entrance sequence. Each consecutive pair is either a
            -- trunk (different cities) or an intra-city transit (same city).
            -- Both live in PathCacheService keyed by (mode, from, to); compute
            -- lazily on cache miss.
            for i = 1, #route - 1 do
                local a, b = route[i], route[i+1]
                local seg = PathCacheService.get(mode, a.ux, a.uy, b.ux, b.uy)
                if not seg then
                    seg = game.pathfinder.findPath({},
                        {x=a.ux, y=a.uy}, {x=b.ux, y=b.uy}, trunk_cost, trunk_proxy)
                    if seg then
                        PathCacheService.put(mode, a.ux, a.uy, b.ux, b.uy, seg)
                    end
                end
                if seg then for _, n in ipairs(seg) do full[#full+1] = n end end
            end

            -- Tier 4: local in — last entrance → destination.
            local last_e = route[#route]
            local local_in = PathCacheService.get(mode, last_e.ux, last_e.uy, end_plot.x, end_plot.y)
            if not local_in then
                local end_node = end_candidates[1]
                if end_node then
                    local_in = game.pathfinder.findPath(path_grid or {},
                        {x=last_e.ux, y=last_e.uy}, end_node,
                        _boundedGetCost(city_bounds and city_bounds[end_city]),
                        sandbox_proxy)
                    if local_in then
                        PathCacheService.put(mode, last_e.ux, last_e.uy, end_plot.x, end_plot.y, local_in)
                    end
                end
            end
            if local_in then for _, n in ipairs(local_in) do full[#full+1] = n end end

            if #full == 0 then return nil end
            table.remove(full, 1)  -- remove start node (vehicle already there)
            return full
        end
    end
    -- ── End entrance-graph routing ───────────────────────────────────────────

    -- Cache lookup: key on snapped start + end_plot, then try end_candidates
    local cached = PathCacheService.get(mode, start_sub.x, start_sub.y, end_plot.x, end_plot.y)
    if cached then return cached end
    for _, ec in ipairs(end_candidates) do
        cached = PathCacheService.get(mode, start_sub.x, start_sub.y, ec.x, ec.y)
        if cached then return cached end
    end

    -- For non-road vehicles (ships etc.), the standard A* uses getNeighbors which
    -- only returns road-connected cells. Pass zero turn_costs to trigger raw
    -- 4-directional grid expansion gated by the cost function.
    local turn_costs_arg = nil
    if mode ~= "road" then
        turn_costs_arg = { turn_90 = 0, turn_180 = 0 }
    end

    local best_path = nil
    for _, end_node in ipairs(end_candidates) do
        if end_node.x == start_sub.x and end_node.y == start_sub.y then return {} end
        local path = game.pathfinder.findPath(path_grid or {}, start_sub, end_node, get_cost, sandbox_proxy, turn_costs_arg)
        if path and (not best_path or #path < #best_path) then best_path = path end
    end

    if not best_path then
        -- Rate-limit pathfinding error spam (once per vehicle per 5 seconds).
        local now = love.timer.getTime()
        local lk  = "_pf_err_" .. vehicle.id
        if not vehicle[lk] or now - vehicle[lk] > 5 then
            vehicle[lk] = now
            print(string.format("ERROR: PathfindingService - No path found for %s %d. start_sub=(%d,%d) end=(%d,%d) end_candidates=%d mode=%s grid=%dx%d",
                vehicle.type, vehicle.id, start_sub.x, start_sub.y, end_plot.x, end_plot.y, #end_candidates, mode, grid_w, grid_h))
        end
        return nil
    end

    if #best_path > 0 then table.remove(best_path, 1) end
    PathCacheService.put(mode, start_sub.x, start_sub.y, end_plot.x, end_plot.y, best_path)
    return best_path
end

-- ── Public router ─────────────────────────────────────────────────────────────

function PathfindingService.findVehiclePath(vehicle, start_node, end_plot, game)
    if not start_node or not end_plot then
        print(string.format("ERROR: PathfindingService - Invalid plots for %s %d", vehicle.type, vehicle.id))
        return nil
    end
    local map = game.maps[vehicle.operational_map_key]
    if not map then
        print(string.format("ERROR: PathfindingService - Could not find operational map '%s' for vehicle %d",
            vehicle.operational_map_key, vehicle.id))
        return nil
    end
    -- Unified map uses FFI grid (map.ffi_grid); city maps use Lua grid (map.grid).
    if not map.ffi_grid and (not map.grid or #map.grid == 0) then
        print(string.format("ERROR: PathfindingService - No map grid available for %s %d", vehicle.type, vehicle.id))
        return nil
    end
    return findVehiclePathSandbox(vehicle, start_node, end_plot, map, game)
end

function PathfindingService.findPathToDepot(vehicle, game)
    return PathfindingService.findVehiclePath(vehicle, vehicle.grid_anchor, vehicle.depot_plot, game)
end

function PathfindingService.findPathToPickup(vehicle, trip, game)
    local leg = trip.legs[trip.current_leg]
    if not leg then return nil end
    return PathfindingService.findVehiclePath(vehicle, vehicle.grid_anchor, leg.start_plot, game)
end

-- Returns pixel coords for a path node on the unified (sandbox) map.
local function nodePixel(node, TPS)
    return (node.x - 0.5) * TPS, (node.y - 0.5) * TPS
end

function PathfindingService.estimatePathTravelTime(path, vehicle, game)
    if not path or #path == 0 then return 0 end
    local map            = game.maps[vehicle.operational_map_key]
    local TPS            = map.tile_pixel_size or map.C.MAP.TILE_SIZE
    local total_distance = 0
    local last_px, last_py = vehicle.px, vehicle.py
    for _, node in ipairs(path) do
        local node_px, node_py = nodePixel(node, TPS)
        total_distance = total_distance + math.sqrt((node_px-last_px)^2 + (node_py-last_py)^2)
        last_px, last_py = node_px, node_py
    end
    local base_speed = vehicle:getSpeed()
    local speed_normalization_factor = game.C.GAMEPLAY.BASE_TILE_SIZE / TPS
    local normalized_speed = base_speed / speed_normalization_factor
    if normalized_speed == 0 then return math.huge end
    return total_distance / normalized_speed
end

function PathfindingService.findPathToDropoff(vehicle, game)
    -- Only pathfind to the first cargo trip's destination.
    -- Running one A* per cargo item is too expensive on the unified grid.
    local leg = vehicle.cargo[1] and vehicle.cargo[1].legs[vehicle.cargo[1].current_leg]
    if not leg then return nil end
    return PathfindingService.findVehiclePath(vehicle, vehicle.grid_anchor, leg.end_plot, game)
end

return PathfindingService
