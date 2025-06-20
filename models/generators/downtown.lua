-- models/generators/downtown.lua
-- Downtown Core Generation Module

local Downtown = {}

function Downtown.generateDowntownModule(grid, district, road_type, plot_type, num_roads, params)
    -- This function now receives the main grid and carves the downtown area into it.
    -- Use debug parameters if provided
    local actual_num_roads = (params and params.downtown_roads) or num_roads or 50
    Downtown.generateConnectedRoads(grid, district, road_type, plot_type, actual_num_roads)
end

-- Helper function to create a grid of a given size and type
function Downtown.createGrid(width, height, default_type)
    local grid = {}
    for y = 1, height do
        grid[y] = {}
        for x = 1, width do
            grid[y][x] = { type = default_type or "grass" }
        end
    end
    return grid
end

function Downtown.generateConnectedRoads(grid, district, road_type, plot_type, num_roads)
    local grid_w, grid_h = #grid[1], #grid
    local road_tiles = {} -- Keep a list of all tiles that are roads
    
    -- Debug: Print district values to see what we're getting
    print("Downtown generator - district values:")
    print("  x:", district.x, type(district.x))
    print("  y:", district.y, type(district.y))
    print("  w:", district.w, type(district.w))
    print("  h:", district.h, type(district.h))
    print("  num_roads:", num_roads)
    
    -- Ensure all district values are numbers
    local dist_x = tonumber(district.x) or 0
    local dist_y = tonumber(district.y) or 0
    local dist_w = tonumber(district.w) or 10
    local dist_h = tonumber(district.h) or 10
    local num_roads_safe = tonumber(num_roads) or 50
    
    print("Downtown generator - converted values:")
    print("  dist_x:", dist_x)
    print("  dist_y:", dist_y)
    print("  dist_w:", dist_w)
    print("  dist_h:", dist_h)
    print("  num_roads_safe:", num_roads_safe)

    -- 1. Fill district area with plots first
    for y = dist_y, dist_y + dist_h - 1 do
        for x = dist_x, dist_x + dist_w - 1 do
            if Downtown.inBounds(x, y, grid_w, grid_h) then
                grid[y][x].type = plot_type
            end
        end
    end

    -- 2. Create a main horizontal and vertical "cross" to guarantee boundary connections.
    local center_x = dist_x + math.floor(dist_w / 2)
    local center_y = dist_y + math.floor(dist_h / 2)
    
    -- Vertical Road
    for y = dist_y, dist_y + dist_h - 1 do
        if Downtown.inBounds(center_x, y, grid_w, grid_h) then
            grid[y][center_x].type = road_type
            table.insert(road_tiles, {x = center_x, y = y})
        end
    end
    -- Horizontal Road
    for x = dist_x, dist_x + dist_w - 1 do
        if Downtown.inBounds(x, center_y, grid_w, grid_h) then
            grid[center_y][x].type = road_type
            table.insert(road_tiles, {x = x, y = center_y})
        end
    end

    -- 3. Grow new grid-like roads off of the main cross.
    for i = 1, num_roads_safe do
        if #road_tiles == 0 then break end
        
        -- Pick a random existing road tile to start from
        local start_node = road_tiles[love.math.random(1, #road_tiles)]
        
        -- Determine if the start node is on the horizontal or vertical axis of the cross
        local is_on_vertical_axis = (start_node.x == center_x)
        local is_on_horizontal_axis = (start_node.y == center_y)

        if is_on_vertical_axis or is_on_horizontal_axis then
            -- Grow a perpendicular road from the main cross
            local dx, dy = 0, 0
            if is_on_vertical_axis then
                dx = love.math.random(0,1) == 0 and -1 or 1 -- Grow left or right
            else -- is_on_horizontal_axis
                dy = love.math.random(0,1) == 0 and -1 or 1 -- Grow up or down
            end

            local cx, cy = start_node.x + dx, start_node.y + dy
            while Downtown.inBounds(cx, cy, grid_w, grid_h) do
                if cx < dist_x or cx >= dist_x + dist_w or 
                   cy < dist_y or cy >= dist_y + dist_h then 
                    break 
                end
                if grid[cy][cx].type == road_type then break end -- Stop if we hit another road
                grid[cy][cx].type = road_type
                table.insert(road_tiles, {x = cx, y = cy})
                cx, cy = cx + dx, cy + dy
            end
        end
    end
end

-- Helper function to check if a grid coordinate is within the map boundaries
function Downtown.inBounds(x, y, width, height)
    return x >= 1 and x <= width and y >= 1 and y <= height
end

return Downtown