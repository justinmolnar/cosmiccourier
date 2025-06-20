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

function MapGenerationService.generateMap(map)
    print("MapGenerationService: Beginning unified map generation process...")
    local C_MAP = map.C.MAP
    
    -- Use debug parameters from the map if available
    local params = map.debug_params or {}
    
    print("MapGenerationService: Using debug parameters:")
    for key, value in pairs(params) do
        print(string.format("  %s: %s", key, tostring(value)))
    end
    
    -- Validate constants are numbers
    local downtown_w = tonumber(C_MAP.DOWNTOWN_GRID_WIDTH)
    local downtown_h = tonumber(C_MAP.DOWNTOWN_GRID_HEIGHT)
    local city_w = tonumber(C_MAP.CITY_GRID_WIDTH)
    local city_h = tonumber(C_MAP.CITY_GRID_HEIGHT)
    
    if not downtown_w or not downtown_h or not city_w or not city_h then
        error("MapGenerationService: Invalid map dimensions in constants")
    end
    
    -- Initialize the grid
    map.grid = MapGenerationService._createGrid(city_w, city_h, "grass")
    
    -- Calculate downtown positioning
    map.downtown_offset = {
        x = math.floor((city_w - downtown_w) / 2),
        y = math.floor((city_h - downtown_h) / 2)
    }
    
    local downtown_district = {
        x = map.downtown_offset.x, 
        y = map.downtown_offset.y,
        w = downtown_w, 
        h = downtown_h
    }
    
    -- Generate downtown core
    MapGenerationService._generateDowntown(map.grid, downtown_district, C_MAP, params)
    
    -- Generate districts
    local all_districts = MapGenerationService._generateDistricts(map.grid, downtown_district, C_MAP, params)
    
    -- Generate highway network
    local highway_paths = MapGenerationService._generateHighways(all_districts, C_MAP, params)
    
    -- Generate connecting roads
    MapGenerationService._generateConnectingRoads(map.grid, all_districts, highway_paths, C_MAP, params)
    
    -- Extract building plots
    map.building_plots = map:getPlotsFromGrid(map.grid)
    
    -- Clear scale caches
    map.scale_grids = nil
    map.scale_building_plots = nil
    
    print("MapGenerationService: Generation complete. Found " .. #map.building_plots .. " valid building plots.")
end

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

function MapGenerationService._generateDowntown(grid, downtown_district, C_MAP, params)
    Downtown.generateDowntownModule(grid, downtown_district, "road", "plot", C_MAP.NUM_SECONDARY_ROADS, params)
    print("MapGenerationService: Generated Downtown Core with debug parameters")
end

function MapGenerationService._generateDistricts(grid, downtown_district, C_MAP, params)
    local all_districts = Districts.generateAll(grid, C_MAP.CITY_GRID_WIDTH, C_MAP.CITY_GRID_HEIGHT, downtown_district, nil, params)
    print("MapGenerationService: Generated districts and internal roads with debug parameters")
    return all_districts
end

function MapGenerationService._generateHighways(all_districts, C_MAP, params)
    local highway_paths = { ring_road = {}, highways = {} }
    
    -- Generate ring road if enabled
    if params.generate_ringroad ~= false then
        local ring_road_nodes = RingRoad.generatePath(all_districts, C_MAP.CITY_GRID_WIDTH, C_MAP.CITY_GRID_HEIGHT, params)
        if #ring_road_nodes > 0 then 
            highway_paths.ring_road = MapGenerationService._generateSplinePoints(ring_road_nodes, 10) 
        end
    end
    
    -- Generate highways if enabled
    if params.generate_highways ~= false then
        local ns_highway_paths = HighwayNS.generatePaths(C_MAP.CITY_GRID_WIDTH, C_MAP.CITY_GRID_HEIGHT, all_districts, params)
        local ew_highway_paths = HighwayEW.generatePaths(C_MAP.CITY_GRID_WIDTH, C_MAP.CITY_GRID_HEIGHT, all_districts, params)
        
        local all_highway_paths = {}
        for _, path in ipairs(ns_highway_paths) do table.insert(all_highway_paths, path) end
        for _, path in ipairs(ew_highway_paths) do table.insert(all_highway_paths, path) end

        highway_paths.highways = HighwayMerger.applyMergingLogic(all_highway_paths, highway_paths.ring_road, params)
    end
    
    print("MapGenerationService: Generated highways with debug parameters")
    return highway_paths
end

function MapGenerationService._generateConnectingRoads(grid, all_districts, highway_paths, C_MAP, params)
    local highway_points = MapGenerationService._extractHighwayPoints(highway_paths.ring_road, highway_paths.highways)
    local connections = ConnectingRoads.generateConnections(grid, all_districts, highway_points, C_MAP.CITY_GRID_WIDTH, C_MAP.CITY_GRID_HEIGHT, params)
    
    MapGenerationService._drawAllRoadsToGrid(grid, highway_paths.ring_road, highway_paths.highways, connections, params)
    ConnectingRoads.drawConnections(grid, connections, params)
    print("MapGenerationService: Generated connecting roads with debug parameters")
end

function MapGenerationService._extractHighwayPoints(ring_road_curve, highway_paths)
    local points = {}
    
    for _, point in ipairs(ring_road_curve) do
        table.insert(points, point)
    end
    
    for _, highway_path in ipairs(highway_paths) do
        local highway_curve = MapGenerationService._generateSplinePoints(highway_path, 10)
        for _, point in ipairs(highway_curve) do
            table.insert(points, point)
        end
    end
    
    return points
end

function MapGenerationService._drawAllRoadsToGrid(grid, ring_road_curve, merged_highway_paths, connections, params)
    local thickness = 3
    
    -- Draw ring road
    if #ring_road_curve > 1 then
        for i = 1, #ring_road_curve - 1 do
            MapGenerationService._drawThickLineColored(grid, ring_road_curve[i].x, ring_road_curve[i].y, 
                                     ring_road_curve[i+1].x, ring_road_curve[i+1].y, "highway_ring", thickness)
        end
    end
    
    -- Draw highways
    local num_ns_highways = (params and params.num_ns_highways) or 2
    for highway_idx, path_nodes in ipairs(merged_highway_paths) do
        local highway_curve = MapGenerationService._generateSplinePoints(path_nodes, 10)
        local highway_type = highway_idx <= num_ns_highways and "highway_ns" or "highway_ew"
        
        for i = 1, #highway_curve - 1 do
            MapGenerationService._drawThickLineColored(grid, highway_curve[i].x, highway_curve[i].y, 
                                     highway_curve[i+1].x, highway_curve[i+1].y, highway_type, thickness)
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

    if math.abs(dx) > math.abs(dy) then
        local x_min, x_max = math.min(x1, x2), math.max(x1, x2)
        for x = x_min, x_max do
            local y = math.floor(y1 + dy * (x - x1) / dx + 0.5)
            for i = -half_thick, half_thick do
                for j = -half_thick, half_thick do
                    if x + i >= 1 and x + i <= w and y + j >= 1 and y + j <= h then
                        grid[y + j][x + i].type = road_type
                    end
                end
            end
        end
    else
        local y_min, y_max = math.min(y1, y2), math.max(y1, y2)
        for y = y_min, y_max do
            local x = dx == 0 and x1 or math.floor(x1 + dx * (y - y1) / dy + 0.5)
            for i = -half_thick, half_thick do
                for j = -half_thick, half_thick do
                    if x + i >= 1 and x + i <= w and y + j >= 1 and y + j <= h then
                        grid[y + j][x + i].type = road_type
                    end
                end
            end
        end
    end
end

return MapGenerationService