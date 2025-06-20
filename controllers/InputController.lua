-- controllers/InputController.lua
local InputController = {}
InputController.__index = InputController

function InputController:new(game_instance)
    local instance = setmetatable({}, InputController)
    instance.Game = game_instance
    
    local UIController = require("controllers.UIController")
    instance.ui_controller = UIController:new(game_instance)
    
    return instance
end

function InputController:keypressed(key)
    if key == "`" then
        self.Game.debug_mode = not self.Game.debug_mode
        print("Debug mode set to: " .. tostring(self.Game.debug_mode))
    elseif key == "-" then
        self.Game.state.money = self.Game.state.money - 10000
        print("DEBUG: Removed 10,000 money.")
    elseif key == "=" then
        self.Game.state.money = self.Game.state.money + 10000
        print("DEBUG: Added 10,000 money.")
    end
end

function InputController:mousewheelmoved(x, y)
    -- CORRECTED: Use ui_manager
    self.Game.ui_manager:handle_scroll(y)
end

function InputController:mousepressed(x, y, button)
    local Game = self.Game
    
    if button == 1 and Game.ui_manager.modal_manager:isActive() then
        local modal = Game.ui_manager.modal_manager.active_modal
        if not (x > modal.x and x < modal.x + modal.w and y > modal.y and y < modal.y + modal.h) then
            Game.ui_manager.modal_manager:hide()
            return 
        end
    end

    if Game.ui_manager:handle_mouse_down(x, y, button, Game) then
        return
    end

    if x < Game.C.UI.SIDEBAR_WIDTH then
        if self.ui_controller:handleMouseDown(x, y, button) then
            return
        end
    end

    if button == 1 then
        if Game.zoom_controls:handle_click(x, y, Game) then
            return
        end
        
        if x >= Game.C.UI.SIDEBAR_WIDTH then
            local game_world_w = love.graphics.getWidth() - Game.C.UI.SIDEBAR_WIDTH
            local game_world_h = love.graphics.getHeight()
            
            local screen_x = x - (Game.C.UI.SIDEBAR_WIDTH + game_world_w / 2)
            local screen_y = y - (game_world_h / 2)
            local scaled_x = screen_x / Game.camera.scale
            local scaled_y = screen_y / Game.camera.scale
            local world_x = scaled_x + Game.camera.x
            local world_y = scaled_y + Game.camera.y
            
            local event_handled = Game.event_spawner:handle_click(world_x, world_y, Game)
            if not event_handled then
                Game.entities:handle_click(world_x, world_y, Game)
            end
        end
    end
end

function InputController:mousereleased(x, y, button)
    local Game = self.Game
    -- CORRECTED: Use ui_manager
    if Game.ui_manager.modal_manager:handle_mouse_up(x, y, Game) then
        return
    end
    Game.ui_manager:handle_mouse_up(x, y, button)
end

return InputController