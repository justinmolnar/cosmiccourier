-- views/UIView.lua
local UIView = {}
UIView.__index = UIView

function UIView:new(game_instance)
    local instance = setmetatable({}, UIView)
    instance.Game = game_instance
    return instance
end

function UIView:draw()
    local Game = self.Game
    local C = Game.C
    local state = Game.state
    local ui_manager = Game.ui_manager
    local sidebar_w = C.UI.SIDEBAR_WIDTH
    local screen_h = love.graphics.getHeight()
    
    -- Require all the new view components
    local TripsPanelView = require("views.components.TripsPanelView")
    local UpgradesPanelView = require("views.components.UpgradesPanelView")
    local VehiclesPanelView = require("views.components.VehiclesPanelView")
    local ClientsPanelView = require("views.components.ClientsPanelView")

    love.graphics.setScissor(0, 0, sidebar_w, screen_h)
    love.graphics.setColor(C.MAP.COLORS.UI_BG)
    love.graphics.rectangle("fill", 0, 0, sidebar_w, screen_h)

    love.graphics.setFont(Game.fonts.ui)
    love.graphics.setColor(1, 1, 1)

    love.graphics.print("Money: $" .. math.floor(state.money), 10, 10)
    love.graphics.printf(string.format("$%.2f/s", ui_manager.income_per_second), 0, 10, C.UI.SIDEBAR_WIDTH - 10, "right")
    love.graphics.print("Trips Completed: " .. state.trips_completed, 10, 30)
    love.graphics.print("Vehicles: " .. #Game.entities.vehicles, 10, 50)
    love.graphics.print("Clients: " .. #Game.entities.clients, 10, 70)

    if state.rush_hour.active then
        love.graphics.setColor(1,1,0)
        love.graphics.printf(string.format("RUSH HOUR: %ds", math.ceil(state.rush_hour.timer)), 0, 95, C.UI.SIDEBAR_WIDTH, "center")
    end

    -- Trips Panel
    ui_manager.trips_accordion:beginDraw(ui_manager.accordion_stats.trips)
    if ui_manager.trips_accordion.is_open then
        TripsPanelView.draw(Game, ui_manager)
    end
    ui_manager.trips_accordion:endDraw(); ui_manager.trips_accordion:drawScrollbar()
    
    -- Upgrades Panel
    ui_manager.upgrades_accordion:beginDraw(ui_manager.accordion_stats.upgrades)
    if ui_manager.upgrades_accordion.is_open then
        UpgradesPanelView.draw(Game, ui_manager)
    end
    ui_manager.upgrades_accordion:endDraw(); ui_manager.upgrades_accordion:drawScrollbar()

    -- Vehicles Panel
    ui_manager.vehicles_accordion:beginDraw(ui_manager.accordion_stats.vehicles)
    if ui_manager.vehicles_accordion.is_open then
        VehiclesPanelView.draw(Game, ui_manager)
    end
    ui_manager.vehicles_accordion:endDraw(); ui_manager.vehicles_accordion:drawScrollbar()

    -- Clients Panel
    ui_manager.clients_accordion:beginDraw(ui_manager.accordion_stats.clients)
    if ui_manager.clients_accordion.is_open then
        ClientsPanelView.draw(Game, ui_manager)
    end
    ui_manager.clients_accordion:endDraw(); ui_manager.clients_accordion:drawScrollbar()

    love.graphics.setScissor()
end

return UIView