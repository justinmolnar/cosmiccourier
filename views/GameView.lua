-- views/GameView.lua
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

    local active_map = Game.maps[Game.active_map_key]
    if not active_map then return end 

    love.graphics.setScissor(sidebar_w, 0, screen_w - sidebar_w, screen_h)
    love.graphics.push()

    local game_world_w = screen_w - sidebar_w
    love.graphics.translate(sidebar_w + game_world_w / 2, screen_h / 2)
    love.graphics.scale(Game.camera.scale, Game.camera.scale)
    love.graphics.translate(-Game.camera.x, -Game.camera.y)
    
    active_map:draw()

    if Game.active_map_key == "city" then
        if Game.entities.depot_plot then
            local depot_px, depot_py = active_map:getPixelCoords(Game.entities.depot_plot.x, Game.entities.depot_plot.y)
            love.graphics.setFont(Game.fonts.emoji)
            love.graphics.push()
            love.graphics.translate(depot_px, depot_py)
            love.graphics.scale(1 / Game.camera.scale, 1 / Game.camera.scale)
            love.graphics.print("🏢", -14, -14)
            love.graphics.pop()
        end

        for _, client in ipairs(Game.entities.clients) do
            love.graphics.setFont(Game.fonts.emoji)
            love.graphics.push()
            love.graphics.translate(client.px, client.py)
            love.graphics.scale(1 / Game.camera.scale, 1 / Game.camera.scale)
            love.graphics.print("🏠", -14, -14)
            love.graphics.pop()
        end

        -- MODIFIED: Added a check for vehicle.visible
        for _, vehicle in ipairs(Game.entities.vehicles) do
            if vehicle.visible then
                vehicle:draw(Game)
            end
        end
        
        Game.event_spawner:draw(Game)

        if ui_manager.hovered_trip_index then
            local trip = Game.entities.trips.pending[ui_manager.hovered_trip_index]
            if trip and trip.legs[trip.current_leg] then
                local leg = trip.legs[trip.current_leg]
                local path_grid = active_map.grid
                local start_node = (leg.vehicleType == "truck" and trip.current_leg > 1) and active_map:findNearestRoadTile(Game.entities.depot_plot) or active_map:findNearestRoadTile(leg.start_plot)
                local end_node = active_map:findNearestRoadTile(leg.end_plot)
                if start_node and end_node and path_grid then
                    local costs = leg.vehicleType == "bike" and Bike.PROPERTIES.pathfinding_costs or Truck.PROPERTIES.pathfinding_costs
                    local path = Game.pathfinder.findPath(path_grid, start_node, end_node, costs, active_map)
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
    end

    love.graphics.pop()
    
    if Game.debug_mode and Game.active_map_key == "city" then
        for _, vehicle in ipairs(Game.entities.vehicles) do
            if vehicle.visible then
                vehicle:drawDebug(Game)
            end
        end
    end
    
    love.graphics.setScissor()
end

return GameView