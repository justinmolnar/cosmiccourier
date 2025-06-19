-- game/map.lua (Refactored with modular generators - MVC approach)
local Map = {}
Map.__index = Map

-- Import all the generator modules
local Downtown = require("game.generators.downtown")
local Districts = require("game.generators.districts")
local HighwayNS = require("game.generators.highway_ns")
local HighwayEW = require("game.generators.highway_ew")
local RingRoad = require("game.generators.ringroad")
local HighwayMerger = require("game.generators.highway_merger")
local ConnectingRoads = require("game.generators.connecting_roads")

-- =============================================================================
-- == HELPER FUNCTIONS (Correctly Ordered)
-- =============================================================================

local function createGrid(width, height, default_type)
    local grid = {}
    for y = 1, height do
        grid[y] = {}
        for x = 1, width do
            grid[y][x] = { type = default_type or "grass" }
        end
    end
    return grid
end

local function inBounds(x, y, width, height)
    return x >= 1 and x <= width and y >= 1 and y <= height
end

local function isRoad(tile_type)
    return tile_type == "road" or
           tile_type == "downtown_road" or
           tile_type == "arterial" or
           tile_type == "highway" or
           tile_type == "highway_ring" or
           tile_type == "highway_ns" or
           tile_type == "highway_ew"
end

local function floodFill(grid, start_x, start_y, road_check_func)
    local w, h = #grid[1], #grid
    if not inBounds(start_x, start_y, w, h) or not road_check_func(grid[start_y][start_x].type) then
        return 0
    end

    local count = 0
    local q = {{x = start_x, y = start_y}}
    local visited = {[start_y .. "," .. start_x] = true}

    while #q > 0 do
        local current = table.remove(q, 1)
        count = count + 1

        local neighbors = {{current.x, current.y - 1}, {current.x, current.y + 1}, {current.x - 1, current.y}, {current.x + 1, current.y}}
        for _, pos in ipairs(neighbors) do
            local nx, ny = pos[1], pos[2]
            local key = ny .. "," .. nx
            if inBounds(nx, ny, w, h) and not visited[key] and road_check_func(grid[ny][nx].type) then
                visited[key] = true
                table.insert(q, {x = nx, y = ny})
            end
        end
    end

    return count
end


function Map:new(C)
    local instance = setmetatable({}, Map)
    instance.C = C
    instance.grid = {}
    instance.building_plots = {}
    instance.current_scale = C.MAP.SCALES.DOWNTOWN
    instance.scale_grids = {}
    instance.scale_building_plots = {}
    instance.downtown_offset = {x = 0, y = 0}
    instance.transition_state = { 
        active = false, 
        timer = 0, 
        duration = C.ZOOM.TRANSITION_DURATION, 
        from_scale = 1, 
        to_scale = 1, 
        progress = 0 
    }
    return instance
end

