-- controllers/UIController.lua
local UIController = {}
UIController.__index = UIController

function UIController:new(game_instance)
    local instance = setmetatable({}, UIController)
    instance.Game = game_instance
    return instance
end

function UIController:handleGenericButtonClick(x, y, buttons_list, game)
    for _, button_data in ipairs(buttons_list) do
        if self:isMouseInButton(x, y, button_data) then
            if button_data.event then
                if button_data.data then
                    game.EventBus:publish(button_data.event, button_data.data)
                else
                    game.EventBus:publish(button_data.event, button_data.id)
                end
                return true
            end
        end
    end
    return false
end

function UIController:isMouseInButton(x, y, btn)
    if not btn then return false end
    return x > btn.x and x < btn.x + btn.w and y > btn.y and y < btn.y + btn.h
end

function UIController:handleMouseDown(x, y, button)
    local Game = self.Game
    local ui_manager = Game.ui_manager

    -- 1. Modals are always on top. Check them first.
    if ui_manager.modal_manager:handle_mouse_down(x, y, Game) then return true end

    -- 2. Check if an accordion HEADER was clicked. This re-enables expand/collapse.
    if ui_manager.trips_accordion:handle_click(x, y) then return true end
    if ui_manager.upgrades_accordion:handle_click(x, y) then return true end
    if ui_manager.vehicles_accordion:handle_click(x, y) then return true end
    if ui_manager.clients_accordion:handle_click(x, y) then return true end

    -- 3. Check for scrollbar interaction ONLY if the accordion is open.
    if ui_manager.trips_accordion.is_open and ui_manager.trips_accordion:handle_mouse_down(x, y, button) then return true end
    if ui_manager.upgrades_accordion.is_open and ui_manager.upgrades_accordion:handle_mouse_down(x, y, button) then return true end
    if ui_manager.vehicles_accordion.is_open and ui_manager.vehicles_accordion:handle_mouse_down(x, y, button) then return true end
    if ui_manager.clients_accordion.is_open and ui_manager.clients_accordion:handle_mouse_down(x, y, button) then return true end

    -- 4. Check for clicks on content WITHIN each OPEN accordion.
    -- This is the crucial fix for the invisible button click issue.

    -- Clicks on trips in the trips panel
    if ui_manager.trips_accordion.is_open and ui_manager.hovered_trip_index then
        Game.EventBus:publish("ui_assign_trip_clicked", ui_manager.hovered_trip_index)
        return true
    end

    -- Clicks on upgrade category buttons (to open the modal)
    if ui_manager.upgrades_accordion.is_open then
        if self:handleGenericButtonClick(x, y, ui_manager.layout_cache.upgrades.buttons, Game) then
            local Modal = require("views.components.Modal")
            -- Find the clicked button to get its data
            for _, btn in ipairs(ui_manager.layout_cache.upgrades.buttons) do
                if self:isMouseInButton(x, y, btn) then
                    local modal_title = btn.name .. " Upgrades"
                    local on_close = function() ui_manager.modal_manager:hide() end
                    local new_modal = Modal:new(modal_title, 800, 600, on_close, btn.data)
                    ui_manager.modal_manager:show(new_modal)
                    break
                end
            end
            return true
        end
    end

    -- Clicks on "hire vehicle" buttons
    if ui_manager.vehicles_accordion.is_open then
        if self:isMouseInButton(x, y, ui_manager.layout_cache.buttons.hire_bike) then
            Game.EventBus:publish("ui_buy_vehicle_clicked", "bike")
            return true
        end
        if self:isMouseInButton(x, y, ui_manager.layout_cache.buttons.hire_truck) then
            Game.EventBus:publish("ui_buy_vehicle_clicked", "truck")
            return true
        end
    end

    -- Clicks on "buy client" button
    if ui_manager.clients_accordion.is_open then
        if self:isMouseInButton(x, y, ui_manager.layout_cache.buttons.buy_client) then
            Game.EventBus:publish("ui_buy_client_clicked")
            return true
        end
    end

    return false
end

return UIController