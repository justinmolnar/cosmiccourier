-- game/road_generator.lua
-- Hierarchical road network generation system

local Districts = require("data.districts")

local RoadGenerator = {}

function RoadGenerator.generateRoadNetwork(grid, grid_width, grid_height)
    -- Clear existing roads
    RoadGenerator.clearRoads(grid, grid_width, grid_height)
    
    -- Phase 1: Generate primary highway spine
    RoadGenerator.generatePrimaryHighways(grid, grid_width, grid_height)
    
    -- Phase 2: Generate secondary arterial roads connecting districts
    RoadGenerator.generateSecondaryArterials(grid, grid_width, grid_height)
    
    -- Phase 3: Generate local district road networks
    RoadGenerator.generateLocalNetworks(grid, grid_width, grid_height)
end

function RoadGenerator.clearRoads(grid, w, h)
    for y = 1, h do
        for x = 1, w do
            if grid[y][x].type == "road" or grid[y][x].type == "highway" or grid[y][x].type == "arterial" then
                grid[y][x].type = "grass"
            end
        end
    end
end

function RoadGenerator.generatePrimaryHighways(grid, w, h)
    local highways = Districts.ROAD_HIERARCHY.primary_highways
    
    for _, highway in ipairs(highways) do
        local start_x = math.floor(w * highway.start_x_percent)
        local start_y = math.floor(h * highway.start_y_percent)
        local end_x = math.floor(w * highway.end_x_percent)
        local end_y = math.floor(h * highway.end_y_percent)
        
        RoadGenerator.drawLine(grid, start_x, start_y, end_x, end_y, highway.type, w, h)
    end
end

function RoadGenerator.generateSecondaryArterials(grid, w, h)
    local districts = RoadGenerator.calculateDistrictBounds(w, h)
    
    for _, district in ipairs(districts) do
        if district.type ~= "park" then  -- Parks don't need highway connections
            local center_x = math.floor(w * district.center_x_percent)
            local center_y = math.floor(h * district.center_y_percent)
            
            -- Find nearest highway
            local nearest_highway = RoadGenerator.findNearestHighway(grid, center_x, center_y, w, h)
            
            if nearest_highway then
                -- Connect district center to highway
                RoadGenerator.drawLine(grid, center_x, center_y, nearest_highway.x, nearest_highway.y, "arterial", w, h)
            end
        end
    end
end

function RoadGenerator.generateLocalNetworks(grid, w, h)
    local districts = RoadGenerator.calculateDistrictBounds(w, h)
    
    for _, district in ipairs(districts) do
        if district.type == "industrial" then
            RoadGenerator.generateIndustrialGrid(grid, district, w, h)
        elseif district.type == "commercial" then
            RoadGenerator.generateCommercialGrid(grid, district, w, h)
        elseif district.type == "residential" then
            RoadGenerator.generateResidentialNetwork(grid, district, w, h)
        elseif district.type == "park" then
            RoadGenerator.generateParkPaths(grid, district, w, h)
        end
    end
end

function RoadGenerator.calculateDistrictBounds(w, h)
    local districts = {}
    
    for _, template in ipairs(Districts.CITY_LAYOUT) do
        local district = {
            name = template.name,
            type = template.type,
            x1 = math.max(1, math.floor(w * template.x1_percent)),
            y1 = math.max(1, math.floor(h * template.y1_percent)),
            x2 = math.min(w, math.floor(w * template.x2_percent)),
            y2 = math.min(h, math.floor(h * template.y2_percent)),
            center_x_percent = template.center_x_percent,
            center_y_percent = template.center_y_percent,
            density = template.density,
            road_density = template.road_density
        }
        table.insert(districts, district)
    end
    
    return districts
end

function RoadGenerator.findNearestHighway(grid, center_x, center_y, w, h)
    local min_distance = math.huge
    local nearest_point = nil
    
    -- Search in expanding radius from center
    for radius = 1, math.max(w, h) do
        for angle = 0, 359, 10 do
            local radian = math.rad(angle)
            local x = center_x + math.floor(radius * math.cos(radian))
            local y = center_y + math.floor(radius * math.sin(radian))
            
            if x >= 1 and x <= w and y >= 1 and y <= h then
                if grid[y][x].type == "highway" then
                    local distance = math.abs(x - center_x) + math.abs(y - center_y)
                    if distance < min_distance then
                        min_distance = distance
                        nearest_point = {x = x, y = y}
                    end
                end
            end
        end
        
        -- If we found a highway, return it
        if nearest_point then
            return nearest_point
        end
    end
    
    return nil
