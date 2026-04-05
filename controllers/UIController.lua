-- controllers/UIController.lua
local UIController = {}
UIController.__index = UIController

function UIController:new(game_instance)
    local instance = setmetatable({}, UIController)
    instance.Game = game_instance
    return instance
end

function UIController:isMouseInButton(x, y, btn)
    if not btn then return false end
    return x >= btn.x and x < btn.x + btn.w and y >= btn.y and y < btn.y + btn.h
end

function UIController:handleMouseDown(x, y, button)
    local Game       = self.Game
    local ui_manager = Game.ui_manager
    local panel      = ui_manager.panel

    -- 1. Modals are always on top.
    if ui_manager.modal_manager:handle_mouse_down(x, y, Game) then return true end

    -- 2. Panel tab bar and scrollbar.
    if panel:handleMouseDown(x, y, button) then return true end

    -- 3. Content clicks — only when mouse is in the content area.
    if not panel:isInContentArea(x, y) then return false end

    local active = panel.active_tab_id
    local cy     = panel:toContentY(y)   -- content-space y

    -- Trips tab: click assigns the hovered trip to the selected vehicle
    if active == "trips" and ui_manager.hovered_trip_index then
        Game.EventBus:publish("ui_assign_trip_clicked", ui_manager.hovered_trip_index)
        return true
    end

    -- Upgrades tab: open the upgrade modal for the clicked category
    if active == "upgrades" then
        for _, btn in ipairs(ui_manager.layout_cache.upgrades.buttons) do
            if self:isMouseInButton(x, cy, btn) then
                local Modal = require("views.components.Modal")
                local on_close = function() ui_manager.modal_manager:hide() end
                local new_modal = Modal:new(btn.name .. " Upgrades", 800, 600, on_close, btn.data)
                ui_manager.modal_manager:show(new_modal)
                return true
            end
        end
    end

    -- Vehicles tab: hire buttons
    if active == "vehicles" then
        local hire_btns = ui_manager.layout_cache.buttons.hire_vehicles or {}
        for _, btn in pairs(hire_btns) do
            if self:isMouseInButton(x, cy, btn) then
                Game.EventBus:publish("ui_buy_vehicle_clicked", btn.vehicle_id)
                return true
            end
        end
    end

    -- Clients tab: buy client button
    if active == "clients" then
        if self:isMouseInButton(x, cy, ui_manager.layout_cache.buttons.buy_client) then
            Game.EventBus:publish("ui_buy_client_clicked")
            return true
        end
    end

    return false
end

return UIController
