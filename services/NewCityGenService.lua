-- services/NewCityGenService.lua
-- Complete file with downtown street generation fixes

local NewCityGenService = {}

-- Import required modules
local WFCZoningService = require("services.WFCZoningService")
local BlockSubdivisionService = require("services.BlockSubdivisionService")

function NewCityGenService.generateDetailedCity(params)
    print("NewCityGenService: Starting detailed city generation...")

    local C_MAP = require("data.constants").MAP
    local width = params.width or C_MAP.CITY_GRID_WIDTH
    local height = params.height or C_MAP.CITY_GRID_HEIGHT

    local city_grid = NewCityGenService._createEmptyGrid(width, height)
    
    -- DEBUG: Check initial state
    print("=== DEBUG: After creating empty grid ===")
    NewCityGenService._debugDowntownArea(city_grid, width, height, "INITIAL")

    -- STAGE 1: Zone Generation
    local wfc_params = {
        downtown_width = C_MAP.DOWNTOWN_GRID_WIDTH,
        downtown_height = C_MAP.DOWNTOWN_GRID_HEIGHT
    }
    local zone_grid = NewCityGenService._generateZonesWithWFC(width, height, wfc_params)
    if not zone_grid then return nil end
    
    -- DEBUG: Check after zone generation
    print("=== DEBUG: After zone generation ===")
    NewCityGenService._debugDowntownArea(city_grid, width, height, "AFTER_ZONES")

    -- STAGE 2: Arterial Road Generation
    local arterial_paths = NewCityGenService._generateArterialsSimple(city_grid, zone_grid, {}, params)
    
    -- DEBUG: Check after arterial generation
    print("=== DEBUG: After arterial generation ===")
    NewCityGenService._debugDowntownArea(city_grid, width, height, "AFTER_ARTERIALS")

    -- STAGE 3: Street Generation (now handles downtown properly)
    BlockSubdivisionService.generateStreets(city_grid, zone_grid, arterial_paths, params)
    
    -- DEBUG: Check after street generation
    print("=== DEBUG: After street generation ===")
    NewCityGenService._debugDowntownArea(city_grid, width, height, "AFTER_STREETS")

    -- STAGE 4: Fill remaining areas with plots
    NewCityGenService._fillRemainingWithPlots(city_grid, zone_grid, width, height)
    
    -- DEBUG: Check after plot filling
    print("=== DEBUG: After plot filling ===")
    NewCityGenService._debugDowntownArea(city_grid, width, height, "AFTER_PLOTS")

    print("NewCityGenService: City generation complete")
    return {
        city_grid = city_grid,
        zone_grid = zone_grid,
        arterial_paths = arterial_paths,
        street_segments = Game.street_segments,
        stats = { width = width, height = height }
    }
end

function NewCityGenService._debugDowntownArea(city_grid, width, height, stage)
    local C_MAP = require("data.constants").MAP
    local downtown_w = math.min(width, C_MAP.DOWNTOWN_GRID_WIDTH)
    local downtown_h = math.min(height, C_MAP.DOWNTOWN_GRID_HEIGHT)
    local downtown_bounds = {
        x1 = math.floor((width - downtown_w) / 2) + 1,
        y1 = math.floor((height - downtown_h) / 2) + 1,
        x2 = math.floor((width - downtown_w) / 2) + downtown_w,
        y2 = math.floor((height - downtown_h) / 2) + downtown_h
    }
    
    local tile_counts = {}
    local sample_tiles = {}
    
    for y = downtown_bounds.y1, downtown_bounds.y2 do
        for x = downtown_bounds.x1, downtown_bounds.x2 do
            local tile_type = city_grid[y][x].type
            tile_counts[tile_type] = (tile_counts[tile_type] or 0) + 1
            
            -- Sample a few tiles for detailed inspection
            if #sample_tiles < 5 then
                table.insert(sample_tiles, {x = x, y = y, type = tile_type})
            end
        end
    end
    
    print(string.format("DOWNTOWN DEBUG [%s]:", stage))
    print(string.format("  Bounds: (%d,%d) to (%d,%d)", downtown_bounds.x1, downtown_bounds.y1, downtown_bounds.x2, downtown_bounds.y2))
    print("  Tile type counts:")
    for tile_type, count in pairs(tile_counts) do
        print(string.format("    %s: %d tiles", tile_type, count))
    end
    print("  Sample tiles:")
    for _, sample in ipairs(sample_tiles) do
        print(string.format("    (%d,%d): %s", sample.x, sample.y, sample.type))
    end
    print("")
