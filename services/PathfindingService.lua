-- services/PathfindingService.lua
local PathfindingService = {}

function PathfindingService.findVehiclePath(vehicle, start_node, end_plot, game)
    if not start_node or not end_plot then
        print(string.format("ERROR: PathfindingService - Invalid plots for %s %d", vehicle.type, vehicle.id))
        return nil
    end

    local map = game.maps[vehicle.operational_map_key]
    if not map then
        print(string.format("ERROR: PathfindingService - Could not find operational map '%s' for vehicle %d", vehicle.operational_map_key, vehicle.id))
        return nil
    end

    local path_grid = map.grid
    if not path_grid or #path_grid == 0 then
        print(string.format("ERROR: PathfindingService - No map grid available for %s %d", vehicle.type, vehicle.id))
        return nil
    end

    local grid_h, grid_w = #path_grid, #path_grid[1]

    if map.road_v_rxs then
        -- ── Road-node map ──────────────────────────────────────────────────────
        -- start_node is road-node coords (vehicle.grid_anchor).
        -- Snap to nearest road_node if not already valid (depot may not be on an intersection).
        if not (map.road_nodes[start_node.y] and map.road_nodes[start_node.y][start_node.x]) then
            local snapped = map:findNearestRoadNode({x = start_node.x + 1, y = start_node.y + 1})
            if snapped then start_node = snapped end
        end
        -- end_plot is a sub-cell (building location) — must be converted to road-node.

        local function get_cost(rx, ry)
            -- Accept both corner road-nodes and tile-centre nodes (is_tile trucks).
            local is_corner = map.road_nodes[ry] and map.road_nodes[ry][rx]
            local is_tile   = map.tile_nodes and map.tile_nodes[ry] and map.tile_nodes[ry][rx]
            if not is_corner and not is_tile then return 9999 end
            -- Tile type at (rx,ry) 0-indexed = grid[ry+1][rx+1] 1-indexed.
            -- For tile-centre nodes this IS the highway tile; for corner nodes it
            -- is the SE neighbour tile, which is a reliable proxy for the road type.
            local tile = path_grid[ry + 1] and path_grid[ry + 1][rx + 1]
            if tile then
                local t = tile.type
                if t == "arterial" then
                    return vehicle:getMovementCostFor("arterial")
                elseif t == "highway" then
                    return vehicle:getMovementCostFor("highway")
                end
            end
            -- City-street corner nodes: tile is a plot (roads are lines, not tiles).
            return vehicle:getMovementCostFor("road")
        end

        local function snapToColumn(rx, ry)
            -- If already a road_node, use it directly.
            -- Arterial road_nodes are not constrained to road_v columns.
            if map.road_nodes[ry] and map.road_nodes[ry][rx] then
                return {x=rx, y=ry}
            end
            -- Search nearby for any road_node on same row (city street columns first).
            local road_v = map.road_v_rxs
            for dist = 1, grid_w do
                for _, dx in ipairs({-dist, dist}) do
                    local cx = rx + dx
                    if cx >= 0 and cx < grid_w then
                        if map.road_nodes[ry] and map.road_nodes[ry][cx] then
                            return {x=cx, y=ry}
                        end
                    end
                end
            end
            -- Fall back to nearest road_node anywhere.
            local nearest = map:findNearestRoadNode({x=rx+1, y=ry+1})
            if nearest then return nearest end
            return {x=rx, y=ry}
        end

        -- Find road-node candidates adjacent to end_plot.
        -- Roads are lines between sub-cells; check all 4 corner gap-positions of the
        -- building sub-cell.  A corner (rx, ry) is valid if it is a road node.
        -- snapToColumn ensures the candidate is at a road_v column the pathfinder
        -- can actually navigate to via its horizontal-scan movement.
        local end_candidates = {}
        local seen = {}
        local gx, gy = end_plot.x, end_plot.y
        for _, c in ipairs({{gx-1, gy-1}, {gx, gy-1}, {gx-1, gy}, {gx, gy}}) do
            local rx, ry = c[1], c[2]
            if rx >= 0 and rx < grid_w and ry >= 0 and ry < grid_h then
                if map.road_nodes[ry] and map.road_nodes[ry][rx] then
                    local s = snapToColumn(rx, ry)
                    local key = s.y * 10000 + s.x
                    if not seen[key] then
                        seen[key] = true
                        table.insert(end_candidates, s)
                    end
                end
            end
        end

        if #end_candidates == 0 then
            -- BFS in road-node space to find nearest road node to end_plot
            local ex, ey = end_plot.x - 1, end_plot.y - 1
            local vis = {[ey * 10000 + ex] = true}
            local q = {{ex, ey}}
            local qi = 1
            while qi <= #q do
                local crx, cry = q[qi][1], q[qi][2]; qi = qi + 1
                if map.road_nodes[cry] and map.road_nodes[cry][crx] then
                    table.insert(end_candidates, snapToColumn(crx, cry))
                    break
                end
                for _, d in ipairs({{0,-1},{0,1},{-1,0},{1,0}}) do
                    local nrx, nry = crx + d[1], cry + d[2]
                    local k = nry * 10000 + nrx
                    if nrx >= 0 and nrx < grid_w and nry >= 0 and nry < grid_h and not vis[k] then
                        vis[k] = true; q[#q + 1] = {nrx, nry}
                    end
                end
                if qi > 1000 then break end
            end
            if #end_candidates == 0 then
                print(string.format("ERROR: PathfindingService - No road node near end_plot for %s %d", vehicle.type, vehicle.id))
                return nil
            end
        end

        local best_path = nil
        for _, end_node in ipairs(end_candidates) do
            if end_node.x == start_node.x and end_node.y == start_node.y then return {} end
            local path = game.pathfinder.findPath(path_grid, start_node, end_node, get_cost, map)
            if path and (not best_path or #path < #best_path) then
                best_path = path
            end
        end

        if not best_path then
            print(string.format("ERROR: PathfindingService - No path found for %s %d", vehicle.type, vehicle.id))
            print(string.format("  start_node=(%d,%d) end_plot=(%d,%d)", start_node.x, start_node.y, end_plot.x, end_plot.y))
            print(string.format("  end_candidates count=%d", #end_candidates))
            for i, ec in ipairs(end_candidates) do
                print(string.format("  candidate[%d]=(%d,%d) in_road_nodes=%s", i, ec.x, ec.y, tostring(map.road_nodes[ec.y] and map.road_nodes[ec.y][ec.x])))
            end
            print(string.format("  start in_road_nodes=%s road_v=%s", tostring(map.road_nodes[start_node.y] and map.road_nodes[start_node.y][start_node.x]), tostring(map.road_v_rxs[start_node.x])))
            return nil
        end

        if #best_path > 0 then table.remove(best_path, 1) end
        return best_path

    else
        -- ── Sandbox map (sub-cell grid) ────────────────────────────────────────
        local function findTraversable(plot)
            local x, y = plot.x, plot.y
            local function inBounds(gx, gy) return gx>=1 and gx<=grid_w and gy>=1 and gy<=grid_h end
            if inBounds(x, y) and map:isRoad(path_grid[y][x].type)
               and vehicle:getMovementCostFor(path_grid[y][x].type) < 9999 then
                return {x=x, y=y}
            end
            local visited = {[y*10000+x] = true}
            local q = {{x, y}}
            local qi = 1
            while qi <= #q do
                local cx, cy = q[qi][1], q[qi][2]; qi = qi + 1
                if inBounds(cx, cy) and map:isRoad(path_grid[cy][cx].type)
                   and vehicle:getMovementCostFor(path_grid[cy][cx].type) < 9999 then
                    return {x=cx, y=cy}
                end
                for _, d in ipairs({{0,-1},{0,1},{-1,0},{1,0}}) do
                    local nx, ny = cx+d[1], cy+d[2]
                    local k = ny*10000+nx
                    if inBounds(nx, ny) and not visited[k] then
                        visited[k] = true; q[#q+1] = {nx, ny}
                    end
                end
                if qi > 1000 then break end
            end
            return map:findNearestRoadTile(plot)
        end

        local start_sub = findTraversable(start_node)
        if not start_sub then return nil end

        local function get_cost(node_x, node_y)
            local tile = path_grid[node_y][node_x]
            return vehicle:getMovementCostFor(tile.type)
        end

        local end_candidates = {}
        local seen = {}
        for _, d in ipairs({{0,-1},{0,1},{-1,0},{1,0}}) do
            local nx, ny = end_plot.x + d[1], end_plot.y + d[2]
            if nx >= 1 and nx <= grid_w and ny >= 1 and ny <= grid_h then
                local tile = path_grid[ny][nx]
                if tile and map:isRoad(tile.type) and vehicle:getMovementCostFor(tile.type) < 9999 then
                    local key = ny * 10000 + nx
                    if not seen[key] then
                        seen[key] = true
                        table.insert(end_candidates, {x=nx, y=ny})
                    end
                end
            end
        end
        if #end_candidates == 0 then
            local fallback = findTraversable(end_plot)
            if not fallback then return nil end
            end_candidates = {fallback}
        end

        local best_path = nil
        for _, end_node in ipairs(end_candidates) do
            if end_node.x == start_sub.x and end_node.y == start_sub.y then return {} end
            local path = game.pathfinder.findPath(path_grid, start_sub, end_node, get_cost, map)
            if path and (not best_path or #path < #best_path) then
                best_path = path
            end
        end

        if not best_path then
            print(string.format("ERROR: PathfindingService - No path found for %s %d", vehicle.type, vehicle.id))
            return nil
        end

        if #best_path > 0 then table.remove(best_path, 1) end
        return best_path
    end
end

function PathfindingService.findPathToDepot(vehicle, game)
    local current_pos = vehicle.grid_anchor
    return PathfindingService.findVehiclePath(vehicle, current_pos, vehicle.depot_plot, game)
end

function PathfindingService.findPathToPickup(vehicle, trip, game)
    local current_pos = vehicle.grid_anchor
    local leg = trip.legs[trip.current_leg]
    if not leg then
        return nil
    end
    return PathfindingService.findVehiclePath(vehicle, current_pos, leg.start_plot, game)
end

function PathfindingService.findPathToRandomHighway(vehicle, game)
    local city_map = game.maps.city
    local highway_tiles = {}

    for y, row in ipairs(city_map.grid) do
        for x, tile in ipairs(row) do
            if string.find(tile.type, "highway") then
                table.insert(highway_tiles, {x = x, y = y})
            end
        end
    end

    if #highway_tiles == 0 then
        print("ERROR: No highway tiles found on city map for pathfinding.")
        return nil
    end

    local destination_plot = highway_tiles[love.math.random(1, #highway_tiles)]
    return PathfindingService.findVehiclePath(vehicle, vehicle.grid_anchor, destination_plot, game)
end

-- Returns pixel coords for a path node.
-- Road-node maps: pixel = rx*TPS  (node coords ARE the road-line grid)
-- Sandbox maps:   pixel = (x-0.5)*TPS  (tile centre)
local function nodePixel(node, TPS, is_road_node_map)
    if is_road_node_map then
        return node.x * TPS, node.y * TPS
    else
        return (node.x - 0.5) * TPS, (node.y - 0.5) * TPS
    end
end

function PathfindingService.estimatePathTravelTime(path, vehicle, game)
    if not path or #path == 0 then return 0 end

    local total_distance = 0
    local map = game.maps[vehicle.operational_map_key]
    local TPS = map.tile_pixel_size or map.C.MAP.TILE_SIZE
    local is_road_node_map = map.road_v_rxs ~= nil

    local last_px, last_py = vehicle.px, vehicle.py

    for _, node in ipairs(path) do
        local node_px, node_py = nodePixel(node, TPS, is_road_node_map)
        local dist = math.sqrt((node_px - last_px)^2 + (node_py - last_py)^2)
        total_distance = total_distance + dist
        last_px, last_py = node_px, node_py
    end

    local base_speed = vehicle.properties.speed
    local speed_normalization_factor = game.C.GAMEPLAY.BASE_TILE_SIZE / TPS
    local normalized_speed = base_speed / speed_normalization_factor

    if normalized_speed == 0 then return math.huge end

    return total_distance / normalized_speed
end

function PathfindingService.findPathToDropoff(vehicle, game)
    local current_pos = vehicle.grid_anchor
    local best_path, shortest_len = nil, math.huge

    for _, trip in ipairs(vehicle.cargo) do
        local leg = trip.legs[trip.current_leg]
        if leg then
            local path = PathfindingService.findVehiclePath(vehicle, current_pos, leg.end_plot, game)
            if path and #path < shortest_len then
                shortest_len = #path
                best_path = path
            end
        end
    end

    return best_path
end

return PathfindingService
