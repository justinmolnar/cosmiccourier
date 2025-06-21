-- services/PathfindingService.lua
local PathfindingService = {}

function PathfindingService.findVehiclePath(vehicle, start_plot, end_plot, game, map)
    if not start_plot or not end_plot then
        print(string.format("ERROR: PathfindingService - Invalid plots for %s %d", vehicle.type, vehicle.id))
        return nil
    end
    
    -- MODIFIED: Use the map that was passed in, instead of the global active map
    local path_grid = map.grid
    if not path_grid or #path_grid == 0 then
        print(string.format("ERROR: PathfindingService - No map grid available for %s %d", vehicle.type, vehicle.id))
        return nil
    end
    
    local start_node = map:findNearestRoadTile(start_plot)
    local end_node = map:findNearestRoadTile(end_plot)
    
    if not start_node or not end_node then
        return nil
    end
    
    if start_node.x == end_node.x and start_node.y == end_node.y then
        return {}
    end
    
    local costs = vehicle.properties.pathfinding_costs
    if not costs then
        print(string.format("ERROR: PathfindingService - No pathfinding costs for %s %d", vehicle.type, vehicle.id))
        return nil
    end
    
    local path = game.pathfinder.findPath(path_grid, start_node, end_node, costs, map)
    
    if not path then
        print(string.format("ERROR: PathfindingService - No path found for %s %d", vehicle.type, vehicle.id))
        return nil
    end
    
    if #path > 0 then
        table.remove(path, 1)
    end
    
    return path
end

function PathfindingService.findPathToDepot(vehicle, game)
    local current_pos = vehicle.grid_anchor
    -- MODIFIED: Always use the city map for depot pathfinding
    return PathfindingService.findVehiclePath(vehicle, current_pos, vehicle.depot_plot, game, game.maps.city)
end

function PathfindingService.findPathToPickup(vehicle, trip, game)
    local current_pos = vehicle.grid_anchor
    local leg = trip.legs[trip.current_leg]
    if not leg then
        return nil
    end
    
    -- MODIFIED: Always use the city map for pickup pathfinding
    return PathfindingService.findVehiclePath(vehicle, current_pos, leg.start_plot, game, game.maps.city)
end

function PathfindingService.estimatePathTravelTime(path, vehicle, game, map)
    if not path or #path == 0 then return 0 end

    local total_distance = 0
    -- MODIFIED: Use the tile size from the map that was passed in.
    local TILE_SIZE = map.C.MAP.TILE_SIZE

    -- Start from the vehicle's current position
    local last_px, last_py = vehicle.px, vehicle.py

    for _, node in ipairs(path) do
        local node_px, node_py = (node.x - 0.5) * TILE_SIZE, (node.y - 0.5) * TILE_SIZE
        local dist = math.sqrt((node_px - last_px)^2 + (node_py - last_py)^2)
        total_distance = total_distance + dist
        last_px, last_py = node_px, node_py
    end

    local base_speed = vehicle.properties.speed
    local speed_normalization_factor = game.C.GAMEPLAY.BASE_TILE_SIZE / TILE_SIZE
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
            -- MODIFIED: Always use the city map for dropoff pathfinding
            local path = PathfindingService.findVehiclePath(vehicle, current_pos, leg.end_plot, game, game.maps.city)
            if path and #path < shortest_len then
                shortest_len = #path
                best_path = path
            end
        end
    end
    
    return best_path
end

return PathfindingService