-- game/generators/districts.lua
-- District Generation Module with Connected Roads and No Overlap

local Districts = {}

function Districts.generateAll(grid, map_w, map_h, downtown_district_params, params)
    local all_districts = {}
    
    -- MODIFIED: Use the passed-in downtown parameters directly.
    -- This was the source of the bug; it was implicitly relying on old state.
    local downtown_dist = {
        x = downtown_district_params.x,
        y = downtown_district_params.y,
        w = downtown_district_params.w,
        h = downtown_district_params.h
    }
    table.insert(all_districts, downtown_dist)
    
    -- Use debug parameters or defaults
    local num_districts = (params and params.num_districts) or 8
    local district_min_size = (params and params.district_min_size) or 40
    local district_max_size = (params and params.district_max_size) or 80
    local district_placement_attempts = (params and params.district_placement_attempts) or 1000
    
    -- Generate non-overlapping districts using proper placement
    local other_districts = Districts.placeNonOverlappingDistricts(grid, num_districts, map_w, map_h, downtown_dist, 
                                                                   district_min_size, district_max_size, district_placement_attempts)
    for _, district in ipairs(other_districts) do
        table.insert(all_districts, district)
    end
    
    -- Fill districts with connected road networks
    for _, district in ipairs(other_districts) do
        Districts.generateConnectedRoadNetwork(grid, district, params)
    end
    
    return all_districts
end

