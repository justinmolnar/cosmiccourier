-- views/SandboxSidebarView.lua
-- Thin wrapper that delegates drawing to SandboxSidebarManager.

local SandboxSidebarView = {}
SandboxSidebarView.__index = SandboxSidebarView

function SandboxSidebarView:new(game)
    local inst = setmetatable({}, SandboxSidebarView)
    inst.game = game
    return inst
end

function SandboxSidebarView:draw()
    local sc = self.game.sandbox_controller
    if not sc or not sc:isActive() then return end
    if sc.sidebar_manager then
        sc.sidebar_manager:draw()
    end
end

return SandboxSidebarView
