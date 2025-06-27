-- views/GameView.lua
-- Updated to render edge-based streets between grid cells
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

    if Game.lab_grid or Game.wfc_final_grid then
        love.graphics.push()
        -- REMOVED the redundant love.graphics.translate() call that was here
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
    
    if Game.wfc_final_grid and Game.wfc_road_data then
        self:drawFinalWfcCity()
        return
    end

    if not Game.lab_grid then return end
    local grid = Game.lab_grid
    if not grid or #grid == 0 or not grid[1] then return end
    
    local grid_h, grid_w = #grid, #grid[1]
    local screen_w, screen_h = love.graphics.getDimensions()
    local sidebar_w = Game.C.UI.SIDEBAR_WIDTH
    local available_w, available_h = screen_w - sidebar_w, screen_h
    
    local tile_size_w = math.floor(available_w * 0.9 / grid_w)
    local tile_size_h = math.floor(available_h * 0.9 / grid_h)
    local tile_size = math.max(4, math.min(tile_size_w, tile_size_h, 25))
    
    local total_grid_w, total_grid_h = grid_w * tile_size, grid_h * tile_size
    local offset_x = sidebar_w + (available_w - total_grid_w) / 2
    local offset_y = (available_h - total_grid_h) / 2
    
    love.graphics.setColor(0.1, 0.1, 0.1, 0.8)
    love.graphics.rectangle("fill", offset_x - 10, offset_y - 40, total_grid_w + 20, total_grid_h + 50)
    
    if Game.show_flood_fill_regions and Game.debug_flood_fill_regions then
        self:drawFloodFillRegions(offset_x, offset_y, tile_size)
    elseif Game.lab_zone_grid then
        self:drawZoneBackground(offset_x, offset_y, tile_size)
    end
    
    for y = 1, grid_h do
        for x = 1, grid_w do
            if grid[y] and grid[y][x] and grid[y][x].type then
                local tile_type = grid[y][x].type
                
                if tile_type == "arterial" then
                    local color = self:getTileColor(tile_type)
                    love.graphics.setColor(color)
                    love.graphics.rectangle("fill", offset_x + (x-1)*tile_size, offset_y + (y-1)*tile_size, tile_size, tile_size)
                end
                
                if tile_type == "plot" then
                    love.graphics.setColor(0.5, 0.5, 0.5, 0.2)
                    love.graphics.rectangle("line", offset_x + (x-1)*tile_size, offset_y + (y-1)*tile_size, tile_size, tile_size)
                end
            end
        end
    end
    
    if Game.street_segments then
        love.graphics.setColor(0.3, 0.3, 0.3, 1.0)
        love.graphics.setLineWidth(math.max(2, tile_size * 0.15))
        
        for _, segment in ipairs(Game.street_segments) do
            if segment.type == "horizontal" then
                local x1 = offset_x + (segment.x1 - 1) * tile_size
                local x2 = offset_x + segment.x2 * tile_size
                local y_pos = offset_y + (segment.y - 0.5) * tile_size
                love.graphics.line(x1, y_pos, x2, y_pos)
            elseif segment.type == "vertical" then
                local y1 = offset_y + (segment.y1 - 1) * tile_size
                local y2 = offset_y + segment.y2 * tile_size
                local x_pos = offset_x + (segment.x - 0.5) * tile_size
                love.graphics.line(x_pos, y1, x_pos, y2)
            end
        end
        love.graphics.setLineWidth(1)
    end
    
    if Game.smooth_highway_overlay_paths and #Game.smooth_highway_overlay_paths > 0 then
        love.graphics.setLineWidth(math.max(2, tile_size / 4))
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

    if Game.arterial_control_paths and #Game.arterial_control_paths > 0 then
        love.graphics.setLineWidth(math.max(3, math.floor(tile_size / 1)))
        love.graphics.setColor(0.1, 0.1, 0.1, 0.8)
        
        for _, path in ipairs(Game.arterial_control_paths) do
            if #path > 1 then
                for i = 1, #path - 1 do
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
        love.graphics.setLineWidth(1)
    end

    love.graphics.setColor(1, 1, 1)
    love.graphics.setFont(Game.fonts.ui)
    
    local title = "Edge-Based Streets - Press 'H' for help"
    if Game.show_flood_fill_regions then
        title = "FLOOD FILL REGIONS DEBUG - Press '6' to toggle"
    end
    love.graphics.print(title, offset_x, offset_y - 35)
    
    self:drawLegend(offset_x + total_grid_w + 20, offset_y)
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
    local tile_size = math.max(2, math.min(tile_size_w, tile_size_h, 25))
    
    local total_grid_w, total_grid_h = grid_w * tile_size, grid_h * tile_size
    local offset_x = sidebar_w + (available_w - total_grid_w) / 2
    local offset_y = (available_h - total_grid_h) / 2
    
    -- Step 1: Draw Zone Colors as background
    if Game.lab_zone_grid then
        self:drawZoneBackground(offset_x, offset_y, tile_size)
    end
    
    -- Step 2: Draw Arterials first (as thick lines)
    if Game.arterial_control_paths and #Game.arterial_control_paths > 0 then
        love.graphics.setLineWidth(math.max(3, tile_size * 0.8))
        love.graphics.setColor(0.2, 0.2, 0.2, 1.0)
        
        for _, path in ipairs(Game.arterial_control_paths) do
            if #path > 1 then
                for i = 1, #path - 1 do
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

    -- Step 3: Draw Local Streets
    love.graphics.setColor(0.3, 0.3, 0.3, 1.0)
    love.graphics.setLineWidth(math.max(1, tile_size * 0.5))
    
    for _, road in ipairs(roads) do
        if road.type == "horizontal" then
            local x1 = offset_x + (road.x1 - 1) * tile_size
            local x2 = offset_x + road.x2 * tile_size
            local y_pos = offset_y + (road.y - 0.5) * tile_size
            love.graphics.line(x1, y_pos, x2, y_pos)
        elseif road.type == "vertical" then
            local y1 = offset_y + (road.y1 - 1) * tile_size
            local y2 = offset_y + road.y2 * tile_size
            local x_pos = offset_x + (road.x - 0.5) * tile_size
            love.graphics.line(x_pos, y1, x_pos, y2)
        end
    end

    love.graphics.setLineWidth(1)
