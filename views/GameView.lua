-- views/GameView.lua
-- FIXED: Added proper handling for WFC lab grid to prevent crashes
-- MODIFIED: Added require statements for Bike and Truck models
local Bike = require("models.vehicles.Bike")
local Truck = require("models.vehicles.Truck")

local GameView = {}
GameView.__index = GameView

function GameView:new(game_instance)
    local instance = setmetatable({}, GameView)
    instance.Game = game_instance
    return instance
end

function GameView:draw()
    local Game = self.Game
    local ui_manager = Game.ui_manager
    local sidebar_w = Game.C.UI.SIDEBAR_WIDTH
    local screen_w, screen_h = love.graphics.getDimensions()
    local DrawingUtils = require("utils.DrawingUtils")

    local active_map = Game.maps[Game.active_map_key]
    if not active_map then return end 

    love.graphics.setScissor(sidebar_w, 0, screen_w - sidebar_w, screen_h)

    if Game.lab_grid then
        love.graphics.push()
        love.graphics.translate(sidebar_w, 0)
        self:drawLabGrid()
        love.graphics.pop()
    else
        love.graphics.push()

        local game_world_w = screen_w - sidebar_w
        love.graphics.translate(sidebar_w + game_world_w / 2, screen_h / 2)
        love.graphics.scale(Game.camera.scale, Game.camera.scale)
        love.graphics.translate(-Game.camera.x, -Game.camera.y)
        
        active_map:draw()

        if Game.active_map_key == "city" then
            if Game.entities.depot_plot then
                local depot_px, depot_py = active_map:getPixelCoords(Game.entities.depot_plot.x, Game.entities.depot_plot.y)
                DrawingUtils.drawWorldIcon(Game, "🏢", depot_px, depot_py)
            end

            for _, client in ipairs(Game.entities.clients) do
                DrawingUtils.drawWorldIcon(Game, "🏠", client.px, client.py)
            end
            
            Game.event_spawner:draw(Game)
        end

        for _, vehicle in ipairs(Game.entities.vehicles) do
            if vehicle.visible then
                vehicle:draw(Game)
            end
        end

        if Game.active_map_key == "city" and ui_manager.hovered_trip_index then
            local trip = Game.entities.trips.pending[ui_manager.hovered_trip_index]
            if trip and trip.legs[trip.current_leg] then
                local leg = trip.legs[trip.current_leg]
                local path_grid = active_map.grid
                local start_node = (leg.vehicleType == "truck" and trip.current_leg > 1) and active_map:findNearestRoadTile(Game.entities.depot_plot) or active_map:findNearestRoadTile(leg.start_plot)
                local end_node = active_map:findNearestRoadTile(leg.end_plot)
                if start_node and end_node and path_grid then
                    -- THE FIX: Reference the new, centralized vehicle properties in the constants file
                    local required_vehicle_properties = (leg.vehicleType == "bike") and Game.C.VEHICLES.BIKE or Game.C.VEHICLES.TRUCK
                    
                    local cost_function = function(x, y)
                        local tile = path_grid[y] and path_grid[y][x]
                        if tile then
                            return required_vehicle_properties.pathfinding_costs[tile.type] or 9999
                        end
                        return 9999
                    end

                    local path = Game.pathfinder.findPath(path_grid, start_node, end_node, cost_function, active_map)
                    
                    if path then
                        local pixel_path = {}
                        for _, node in ipairs(path) do
                            local px, py = active_map:getPixelCoords(node.x, node.y)
                            table.insert(pixel_path, px)
                            table.insert(pixel_path, py)
                        end
                        local hover_color = Game.C.MAP.COLORS.HOVER
                        love.graphics.setColor(hover_color[1], hover_color[2], hover_color[3], 0.7)
                        love.graphics.setLineWidth(3 / Game.camera.scale)
                        love.graphics.line(pixel_path)
                        love.graphics.setLineWidth(1)
                        local circle_radius = 5 / Game.camera.scale
                        love.graphics.setColor(hover_color)
                        love.graphics.circle("fill", pixel_path[1], pixel_path[2], circle_radius)
                        love.graphics.circle("fill", pixel_path[#pixel_path-1], pixel_path[#pixel_path], circle_radius)
                    end
                end
            end
        end

        if Game.debug_mode then
            for _, vehicle in ipairs(Game.entities.vehicles) do
                if vehicle.visible then
                    vehicle:drawDebug(Game)
                end
            end
        end

        love.graphics.pop()
    end
    
    love.graphics.setScissor()
end

function GameView:drawLabGrid()
    local Game = self.Game
    
    -- Check if we have the final WFC result to draw
    if Game.wfc_final_grid and Game.wfc_road_data then
        self:drawFinalWfcCity()
        return
    end

    -- Fallback to drawing the intermediate steps if the final grid doesn't exist yet
    if not Game.lab_grid then return end
    local grid = Game.lab_grid
    if not grid or #grid == 0 or not grid[1] then return end
    
    local grid_h, grid_w = #grid, #grid[1]
    local screen_w, screen_h = love.graphics.getDimensions()
    local sidebar_w = Game.C.UI.SIDEBAR_WIDTH
    local available_w, available_h = screen_w - sidebar_w, screen_h
    
    local tile_size_w = math.floor(available_w * 0.9 / grid_w)
    local tile_size_h = math.floor(available_h * 0.9 / grid_h)
    local tile_size = math.max(6, math.min(tile_size_w, tile_size_h, 25))
    
    local total_grid_w, total_grid_h = grid_w * tile_size, grid_h * tile_size
    local offset_x, offset_y = (available_w - total_grid_w) / 2, (available_h - total_grid_h) / 2
    
    love.graphics.setColor(0.1, 0.1, 0.1, 0.8)
    love.graphics.rectangle("fill", offset_x - 10, offset_y - 40, total_grid_w + 20, total_grid_h + 50)
    
    for y = 1, grid_h do
        for x = 1, grid_w do
            if grid[y] and grid[y][x] and grid[y][x].type then
                local color = self:getTileColor(grid[y][x].type)
                love.graphics.setColor(color)
                love.graphics.rectangle("fill", offset_x + (x-1)*tile_size, offset_y + (y-1)*tile_size, tile_size, tile_size)
            end
        end
    end
    
    if Game.show_districts and Game.lab_zone_grid then
        self:drawZoneOverlay(offset_x, offset_y, tile_size)
    end
    
    if Game.smooth_highway_overlay_paths and #Game.smooth_highway_overlay_paths > 0 then
        love.graphics.setLineWidth(5)
        love.graphics.setColor(1, 0.5, 0.7, 0.8)
        for _, spline_path in ipairs(Game.smooth_highway_overlay_paths) do
            local pixel_path = {}
            if #spline_path > 1 then
                for _, node in ipairs(spline_path) do
                    table.insert(pixel_path, offset_x + (node.x - 1) * tile_size + (tile_size / 2))
                    table.insert(pixel_path, offset_y + (node.y - 1) * tile_size + (tile_size / 2))
                end
                love.graphics.line(pixel_path)
            end
        end
        love.graphics.setLineWidth(1)
    end

    love.graphics.setColor(1, 1, 1)
    love.graphics.setFont(Game.fonts.ui)
    love.graphics.print("WFC Lab Grid - Press 'U' to generate final city", offset_x, offset_y - 35)
end

function GameView:drawFinalWfcCity()
    local Game = self.Game
    local grid = Game.wfc_final_grid
    local roads = Game.wfc_road_data
    if not grid or not roads then return end

    local grid_h, grid_w = #grid, #grid[1]
    local screen_w, screen_h = love.graphics.getDimensions()
    local sidebar_w = Game.C.UI.SIDEBAR_WIDTH
    local available_w, available_h = screen_w - sidebar_w, screen_h

    local tile_size_w = math.floor(available_w * 0.9 / grid_w)
    local tile_size_h = math.floor(available_h * 0.9 / grid_h)
    local tile_size = math.max(4, math.min(tile_size_w, tile_size_h, 25))
    
    local total_grid_w, total_grid_h = grid_w * tile_size, grid_h * tile_size
    local offset_x, offset_y = (available_w - total_grid_w) / 2, (available_h - total_grid_h) / 2
    
    -- Draw the zoned blocks
    for y = 1, grid_h do
        for x = 1, grid_w do
            local cell = grid[y][x]
            if cell and cell.zone then
                local color = self:getZoneColor(cell.zone)
                love.graphics.setColor(color)
                love.graphics.rectangle("fill", offset_x + (x-1)*tile_size, offset_y + (y-1)*tile_size, tile_size, tile_size)
            end
        end
    end

    -- Draw the local WFC roads on top
    love.graphics.setColor(0.2, 0.2, 0.2, 0.9) -- Slightly darker, more visible roads
    love.graphics.setLineWidth(math.max(1, math.floor(tile_size / 5)))
    
    for _, road in ipairs(roads) do
        local x1 = offset_x + road.x1 * tile_size
        local y1 = offset_y + road.y1 * tile_size
        local x2 = offset_x + road.x2 * tile_size
        local y2 = offset_y + road.y2 * tile_size
        love.graphics.line(x1, y1, x2, y2)
    end

    -- MODIFICATION: Draw the arterial roads as a final overlay
    if Game.arterial_control_paths and #Game.arterial_control_paths > 0 then
        love.graphics.setLineWidth(math.max(2, math.floor(tile_size / 3))) -- Arteries are thicker
        love.graphics.setColor(0.1, 0.1, 0.1, 0.6) -- Dark, semi-transparent color for arteries
        
        for _, path in ipairs(Game.arterial_control_paths) do
            local pixel_path = {}
            if #path > 1 then
                for i = 1, #path - 1 do
                    -- Draw a line segment between each node in the arterial path
                    local node1 = path[i]
                    local node2 = path[i+1]
                    local p1x = offset_x + (node1.x - 0.5) * tile_size
                    local p1y = offset_y + (node1.y - 0.5) * tile_size
                    local p2x = offset_x + (node2.x - 0.5) * tile_size
                    local p2y = offset_y + (node2.y - 0.5) * tile_size
                    love.graphics.line(p1x, p1y, p2x, p2y)
                end
            end
        end
    end
    
    love.graphics.setLineWidth(1)
end


-- FIXED: Update zone overlay to use the same positioning
function GameView:drawZoneOverlay(offset_x, offset_y, tile_size)
    local Game = self.Game
    
    if not Game.lab_zone_grid then return end
    
    local zone_grid = Game.lab_zone_grid
    local grid_h, grid_w = #zone_grid, #zone_grid[1]
    
    -- Draw semi-transparent zone colors
    for y = 1, grid_h do
        for x = 1, grid_w do
            if zone_grid[y] and zone_grid[y][x] then
                local zone = zone_grid[y][x]
                local zone_color = self:getZoneColor(zone)
                
                love.graphics.setColor(zone_color[1], zone_color[2], zone_color[3], 0.4)
                love.graphics.rectangle("fill", 
                    offset_x + (x-1) * tile_size + 1, 
                    offset_y + (y-1) * tile_size + 1, 
                    tile_size - 2, 
                    tile_size - 2)
            end
        end
    end
    
    -- Draw zone legend
    local legend_x = offset_x + grid_w * tile_size + 20
    local legend_y = offset_y
    
    love.graphics.setColor(1, 1, 1)
    love.graphics.setFont(Game.fonts.ui_small)
    love.graphics.print("Zones:", legend_x, legend_y)
    
local zones = {"downtown", "commercial", "residential_north", "residential_south", "industrial_heavy", "industrial_light", "university", "medical", "entertainment", "waterfront", "warehouse", "tech", "park_central", "park_nature"}    for i, zone in ipairs(zones) do
        local color = self:getZoneColor(zone)
        love.graphics.setColor(color[1], color[2], color[3])
        love.graphics.rectangle("fill", legend_x, legend_y + 20 + (i-1)*20, 15, 15)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print(zone, legend_x + 20, legend_y + 20 + (i-1)*20)
    end
end

-- FIXED: Helper function to get appropriate colors for different tile types
function GameView:getTileColor(tile_type)
    local C_MAP = self.Game.C.MAP
    
    if tile_type == "road" then
        return C_MAP.COLORS.ROAD
    elseif tile_type == "arterial" then
        return {0.1, 0.1, 0.1} -- Lighter gray for arterials
    elseif tile_type == "plot" then
        return C_MAP.COLORS.PLOT
    elseif tile_type == "grass" then
        return C_MAP.COLORS.GRASS
    else
        return {0.5, 0.5, 0.5} -- Default gray for unknown types
    end
end


function GameView:getZoneColor(zone_type)
    if zone_type == "downtown" then
        return {1, 1, 0} -- Yellow for downtown
    elseif zone_type == "commercial" then
        return {0, 0, 1} -- Blue for commercial
    elseif zone_type == "residential_north" then
        return {0, 1, 0} -- Green for residential north
    elseif zone_type == "residential_south" then
        return {0, 0.7, 0} -- Dark green for residential south
    elseif zone_type == "industrial_heavy" then
        return {1, 0, 0} -- Red for heavy industrial
    elseif zone_type == "industrial_light" then
        return {0.8, 0.2, 0.2} -- Light red for light industrial
    elseif zone_type == "university" then
        return {0.6, 0, 0.8} -- Purple for university
    elseif zone_type == "medical" then
        return {1, 0.5, 0.8} -- Pink for medical
    elseif zone_type == "entertainment" then
        return {1, 0.5, 0} -- Orange for entertainment
    elseif zone_type == "waterfront" then
        return {0, 0.8, 0.8} -- Cyan for waterfront
    elseif zone_type == "warehouse" then
        return {0.5, 0.3, 0.1} -- Brown for warehouse
    elseif zone_type == "tech" then
        return {0.3, 0.3, 0.8} -- Dark blue for tech
    elseif zone_type == "park_central" then
        return {0.2, 0.8, 0.3} -- Light green for central park
    elseif zone_type == "park_nature" then
        return {0.1, 0.6, 0.1} -- Dark green for nature park
    else
        return {0.5, 0.5, 0.5} -- Gray for unknown
    end
end

return GameView