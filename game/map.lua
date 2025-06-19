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

-- Helper function to create a grid of a given size and type
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

-- Helper function to check if a grid coordinate is within the map boundaries
local function inBounds(x, y, width, height)
    return x >= 1 and x <= width and y >= 1 and y <= height
end

function Map:new(C)
    local instance = setmetatable({}, Map)
    instance.C = C
    instance.grid = {}
    instance.building_plots = {}
    instance.current_scale = C.MAP.SCALES.DOWNTOWN
    instance.scale_grids = {}
    instance.scale_building_plots = {}
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
    
    -- Generate downtown using dedicated module
    local downtown_grid = Downtown.generateDowntownModule(self.C.MAP)
    self.scale_grids[self.C.MAP.SCALES.DOWNTOWN] = downtown_grid
    self.scale_building_plots[self.C.MAP.SCALES.DOWNTOWN] = self:getPlotsFromGrid(downtown_grid)
    print("Generated Downtown Core...")

    -- Generate city using modular approach
    local city_grid = self:generateCityModuleModular(downtown_grid)
    self.scale_grids[self.C.MAP.SCALES.CITY] = city_grid
    self.scale_building_plots[self.C.MAP.SCALES.CITY] = self:getPlotsFromGrid(city_grid)
    print("Generated Metropolitan Area...")

    self.grid = self.scale_grids[self.current_scale]
    self.building_plots = self.scale_building_plots[self.current_scale]
    
    print("Modular map generation complete.")
end

function Map:generateCityModuleModular(downtown_grid_module)
    local C_MAP = self.C.MAP
    local W, H = C_MAP.CITY_GRID_WIDTH, C_MAP.CITY_GRID_HEIGHT
    local grid = createGrid(W, H, "plot")

    -- 1. Generate districts using dedicated module
    local all_districts = Districts.generateAll(grid, W, H, downtown_grid_module)
    print("Generated districts using Districts module")

    -- 2. Generate ring road using dedicated module
    local ring_road_nodes = RingRoad.generatePath(all_districts, W, H)
    local ring_road_curve = {}
    if #ring_road_nodes > 0 then
        ring_road_curve = self:generateSplinePoints(ring_road_nodes, 10)
    end
    print("Generated ring road using RingRoad module")

    -- 3. Generate highways using dedicated modules
    local ns_highway_paths = HighwayNS.generatePaths(W, H, all_districts)
    local ew_highway_paths = HighwayEW.generatePaths(W, H, all_districts)
    local all_highway_paths = {}
    
    -- Combine highway paths (NS first, then EW for proper indexing)
    for _, path in ipairs(ns_highway_paths) do
        table.insert(all_highway_paths, path)
    end
    for _, path in ipairs(ew_highway_paths) do
        table.insert(all_highway_paths, path)
    end
    print("Generated highways using HighwayNS and HighwayEW modules")

    -- 4. Apply merging logic using dedicated module
    local merged_highway_paths = HighwayMerger.applyMergingLogic(all_highway_paths, ring_road_curve)
    print("Applied highway merging using HighwayMerger module")

    -- 5. Generate connecting roads (future implementation)
    local highway_points = self:extractHighwayPoints(ring_road_curve, merged_highway_paths)
    local connections = ConnectingRoads.generateConnections(grid, all_districts, highway_points, W, H)
    print("Generated connecting roads using ConnectingRoads module")

    -- 6. Draw all roads to the grid
    self:drawAllRoadsToGrid(grid, ring_road_curve, merged_highway_paths, connections)
    
    return grid
end

function Map:extractHighwayPoints(ring_road_curve, highway_paths)
    local points = {}
    
    -- Add ring road points
    for _, point in ipairs(ring_road_curve) do
        table.insert(points, point)
    end
    
    -- Add highway points
    for _, highway_path in ipairs(highway_paths) do
        local highway_curve = self:generateSplinePoints(highway_path, 10)
        for _, point in ipairs(highway_curve) do
            table.insert(points, point)
        end
    end
    
    return points