function Districts.placeNonOverlappingDistricts(grid, num_districts, max_w, max_h, downtown_dist, 
                                               district_min_size, district_max_size, max_attempts)
    local districts = {}
    local attempts = 0
    
    -- MODIFIED: Create a local copy of the downtown district to check against.
    -- This was the source of the bug; it was implicitly using incorrect coordinates.
    local downtown_boundary = {
        x = downtown_dist.x,
        y = downtown_dist.y,
        w = downtown_dist.w,
        h = downtown_dist.h
    }
    
    while #districts < num_districts and attempts < max_attempts do
        local w = love.math.random(district_min_size, district_max_size)
        local h = love.math.random(district_min_size, district_max_size)
        local x = love.math.random(1, max_w - w)
        local y = love.math.random(1, max_h - h)
        
        local new_district = {x = x, y = y, w = w, h = h}
        
        local overlaps = false
        
        -- Check overlap with downtown using our corrected local boundary
        if Districts.doDistrictsOverlap(new_district, downtown_boundary) then
            overlaps = true
        end
        
        if not overlaps then
            for _, existing_district in ipairs(districts) do
                if Districts.doDistrictsOverlap(new_district, existing_district) then
                    overlaps = true
                    break
                end
            end
        end
        
        local min_border_distance = 10
        if x < min_border_distance or y < min_border_distance or 
           x + w > max_w - min_border_distance or y + h > max_h - min_border_distance then
            overlaps = true
        end
        
        if not overlaps then
            table.insert(districts, new_district)
        end
        
        attempts = attempts + 1
    end
    
    print(string.format("Successfully placed %d/%d districts after %d attempts", #districts, num_districts, attempts))
    return districts
end

function Districts.doDistrictsOverlap(district1, district2)
    -- REDUCED buffer from 15 to 5 to allow closer placement
    local buffer = 5
    
    local d1_left = district1.x - buffer
    local d1_right = district1.x + district1.w + buffer
    local d1_top = district1.y - buffer
    local d1_bottom = district1.y + district1.h + buffer
    
    local d2_left = district2.x
    local d2_right = district2.x + district2.w
    local d2_top = district2.y
    local d2_bottom = district2.y + district2.h
    
    -- Check if rectangles overlap
    return not (d1_right < d2_left or d1_left > d2_right or d1_bottom < d2_top or d1_top > d2_bottom)
end

function Districts.generateConnectedRoadNetwork(grid, district, params)
    local grid_w, grid_h = #grid[1], #grid
    
    -- Use debug parameters or defaults
    local district_roads_min = (params and params.district_roads_min) or 15
    local district_roads_max = (params and params.district_roads_max) or 30
    
    -- First, fill the district area with plots
    for y = district.y, district.y + district.h - 1 do
        for x = district.x, district.x + district.w - 1 do
            if Districts.inBounds(x, y, grid_w, grid_h) then
                grid[y][x].type = "plot"
            end
        end
    end
    
    -- Create a connected road network similar to downtown
    Districts.createConnectedRoads(grid, district, district_roads_min, district_roads_max)
end

function Districts.createConnectedRoads(grid, district, roads_min, roads_max)
    local grid_w, grid_h = #grid[1], #grid
    local road_tiles = {} -- Keep track of all road tiles for connectivity
    
    -- Create main cross roads through the center (like downtown)
    local center_x = district.x + math.floor(district.w / 2)
    local center_y = district.y + math.floor(district.h / 2)
    
    -- Vertical main road
    for y = district.y, district.y + district.h - 1 do
        if Districts.inBounds(center_x, y, grid_w, grid_h) then
            grid[y][center_x].type = "road"
            table.insert(road_tiles, {x = center_x, y = y})
        end
    end
    
    -- Horizontal main road
    for x = district.x, district.x + district.w - 1 do
        if Districts.inBounds(x, center_y, grid_w, grid_h) then
            grid[center_y][x].type = "road"
            table.insert(road_tiles, {x = x, y = center_y})
        end
    end
    
    -- ENSURE MINIMUM 3 ROADS PER SIDE FOR WALKER GENERATION
    Districts.ensureMinimumBoundaryRoads(grid, district, road_tiles)
    
    -- Add secondary roads that connect to the main cross
    local num_secondary_roads = roads_min + love.math.random(0, roads_max - roads_min)
    
    for i = 1, num_secondary_roads do
        if #road_tiles == 0 then break end
        
        -- Pick a random existing road tile to start from
        local start_node = road_tiles[love.math.random(1, #road_tiles)]
        
        -- Determine if we're on the main vertical or horizontal axis
        local is_on_vertical_axis = (start_node.x == center_x)
        local is_on_horizontal_axis = (start_node.y == center_y)
        
        if is_on_vertical_axis or is_on_horizontal_axis then
            -- Grow a perpendicular road from the main cross
            local dx, dy = 0, 0
            if is_on_vertical_axis then
                dx = love.math.random(0, 1) == 0 and -1 or 1 -- Go left or right
            else -- is_on_horizontal_axis
                dy = love.math.random(0, 1) == 0 and -1 or 1 -- Go up or down
            end
            
            local cx, cy = start_node.x + dx, start_node.y + dy
            local road_length = 0
            local max_road_length = math.min(district.w, district.h) / 3
            
            while Districts.inBounds(cx, cy, grid_w, grid_h) and road_length < max_road_length do
                -- Stop if we're outside the district boundaries
                if cx < district.x or cx >= district.x + district.w or 
                   cy < district.y or cy >= district.y + district.h then 
                    break 
                end
                
                -- Stop if we hit another road (creates intersections)
                if grid[cy][cx].type == "road" and (cx ~= start_node.x + dx or cy ~= start_node.y + dy) then 
                    break 
                end
                
                grid[cy][cx].type = "road"
                table.insert(road_tiles, {x = cx, y = cy})
                
                cx, cy = cx + dx, cy + dy
                road_length = road_length + 1
            end
        end
    end
    
    -- Add some random connecting roads for more variety
    local num_connecting_roads = 5 + love.math.random(0, 10)
    
    for i = 1, num_connecting_roads do
        if #road_tiles < 2 then break end
        
        -- Pick two random road tiles and try to connect them
        local start_tile = road_tiles[love.math.random(1, #road_tiles)]
        local end_tile = road_tiles[love.math.random(1, #road_tiles)]
        
        -- Only connect if they're reasonably close
        local distance = math.abs(start_tile.x - end_tile.x) + math.abs(start_tile.y - end_tile.y)
        if distance > 5 and distance < 20 then
            Districts.createSimpleConnection(grid, start_tile, end_tile, district)
        end
    end
end

function Districts.ensureMinimumBoundaryRoads(grid, district, road_tiles)
    local grid_w, grid_h = #grid[1], #grid
    local min_roads_per_side = 3
    
    -- Check each side and add roads if needed
    local sides = {
        {name = "top", x_start = district.x, x_end = district.x + district.w - 1, y = district.y, is_horizontal = true},
        {name = "bottom", x_start = district.x, x_end = district.x + district.w - 1, y = district.y + district.h - 1, is_horizontal = true},
        {name = "left", y_start = district.y, y_end = district.y + district.h - 1, x = district.x, is_horizontal = false},
        {name = "right", y_start = district.y, y_end = district.y + district.h - 1, x = district.x + district.w - 1, is_horizontal = false}
    }
    
    for _, side in ipairs(sides) do
        local existing_roads = {}
        
        if side.is_horizontal then
            -- Count existing roads on horizontal sides (top/bottom)
            for x = side.x_start, side.x_end do
                if Districts.inBounds(x, side.y, grid_w, grid_h) and grid[side.y][x].type == "road" then
                    table.insert(existing_roads, {x = x, y = side.y})
                end
            end
            
            -- Add more roads if needed
            local roads_needed = min_roads_per_side - #existing_roads
            if roads_needed > 0 then
                local side_length = side.x_end - side.x_start + 1
                local spacing = math.floor(side_length / (min_roads_per_side + 1))
                
                for i = 1, roads_needed do
                    local road_x = side.x_start + (i * spacing)
                    road_x = math.min(road_x, side.x_end) -- Clamp to side bounds
                    
                    if Districts.inBounds(road_x, side.y, grid_w, grid_h) and grid[side.y][road_x].type ~= "road" then
                        -- Create a road that connects to the interior
                        Districts.createBoundaryRoad(grid, road_x, side.y, district, road_tiles, side.name)
                    end
                end
            end
        else
            -- Count existing roads on vertical sides (left/right)
            for y = side.y_start, side.y_end do
                if Districts.inBounds(side.x, y, grid_w, grid_h) and grid[y][side.x].type == "road" then
                    table.insert(existing_roads, {x = side.x, y = y})
                end
            end
            
            -- Add more roads if needed
            local roads_needed = min_roads_per_side - #existing_roads
            if roads_needed > 0 then
                local side_length = side.y_end - side.y_start + 1
                local spacing = math.floor(side_length / (min_roads_per_side + 1))
                
                for i = 1, roads_needed do
                    local road_y = side.y_start + (i * spacing)
                    road_y = math.min(road_y, side.y_end) -- Clamp to side bounds
                    
                    if Districts.inBounds(side.x, road_y, grid_w, grid_h) and grid[road_y][side.x].type ~= "road" then
                        -- Create a road that connects to the interior
                        Districts.createBoundaryRoad(grid, side.x, road_y, district, road_tiles, side.name)
                    end
                end
            end
        end
        
        print(string.format("District side %s: %d existing roads, added %d roads", 
              side.name, #existing_roads, math.max(0, min_roads_per_side - #existing_roads)))
    end
end

function Districts.createBoundaryRoad(grid, start_x, start_y, district, road_tiles, side_name)
    local grid_w, grid_h = #grid[1], #grid
    
    -- Place the boundary road tile
    if Districts.inBounds(start_x, start_y, grid_w, grid_h) then
        grid[start_y][start_x].type = "road"
        table.insert(road_tiles, {x = start_x, y = start_y})
    end
    
    -- Determine direction to connect inward
    local dx, dy = 0, 0
    local max_length = math.min(district.w, district.h) / 4 -- Shorter connecting roads
    
    if side_name == "top" then
        dy = 1 -- Go down into district
    elseif side_name == "bottom" then
        dy = -1 -- Go up into district
    elseif side_name == "left" then
        dx = 1 -- Go right into district
    elseif side_name == "right" then
        dx = -1 -- Go left into district
    end
    
    -- Create a connecting road inward
    local cx, cy = start_x + dx, start_y + dy
    local road_length = 0
    
    while Districts.inBounds(cx, cy, grid_w, grid_h) and road_length < max_length do
        -- Stop if we're outside the district boundaries
        if cx < district.x or cx >= district.x + district.w or 
           cy < district.y or cy >= district.y + district.h then 
            break 
        end
        
        -- Stop if we hit an existing road (successful connection!)
        if grid[cy][cx].type == "road" then 
            break 
        end
        
        grid[cy][cx].type = "road"
        table.insert(road_tiles, {x = cx, y = cy})
        
        cx, cy = cx + dx, cy + dy
        road_length = road_length + 1
    end
end

function Districts.createSimpleConnection(grid, start_tile, end_tile, district)
    local grid_w, grid_h = #grid[1], #grid
    local cx, cy = start_tile.x, start_tile.y
    
    -- Simple L-shaped connection (go horizontal first, then vertical)
    -- Horizontal segment
    local target_x = end_tile.x
    local dx = target_x > cx and 1 or -1
    
    while cx ~= target_x and Districts.inBounds(cx, cy, grid_w, grid_h) do
        if cx >= district.x and cx < district.x + district.w and 
           cy >= district.y and cy < district.y + district.h then
            if grid[cy][cx].type ~= "road" then
                grid[cy][cx].type = "road"
            end
        end
        cx = cx + dx
    end
    
    -- Vertical segment
    local target_y = end_tile.y
    local dy = target_y > cy and 1 or -1
    
    while cy ~= target_y and Districts.inBounds(cx, cy, grid_w, grid_h) do
        if cx >= district.x and cx < district.x + district.w and 
           cy >= district.y and cy < district.y + district.h then
            if grid[cy][cx].type ~= "road" then
                grid[cy][cx].type = "road"
            end
        end
        cy = cy + dy
    end
end

function Districts.embedGrid(large_grid, small_grid, start_x, start_y, road_type, plot_type)
    local small_h, small_w = #small_grid, #small_grid[1]
    local large_w, large_h = #large_grid[1], #large_grid
    
    for y = 1, small_h do 
        for x = 1, small_w do
            local tx, ty = start_x + x, start_y + y
            if Districts.inBounds(tx, ty, large_w, large_h) then
                if small_grid[y][x].type == 'road' then 
                    large_grid[ty][tx].type = road_type 
                else 
                    large_grid[ty][tx].type = plot_type 
                end
            end
        end 
    end
    
    -- ENSURE DOWNTOWN ALSO HAS MINIMUM BOUNDARY ROADS
    local downtown_district = {
        x = start_x + 1, 
        y = start_y + 1, 
        w = small_w, 
        h = small_h
    }
    local road_tiles = {}
    
    -- Collect existing road tiles in downtown
    for y = 1, small_h do 
        for x = 1, small_w do
            local tx, ty = start_x + x, start_y + y
            if Districts.inBounds(tx, ty, large_w, large_h) and large_grid[ty][tx].type == road_type then
                table.insert(road_tiles, {x = tx, y = ty})
            end
        end 
    end
    
    Districts.ensureMinimumBoundaryRoads(large_grid, downtown_district, road_tiles)
end

-- Helper function to check if a grid coordinate is within the map boundaries
function Districts.inBounds(x, y, width, height)
    return x >= 1 and x <= width and y >= 1 and y <= height
end

return Districts