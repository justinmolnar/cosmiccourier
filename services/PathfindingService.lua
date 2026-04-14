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

-- Build the vehicle's cost closure. Handles three node conventions:
--   Tile node   {x, y, is_tile=true}   → underlying tile at 1-idx (x+1, y+1).
--   Corner node {x, y} on dual-node map → road cost (downtown_road if any adjacent
--                                          cell is downtown_plot/downtown_road).
--   Cell node   {x, y} (sandbox fallback) → tile type at the cell.
local function _buildVehicleCostFn(vehicle, map, grid_w, game)
    local ScopeService = require("services.ScopeService")
    local fgi = map.ffi_grid
    local fgw = grid_w
    local grid_h = map._h or (map.grid and #map.grid) or 0
    local path_grid = map.grid
    local function getTileType(gx, gy)
        if gx < 1 or gx > fgw or gy < 1 or gy > grid_h then return "grass" end
        if fgi then return _TILE_NAMES[fgi[(gy-1)*fgw + (gx-1)].type] or "grass" end
        return path_grid[gy][gx].type
    end
    local bounds = vehicle.pathfinding_bounds
    local zsv = map.zone_seg_v
    local zsh = map.zone_seg_h
    return function(node_x, node_y, node)
        local is_tile = node and node.is_tile
        local is_corner = node and map.road_nodes and map.road_nodes[node_y]
                               and map.road_nodes[node_y][node_x] and not is_tile
        local gx, gy
        if is_tile or is_corner then
            -- SE-adjacent cell for both (tile node at (x,y) → cell (x+1, y+1);
            -- corner at (x,y) is between four cells, SE is (x+1, y+1)).
            gx, gy = node_x + 1, node_y + 1
        else
            gx, gy = node_x, node_y
        end
        if bounds and (gx < bounds.x1 or gx > bounds.x2
                    or gy < bounds.y1 or gy > bounds.y2) then
            return IMPASSABLE
        end
        if game and not ScopeService.isRevealed(game, gx, gy) then
            return IMPASSABLE
        end
        if is_tile then
            return vehicle:getMovementCostFor(getTileType(gx, gy))
        end
        -- Corner node on dual-node map: cost is road/downtown_road based on
        -- any adjacent cell that's downtown. No zone_seg fallback needed —
        -- corner nodes only exist on the street network.
        if is_corner then
            local rx, ry = node_x, node_y
            local t_tr = getTileType(rx+1, ry+1)
            local t_tl = getTileType(rx,   ry+1)
            local t_br = getTileType(rx+1, ry)
            local t_bl = getTileType(rx,   ry)
            local is_downtown = t_tr == "downtown_plot" or t_tr == "downtown_road"
                              or t_tl == "downtown_plot" or t_tl == "downtown_road"
                              or t_br == "downtown_plot" or t_br == "downtown_road"
                              or t_bl == "downtown_plot" or t_bl == "downtown_road"
            return vehicle:getMovementCostFor(is_downtown and "downtown_road" or "road")
        end
        -- Cell node (sandbox fallback, e.g. world-gen sandbox maps).
        local t = getTileType(node_x, node_y)
        local cost = vehicle:getMovementCostFor(t)
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
        local c = get_cost(node.x, node.y, node)
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

-- ── Dual-node A* (vehicle pathfinding on the unified + city maps) ────────────

local function findVehiclePath_impl(vehicle, start_node, end_plot, map, game)
    local path_grid = map.grid
    local grid_h = map._h or (path_grid and #path_grid or 0)
    local grid_w = map._w or (path_grid and path_grid[1] and #path_grid[1] or 0)

    -- Tile-node grid_anchor has 0-idx coords that don't match 1-idx cells.
    -- Convert before snap. Corner nodes are off by ≤1 cell; snap recovers.
    local start_cell_input = start_node
    if start_node.is_tile and map.nodeToCell then
        start_cell_input = map:nodeToCell(start_node)
    end
    local start_cell = _snapToNearestTraversable(start_cell_input, map, path_grid, grid_w, grid_h, vehicle, game)
    if not start_cell then return nil end

    local get_cost = _buildVehicleCostFn(vehicle, map, grid_w, game)
    local mode = vehicle.transport_mode or "road"

    -- ── Cross-city routing via the entrance graph ────────────────────────────
    local can_highway = vehicle:getMovementCostFor("highway") < IMPASSABLE
    local start_city  = can_highway and (_cityOf(start_cell.x, start_cell.y, game)
                                      or _cityOf(start_node.x, start_node.y, game)) or nil
    local end_city    = can_highway and _cityOf(end_plot.x, end_plot.y, game) or nil

    if start_city and end_city and start_city ~= end_city then
        local plan = RoutePlannerService.findRoute(start_cell, end_plot, game, {[mode] = true})
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

    -- ── Same-city: direct A* with dual-node start/end ───────────────────────
    local start_pf = map.pathStartNodeFor and map:pathStartNodeFor(start_cell)
    local end_nodes = map.pathEndNodesFor and map:pathEndNodesFor(end_plot) or {}
    if not start_pf or #end_nodes == 0 then
        -- Fallback: map lacks dual-node data (e.g. authoring sandbox). Use cells.
        start_pf = start_cell
        end_nodes = _endCandidates(end_plot, get_cost, grid_w, grid_h)
        if #end_nodes == 0 then
            local fallback = _snapToNearestTraversable(end_plot, map, path_grid, grid_w, grid_h, vehicle, game)
            if not fallback then return nil end
            end_nodes = {fallback}
        end
    end

    local cached = PathCacheService.get(mode, start_cell.x, start_cell.y, end_plot.x, end_plot.y)
    if cached then return cached end

    -- Non-road vehicles (ships etc.) use raw 4-directional expansion via turn_costs=0.
    local turn_costs_arg = nil
    if mode ~= "road" then
        turn_costs_arg = { turn_90 = 0, turn_180 = 0 }
    end

    local best_path = nil
    for _, end_node in ipairs(end_nodes) do
        if end_node.x == start_pf.x and end_node.y == start_pf.y
           and (end_node.is_tile or false) == (start_pf.is_tile or false) then
            return {}
        end
        local path = game.pathfinder.findPath(path_grid or {}, start_pf, end_node, get_cost, map, turn_costs_arg)
        if path and (not best_path or #path < #best_path) then best_path = path end
    end

    if not best_path then
        local now = love.timer.getTime()
        local lk  = "_pf_err_" .. vehicle.id
        if not vehicle[lk] or now - vehicle[lk] > 5 then
            vehicle[lk] = now
            print(string.format("ERROR: PathfindingService - No path found for %s %d. start=(%d,%d) end=(%d,%d) end_nodes=%d mode=%s grid=%dx%d",
                vehicle.type, vehicle.id, start_pf.x, start_pf.y, end_plot.x, end_plot.y, #end_nodes, mode, grid_w, grid_h))
        end
        return nil
    end

    if #best_path > 0 then table.remove(best_path, 1) end
    PathCacheService.put(mode, start_cell.x, start_cell.y, end_plot.x, end_plot.y, best_path)
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
    return findVehiclePath_impl(vehicle, start_node, end_plot, map, game)
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

    local from_cell = from
    if from.is_tile and map.nodeToCell then from_cell = map:nodeToCell(from) end
    local start_cell = _snapToNearestTraversable(from_cell, map, path_grid, grid_w, grid_h, vehicle, game)
    if not start_cell then return nil end

    local get_cost = _buildVehicleCostFn(vehicle, map, grid_w, game)
    local bounds   = city_idx and game.city_sc_bounds and game.city_sc_bounds[city_idx]
    local function bounded(x, y, node)
        local gx, gy = x, y
        if node and node.is_tile then gx, gy = x + 1, y + 1 end
        if bounds and (gx < bounds.x1 or gx > bounds.x2
                    or gy < bounds.y1 or gy > bounds.y2) then
            return IMPASSABLE
        end
        return get_cost(x, y, node)
    end

    local mode = vehicle.transport_mode or "road"
    local turn_costs = (mode ~= "road") and {turn_90 = 0, turn_180 = 0} or nil

    local start_pf  = map.pathStartNodeFor and map:pathStartNodeFor(start_cell) or start_cell
    local end_nodes = map.pathEndNodesFor and map:pathEndNodesFor(to) or {}
    if #end_nodes == 0 then
        local target = {x = to.x, y = to.y}
        if bounded(target.x, target.y) >= IMPASSABLE then
            local cands = _endCandidates(target, bounded, grid_w, grid_h)
            if #cands == 0 then return nil end
            target = cands[1]
        end
        end_nodes = {target}
    end

    local best_path = nil
    for _, end_node in ipairs(end_nodes) do
        local path = game.pathfinder.findPath(path_grid or {}, start_pf, end_node,
            bounded, map, turn_costs)
        if path and (not best_path or #path < #best_path) then best_path = path end
    end
    return best_path
end

function PathfindingService.findPathToDepot(vehicle, game)
    return PathfindingService.findVehiclePath(vehicle, vehicle.grid_anchor, vehicle.depot_plot, game)
end

function PathfindingService.findPathToPickup(vehicle, trip, game)
    local leg = trip.legs[trip.current_leg]
    if not leg then return nil end
    return PathfindingService.findVehiclePath(vehicle, vehicle.grid_anchor, leg.start_plot, game)
end

function PathfindingService.estimatePathTravelTime(path, vehicle, game)
    if not path or #path == 0 then return 0 end
    local map            = game.maps[vehicle.operational_map_key]
    local TPS            = map.tile_pixel_size or map.C.MAP.TILE_SIZE
    local total_distance = 0
    local last_px, last_py = vehicle.px, vehicle.py
    for _, node in ipairs(path) do
        local node_px, node_py = map:getNodePixel(node)
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
