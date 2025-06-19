-- game/generators/connecting_roads.lua
-- Walker-based Connecting Roads Generation Module

local ConnectingRoads = {}

-- game/generators/connecting_roads.lua
-- Walker-based Connecting Roads Generation Module with Connection Goals

local ConnectingRoads = {}

function ConnectingRoads.generateConnections(grid, districts, highway_points, map_w, map_h)
    print("Starting simple walker-based road generation...")
    
    -- Find all district boundary road endpoints to start walkers from
    local starting_points = ConnectingRoads.findDistrictBoundaryRoads(grid, districts, map_w, map_h)
    print("Found", #starting_points, "starting points for walkers")
    
    -- Create simple walkers from each starting point
    local all_walker_paths = {}
    for _, start_point in ipairs(starting_points) do
        -- Only create walkers occasionally to avoid chaos
        if love.math.random() < 0.3 then  -- 30% chance per boundary point
            local walker_paths = ConnectingRoads.createSimpleWalkersFromPoint(grid, start_point, districts, highway_points, map_w, map_h)
            for _, path in ipairs(walker_paths) do
                table.insert(all_walker_paths, path)
            end
        end
    end
    
    print("Generated", #all_walker_paths, "walker paths")
    return all_walker_paths
end

function ConnectingRoads.createSimpleWalkersFromPoint(grid, start_point, districts, highway_points, map_w, map_h)
    local walker_paths = {}
    local MAX_WALKERS_PER_POINT = 1  -- Keep it simple - just one walker per point
    
    -- Create simple walker
    local walker = {
        x = start_point.x + start_point.direction.x,
        y = start_point.y + start_point.direction.y,
        direction = {x = start_point.direction.x, y = start_point.direction.y},
        path = {{x = start_point.x, y = start_point.y}},
        steps = 0,
        max_steps = love.math.random(20, 50),  -- Shorter, more predictable paths
        from_district = start_point.district
    }
    
    local active_walkers = {walker}
    
    while #active_walkers > 0 do
        local current_walker = table.remove(active_walkers, 1)
        local walker_result = ConnectingRoads.stepSimpleWalker(current_walker, grid, districts, highway_points, map_w, map_h)
        
        if walker_result.completed_path then
            table.insert(walker_paths, walker_result.completed_path)
        end
        
        if walker_result.continue_walker then
            table.insert(active_walkers, walker_result.continue_walker)
        end
        
        -- Minimal splitting to avoid chaos
        if walker_result.split_walker and love.math.random() < 0.1 then  -- Very low split chance
            table.insert(active_walkers, walker_result.split_walker)
        end
    end
    
    return walker_paths
end

function ConnectingRoads.stepSimpleWalker(walker, grid, districts, highway_points, map_w, map_h)
    local result = {}
    
    -- Check if walker should stop
    walker.steps = walker.steps + 1
    if walker.steps > walker.max_steps then
        result.completed_path = walker.path
        return result
    end
    
    -- Check if we're out of bounds
    if not ConnectingRoads.inBounds(walker.x, walker.y, map_w, map_h) then
        result.completed_path = walker.path
        return result
    end
    
    -- Check if we hit an existing road we can connect to
    local current_tile = grid[walker.y][walker.x]
    if current_tile.type == "road" or current_tile.type == "highway_ring" or 
       current_tile.type == "highway_ns" or current_tile.type == "highway_ew" or
       current_tile.type == "downtown_road" then
        -- Successfully connected!
        table.insert(walker.path, {x = walker.x, y = walker.y})
        result.completed_path = walker.path
        return result
    end
    
    -- Check if we're in another district (stop to avoid going through districts)
    for _, district in ipairs(districts) do
        if district ~= walker.from_district and
           walker.x >= district.x and walker.x < district.x + district.w and
           walker.y >= district.y and walker.y < district.y + district.h then
            result.completed_path = walker.path
            return result
        end
    end
    
    -- Add current position to path
    table.insert(walker.path, {x = walker.x, y = walker.y})
    
    -- Simple, predictable movement decisions
    local random_chance = love.math.random()
    
    if random_chance < 0.03 then
        -- 3% chance to split (very low)
        local split_walker = ConnectingRoads.createSplitWalker(walker)
        result.split_walker = split_walker
    elseif random_chance < 0.1 then
        -- 7% chance to turn
        ConnectingRoads.turnWalker(walker)
    end
    -- Otherwise continue straight (90% chance)
    
    -- Move walker forward
    walker.x = walker.x + walker.direction.x
    walker.y = walker.y + walker.direction.y
    
    result.continue_walker = walker
    return result
end

function ConnectingRoads.initializeDistrictGoals(districts)
    local goals = {}
    for _, district in ipairs(districts) do
        goals[district] = {
            needs_district_connection = true,
            needs_highway_connection = true,
            district_connections = 0,
            highway_connections = 0,
            target_district_connections = 2,  -- Want at least 2 district connections
            target_highway_connections = 1   -- Want at least 1 highway connection
        }
    end
    return goals
end

function ConnectingRoads.allGoalsMet(district_goals)
    for _, goal in pairs(district_goals) do
        if goal.needs_district_connection or goal.needs_highway_connection then
            return false
        end
    end
    return true
end

function ConnectingRoads.countUnmetGoals(district_goals)
    local count = 0
    for _, goal in pairs(district_goals) do
        if goal.needs_district_connection or goal.needs_highway_connection then
            count = count + 1
        end
    end
    return count
end

function ConnectingRoads.createGoalOrientedWalkers(grid, start_point, districts, highway_points, map_w, map_h, district_goal)
    local walker_paths = {}
    local MAX_WALKERS_PER_POINT = 3  -- More walkers when pursuing goals
    local walkers_created = 0
    
    -- Create multiple walkers with different goals
    local walker_configs = {}
    
    if district_goal.needs_district_connection then
        table.insert(walker_configs, {
            goal_type = "district",
            target = ConnectingRoads.findNearestOtherDistrict(start_point, districts)
        })
    end
    
    if district_goal.needs_highway_connection then
        table.insert(walker_configs, {
            goal_type = "highway",
            target = ConnectingRoads.findNearestHighwayPoint(start_point.x, start_point.y, highway_points)
        })
    end
    
    -- Create walkers for each goal
    for _, config in ipairs(walker_configs) do
        if walkers_created >= MAX_WALKERS_PER_POINT then break end
        
        local walker = ConnectingRoads.createGoalOrientedWalker(start_point, config, districts)
        local active_walkers = {walker}
        walkers_created = walkers_created + 1
        
        while #active_walkers > 0 do
            local current_walker = table.remove(active_walkers, 1)
            local walker_result = ConnectingRoads.stepGoalOrientedWalker(
                current_walker, grid, districts, highway_points, map_w, map_h
            )
            
            if walker_result.completed_path then
                table.insert(walker_paths, walker_result.completed_path)
                walker_result.completed_path.connection_type = config.goal_type
                walker_result.completed_path.from_district = start_point.district
            end
            
            if walker_result.continue_walker then
                table.insert(active_walkers, walker_result.continue_walker)
            end
            
            if walker_result.split_walker and walkers_created < MAX_WALKERS_PER_POINT then
                table.insert(active_walkers, walker_result.split_walker)
                walkers_created = walkers_created + 1
            end
        end
    end
    
    return walker_paths
end

function ConnectingRoads.createGoalOrientedWalker(start_point, config, districts)
    -- Calculate initial direction toward goal
    local direction = start_point.direction
    if config.target then
        local dx = config.target.x - start_point.x
        local dy = config.target.y - start_point.y
        
        -- Bias initial direction toward target
        if math.abs(dx) > math.abs(dy) then
            direction = {x = dx > 0 and 1 or -1, y = 0}
        else
            direction = {x = 0, y = dy > 0 and 1 or -1}
        end
    end
    
    return {
        x = start_point.x + direction.x,
        y = start_point.y + direction.y,
        direction = direction,
        path = {{x = start_point.x, y = start_point.y}},
        steps = 0,
        max_steps = love.math.random(40, 100),  -- Longer paths for goal-seeking
        from_district = start_point.district,
        goal_type = config.goal_type,
        target = config.target
    }
end

function ConnectingRoads.stepGoalOrientedWalker(walker, grid, districts, highway_points, map_w, map_h)
    local result = {}
    
    -- Check if walker should stop
    walker.steps = walker.steps + 1
    if walker.steps > walker.max_steps then
        result.completed_path = walker.path
        return result
    end
    
    -- Check if we're out of bounds
    if not ConnectingRoads.inBounds(walker.x, walker.y, map_w, map_h) then
        result.completed_path = walker.path
        return result
    end
    
    -- Check if we hit a connection target
    local current_tile = grid[walker.y][walker.x]
    local connected = false
    
    if walker.goal_type == "highway" then
        if current_tile.type == "highway_ring" or current_tile.type == "highway_ns" or current_tile.type == "highway_ew" then
            connected = true
        end
    elseif walker.goal_type == "district" then
        if current_tile.type == "road" or current_tile.type == "downtown_road" then
            -- Check if we're in a different district
            for _, district in ipairs(districts) do
                if district ~= walker.from_district and
                   walker.x >= district.x and walker.x < district.x + district.w and
                   walker.y >= district.y and walker.y < district.y + district.h then
                    connected = true
                    break
                end
            end
        end
    end
    
    if connected then
        table.insert(walker.path, {x = walker.x, y = walker.y})
        result.completed_path = walker.path
        return result
    end
    
    -- Stop if we hit another district we're not targeting
    for _, district in ipairs(districts) do
        if district ~= walker.from_district and
           walker.x >= district.x and walker.x < district.x + district.w and
           walker.y >= district.y and walker.y < district.y + district.h and
           walker.goal_type ~= "district" then
            result.completed_path = walker.path
            return result
        end
    end
    
    -- Add current position to path
    table.insert(walker.path, {x = walker.x, y = walker.y})
    
    -- Goal-oriented movement decision
    local moved = false
    
    -- 60% chance to move toward goal if we have one
    if walker.target and love.math.random() < 0.6 then
        local dx = walker.target.x - walker.x
        local dy = walker.target.y - walker.y
        
        if math.abs(dx) > math.abs(dy) then
            walker.direction = {x = dx > 0 and 1 or -1, y = 0}
        else
            walker.direction = {x = 0, y = dy > 0 and 1 or -1}
        end
        moved = true
    end
    
    -- Random behavior for remaining chances
    if not moved then
        local random_chance = love.math.random()
        
        if random_chance < 0.05 then
            -- 5% chance to split
            local split_walker = ConnectingRoads.createSplitWalker(walker)
            result.split_walker = split_walker
        elseif random_chance < 0.15 then
            -- 10% chance to turn
            ConnectingRoads.turnWalker(walker)
        end
    end
    
    -- Move walker forward
    walker.x = walker.x + walker.direction.x
    walker.y = walker.y + walker.direction.y
    
    result.continue_walker = walker
    return result
end

function ConnectingRoads.findNearestOtherDistrict(start_point, districts)
    local nearest_district = nil
    local min_distance = math.huge
    
    for _, district in ipairs(districts) do
        if district ~= start_point.district then
            local center_x = district.x + district.w / 2
            local center_y = district.y + district.h / 2
            local distance = math.sqrt((start_point.x - center_x)^2 + (start_point.y - center_y)^2)
            
            if distance < min_distance then
                min_distance = distance
                nearest_district = {x = center_x, y = center_y}
            end
        end
    end
    
    return nearest_district
end

function ConnectingRoads.findNearestHighwayPoint(start_x, start_y, highway_points)
    if not highway_points or #highway_points == 0 then return nil end
    
    local best_point, min_dist_sq = nil, math.huge
    for _, point in ipairs(highway_points) do
        local dist_sq = (point.x - start_x)^2 + (point.y - start_y)^2
        if dist_sq < min_dist_sq then
            min_dist_sq = dist_sq
            best_point = point
        end
    end
    
    return best_point
end

function ConnectingRoads.updateDistrictGoals(district_goals, walker_paths, districts, grid)
    for _, path in ipairs(walker_paths) do
        if path.connection_type and path.from_district then
            local goal = district_goals[path.from_district]
            
            if path.connection_type == "district" then
                goal.district_connections = goal.district_connections + 1
                if goal.district_connections >= goal.target_district_connections then
                    goal.needs_district_connection = false
                end
            elseif path.connection_type == "highway" then
                goal.highway_connections = goal.highway_connections + 1
                if goal.highway_connections >= goal.target_highway_connections then
                    goal.needs_highway_connection = false
                end
            end
        end
    end
end

function ConnectingRoads.reportFinalConnections(district_goals)
    print("Final Connection Report:")
    for district, goal in pairs(district_goals) do
        print(string.format("District: %d district connections, %d highway connections", 
            goal.district_connections, goal.highway_connections))
    end
end

function ConnectingRoads.findDistrictBoundaryRoads(grid, districts, map_w, map_h)
    local boundary_points = {}
    
    for _, district in ipairs(districts) do
        -- Check all edges of the district for roads that could extend outward
        local edges = {
            -- Top edge
            {x_start = district.x, x_end = district.x + district.w, y = district.y, direction = {x = 0, y = -1}},
            -- Bottom edge  
            {x_start = district.x, x_end = district.x + district.w, y = district.y + district.h - 1, direction = {x = 0, y = 1}},
            -- Left edge
            {x = district.x, y_start = district.y, y_end = district.y + district.h, direction = {x = -1, y = 0}},
            -- Right edge
            {x = district.x + district.w - 1, y_start = district.y, y_end = district.y + district.h, direction = {x = 1, y = 0}}
        }
        
        for _, edge in ipairs(edges) do
            if edge.x_start then
                -- Horizontal edge
                for x = edge.x_start, edge.x_end - 1 do
                    if ConnectingRoads.inBounds(x, edge.y, map_w, map_h) then
                        local tile_type = grid[edge.y][x].type
                        -- Include both regular roads AND downtown roads
                        if tile_type == "road" or tile_type == "downtown_road" then
                            table.insert(boundary_points, {
                                x = x, 
                                y = edge.y, 
                                direction = edge.direction,
                                district = district
                            })
                        end
                    end
                end
            else
                -- Vertical edge
                for y = edge.y_start, edge.y_end - 1 do
                    if ConnectingRoads.inBounds(edge.x, y, map_w, map_h) then
                        local tile_type = grid[y][edge.x].type
                        -- Include both regular roads AND downtown roads
                        if tile_type == "road" or tile_type == "downtown_road" then
                            table.insert(boundary_points, {
                                x = edge.x, 
                                y = y, 
                                direction = edge.direction,
                                district = district
                            })
                        end
                    end
                end
            end
        end
    end
    
    return boundary_points
end

function ConnectingRoads.createWalkerFromPoint(grid, start_point, districts, highway_points, map_w, map_h)
    local walker_paths = {}
    local MAX_WALKERS_PER_POINT = 2  -- Limit splitting to prevent chaos
    local walkers_created = 0
    
    -- Create initial walker
    local initial_walker = {
        x = start_point.x + start_point.direction.x,
        y = start_point.y + start_point.direction.y,
        direction = {x = start_point.direction.x, y = start_point.direction.y},
        path = {{x = start_point.x, y = start_point.y}},
        steps = 0,
        max_steps = love.math.random(20, 60),
        from_district = start_point.district
    }
    
    local active_walkers = {initial_walker}
    
    while #active_walkers > 0 and walkers_created < MAX_WALKERS_PER_POINT do
        local walker = table.remove(active_walkers, 1)
        local walker_result = ConnectingRoads.stepWalker(walker, grid, districts, highway_points, map_w, map_h)
        
        if walker_result.completed_path then
            table.insert(walker_paths, walker_result.completed_path)
        end
        
        if walker_result.continue_walker then
            table.insert(active_walkers, walker_result.continue_walker)
        end
        
        -- Handle walker splitting
        if walker_result.split_walker and walkers_created < MAX_WALKERS_PER_POINT then
            table.insert(active_walkers, walker_result.split_walker)
            walkers_created = walkers_created + 1
        end
    end
    
    return walker_paths
end

function ConnectingRoads.stepWalker(walker, grid, districts, highway_points, map_w, map_h)
    local result = {}
    
    -- Check if walker should stop
    walker.steps = walker.steps + 1
    if walker.steps > walker.max_steps then
        result.completed_path = walker.path
        return result
    end
    
    -- Check if we're out of bounds
    if not ConnectingRoads.inBounds(walker.x, walker.y, map_w, map_h) then
        result.completed_path = walker.path
        return result
    end
    
    -- Check if we hit an existing road we can connect to
    local current_tile = grid[walker.y][walker.x]
    if current_tile.type == "road" or current_tile.type == "highway_ring" or 
       current_tile.type == "highway_ns" or current_tile.type == "highway_ew" or
       current_tile.type == "downtown_road" then
        -- Successfully connected!
        table.insert(walker.path, {x = walker.x, y = walker.y})
        result.completed_path = walker.path
        return result
    end
    
    -- Check if we're in another district (stop to avoid going through districts)
    for _, district in ipairs(districts) do
        if district ~= walker.from_district and
           walker.x >= district.x and walker.x < district.x + district.w and
           walker.y >= district.y and walker.y < district.y + district.h then
            result.completed_path = walker.path
            return result
        end
    end
    
    -- Add current position to path
    table.insert(walker.path, {x = walker.x, y = walker.y})
    
    -- Decide walker's next action
    local random_chance = love.math.random()
    
    if random_chance < 0.05 then
        -- 5% chance to split
        local split_walker = ConnectingRoads.createSplitWalker(walker)
        result.split_walker = split_walker
    elseif random_chance < 0.15 then
        -- 10% chance to turn
        ConnectingRoads.turnWalker(walker)
    end
    -- Otherwise continue straight (85% chance)
    
    -- Move walker forward
    walker.x = walker.x + walker.direction.x
    walker.y = walker.y + walker.direction.y
    
    result.continue_walker = walker
    return result
end

function ConnectingRoads.createSplitWalker(original_walker)
    -- Create a new walker going in a perpendicular direction
    local perpendicular_directions = {}
    if original_walker.direction.x == 0 then
        -- Moving vertically, split horizontally
        table.insert(perpendicular_directions, {x = -1, y = 0})
        table.insert(perpendicular_directions, {x = 1, y = 0})
    else
        -- Moving horizontally, split vertically
        table.insert(perpendicular_directions, {x = 0, y = -1})
        table.insert(perpendicular_directions, {x = 0, y = 1})
    end
    
    local new_direction = perpendicular_directions[love.math.random(1, #perpendicular_directions)]
    
    return {
        x = original_walker.x,
        y = original_walker.y,
        direction = new_direction,
        path = {original_walker.path[#original_walker.path]}, -- Start from current position
        steps = 0,
        max_steps = love.math.random(15, 40), -- Shorter paths for splits
        from_district = original_walker.from_district
    }
end

function ConnectingRoads.turnWalker(walker)
    -- Turn 90 degrees left or right
    local turn_options = {}
    if walker.direction.x == 0 then
        -- Currently moving vertically
        table.insert(turn_options, {x = -1, y = 0})
        table.insert(turn_options, {x = 1, y = 0})
    else
        -- Currently moving horizontally
        table.insert(turn_options, {x = 0, y = -1})
        table.insert(turn_options, {x = 0, y = 1})
    end
    
    walker.direction = turn_options[love.math.random(1, #turn_options)]
end

function ConnectingRoads.drawConnections(grid, walker_paths)
    -- Draw all the walker paths as thin roads
    for _, path in ipairs(walker_paths) do
        for i = 1, #path - 1 do
            ConnectingRoads.drawThinLine(grid, path[i].x, path[i].y, path[i+1].x, path[i+1].y, "road")
        end
    end
end

function ConnectingRoads.drawThinLine(grid, x1, y1, x2, y2, road_type)
    if not grid or #grid == 0 then return end
    
    local w, h = #grid[1], #grid
    local dx, dy = math.abs(x2 - x1), math.abs(y2 - y1)
    local sx, sy = (x1 < x2) and 1 or -1, (y1 < y2) and 1 or -1
    local err, x, y = dx - dy, x1, y1
    
    while true do
        if ConnectingRoads.inBounds(x, y, w, h) then
            -- Only draw if it's not already a highway or other major road
            if grid[y][x].type ~= "highway_ring" and grid[y][x].type ~= "highway_ns" and 
               grid[y][x].type ~= "highway_ew" and grid[y][x].type ~= "downtown_road" then
                grid[y][x].type = road_type
            end
        end
        
        if x == x2 and y == y2 then break end
        
        local e2 = 2 * err
        if e2 > -dy then err = err - dy; x = x + sx end
        if e2 < dx then err = err + dx; y = y + sy end
    end
end

function ConnectingRoads.inBounds(x, y, width, height)
    return x >= 1 and x <= width and y >= 1 and y <= height
end

return ConnectingRoads