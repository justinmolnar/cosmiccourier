-- views/components/ZoomControls.lua
-- Passive zoom-level indicator (scroll wheel handles zoom; buttons removed).

local ZoomControls = {}
ZoomControls.__index = ZoomControls

function ZoomControls:new(C)
    local instance = setmetatable({}, ZoomControls)
    instance.C = C
    return instance
end

function ZoomControls:update(game)
    -- Nothing to update; zoom is handled by InputController scroll wheel.
end

function ZoomControls:draw(game)
    local C    = self.C
    local cs   = game.camera.scale
    local font = game.fonts and game.fonts.ui_small
    if not font then return end
    local screen_w = love.graphics.getWidth()
    local label = string.format("%.1f×", cs)
    local tw    = font:getWidth(label)
    local margin = C.ZOOM.ZOOM_BUTTON_MARGIN
    local x = screen_w - tw - margin - 4
    local y = love.graphics.getHeight() - font:getHeight() - margin
    love.graphics.setFont(font)
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", x - 3, y - 2, tw + 6, font:getHeight() + 4, 3)
    love.graphics.setColor(1, 1, 1, 0.85)
    love.graphics.print(label, x, y)
    love.graphics.setColor(1, 1, 1)
end

-- handle_click kept as no-op for any lingering callers
function ZoomControls:handle_click(x, y, game)
    return false
end

return ZoomControls