end

function GameView:drawZoneBackground(offset_x, offset_y, tile_size)
    local Game = self.Game
    
    if not Game.lab_zone_grid then return end
    
    local zone_grid = Game.lab_zone_grid
    local grid_h, grid_w = #zone_grid, #zone_grid[1]
    
    -- Draw zone colors as background
    for y = 1, grid_h do
        for x = 1, grid_w do
            if zone_grid[y] and zone_grid[y][x] then
                local zone = zone_grid[y][x]
                local zone_color = self:getZoneColor(zone)
                
                -- Draw zones prominently as background
                love.graphics.setColor(zone_color[1], zone_color[2], zone_color[3], 0.7)
                love.graphics.rectangle("fill", 
                    offset_x + (x-1) * tile_size, 
                    offset_y + (y-1) * tile_size, 
                    tile_size, 
                    tile_size)
            end
        end
    end
end

function GameView:drawFloodFillRegions(offset_x, offset_y, tile_size)
    local Game = self.Game
    
    if not Game.debug_flood_fill_regions then return end
    
    local region_colors = {
        {1.0, 0.2, 0.2, 0.6}, {0.2, 1.0, 0.2, 0.6}, {0.2, 0.2, 1.0, 0.6}, 
        {1.0, 1.0, 0.2, 0.6}, {1.0, 0.2, 1.0, 0.6}, {0.2, 1.0, 1.0, 0.6},
        {1.0, 0.5, 0.2, 0.6}, {0.5, 0.2, 1.0, 0.6}, {0.2, 0.5, 0.2, 0.6},
        {0.5, 0.5, 0.2, 0.6}, {0.2, 0.5, 0.5, 0.6}, {0.5, 0.2, 0.5, 0.6}
    }
    
    for region_idx, region in ipairs(Game.debug_flood_fill_regions) do
        local color = region_colors[((region_idx - 1) % #region_colors) + 1]
        love.graphics.setColor(color[1], color[2], color[3], color[4])
        
        for _, cell in ipairs(region.cells) do
            love.graphics.rectangle("fill", 
                offset_x + (cell.x - 1) * tile_size, 
                offset_y + (cell.y - 1) * tile_size, 
                tile_size, 
                tile_size)
        end
        
        love.graphics.setColor(color[1], color[2], color[3], 1.0)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line",
            offset_x + (region.min_x - 1) * tile_size,
            offset_y + (region.min_y - 1) * tile_size,
            (region.max_x - region.min_x + 1) * tile_size,
            (region.max_y - region.min_y + 1) * tile_size)
        
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setFont(Game.fonts.ui_small)
        local center_x = offset_x + ((region.min_x + region.max_x) / 2 - 1) * tile_size
        local center_y = offset_y + ((region.min_y + region.max_y) / 2 - 1) * tile_size
        love.graphics.print(tostring(region.id), center_x, center_y)
    end
    
    love.graphics.setLineWidth(1)
end

function GameView:drawLegend(legend_x, legend_y)
    local Game = self.Game
    
    love.graphics.setColor(1, 1, 1)
    love.graphics.setFont(Game.fonts.ui_small)
    love.graphics.print("Legend:", legend_x, legend_y)
    
    local legend_items = {
        {type = "arterial", name = "Arterial (on grid)", color = {0.1, 0.1, 0.1}},
        {type = "street", name = "Street (between grid)", color = {0.8, 0.8, 0.8}}, -- Changed color to match
        {type = "intersection", name = "Intersection", color = {0.8, 0.8, 0.8}}, -- Changed color to match
        {type = "plot", name = "Building Plot", color = {0.5, 0.5, 0.5}},
        {type = "zone", name = "Zone Color", color = {0.7, 0.7, 0.7}}
    }
    
    for i, item in ipairs(legend_items) do
        local y_pos = legend_y + 20 + (i-1) * 20
        
        love.graphics.setColor(item.color[1], item.color[2], item.color[3])
        if item.type == "street" then
            love.graphics.rectangle("fill", legend_x, y_pos + 4, 15, 8) -- Show as a filled rectangle
        elseif item.type == "intersection" then
            love.graphics.rectangle("fill", legend_x + 4, y_pos + 4, 8, 8) -- Show as a filled square
        else
            love.graphics.rectangle("fill", legend_x, y_pos, 15, 15)
        end
        
        love.graphics.setColor(1, 1, 1)
        love.graphics.print(item.name, legend_x + 20, y_pos)
    end
    
    love.graphics.print("Streets are BETWEEN grid cells", legend_x, legend_y + 120)
    love.graphics.print("Arteries are ON grid cells", legend_x, legend_y + 140)
    love.graphics.print("Zones: " .. (Game.show_districts and "VISIBLE" or "HIDDEN"), legend_x, legend_y + 160)
    
    if Game.street_intersections then
        love.graphics.print("Intersections: " .. #Game.street_intersections, legend_x, legend_y + 180)
    end
    if Game.street_segments then
        love.graphics.print("Street edges: " .. #Game.street_segments, legend_x, legend_y + 200)
    end
end

function GameView:getTileColor(tile_type)
    if tile_type == "arterial" then
        return {0.1, 0.1, 0.1}
    elseif tile_type == "road" then
        return {0.3, 0.3, 0.3}
    elseif tile_type == "plot" then
        return {0.8, 0.8, 0.9}
    elseif tile_type == "grass" then
        return {0.2, 0.8, 0.2}
    else
        return {0.5, 0.5, 0.5}
    end
end

function GameView:getZoneColor(zone_type)
    if zone_type == "downtown" then
        return {1, 1, 0}
    elseif zone_type == "commercial" then
        return {0, 0, 1}
    elseif zone_type == "residential_north" then
        return {0, 1, 0}
    elseif zone_type == "residential_south" then
        return {0, 0.7, 0}
    elseif zone_type == "industrial_heavy" then
        return {1, 0, 0}
    elseif zone_type == "industrial_light" then
        return {0.8, 0.2, 0.2}
    elseif zone_type == "university" then
        return {0.6, 0, 0.8}
    elseif zone_type == "medical" then
        return {1, 0.5, 0.8}
    elseif zone_type == "entertainment" then
        return {1, 0.5, 0}
    elseif zone_type == "waterfront" then
        return {0, 0.8, 0.8}
    elseif zone_type == "warehouse" then
        return {0.5, 0.3, 0.1}
    elseif zone_type == "tech" then
        return {0.3, 0.3, 0.8}
    elseif zone_type == "park_central" then
        return {0.2, 0.8, 0.3}
    elseif zone_type == "park_nature" then
        return {0.1, 0.6, 0.1}
    else
        return {0.5, 0.5, 0.5}
    end
end

return GameView