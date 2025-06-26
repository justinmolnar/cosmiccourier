-- services/PathfindingService.lua
local PathfindingService = {}

function PathfindingService.findVehiclePath(vehicle, start_plot, end_plot, game)
    if not start_plot or not end_plot then
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
    
    local start_node = map:findNearestRoadTile(start_plot)
    local end_node = map:findNearestRoadTile(end_plot)
    
    if not start_node or not end_node then
        return nil
    end
    
    if start_node.x == end_node.x and start_node.y == end_node.y then
        return {}
    end
    
    -- This no longer needs to know about vehicle types, it just asks the vehicle for its costs!
    local function get_cost_for_node(node_x, node_y)
        local tile = path_grid[node_y][node_x]
        return vehicle:getMovementCostFor(tile.type)
    end
    
    local path = game.pathfinder.findPath(path_grid, start_node, end_node, get_cost_for_node, map)
    
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

function PathfindingService.findPathToRandomHighway(vehicle, game)
    local city_map = game.maps.city
    local highway_tiles = {}
    
    -- Collect all possible highway tiles
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

    -- Pick a random one as the destination
    local destination_plot = highway_tiles[love.math.random(1, #highway_tiles)]
    
    -- Find a path from where the vehicle is to that random highway tile
    return PathfindingService.findVehiclePath(vehicle, vehicle.grid_anchor, destination_plot, game)
end

function PathfindingService.estimatePathTravelTime(path, vehicle, game)
    if not path or #path == 0 then return 0 end

    local total_distance = 0
    -- Use the vehicle's operational map to get the correct tile size.
    local map = game.maps[vehicle.operational_map_key]
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