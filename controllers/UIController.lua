-- controllers/UIController.lua
local UIController = {}
UIController.__index = UIController

function UIController:new(game_instance)
    local instance = setmetatable({}, UIController)
    instance.Game = game_instance
    return instance
end

function UIController:handleMouseDown(x, y, button)
    local Game = self.Game
    -- CORRECTED: Use ui_manager
    local ui_manager = Game.ui_manager

    if ui_manager.modal_manager:handle_mouse_down(x, y, Game) then return true end
    
    if ui_manager.trips_accordion:handle_click(x, y) then return true end
    if ui_manager.upgrades_accordion:handle_click(x, y) then return true end
    if ui_manager.vehicles_accordion:handle_click(x, y) then return true end
    if ui_manager.clients_accordion:handle_click(x, y) then return true end

    if ui_manager.hovered_trip_index then 
        Game.EventBus:publish("ui_assign_trip_clicked", ui_manager.hovered_trip_index)
        return true 
    end
    
    if ui_manager.upgrades_accordion.is_open then
        local Modal = require("views.components.Modal")
        for _, btn in ipairs(ui_manager.layout_cache.upgrades.buttons) do
            if x > btn.x and x < btn.x + btn.w and y > btn.y and y < btn.y + btn.h then
                local tech_tree_data = nil
                for _, category in ipairs(Game.state.Upgrades.categories) do
                    for _, sub_type in ipairs(category.sub_types) do
                        if sub_type.id == btn.id then
                            tech_tree_data = sub_type
                            break
                        end
                    end
                    if tech_tree_data then break end
                end

                if tech_tree_data then
                    local modal_title = btn.name .. " Upgrades"
                    local on_close = function() ui_manager.modal_manager:hide() end
                    local new_modal = Modal:new(modal_title, 800, 600, on_close, tech_tree_data)
                    ui_manager.modal_manager:show(new_modal)
                end
                return true
            end
        end
    end

    local hire_bike_btn = ui_manager.layout_cache.buttons.hire_bike
    if hire_bike_btn and x > hire_bike_btn.x and x < hire_bike_btn.x + hire_bike_btn.w and y > hire_bike_btn.y and y < hire_bike_btn.y + hire_bike_btn.h then
        Game.EventBus:publish("ui_buy_vehicle_clicked", "bike")
        return true
    end

    local hire_truck_btn = ui_manager.layout_cache.buttons.hire_truck
    if hire_truck_btn and x > hire_truck_btn.x and x < hire_truck_btn.x + hire_truck_btn.w and y > hire_truck_btn.y and y < hire_truck_btn.y + hire_truck_btn.h then
        Game.EventBus:publish("ui_buy_vehicle_clicked", "truck")
        return true
    end

    local client_btn = ui_manager.layout_cache.buttons.buy_client
    if client_btn and x > client_btn.x and x < client_btn.x + client_btn.w and y > client_btn.y and y < client_btn.y + client_btn.h then
        Game.EventBus:publish("ui_buy_client_clicked")
        return true
    end

    return false
end

return UIController