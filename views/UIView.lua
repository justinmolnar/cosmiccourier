-- views/UIView.lua
local UIView = {}
UIView.__index = UIView

local LicenseService = require("services.LicenseService")

-- License HUD button bounds (static within sidebar)
local LICENSE_BTN_Y = 90
local LICENSE_BTN_H = 24

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

    -- License HUD button
    local btn_x, btn_y, btn_w, btn_h = 8, LICENSE_BTN_Y, sidebar_w - 16, LICENSE_BTN_H
    ui_manager.license_button_bounds = { x = btn_x, y = btn_y, w = btn_w, h = btn_h }
    local current = LicenseService.getCurrent(Game)
    local label = current and current.display_name or "No License"
    local next_lic = LicenseService.getNextAvailable(Game)
    love.graphics.setColor(0.18, 0.22, 0.32)
    love.graphics.rectangle("fill", btn_x, btn_y, btn_w, btn_h, 4, 4)
    love.graphics.setColor(0.42, 0.52, 0.72, 0.8)
    love.graphics.rectangle("line", btn_x, btn_y, btn_w, btn_h, 4, 4)
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf("📜 " .. label, btn_x, btn_y + 4, btn_w, "center")
    if next_lic then
        love.graphics.setFont(Game.fonts.ui_small or Game.fonts.ui)
        love.graphics.setColor(0.75, 0.82, 0.95, 0.9)
        love.graphics.printf(
            string.format("next: %s ($%d)", next_lic.display_name, next_lic.cost),
            btn_x, btn_y + btn_h + 2, btn_w, "center")
        love.graphics.setFont(Game.fonts.ui)
    end

    if state.rush_hour and state.rush_hour.active then
        love.graphics.setColor(1, 1, 0)
        love.graphics.printf(string.format("RUSH HOUR: %ds", math.ceil(state.rush_hour.timer)),
            0, 128, sidebar_w, "center")
    end

    love.graphics.setScissor()

    -- Panel (tab bar + scrollable content). Manages its own scissor.
    ui_manager.panel:draw(Game)

    -- Drag ghost overlay (drawn above panel, clipped to sidebar)
    love.graphics.setScissor(0, 0, sidebar_w, screen_h)
    local DT = require("views.tabs.DispatchTab")
    DT.drawDragGhost(ui_manager.panel, Game)
    love.graphics.setScissor()

    -- Tooltip overlay (drawn above everything, no clip so it can overflow sidebar)
    love.graphics.setFont(Game.fonts.ui_small)
    DT.drawTooltip(Game)

    -- Modals always on top
    ui_manager.modal_manager:draw(Game)
end

return UIView
