-- services/NewCityGenService.lua
-- Updated with recursive block subdivision for street generation

local NewCityGenService = {}

-- Import required modules
local WFCZoningService = require("services.WFCZoningService")
local BlockSubdivisionService = require("services.BlockSubdivisionService")

function NewCityGenService._forceStreetsFromDowntownArterials(city_grid, district)
    print("Forcing streets to grow directly from downtown arterials...")
    local road_type = "downtown_road"
    local dist_x, dist_y = district.x, district.y
    local dist_w, dist_h = district.w, district.h
    
    local arterial_points = {}
    -- First, find all arterial points that are inside the downtown district
    for y = dist_y, dist_y + dist_h - 1 do
        for x = dist_x, dist_x + dist_w - 1 do
            if city_grid[y][x].type == "arterial" then
                table.insert(arterial_points, {x = x, y = y})
            end
        end
    end

    if #arterial_points == 0 then
        print("WARNING: No arterial road points found within downtown to build streets from.")
        return
    end

    -- For every 4th arterial point found, grow a horizontal street
    -- This creates a simple, predictable grid pattern.
    for i = 1, #arterial_points do
        if i % 4 == 0 then
            local p = arterial_points[i]

            -- Grow a street to the left from the arterial point
            for x = p.x - 1, dist_x, -1 do
                if city_grid[p.y][x].type ~= "plot" and city_grid[p.y][x].type ~= "downtown_plot" then break end -- Stop if we hit anything
                city_grid[p.y][x].type = road_type
            end

            -- Grow a street to the right from the arterial point
            for x = p.x + 1, dist_x + dist_w - 1 do
                if city_grid[p.y][x].type ~= "plot" and city_grid[p.y][x].type ~= "downtown_plot" then break end -- Stop if we hit anything
                city_grid[p.y][x].type = road_type
            end
        end
    end
    print("Finished growing streets from downtown arterials.")
end

function NewCityGenService.generateDetailedCity(params)
    print("NewCityGenService: Starting detailed city generation...")

    local C_MAP = require("data.constants").MAP
    local width = params.width or C_MAP.CITY_GRID_WIDTH
    local height = params.height or C_MAP.CITY_GRID_HEIGHT

    local city_grid = NewCityGenService._createEmptyGrid(width, height)

    -- STAGE 1: Zone Generation
    local wfc_params = {
        downtown_width = C_MAP.DOWNTOWN_GRID_WIDTH,
        downtown_height = C_MAP.DOWNTOWN_GRID_HEIGHT
    }
    local zone_grid = NewCityGenService._generateZonesWithWFC(width, height, wfc_params)
    if not zone_grid then return nil end

    -- STAGE 2: Arterial Road Generation
    local arterial_paths = NewCityGenService._generateArterialsSimple(city_grid, zone_grid, {}, params)

    -- STAGE 3: THE FIX - Pre-Subdivide Downtown to guide the main street algorithm
    -- FIX: Ensure downtown dimensions are not larger than the map itself.
    local downtown_w = math.min(width, C_MAP.DOWNTOWN_GRID_WIDTH)
    local downtown_h = math.min(height, C_MAP.DOWNTOWN_GRID_HEIGHT)

    -- FIX: Recalculate district origin to be 1-indexed and centered.
    local district = {
        x = math.floor((width - downtown_w) / 2) + 1,
        y = math.floor((height - downtown_h) / 2) + 1,
        w = downtown_w,
        h = downtown_h
    }


    -- Draw two vertical and two horizontal lines to create "nodes" for the generator to work from.
    local v1_x = district.x + math.floor(district.w * 0.33)
    local v2_x = district.x + math.floor(district.w * 0.66)
    for y = district.y, district.y + district.h - 1 do
        city_grid[y][v1_x].type = "downtown_road"
        city_grid[y][v2_x].type = "downtown_road"
    end

    local h1_y = district.y + math.floor(district.h * 0.33)
    local h2_y = district.y + math.floor(district.h * 0.66)
    for x = district.x, district.x + district.w - 1 do
        city_grid[h1_y][x].type = "downtown_road"
        city_grid[h2_y][x].type = "downtown_road"
    end

    -- STAGE 4: Run the main street algorithm, which will now correctly process the pre-divided downtown
    BlockSubdivisionService.generateStreets(city_grid, zone_grid, arterial_paths, params)

    print("NewCityGenService: City generation complete")
    return {
        city_grid = city_grid,
        zone_grid = zone_grid,
        arterial_paths = arterial_paths,
        street_segments = Game.street_segments,
        stats = { width = width, height = height }
    }
