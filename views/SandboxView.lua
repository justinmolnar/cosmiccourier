-- views/SandboxView.lua
-- Renders the sandbox map viewport (right of the sidebar).

local SandboxView = {}
SandboxView.__index = SandboxView

function SandboxView:new(game)
    local inst = setmetatable({}, SandboxView)
    inst.game = game
    return inst
end

function SandboxView:draw()
    local game  = self.game
    local sc    = game.sandbox_controller
    if not sc or not sc:isActive() then return end

    local C        = game.C
    local sidebar_w = C.UI.SIDEBAR_WIDTH
    local sw, sh   = love.graphics.getDimensions()
    local vw       = sw - sidebar_w

    -- Viewport background
    love.graphics.setScissor(sidebar_w, 0, vw, sh)
    love.graphics.setColor(0.05, 0.05, 0.08)
    love.graphics.rectangle("fill", sidebar_w, 0, vw, sh)

    if sc.sandbox_map and sc.sandbox_map.grid and #sc.sandbox_map.grid > 0 then
        love.graphics.push()
        love.graphics.translate(sidebar_w + vw / 2, sh / 2)
        love.graphics.scale(sc.camera.scale, sc.camera.scale)
        love.graphics.translate(-sc.camera.x, -sc.camera.y)
        sc:drawMap()
        love.graphics.pop()
        sc:drawModal()   -- screen-space overlay, drawn after camera transform is restored
    else
        love.graphics.setColor(0.4, 0.4, 0.5)
        love.graphics.setFont(game.fonts.ui)
        love.graphics.printf("Adjust parameters and press Generate ->",
            sidebar_w, sh / 2 - 10, vw, "center")
    end

    -- Status bar
    love.graphics.setScissor(sidebar_w, sh - 22, vw, 22)
    love.graphics.setColor(0, 0, 0, 0.75)
    love.graphics.rectangle("fill", sidebar_w, sh - 22, vw, 22)
    love.graphics.setColor(0.6, 0.6, 0.7)
    love.graphics.setFont(game.fonts.ui_small)
    local status = "SANDBOX  |  " .. (sc.status_text or "") ..
                   "  |  RMB pan | Wheel zoom | F9 close"
    love.graphics.print(status, sidebar_w + 8, sh - 18)

    love.graphics.setScissor()
    love.graphics.setColor(1, 1, 1)
end

return SandboxView
