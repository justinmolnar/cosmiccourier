-- services/PathfindingService.lua
local WGC       = require("data.WorldGenConfig")
local IMPASSABLE = WGC.IMPASSABLE_COST
local SNAP_CAP   = WGC.SNAP_SEARCH_CAP

local PathfindingService = {}

-- ── Snap helper ───────────────────────────────────────────────────────────────

-- BFS snap to nearest traversable tile on a sandbox (sub-cell) map.
local function _snapToNearestTraversable(plot, map, path_grid, grid_w, grid_h, vehicle)
    local x, y = plot.x, plot.y
    local function inBounds(gx, gy) return gx>=1 and gx<=grid_w and gy>=1 and gy<=grid_h end
    if inBounds(x, y) and map:isRoad(path_grid[y][x].type)
       and vehicle:getMovementCostFor(path_grid[y][x].type) < IMPASSABLE then
        return {x=x, y=y}
    end
    local visited = {[y*10000+x] = true}
    local q, qi = {{x, y}}, 1
    while qi <= #q and qi <= SNAP_CAP do
        local cx, cy = q[qi][1], q[qi][2]; qi = qi + 1
        if inBounds(cx, cy) and map:isRoad(path_grid[cy][cx].type)
           and vehicle:getMovementCostFor(path_grid[cy][cx].type) < IMPASSABLE then
            return {x=cx, y=cy}
        end
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
    local path_grid = map.grid
    local grid_h, grid_w = #path_grid, #path_grid[1]

    local start_sub = _snapToNearestTraversable(start_node, map, path_grid, grid_w, grid_h, vehicle)
    if not start_sub then return nil end

    local bounds = vehicle.pathfinding_bounds
    local function get_cost(node_x, node_y)
        if bounds and (node_x < bounds.x1 or node_x > bounds.x2
                    or node_y < bounds.y1 or node_y > bounds.y2) then
            return IMPASSABLE
        end
        return vehicle:getMovementCostFor(path_grid[node_y][node_x].type)
    end

    local end_candidates, seen = {}, {}
    for _, d in ipairs({{0,-1},{0,1},{-1,0},{1,0}}) do
        local nx, ny = end_plot.x + d[1], end_plot.y + d[2]
        if nx >= 1 and nx <= grid_w and ny >= 1 and ny <= grid_h then
            local tile = path_grid[ny][nx]
            if tile and map:isRoad(tile.type) and vehicle:getMovementCostFor(tile.type) < IMPASSABLE then
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

    local best_path = nil
    for _, end_node in ipairs(end_candidates) do
        if end_node.x == start_sub.x and end_node.y == start_sub.y then return {} end
        local path = game.pathfinder.findPath(path_grid, start_sub, end_node, get_cost, sandbox_proxy)
        if path and (not best_path or #path < #best_path) then best_path = path end
    end

    if not best_path then
        print(string.format("ERROR: PathfindingService - No path found for %s %d", vehicle.type, vehicle.id))
        return nil
    end

    if #best_path > 0 then table.remove(best_path, 1) end
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
    local path_grid = map.grid
    if not path_grid or #path_grid == 0 then
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
    local current_pos   = vehicle.grid_anchor
    local best_path, shortest_len = nil, math.huge
    for _, trip in ipairs(vehicle.cargo) do
        local leg = trip.legs[trip.current_leg]
        if leg then
            local path = PathfindingService.findVehiclePath(vehicle, current_pos, leg.end_plot, game)
            if path and #path < shortest_len then
                shortest_len = #path; best_path = path
            end
        end
    end
    return best_path
end

return PathfindingService
