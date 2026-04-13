-- services/PathfindingService.lua
local WGC                 = require("data.WorldGenConfig")
local IMPASSABLE          = WGC.IMPASSABLE_COST
local SNAP_CAP            = WGC.SNAP_SEARCH_CAP
local PathCacheService    = require("services.PathCacheService")
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
local function _snapToNearestTraversable(plot, map, path_grid, grid_w, grid_h, vehicle, game)
    local ScopeService = require("services.ScopeService")
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
        if game and not ScopeService.isRevealed(game, cx, cy) then return false end
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

-- ── Vehicle cost function ─────────────────────────────────────────────────────

-- Build the vehicle's per-cell cost closure for sandbox-grid A*. Honors
-- pathfinding_bounds and treats zone_seg edges as traversable for road
-- vehicles even when the underlying tile type is plot/downtown_plot.
local function _buildVehicleCostFn(vehicle, map, grid_w, game)
    local ScopeService = require("services.ScopeService")
    local fgi = map.ffi_grid
    local fgw = grid_w
    local path_grid = map.grid
    local function getTileType(gx, gy)
        if fgi then return _TILE_NAMES[fgi[(gy-1)*fgw + (gx-1)].type] or "grass" end
        return path_grid[gy][gx].type
    end
    local bounds = vehicle.pathfinding_bounds
    local zsv = map.zone_seg_v
    local zsh = map.zone_seg_h
    return function(node_x, node_y)
        if bounds and (node_x < bounds.x1 or node_x > bounds.x2
                    or node_y < bounds.y1 or node_y > bounds.y2) then
            return IMPASSABLE
        end
        if game and not ScopeService.isRevealed(game, node_x, node_y) then
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
end

-- Walk a completed path and sum the per-tile movement costs for a vehicle.
-- Returns the raw accumulated cost (same units as A* gScore), NOT money.
function PathfindingService.computePathCost(vehicle, path, game)
    if not path or #path == 0 then return 0 end
    local map = game.maps[vehicle.operational_map_key]
    if not map then return 0 end
    local grid_w = map._w or (map.grid and map.grid[1] and #map.grid[1] or 0)
    local get_cost = _buildVehicleCostFn(vehicle, map, grid_w, game)
    local total = 0
    for _, node in ipairs(path) do
        local c = get_cost(node.x, node.y)
        if c < IMPASSABLE then
            total = total + c
        end
    end
    return total
end

-- Cardinal-neighbor end candidates for a destination plot. Used when the
-- destination cell itself isn't traversable (building plots, etc.).
local function _endCandidates(end_plot, get_cost, grid_w, grid_h)
    local out, seen = {}, {}
    for _, d in ipairs({{0,-1},{0,1},{-1,0},{1,0}}) do
        local nx, ny = end_plot.x + d[1], end_plot.y + d[2]
        if nx >= 1 and nx <= grid_w and ny >= 1 and ny <= grid_h then
            if get_cost(nx, ny) < IMPASSABLE then
                local key = ny * 10000 + nx
                if not seen[key] then seen[key] = true; out[#out+1] = {x=nx, y=ny} end
            end
        end
    end
    return out
end

-- ── Sandbox A* (used for all vehicle pathfinding on the unified map) ──────────

local function findVehiclePathSandbox(vehicle, start_node, end_plot, map, game)
    local path_grid = map.grid  -- nil for unified map (FFI); Lua table for city maps
    local grid_h = map._h or (path_grid and #path_grid or 0)
    local grid_w = map._w or (path_grid and path_grid[1] and #path_grid[1] or 0)

    local start_sub = _snapToNearestTraversable(start_node, map, path_grid, grid_w, grid_h, vehicle, game)
    if not start_sub then return nil end

    local get_cost = _buildVehicleCostFn(vehicle, map, grid_w, game)
    local sandbox_proxy = setmetatable({road_v_rxs = false}, {__index = map})
    local mode = vehicle.transport_mode or "road"

    -- ── Cross-city routing via the entrance graph ────────────────────────────
    -- Only highway-capable vehicles use it (bikes can't traverse highways).
    -- _cityOf falls back to original start_node when the snap moved the
    -- vehicle onto a boundary highway tile just outside city bounds.
    local can_highway = vehicle:getMovementCostFor("highway") < IMPASSABLE
    local start_city  = can_highway and (_cityOf(start_sub.x, start_sub.y, game)
                                      or _cityOf(start_node.x, start_node.y, game)) or nil
    local end_city    = can_highway and _cityOf(end_plot.x, end_plot.y, game) or nil

    if start_city and end_city and start_city ~= end_city then
        local plan = RoutePlannerService.findRoute(start_sub, end_plot, game, {[mode] = true})
        if not plan then
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

        local materialized = RoutePlannerService.materializeRoute(plan, game, vehicle)
        if not materialized then return nil end

        local full = {}
        for _, seg in ipairs(materialized.segments) do
            for _, n in ipairs(seg.points or {}) do full[#full+1] = n end
        end
        if #full == 0 then return nil end
        table.remove(full, 1)  -- vehicle already at start
        return full
    end

    -- ── Same-city: direct A* with end_candidates and per-(start,end) cache ──

    local end_candidates = _endCandidates(end_plot, get_cost, grid_w, grid_h)
    if #end_candidates == 0 then
        local fallback = _snapToNearestTraversable(end_plot, map, path_grid, grid_w, grid_h, vehicle, game)
        if not fallback then return nil end
        end_candidates = {fallback}
    end

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

-- Compute the pixel-path for a single in-city local segment of a route plan.
-- Snaps `from` to the nearest traversable cell, builds end-candidates around
-- `to`, runs bounded A* clamped to city_idx's sub-cell box, and returns the
-- raw path INCLUDING both endpoints (no start stripping). Used by
-- RoutePlannerService.materializeRoute when materializing local segments.
function PathfindingService.findLocalSegment(vehicle, from, to, city_idx, game)
    local map = game.maps[vehicle.operational_map_key]
    if not map then return nil end
    local path_grid = map.grid
    local grid_h = map._h or (path_grid and #path_grid or 0)
    local grid_w = map._w or (path_grid and path_grid[1] and #path_grid[1] or 0)

    local start_sub = _snapToNearestTraversable(from, map, path_grid, grid_w, grid_h, vehicle, game)
    if not start_sub then return nil end

    local get_cost = _buildVehicleCostFn(vehicle, map, grid_w, game)
    local bounds   = city_idx and game.city_sc_bounds and game.city_sc_bounds[city_idx]
    local function bounded(x, y)
        if bounds and (x < bounds.x1 or x > bounds.x2
                    or y < bounds.y1 or y > bounds.y2) then
            return IMPASSABLE
        end
        return get_cost(x, y)
    end

    local sandbox_proxy = setmetatable({road_v_rxs = false}, {__index = map})
    local mode = vehicle.transport_mode or "road"
    local turn_costs = (mode ~= "road") and {turn_90 = 0, turn_180 = 0} or nil

    -- Pick a traversable end target: prefer the cell itself if traversable,
    -- otherwise a cardinal neighbor (so building plots work as destinations).
    local target = {x = to.x, y = to.y}
    if bounded(target.x, target.y) >= IMPASSABLE then
        local cands = _endCandidates(target, bounded, grid_w, grid_h)
        if #cands == 0 then return nil end
        target = cands[1]
    end

    return game.pathfinder.findPath(path_grid or {}, start_sub, target,
        bounded, sandbox_proxy, turn_costs)
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
