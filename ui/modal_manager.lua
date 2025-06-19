-- ui/modal_manager.lua
-- Manages the active state of all modal windows.

local ModalManager = {}
ModalManager.__index = ModalManager

function ModalManager:new()
    local instance = setmetatable({}, ModalManager)
    instance.active_modal = nil
    return instance
end

function ModalManager:show(modal_instance)
    self.active_modal = modal_instance
end

function ModalManager:hide()
    self.active_modal = nil
end

function ModalManager:isActive()
    return self.active_modal ~= nil
end

function ModalManager:update(dt, game)
    if self:isActive() then
        self.active_modal:update(dt, game)
    end
end

function ModalManager:draw(game)
    if self:isActive() then
        self.active_modal:draw(game)
    end
end

function ModalManager:handle_mouse_down(x, y, game)
    if self:isActive() then
        -- MODIFIED: This now calls the correct function on the modal and passes the game object.
        return self.active_modal:handle_mouse_down(x, y, game)
    end
    return false
end

function ModalManager:handle_mouse_up(x, y, game)
    if self:isActive() then
        -- MODIFIED: This now correctly calls the active modal's function
        -- to handle events like releasing a pan/drag.
        return self.active_modal:handle_mouse_up(x, y, game)
    end
    return false
end

return ModalManager