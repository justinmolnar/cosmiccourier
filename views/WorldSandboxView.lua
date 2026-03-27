-- views/WorldSandboxView.lua
-- Renders the world sandbox viewport (image + status bar).

local WorldSandboxView = {}
WorldSandboxView.__index = WorldSandboxView

function WorldSandboxView:new(game)
    local inst = setmetatable({}, WorldSandboxView)
    inst.game = game
    return inst
end

function WorldSandboxView:draw()
    local wsc = self.game.world_sandbox_controller
    if not wsc or not wsc:isActive() then return end

    local C         = self.game.C
    local sw, sh    = love.graphics.getDimensions()
    local sidebar_w = C.UI.SIDEBAR_WIDTH
    local vw        = sw - sidebar_w

    -- Viewport background
    love.graphics.setScissor(sidebar_w, 0, vw, sh)
    love.graphics.setColor(0.04, 0.04, 0.07)
    love.graphics.rectangle("fill", sidebar_w, 0, vw, sh)

    if wsc.world_image then
        local ts = C.MAP.TILE_SIZE
        love.graphics.push()
        love.graphics.translate(sidebar_w + vw / 2, sh / 2)
        love.graphics.scale(wsc.camera.scale, wsc.camera.scale)
        love.graphics.translate(-wsc.camera.x, -wsc.camera.y)
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(wsc.world_image, 0, 0, 0, ts, ts)
        love.graphics.pop()
    else
        love.graphics.setColor(0.4, 0.4, 0.5)
        love.graphics.setFont(self.game.fonts.ui)
        love.graphics.printf("Press Generate →", sidebar_w, sh / 2 - 10, vw, "center")
    end

    -- Status bar
    love.graphics.setScissor(sidebar_w, sh - 22, vw, 22)
    love.graphics.setColor(0, 0, 0, 0.75)
    love.graphics.rectangle("fill", sidebar_w, sh - 22, vw, 22)
    love.graphics.setColor(0.6, 0.6, 0.7)
    love.graphics.setFont(self.game.fonts.ui_small)
    love.graphics.print(wsc.status_text or "WORLD GEN  |  F8 close", sidebar_w + 8, sh - 18)

    love.graphics.setScissor()
    love.graphics.setColor(1, 1, 1)
end

return WorldSandboxView
