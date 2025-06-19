-- game/generators/connecting_roads.lua
-- Walker-based Connecting Roads Generation Module with Clear Death Rules

local ConnectingRoads = {}

function ConnectingRoads.generateConnections(grid, districts, highway_points, map_w, map_h)
    print("Starting walker-based road generation...")
    
    -- Find all district boundary road endpoints to start walkers from
    local starting_points = ConnectingRoads.findDistrictBoundaryRoads(grid, districts, highway_points, map_w, map_h)
    print("Found", #starting_points, "starting points for walkers")
    
    -- Create walkers from EVERY starting point to ensure full connectivity
    local all_walker_paths = {}
    for _, start_point in ipairs(starting_points) do
        -- SPAWN AT EVERY BOUNDARY ROAD TILE - no random chance
        local walker_paths = ConnectingRoads.createWalkersFromPoint(grid, start_point, districts, highway_points, map_w, map_h)
        for _, path in ipairs(walker_paths) do
            table.insert(all_walker_paths, path)
        end
    end
    
    print("Generated", #all_walker_paths, "walker paths")
    return all_walker_paths
end

function ConnectingRoads.createWalkersFromPoint(grid, start_point, districts, highway_points, map_w, map_h)
    local walker_paths = {}
    
    -- Create ONE walker per boundary point to ensure every district road gets a connection attempt
    local walker = {
        x = start_point.x + start_point.direction.x,
        y = start_point.y + start_point.direction.y,
        direction = {x = start_point.direction.x, y = start_point.direction.y},
        path = {{x = start_point.x, y = start_point.y}},
        visited = {}, -- Fix: Add a table to track visited tiles for this walker
        from_district = start_point.district,
        connection_distance = 25  -- Increased range to find connections more easily
    }
    
    local active_walkers = {walker}
    
    while #active_walkers > 0 do
        local current_walker = table.remove(active_walkers, 1)
        local walker_result = ConnectingRoads.stepWalker(current_walker, grid, districts, highway_points, map_w, map_h)
        
        if walker_result.completed_path then
            table.insert(walker_paths, walker_result.completed_path)
        end
        
        if walker_result.continue_walker then
            table.insert(active_walkers, walker_result.continue_walker)
        end
        
        -- Very rarely split to avoid too much chaos, but still allow some branching
        if walker_result.split_walker and love.math.random() < 0.05 and #active_walkers < 3 then
            table.insert(active_walkers, walker_result.split_walker)
        end
    end
    
    return walker_paths
end

function ConnectingRoads.stepWalker(walker, grid, districts, highway_points, map_w, map_h)
    local result = {}
    
    -- DEATH CONDITION 1: Check if we're out of bounds
    if not ConnectingRoads.inBounds(walker.x, walker.y, map_w, map_h) then
        print("Walker died: out of bounds")
        result.completed_path = walker.path
        return result
    end
    
    -- DEATH CONDITION 2: Check if we hit an existing road - SUCCESS!
    local current_tile = grid[walker.y][walker.x]
    if ConnectingRoads.isRoadTile(current_tile.type) then
        table.insert(walker.path, {x = walker.x, y = walker.y})
        print("Walker connected to existing road")
        result.completed_path = walker.path
        return result
    end
    
    -- DEATH CONDITION 3: Check if we're in ANY district
    local current_district = ConnectingRoads.findDistrictAtPosition(walker.x, walker.y, districts)
    if current_district then
        print("Walker died: entered district")
        result.completed_path = walker.path
        return result
    end

    -- FIX: NEW DEATH CONDITION 4: Check for loops by seeing if we have visited this tile before.
    local visited_key = walker.y .. "," .. walker.x
    if walker.visited[visited_key] then
        print("Walker died: detected a loop by re-visiting tile " .. visited_key)
        -- Return an empty result to indicate failure, preventing a partial road from being drawn.
        return {} 
    end
    -- If not visited, record this tile in our memory.
    walker.visited[visited_key] = true
    
    -- Walker survives, add current position to path
    table.insert(walker.path, {x = walker.x, y = walker.y})
    
    -- Look for nearby roads to connect to (but only roads NOT from our origin district)
    local nearby_road = ConnectingRoads.findNearbyRoadNotFromOrigin(
        walker.x, walker.y, walker.connection_distance, grid, walker.from_district, districts, map_w, map_h
    )
    
    if nearby_road then
        -- Strong attraction to nearby road - head directly toward it
        local dx = nearby_road.x - walker.x
        local dy = nearby_road.y - walker.y
        
        if math.abs(dx) > math.abs(dy) then
            walker.direction = {x = dx > 0 and 1 or -1, y = 0}
        else
            walker.direction = {x = 0, y = dy > 0 and 1 or -1}
        end
        print("Walker attracted to nearby road")
    else
        -- Random behavior when no target road is nearby
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
    end
    
    -- Move walker forward
    walker.x = walker.x + walker.direction.x
    walker.y = walker.y + walker.direction.y
    
    result.continue_walker = walker
    return result
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

function ConnectingRoads.findNearbyRoadNotFromOrigin(x, y, max_distance, grid, origin_district, districts, map_w, map_h)
    for radius = 1, max_distance do
        -- Check points in a circle around the walker
        for angle = 0, 359, 15 do  -- Check every 15 degrees
            local check_x = x + math.floor(radius * math.cos(math.rad(angle)))
            local check_y = y + math.floor(radius * math.sin(math.rad(angle)))
            
            if ConnectingRoads.inBounds(check_x, check_y, map_w, map_h) then
                local tile_type = grid[check_y][check_x].type
                
                if ConnectingRoads.isRoadTile(tile_type) then
                    -- Make sure this road is not from our origin district
                    local road_district = ConnectingRoads.findDistrictAtPosition(check_x, check_y, districts)
                    
                    -- Connect to roads that are either:
                    -- 1. Not in any district (highways, connecting roads)
                    -- 2. In a different district than our origin
                    if road_district ~= origin_district then
                        return {x = check_x, y = check_y}
                    end
                end
            end
        end
    end
    
    return nil
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
        visited = original_walker.visited, -- Share the visited history to prevent immediate loops
        from_district = original_walker.from_district,
        connection_distance = original_walker.connection_distance
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
                        if district_idx == 1 then
                            print(string.format("Downtown edge check x=%d y=%d: %s", x, edge.y, tile_type))
                        end
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
                        if district_idx == 1 then
                            print(string.format("Downtown edge check x=%d y=%d: %s", edge.x, y, tile_type))
                        end
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
            local max_walkers_this_side
            
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
            max_walkers_this_side = faces_downtown and 8 or 4
            
            -- Shuffle the roads and take up to the limit
            for i = #side_roads, 2, -1 do
                local j = love.math.random(i)
                side_roads[i], side_roads[j] = side_roads[j], side_roads[i]
            end
            
            local roads_to_use = math.min(#side_roads, max_walkers_this_side)
            for i = 1, roads_to_use do
                table.insert(boundary_points, side_roads[i])
            end
            
            if district_idx == 1 then
                print(string.format("DOWNTOWN %s side: %d/%d roads used (faces downtown: %s)", 
                      side_name, roads_to_use, #side_roads, tostring(faces_downtown)))
            else
                print(string.format("District %d %s side: %d/%d roads used (faces downtown: %s)", 
                      district_idx, side_name, roads_to_use, #side_roads, tostring(faces_downtown)))
            end
        end
    end
    
    print("Total boundary road tiles found:", #boundary_points)
    return boundary_points
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

    local dx = x2 - x1
    local dy = y2 - y1

    -- Check for the dominant axis
    if math.abs(dx) > math.abs(dy) then
        -- Line is more horizontal
        local x_min, x_max = math.min(x1, x2), math.max(x1, x2)
        for x = x_min, x_max do
            local y = math.floor(y1 + dy * (x - x1) / dx + 0.5)
            if ConnectingRoads.inBounds(x, y, w, h) then
                local current_type = grid[y][x].type
                if not ConnectingRoads.isRoadTile(current_type) then
                    grid[y][x].type = road_type
                end
            end
        end
    else
        -- Line is more vertical (or diagonal)
        local y_min, y_max = math.min(y1, y2), math.max(y1, y2)
        for y = y_min, y_max do
            -- Avoid division by zero for perfectly vertical lines
            local x = dx == 0 and x1 or math.floor(x1 + dx * (y - y1) / dy + 0.5)
            if ConnectingRoads.inBounds(x, y, w, h) then
                local current_type = grid[y][x].type
                if not ConnectingRoads.isRoadTile(current_type) then
                    grid[y][x].type = road_type
                end
            end
        end
    end
end

function ConnectingRoads.inBounds(x, y, width, height)
    return x >= 1 and x <= width and y >= 1 and y <= height
end

return ConnectingRoads