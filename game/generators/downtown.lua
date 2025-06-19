-- game/generators/downtown.lua
-- Downtown Core Generation Module

local Downtown = {}

function Downtown.generateDowntownModule(C_MAP)
    local w, h = C_MAP.DOWNTOWN_GRID_WIDTH, C_MAP.DOWNTOWN_GRID_HEIGHT
    local grid = Downtown.createGrid(w, h, "plot")
    Downtown.generateDistrictInternals(grid, {x=1, y=1, w=w, h=h}, "road", "plot", C_MAP.NUM_SECONDARY_ROADS)
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

function Downtown.generateDistrictInternals(grid, district, road_type, plot_type, num_roads_override)
    local grid_w, grid_h = #grid[1], #grid
    
    -- Fill district area with plots
    for y = district.y, district.y + district.h - 1 do
        for x = district.x, district.x + district.w - 1 do
            if Downtown.inBounds(x, y, grid_w, grid_h) then
                grid[y][x].type = plot_type
            end
        end
    end
    
    -- Generate internal roads
    local num_secondary_roads = num_roads_override or (15 + love.math.random(0, 15))
    for i = 1, num_secondary_roads do
        local sx, sy = love.math.random(district.x, district.x + district.w - 1), 
                       love.math.random(district.y, district.y + district.h - 1)
        local dir, dx, dy = love.math.random(0, 3), 0, 0
        
        if dir == 0 then 
            dy = -1 
        elseif dir == 1 then 
            dy = 1 
        end
        if dir == 2 then 
            dx = -1 
        elseif dir == 3 then 
            dx = 1 
        end
        
        local cx, cy = sx, sy
        while Downtown.inBounds(cx, cy, grid_w, grid_h) do
            if cx < district.x or cx >= district.x + district.w or 
               cy < district.y or cy >= district.y + district.h then 
                break 
            end
            if grid[cy][cx].type == road_type and (cx ~= sx or cy ~= sy) then 
                break 
            end
            grid[cy][cx].type = road_type
            cx, cy = cx + dx, cy + dy
        end
    end
end

-- Helper function to check if a grid coordinate is within the map boundaries
function Downtown.inBounds(x, y, width, height)
    return x >= 1 and x <= width and y >= 1 and y <= height
end

return Downtown