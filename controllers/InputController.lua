-- controllers/InputController.lua
-- Complete input controller with debug menu integration

local InputController = {}
InputController.__index = InputController

function InputController:new(game)
    local instance = setmetatable({}, InputController)
    instance.game = game
    
    -- Initialize debug menu controller
    local DebugMenuController = require("controllers.DebugMenuController")
    instance.debug_menu_controller = DebugMenuController:new(game)
    
    -- Initialize debug menu view
    local DebugMenuView = require("views.components.DebugMenuView")
    instance.debug_menu_view = DebugMenuView:new(instance.debug_menu_controller, game)
    
    return instance
end

function InputController:keypressed(key)
    -- Check if debug menu wants to handle the key first
    if self.debug_menu_controller:isVisible() then
        if self.debug_menu_controller:handle_key_pressed(key) then
            return
        end
    end
    
    -- Handle debug menu toggle
    if key == "`" then
        self.debug_menu_controller:toggle()
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

        -- TEMPORARY DEBUG KEY
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
    -- Check if debug menu wants to handle text input
    if self.debug_menu_controller:isVisible() then
        if self.debug_menu_controller:handle_text_input(text) then
            return
        end
    end
end

function InputController:mousewheelmoved(x, y)
    local mx, my = love.mouse.getPosition()
    
    -- Check debug menu first, but only if mouse is over the menu
    if self.debug_menu_controller:isVisible() then
        if self.debug_menu_controller:handle_scroll(mx, my, y) then
            return
        end
    end
    
    -- Handle UI scrolling if it exists
    if self.game.ui_manager and self.game.ui_manager.handle_scroll then
        self.game.ui_manager:handle_scroll(y)
    end
end

function InputController:mousepressed(x, y, button)
    -- Check debug menu first
    if self.debug_menu_controller:isVisible() then
        if self.debug_menu_controller:handle_mouse_down(x, y, button) then
            return
        end
    end

    -- This is the main UI controller, which now has the corrected logic from Fix #1
    local UIController = require("controllers.UIController")
    local ui_controller = UIController:new(self.game)
    if ui_controller:handleMouseDown(x, y, button) then
        return
    end
    
    -- Handle zoom controls if they exist
    if self.game.zoom_controls and self.game.zoom_controls.handle_click then
        if self.game.zoom_controls:handle_click(x, y, self.game) then
            return
        end
    end

    if button == 1 then -- Left mouse button
        local sidebar_w = self.game.C.UI.SIDEBAR_WIDTH
        
        if x < sidebar_w then
            -- This area is now fully handled by the UIController above
        else
            -- This is the crucial part that calls our new helper function
            self:handleGameWorldClick(x, y)
        end
    end
end

function InputController:mousereleased(x, y, button)
    self.debug_menu_controller:handle_mouse_up(x, y, button)
    
    if self.game.ui_manager and self.game.ui_manager.handle_mouse_up then
        self.game.ui_manager:handle_mouse_up(x, y, button)
    end
end

function InputController:handleSidebarClick(x, y)
    -- Sidebar click handling - add your existing sidebar logic here
end

function InputController:handleGameWorldClick(x, y)
    -- Convert screen coordinates to world coordinates
    local world_x, world_y = self.game.camera:screenToWorld(x, y, self.game)

    -- Handle event spawner clicks with the correct world coordinates
    if self.game.event_spawner and self.game.event_spawner.handle_click then
        if self.game.event_spawner:handle_click(world_x, world_y, self.game) then
            return
        end
    end

    -- Handle entity selection with the correct world coordinates
    if self.game.entities and self.game.entities.handle_click then
        self.game.entities:handle_click(world_x, world_y, self.game)
    end
end

function InputController:update(dt)
    -- Update debug menu controller
    self.debug_menu_controller:update(dt)
end

-- Getter methods for other systems to access debug menu
function InputController:getDebugMenuView()
    return self.debug_menu_view
end

function InputController:isDebugMenuVisible()
    return self.debug_menu_controller:isVisible()
end

function InputController:getDebugMenuController()
    return self.debug_menu_controller
end

return InputController