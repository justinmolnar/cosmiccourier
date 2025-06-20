-- game/city_generator.lua
-- Logic for generating realistic city layouts at metropolitan scale

local Districts = require("data.districts")

local CityGenerator = {}

function CityGenerator.generateCity(grid, building_plots, grid_width, grid_height)
    -- Step 1: Fill everything with urban development first
    CityGenerator.fillUrbanArea(grid, grid_width, grid_height)
    
    -- Step 2: Carve out the major highway network
    CityGenerator.createHighwayNetwork(grid, grid_width, grid_height)
    
    -- Step 3: Define district density variations
    CityGenerator.createDistrictDensities(grid, grid_width, grid_height)
    
    -- Step 4: Create the visible downtown core
    CityGenerator.createDowntownCore(grid, grid_width, grid_height)
    
    -- Step 5: Add minimal building plots (representing city blocks)
    CityGenerator.addCityBlocks(grid, building_plots, grid_width, grid_height)
end

function CityGenerator.fillUrbanArea(grid, w, h)
    -- Fill most of the map with urban development (plots)
    for y = 1, h do
        for x = 1, w do
            -- 85% urban coverage - this represents the built-up metropolitan area
            if love.math.random() < 0.85 then
                grid[y][x].type = "plot"
            end
        end
    end
end

function CityGenerator.createHighwayNetwork(grid, w, h)
    local highways = Districts.ROAD_HIERARCHY.primary_highways
    
    for _, highway in ipairs(highways) do
        local start_x = math.floor(w * highway.start_x_percent)
        local start_y = math.floor(h * highway.start_y_percent)
        local end_x = math.floor(w * highway.end_x_percent)
        local end_y = math.floor(h * highway.end_y_percent)
        
        -- Draw thick highways (3 pixels wide)
        CityGenerator.drawThickLine(grid, start_x, start_y, end_x, end_y, "highway", w, h, 3)
    end
end

function CityGenerator.createDistrictDensities(grid, w, h)
    local districts = CityGenerator.calculateDistrictBounds(w, h)
    
    for _, district in ipairs(districts) do
        CityGenerator.applyDistrictDensity(grid, district, w, h)
    end
end

function CityGenerator.createDowntownCore(grid, w, h)
    -- Downtown core - very dense area in the center
    local center_x = math.floor(w / 2)
    local center_y = math.floor(h / 2)
    local core_radius = math.min(w, h) * 0.08  -- 8% of map size
    
    for y = 1, h do
        for x = 1, w do
            local distance = math.sqrt((x - center_x)^2 + (y - center_y)^2)
            if distance <= core_radius then
                -- Downtown core is 100% developed
                if grid[y][x].type ~= "highway" then
                    grid[y][x].type = "plot"
                end
            end
        end
    end
end

function CityGenerator.calculateDistrictBounds(w, h)
    local districts = {}
    
    for _, template in ipairs(Districts.CITY_LAYOUT) do
        local district = {
            name = template.name,
            type = template.type,
            x1 = math.max(1, math.floor(w * template.x1_percent)),
            y1 = math.max(1, math.floor(h * template.y1_percent)),
            x2 = math.min(w, math.floor(w * template.x2_percent)),
            y2 = math.min(h, math.floor(h * template.y2_percent)),
            density = template.density
        }
        table.insert(districts, district)
    end
    
    return districts
end

function CityGenerator.applyDistrictDensity(grid, district, w, h)
    for y = district.y1, district.y2 do
        for x = district.x1, district.x2 do
            if x >= 1 and x <= w and y >= 1 and y <= h then
                if grid[y][x].type ~= "highway" then
                    -- Apply district-specific density
                    if love.math.random() < district.density then
                        grid[y][x].type = "plot"
                    else
                        grid[y][x].type = "grass"  -- Parks, open space, etc.
                    end
                end
            end
        end
    end
end

function CityGenerator.drawThickLine(grid, x1, y1, x2, y2, road_type, w, h, thickness)
    -- Bresenham's line algorithm
    local dx = math.abs(x2 - x1)
    local dy = math.abs(y2 - y1)
    local sx = x1 < x2 and 1 or -1
    local sy = y1 < y2 and 1 or -1
    local err = dx - dy
    
    local x, y = x1, y1
    
    while true do
        -- Draw thick line by filling area around the center line
        for offset_x = -thickness + 1, thickness - 1 do
            for offset_y = -thickness + 1, thickness - 1 do
                local draw_x = x + offset_x
                local draw_y = y + offset_y
                if draw_x >= 1 and draw_x <= w and draw_y >= 1 and draw_y <= h then
                    grid[draw_y][draw_x].type = road_type
                end
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

function CityGenerator.addCityBlocks(grid, building_plots, w, h)
    -- At city scale, "building plots" represent entire city blocks
    for y = 1, h do
        for x = 1, w do
            if grid[y][x].type == "plot" then
                table.insert(building_plots, {x = x, y = y})
            end
        end
    end
end

return CityGenerator