-- controllers/InputController.lua

local InputController = {}
InputController.__index = InputController

function InputController:new(game)
    local instance = setmetatable({}, InputController)
    instance.game = game
    local UIController = require("controllers.UIController")
    instance.ui_controller = UIController:new(game)
    return instance
end

function InputController:keypressed(key)
    if key == "escape" then
        love.event.quit()
        return
    end

    -- Debug mode toggle
    if key == "tab" then
        self.game.debug_mode = not self.game.debug_mode
        if self.game.error_service then
            self.game.error_service.logInfo("Input", "Debug mode set to: " .. tostring(self.game.debug_mode))
        end
        return
    end

    -- Debug overlay toggles
    local DEBUG_TOGGLES = {
        b = { field = "debug_building_plots",      label = "building plots overlay" },
        p = { field = "debug_pickup_locations",    label = "pickup/client overlay" },
        g = { field = "debug_road_segments",       label = "road segments overlay" },
        v = { field = "debug_smooth_roads",        label = "smooth road overlay" },
        n = { field = "debug_hide_roads",          label = "hide roads" },
        m = { field = "debug_smooth_roads_merged", label = "merged street overlay" },
        j = { field = "debug_smooth_roads_like",   label = "streets-like-big-roads overlay" },
        o = { field = "overlay_only_mode",         label = "overlay-only mode" },
    }
    local toggle = DEBUG_TOGGLES[key]
    if toggle then
        self.game[toggle.field] = not (self.game[toggle.field] or false)
        print("DEBUG: " .. toggle.label .. " " .. (self.game[toggle.field] and "ON" or "OFF"))
        return
    end

    -- Force-enable autodispatch (debug cheat)
    if key == "a" then
        self.game.state.upgrades.auto_dispatch_unlocked = true
        print("DEBUG: Force enabled autodispatch")
        return
    end

    -- Money cheats
    if key == "-" then
        if self.game.state then
            self.game.state.money = self.game.state.money - 10000
            if self.game.error_service then
                self.game.error_service.logInfo("Input", "DEBUG: Removed 10,000 money.")
            end
        end
        return
    elseif key == "=" then
        if self.game.state then
            self.game.state.money = self.game.state.money + 10000
            if self.game.error_service then
                self.game.error_service.logInfo("Input", "DEBUG: Added 10,000 money.")
            end
        end
        return
    end
end

function InputController:textinput(text)
end

function InputController:mousewheelmoved(x, y)
    if self.game.ui_manager and self.game.ui_manager.handle_scroll then
        self.game.ui_manager:handle_scroll(y)
    end
end

function InputController:mousepressed(x, y, button)
    local Game = self.game

    if self.ui_controller:handleMouseDown(x, y, button) then
        return
    end

    if Game.zoom_controls and Game.zoom_controls.handle_click then
        if Game.zoom_controls:handle_click(x, y, Game) then
            return
        end
    end

    if button == 1 then
        local sidebar_w = Game.C.UI.SIDEBAR_WIDTH
        if x >= sidebar_w then
            self:handleGameWorldClick(x, y)
        end
    end
end

function InputController:mousereleased(x, y, button)
    if self.game.ui_manager and self.game.ui_manager.handle_mouse_up then
        self.game.ui_manager:handle_mouse_up(x, y, button)
    end
end

function InputController:mousemoved(x, y, dx, dy)
end

function InputController:handleGameWorldClick(x, y)
    local world_x, world_y = self.game.camera:screenToWorld(x, y, self.game)

    if self.game.event_spawner and self.game.event_spawner.handle_click then
        if self.game.event_spawner:handle_click(world_x, world_y, self.game) then
            return
        end
    end

    if self.game.entities and self.game.entities.handle_click then
        self.game.entities:handle_click(world_x, world_y, self.game)
    end
end

function InputController:update(dt)
end

return InputController
