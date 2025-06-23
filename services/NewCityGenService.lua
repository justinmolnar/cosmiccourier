-- services/NewCityGenService.lua
-- New WFC-based city generator service as described in the master plan

local NewCityGenService = {}

-- Import required modules
local WFC = require("lib.wfc")

-- Zone states for WFC
local ZONE_STATES = {
    "downtown",
    "commercial", 
    "residential",
    "industrial",
    "park"
}

function NewCityGenService.generateDetailedCity(params)
    print("NewCityGenService: Starting detailed city generation with WFC")
    
    -- Extract parameters with defaults
    local width = params.width or 64
    local height = params.height or 48
    local terrain_data = params.terrain_data or {}
    local highway_connections = params.highway_connections or {}
    local use_wfc_for_zones = params.use_wfc_for_zones or true
    local use_wfc_for_arterials = params.use_wfc_for_arterials or false
    local use_wfc_for_details = params.use_wfc_for_details or false
    
    local city_grid = NewCityGenService._createEmptyGrid(width, height)
    
    -- STAGE 1: Zone Generation
    print("NewCityGenService: Stage 1 - Zone Generation")
    local zone_grid
    if use_wfc_for_zones then
        zone_grid = NewCityGenService._generateZonesWithWFC(width, height, params)
    else
        zone_grid = NewCityGenService._generateZonesSimple(width, height, params)
    end
    
    if not zone_grid then
        print("ERROR: Zone generation failed!")
        return nil
    end
    
    -- STAGE 2: Arterial Road Generation  
    print("NewCityGenService: Stage 2 - Arterial Road Generation")
    if use_wfc_for_arterials then
        NewCityGenService._generateArterialsWithWFC(city_grid, zone_grid, highway_connections, params)
    else
        NewCityGenService._generateArterialsSimple(city_grid, zone_grid, highway_connections, params)
    end
    
    -- STAGE 3: Local Detail Generation
    print("NewCityGenService: Stage 3 - Local Detail Generation")
    if use_wfc_for_details then
        NewCityGenService._generateDetailsWithWFC(city_grid, zone_grid, params)
    else
        NewCityGenService._generateDetailsSimple(city_grid, zone_grid, params)
    end
    
    print("NewCityGenService: City generation complete")
    return {
        city_grid = city_grid,
        zone_grid = zone_grid,
        stats = {
            width = width,
            height = height,
            zones_generated = NewCityGenService._countZones(zone_grid),
            generation_method = use_wfc_for_zones and "WFC" or "Simple"
        }
    }
end

-- Create an empty grid filled with grass
function NewCityGenService._createEmptyGrid(width, height)
    local grid = {}
    for y = 1, height do
        grid[y] = {}
        for x = 1, width do
            grid[y][x] = { type = "grass" }
        end
    end
    return grid
end

-- Generate zones using WFC
function NewCityGenService._generateZonesWithWFC(width, height, params)
    print("NewCityGenService: Using WFC for zone generation")
    
    -- Create WFC instance
    local wfc = WFC.new(width, height, ZONE_STATES)
    
    -- Set up zone constraints for coherent blob generation
    WFC.setZoneConstraints(wfc)
    
    -- Add initial downtown constraint in the center
    local center_x = math.floor(width / 2)
    local center_y = math.floor(height / 2)
    
    print(string.format("NewCityGenService: Placing downtown constraint at (%d, %d)", center_x, center_y))
    WFC.collapse(wfc, center_x, center_y, "downtown")
    
    -- Optional: Add some additional constraints based on params
    if params.industrial_zones then
        -- Place industrial zones near edges
        local edge_positions = {
            {x = 5, y = 5, zone = "industrial"},
            {x = width - 5, y = height - 5, zone = "industrial"}
        }
        
        for _, pos in ipairs(edge_positions) do
            if love.math.random() < 0.7 then -- 70% chance to place
                WFC.collapse(wfc, pos.x, pos.y, pos.zone)
            end
        end
    end
    
    -- Run the WFC solver
    local success = WFC.solve(wfc)
    
    if not success then
        print("ERROR: WFC zone generation failed!")
        WFC.debugPrint(wfc)
        return nil
    end
    
    print("NewCityGenService: WFC zone generation successful!")
    local result = WFC.getResult(wfc)
    
    -- Debug: Print the first few rows to verify it worked
    print("NewCityGenService: Zone generation result preview:")
    for y = 1, math.min(5, height) do
        local row = ""
        for x = 1, math.min(10, width) do
            local zone = result[y][x]
            local char = zone == "downtown" and "D" or 
                        zone == "commercial" and "C" or
                        zone == "residential" and "R" or
                        zone == "industrial" and "I" or
                        zone == "park" and "P" or "?"
            row = row .. char .. " "
        end
        print("  " .. row)
    end
    
    return result
end

-- Simple zone generation (fallback)
function NewCityGenService._generateZonesSimple(width, height, params)
    print("NewCityGenService: Using simple zone generation")
    
    local zone_grid = {}
    for y = 1, height do
        zone_grid[y] = {}
        for x = 1, width do
            local center_x, center_y = width / 2, height / 2
            local distance = math.sqrt((x - center_x)^2 + (y - center_y)^2)
            
            if distance < 8 then
                zone_grid[y][x] = "downtown"
            elseif distance < 15 then
                zone_grid[y][x] = "commercial" 
            elseif distance < 25 then
                zone_grid[y][x] = love.math.random() < 0.7 and "residential" or "park"
            else
                zone_grid[y][x] = love.math.random() < 0.3 and "industrial" or "residential"
            end
        end
    end
    
    return zone_grid