end

function RoadGenerator.drawLine(grid, x1, y1, x2, y2, road_type, w, h)
    -- Bresenham's line algorithm for any angle
    local dx = math.abs(x2 - x1)
    local dy = math.abs(y2 - y1)
    local sx = x1 < x2 and 1 or -1
    local sy = y1 < y2 and 1 or -1
    local err = dx - dy
    
    local x, y = x1, y1
    
    while true do
        if x >= 1 and x <= w and y >= 1 and y <= h then
            -- Don't overwrite highways with lesser roads
            if grid[y][x].type ~= "highway" or road_type == "highway" then
                grid[y][x].type = road_type
            end
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

function RoadGenerator.generateIndustrialGrid(grid, district, w, h)
    local spacing = Districts.ROAD_SPACING.industrial
    
    -- Horizontal roads
    for y = district.y1, district.y2, spacing do
        for x = district.x1, district.x2 do
            if x >= 1 and x <= w and y >= 1 and y <= h then
                if grid[y][x].type ~= "highway" and grid[y][x].type ~= "arterial" then
                    grid[y][x].type = "road"
                end
            end
        end
    end
    
    -- Vertical roads
    for x = district.x1, district.x2, spacing do
        for y = district.y1, district.y2 do
            if x >= 1 and x <= w and y >= 1 and y <= h then
                if grid[y][x].type ~= "highway" and grid[y][x].type ~= "arterial" then
                    grid[y][x].type = "road"
                end
            end
        end
    end
end

function RoadGenerator.generateCommercialGrid(grid, district, w, h)
    local spacing = Districts.ROAD_SPACING.commercial
    
    -- Dense grid pattern for commercial areas
    for y = district.y1, district.y2, spacing do
        for x = district.x1, district.x2 do
            if x >= 1 and x <= w and y >= 1 and y <= h then
                if grid[y][x].type ~= "highway" and grid[y][x].type ~= "arterial" then
                    grid[y][x].type = "road"
                end
            end
        end
    end
    
    for x = district.x1, district.x2, spacing do
        for y = district.y1, district.y2 do
            if x >= 1 and x <= w and y >= 1 and y <= h then
                if grid[y][x].type ~= "highway" and grid[y][x].type ~= "arterial" then
                    grid[y][x].type = "road"
                end
            end
        end
    end
end

function RoadGenerator.generateResidentialNetwork(grid, district, w, h)
    -- Create main residential roads
    local num_main_roads = math.max(2, math.floor((district.x2 - district.x1) / 8))
    
    for i = 1, num_main_roads do
        local x = district.x1 + math.floor((district.x2 - district.x1) * i / (num_main_roads + 1))
        for y = district.y1, district.y2 do
            if x >= 1 and x <= w and y >= 1 and y <= h then
                if grid[y][x].type ~= "highway" and grid[y][x].type ~= "arterial" then
                    grid[y][x].type = "road"
                end
            end
        end
    end
    
    -- Add some connecting roads
    local num_cross_roads = math.max(1, math.floor((district.y2 - district.y1) / 6))
    
    for i = 1, num_cross_roads do
        local y = district.y1 + math.floor((district.y2 - district.y1) * i / (num_cross_roads + 1))
        for x = district.x1, district.x2 do
            if x >= 1 and x <= w and y >= 1 and y <= h then
                if grid[y][x].type ~= "highway" and grid[y][x].type ~= "arterial" then
                    grid[y][x].type = "road"
                end
            end
        end
    end
end

function RoadGenerator.generateParkPaths(grid, district, w, h)
    -- Minimal paths through parks
    local center_x = math.floor((district.x1 + district.x2) / 2)
    local center_y = math.floor((district.y1 + district.y2) / 2)
    
    -- One main path through the center
    for x = district.x1, district.x2 do
        if x >= 1 and x <= w and center_y >= 1 and center_y <= h then
            if grid[center_y][x].type ~= "highway" and grid[center_y][x].type ~= "arterial" then
                grid[center_y][x].type = "road"
            end
        end
    end
end

return RoadGenerator