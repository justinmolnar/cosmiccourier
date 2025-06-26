-- services/NewCityGenService.lua
-- Updated with recursive block subdivision for street generation

local NewCityGenService = {}

-- Import required modules
local WFCZoningService = require("services.WFCZoningService")
local BlockSubdivisionService = require("services.BlockSubdivisionService")

function NewCityGenService.generateDetailedCity(params)
    print("NewCityGenService: Starting detailed city generation with recursive subdivision")
    
    -- Extract parameters with defaults
    local width = params.width or 64
    local height = params.height or 48
    local terrain_data = params.terrain_data or {}
    local highway_connections = params.highway_connections or {}
    local use_wfc_for_zones = params.use_wfc_for_zones or true
    local use_recursive_streets = params.use_recursive_streets ~= false -- Default to true
    
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
    local arterial_paths = {}
    if params.generate_arterials ~= false then
        arterial_paths = NewCityGenService._generateArterialsSimple(city_grid, zone_grid, highway_connections, params)
    end
    
    -- STAGE 3: Street Generation using Recursive Subdivision
    print("NewCityGenService: Stage 3 - Street Generation with Recursive Subdivision")
    if use_recursive_streets then
        local street_params = {
            min_block_size = params.min_block_size or 3,
            max_block_size = params.max_block_size or 8,
            street_width = params.street_width or 1
        }
        BlockSubdivisionService.generateStreets(city_grid, zone_grid, arterial_paths, street_params)
    else
        NewCityGenService._generateDetailsSimple(city_grid, zone_grid, params)
    end
    
    -- STAGE 4: Fill remaining areas with plots
    print("NewCityGenService: Stage 4 - Filling plots")
    NewCityGenService._fillRemainingWithPlots(city_grid, zone_grid, width, height)
    
    print("NewCityGenService: City generation complete")
    return {
        city_grid = city_grid,
        zone_grid = zone_grid,
        arterial_paths = arterial_paths,
        stats = {
            width = width,
            height = height,
            zones_generated = NewCityGenService._countZones(zone_grid),
            generation_method = "Recursive Subdivision"
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

-- Generate zones using our custom WFCZoningService
function NewCityGenService._generateZonesWithWFC(width, height, params)
    print("NewCityGenService: Using custom WFCZoningService for zone generation")
    
    -- Calculate downtown center
    local center_x = math.floor(width / 2)
    local center_y = math.floor(height / 2)
    
    print(string.format("NewCityGenService: Placing downtown at (%d, %d)", center_x, center_y))
    
    -- Use our custom WFC zoning service that creates proper districts
    local zone_grid = WFCZoningService.generateCoherentZones(width, height, center_x, center_y)
    
    if not zone_grid then
        print("ERROR: WFCZoningService failed to generate zones!")
        return nil
    end
    
    print("NewCityGenService: Custom WFC zone generation successful!")
    
    -- Debug: Print zone statistics
    local stats, total = WFCZoningService.getZoneStats(zone_grid)
    print("NewCityGenService: Zone distribution:")
    for zone_name, zone_stats in pairs(stats) do
        print(string.format("  %s: %d cells (%d%%)", zone_name, zone_stats.count, zone_stats.percentage))
    end
    
    return zone_grid
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
                zone_grid[y][x] = love.math.random() < 0.7 and "residential_north" or "park_central"
            else
                zone_grid[y][x] = love.math.random() < 0.3 and "industrial_heavy" or "residential_south"
            end
        end
    end
    
    return zone_grid
end

-- Generate arterial roads with A* pathfinding
function NewCityGenService._generateArterialsSimple(city_grid, zone_grid, highway_connections, params)
    print("NewCityGenService: Generating arterial roads")
    
    local arterial_paths = {}
    
    -- Import the arterial road service
    local ArterialRoadService = require("services.ArterialRoadService")
    
    -- Set up arterial generation parameters
    local arterial_params = {
        num_arterials = params.num_arterials or 3,
        min_edge_distance = params.min_edge_distance or 15
    }
    
    -- Generate arterials and get the paths back
    arterial_paths = ArterialRoadService.generateArterialRoads(city_grid, zone_grid, arterial_params)
    
    print("NewCityGenService: Arterial generation complete, generated " .. #arterial_paths .. " paths")
    return arterial_paths
end

-- Fill remaining areas with building plots
function NewCityGenService._fillRemainingWithPlots(city_grid, zone_grid, width, height)
    for y = 1, height do
        for x = 1, width do
            if city_grid[y][x].type == "grass" then
                -- Check the zone to determine what to place
                local zone = zone_grid and zone_grid[y] and zone_grid[y][x]
                if zone and string.find(zone, "park") then
                    -- Keep parks as grass
                    city_grid[y][x] = { type = "grass" }
                else
                    -- Everything else becomes plots
                    city_grid[y][x] = { type = "plot" }
                end
            end
        end
    end
end

-- Generate local details (roads, plots) - simple implementation (DEPRECATED - use BlockSubdivisionService instead)
function NewCityGenService._generateDetailsSimple(city_grid, zone_grid, params)
    print("NewCityGenService: Using deprecated simple detail generation")
    
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
            elseif string.find(zone, "commercial") or string.find(zone, "residential") then
                -- Regular grid pattern
                if x % 4 == 0 or y % 4 == 0 then
                    city_grid[y][x] = { type = "road" }
                else
                    city_grid[y][x] = { type = "plot" }
                end
            elseif string.find(zone, "industrial") then
                -- Sparse road network
                if x % 6 == 0 or y % 6 == 0 then
                    city_grid[y][x] = { type = "road" }
                else
                    city_grid[y][x] = { type = "plot" }
                end
            elseif string.find(zone, "park") then
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

-- Simplified arterials-only generation for testing
function NewCityGenService.generateArterialsOnly(city_grid, zone_grid, params)
    print("NewCityGenService: Generating arterials only")
    
    if not city_grid or not zone_grid then
        print("ERROR: Missing grids for arterial generation")
        return false, nil
    end
    
    -- Clear any existing arterial roads
    print("NewCityGenService: Clearing existing arterial roads")
    local width, height = #city_grid[1], #city_grid
    for y = 1, height do
        for x = 1, width do
            if city_grid[y][x].type == "arterial" then
                city_grid[y][x].type = "grass"
            end
        end
    end
    
    -- Import the arterial road service
    local ArterialRoadService = require("services.ArterialRoadService")
    
    -- Set up arterial generation parameters
    local arterial_params = {
        num_arterials = params.num_arterials or 3,
        min_edge_distance = params.min_edge_distance or 15
    }
    
    -- Generate arterials using pathfinding and get the paths back
    local generated_paths = ArterialRoadService.generateArterialRoads(city_grid, zone_grid, arterial_params)
    
    print("NewCityGenService: Arterials-only generation complete")
    return true, generated_paths
end

-- New function to generate streets only (after arterials are placed)
function NewCityGenService.generateStreetsOnly(city_grid, zone_grid, arterial_paths, params)
    print("NewCityGenService: Generating streets only using recursive subdivision")
    
    if not city_grid or not zone_grid then
        print("ERROR: Missing grids for street generation")
        return false
    end
    
    -- Clear existing roads (but not arterials)
    local width, height = #city_grid[1], #city_grid
    for y = 1, height do
        for x = 1, width do
            if city_grid[y][x].type == "road" then
                city_grid[y][x].type = "grass"
            end
        end
    end
    
    -- Set up street generation parameters
    local street_params = {
        min_block_size = params.min_block_size or 3,
        max_block_size = params.max_block_size or 8,
        street_width = params.street_width or 1
    }
    
    -- Generate streets using recursive subdivision
    local success = BlockSubdivisionService.generateStreets(city_grid, zone_grid, arterial_paths, street_params)
    
    -- Fill remaining areas with plots
    NewCityGenService._fillRemainingWithPlots(city_grid, zone_grid, width, height)
    
    print("NewCityGenService: Streets-only generation complete")
    return success
end

return NewCityGenService