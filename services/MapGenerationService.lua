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
    MapGenerationService.generateCityAt(map, map.grid, math.floor(city_w / 2), math.floor(city_h / 2), C_MAP, params)

    -- Extract building plots from the newly generated city grid
    map.building_plots = map:getPlotsFromGrid(map.grid)

    -- Clear any cached data from older map versions
    map.scale_grids = nil
    map.scale_building_plots = nil

    print("MapGenerationService: Generation complete. Found " .. #map.building_plots .. " valid building plots.")
end

function MapGenerationService.generateRegion(region_map)
    local C_MAP = region_map.C.MAP
    local REGION_W = C_MAP.REGION_GRID_WIDTH
    local REGION_H = C_MAP.REGION_GRID_HEIGHT
    local CITY_W = C_MAP.CITY_GRID_WIDTH
    local CITY_H = C_MAP.CITY_GRID_HEIGHT
    local params = region_map.debug_params or {}

    region_map.grid = MapGenerationService._createGrid(REGION_W, REGION_H, "grass")
    region_map.cities_data = {} -- Initialize the cities data table

    MapGenerationService._generateRivers(region_map.grid)
    MapGenerationService._generateMountains(region_map.grid)

    -- Generate cities and collect their LOCAL data
    -- MAIN CITY
    local main_city_center_x = REGION_W / 2
    local main_city_center_y = REGION_H / 2
    local main_city_data = MapGenerationService.generateCityAt(region_map, region_map.grid, main_city_center_x, main_city_center_y, C_MAP, MapGenerationService._deepCopyParams(params))
    table.insert(region_map.cities_data, main_city_data)
    
    -- SECOND CITY
    local second_city_x = CITY_W / 2 + 20
    local second_city_y = REGION_H - CITY_H / 2 - 20
    local second_city_data = MapGenerationService.generateCityAt(region_map, region_map.grid, second_city_x, second_city_y, C_MAP, MapGenerationService._deepCopyParams(params))
    table.insert(region_map.cities_data, second_city_data)

    -- THE FIX: Translate all local city data into global region coordinates
    local all_districts_in_region = {}
    for city_index, city in ipairs(region_map.cities_data) do
        local city_offset_x = city.center_x - (CITY_W / 2)
        local city_offset_y = city.center_y - (CITY_H / 2)
        
        -- Translate districts
        for _, dist in ipairs(city.districts) do
            dist.x = dist.x + city_offset_x
            dist.y = dist.y + city_offset_y
            table.insert(all_districts_in_region, dist)
        end

        -- Translate ring road points
        local regional_ring_road = {}
        for _, point in ipairs(city.ring_road) do
            table.insert(regional_ring_road, {
                x = point.x + city_offset_x,
                y = point.y + city_offset_y
            })
        end
        
        -- Update the stored city data with translated points
        region_map.cities_data[city_index].ring_road = regional_ring_road
        region_map.cities_data[city_index].districts = city.districts
    end

    -- Generate REGIONAL highways using the correctly translated data
    print("--- BEGIN REGIONAL HIGHWAY GENERATION ---")
    local regional_ns_highways = HighwayNS.generatePaths(REGION_W, REGION_H, all_districts_in_region, params)
    local regional_ew_highways = HighwayEW.generatePaths(REGION_W, REGION_H, all_districts_in_region, region_map.cities_data, params)
    
    local all_regional_highways = {}
    for _, path in ipairs(regional_ns_highways) do table.insert(all_regional_highways, path) end
    for _, path in ipairs(regional_ew_highways) do table.insert(all_regional_highways, path) end

    -- Draw the new regional highways onto the main region grid
    local num_ns = (params and params.num_ns_highways) or 2
    for i, path in ipairs(all_regional_highways) do
        local highway_type = (i <= num_ns) and "highway_ns" or "highway_ew"
        local highway_curve = MapGenerationService._generateSplinePoints(path, 10)
        for j = 1, #highway_curve - 1 do
            MapGenerationService._drawThickLineColored(region_map.grid, highway_curve[j].x, highway_curve[j].y, highway_curve[j+1].x, highway_curve[j+1].y, highway_type, 3)
        end
    end
    print("--- END REGIONAL HIGHWAY GENERATION ---")

    -- The rest of the function for setting up city/downtown offsets and plots remains the same...
    local city_map = Game.maps.city
    city_map.grid = MapGenerationService._createGrid(CITY_W, CITY_H, "grass")

    region_map.main_city_offset = { x = main_city_center_x - CITY_W/2, y = main_city_center_y - CITY_H/2 }

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
    
    city_map.downtown_offset = { x = math.floor(CITY_W / 2) - math.floor(C_MAP.DOWNTOWN_GRID_WIDTH / 2), y = math.floor(CITY_H / 2) - math.floor(C_MAP.DOWNTOWN_GRID_HEIGHT / 2) }
    region_map.downtown_offset = { x = main_city_center_x - math.floor(C_MAP.DOWNTOWN_GRID_WIDTH / 2), y = main_city_center_y - math.floor(C_MAP.DOWNTOWN_GRID_HEIGHT / 2) }
    
    Game.entities.depot_plot = city_map:getRandomDowntownBuildingPlot()
    print("Region generation complete!")
end

function MapGenerationService.generateCityAt(map, target_grid, center_x, center_y, city_config, params)
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

    -- Generate the Ring Road for this city
    local ring_road_nodes = {}
    if params.generate_ringroad ~= false then
        ring_road_nodes = RingRoad.generatePath(all_districts, city_w, city_h, temp_downtown_district, params)
    end
    local ring_road_curve = {}
    if #ring_road_nodes > 0 then 
        ring_road_curve = MapGenerationService._generateSplinePoints(ring_road_nodes, 10) 
    end
    
    -- Generate connecting roads within the city
    local highway_points_for_connections = MapGenerationService._extractHighwayPoints(ring_road_curve, {})
    local connections = ConnectingRoads.generateConnections(temp_grid, all_districts, highway_points_for_connections, city_w, city_h, temp_downtown_district, city_params)

    -- Draw only the local roads (ring road and connectors) to the temporary grid
    MapGenerationService._drawAllRoadsToGrid(temp_grid, ring_road_curve, {}, connections, city_params, city_config)
    ConnectingRoads.drawConnections(temp_grid, connections, city_params)

    -- Stamping logic
    local stamped_count = 0
    local target_start_x = center_x - math.floor(city_w / 2)
    local target_start_y = center_y - math.floor(city_h / 2)
    local region_w = #target_grid[1]
    local region_h = #target_grid

    for y = 1, city_h do
        for x = 1, city_w do
            local source_tile = temp_grid[y][x]
            if source_tile.type ~= "grass" then
                local target_x = target_start_x + x - 1
                local target_y = target_start_y + y - 1
                
                if target_y >= 1 and target_y <= region_h and 
                   target_x >= 1 and target_x <= region_w and
                   target_grid[target_y] and target_grid[target_y][target_x] then
                    target_grid[target_y][target_x] = source_tile
                    stamped_count = stamped_count + 1
                end
            end
        end
    end
    
    print(string.format("--- END CITY GENERATION AT (%d, %d). Stamped %d tiles. ---", center_x, center_y, stamped_count))
    
    -- Calculate and return the generated data
    local building_plots = map:getPlotsFromGrid(temp_grid)

    return {
        districts = all_districts,
        ring_road = ring_road_curve,
        center_x = center_x,
        center_y = center_y,
        building_plots = building_plots
    }
end

function MapGenerationService.getPlotInAnotherCity(game, origin_city_index)
    local region_map = game.maps.region
    if not region_map or not region_map.cities_data or #region_map.cities_data < 2 then
        return nil -- Not enough cities to find "another" one
    end

    local possible_destinations = {}
    for i, city_data in ipairs(region_map.cities_data) do
        if i ~= origin_city_index then
            table.insert(possible_destinations, city_data)
        end
    end

    if #possible_destinations == 0 then
        return nil -- Should not happen if there are >= 2 cities
    end

    local destination_city = possible_destinations[love.math.random(1, #possible_destinations)]
    
    if destination_city.building_plots and #destination_city.building_plots > 0 then
        return destination_city.building_plots[love.math.random(1, #destination_city.building_plots)]
    end

    return nil
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
    if not points or #points == 0 then return {} end
    if #points == 1 then return {points[1]} end
    if #points == 2 then return {points[1], points[2]} end
    
    -- FIXED: For paths with only 3 points, just return them (no spline needed)
    if #points == 3 then
        return points
    end
    
    local curve_points = {}
    num_segments = math.max(1, num_segments or 10)
    
    -- FIXED: Pre-filter points to remove too-close duplicates (causes spline chaos)
    local filtered_points = {points[1]}
    local min_distance = 2.0 -- Minimum distance between control points
    
    for i = 2, #points do
        local last_point = filtered_points[#filtered_points]
        local current_point = points[i]
        local distance = math.sqrt((current_point.x - last_point.x)^2 + (current_point.y - last_point.y)^2)
        
        if distance >= min_distance then
            table.insert(filtered_points, current_point)
        end
    end
    
    -- Ensure we always include the last point
    if #filtered_points > 1 then
        local last_filtered = filtered_points[#filtered_points]
        local actual_last = points[#points]
        if last_filtered.x ~= actual_last.x or last_filtered.y ~= actual_last.y then
            table.insert(filtered_points, actual_last)
        end
    end
    
    print(string.format("Spline: Filtered %d points down to %d points", #points, #filtered_points))
    
    -- If we don't have enough points after filtering, just return what we have
    if #filtered_points < 4 then
        return filtered_points
    end
    
    -- FIXED: Use the filtered points for spline generation
    points = filtered_points
    
    -- Add the first point
    table.insert(curve_points, points[1])
    
    -- FIXED: Catmull-Rom spline with proper bounds checking and smoother interpolation
    for i = 2, #points - 2 do
        local p0, p1, p2, p3 = points[i-1], points[i], points[i+1], points[i+2]
        
        -- FIXED: Adaptive segment count based on distance between points
        local segment_distance = math.sqrt((p2.x - p1.x)^2 + (p2.y - p1.y)^2)
        local adaptive_segments = math.max(3, math.min(num_segments, math.floor(segment_distance / 4)))
        
        for t_step = 0, adaptive_segments - 1 do
            local t = t_step / adaptive_segments
            
            -- FIXED: Cleaner Catmull-Rom formula with bounds checking
            local t2 = t * t
            local t3 = t2 * t
            
            -- Catmull-Rom basis functions
            local b0 = -0.5 * t3 + t2 - 0.5 * t
            local b1 = 1.5 * t3 - 2.5 * t2 + 1
            local b2 = -1.5 * t3 + 2 * t2 + 0.5 * t
            local b3 = 0.5 * t3 - 0.5 * t2
            
            local x = b0 * p0.x + b1 * p1.x + b2 * p2.x + b3 * p3.x
            local y = b0 * p0.y + b1 * p1.y + b2 * p2.y + b3 * p3.y
            
            -- FIXED: Bounds checking to prevent crazy values
            if x >= -1000 and x <= 10000 and y >= -1000 and y <= 10000 then
                table.insert(curve_points, {x = math.floor(x + 0.5), y = math.floor(y + 0.5)})
            else
                print(string.format("Spline: Rejected out-of-bounds point (%f, %f)", x, y))
            end
        end
    end
    
    -- Add the last point
    table.insert(curve_points, points[#points])
    
    -- FIXED: Post-process to remove duplicate consecutive points and weird outliers
    local cleaned_points = {curve_points[1]}
    for i = 2, #curve_points do
        local last_point = cleaned_points[#cleaned_points]
        local current_point = curve_points[i]
        
        -- Skip duplicate points
        if current_point.x ~= last_point.x or current_point.y ~= last_point.y then
            -- FIXED: Skip points that create crazy jumps (outlier detection)
            local distance = math.sqrt((current_point.x - last_point.x)^2 + (current_point.y - last_point.y)^2)
            if distance <= 50 then -- Max reasonable distance between consecutive spline points
                table.insert(cleaned_points, current_point)
            else
                print(string.format("Spline: Rejected outlier point with distance %f", distance))
            end
        end
    end
    
    print(string.format("Spline: Generated %d curve points from %d control points", #cleaned_points, #points))
    return cleaned_points
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