-- =============================================================================
-- == MASTER GENERATION FUNCTION (Using modular generators)
-- =============================================================================
function Map:generate()
    print("Beginning modular map generation process...")
    
    local downtown_grid = Downtown.generateDowntownModule(self.C.MAP)
    self.scale_grids[self.C.MAP.SCALES.DOWNTOWN] = downtown_grid
    self.scale_building_plots[self.C.MAP.SCALES.DOWNTOWN] = self:getPlotsFromGrid(downtown_grid)
    print("Generated Downtown Core...")

    local city_grid = self:generateCityModuleModular(downtown_grid)
    self.scale_grids[self.C.MAP.SCALES.CITY] = city_grid
    self.scale_building_plots[self.C.MAP.SCALES.CITY] = self:getPlotsFromGrid(city_grid)
    print("Generated Metropolitan Area...")

    self.grid = self.scale_grids[self.current_scale]
    self.building_plots = self.scale_building_plots[self.current_scale]
    
    print("Modular map generation complete. Found " .. #self.building_plots .. " valid building plots.")
end

function Map:generateCityModuleModular(downtown_grid_module)
    local C_MAP = self.C.MAP
    local W, H = C_MAP.CITY_GRID_WIDTH, C_MAP.CITY_GRID_HEIGHT
    local grid = createGrid(W, H, "plot")

    local all_districts = Districts.generateAll(grid, W, H, downtown_grid_module, self)
    print("Generated districts using Districts module")

    local ring_road_nodes = RingRoad.generatePath(all_districts, W, H)
    local ring_road_curve = {}
    if #ring_road_nodes > 0 then
        ring_road_curve = self:generateSplinePoints(ring_road_nodes, 10)
    end
    print("Generated ring road using RingRoad module")

    local ns_highway_paths = HighwayNS.generatePaths(W, H, all_districts)
    local ew_highway_paths = HighwayEW.generatePaths(W, H, all_districts)
    local all_highway_paths = {}
    
    for _, path in ipairs(ns_highway_paths) do
        table.insert(all_highway_paths, path)
    end
    for _, path in ipairs(ew_highway_paths) do
        table.insert(all_highway_paths, path)
    end
    print("Generated highways using HighwayNS and HighwayEW modules")

    local merged_highway_paths = HighwayMerger.applyMergingLogic(all_highway_paths, ring_road_curve)
    print("Applied highway merging using HighwayMerger module")

    local highway_points = self:extractHighwayPoints(ring_road_curve, merged_highway_paths)
    local connections = ConnectingRoads.generateConnections(grid, all_districts, highway_points, W, H)
    print("Generated connecting roads using ConnectingRoads module")

    self:drawAllRoadsToGrid(grid, ring_road_curve, merged_highway_paths, connections)
    
    return grid
end

function Map:extractHighwayPoints(ring_road_curve, highway_paths)
    local points = {}
    
    for _, point in ipairs(ring_road_curve) do
        table.insert(points, point)
    end
    
    for _, highway_path in ipairs(highway_paths) do
        local highway_curve = self:generateSplinePoints(highway_path, 10)
        for _, point in ipairs(highway_curve) do
            table.insert(points, point)
        end
    end
    
    return points
end

function Map:drawAllRoadsToGrid(grid, ring_road_curve, merged_highway_paths, connections)
    if #ring_road_curve > 1 then
        for i = 1, #ring_road_curve - 1 do
            self:drawThickLineColored(grid, ring_road_curve[i].x, ring_road_curve[i].y, 
                                     ring_road_curve[i+1].x, ring_road_curve[i+1].y, "highway_ring", 3)
        end
    end
    
    for highway_idx, path_nodes in ipairs(merged_highway_paths) do
        local highway_curve = self:generateSplinePoints(path_nodes, 10)
        local highway_type
        
        if highway_idx <= 2 then
            highway_type = "highway_ns"
        else
            highway_type = "highway_ew"
        end
        
        for i = 1, #highway_curve - 1 do
            self:drawThickLineColored(grid, highway_curve[i].x, highway_curve[i].y, 
                                     highway_curve[i+1].x, highway_curve[i+1].y, highway_type, 3)
        end
    end
    
    ConnectingRoads.drawConnections(grid, connections)
end

-- =============================================================================
-- == UTILITY FUNCTIONS
-- =============================================================================

function Map:getPlotsFromGrid(grid)
    if not grid or #grid == 0 then return {} end
    -- *** FIX: Swapped w and h to the correct order. ***
    local h, w = #grid, #grid[1]
    local plots = {}
    
    local MIN_NETWORK_SIZE = 50
    local visited_roads = {}
    local valid_road_tiles = {}

    for y = 1, h do
        for x = 1, w do
            local key = y .. "," .. x
            if isRoad(grid[y][x].type) and not visited_roads[key] then
                local network_tiles = {}
                local q = {{x=x, y=y}}
                visited_roads[key] = true
                
                while #q > 0 do
                    local current = table.remove(q, 1)
                    table.insert(network_tiles, current)
                    
                    local neighbors = {{current.x, current.y - 1}, {current.x, current.y + 1}, {current.x - 1, current.y}, {current.x + 1, current.y}}
                    for _, pos in ipairs(neighbors) do
                        local nx, ny = pos[1], pos[2]
                        local nkey = ny .. "," .. nx
                        if inBounds(nx, ny, w, h) and isRoad(grid[ny][nx].type) and not visited_roads[nkey] then
                            visited_roads[nkey] = true
                            table.insert(q, {x=nx, y=ny})
                        end
                    end
                end

                if #network_tiles >= MIN_NETWORK_SIZE then
                    for _, tile in ipairs(network_tiles) do
                        table.insert(valid_road_tiles, tile)
                    end
                end
            end
        end
    end

    local visited_plots = {}
    for _, road_tile in ipairs(valid_road_tiles) do
        local neighbors = {{road_tile.x, road_tile.y - 1}, {road_tile.x, road_tile.y + 1}, {road_tile.x - 1, road_tile.y}, {road_tile.x + 1, road_tile.y}}
        for _, plot_pos in ipairs(neighbors) do
            local px, py = plot_pos[1], plot_pos[2]
            local pkey = py .. "," .. px
            if inBounds(px, py, w, h) and (grid[py][px].type == 'plot' or grid[py][px].type == 'downtown_plot') and not visited_plots[pkey] then
                table.insert(plots, {x=px, y=py})
                visited_plots[pkey] = true
            end
        end
    end
    
    return plots
end


function Map:generateSplinePoints(points, num_segments)
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

function Map:drawThickLineColored(grid, x1, y1, x2, y2, road_type, thickness)
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
                    if inBounds(x + i, y + j, w, h) then
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
                    if inBounds(x + i, y + j, w, h) then
                        grid[y + j][x + i].type = road_type
                    end
                end
            end
        end
    end
end


-- =============================================================================
-- == MAP STATE MANAGEMENT & RENDERING
-- =============================================================================

function Map:setScale(new_scale)
    local C_MAP = self.C.MAP
    if not C_MAP.SCALE_NAMES[new_scale] then 
        print("ERROR: Invalid map scale:", new_scale) 
        return false 
    end
    if new_scale == self.current_scale then return true end
    
    self.transition_state.active = true
    self.transition_state.timer = 0
    self.transition_state.from_scale = self.current_scale
    self.transition_state.to_scale = new_scale
    self.transition_state.progress = 0
    
    print("Starting transition from", C_MAP.SCALE_NAMES[self.current_scale], "to", C_MAP.SCALE_NAMES[new_scale])
    return true
end

function Map:update(dt, game)
    if self.transition_state.active then
        self.transition_state.timer = self.transition_state.timer + dt
        self.transition_state.progress = self.transition_state.timer / self.transition_state.duration
        
        if self.transition_state.progress >= 1.0 then
            self.transition_state.active = false
            self.transition_state.progress = 1.0
            self.current_scale = self.transition_state.to_scale
            self.grid = self.scale_grids[self.current_scale]
            self.building_plots = self.scale_building_plots[self.current_scale]
            
            if game and game.EventBus then
                game.EventBus:publish("map_scale_changed")
            end
            
            print("Transition complete - now at", self.C.MAP.SCALE_NAMES[self.current_scale])
        end
    end
end

function Map:draw()
    if self.transition_state.active then
        local progress = self.transition_state.progress
        local eased_progress = 1 - (1 - progress) * (1 - progress)
        self:drawGrid(self.scale_grids[self.transition_state.from_scale], 1 - eased_progress)
        self:drawGrid(self.scale_grids[self.transition_state.to_scale], eased_progress)
    else
        self:drawGrid(self.grid, 1)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function Map:drawGrid(grid, alpha)
    local C_MAP = self.C.MAP
    if not grid or #grid == 0 then return end
    
    local grid_h, grid_w = #grid, #grid[1]
    local tile_size = (#grid[1] == C_MAP.DOWNTOWN_GRID_WIDTH) and 16 or C_MAP.TILE_SIZE
    
    for y = 1, grid_h do 
        for x = 1, grid_w do
            local tile = grid[y][x]
            local color = C_MAP.COLORS.PLOT
            
            if isRoad(tile.type) then
                color = C_MAP.COLORS.ROAD
            elseif tile.type == "highway" then 
                color = {0.1, 0.1, 0.1}
            elseif tile.type == "highway_ring" then 
                color = {0.2, 0.4, 0.8}
            elseif tile.type == "highway_ns" then 
                color = {0.8, 0.2, 0.2}
            elseif tile.type == "highway_ew" then 
                color = {0.2, 0.8, 0.2}
            elseif tile.type == "downtown_plot" then 
                color = C_MAP.COLORS.DOWNTOWN_PLOT
            elseif tile.type == "grass" then 
                color = C_MAP.COLORS.GRASS 
            end
            
            love.graphics.setColor(color[1], color[2], color[3], alpha or 1)
            love.graphics.rectangle("fill", (x-1) * tile_size, (y-1) * tile_size, tile_size, tile_size)
        end 
    end
end

-- =============================================================================
-- == PUBLIC API METHODS
-- =============================================================================

function Map:findNearestDowntownRoadTile(plot)
    if not plot then return nil end
    
    -- Explicitly use the downtown grid for this operation
    local grid = self.scale_grids[self.C.MAP.SCALES.DOWNTOWN]
    if not grid or #grid == 0 then return nil end
    
    local grid_h, grid_w = #grid, #grid[1]
    local x, y = plot.x, plot.y
    
    for r = 0, 2 do 
        for dy = -r, r do 
            for dx = -r, r do 
                if math.abs(dx) == r or math.abs(dy) == r then
                    local nx, ny = x + dx, y + dy
                    if inBounds(nx, ny, grid_w, grid_h) then 
                        if isRoad(grid[ny][nx].type) then 
                            return {x = nx, y = ny} 
                        end 
                    end
                end 
            end 
        end 
    end
    
    return nil
end

function Map:getRandomDowntownBuildingPlot()
    local downtown_plots = self.scale_building_plots[self.C.MAP.SCALES.DOWNTOWN]
    if downtown_plots and #downtown_plots > 0 then 
        return downtown_plots[love.math.random(1, #downtown_plots)] 
    end
    return nil
end

function Map:getCurrentScale() 
    return self.current_scale 
end

function Map:getScaleName() 
    return self.C.MAP.SCALE_NAMES[self.current_scale] or "Unknown Scale" 
end

function Map:findNearestRoadTile(plot)
    if not plot then return nil end
    
    local grid = self.scale_grids[self.current_scale] or self.grid
    if not grid or #grid == 0 then return nil end
    
    local grid_h, grid_w = #grid, #grid[1]
    local x, y = plot.x, plot.y
    
    for r = 0, 2 do 
        for dy = -r, r do 
            for dx = -r, r do 
                if math.abs(dx) == r or math.abs(dy) == r then
                    local nx, ny = x + dx, y + dy
                    if inBounds(nx, ny, grid_w, grid_h) then 
                        if isRoad(grid[ny][nx].type) then 
                            return {x = nx, y = ny} 
                        end 
                    end
                end 
            end 
        end 
    end
    
    return nil
end

function Map:getRandomBuildingPlot()
    if #self.building_plots > 0 then 
        return self.building_plots[love.math.random(1, #self.building_plots)] 
    end
    return nil
end

function Map:getPixelCoords(grid_x, grid_y)
    local grid = self.scale_grids[self.current_scale] or self.grid
    if not grid or #grid == 0 then return 0, 0 end
    
    local C_MAP = self.C.MAP
    local tile_size = (#grid[1] == C_MAP.DOWNTOWN_GRID_WIDTH) and 16 or C_MAP.TILE_SIZE
    return (grid_x - 0.5) * tile_size, (grid_y - 0.5) * tile_size
end

function Map:getDowntownPixelCoords(grid_x, grid_y)
    local C_MAP = self.C.MAP
    local DOWNTOWN_TILE_SIZE = 16
    
    local local_px = (grid_x - 0.5) * DOWNTOWN_TILE_SIZE
    local local_py = (grid_y - 0.5) * DOWNTOWN_TILE_SIZE

    if self.current_scale == self.C.MAP.SCALES.DOWNTOWN then
        return local_px, local_py
    else
        local city_tile_size = C_MAP.TILE_SIZE
        
        local downtown_offset_px = (self.downtown_offset.x - 0.5) * city_tile_size
        local downtown_offset_py = (self.downtown_offset.y - 0.5) * city_tile_size

        local scale_ratio = city_tile_size / DOWNTOWN_TILE_SIZE
        local scaled_local_px = local_px * scale_ratio
        local scaled_local_py = local_py * scale_ratio
        
        return downtown_offset_px + scaled_local_px, downtown_offset_py + scaled_local_py
    end
end

function Map:getCurrentTileSize()
    local grid = self.scale_grids[self.current_scale] or self.grid
    if not grid or #grid == 0 then return 16 end
    local C_MAP = self.C.MAP
    return (#grid[1] == C_MAP.DOWNTOWN_GRID_WIDTH) and 16 or C_MAP.TILE_SIZE
end

return Map