end

-- Generate arterial roads with A* pathfinding (simple implementation)
function NewCityGenService._generateArterialsSimple(city_grid, zone_grid, highway_connections, params)
    print("NewCityGenService: Generating arterial roads with A* pathfinding")
    
    -- Find downtown center
    local downtown_center = NewCityGenService._findZoneCenter(zone_grid, "downtown")
    if not downtown_center then
        print("WARNING: No downtown center found for arterial generation")
        return
    end
    
    -- Create main arterial roads from downtown to edges
    local width, height = #zone_grid[1], #zone_grid
    
    -- Horizontal arterial
    for x = 1, width do
        if NewCityGenService._inBounds(x, downtown_center.y, width, height) then
            city_grid[downtown_center.y][x] = { type = "arterial" }
        end
    end
    
    -- Vertical arterial  
    for y = 1, height do
        if NewCityGenService._inBounds(downtown_center.x, y, width, height) then
            city_grid[y][downtown_center.x] = { type = "arterial" }
        end
    end
    
    -- Connect to highway connections if provided
    for _, connection in ipairs(highway_connections) do
        NewCityGenService._createPath(city_grid, downtown_center, connection, "arterial")
    end
end

-- Generate arterial roads with WFC (placeholder)
function NewCityGenService._generateArterialsWithWFC(city_grid, zone_grid, highway_connections, params)
    print("NewCityGenService: WFC arterial generation not yet implemented, using simple method")
    NewCityGenService._generateArterialsSimple(city_grid, zone_grid, highway_connections, params)
end

-- Generate local details (roads, plots) - simple implementation
function NewCityGenService._generateDetailsSimple(city_grid, zone_grid, params)
    print("NewCityGenService: Generating local details")
    
    local width, height = #zone_grid[1], #zone_grid
    
    for y = 1, height do
        for x = 1, width do
            local zone = zone_grid[y][x]
            
            -- Skip if already has arterial road
            if city_grid[y][x].type == "arterial" then
                goto continue
            end
            
            -- Generate content based on zone type
            if zone == "downtown" then
                -- Dense road network in downtown
                if (x + y) % 3 == 0 then
                    city_grid[y][x] = { type = "road" }
                else
                    city_grid[y][x] = { type = "plot" }
                end
            elseif zone == "commercial" or zone == "residential" then
                -- Regular grid pattern
                if x % 4 == 0 or y % 4 == 0 then
                    city_grid[y][x] = { type = "road" }
                else
                    city_grid[y][x] = { type = "plot" }
                end
            elseif zone == "industrial" then
                -- Sparse road network
                if x % 6 == 0 or y % 6 == 0 then
                    city_grid[y][x] = { type = "road" }
                else
                    city_grid[y][x] = { type = "plot" }
                end
            elseif zone == "park" then
                -- Mostly grass with some paths
                if x % 8 == 0 or y % 8 == 0 then
                    city_grid[y][x] = { type = "road" }
                else
                    city_grid[y][x] = { type = "grass" }
                end
            else
                city_grid[y][x] = { type = "grass" }
            end
            
            ::continue::
        end
    end
end

-- Generate local details with WFC (placeholder)
function NewCityGenService._generateDetailsWithWFC(city_grid, zone_grid, params)
    print("NewCityGenService: WFC detail generation not yet implemented, using simple method")
    NewCityGenService._generateDetailsSimple(city_grid, zone_grid, params)
end

-- Helper function to find the center of a specific zone type
function NewCityGenService._findZoneCenter(zone_grid, zone_type)
    local sum_x, sum_y, count = 0, 0, 0
    local height, width = #zone_grid, #zone_grid[1]
    
    for y = 1, height do
        for x = 1, width do
            if zone_grid[y][x] == zone_type then
                sum_x = sum_x + x
                sum_y = sum_y + y
                count = count + 1
            end
        end
    end
    
    if count == 0 then
        return nil
    end
    
    return {
        x = math.floor(sum_x / count),
        y = math.floor(sum_y / count)
    }
end

-- Helper function to create a simple path between two points
function NewCityGenService._createPath(grid, start, end_point, road_type)
    local current_x, current_y = start.x, start.y
    local target_x, target_y = end_point.x, end_point.y
    local width, height = #grid[1], #grid
    
    -- Simple L-shaped path
    while current_x ~= target_x do
        if NewCityGenService._inBounds(current_x, current_y, width, height) then
            grid[current_y][current_x] = { type = road_type }
        end
        current_x = current_x + (target_x > current_x and 1 or -1)
    end
    
    while current_y ~= target_y do
        if NewCityGenService._inBounds(current_x, current_y, width, height) then
            grid[current_y][current_x] = { type = road_type }
        end
        current_y = current_y + (target_y > current_y and 1 or -1)
    end
end

-- Helper function to check bounds
function NewCityGenService._inBounds(x, y, width, height)
    return x >= 1 and x <= width and y >= 1 and y <= height
end

-- Helper function to count zones for statistics
function NewCityGenService._countZones(zone_grid)
    local counts = {}
    local height, width = #zone_grid, #zone_grid[1]
    
    for y = 1, height do
        for x = 1, width do
            local zone = zone_grid[y][x]
            counts[zone] = (counts[zone] or 0) + 1
        end
    end
    
    return counts
end

return NewCityGenService