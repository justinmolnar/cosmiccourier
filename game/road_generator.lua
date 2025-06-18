-- game/road_generator.lua
-- Hierarchical road network generation system with more variation

local Districts = require("data.districts")

local RoadGenerator = {}

function RoadGenerator.generateRoadNetwork(grid, grid_width, grid_height)
    RoadGenerator.clearRoads(grid, grid_width, grid_height)
    RoadGenerator.generatePrimaryHighways(grid, grid_width, grid_height)
    RoadGenerator.generateSecondaryArterials(grid, grid_width, grid_height)
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
        RoadGenerator.drawLine(grid, start_x, start_y, end_x, end_y, "highway", w, h)
    end
end

function RoadGenerator.generateSecondaryArterials(grid, w, h)
    local districts = RoadGenerator.calculateDistrictBounds(w, h)
    
    for _, district in ipairs(districts) do
        if district.type ~= "park" then
            local center_x = math.floor(w * district.center_x_percent)
            local center_y = math.floor(h * district.center_y_percent)
            local nearest_highway = RoadGenerator.findNearestHighway(grid, center_x, center_y, w, h)
            if nearest_highway then
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
        table.insert(districts, {
            name = template.name, type = template.type,
            x1 = math.max(1, math.floor(w * template.x1_percent)),
            y1 = math.max(1, math.floor(h * template.y1_percent)),
            x2 = math.min(w, math.floor(w * template.x2_percent)),
            y2 = math.min(h, math.floor(h * template.y2_percent)),
            center_x_percent = template.center_x_percent,
            center_y_percent = template.center_y_percent,
            density = template.density, road_density = template.road_density
        })
    end
    return districts
end

function RoadGenerator.findNearestHighway(grid, center_x, center_y, w, h)
    local min_distance = math.huge
    local nearest_point = nil
    for radius = 1, math.max(w, h) do
        for angle = 0, 359, 10 do
            local radian = math.rad(angle)
            local x = center_x + math.floor(radius * math.cos(radian))
            local y = center_y + math.floor(radius * math.sin(radian))
            if x >= 1 and x <= w and y >= 1 and y <= h and grid[y][x].type == "highway" then
                local distance = math.abs(x - center_x) + math.abs(y - center_y)
                if distance < min_distance then
                    min_distance = distance
                    nearest_point = {x = x, y = y}
                end
            end
        end
        if nearest_point then return nearest_point end
    end
    return nil
end

function RoadGenerator.drawLine(grid, x1, y1, x2, y2, road_type, w, h)
    local dx = math.abs(x2 - x1)
    local dy = math.abs(y2 - y1)
    local sx = x1 < x2 and 1 or -1
    local sy = y1 < y2 and 1 or -1
    local err = dx - dy
    local x, y = x1, y1
    while true do
        if x >= 1 and x <= w and y >= 1 and y <= h then
            if grid[y][x].type ~= "highway" or road_type == "highway" then
                grid[y][x].type = road_type
            end
        end
        if x == x2 and y == y2 then break end
        local e2 = 2 * err
        if e2 > -dy then err = err - dy; x = x + sx end
        if e2 < dx then err = err + dx; y = y + sy end
    end
end

-- UPDATED GENERATORS with more variety --

function RoadGenerator.generateGridPattern(grid, district, w, h, base_spacing, randomness_factor)
    -- Horizontal roads
    local y = district.y1
    while y < district.y2 do
        local segment_end_x = district.x1 + math.floor((district.x2 - district.x1) * (0.6 + love.math.random() * 0.4))
        RoadGenerator.drawLine(grid, district.x1, y, segment_end_x, y, "road", w, h)
        y = y + base_spacing + math.random(-randomness_factor, randomness_factor)
    end
    
    -- Vertical roads
    local x = district.x1
    while x < district.x2 do
        local segment_end_y = district.y1 + math.floor((district.y2 - district.y1) * (0.6 + love.math.random() * 0.4))
        RoadGenerator.drawLine(grid, x, district.y1, x, segment_end_y, "road", w, h)
        x = x + base_spacing + math.random(-randomness_factor, randomness_factor)
    end
end

function RoadGenerator.generateIndustrialGrid(grid, district, w, h)
    RoadGenerator.generateGridPattern(grid, district, w, h, Districts.ROAD_SPACING.industrial, 5)
end

function RoadGenerator.generateCommercialGrid(grid, district, w, h)
    -- Commercial is a very dense, more complete grid
    local spacing = Districts.ROAD_SPACING.commercial
    for y = district.y1, district.y2, spacing do
        RoadGenerator.drawLine(grid, district.x1, y, district.x2, y, "road", w, h)
    end
    for x = district.x1, district.x2, spacing do
        RoadGenerator.drawLine(grid, x, district.y1, x, district.y2, "road", w, h)
    end
end

function RoadGenerator.generateResidentialNetwork(grid, district, w, h)
    RoadGenerator.generateGridPattern(grid, district, w, h, Districts.ROAD_SPACING.residential, 3)
end

function RoadGenerator.generateParkPaths(grid, district, w, h)
    local center_x = math.floor((district.x1 + district.x2) / 2)
    local center_y = math.floor((district.y1 + district.y2) / 2)
    RoadGenerator.drawLine(grid, district.x1, center_y, district.x2, center_y, "road", w, h)
    RoadGenerator.drawLine(grid, center_x, district.y1, center_x, district.y2, "road", w, h)
end

return RoadGenerator