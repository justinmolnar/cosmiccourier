-- views/HUDStrip.lua
-- Vertical column of overlay-toggle buttons along the right edge of the world view.
-- Overlays registered by game systems; strip has no hardcoded game knowledge.

local HUDStrip = {}
HUDStrip.__index = HUDStrip

local BTN  = 36    -- button size (square)
local GAP  = 4     -- gap between buttons
local MX   = 8     -- margin from sidebar left edge
local TOP  = 48    -- y offset from top of screen

function HUDStrip:new()
    return setmetatable({ overlays = {} }, HUDStrip)
end

-- def: { id, icon, tooltip, key, field, locked }
--   field: game table key to toggle (e.g. "debug_district_overlay")
--   key:   optional keyboard shortcut (single char string)
function HUDStrip:registerOverlay(def)
    table.insert(self.overlays, def)
end

-- ─── Input ───────────────────────────────────────────────────────────────────

function HUDStrip:handleMouseDown(x, y, game)
    local bx, by = self:_origin(game)
    for _, ov in ipairs(self.overlays) do
        if x >= bx and x < bx + BTN and y >= by and y < by + BTN then
            if not ov.locked then
                game[ov.field] = not (game[ov.field] or false)
            end
            return true
        end
        by = by + BTN + GAP
    end
    return false
end

function HUDStrip:handleKey(key, game)
    for _, ov in ipairs(self.overlays) do
        if ov.key == key and not ov.locked then
            game[ov.field] = not (game[ov.field] or false)
            return true
        end
    end
    return false
end

-- ─── Draw ────────────────────────────────────────────────────────────────────

function HUDStrip:draw(game)
    if #self.overlays == 0 then return end
    local bx, by = self:_origin(game)
    local mx, my = love.mouse.getPosition()

    for _, ov in ipairs(self.overlays) do
        local active  = game[ov.field] or false
        local hovered = mx >= bx and mx < bx + BTN and my >= by and my < by + BTN

        -- Background
        if active then
            love.graphics.setColor(0.25, 0.45, 0.75, 0.95)
        elseif hovered then
            love.graphics.setColor(0.2, 0.2, 0.28, 0.95)
        else
            love.graphics.setColor(0.1, 0.1, 0.15, 0.88)
        end
        love.graphics.rectangle("fill", bx, by, BTN, BTN, 5)

        -- Border
        love.graphics.setColor(active and {0.5, 0.7, 1, 1} or {0.35, 0.35, 0.45, 1})
        love.graphics.rectangle("line", bx, by, BTN, BTN, 5)

        -- Icon
        love.graphics.setFont(game.fonts.emoji)
        love.graphics.setColor(ov.locked and {0.35, 0.35, 0.35, 1} or {1, 1, 1, 1})
        love.graphics.printf(ov.icon or "?", bx, by + 4, BTN, "center")

        -- Tooltip on hover
        if hovered and ov.tooltip then
            local tw = 160
            local tx = bx - tw - 6
            local ty = by
            love.graphics.setColor(0, 0, 0, 0.82)
            love.graphics.rectangle("fill", tx, ty, tw, 22, 3)
            love.graphics.setFont(game.fonts.ui_small)
            love.graphics.setColor(1, 1, 1)
            love.graphics.printf(ov.tooltip, tx + 4, ty + 4, tw - 8, "left")
        end

        by = by + BTN + GAP
    end
end

-- ─── Internal ────────────────────────────────────────────────────────────────

function HUDStrip:_origin(game)
    local sw = love.graphics.getWidth()
    return sw - BTN - MX, TOP
end

return HUDStrip