end

function NewCityGenService._forceDowntownGrid(city_grid, district)
    print("Forcefully carving grid into downtown district...")
    
    local road_type = "downtown_road"
    local dist_x, dist_y = district.x, district.y
    local dist_w, dist_h = district.w, district.h
    local road_spacing = 6 -- How many tiles between each new road.

    -- Force vertical streets
    for x = dist_x, dist_x + dist_w - 1 do
        if (x - dist_x) % road_spacing == 0 then
            for y = dist_y, dist_y + dist_h - 1 do
                if city_grid[y] and city_grid[y][x] then
                    city_grid[y][x].type = road_type
                end
            end
        end
    end

    -- Force horizontal streets
    for y = dist_y, dist_y + dist_h - 1 do
        if (y - dist_y) % road_spacing == 0 then
            for x = dist_x, dist_x + dist_w - 1 do
                if city_grid[y] and city_grid[y][x] then
                    city_grid[y][x].type = road_type
                end
            end
        end
    end
    print("Downtown grid carved.")
end


function NewCityGenService._growStreetsFromDowntownArterials(city_grid, arterial_paths, district, num_streets)
    print("Forcing streets to grow from downtown arterials...")
    if not arterial_paths or #arterial_paths == 0 then return end

    local downtown_arterial_points = {}
    for _, path in ipairs(arterial_paths) do
        for _, point in ipairs(path) do
            if point.x >= district.x and point.x < district.x + district.w and
               point.y >= district.y and point.y < district.y + district.h then
                table.insert(downtown_arterial_points, point)
            end
        end
    end

    if #downtown_arterial_points == 0 then
        print("Warning: No arterial road points found within downtown to grow from.")
        return
    end

    local roads_created = 0
    for i = 1, num_streets do
        local start_point = downtown_arterial_points[love.math.random(1, #downtown_arterial_points)]
        
        local prev_point, next_point
        for _, path in ipairs(arterial_paths) do
            for p_idx, point in ipairs(path) do
                -- THE FIX: Compare coordinates, not table references
                if point.x == start_point.x and point.y == start_point.y and p_idx > 1 and p_idx < #path then
                    prev_point = path[p_idx - 1]
                    next_point = path[p_idx + 1]
                    break
                end
            end
            if prev_point then break end
        end

        local is_vertical = false
        if prev_point and next_point and math.abs(next_point.x - prev_point.x) < math.abs(next_point.y - prev_point.y) then
            is_vertical = true
        end

        local dx, dy = 0, 0
        if is_vertical then
            dx = love.math.random(0,1) == 0 and -1 or 1
        else
            dy = love.math.random(0,1) == 0 and -1 or 1
        end

        local cx, cy = start_point.x + dx, start_point.y + dy
        while (cx >= district.x and cx < district.x + district.w and cy >= district.y and cy < district.y + district.h) do
            if city_grid[cy][cx].type ~= "plot" and city_grid[cy][cx].type ~= "downtown_plot" then break end
            city_grid[cy][cx].type = "downtown_road"
            cx, cy = cx + dx, cy + dy
        end
        roads_created = roads_created + 1
    end
    print("Created " .. roads_created .. " streets branching from downtown arterials.")
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
    
    -- Clear existing roads (but not arterials)
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