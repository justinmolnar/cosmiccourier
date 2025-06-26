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
    -- Use debug params if they exist, otherwise use defaults from the new service
    local params = map.debug_params or {
        width = C_MAP.CITY_GRID_WIDTH,
        height = C_MAP.CITY_GRID_HEIGHT,
        use_wfc_for_zones = true,
        use_recursive_streets = true,
        generate_arterials = true
    }

    -- THE SWAP: Call the new, unified city generator
    local result = require("services.NewCityGenService").generateDetailedCity(params)

    if result and result.city_grid then
        -- Replace the map's grid with the newly generated one
        map.grid = result.city_grid
        print("MapGenerationService: Successfully replaced map grid with new generation.")
    else
        print("ERROR: NewCityGenService failed to return a valid city grid. Falling back to empty grid.")
        map.grid = MapGenerationService._createEmptyGrid(params.width, params.height, "grass")
    end
    
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
    local params = region_map.debug_params or {}

    -- Use the default city and downtown sizes from the constants file
    local city_w = C_MAP.CITY_GRID_WIDTH
    local city_h = C_MAP.CITY_GRID_HEIGHT
    print(string.format("MapGenerationService: Using default %dx%d city size for generation.", city_w, city_h))

    region_map.grid = MapGenerationService._createGrid(REGION_W, REGION_H, "grass")
    region_map.cities_data = {}
    
    Game.main_city_debug_data = {}

    MapGenerationService._generateRivers(region_map.grid)
    MapGenerationService._generateMountains(region_map.grid)

    -- MAIN CITY
    local main_city_center_x = REGION_W / 2
    local main_city_center_y = REGION_H / 2
    local main_city_data = MapGenerationService.generateCityAt(region_map, region_map.grid, main_city_center_x, main_city_center_y, C_MAP, MapGenerationService._deepCopyParams(params))
    if main_city_data then 
        table.insert(region_map.cities_data, main_city_data)
        Game.main_city_debug_data.zone_grid = main_city_data.zone_grid
        Game.main_city_debug_data.arterial_paths = main_city_data.arterial_paths
    end
    
    -- SECOND CITY
    local second_city_x = REGION_W - (city_w / 2) - 50
    local second_city_y = REGION_H - (city_h / 2) - 50
    local second_city_data = MapGenerationService.generateCityAt(region_map, region_map.grid, second_city_x, second_city_y, C_MAP, MapGenerationService._deepCopyParams(params))
    if second_city_data then table.insert(region_map.cities_data, second_city_data) end

    -- Translate city data into global region coordinates
    local all_districts_in_region = {}
    for city_index, city in ipairs(region_map.cities_data) do
        if city and city.districts and city.ring_road then
            local city_offset_x = city.center_x - (city_w / 2)
            local city_offset_y = city.center_y - (city_h / 2)
            for _, dist in ipairs(city.districts) do
                if dist then
                    for _, point in ipairs(dist) do
                        point.x = point.x + city_offset_x
                        point.y = point.y + city_offset_y
                    end
                    table.insert(all_districts_in_region, dist)
                end
            end
        end
    end

    -- Generate REGIONAL highways
    local regional_ns_highways = HighwayNS.generatePaths(REGION_W, REGION_H, {}, params)
    local regional_ew_highways = HighwayEW.generatePaths(REGION_W, REGION_H, {}, region_map.cities_data, params)
    local all_regional_highways = {}
    for _, path in ipairs(regional_ns_highways) do table.insert(all_regional_highways, path) end
    for _, path in ipairs(regional_ew_highways) do table.insert(all_regional_highways, path) end
    for i, path in ipairs(all_regional_highways) do
        local highway_curve = MapGenerationService._generateSplinePoints(path, 10)
        if #highway_curve > 1 then
            local highway_type = (i <= #regional_ns_highways) and "highway_ns" or "highway_ew"
            for j = 1, #highway_curve - 1 do
                MapGenerationService._drawThickLineColored(region_map.grid, highway_curve[j].x, highway_curve[j].y, highway_curve[j+1].x, highway_curve[j+1].y, highway_type, 3)
            end
        end
    end

    -- Correctly set up the main city map for the player
    local city_map = Game.maps.city
    city_map.grid = main_city_data.city_grid
    region_map.main_city_offset = { x = main_city_center_x - city_w/2, y = main_city_center_y - city_h/2 }

    -- Capture debug data
    Game.main_city_debug_data.city_grid = city_map.grid
    Game.main_city_debug_data.street_segments = main_city_data.street_segments
    
    city_map.building_plots = city_map:getPlotsFromGrid(city_map.grid)
    
    -- Use new DOWNTOWN constants for offset calculation
    local downtown_w = C_MAP.DOWNTOWN_GRID_WIDTH
    local downtown_h = C_MAP.DOWNTOWN_GRID_HEIGHT
    city_map.downtown_offset = { 
        x = math.floor(city_w / 2) - math.floor(downtown_w / 2), 
        y = math.floor(city_h / 2) - math.floor(downtown_h / 2) 
    }
    
    Game.entities.depot_plot = city_map:getRandomDowntownBuildingPlot()
    print("Region generation complete! Playable city map populated.")
end

function MapGenerationService.generateCityAt(map, target_grid, center_x, center_y, city_config, params)
    print(string.format("--- BEGIN NEW CITY GENERATION AT (%d, %d) ---", center_x, center_y))

    local city_w = city_config.CITY_GRID_WIDTH
    local city_h = city_config.CITY_GRID_HEIGHT

    local city_grid = MapGenerationService._createGrid(city_w, city_h, "grass")
    
    -- STAGE 1: Zone Generation
    local zone_grid = require("services.WFCZoningService").generateCoherentZones(city_w, city_h, math.floor(city_w/2), math.floor(city_h/2))
    if not zone_grid then return nil end

    -- STAGE 2: Arterial Road Generation
    local arterial_paths = require("services.ArterialRoadService").generateArterialRoads(city_grid, zone_grid, params)

    -- STAGE 3: Street Generation
    local street_params = {
        min_block_size = params.min_block_size or math.max(4, math.floor(math.sqrt(city_w*city_h) / 15)),
        max_block_size = params.max_block_size or math.max(8, math.floor(math.sqrt(city_w*city_h) / 8)),
    }
    require("services.BlockSubdivisionService").generateStreets(city_grid, zone_grid, arterial_paths, street_params)

    -- STAGE 4: Fill remaining areas with plots
    require("services.BlockSubdivisionService")._fillGridWithPlots(city_grid, zone_grid, city_w, city_h)

    print(string.format("--- END CITY GENERATION AT (%d, %d). ---", center_x, center_y))
    
    -- Return a complete package of all generated data
    return {
        city_grid = city_grid,
        zone_grid = zone_grid,
        arterial_paths = arterial_paths,
        street_segments = Game.street_segments, -- This is temporarily stored on Game by the service
        center_x = center_x,
        center_y = center_y,
        building_plots = map:getPlotsFromGrid(city_grid)
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