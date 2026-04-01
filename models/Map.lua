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
    instance.downtown_grid_width  = C.MAP.DOWNTOWN_GRID_WIDTH
    instance.downtown_grid_height = C.MAP.DOWNTOWN_GRID_HEIGHT
    instance.city_grid_width      = C.MAP.CITY_GRID_WIDTH
    instance.city_grid_height     = C.MAP.CITY_GRID_HEIGHT
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
-- == UTILITY & HELPER FUNCTIONS
-- =============================================================================

function Map:isRoad(tile_type)
    return tile_type == "road" or
           tile_type == "downtown_road" or
           tile_type == "arterial" or
           tile_type == "highway"
end

local TilePalette  = require("data.tile_palette")
local GridSearch   = require("lib.grid_search")
local function getTileColor(tile_type, is_in_downtown, C_MAP)
    local entry = TilePalette[tile_type] or TilePalette.default
    local key = is_in_downtown and entry.downtown or entry.city
    return C_MAP.COLORS[key]
end

function Map:getPlotsFromGrid(grid)
    if not grid or #grid == 0 then return {} end
    local h, w = #grid, #grid[1]
    local plots = {}

    local MIN_NETWORK_SIZE = require("data.GameplayConfig").MIN_NETWORK_SIZE
    local road_visited = {}
    local valid_road_tiles = {}

    local function inBounds(x, y) return x >= 1 and x <= w and y >= 1 and y <= h end

    for y = 1, h do
        for x = 1, w do
            local key = y .. "," .. x
            if self:isRoad(grid[y][x].type) and not road_visited[key] then
                local network = GridSearch.floodFill(grid, x, y, function(nx, ny)
                    return self:isRoad(grid[ny][nx].type)
                end)
                for _, t in ipairs(network) do
                    road_visited[t.y .. "," .. t.x] = true
                end
                if #network >= MIN_NETWORK_SIZE then
                    for _, t in ipairs(network) do
                        valid_road_tiles[#valid_road_tiles+1] = t
                    end
                end
            end
        end
    end

    local visited_plots = {}
    for _, road_tile in ipairs(valid_road_tiles) do
        for _, d in ipairs({{0,-1},{0,1},{-1,0},{1,0}}) do
            local px, py = road_tile.x+d[1], road_tile.y+d[2]
            local pkey = py .. "," .. px
            if inBounds(px, py) and (grid[py][px].type == "plot" or grid[py][px].type == "downtown_plot") and not visited_plots[pkey] then
                plots[#plots+1] = {x=px, y=py}
                visited_plots[pkey] = true
            end
        end
    end

    return plots
end

-- =============================================================================
-- == MAP STATE MANAGEMENT & RENDERING
-- =============================================================================

function Map:setScale(new_scale, game)
    if not self.C.MAP.SCALE_NAMES[new_scale] then return false end

    game.state.current_map_scale = new_scale

    if game.EventBus then
        local cam
        if game.world_gen_cam_params and game.world_gen_cam_params[new_scale] then
            cam = game.world_gen_cam_params[new_scale]
        else
            cam = { x = 0, y = 0, scale = 1 }
        end
        game.EventBus:publish("map_scale_changed", { camera = cam, active_map_key = "city" })
    end

    print("Set camera view to", self.C.MAP.SCALE_NAMES[new_scale] or "Unknown Scale")
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

            if game and game.EventBus then
                game.EventBus:publish("map_scale_changed")
            end

            print("Transition complete - now at", self.C.MAP.SCALE_NAMES[self.current_scale])
        end
    end
end

function Map:draw()
    self:drawGrid(self.grid, 1)
    love.graphics.setColor(1, 1, 1, 1)
end

-- Draws only road-type tiles (for overlaying on top of a background image).
function Map:drawRoads()
    local C_MAP = self.C.MAP
    if not self.grid or #self.grid == 0 then return end
    local tile_size = self.tile_pixel_size or C_MAP.TILE_SIZE
    local road_color     = C_MAP.COLORS.ROAD
    local dt_road_color  = C_MAP.COLORS.DOWNTOWN_ROAD
    local art_color      = C_MAP.COLORS.ARTERIAL
    for y = 1, #self.grid do
        local row = self.grid[y]
        for x = 1, #row do
            local t = row[x].type
            local c
            if t == "road" then
                c = road_color
            elseif t == "downtown_road" then
                c = dt_road_color
            elseif t == "arterial" then
                c = art_color
            elseif t == "highway" then
                c = C_MAP.COLORS.ROAD  -- draw highways too so they're visible
            end
            if c then
                love.graphics.setColor(c[1], c[2], c[3], 1)
                love.graphics.rectangle("fill", (x-1)*tile_size, (y-1)*tile_size, tile_size, tile_size)
            end
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function Map:drawGrid(grid, alpha)
    local C_MAP = self.C.MAP
    if not grid or #grid == 0 then return end
    
    local grid_h, grid_w = #grid, #grid[1]
    local tile_size = self.tile_pixel_size or C_MAP.TILE_SIZE
    
    local dt_x_min = self.downtown_offset.x
    local dt_y_min = self.downtown_offset.y
    local dt_x_max = self.downtown_offset.x + self.downtown_grid_width
    local dt_y_max = self.downtown_offset.y + self.downtown_grid_height

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

function Map:pixelToGrid(pixel_x, pixel_y)
    local TILE_SIZE = self.C.MAP.TILE_SIZE
    return math.floor(pixel_x / TILE_SIZE + 0.5), math.floor(pixel_y / TILE_SIZE + 0.5)
end

function Map:getRandomCityBuildingPlot()
    local city_plots = {}
    local x_min = self.downtown_offset.x
    local y_min = self.downtown_offset.y
    local x_max = self.downtown_offset.x + self.downtown_grid_width
    local y_max = self.downtown_offset.y + self.downtown_grid_height

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
    local x_max = self.downtown_offset.x + self.downtown_grid_width
    local y_max = self.downtown_offset.y + self.downtown_grid_height
    local grid = self.grid
    local gh = grid and #grid or 0
    local gw = gh > 0 and #grid[1] or 0

    for _, plot in ipairs(self.building_plots) do
        if plot.x >= x_min and plot.x < x_max and plot.y >= y_min and plot.y < y_max then
            local t = grid and grid[plot.y] and grid[plot.y][plot.x] and grid[plot.y][plot.x].type
            if t == "downtown_plot" then
                for _, d in ipairs({{0,-1},{0,1},{-1,0},{1,0}}) do
                    local nx, ny = plot.x+d[1], plot.y+d[2]
                    if nx>=1 and nx<=gw and ny>=1 and ny<=gh
                       and grid[ny][nx] and self:isRoad(grid[ny][nx].type) then
                        table.insert(downtown_plots, plot)
                        break
                    end
                end
            end
        end
    end

    if #downtown_plots > 0 then
        return downtown_plots[love.math.random(1, #downtown_plots)]
    end
    -- Road-node maps: city streets are no longer road tiles, so isRoad check finds nothing.
    -- Fall back to any downtown_plot in building_plots within downtown bounds.
    if self.building_plots then
        local fallback = {}
        for _, plot in ipairs(self.building_plots) do
            if plot.x >= x_min and plot.x < x_max and plot.y >= y_min and plot.y < y_max then
                local t = grid and grid[plot.y] and grid[plot.y][plot.x] and grid[plot.y][plot.x].type
                if t == "downtown_plot" then
                    table.insert(fallback, plot)
                end
            end
        end
        if #fallback > 0 then
            return fallback[love.math.random(1, #fallback)]
        end
    end
    return nil
end

function Map:getScaleName(game)
    local scale = game and game.state.current_map_scale or self.current_scale
    return self.C.MAP.SCALE_NAMES[scale] or "Unknown Scale"
end

function Map:findNearestRoadTile(plot)
    if not plot then return nil end
    local grid = self.grid
    if not grid or #grid == 0 then return nil end
    local grid_h, grid_w = #grid, #grid[1]
    local x, y = plot.x, plot.y
    local function inBounds(gx, gy) return gx>=1 and gx<=grid_w and gy>=1 and gy<=grid_h end

    -- 4-directional BFS so Manhattan-nearest road tile is always returned first.
    -- This avoids the diagonal bias of the old Chebyshev spiral (which always found
    -- corner intersections before orthogonally-adjacent road tiles).
    local visited = {[y*10000+x] = true}
    local q = {{x, y}}
    local qi = 1
    while qi <= #q do
        local cx, cy = q[qi][1], q[qi][2]; qi = qi + 1
        if (cx ~= x or cy ~= y) and inBounds(cx, cy) and self:isRoad(grid[cy][cx].type) then
            return {x=cx, y=cy}
        end
        for _, d in ipairs({{0,-1},{0,1},{-1,0},{1,0}}) do
            local nx, ny = cx+d[1], cy+d[2]
            local k = ny*10000+nx
            if inBounds(nx, ny) and not visited[k] then
                visited[k] = true
                q[#q+1] = {nx, ny}
            end
        end
        if qi > 1000 then break end  -- safety cap
    end
    return nil
end

-- Finds the nearest road-node (rx, ry) to the given sub-cell plot.
-- Road nodes are the lines between sub-cells: rx = gx-1, ry = gy-1,
-- pixel position = (rx*tps, ry*tps).  Only valid on road-node maps (road_nodes set).
function Map:findNearestRoadNode(plot)
    if not plot or not self.road_nodes then return nil end
    local gw = self.grid and #self.grid[1] or 0
    local gh = self.grid and #self.grid or 0
    -- Check all 4 corners of the plot sub-cell first (matches PathfindingService logic).
    local gx, gy = plot.x, plot.y
    for _, c in ipairs({{gx-1,gy-1},{gx,gy-1},{gx-1,gy},{gx,gy}}) do
        local rx, ry = c[1], c[2]
        if rx >= 0 and ry >= 0 and rx < gw and ry < gh then
            if self.road_nodes[ry] and self.road_nodes[ry][rx] then
                return {x = rx, y = ry}
            end
        end
    end
    local rx, ry = gx - 1, gy - 1
    local visited = {[ry * 10000 + rx] = true}
    local q = {{rx, ry}}
    local qi = 1
    while qi <= #q do
        local crx, cry = q[qi][1], q[qi][2]; qi = qi + 1
        if self.road_nodes[cry] and self.road_nodes[cry][crx] then
            return {x = crx, y = cry}
        end
        for _, d in ipairs({{0,-1},{0,1},{-1,0},{1,0}}) do
            local nrx, nry = crx + d[1], cry + d[2]
            local k = nry * 10000 + nrx
            if nrx >= 0 and nrx < gw and nry >= 0 and nry < gh and not visited[k] then
                visited[k] = true; q[#q + 1] = {nrx, nry}
            end
        end
        if qi > 1000 then break end
    end
    return nil
end

function Map:getRandomBuildingPlot()
    local road_adjacent = {}
    local grid = self.grid
    local gh = grid and #grid or 0
    local gw = gh > 0 and #grid[1] or 0
    for _, plot in ipairs(self.building_plots) do
        for _, d in ipairs({{0,-1},{0,1},{-1,0},{1,0}}) do
            local nx, ny = plot.x+d[1], plot.y+d[2]
            if nx>=1 and nx<=gw and ny>=1 and ny<=gh
               and grid[ny][nx] and self:isRoad(grid[ny][nx].type) then
                table.insert(road_adjacent, plot)
                break
            end
        end
    end
    if #road_adjacent > 0 then
        return road_adjacent[love.math.random(1, #road_adjacent)]
    end
    -- Road-node maps: city streets are no longer road tiles, so isRoad check finds nothing.
    -- building_plots are already guaranteed road-line adjacent by construction.
    if self.building_plots and #self.building_plots > 0 then
        return self.building_plots[love.math.random(1, #self.building_plots)]
    end
    return nil
end

function Map:getPixelCoords(grid_x, grid_y)
    local tps = self.tile_pixel_size or self.C.MAP.TILE_SIZE
    return (grid_x - 0.5) * tps, (grid_y - 0.5) * tps
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
    local x_max = self.downtown_offset.x + self.downtown_grid_width
    local y_max = self.downtown_offset.y + self.downtown_grid_height

    return plot.x >= x_min and plot.x < x_max and plot.y >= y_min and plot.y < y_max
end

function Map:getCityDataForPlot(plot)
    if not self.cities_data then return nil end

    for _, city_data in ipairs(self.cities_data) do
        local city_w = self.city_grid_width
        local city_h = self.city_grid_height
        local city_x_min = city_data.center_x - (city_w / 2)
        local city_y_min = city_data.center_y - (city_h / 2)
        
        if plot.x >= city_x_min and plot.x < city_x_min + city_w and
           plot.y >= city_y_min and plot.y < city_y_min + city_h then
            return city_data
        end
    end
    return nil
end

return Map