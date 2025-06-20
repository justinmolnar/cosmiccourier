-- views/GameView.lua
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
    local ui_manager = Game.ui_manager -- CORRECTED: Use ui_manager instead of ui
    local sidebar_w = Game.C.UI.SIDEBAR_WIDTH
    local screen_w, screen_h = love.graphics.getDimensions()

    love.graphics.setScissor(sidebar_w, 0, screen_w - sidebar_w, screen_h)
    love.graphics.push()

    local game_world_w = screen_w - sidebar_w
    love.graphics.translate(sidebar_w + game_world_w / 2, screen_h / 2)
    love.graphics.scale(Game.camera.scale, Game.camera.scale)
    love.graphics.translate(-Game.camera.x, -Game.camera.y)
    
    Game.map:draw()

    if Game.entities.depot_plot then
        local depot_px, depot_py = Game.map:getPixelCoords(Game.entities.depot_plot.x, Game.entities.depot_plot.y)
        love.graphics.setFont(Game.fonts.emoji)
        love.graphics.setColor(0, 0, 0)
        love.graphics.push()
        love.graphics.translate(depot_px, depot_py)
        love.graphics.scale(1 / Game.camera.scale, 1 / Game.camera.scale)
        love.graphics.print("🏠", -14, -14)
        love.graphics.pop()
    end

    love.graphics.setFont(Game.fonts.emoji)
    for _, client in ipairs(Game.entities.clients) do
        love.graphics.setColor(0, 0, 0)
        love.graphics.push()
        love.graphics.translate(client.px, client.py)
        love.graphics.scale(1 / Game.camera.scale, 1 / Game.camera.scale)
        love.graphics.print("🏢", -14, -14)
        love.graphics.pop()
    end

    for _, vehicle in ipairs(Game.entities.vehicles) do
        if vehicle == Game.entities.selected_vehicle then
            love.graphics.setColor(1, 1, 0)
            local radius = 16 / Game.camera.scale
            love.graphics.setLineWidth(2 / Game.camera.scale)
            love.graphics.circle("line", vehicle.px, vehicle.py, radius)
            love.graphics.setLineWidth(1)
        end

        love.graphics.setFont(Game.fonts.emoji)
        love.graphics.setColor(0, 0, 0)
        love.graphics.push()
        love.graphics.translate(vehicle.px, vehicle.py)
        love.graphics.scale(1 / Game.camera.scale, 1 / Game.camera.scale)
        local icon = vehicle.type == "bike" and "🚲" or "🚚"
        love.graphics.print(icon, -14, -14)
        love.graphics.pop()

        if Game.debug_mode then
            vehicle:drawDebug(Game)
        end
    end
    
    Game.event_spawner:draw(Game)

    -- CORRECTED: The error is here. Use ui_manager.
    if ui_manager.hovered_trip_index then
        local trip = Game.entities.trips.pending[ui_manager.hovered_trip_index]
        if trip and trip.legs[trip.current_leg] then
            local leg = trip.legs[trip.current_leg]
            local path_grid = Game.map.grid
            local start_node = (leg.vehicleType == "truck" and trip.current_leg > 1) and Game.map:findNearestRoadTile(Game.entities.depot_plot) or Game.map:findNearestRoadTile(leg.start_plot)
            local end_node = Game.map:findNearestRoadTile(leg.end_plot)
            if start_node and end_node and path_grid then
                -- FIX: Get pathfinding costs from the vehicle classes that are now properly required
                local costs = leg.vehicleType == "bike" and Bike.PROPERTIES.pathfinding_costs or Truck.PROPERTIES.pathfinding_costs
                local path = Game.pathfinder.findPath(path_grid, start_node, end_node, costs, Game.map)
                if path then
                    local pixel_path = {}
                    for _, node in ipairs(path) do
                        local px, py = Game.map:getPixelCoords(node.x, node.y)
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

    -- MOVE THIS OUTSIDE THE CAMERA TRANSFORM - END THE TRANSFORM HERE
    love.graphics.pop()
    
    -- NOW DRAW FLOATING TEXT IN SCREEN SPACE (UNSCALED)
    love.graphics.setFont(Game.fonts.ui)
    for _, ft in ipairs(Game.state.floating_texts) do
        -- Convert world coordinates to screen coordinates
        local CoordinateSystem = require("utils.CoordinateSystem")
        local coord_system = CoordinateSystem.new(Game.C)
        local screen_x, screen_y = coord_system:worldToScreen(ft.x, ft.y, Game.camera)
        
        love.graphics.setColor(1, 1, 0.8, ft.alpha)
        -- Center the text around the screen position
        love.graphics.printf(ft.text, screen_x - 75, screen_y, 150, "center")
    end
    
    love.graphics.setScissor()
end

return GameView