-- game/generators/districts.lua
-- District Generation Module

local Districts = {}

function Districts.generateAll(grid, map_w, map_h, downtown_grid, map_instance) -- <<< MODIFY THIS LINE
    local all_districts = {}
    
    -- 1. Place the downtown district
    local downtown_w, downtown_h = #downtown_grid[1], #downtown_grid
    local start_x, start_y = math.floor((map_w - downtown_w) / 2), math.floor((map_h - downtown_h) / 2)
    
    -- <<< ADD THIS BLOCK TO STORE THE OFFSET >>>
    if map_instance then
        map_instance.downtown_offset = {x = start_x, y = start_y}
        print("Downtown offset stored at:", start_x, start_y)
    end
    
    local downtown_district = {x = start_x, y = start_y, w = downtown_w, h = downtown_h}
    table.insert(all_districts, downtown_district)
    
    -- 2. Generate surrounding districts
    local other_districts = Districts.placeDistricts(grid, 10, map_w, map_h, downtown_district)
    for _, district in ipairs(other_districts) do
        table.insert(all_districts, district)
    end
    
    -- 3. Fill districts with their internal road networks
    -- FIXED: Use regular "road" and "plot" for downtown instead of "downtown_road" and "downtown_plot"
    Districts.embedGrid(grid, downtown_grid, start_x, start_y, "road", "plot")
    for _, district in ipairs(other_districts) do
        Districts.generateDistrictInternals(grid, district, "road", "plot")
    end
    
    return all_districts
end

function Districts.placeDistricts(grid, num_districts, max_w, max_h, downtown_dist)
    local districts = {}
    local attempts = 0
    
    while #districts < num_districts and attempts < 500 do
        local w, h = love.math.random(40, 80), love.math.random(40, 80)
        local x, y = love.math.random(1, max_w - w), love.math.random(1, max_h - h)
        local valid = true
        
        -- Check if overlaps with downtown
        if x < downtown_dist.x + downtown_dist.w and x + w > downtown_dist.x and 
           y < downtown_dist.y + downtown_dist.h and y + h > downtown_dist.y then
            valid = false
        end
        
        -- Check if the area is suitable (sample a few points)
        if valid then
            for i = 1, 5 do
                local cx, cy = love.math.random(x, x + w), love.math.random(y, y + h)
                if not Districts.inBounds(cx, cy, max_w, max_h) or grid[cy][cx].type ~= 'plot' then
                    valid = false
                    break
                end
            end
        end
        
        if valid then
            table.insert(districts, {x = x, y = y, w = w, h = h})
        end
        
        attempts = attempts + 1
    end
    
    return districts
end

function Districts.generateDistrictInternals(grid, district, road_type, plot_type, num_roads_override)
    local grid_w, grid_h = #grid[1], #grid
    
    -- Fill district area with plots
    for y = district.y, district.y + district.h - 1 do
        for x = district.x, district.x + district.w - 1 do
            if Districts.inBounds(x, y, grid_w, grid_h) then
                local current_type = grid[y][x].type
                -- FIXED: Don't check for downtown_plot and downtown_road since we're not using them anymore
                if current_type ~= 'plot' and current_type ~= 'road' then 
                    grid[y][x].type = plot_type 
                end
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
        while Districts.inBounds(cx, cy, grid_w, grid_h) do
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
end

-- Helper function to check if a grid coordinate is within the map boundaries
function Districts.inBounds(x, y, width, height)
    return x >= 1 and x <= width and y >= 1 and y <= height
end

return Districts