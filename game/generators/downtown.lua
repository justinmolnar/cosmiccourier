-- game/generators/downtown.lua
-- Downtown Core Generation Module

local Downtown = {}

function Downtown.generateDowntownModule(C_MAP)
    local w, h = C_MAP.DOWNTOWN_GRID_WIDTH, C_MAP.DOWNTOWN_GRID_HEIGHT
    local grid = Downtown.createGrid(w, h, "plot")
    -- Call the new, improved generation function
    Downtown.generateConnectedRoads(grid, {x=1, y=1, w=w, h=h}, "road", "plot", C_MAP.NUM_SECONDARY_ROADS)
    return grid
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

    -- 1. Fill district area with plots first
    for y = district.y, district.y + district.h - 1 do
        for x = district.x, district.x + district.w - 1 do
            if Downtown.inBounds(x, y, grid_w, grid_h) then
                grid[y][x].type = plot_type
            end
        end
    end

    -- 2. Create a main horizontal and vertical "cross" to guarantee boundary connections.
    local center_x = district.x + math.floor(district.w / 2)
    local center_y = district.y + math.floor(district.h / 2)
    
    -- Vertical Road
    for y = district.y, district.y + district.h - 1 do
        if Downtown.inBounds(center_x, y, grid_w, grid_h) then
            grid[y][center_x].type = road_type
            table.insert(road_tiles, {x = center_x, y = y})
        end
    end
    -- Horizontal Road
    for x = district.x, district.x + district.w - 1 do
        if Downtown.inBounds(x, center_y, grid_w, grid_h) then
            -- *** FIX: The grid was indexed incorrectly as grid[x][y] instead of grid[y][x]. ***
            grid[center_y][x].type = road_type
            table.insert(road_tiles, {x = x, y = center_y})
        end
    end

    -- 3. Grow new grid-like roads off of the main cross.
    for i = 1, num_roads do
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