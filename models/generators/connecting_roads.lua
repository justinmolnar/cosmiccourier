-- game/generators/connecting_roads.lua
-- Walker-based Connecting Roads Generation Module with Clear Death Rules

local ConnectingRoads = {}

function ConnectingRoads.generateConnections(grid, districts, highway_points, map_w, map_h, game)
    print("Starting walker-based road generation...")
    
    local starting_points = ConnectingRoads.findDistrictBoundaryRoads(grid, districts, highway_points, map_w, map_h, game)
    print("Found", #starting_points, "starting points for walkers")
    
    local all_walker_paths = {}
    for _, start_point in ipairs(starting_points) do
        local walker_paths = ConnectingRoads.createWalkersFromPoint(grid, start_point, districts, highway_points, map_w, map_h, game)
        for _, path in ipairs(walker_paths) do
            table.insert(all_walker_paths, path)
        end
    end
    
    print("Generated", #all_walker_paths, "walker paths")
    return all_walker_paths
end

function ConnectingRoads.createWalkersFromPoint(grid, start_point, districts, highway_points, map_w, map_h, game)
    local walker_paths = {}
    
    local walker = {
        x = start_point.x + start_point.direction.x,
        y = start_point.y + start_point.direction.y,
        direction = {x = start_point.direction.x, y = start_point.direction.y},
        path = {{x = start_point.x, y = start_point.y}},
        visited = {},
        from_district = start_point.district,
        connection_distance = 65
    }
    
    local active_walkers = {walker}
    
    while #active_walkers > 0 do
        local current_walker = table.remove(active_walkers, 1)
        local walker_result = ConnectingRoads.stepWalker(current_walker, grid, districts, highway_points, map_w, map_h, game)
        
        if walker_result.completed_path then
            table.insert(walker_paths, walker_result.completed_path)
        end
        
        if walker_result.continue_walker then
            table.insert(active_walkers, walker_result.continue_walker)
        end
        
        if walker_result.split_walker and love.math.random() < 0.05 and #active_walkers < 3 then
            table.insert(active_walkers, walker_result.split_walker)
        end
    end
    
    return walker_paths
end

function ConnectingRoads.stepWalker(walker, grid, districts, highway_points, map_w, map_h, game)
    local result = {}
    
    if not ConnectingRoads.inBounds(walker.x, walker.y, map_w, map_h) then
        return result
    end
    
    local current_tile = grid[walker.y][walker.x]
    local road_district = ConnectingRoads.findDistrictAtPosition(walker.x, walker.y, districts)

    -- Use the central, correct isRoad function
    if game.map:isRoad(current_tile.type) and (road_district ~= walker.from_district) then
        table.insert(walker.path, {x = walker.x, y = walker.y})
        result.completed_path = walker.path
        return result
    end
    
    if walker.path and #walker.path > (map_w + map_h) then return result end
    local visited_key = walker.y .. "," .. walker.x
    if walker.visited[visited_key] then return {} end
    walker.visited[visited_key] = true
    
    table.insert(walker.path, {x = walker.x, y = walker.y})
    
    local nearby_road = ConnectingRoads.findNearbyRoadNotFromOrigin(
        walker.x, walker.y, walker.connection_distance, grid, walker.from_district, districts, map_w, map_h, game
    )
    
    if nearby_road then
        local dx = nearby_road.x - walker.x
        local dy = nearby_road.y - walker.y
        if math.abs(dx) > math.abs(dy) then
            walker.direction = {x = dx > 0 and 1 or -1, y = 0}
        else
            walker.direction = {x = 0, y = dy > 0 and 1 or -1}
        end
    else
        local random_chance = love.math.random()
        if random_chance < 0.05 then
            result.split_walker = ConnectingRoads.createSplitWalker(walker)
        elseif random_chance < 0.15 then
            ConnectingRoads.turnWalker(walker)
        end
    end
    
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


function ConnectingRoads.findNearbyRoadNotFromOrigin(x, y, max_distance, grid, origin_district, districts, map_w, map_h, game)
    for radius = 1, max_distance do
        for angle = 0, 359, 15 do
            local check_x = x + math.floor(radius * math.cos(math.rad(angle)))
            local check_y = y + math.floor(radius * math.sin(math.rad(angle)))
            
            if ConnectingRoads.inBounds(check_x, check_y, map_w, map_h) then
                local tile_type = grid[check_y][check_x].type
                
                if game.map:isRoad(tile_type) then
                    local road_district = ConnectingRoads.findDistrictAtPosition(check_x, check_y, districts)
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

function ConnectingRoads.findDistrictBoundaryRoads(grid, districts, highway_points, map_w, map_h, game)
    local boundary_points = {}
    local downtown = districts[1]
    local downtown_center_x = downtown.x + downtown.w / 2
    local downtown_center_y = downtown.y + downtown.h / 2
    
    for district_idx, district in ipairs(districts) do
        local district_center_x = district.x + district.w / 2
        local district_center_y = district.y + district.h / 2
        
        local sides = { top = {}, bottom = {}, left = {}, right = {} }
        
        local edges = {
            {x_start = district.x, x_end = district.x + district.w - 1, y = district.y, direction = {x = 0, y = -1}, side = "top"},
            {x_start = district.x, x_end = district.x + district.w - 1, y = district.y + district.h - 1, direction = {x = 0, y = 1}, side = "bottom"},
            {x = district.x, y_start = district.y, y_end = district.y + district.h - 1, direction = {x = -1, y = 0}, side = "left"},
            {x = district.x + district.w - 1, y_start = district.y, y_end = district.y + district.h - 1, direction = {x = 1, y = 0}, side = "right"}
        }
        
        for _, edge in ipairs(edges) do
            if edge.x_start then
                for x = edge.x_start, edge.x_end do
                    if ConnectingRoads.inBounds(x, edge.y, map_w, map_h) then
                        if game.map:isRoad(grid[edge.y][x].type) then
                            table.insert(sides[edge.side], { x = x, y = edge.y, direction = edge.direction, district = district })
                        end
                    end
                end
            else
                for y = edge.y_start, edge.y_end do
                    if ConnectingRoads.inBounds(edge.x, y, map_w, map_h) then
                        if game.map:isRoad(grid[y][edge.x].type) then
                            table.insert(sides[edge.side], { x = edge.x, y = y, direction = edge.direction, district = district })
                        end
                    end
                end
            end
        end
        
        for side_name, side_roads in pairs(sides) do
            local faces_downtown = false
            if side_name == "top" and district_center_y > downtown_center_y then faces_downtown = true
            elseif side_name == "bottom" and district_center_y < downtown_center_y then faces_downtown = true
            elseif side_name == "left" and district_center_x > downtown_center_x then faces_downtown = true
            elseif side_name == "right" and district_center_x < downtown_center_x then faces_downtown = true end
            
            local max_walkers_this_side = faces_downtown and 8 or 4
            
            for i = #side_roads, 2, -1 do
                local j = love.math.random(i)
                side_roads[i], side_roads[j] = side_roads[j], side_roads[i]
            end
            
            local roads_to_use = math.min(#side_roads, max_walkers_this_side)
            for i = 1, roads_to_use do
                table.insert(boundary_points, side_roads[i])
            end
        end
    end
    
    return boundary_points
end

function ConnectingRoads.drawConnections(grid, walker_paths, game)
    for _, path in ipairs(walker_paths) do
        for i = 1, #path - 1 do
            -- FIX: Pass the 'game' object to drawThinLine
            ConnectingRoads.drawThinLine(grid, path[i].x, path[i].y, path[i+1].x, path[i+1].y, "road", game)
        end
    end
end

function ConnectingRoads.drawThinLine(grid, x1, y1, x2, y2, road_type, game)
    if not grid or #grid == 0 then return end
    local w, h = #grid[1], #grid

    local dx = x2 - x1
    local dy = y2 - y1

    if math.abs(dx) > math.abs(dy) then
        local x_min, x_max = math.min(x1, x2), math.max(x1, x2)
        for x = x_min, x_max do
            local y = math.floor(y1 + dy * (x - x1) / dx + 0.5)
            if ConnectingRoads.inBounds(x, y, w, h) then
                local current_type = grid[y][x].type
                -- FIX: Use the central game.map:isRoad function
                if not game.map:isRoad(current_type) then
                    grid[y][x].type = road_type
                end
            end
        end
    else
        local y_min, y_max = math.min(y1, y2), math.max(y1, y2)
        for y = y_min, y_max do
            local x = dx == 0 and x1 or math.floor(x1 + dx * (y - y1) / dy + 0.5)
            if ConnectingRoads.inBounds(x, y, w, h) then
                local current_type = grid[y][x].type
                -- FIX: Use the central game.map:isRoad function
                if not game.map:isRoad(current_type) then
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