-- services/PathfindingService.lua
local PathfindingService = {}

function PathfindingService.findVehiclePath(vehicle, start_plot, end_plot, game)
    if not start_plot or not end_plot then
        print(string.format("ERROR: PathfindingService - Invalid plots for %s %d", vehicle.type, vehicle.id))
        return nil
    end
    
    local path_grid = game.map.grid
    if not path_grid then
        print(string.format("ERROR: PathfindingService - No map grid available for %s %d", vehicle.type, vehicle.id))
        return nil
    end
    
    local start_node = game.map:findNearestRoadTile(start_plot)
    local end_node = game.map:findNearestRoadTile(end_plot)
    
    if not start_node then
        print(string.format("ERROR: PathfindingService - No road near start for %s %d", vehicle.type, vehicle.id))
        return nil
    end
    
    if not end_node then
        print(string.format("ERROR: PathfindingService - No road near destination for %s %d", vehicle.type, vehicle.id))
        return nil
    end
    
    -- Same start and end, no path needed
    if start_node.x == end_node.x and start_node.y == end_node.y then
        return {}
    end
    
    local costs = vehicle.properties.pathfinding_costs
    if not costs then
        print(string.format("ERROR: PathfindingService - No pathfinding costs for %s %d", vehicle.type, vehicle.id))
        return nil
    end
    
    local path = game.pathfinder.findPath(path_grid, start_node, end_node, costs, game.map)
    
    if not path then
        print(string.format("ERROR: PathfindingService - No path found for %s %d", vehicle.type, vehicle.id))
        return nil
    end
    
    -- Remove the first node since we're already there
    if #path > 0 then
        table.remove(path, 1)
    end
    
    return path
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