-- game/generators/connecting_roads.lua
-- Walker-based Connecting Roads Generation Module with Organic Wandering

local ConnectingRoads = {}

function ConnectingRoads.generateConnections(grid, districts, highway_points, map_w, map_h, params)
    print("Starting organic walker-based road generation...")
    
    -- Use debug parameters or defaults
    local walker_connection_distance = (params and params.walker_connection_distance) or 25
    local walker_split_chance = (params and params.walker_split_chance) or 0.05
    local walker_turn_chance = (params and params.walker_turn_chance) or 0.15
    local walker_max_active = (params and params.walker_max_active) or 3
    local walker_death_rules_enabled = (params and params.walker_death_rules_enabled) ~= false -- Default true
    
    -- Find all district boundary road endpoints to start walkers from
    local starting_points = ConnectingRoads.findDistrictBoundaryRoads(grid, districts, highway_points, map_w, map_h)
    print("Found", #starting_points, "starting points for walkers")
    
    -- Create walkers from starting points
    local all_walker_paths = {}
    for _, start_point in ipairs(starting_points) do
        local walker_paths = ConnectingRoads.createWalkersFromPoint(grid, start_point, districts, highway_points, map_w, map_h,
                                                                   walker_connection_distance, walker_split_chance, 
                                                                   walker_turn_chance, walker_max_active, walker_death_rules_enabled)
        for _, path in ipairs(walker_paths) do
            table.insert(all_walker_paths, path)
        end
    end
    
    print("Generated", #all_walker_paths, "walker paths")
    return all_walker_paths
end

function ConnectingRoads.createWalkersFromPoint(grid, start_point, districts, highway_points, map_w, map_h,
                                               connection_distance, split_chance, turn_chance, max_active, death_rules_enabled)
    local walker_paths = {}
    
    -- Create ONE walker per boundary point
    local walker = {
        x = start_point.x + start_point.direction.x,
        y = start_point.y + start_point.direction.y,
        direction = {x = start_point.direction.x, y = start_point.direction.y},
        path = {{x = start_point.x, y = start_point.y}},
        from_district = start_point.district,
        -- NEW: Track how long we've been walking
        steps_taken = 0,
        -- NEW: Bias towards map center for inward-facing walkers
        center_bias = start_point.faces_downtown and 0.3 or 0.0,
        map_center_x = map_w / 2,
        map_center_y = map_h / 2
    }
    
    local active_walkers = {walker}
    
    while #active_walkers > 0 do
        local current_walker = table.remove(active_walkers, 1)
        local walker_result = ConnectingRoads.stepWalker(current_walker, grid, districts, highway_points, map_w, map_h,
                                                        connection_distance, turn_chance, death_rules_enabled)
        
        if walker_result.completed_path then
            table.insert(walker_paths, walker_result.completed_path)
        end
        
        if walker_result.continue_walker then
            table.insert(active_walkers, walker_result.continue_walker)
        end
        
        -- Allow occasional splitting for more variety
        if walker_result.split_walker and love.math.random() < split_chance and #active_walkers < max_active then
            table.insert(active_walkers, walker_result.split_walker)
        end
    end
    
    return walker_paths
end

function ConnectingRoads.stepWalker(walker, grid, districts, highway_points, map_w, map_h, 
                                   connection_distance, turn_chance, death_rules_enabled)
    local result = {}
    
    -- Increment step counter
    walker.steps_taken = walker.steps_taken + 1
    
    -- DEATH CONDITION 1: Check if we're out of bounds
    if not ConnectingRoads.inBounds(walker.x, walker.y, map_w, map_h) then
        result.completed_path = walker.path
        return result
    end
    
    -- DEATH CONDITION 2: Check if we hit an existing road - SUCCESS!
    local current_tile = grid[walker.y][walker.x]
    if ConnectingRoads.isRoadTile(current_tile.type) then
        table.insert(walker.path, {x = walker.x, y = walker.y})
        result.completed_path = walker.path
        return result
    end
    
    -- DEATH CONDITION 3: Check if we've walked too far (prevents infinite loops)
    if walker.steps_taken > 200 then
        result.completed_path = walker.path
        return result
    end
    
    -- DEATH CONDITION 4: Check if we're in a DIFFERENT district (only if death rules enabled)
    if death_rules_enabled then
        local current_district = ConnectingRoads.findDistrictAtPosition(walker.x, walker.y, districts)
        if current_district and current_district ~= walker.from_district then
            result.completed_path = walker.path
            return result
        end
    end
    
    -- Walker survives, add current position to path
    table.insert(walker.path, {x = walker.x, y = walker.y})
    
    -- NEW ORGANIC DIRECTION LOGIC
    ConnectingRoads.updateWalkerDirection(walker, turn_chance)
    
    -- Move walker forward
    walker.x = walker.x + walker.direction.x
    walker.y = walker.y + walker.direction.y
    
    result.continue_walker = walker
    return result
end

function ConnectingRoads.updateWalkerDirection(walker, turn_chance)
    -- Start with current direction (momentum)
    local new_direction = {x = walker.direction.x, y = walker.direction.y}
    
    -- Calculate bias towards map center (for inward-facing walkers)
    local center_pull_x = 0
    local center_pull_y = 0
    
    if walker.center_bias > 0 then
        local dx_to_center = walker.map_center_x - walker.x
        local dy_to_center = walker.map_center_y - walker.y
        local distance_to_center = math.sqrt(dx_to_center * dx_to_center + dy_to_center * dy_to_center)
        
        if distance_to_center > 0 then
            center_pull_x = (dx_to_center / distance_to_center) * walker.center_bias
            center_pull_y = (dy_to_center / distance_to_center) * walker.center_bias
        end
    end
    
    -- Add randomness for organic wandering
    local random_strength = 0.4
    local random_x = (love.math.random() - 0.5) * 2 * random_strength
    local random_y = (love.math.random() - 0.5) * 2 * random_strength
    
    -- Combine all influences
    local combined_x = new_direction.x + center_pull_x + random_x
    local combined_y = new_direction.y + center_pull_y + random_y
    
    -- Normalize to cardinal directions (keep grid-aligned movement)
    if math.abs(combined_x) > math.abs(combined_y) then
        walker.direction.x = combined_x > 0 and 1 or -1
        walker.direction.y = 0
    else
        walker.direction.x = 0
        walker.direction.y = combined_y > 0 and 1 or -1
    end
    
    -- Occasional random turns for more interesting paths
    if love.math.random() < turn_chance then
        ConnectingRoads.turnWalker(walker)
    end
    
    -- Very rare direction reversal for backtracking
    if love.math.random() < 0.02 then
        walker.direction.x = -walker.direction.x
        walker.direction.y = -walker.direction.y
    end
end

function ConnectingRoads.findDistrictAtPosition(x, y, districts)
    for _, district in ipairs(districts) do
        if x >= district.x and x < district.x + district.w and
           y >= district.y and y < district.y + district.h then
            return district
        end
    end
    return nil
end

function ConnectingRoads.isRoadTile(tile_type)
    return tile_type == "road" or 
           tile_type == "highway_ring" or 
           tile_type == "highway_ns" or 
           tile_type == "highway_ew" or
           tile_type == "downtown_road" or
           tile_type == "arterial"
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
        from_district = original_walker.from_district,
        steps_taken = 0, -- Reset step counter for split walker
        center_bias = original_walker.center_bias,
        map_center_x = original_walker.map_center_x,
        map_center_y = original_walker.map_center_y
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

function ConnectingRoads.findDistrictBoundaryRoads(grid, districts, highway_points, map_w, map_h)
    local boundary_points = {}
    
    -- First, find downtown district (District 1) for reference
    local downtown = districts[1]
    local downtown_center_x = downtown.x + downtown.w / 2
    local downtown_center_y = downtown.y + downtown.h / 2
    
    for district_idx, district in ipairs(districts) do
        local district_center_x = district.x + district.w / 2
        local district_center_y = district.y + district.h / 2
        
        -- Collect all boundary roads by side
        local sides = {
            top = {},
            bottom = {},
            left = {},
            right = {}
        }
        
        -- Check all edges of the district for roads that could extend outward
        local edges = {
            -- Top edge
            {x_start = district.x, x_end = district.x + district.w - 1, y = district.y, direction = {x = 0, y = -1}, side = "top"},
            -- Bottom edge  
            {x_start = district.x, x_end = district.x + district.w - 1, y = district.y + district.h - 1, direction = {x = 0, y = 1}, side = "bottom"},
            -- Left edge
            {x = district.x, y_start = district.y, y_end = district.y + district.h - 1, direction = {x = -1, y = 0}, side = "left"},
            -- Right edge
            {x = district.x + district.w - 1, y_start = district.y, y_end = district.y + district.h - 1, direction = {x = 1, y = 0}, side = "right"}
        }
        
        for _, edge in ipairs(edges) do
            if edge.x_start then
                -- Horizontal edge
                for x = edge.x_start, edge.x_end do
                    if ConnectingRoads.inBounds(x, edge.y, map_w, map_h) then
                        local tile_type = grid[edge.y][x].type
                        if ConnectingRoads.isRoadTile(tile_type) then
                            table.insert(sides[edge.side], {
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
                for y = edge.y_start, edge.y_end do
                    if ConnectingRoads.inBounds(edge.x, y, map_w, map_h) then
                        local tile_type = grid[y][edge.x].type
                        if ConnectingRoads.isRoadTile(tile_type) then
                            table.insert(sides[edge.side], {
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
        
        -- Now limit walkers per side based on facing toward downtown
        for side_name, side_roads in pairs(sides) do
            -- Determine if this side faces toward downtown center
            local faces_downtown = false
            
            if side_name == "top" and district_center_y > downtown_center_y then
                faces_downtown = true
            elseif side_name == "bottom" and district_center_y < downtown_center_y then
                faces_downtown = true
            elseif side_name == "left" and district_center_x > downtown_center_x then
                faces_downtown = true
            elseif side_name == "right" and district_center_x < downtown_center_x then
                faces_downtown = true
            end
            
            -- Set limits: 8 for sides facing downtown, 4 for sides facing away
            local max_walkers_this_side = faces_downtown and 8 or 4
            
            -- Shuffle the roads and take up to the limit
            for i = #side_roads, 2, -1 do
                local j = love.math.random(i)
                side_roads[i], side_roads[j] = side_roads[j], side_roads[i]
            end
            
            local roads_to_use = math.min(#side_roads, max_walkers_this_side)
            for i = 1, roads_to_use do
                -- Mark whether this walker faces downtown
                side_roads[i].faces_downtown = faces_downtown
                table.insert(boundary_points, side_roads[i])
            end
        end
    end
    
    return boundary_points
end

function ConnectingRoads.drawConnections(grid, walker_paths, params)
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
            local current_type = grid[y][x].type
            if not ConnectingRoads.isRoadTile(current_type) then
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