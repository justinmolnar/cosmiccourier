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

function Map:isRoad(tile_type)
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
    print("Beginning unified map generation process...")
    local C_MAP = self.C.MAP
    
    self.grid = createGrid(C_MAP.CITY_GRID_WIDTH, C_MAP.CITY_GRID_HEIGHT, "grass")
    
    local downtown_w = C_MAP.DOWNTOWN_GRID_WIDTH
    local downtown_h = C_MAP.DOWNTOWN_GRID_HEIGHT
    self.downtown_offset = {
        x = math.floor((C_MAP.CITY_GRID_WIDTH - downtown_w) / 2),
        y = math.floor((C_MAP.CITY_GRID_HEIGHT - downtown_h) / 2)
    }
    
    local downtown_district = {
        x = self.downtown_offset.x, y = self.downtown_offset.y,
        w = downtown_w, h = downtown_h
    }
    
    require("game.generators.downtown").generateDowntownModule(self.grid, downtown_district, C_MAP)
    print("Generated Downtown Core onto main grid...")

    local all_districts = Districts.generateAll(self.grid, C_MAP.CITY_GRID_WIDTH, C_MAP.CITY_GRID_HEIGHT, downtown_district)
    print("Generated districts and their internal roads using Districts module")

    local ring_road_nodes = RingRoad.generatePath(all_districts, C_MAP.CITY_GRID_WIDTH, C_MAP.CITY_GRID_HEIGHT)
    local ring_road_curve = {}
    if #ring_road_nodes > 0 then ring_road_curve = self:generateSplinePoints(ring_road_nodes, 10) end
    
    local ns_highway_paths = HighwayNS.generatePaths(C_MAP.CITY_GRID_WIDTH, C_MAP.CITY_GRID_HEIGHT, all_districts)
    local ew_highway_paths = HighwayEW.generatePaths(C_MAP.CITY_GRID_WIDTH, C_MAP.CITY_GRID_HEIGHT, all_districts)
    local all_highway_paths = {}
    for _, path in ipairs(ns_highway_paths) do table.insert(all_highway_paths, path) end
    for _, path in ipairs(ew_highway_paths) do table.insert(all_highway_paths, path) end

    local merged_highway_paths = HighwayMerger.applyMergingLogic(all_highway_paths, ring_road_curve)
    
    self:drawAllRoadsToGrid(self.grid, ring_road_curve, merged_highway_paths, {})
    print("Generated and drew highways.")
    
    local highway_points = self:extractHighwayPoints(ring_road_curve, merged_highway_paths)
    local connections = ConnectingRoads.generateConnections(self.grid, all_districts, highway_points, C_MAP.CITY_GRID_WIDTH, C_MAP.CITY_GRID_HEIGHT, Game)
    
    -- FIX: Pass the 'Game' object to drawConnections
    ConnectingRoads.drawConnections(self.grid, connections, Game)
    print("Generated and drew connecting roads.")
    
    self.building_plots = self:getPlotsFromGrid(self.grid)
    
    self.scale_grids = nil
    self.scale_building_plots = nil
    
    print("Unified map generation complete. Found " .. #self.building_plots .. " valid building plots.")
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
    local h, w = #grid, #grid[1]
    local plots = {}
    
    local MIN_NETWORK_SIZE = 10
    local visited_roads = {}
    local valid_road_tiles = {}

    for y = 1, h do
        for x = 1, w do
            local key = y .. "," .. x
            if self:isRoad(grid[y][x].type) and not visited_roads[key] then
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
                        if inBounds(nx, ny, w, h) and self:isRoad(grid[ny][nx].type) and not visited_roads[nkey] then
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
    if not self.C.MAP.SCALE_NAMES[new_scale] then return false end
    
    self.current_scale = new_scale
    
    local screen_w, screen_h = love.graphics.getDimensions()
    local game_world_w = screen_w - Game.C.UI.SIDEBAR_WIDTH
    
    if new_scale == self.C.MAP.SCALES.DOWNTOWN then
        -- FIX: Center the camera on the DOWNTOWN area, not the whole map.
        local downtown_center_x_grid = self.downtown_offset.x + (self.C.MAP.DOWNTOWN_GRID_WIDTH / 2)
        local downtown_center_y_grid = self.downtown_offset.y + (self.C.MAP.DOWNTOWN_GRID_HEIGHT / 2)
        
        Game.camera.x, Game.camera.y = self:getPixelCoords(downtown_center_x_grid, downtown_center_y_grid)
        Game.camera.scale = 16 / self.C.MAP.TILE_SIZE
        
    else -- City view
        local city_center_x_grid = self.C.MAP.CITY_GRID_WIDTH / 2
        local city_center_y_grid = self.C.MAP.CITY_GRID_HEIGHT / 2
        Game.camera.x, Game.camera.y = self:getPixelCoords(city_center_x_grid, city_center_y_grid)
        
        local total_map_width_pixels = self.C.MAP.CITY_GRID_WIDTH * self.C.MAP.TILE_SIZE
        Game.camera.scale = game_world_w / total_map_width_pixels
    end
    
    if Game and Game.EventBus then
        Game.EventBus:publish("map_scale_changed")
    end
    
    print("Set camera view to", self.C.MAP.SCALE_NAMES[self.current_scale])
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
    -- With a single grid, drawing is simple. We just draw the one grid.
    -- The visual "zoom" effect will be handled by the camera transforms in main.lua
    self:drawGrid(self.grid, 1)
    love.graphics.setColor(1, 1, 1, 1)
end

function Map:drawGrid(grid, alpha)
    local C_MAP = self.C.MAP
    if not grid or #grid == 0 then return end
    
    local grid_h, grid_w = #grid, #grid[1]
    
    -- FIX: The tile size should ALWAYS be the base size from constants.
    -- The camera's scale will handle making it look bigger or smaller.
    local tile_size = C_MAP.TILE_SIZE
    
    local dt_x_min = self.downtown_offset.x
    local dt_y_min = self.downtown_offset.y
    local dt_x_max = self.downtown_offset.x + self.C.MAP.DOWNTOWN_GRID_WIDTH
    local dt_y_max = self.downtown_offset.y + self.C.MAP.DOWNTOWN_GRID_HEIGHT

    for y = 1, grid_h do 
        for x = 1, grid_w do
            local tile = grid[y][x]
            local is_in_downtown = (x >= dt_x_min and x < dt_x_max and y >= dt_y_min and y < dt_y_max)
            
            local color
            if is_in_downtown then
                if self:isRoad(tile.type) then
                    color = C_MAP.COLORS.DOWNTOWN_ROAD
                else
                    color = C_MAP.COLORS.DOWNTOWN_PLOT
                end
            else
                if self:isRoad(tile.type) then
                    color = C_MAP.COLORS.ROAD
                elseif tile.type == "grass" then 
                    color = C_MAP.COLORS.GRASS 
                else
                    color = C_MAP.COLORS.PLOT
                end
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
    -- DEPRECATED: With a single grid, this is identical to the main function.
    -- For backward compatibility, we just call the main function.
    return self:findNearestRoadTile(plot)
end

function Map:getRandomCityBuildingPlot()
    local city_plots = {}
    local x_min = self.downtown_offset.x
    local y_min = self.downtown_offset.y
    local x_max = self.downtown_offset.x + self.C.MAP.DOWNTOWN_GRID_WIDTH
    local y_max = self.downtown_offset.y + self.C.MAP.DOWNTOWN_GRID_HEIGHT

    for _, plot in ipairs(self.building_plots) do
        if not (plot.x >= x_min and plot.x < x_max and plot.y >= y_min and plot.y < y_max) then
            table.insert(city_plots, plot)
        end
    end

    if #city_plots > 0 then
        return city_plots[love.math.random(1, #city_plots)]
    end

    return self:getRandomBuildingPlot() -- Fallback
end

function Map:getCityCoordsFromDowntownPlot(downtown_plot)
    if not downtown_plot or not self.downtown_offset then
        return nil
    end
    return {
        x = self.downtown_offset.x + downtown_plot.x,
        y = self.downtown_offset.y + downtown_plot.y
    }
end

function Map:getRandomDowntownBuildingPlot()
    local downtown_plots = {}
    local x_min = self.downtown_offset.x
    local y_min = self.downtown_offset.y
    local x_max = self.downtown_offset.x + self.C.MAP.DOWNTOWN_GRID_WIDTH
    local y_max = self.downtown_offset.y + self.C.MAP.DOWNTOWN_GRID_HEIGHT

    for _, plot in ipairs(self.building_plots) do
        if plot.x >= x_min and plot.x < x_max and plot.y >= y_min and plot.y < y_max then
            table.insert(downtown_plots, plot)
        end
    end

    if #downtown_plots > 0 then
        return downtown_plots[love.math.random(1, #downtown_plots)]
    end
    
    return self:getRandomBuildingPlot() -- Fallback to any plot if none are found
end

function Map:getCurrentScale() 
    return self.current_scale 
end

function Map:getScaleName() 
    return self.C.MAP.SCALE_NAMES[self.current_scale] or "Unknown Scale" 
end

function Map:findNearestRoadTile(plot)
    if not plot then return nil end
    
    local grid = self.grid 
    if not grid or #grid == 0 then return nil end
    
    local grid_h, grid_w = #grid, #grid[1]
    local x, y = plot.x, plot.y
    
    for r = 0, 5 do -- Increased search radius slightly to be more robust
        for dy = -r, r do 
            for dx = -r, r do 
                if math.abs(dx) == r or math.abs(dy) == r then
                    local nx, ny = x + dx, y + dy
                    if inBounds(nx, ny, grid_w, grid_h) then 
                        -- FIX: This must call self:isRoad, not the old global function.
                        if self:isRoad(grid[ny][nx].type) then 
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
    -- This function now always returns the world coordinate based on the single, fundamental tile size.
    local TILE_SIZE = self.C.MAP.TILE_SIZE
    return (grid_x - 0.5) * TILE_SIZE, (grid_y - 0.5) * TILE_SIZE
end

function Map:getDowntownPixelCoords(grid_x, grid_y)
    -- This function's complex logic is no longer needed with a single camera/viewport system.
    -- We now just use the main getPixelCoords function, as all coordinates are global.
    return self:getPixelCoords(grid_x, grid_y)
end

function Map:getCurrentTileSize()
    -- FIX: Determine tile size based on the current visual scale, not grid dimensions.
    if self.current_scale == self.C.MAP.SCALES.DOWNTOWN then
        return 16
    else
        return self.C.MAP.TILE_SIZE
    end
end

function Map:isPlotInDowntown(plot)
    if not plot or not self.downtown_offset then return false end

    local x_min = self.downtown_offset.x
    local y_min = self.downtown_offset.y
    local x_max = self.downtown_offset.x + self.C.MAP.DOWNTOWN_GRID_WIDTH
    local y_max = self.downtown_offset.y + self.C.MAP.DOWNTOWN_GRID_HEIGHT

    return plot.x >= x_min and plot.x < x_max and plot.y >= y_min and plot.y < y_max
end


return Map