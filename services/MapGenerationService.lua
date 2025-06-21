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

-- NEW, REUSABLE FUNCTION TO "STAMP" A CITY
function MapGenerationService.generateCityAt(target_grid, center_x, center_y, city_config, params, map_instance)
    print(string.format("Generating city at (%d, %d)", center_x, center_y))

    local city_w = city_config.CITY_GRID_WIDTH
    local city_h = city_config.CITY_GRID_HEIGHT

    -- Define the city's overall bounding box on the target grid
    local city_bounds = {
        x = center_x - math.floor(city_w / 2),
        y = center_y - math.floor(city_h / 2),
        w = city_w,
        h = city_h
    }

    -- 1. Create Downtown in the center of the city area
    local downtown_w = city_config.DOWNTOWN_GRID_WIDTH
    local downtown_h = city_config.DOWNTOWN_GRID_HEIGHT
    local downtown_district = {
        x = center_x - math.floor(downtown_w / 2),
        y = center_y - math.floor(downtown_h / 2),
        w = downtown_w,
        h = downtown_h
    }
    
    -- Ensure the map instance knows where its primary downtown is, for entity placement
    if map_instance then
        map_instance.downtown_offset = { x = downtown_district.x, y = downtown_district.y }
    end
    
    Downtown.generateDowntownModule(target_grid, downtown_district, "downtown_road", "downtown_plot", params)
    
    -- 2. Generate surrounding districts
    local all_districts = Districts.generateAll(target_grid, city_bounds.w, city_bounds.h, downtown_district, params)

    -- 3. Generate highway network for this city
    local ring_road_nodes = RingRoad.generatePath(all_districts, city_bounds.w, city_bounds.h, params)
    local ring_road_curve = {}
    if #ring_road_nodes > 0 then
        ring_road_curve = MapGenerationService._generateSplinePoints(ring_road_nodes, 10)
    end

    local ns_paths = HighwayNS.generatePaths(city_bounds.w, city_bounds.h, all_districts, params)
    local ew_paths = HighwayEW.generatePaths(city_bounds.w, city_bounds.h, all_districts, params)
    
    local all_highway_paths = {}
    for _, path in ipairs(ns_paths) do table.insert(all_highway_paths, path) end
    for _, path in ipairs(ew_paths) do table.insert(all_highway_paths, path) end

    local merged_highway_paths = HighwayMerger.applyMergingLogic(all_highway_paths, ring_road_curve, params)
    
    -- 4. Generate roads connecting everything
    local highway_points = MapGenerationService._extractHighwayPoints(ring_road_curve, merged_highway_paths)
    local connections = ConnectingRoads.generateConnections(target_grid, all_districts, highway_points, city_bounds.w, city_bounds.h, params)

    -- 5. Draw all the generated roads onto the target grid
    MapGenerationService._drawAllRoadsToGrid(target_grid, ring_road_curve, merged_highway_paths, connections, params, city_config)
    ConnectingRoads.drawConnections(target_grid, connections, params)

    print(string.format("Finished generating city at (%d, %d)", center_x, center_y))
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

return MapGenerationService