end

function Map:drawAllRoadsToGrid(grid, ring_road_curve, merged_highway_paths, connections)
    -- Draw ring road (BLUE)
    if #ring_road_curve > 1 then
        for i = 1, #ring_road_curve - 1 do
            self:drawThickLineColored(grid, ring_road_curve[i].x, ring_road_curve[i].y, 
                                     ring_road_curve[i+1].x, ring_road_curve[i+1].y, "highway_ring", 3)
        end
    end
    
    -- Draw merged highways with different colors
    for highway_idx, path_nodes in ipairs(merged_highway_paths) do
        local highway_curve = self:generateSplinePoints(path_nodes, 10)
        local highway_type
        
        -- Determine highway type based on index (first 2 are N/S, next 2 are E/W)
        if highway_idx <= 2 then
            highway_type = "highway_ns"  -- North-South highways (RED)
        else
            highway_type = "highway_ew"  -- East-West highways (GREEN)
        end
        
        for i = 1, #highway_curve - 1 do
            self:drawThickLineColored(grid, highway_curve[i].x, highway_curve[i].y, 
                                     highway_curve[i+1].x, highway_curve[i+1].y, highway_type, 3)
        end
    end
    
    -- Draw connecting roads (future implementation)
    ConnectingRoads.drawConnections(grid, connections)
end

-- =============================================================================
-- == UTILITY FUNCTIONS
-- =============================================================================

function Map:getPlotsFromGrid(grid)
    local plots = {}
    if not grid or #grid == 0 then return plots end
    local h, w = #grid, #grid[1]
    
    for y = 1, h do 
        for x = 1, w do 
            if grid[y][x].type == 'plot' or grid[y][x].type == 'downtown_plot' then 
                table.insert(plots, {x = x, y = y}) 
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
    local dx, dy = math.abs(x2 - x1), math.abs(y2 - y1)
    local sx, sy = (x1 < x2) and 1 or -1, (y1 < y2) and 1 or -1
    local err, x, y = dx - dy, x1, y1
    local half_thick = math.floor(thickness / 2)
    
    while true do
        for i = -half_thick, half_thick do
            for j = -half_thick, half_thick do
                if inBounds(x + i, y + j, w, h) then
                    grid[y + j][x + i].type = road_type
                end
            end
        end
        
        if x == x2 and y == y2 then break end
        
        local e2 = 2 * err
        if e2 > -dy then err = err - dy; x = x + sx end
        if e2 < dx then err = err + dx; y = y + sy end
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

function Map:update(dt)
    if self.transition_state.active then
        self.transition_state.timer = self.transition_state.timer + dt
        self.transition_state.progress = self.transition_state.timer / self.transition_state.duration
        
        if self.transition_state.progress >= 1.0 then
            self.transition_state.active = false
            self.transition_state.progress = 1.0
            self.current_scale = self.transition_state.to_scale
            self.grid = self.scale_grids[self.current_scale]
            self.building_plots = self.scale_building_plots[self.current_scale]
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
            
            if tile.type == "road" or tile.type == "arterial" then 
                color = C_MAP.COLORS.ROAD
            elseif tile.type == "highway" then 
                color = {0.1, 0.1, 0.1}
            elseif tile.type == "highway_ring" then 
                color = {0.2, 0.4, 0.8}  -- Blue for ring roads
            elseif tile.type == "highway_ns" then 
                color = {0.8, 0.2, 0.2}  -- Red for North-South highways
            elseif tile.type == "highway_ew" then 
                color = {0.2, 0.8, 0.2}  -- Green for East-West highways
            elseif tile.type == "downtown_plot" then 
                color = C_MAP.COLORS.DOWNTOWN_PLOT
            elseif tile.type == "downtown_road" then 
                color = C_MAP.COLORS.DOWNTOWN_ROAD
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
                        if grid[ny][nx].type == "road" or grid[ny][nx].type == "highway" or grid[ny][nx].type == "downtown_road" then 
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

return Map