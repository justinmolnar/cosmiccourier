-- views/UIView.lua
local UIView = {}
UIView.__index = UIView

function UIView:new(game_instance)
    local instance = setmetatable({}, UIView)
    instance.Game = game_instance
    return instance
end

function UIView:draw()
    local Game       = self.Game
    local C          = Game.C
    local state      = Game.state
    local ui_manager = Game.ui_manager
    local sidebar_w  = C.UI.SIDEBAR_WIDTH
    local screen_h   = love.graphics.getHeight()

    -- Sidebar background + stats header (scissored to sidebar width)
    love.graphics.setScissor(0, 0, sidebar_w, screen_h)
    love.graphics.setColor(C.MAP.COLORS.UI_BG)
    love.graphics.rectangle("fill", 0, 0, sidebar_w, screen_h)

    love.graphics.setFont(Game.fonts.ui)
    love.graphics.setColor(1, 1, 1)

    love.graphics.print("Money: $" .. math.floor(state.money), 10, 10)
    love.graphics.printf(string.format("$%.2f/s", ui_manager.income_per_second), 0, 10, sidebar_w - 10, "right")
    love.graphics.print("Trips Completed: " .. state.trips_completed, 10, 30)
    love.graphics.print("Vehicles: " .. #Game.entities.vehicles, 10, 50)
    love.graphics.print("Clients: " .. #Game.entities.clients, 10, 70)

    if state.rush_hour and state.rush_hour.active then
        love.graphics.setColor(1, 1, 0)
        love.graphics.printf(string.format("RUSH HOUR: %ds", math.ceil(state.rush_hour.timer)),
            0, 95, sidebar_w, "center")
    end

    love.graphics.setScissor()

    -- Panel (tab bar + scrollable content). Manages its own scissor.
    ui_manager.panel:draw(Game)

    -- Modals always on top
    ui_manager.modal_manager:draw(Game)
end

return UIView
