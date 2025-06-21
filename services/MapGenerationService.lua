-- services/MapGenerationService.lua
local MapGenerationService = {}

-- Import all the generator modules
local Downtown = require("models.generators.downtown")
local Districts = require("models.generators.districts")
local HighwayNS = require("models.generators.highway_ns")
local HighwayEW = require("models.generators.highway_ew")
local RingRoad = require("models.generators.ringroad")
local HighwayMerger = require("models.generators.highway_merger")
local ConnectingRoads = require("models.generators.connecting_roads")

-- NEW: Add a deep copy function to fix the table reference bug
function MapGenerationService._deepCopyParams(params)
    if not params then return {} end
    
    local copy = {}
    for key, value in pairs(params) do
        if type(value) == "table" then
            copy[key] = MapGenerationService._deepCopyParams(value) -- Recursive for nested tables
        else
            copy[key] = value
        end
    end
    return copy
end

function MapGenerationService.generateMap(map)
    print("MapGenerationService: Beginning unified map generation process...")
    local C_MAP = map.C.MAP
    local params = map.debug_params or {}

    -- Create the grid for the main city
    local city_w = tonumber(C_MAP.CITY_GRID_WIDTH)
    local city_h = tonumber(C_MAP.CITY_GRID_HEIGHT)
    map.grid = MapGenerationService._createGrid(city_w, city_h, "grass")

    -- Generate the initial city in the center of this grid
    MapGenerationService.generateCityAt(map.grid, math.floor(city_w / 2), math.floor(city_h / 2), C_MAP, params, map)

    -- Extract building plots from the newly generated city grid
    map.building_plots = map:getPlotsFromGrid(map.grid)

    -- Clear any cached data from older map versions
    map.scale_grids = nil
    map.scale_building_plots = nil

    print("MapGenerationService: Generation complete. Found " .. #map.building_plots .. " valid building plots.")
end

function MapGenerationService.generateCityAt(target_grid, center_x, center_y, city_config, params)
    print(string.format("--- BEGIN CITY GENERATION AT (%d, %d) ---", center_x, center_y))

    local city_w = city_config.CITY_GRID_WIDTH
    local city_h = city_config.CITY_GRID_HEIGHT

    local temp_grid = MapGenerationService._createGrid(city_w, city_h, "grass")

    local temp_downtown_district = {
        x = math.floor(city_w / 2) - math.floor(city_config.DOWNTOWN_GRID_WIDTH / 2),
        y = math.floor(city_h / 2) - math.floor(city_config.DOWNTOWN_GRID_HEIGHT / 2),
        w = city_config.DOWNTOWN_GRID_WIDTH,
        h = city_config.DOWNTOWN_GRID_HEIGHT
    }
    
    -- FIX: Create a fresh copy of params for each city generation to prevent 
    -- the shared reference bug that was causing the second city to be empty
    local city_params = MapGenerationService._deepCopyParams(params)
    
    Downtown.generateDowntownModule(temp_grid, temp_downtown_district, "downtown_road", "downtown_plot", city_params)
    
    local all_districts = Districts.generateAll(temp_grid, city_w, city_h, temp_downtown_district, city_params)

    local highway_paths = MapGenerationService._generateHighways(all_districts, city_w, city_h, temp_downtown_district, city_params)
    
    local highway_points = MapGenerationService._extractHighwayPoints(highway_paths.ring_road, highway_paths.highways)
    local connections = ConnectingRoads.generateConnections(temp_grid, all_districts, highway_points, city_w, city_h, temp_downtown_district, city_params)

    MapGenerationService._drawAllRoadsToGrid(temp_grid, highway_paths.ring_road, highway_paths.highways, connections, city_params, city_config)
    ConnectingRoads.drawConnections(temp_grid, connections, city_params)

    -- DEBUG: Count non-grass tiles in temp grid BEFORE stamping
    local non_grass_count = 0
    local tile_types = {}
    for y = 1, city_h do
        for x = 1, city_w do
            local tile_type = temp_grid[y][x].type
            if tile_type ~= "grass" then
                non_grass_count = non_grass_count + 1
                tile_types[tile_type] = (tile_types[tile_type] or 0) + 1
            end
        end
    end
    print(string.format("DEBUG: Temp grid has %d non-grass tiles before stamping:", non_grass_count))
    for tile_type, count in pairs(tile_types) do
        print(string.format("  %s: %d", tile_type, count))
    end

    local target_start_x = center_x - math.floor(city_w / 2)
    local target_start_y = center_y - math.floor(city_h / 2)
    
    print(string.format("DEBUG: Stamping city from temp grid to target grid"))
    print(string.format("  Target region bounds: (%d,%d) to (%d,%d)", 
          target_start_x, target_start_y, target_start_x + city_w, target_start_y + city_h))
    print(string.format("  Target grid size: %dx%d", #target_grid[1], #target_grid))

    -- DEBUG: Check if target coordinates are in bounds
    local region_w = #target_grid[1]
    local region_h = #target_grid
    local out_of_bounds = false
    
    if target_start_x < 1 or target_start_y < 1 or 
       target_start_x + city_w > region_w or target_start_y + city_h > region_h then
        out_of_bounds = true
        print(string.format("ERROR: City bounds extend outside region! Region is %dx%d", region_w, region_h))
    end

    local stamped_count = 0
    local stamped_types = {}
    
    for y = 1, city_h do
        for x = 1, city_w do
            local source_tile = temp_grid[y][x]
            if source_tile.type ~= "grass" then
                local target_x = target_start_x + x - 1  -- FIX: Off-by-one error?
                local target_y = target_start_y + y - 1  -- FIX: Off-by-one error?
                
                if target_y >= 1 and target_y <= region_h and 
                   target_x >= 1 and target_x <= region_w then
                    target_grid[target_y][target_x] = source_tile
                    stamped_count = stamped_count + 1
                    stamped_types[source_tile.type] = (stamped_types[source_tile.type] or 0) + 1
                else
                    -- DEBUG: Track out of bounds attempts
                    if not out_of_bounds then
                        print(string.format("WARNING: Trying to stamp at (%d,%d) which is out of bounds", target_x, target_y))
                        out_of_bounds = true
                    end
                end
            end
        end
    end
    
    print(string.format("DEBUG: Successfully stamped %d tiles:", stamped_count))
    for tile_type, count in pairs(stamped_types) do
        print(string.format("  %s: %d", tile_type, count))
    end
    
    -- DEBUG: Verify the tiles actually got stamped by sampling the target grid
    local verification_count = 0
    local verify_start_x = math.max(1, target_start_x)
    local verify_start_y = math.max(1, target_start_y)
    local verify_end_x = math.min(region_w, target_start_x + city_w - 1)
    local verify_end_y = math.min(region_h, target_start_y + city_h - 1)
    
    for y = verify_start_y, verify_end_y do
        for x = verify_start_x, verify_end_x do
            if target_grid[y] and target_grid[y][x] and target_grid[y][x].type ~= "grass" then
                verification_count = verification_count + 1
            end
        end
    end
    
    print(string.format("DEBUG: Verification found %d non-grass tiles in target region", verification_count))
    
    print(string.format("--- END CITY GENERATION AT (%d, %d). Stamped %d/%d tiles. ---", 
          center_x, center_y, stamped_count, non_grass_count))
end

function MapGenerationService.generateRegion(region_map)
    local C_MAP = region_map.C.MAP
    local REGION_W = C_MAP.REGION_GRID_WIDTH
    local REGION_H = C_MAP.REGION_GRID_HEIGHT
    local CITY_W = C_MAP.CITY_GRID_WIDTH
    local CITY_H = C_MAP.CITY_GRID_HEIGHT
    local params = region_map.debug_params or {}

    region_map.grid = MapGenerationService._createGrid(REGION_W, REGION_H, "grass")

    MapGenerationService._generateRivers(region_map.grid)
    MapGenerationService._generateMountains(region_map.grid)

    -- MAIN CITY: Center of the region
    local main_city_center_x = REGION_W / 2
    local main_city_center_y = REGION_H / 2
    
    print(string.format("MAIN CITY will occupy bounds: (%d,%d) to (%d,%d)", 
          main_city_center_x - CITY_W/2, main_city_center_y - CITY_H/2,
          main_city_center_x + CITY_W/2, main_city_center_y + CITY_H/2))
    
    MapGenerationService.generateCityAt(region_map.grid, main_city_center_x, main_city_center_y, C_MAP, 
                                       MapGenerationService._deepCopyParams(params))

    -- SECOND CITY: Position it safely within bounds and away from main city
    -- Calculate safe position that ensures both cities fit completely within region
    local safe_margin = 20
    local min_distance = 250 -- Minimum distance between city centers
    
    -- Try bottom-left position first
    local second_city_x = CITY_W/2 + safe_margin
    local second_city_y = REGION_H - CITY_H/2 - safe_margin
    
    -- Check if this is far enough from main city
    local distance = math.sqrt((second_city_x - main_city_center_x)^2 + (second_city_y - main_city_center_y)^2)
    if distance < min_distance then
        -- Try top-left position instead
        second_city_y = CITY_H/2 + safe_margin
        distance = math.sqrt((second_city_x - main_city_center_x)^2 + (second_city_y - main_city_center_y)^2)
        
        if distance < min_distance then
            -- Try far left position
            second_city_x = CITY_W/2 + safe_margin
            second_city_y = REGION_H * 0.25 -- Quarter way down
        end
    end
    
    -- Final bounds check
    local second_bounds_x1 = second_city_x - CITY_W/2
    local second_bounds_y1 = second_city_y - CITY_H/2
    local second_bounds_x2 = second_city_x + CITY_W/2
    local second_bounds_y2 = second_city_y + CITY_H/2
    
    if second_bounds_x1 < 1 or second_bounds_y1 < 1 or 
       second_bounds_x2 > REGION_W or second_bounds_y2 > REGION_H then
        print("ERROR: Cannot fit second city within region bounds!")
        print(string.format("  Region size: %dx%d", REGION_W, REGION_H))
        print(string.format("  Second city bounds: (%d,%d) to (%d,%d)", 
              second_bounds_x1, second_bounds_y1, second_bounds_x2, second_bounds_y2))
        -- Skip second city generation
    else
        print(string.format("SECOND CITY will occupy bounds: (%d,%d) to (%d,%d)", 
              second_bounds_x1, second_bounds_y1, second_bounds_x2, second_bounds_y2))
        
        MapGenerationService.generateCityAt(region_map.grid, second_city_x, second_city_y, C_MAP, 
                                           MapGenerationService._deepCopyParams(params))
    end

    -- Continue with the rest of the function...
    local city_map = Game.maps.city
    city_map.grid = MapGenerationService._createGrid(CITY_W, CITY_H, "grass")

    local source_start_x = main_city_center_x - math.floor(CITY_W / 2)
    local source_start_y = main_city_center_y - math.floor(CITY_H / 2)
    for y = 1, CITY_H do
        for x = 1, CITY_W do
            local sx, sy = source_start_x + x, source_start_y + y
            if region_map.grid[sy] and region_map.grid[sy][sx] then
                city_map.grid[y][x] = region_map.grid[sy][sx]
            end
        end
    end
    
    region_map.building_plots = region_map:getPlotsFromGrid(region_map.grid)
    city_map.building_plots = city_map:getPlotsFromGrid(city_map.grid)
    
    city_map.downtown_offset = {
        x = math.floor(CITY_W / 2) - math.floor(C_MAP.DOWNTOWN_GRID_WIDTH / 2),
        y = math.floor(CITY_H / 2) - math.floor(C_MAP.DOWNTOWN_GRID_HEIGHT / 2)
    }

    region_map.downtown_offset = {
        x = main_city_center_x - math.floor(C_MAP.DOWNTOWN_GRID_WIDTH / 2),
        y = main_city_center_y - math.floor(C_MAP.DOWNTOWN_GRID_HEIGHT / 2)
    }
    
    Game.entities.depot_plot = city_map:getRandomDowntownBuildingPlot()
    print("Region generation complete!")
end

function MapGenerationService.generateCityAt(target_grid, center_x, center_y, city_config, params)
    print(string.format("--- BEGIN CITY GENERATION AT (%d, %d) ---", center_x, center_y))

    local city_w = city_config.CITY_GRID_WIDTH
    local city_h = city_config.CITY_GRID_HEIGHT

    local temp_grid = MapGenerationService._createGrid(city_w, city_h, "grass")

    local temp_downtown_district = {
        x = math.floor(city_w / 2) - math.floor(city_config.DOWNTOWN_GRID_WIDTH / 2),
        y = math.floor(city_h / 2) - math.floor(city_config.DOWNTOWN_GRID_HEIGHT / 2),
        w = city_config.DOWNTOWN_GRID_WIDTH,
        h = city_config.DOWNTOWN_GRID_HEIGHT
    }
    
    local city_params = MapGenerationService._deepCopyParams(params)
    
    Downtown.generateDowntownModule(temp_grid, temp_downtown_district, "downtown_road", "downtown_plot", city_params)
    
    local all_districts = Districts.generateAll(temp_grid, city_w, city_h, temp_downtown_district, city_params)

    local highway_paths = MapGenerationService._generateHighways(all_districts, city_w, city_h, temp_downtown_district, city_params)
    
    local highway_points = MapGenerationService._extractHighwayPoints(highway_paths.ring_road, highway_paths.highways)
    local connections = ConnectingRoads.generateConnections(temp_grid, all_districts, highway_points, city_w, city_h, temp_downtown_district, city_params)

    MapGenerationService._drawAllRoadsToGrid(temp_grid, highway_paths.ring_road, highway_paths.highways, connections, city_params, city_config)
    ConnectingRoads.drawConnections(temp_grid, connections, city_params)

    -- Count non-grass tiles in temp grid BEFORE stamping
    local non_grass_count = 0
    for y = 1, city_h do
        for x = 1, city_w do
            if temp_grid[y][x].type ~= "grass" then
                non_grass_count = non_grass_count + 1
            end
        end
    end
    print(string.format("DEBUG: Temp grid has %d non-grass tiles before stamping", non_grass_count))

    local target_start_x = center_x - math.floor(city_w / 2)
    local target_start_y = center_y - math.floor(city_h / 2)
    
    print(string.format("DEBUG: Stamping to region bounds: (%d,%d) to (%d,%d)", 
          target_start_x, target_start_y, target_start_x + city_w, target_start_y + city_h))

    -- SAFE stamping with bounds checking
    local region_w = #target_grid[1]
    local region_h = #target_grid
    local stamped_count = 0
    
    for y = 1, city_h do
        for x = 1, city_w do
            local source_tile = temp_grid[y][x]
            if source_tile.type ~= "grass" then
                local target_x = target_start_x + x - 1
                local target_y = target_start_y + y - 1
                
                -- CRITICAL: Proper bounds checking
                if target_y >= 1 and target_y <= region_h and 
                   target_x >= 1 and target_x <= region_w and
                   target_grid[target_y] and target_grid[target_y][target_x] then
                    target_grid[target_y][target_x] = source_tile
                    stamped_count = stamped_count + 1
                end
            end
        end
    end
    
    print(string.format("DEBUG: Successfully stamped %d/%d tiles", stamped_count, non_grass_count))
    print(string.format("--- END CITY GENERATION AT (%d, %d) ---", center_x, center_y))
end

-- HELPER AND UTILITY FUNCTIONS (moved from Map.lua)
function MapGenerationService._createGrid(width, height, default_type)
    local grid = {}
    for y = 1, height do
        grid[y] = {}
        for x = 1, width do
            grid[y][x] = { type = default_type or "grass" }
        end
    end
    return grid
end

function MapGenerationService._extractHighwayPoints(ring_road_curve, highway_paths)
    local points = {}
    for _, point in ipairs(ring_road_curve) do
        table.insert(points, point)
    end
    for _, highway_path in ipairs(highway_paths or {}) do
        local highway_curve = MapGenerationService._generateSplinePoints(highway_path, 10)
        for _, point in ipairs(highway_curve) do
            table.insert(points, point)
        end
    end
    return points
end

function MapGenerationService._drawAllRoadsToGrid(grid, ring_road_curve, merged_highway_paths, connections, params, city_config)
    local thickness = 3
    
    if #ring_road_curve > 1 then
        for i = 1, #ring_road_curve - 1 do
            MapGenerationService._drawThickLineColored(grid, ring_road_curve[i].x, ring_road_curve[i].y, ring_road_curve[i+1].x, ring_road_curve[i+1].y, "highway_ring", thickness)
        end
    end
    
    local num_ns_highways = (params and params.num_ns_highways) or (city_config and city_config.NUM_NS_HIGHWAYS) or 2
    for highway_idx, path_nodes in ipairs(merged_highway_paths) do
        local highway_curve = MapGenerationService._generateSplinePoints(path_nodes, 10)
        local highway_type = highway_idx <= num_ns_highways and "highway_ns" or "highway_ew"
        
        for i = 1, #highway_curve - 1 do
            MapGenerationService._drawThickLineColored(grid, highway_curve[i].x, highway_curve[i].y, highway_curve[i+1].x, highway_curve[i+1].y, highway_type, thickness)
        end
    end
end

function MapGenerationService._generateSplinePoints(points, num_segments)
    local curve_points = {}
    if #points < 4 then return points end
    
    for i = 2, #points - 2 do
        local p0, p1, p2, p3 = points[i-1], points[i], points[i+1], points[i+2]
        for t = 0, 1, 1/num_segments do
            local x = 0.5 * ((2 * p1.x) + (-p0.x + p2.x) * t + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t * t + (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t * t * t)
            local y = 0.5 * ((2 * p1.y) + (-p0.y + p2.y) * t + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t * t + (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t * t * t)
            table.insert(curve_points, {x = math.floor(x), y = math.floor(y)})
        end
    end
    
    return curve_points
end

function MapGenerationService._drawThickLineColored(grid, x1, y1, x2, y2, road_type, thickness)
    if not grid or #grid == 0 then return end
    local w, h = #grid[1], #grid
    local half_thick = math.floor(thickness / 2)

    local dx = x2 - x1
    local dy = y2 - y1

    local function inBounds(x, y)
        return x >= 1 and x <= w and y >= 1 and y <= h
    end

    if math.abs(dx) > math.abs(dy) then
        local x_min, x_max = math.min(x1, x2), math.max(x1, x2)
        for x = x_min, x_max do
            local y = dx == 0 and y1 or math.floor(y1 + dy * (x - x1) / dx + 0.5)
            for i = -half_thick, half_thick do
                for j = -half_thick, half_thick do
                    if inBounds(x + i, y + j) then
                        grid[y + j][x + i].type = road_type
                    end
                end
            end
        end
    else
        local y_min, y_max = math.min(y1, y2), math.max(y1, y2)
        for y = y_min, y_max do
            local x = dy == 0 and x1 or math.floor(x1 + dx * (y - y1) / dy + 0.5)
            for i = -half_thick, half_thick do
                for j = -half_thick, half_thick do
                    if inBounds(x + i, y + j) then
                        grid[y + j][x + i].type = road_type
                    end
                end
            end
        end
    end
end

function MapGenerationService._generateRivers(grid)
    local w, h = #grid[1], #grid
    -- Start a river near the top, somewhere in the middle 60% of the map
    local river_x = w * (0.2 + love.math.random() * 0.6)
    local river_y = 1

    -- A simple random walk downwards for a river
    while river_y <= h do
        river_x = river_x + love.math.random(-1, 1)
        river_x = math.max(3, math.min(w - 2, river_x)) -- Clamp to map bounds, with a small margin
        
        -- Draw a thick line for the river tile
        for i = -2, 2 do
            if grid[river_y] and grid[river_y][math.floor(river_x + i)] then
                grid[river_y][math.floor(river_x + i)].type = "water"
            end
        end
        river_y = river_y + 1
    end
    print("Generated a river.")
end

function MapGenerationService._generateMountains(grid)
    local w, h = #grid[1], #grid
    local num_ranges = 3
    
    for i = 1, num_ranges do
        local mountain_x = love.math.random(0, w)
        local mountain_y = love.math.random(0, h)
        local mountain_size = love.math.random(30, 60)

        -- A simple circle of mountain tiles
        for y_offset = -mountain_size, mountain_size do
            for x_offset = -mountain_size, mountain_size do
                if math.sqrt(x_offset^2 + y_offset^2) < mountain_size then
                    local final_x = math.floor(mountain_x + x_offset)
                    local final_y = math.floor(mountain_y + y_offset)
                     if grid[final_y] and grid[final_y][final_x] then
                        grid[final_y][final_x].type = "mountain"
                     end
                end
            end
        end
    end
    print("Generated " .. num_ranges .. " mountain ranges.")
end

function MapGenerationService._generateHighways(all_districts, map_w, map_h, downtown_district, params)
    local highway_paths = { ring_road = {}, highways = {} }
    
    -- Generate ring road if enabled
    if params.generate_ringroad ~= false then
        -- MODIFIED: Pass the downtown_district to the ring road generator
        local ring_road_nodes = RingRoad.generatePath(all_districts, map_w, map_h, downtown_district, params)
        if #ring_road_nodes > 0 then 
            highway_paths.ring_road = MapGenerationService._generateSplinePoints(ring_road_nodes, 10) 
        end
    end
    
    -- Generate highways if enabled
    if params.generate_highways ~= false then
        local ns_highway_paths = HighwayNS.generatePaths(map_w, map_h, all_districts, params)
        local ew_highway_paths = HighwayEW.generatePaths(map_w, map_h, all_districts, params)
        
        local all_highway_paths = {}
        for _, path in ipairs(ns_highway_paths) do table.insert(all_highway_paths, path) end
        for _, path in ipairs(ew_highway_paths) do table.insert(all_highway_paths, path) end

        highway_paths.highways = HighwayMerger.applyMergingLogic(all_highway_paths, highway_paths.ring_road, params)
    end
    
    print("Generated highways with debug parameters")
    return highway_paths
end

return MapGenerationService