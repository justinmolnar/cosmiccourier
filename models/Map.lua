-- game/map.lua (Refactored for modular generation)
local Map = {}
Map.__index = Map

function Map:new(C)
    local instance = setmetatable({}, Map)
    instance.C = C
    instance.grid = {}
    instance.building_plots = {}
    instance.current_scale = C.MAP.SCALES.DOWNTOWN
    instance.downtown_offset = {x = 0, y = 0}
    instance.transition_state = { 
        active = false, 
        timer = 0, 
        duration = C.ZOOM.TRANSITION_DURATION, 
        from_scale = 1, 
        to_scale = 1, 
        progress = 0 
    }
    instance.debug_params = nil
    return instance
end

-- =============================================================================
-- == MASTER GENERATION FUNCTION (Now delegates to the service)
-- =============================================================================
function Map:generate()
    local MapGenerationService = require("services.MapGenerationService")
    MapGenerationService.generateMap(self)
end

-- =============================================================================
-- == UTILITY & HELPER FUNCTIONS
-- =============================================================================

function Map:isRoad(tile_type)
    return tile_type == "road" or
           tile_type == "downtown_road" or
           tile_type == "arterial" or
           tile_type == "highway" or
           tile_type == "highway_ring" or
           tile_type == "highway_ns" or
           tile_type == "highway_ew"
end

local function getTileColor(tile_type, is_in_downtown, C_MAP)
    if is_in_downtown then
        if tile_type == "road" or tile_type == "downtown_road" or 
           tile_type == "arterial" or tile_type == "highway" or 
           tile_type == "highway_ring" or tile_type == "highway_ns" or 
           tile_type == "highway_ew" then
            return C_MAP.COLORS.DOWNTOWN_ROAD
        else
            return C_MAP.COLORS.DOWNTOWN_PLOT
        end
    else
        if tile_type == "road" or tile_type == "downtown_road" or 
           tile_type == "arterial" or tile_type == "highway" or 
           tile_type == "highway_ring" or tile_type == "highway_ns" or 
           tile_type == "highway_ew" then
            return C_MAP.COLORS.ROAD
        elseif tile_type == "grass" then 
            return C_MAP.COLORS.GRASS 
        else
            return C_MAP.COLORS.PLOT
        end
    end
end

function Map:getPlotsFromGrid(grid)
    if not grid or #grid == 0 then return {} end
    local h, w = #grid, #grid[1]
    local plots = {}
    
    local MIN_NETWORK_SIZE = 10
    local visited_roads = {}
    local valid_road_tiles = {}

    local function inBounds(x, y)
        return x >= 1 and x <= w and y >= 1 and y <= h
    end

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
                        if inBounds(nx, ny) and self:isRoad(grid[ny][nx].type) and not visited_roads[nkey] then
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
            if inBounds(px, py) and (grid[py][px].type == 'plot' or grid[py][px].type == 'downtown_plot') and not visited_plots[pkey] then
                table.insert(plots, {x=px, y=py})
                visited_plots[pkey] = true
            end
        end
    end
    
    return plots
end

-- =============================================================================
-- == MAP STATE MANAGEMENT & RENDERING
-- =============================================================================

