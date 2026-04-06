-- controllers/UIController.lua
local CR = require("views.ComponentRenderer")

local UIController = {}
UIController.__index = UIController

function UIController:new(game_instance)
    local instance = setmetatable({}, UIController)
    instance.Game = game_instance
    return instance
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

    local comps = panel:getComponents()
    if not comps then return false end

    local cy  = panel:toContentY(y)
    local hit = CR.hitTest(comps, panel.x, panel.w, x, cy)
    if not hit or not hit.id then return false end

    local id   = hit.id
    local data = hit.data or {}

    if id == "assign_trip" then
        Game.EventBus:publish("ui_assign_trip_clicked", data.index)

    elseif id == "hire_vehicle" then
        Game.EventBus:publish("ui_buy_vehicle_clicked", data.vehicle_id)

    elseif id == "buy_client" then
        Game.EventBus:publish("ui_buy_client_clicked")

    elseif id == "select_vehicle" then
        Game.entities.selected_vehicle = data.vehicle

    elseif id == "deselect_vehicle" then
        Game.entities.selected_vehicle = nil

    elseif id == "unassign_vehicle" then
        local v = data.vehicle
        if v then v:unassign(Game) end

    elseif id == "open_upgrade" then
        local Modal    = require("views.components.Modal")
        local on_close = function() ui_manager.modal_manager:hide() end
        local new_modal = Modal:new((data.name or "?") .. " Upgrades", 800, 600, on_close, data)
        ui_manager.modal_manager:show(new_modal)

    end

    return true
end

return UIController
