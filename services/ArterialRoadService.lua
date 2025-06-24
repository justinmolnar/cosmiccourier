-- services/ArterialRoadService.lua
-- Generates arterial roads that snake around districts using pathfinding

local ArterialRoadService = {}

-- Make this compatible with your existing WFC system
ArterialRoadService.generateArterialsWFC = function(city_grid, zone_grid, params)
    return ArterialRoadService.generateArterialRoads(city_grid, zone_grid, params)
end

-- Import pathfinding
local Pathfinder = require("lib.pathfinder")

function ArterialRoadService.generateArterialRoads(city_grid, zone_grid, params)
    print("ArterialRoadService: Starting arterial road generation")
    
    local width, height = #city_grid[1], #city_grid
    local num_arterials = params.num_arterials or 3
    local min_distance_between_points = params.min_edge_distance or 15
    
    -- Create a pathfinding cost grid based on zones
    local cost_grid = ArterialRoadService._createCostGrid(zone_grid, width, height)
    
    -- Generate arterial roads
    for i = 1, num_arterials do
        print(string.format("ArterialRoadService: Generating arterial road %d/%d", i, num_arterials))
        
        -- Pick district transition points on map edges
        local entry_point = ArterialRoadService._getRandomEdgePoint(width, height, "entry", nil, nil, zone_grid)
        local exit_point = ArterialRoadService._getRandomEdgePoint(width, height, "exit", entry_point, min_distance_between_points, zone_grid)
        
        if entry_point and exit_point then
            local entry_desc = entry_point.zone_from and 
                string.format("%s/%s boundary", entry_point.zone_from, entry_point.zone_to) or 
                "edge point"
            local exit_desc = exit_point.zone_from and 
                string.format("%s/%s boundary", exit_point.zone_from, exit_point.zone_to) or 
                "edge point"
                
            print(string.format("ArterialRoadService: Route from (%d,%d) %s to (%d,%d) %s", 
                  entry_point.x, entry_point.y, entry_desc, 
                  exit_point.x, exit_point.y, exit_desc))
            
            -- Find path using A* with our custom cost grid
            local path = ArterialRoadService._findArterialPath(cost_grid, entry_point, exit_point, width, height)
            
            if path then
                -- Smooth the path to make it more natural
                local smoothed_path = ArterialRoadService._smoothPath(path)
                
                -- Draw the arterial road onto the city grid
                ArterialRoadService._drawArterialToGrid(city_grid, smoothed_path)
                
                print(string.format("ArterialRoadService: Successfully created arterial with %d nodes", #smoothed_path))
            else
                print("ArterialRoadService: Failed to find path for arterial road")
            end
        else
            print("ArterialRoadService: Failed to find suitable entry/exit points")
        end
    end
    
    print("ArterialRoadService: Arterial road generation complete")
end

-- Create a cost grid where districts have high cost, edges have low cost
function ArterialRoadService._createCostGrid(zone_grid, width, height)
    local cost_grid = {}
    local edge_distance = 3 -- Reduced edge zone
    
    for y = 1, height do
        cost_grid[y] = {}
        for x = 1, width do
            local zone = zone_grid[y][x]
            local base_cost = 1
            
            -- High costs for districts but not extreme
            if zone == "downtown" then
                base_cost = 100 -- High but not impossible
            elseif zone == "commercial" or zone == "residential_north" or zone == "residential_south" then
                base_cost = 80 -- High cost for dense areas
            elseif zone == "industrial_heavy" or zone == "industrial_light" then
                base_cost = 90 -- High cost for industrial
            elseif zone == "university" or zone == "medical" or zone == "tech" then
                base_cost = 70 -- High cost for special zones
            elseif zone == "warehouse" or zone == "entertainment" or zone == "waterfront" then
                base_cost = 60 -- High cost for other developed zones
            elseif zone:find("park") then
                base_cost = 10 -- Much lower cost for parks - roads can go through parks
            end
            
            -- Moderate cost reduction near edges (not extreme)
            local distance_to_edge = math.min(x - 1, width - x, y - 1, height - y)
            if distance_to_edge <= edge_distance then
                -- Linear reduction instead of exponential
                local edge_multiplier = 0.3 + (0.7 * distance_to_edge / edge_distance)
                base_cost = math.max(1, base_cost * edge_multiplier)
            end
            
            cost_grid[y][x] = base_cost
        end
    end
    
    return cost_grid
end

function ArterialRoadService._getRandomEdgePointFallback(width, height, point_type, other_point, min_distance)
    local edges = {
        {name = "top", points = {}},
        {name = "bottom", points = {}},
        {name = "left", points = {}},
        {name = "right", points = {}}
    }
    
    -- Generate edge points
    for x = 1, width do
        table.insert(edges[1].points, {x = x, y = 1, edge = "top"})
        table.insert(edges[2].points, {x = x, y = height, edge = "bottom"})
    end
    
    for y = 1, height do
        table.insert(edges[3].points, {x = 1, y = y, edge = "left"})
        table.insert(edges[4].points, {x = width, y = y, edge = "right"})
    end
    
    -- Collect valid points
    local valid_points = {}
    for _, edge in ipairs(edges) do
        for _, point in ipairs(edge.points) do
            local is_valid = true
            
            if other_point and min_distance then
                local distance = math.sqrt((point.x - other_point.x)^2 + (point.y - other_point.y)^2)
                if distance < min_distance then
                    is_valid = false
                end
                
                if point.edge == other_point.edge then
                    is_valid = false
                end
            end
            
            if is_valid then
                table.insert(valid_points, point)
            end
        end
    end
    
    if #valid_points > 0 then
        return valid_points[love.math.random(1, #valid_points)]
    end
    
    return nil
end

-- Get a random point on the edge of the map
function ArterialRoadService._getRandomEdgePoint(width, height, point_type, other_point, min_distance, zone_grid)
    -- Find district boundary points on edges
    local boundary_points = ArterialRoadService._findDistrictBoundaryPoints(zone_grid, width, height)
    
    if #boundary_points == 0 then
        print("ArterialRoadService: No district boundary points found, falling back to random edge points")
        return ArterialRoadService._getRandomEdgePointFallback(width, height, point_type, other_point, min_distance)
    end
    
    -- Filter valid boundary points
    local valid_points = {}
    for _, point in ipairs(boundary_points) do
        local is_valid = true
        
        -- If we need to check distance from another point
        if other_point and min_distance then
            local distance = math.sqrt((point.x - other_point.x)^2 + (point.y - other_point.y)^2)
            if distance < min_distance then
                is_valid = false
            end
            
            -- Force different edges
            if point.edge == other_point.edge then
                is_valid = false
            end
        end
        
        if is_valid then
            table.insert(valid_points, point)
        end
    end
    
    if #valid_points > 0 then
        return valid_points[love.math.random(1, #valid_points)]
    else
        -- Fallback to random if no valid boundary points
        return ArterialRoadService._getRandomEdgePointFallback(width, height, point_type, other_point, min_distance)
    end
end

function ArterialRoadService._findDistrictBoundaryPoints(zone_grid, width, height)
    local boundary_points = {}
    
    -- Check top and bottom edges for district transitions
    for x = 2, width do  -- Start at 2 so we can check x-1
        -- Top edge - check if zone changes from previous tile
        if zone_grid[1][x] ~= zone_grid[1][x-1] then
            table.insert(boundary_points, {
                x = x, y = 1, edge = "top", 
                zone_from = zone_grid[1][x-1], 
                zone_to = zone_grid[1][x]
            })
        end
        
        -- Bottom edge - check if zone changes from previous tile
        if zone_grid[height][x] ~= zone_grid[height][x-1] then
            table.insert(boundary_points, {
                x = x, y = height, edge = "bottom", 
                zone_from = zone_grid[height][x-1], 
                zone_to = zone_grid[height][x]
            })
        end
    end
    
    -- Check left and right edges for district transitions
    for y = 2, height do  -- Start at 2 so we can check y-1
        -- Left edge - check if zone changes from previous tile
        if zone_grid[y][1] ~= zone_grid[y-1][1] then
            table.insert(boundary_points, {
                x = 1, y = y, edge = "left", 
                zone_from = zone_grid[y-1][1], 
                zone_to = zone_grid[y][1]
            })
        end
        
        -- Right edge - check if zone changes from previous tile
        if zone_grid[y][width] ~= zone_grid[y-1][width] then
            table.insert(boundary_points, {
                x = width, y = y, edge = "right", 
                zone_from = zone_grid[y-1][width], 
                zone_to = zone_grid[y][width]
            })
        end
    end
    
    print("ArterialRoadService: Found " .. #boundary_points .. " district transition points on edges")
    for _, point in ipairs(boundary_points) do
        print(string.format("  Transition at (%d,%d) on %s edge: %s -> %s", 
              point.x, point.y, point.edge, point.zone_from, point.zone_to))
    end
    
    return boundary_points
end

-- Custom A* pathfinding for arterial roads
function ArterialRoadService._findArterialPath(cost_grid, start_point, end_point, width, height)
    print(string.format("ArterialRoadService: Pathfinding from (%d,%d) to (%d,%d)", 
          start_point.x, start_point.y, end_point.x, end_point.y))
    print(string.format("Start cost: %d, End cost: %d", 
          cost_grid[start_point.y][start_point.x], cost_grid[end_point.y][end_point.x]))
    
    -- Simple A* implementation
    local open_set = {}
    local closed_set = {}
    local came_from = {}
    local g_score = {}
    local f_score = {}
    
    local function node_key(x, y)
        return y * width + x
    end
    
    local function heuristic(x1, y1, x2, y2)
        return math.abs(x1 - x2) + math.abs(y1 - y2) -- Manhattan distance
    end
    
    local function get_neighbors(x, y)
        local neighbors = {}
        local directions = {{0, -1}, {1, 0}, {0, 1}, {-1, 0}} -- up, right, down, left
        
        for _, dir in ipairs(directions) do
            local nx, ny = x + dir[1], y + dir[2]
            if nx >= 1 and nx <= width and ny >= 1 and ny <= height then
                table.insert(neighbors, {x = nx, y = ny})
            end
        end
        
        return neighbors
    end
    
    local function reconstruct_path(current)
        local path = {current}
        while came_from[node_key(current.x, current.y)] do
            current = came_from[node_key(current.x, current.y)]
            table.insert(path, 1, current)
        end
        return path
    end
    
    -- Initialize
    local start_key = node_key(start_point.x, start_point.y)
    open_set[start_key] = start_point
    g_score[start_key] = 0
    f_score[start_key] = heuristic(start_point.x, start_point.y, end_point.x, end_point.y)
    
    local iterations = 0
    local max_iterations = width * height
    
    while next(open_set) and iterations < max_iterations do
        iterations = iterations + 1
        
        -- Find node in open set with lowest f_score
        local current = nil
        local current_key = nil
        local lowest_f = math.huge
        
        for key, node in pairs(open_set) do
            if f_score[key] < lowest_f then
                lowest_f = f_score[key]
                current = node
                current_key = key
            end
        end
        
        if current.x == end_point.x and current.y == end_point.y then
            local final_path = reconstruct_path(current)
            print(string.format("ArterialRoadService: Path found in %d iterations, %d nodes", iterations, #final_path))
            return final_path
        end
        
        open_set[current_key] = nil
        closed_set[current_key] = true
        
        for _, neighbor in ipairs(get_neighbors(current.x, current.y)) do
            local neighbor_key = node_key(neighbor.x, neighbor.y)
            
            if not closed_set[neighbor_key] then
                local tentative_g = g_score[current_key] + cost_grid[neighbor.y][neighbor.x]
                
                if not open_set[neighbor_key] then
                    open_set[neighbor_key] = neighbor
                elseif tentative_g >= (g_score[neighbor_key] or math.huge) then
                    goto continue
                end
                
                came_from[neighbor_key] = current
                g_score[neighbor_key] = tentative_g
                f_score[neighbor_key] = tentative_g + heuristic(neighbor.x, neighbor.y, end_point.x, end_point.y)
            end
            
            ::continue::
        end
    end
    
    print(string.format("ArterialRoadService: No path found after %d iterations", iterations))
    return nil -- No path found
end

-- Smooth the path to make it more natural (reduce sharp angles)
function ArterialRoadService._smoothPath(path)
    if #path < 3 then return path end
    
    local smoothed = {path[1]} -- Keep first point
    
    for i = 2, #path - 1 do
        local prev_point = path[i - 1]
        local current_point = path[i]
        local next_point = path[i + 1]
        
        -- Calculate the angle at this point
        local vec1_x = current_point.x - prev_point.x
        local vec1_y = current_point.y - prev_point.y
        local vec2_x = next_point.x - current_point.x
        local vec2_y = next_point.y - current_point.y
        
        -- If it's a sharp turn, add intermediate points for smoother curves
        if vec1_x ~= vec2_x or vec1_y ~= vec2_y then
            table.insert(smoothed, current_point)
        end
    end
    
    table.insert(smoothed, path[#path]) -- Keep last point
    return smoothed
end

-- Draw the arterial road onto the city grid
function ArterialRoadService._drawArterialToGrid(city_grid, path)
    for i = 1, #path - 1 do
        local current = path[i]
        local next_point = path[i + 1]
        
        -- Draw line between current and next point
        ArterialRoadService._drawLine(city_grid, current.x, current.y, next_point.x, next_point.y, "arterial")
    end
end

-- Draw a line on the grid (Bresenham's line algorithm)
function ArterialRoadService._drawLine(grid, x1, y1, x2, y2, road_type)
    local dx = math.abs(x2 - x1)
    local dy = math.abs(y2 - y1)
    local sx = x1 < x2 and 1 or -1
    local sy = y1 < y2 and 1 or -1
    local err = dx - dy
    local x, y = x1, y1
    
    while true do
        -- Only place road if the current tile isn't already an arterial or better
        if grid[y] and grid[y][x] and grid[y][x].type ~= "arterial" and grid[y][x].type ~= "road" then
            grid[y][x] = { type = road_type }
        end
        
        if x == x2 and y == y2 then break end
        
        local e2 = 2 * err
        if e2 > -dy then
            err = err - dy
            x = x + sx
        end
        if e2 < dx then
            err = err + dx
            y = y + sy
        end
    end
end

return ArterialRoadService