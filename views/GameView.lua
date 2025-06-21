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

    -- Draw scale-specific content
    local current_scale = Game.state.current_map_scale
    local C_MAP = Game.C.MAP
    
    if current_scale == C_MAP.SCALES.REGION then
        -- At region scale, only draw trucks and regional elements
        self:drawRegionalElements(Game)
        self:drawVehiclesAtRegionScale(Game)
    else
        -- At city/downtown scale, draw city-specific content
        self:drawCityElements(Game)
        self:drawVehiclesAtCityScale(Game)
    end

    -- Draw trip path visualization (only for city/downtown view)
    if (current_scale == C_MAP.SCALES.CITY or current_scale == C_MAP.SCALES.DOWNTOWN) 
       and ui_manager.hovered_trip_index then
        self:drawTripPathVisualization(Game, ui_manager)
    end

    love.graphics.pop()
    
    -- Debug drawing (only for detailed views)
    if Game.debug_mode and current_scale ~= C_MAP.SCALES.REGION then
        self:drawDebugInfo(Game)
    end
    
    love.graphics.setScissor()
end

function GameView:drawRegionalElements(game)
    -- Draw regional-scale elements (cities, major roads, etc.)
    -- For now, this is mostly handled by the region map itself
    
    -- Could add city markers, major highway indicators, etc.
end

function GameView:drawCityElements(game)
    local active_map = game.maps[game.active_map_key]
    
    -- Draw depot
    if game.entities.depot_plot then
        local depot_px, depot_py = active_map:getPixelCoords(game.entities.depot_plot.x, game.entities.depot_plot.y)
        love.graphics.setFont(game.fonts.emoji)
        love.graphics.push()
        love.graphics.translate(depot_px, depot_py)
        love.graphics.scale(1 / game.camera.scale, 1 / game.camera.scale)
        love.graphics.print("🏢", -14, -14)
        love.graphics.pop()
    end

    -- Draw clients
    for _, client in ipairs(game.entities.clients) do
        love.graphics.setFont(game.fonts.emoji)
        love.graphics.push()
        love.graphics.translate(client.px, client.py)
        love.graphics.scale(1 / game.camera.scale, 1 / game.camera.scale)
        love.graphics.print("🏠", -14, -14)
        love.graphics.pop()
    end
    
    -- Draw event spawner
    game.event_spawner:draw(game)
end

function GameView:drawVehiclesAtRegionScale(game)
    -- At region scale, only draw trucks (bikes are abstracted)
    for _, vehicle in ipairs(game.entities.vehicles) do
        if vehicle.type == "truck" and vehicle.visible then
            vehicle:draw(game)
        end
    end
end

function GameView:drawVehiclesAtCityScale(game)
    -- At city/downtown scale, draw all vehicles
    for _, vehicle in ipairs(game.entities.vehicles) do
        if vehicle.visible then
            local current_scale = Game.state.current_map_scale
            local should_draw = false
            
            -- Trucks render at all zoom levels
            if vehicle.type == "truck" then
                should_draw = true
            -- Bikes only render at downtown and city scales
            elseif vehicle.type == "bike" and (current_scale == Game.C.MAP.SCALES.DOWNTOWN or current_scale == Game.C.MAP.SCALES.CITY) then
                should_draw = true
            end
            
            if should_draw then
                vehicle:draw(Game)
            end
        end
    end
end

function GameView:drawTripPathVisualization(game, ui_manager)
    local Bike = require("models.vehicles.Bike")
    local Truck = require("models.vehicles.Truck")
    local active_map = game.maps[game.active_map_key]
    
    local trip = game.entities.trips.pending[ui_manager.hovered_trip_index]
    if trip and trip.legs[trip.current_leg] then
        local leg = trip.legs[trip.current_leg]
        local path_grid = active_map.grid
        local start_node = (leg.vehicleType == "truck" and trip.current_leg > 1) and 
                          active_map:findNearestRoadTile(game.entities.depot_plot) or 
                          active_map:findNearestRoadTile(leg.start_plot)
        local end_node = active_map:findNearestRoadTile(leg.end_plot)
        
        if start_node and end_node and path_grid then
            local costs = leg.vehicleType == "bike" and Bike.PROPERTIES.pathfinding_costs or Truck.PROPERTIES.pathfinding_costs
            local path = game.pathfinder.findPath(path_grid, start_node, end_node, costs, active_map)
            
            if path then
                local pixel_path = {}
                for _, node in ipairs(path) do
                    local px, py = active_map:getPixelCoords(node.x, node.y)
                    table.insert(pixel_path, px)
                    table.insert(pixel_path, py)
                end
                
                local hover_color = game.C.MAP.COLORS.HOVER
                love.graphics.setColor(hover_color[1], hover_color[2], hover_color[3], 0.7)
                love.graphics.setLineWidth(3 / game.camera.scale)
                love.graphics.line(pixel_path)
                love.graphics.setLineWidth(1)
                
                local circle_radius = 5 / game.camera.scale
                love.graphics.setColor(hover_color)
                love.graphics.circle("fill", pixel_path[1], pixel_path[2], circle_radius)
                love.graphics.circle("fill", pixel_path[#pixel_path-1], pixel_path[#pixel_path], circle_radius)
            end
        end
    end
end

function GameView:drawDebugInfo(game)
    for _, vehicle in ipairs(game.entities.vehicles) do
        if vehicle.visible and vehicle:shouldDrawAtCurrentScale(game) then
            vehicle:drawDebug(game)
        end
    end
end

return GameView