end

function NewCityGenService.generateMinimalTest(params)
    print("=== MINIMAL TEST: Only Zones + Arterials ===")
    
    local C_MAP = require("data.constants").MAP
    local width = params.width or C_MAP.CITY_GRID_WIDTH
    local height = params.height or C_MAP.CITY_GRID_HEIGHT

    local city_grid = NewCityGenService._createEmptyGrid(width, height)
    print("1. Created empty grid (all grass)")
    
    local zone_grid = NewCityGenService._generateZonesWithWFC(width, height, {
        downtown_width = C_MAP.DOWNTOWN_GRID_WIDTH,
        downtown_height = C_MAP.DOWNTOWN_GRID_HEIGHT
    })
    print("2. Generated zone grid")
    
    local arterial_paths = NewCityGenService._generateArterialsSimple(city_grid, zone_grid, {}, params)
    print("3. Generated arterials")
    
    -- DEBUG: Check what's in downtown now (before any street generation)
    NewCityGenService._debugDowntownArea(city_grid, width, height, "MINIMAL_TEST_RESULT")
    
    -- DON'T run street generation or plot filling - just return what we have
    return {
        city_grid = city_grid,
        zone_grid = zone_grid,
        arterial_paths = arterial_paths,
        stats = { width = width, height = height }
    }
end

function NewCityGenService._fillRemainingWithPlots(city_grid, zone_grid, width, height)
    local C_MAP = require("data.constants").MAP
    local downtown_w = math.min(width, C_MAP.DOWNTOWN_GRID_WIDTH)
    local downtown_h = math.min(height, C_MAP.DOWNTOWN_GRID_HEIGHT)
    local downtown_bounds = {
        x1 = math.floor((width - downtown_w) / 2) + 1,
        y1 = math.floor((height - downtown_h) / 2) + 1,
        x2 = math.floor((width - downtown_w) / 2) + downtown_w,
        y2 = math.floor((height - downtown_h) / 2) + downtown_h
    }
    
    for y = 1, height do
        for x = 1, width do
            local current_type = city_grid[y][x].type
            
            -- CRITICAL FIX: Only fill grass cells (preserve ALL road types)
            if current_type == "grass" then
                local zone = zone_grid and zone_grid[y] and zone_grid[y][x]
                local is_downtown = (x >= downtown_bounds.x1 and x <= downtown_bounds.x2 and 
                                   y >= downtown_bounds.y1 and y <= downtown_bounds.y2)
                
                -- Use geometric bounds to determine downtown, NOT zone grid
                -- This prevents the zone grid's "downtown" zones from overwriting roads
                if zone and string.find(zone, "park") then
                    city_grid[y][x] = { type = "grass" }
                elseif is_downtown then
                    city_grid[y][x] = { type = "downtown_plot" }
                else
                    city_grid[y][x] = { type = "plot" }
                end
            end
            -- All road types (arterial, road, downtown_road) are preserved regardless of zone
        end
    end
    
    print("Plot filling complete - all road types preserved")
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
        num_arterials = params.num_arterials, -- Let the service calculate if nil
        min_edge_distance = params.min_edge_distance or 15
    }
    
    -- Generate arterials and get the paths back
    arterial_paths = ArterialRoadService.generateArterialRoads(city_grid, zone_grid, arterial_params)
    
    print("NewCityGenService: Arterial generation complete, generated " .. #arterial_paths .. " paths")
    return arterial_paths
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
        num_arterials = params.num_arterials, -- Let service calculate if nil
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
    
    -- Clear existing roads (but not arterials or downtown roads)
    local width, height = #city_grid[1], #city_grid
    for y = 1, height do
        for x = 1, width do
            if city_grid[y][x].type == "road" then
                city_grid[y][x].type = "grass"
            end
        end
    end
    
    -- DYNAMIC BLOCK SIZES
    local map_diagonal = math.sqrt(width^2 + height^2)
    local dynamic_max_size = math.max(8, math.floor(map_diagonal / 20))
    local dynamic_min_size = math.max(4, math.floor(dynamic_max_size / 2))

    -- Set up street generation parameters
    local street_params = {
        min_block_size = params.min_block_size or dynamic_min_size,
        max_block_size = params.max_block_size or dynamic_max_size,
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