function Map:setScale(new_scale)
    if not self.C.MAP.SCALE_NAMES[new_scale] then return false end

    -- Get the map instance that corresponds to the new scale
    local target_map_key = (new_scale == self.C.MAP.SCALES.REGION) and "region" or "city"
    local target_map = Game.maps[target_map_key]
    Game.active_map_key = target_map_key
    
    -- MODIFIED: Set the single source of truth for the game's scale
    Game.state.current_map_scale = new_scale
    
    local screen_w, screen_h = love.graphics.getDimensions()
    local game_world_w = screen_w - (Game and Game.C.UI.SIDEBAR_WIDTH or 280)
    
    if new_scale == self.C.MAP.SCALES.DOWNTOWN then
        local downtown_center_x_grid = self.downtown_offset.x + (self.C.MAP.DOWNTOWN_GRID_WIDTH / 2)
        local downtown_center_y_grid = self.downtown_offset.y + (self.C.MAP.DOWNTOWN_GRID_HEIGHT / 2)
        
        Game.camera.x, Game.camera.y = self:getPixelCoords(downtown_center_x_grid, downtown_center_y_grid)
        Game.camera.scale = 16 / self.C.MAP.TILE_SIZE
        
    elseif new_scale == self.C.MAP.SCALES.CITY then
        local city_center_x_grid = self.C.MAP.CITY_GRID_WIDTH / 2
        local city_center_y_grid = self.C.MAP.CITY_GRID_HEIGHT / 2
        Game.camera.x, Game.camera.y = self:getPixelCoords(city_center_x_grid, city_center_y_grid)
        
        local total_map_width_pixels = self.C.MAP.CITY_GRID_WIDTH * self.C.MAP.TILE_SIZE
        Game.camera.scale = game_world_w / total_map_width_pixels

    elseif new_scale == self.C.MAP.SCALES.REGION then
        if #target_map.grid == 0 then
            target_map.grid = require("services.MapGenerationService")._createGrid(self.C.MAP.REGION_GRID_WIDTH, self.C.MAP.REGION_GRID_HEIGHT, "grass")
        end
        
        local region_center_x_grid = self.C.MAP.REGION_GRID_WIDTH / 2
        local region_center_y_grid = self.C.MAP.REGION_GRID_HEIGHT / 2
        Game.camera.x, Game.camera.y = target_map:getPixelCoords(region_center_x_grid, region_center_y_grid)
        
        local total_map_width_pixels = self.C.MAP.REGION_GRID_WIDTH * self.C.MAP.TILE_SIZE
        Game.camera.scale = game_world_w / total_map_width_pixels
    end
    
    if Game and Game.EventBus then
        Game.EventBus:publish("map_scale_changed")
    end
    
    print("Set camera view to", self.C.MAP.SCALE_NAMES[Game.state.current_map_scale])
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
            
            if Game and Game.EventBus then
                Game.EventBus:publish("map_scale_changed")
            end
            
            print("Transition complete - now at", self.C.MAP.SCALE_NAMES[self.current_scale])
        end
    end
end

function Map:draw()
    self:drawGrid(self.grid, 1)
    love.graphics.setColor(1, 1, 1, 1)
end

function Map:drawGrid(grid, alpha)
    local C_MAP = self.C.MAP
    if not grid or #grid == 0 then return end
    
    local grid_h, grid_w = #grid, #grid[1]
    local tile_size = C_MAP.TILE_SIZE
    
    local dt_x_min = self.downtown_offset.x
    local dt_y_min = self.downtown_offset.y
    local dt_x_max = self.downtown_offset.x + self.C.MAP.DOWNTOWN_GRID_WIDTH
    local dt_y_max = self.downtown_offset.y + self.C.MAP.DOWNTOWN_GRID_HEIGHT

    for y = 1, grid_h do 
        for x = 1, grid_w do
            local tile = grid[y][x]
            local is_in_downtown = (x >= dt_x_min and x < dt_x_max and y >= dt_y_min and y < dt_y_max)
            
            local color = getTileColor(tile.type, is_in_downtown, C_MAP)
            
            love.graphics.setColor(color[1], color[2], color[3], alpha or 1)
            love.graphics.rectangle("fill", (x-1) * tile_size, (y-1) * tile_size, tile_size, tile_size)
        end 
    end
end

-- =============================================================================
-- == PUBLIC API METHODS
-- =============================================================================

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

function Map:getScaleName() 
    -- MODIFIED: Read the scale from the global game state to ensure it's always correct.
    return self.C.MAP.SCALE_NAMES[Game.state.current_map_scale] or "Unknown Scale" 
end

function Map:findNearestRoadTile(plot)
    if not plot then return nil end
    
    local grid = self.grid 
    if not grid or #grid == 0 then return nil end
    
    local grid_h, grid_w = #grid, #grid[1]
    local x, y = plot.x, plot.y

    local function inBounds(gx, gy)
        return gx >= 1 and gx <= grid_w and gy >= 1 and gy <= grid_h
    end
    
    for r = 0, 5 do -- Increased search radius
        for dy = -r, r do 
            for dx = -r, r do 
                if math.abs(dx) == r or math.abs(dy) == r then
                    local nx, ny = x + dx, y + dy
                    if inBounds(nx, ny) and self:isRoad(grid[ny][nx].type) then 
                        return {x = nx, y = ny} 
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
    local TILE_SIZE = self.C.MAP.TILE_SIZE
    return (grid_x - 0.5) * TILE_SIZE, (grid_y - 0.5) * TILE_SIZE
end

function Map:getCurrentTileSize()
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