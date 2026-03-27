-- views/WorldSandboxSidebarView.lua
-- Thin delegate — all logic lives in WorldSandboxSidebarManager.

local WorldSandboxSidebarView = {}
WorldSandboxSidebarView.__index = WorldSandboxSidebarView

function WorldSandboxSidebarView:new(game)
    local inst = setmetatable({}, WorldSandboxSidebarView)
    inst.game = game
    return inst
end

function WorldSandboxSidebarView:draw()
    local wsc = self.game.world_sandbox_controller
    if not wsc or not wsc:isActive() then return end
    if wsc.sidebar_manager then
        wsc.sidebar_manager:draw()
    end
end

return WorldSandboxSidebarView
