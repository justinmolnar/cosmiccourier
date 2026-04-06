-- views/ContextMenu.lua
-- A screen-space right-click context menu.
-- Created by the input controller with a list of items and a screen position.
-- Dismissed on any outside click, Escape, or after an item is activated.
--
-- Item format:
--   { label = "...", icon = "🏢",  action = function(game) ... end }
--   { label = "...", disabled = true }   -- greyed-out unclickable row
--   { separator = true }                 -- horizontal divider

local ContextMenu = {}
ContextMenu.__index = ContextMenu

local W        = 200   -- menu width
local ROW_H    = 26    -- normal row height
local SEP_H    = 9     -- separator height
local PAD_X    = 10    -- left text indent
local RADIUS   = 4     -- corner radius
local SHADOW   = 3     -- drop-shadow offset

function ContextMenu:new(sx, sy, items)
    local self = setmetatable({}, ContextMenu)
    self.items  = items or {}
    self.hovered = nil

    -- Compute total height
    local h = 6
    for _, item in ipairs(self.items) do
        h = h + (item.separator and SEP_H or ROW_H)
    end
    h = h + 4

    -- Clamp to screen
    local sw = love.graphics.getWidth()
    local sh = love.graphics.getHeight()
    self.x = math.min(sx, sw - W - 6)
    self.y = math.min(sy, sh - h - 6)
    self.w = W
    self.h = h

    return self
end

-- Returns the screen-space rect for item i
function ContextMenu:_itemRect(i)
    local iy = self.y + 4
    for idx, item in ipairs(self.items) do
        local ih = item.separator and SEP_H or ROW_H
        if idx == i then
            return self.x + 1, iy, self.w - 2, ih
        end
        iy = iy + ih
    end
end

function ContextMenu:draw(game)
    local g = love.graphics

    -- Shadow
    g.setColor(0, 0, 0, 0.25)
    g.rectangle("fill", self.x + SHADOW, self.y + SHADOW, self.w, self.h, RADIUS)

    -- Background
    g.setColor(0.13, 0.13, 0.18, 0.97)
    g.rectangle("fill", self.x, self.y, self.w, self.h, RADIUS)

    -- Border
    g.setColor(0.35, 0.35, 0.5, 1)
    g.rectangle("line", self.x, self.y, self.w, self.h, RADIUS)

    local mx, my = love.mouse.getPosition()
    local font_ui    = game.fonts.ui
    local font_emoji = game.fonts.emoji

    local iy = self.y + 4
    for i, item in ipairs(self.items) do
        if item.separator then
            g.setColor(0.3, 0.3, 0.4, 0.8)
            local sy2 = iy + math.floor(SEP_H / 2)
            g.setLineWidth(1)
            g.line(self.x + 8, sy2, self.x + self.w - 8, sy2)
            iy = iy + SEP_H
        else
            local rx, ry, rw, rh = self.x + 1, iy, self.w - 2, ROW_H
            local hovered = not item.disabled
                         and mx >= rx and mx < rx + rw
                         and my >= ry and my < ry + rh

            if hovered then
                g.setColor(0.25, 0.45, 0.75, 0.9)
                g.rectangle("fill", rx, ry, rw, rh, 3)
            end

            local alpha = item.disabled and 0.35 or 1.0
            local tx = self.x + PAD_X
            if item.icon then
                -- Draw icon with emoji font then label offset
                g.setFont(font_emoji)
                g.setColor(1, 1, 1, alpha)
                g.print(item.icon, tx, iy + 4)
                tx = tx + 22
            end

            g.setFont(font_ui)
            g.setColor(1, 1, 1, alpha)
            g.print(item.label or "", tx, iy + 5)

            iy = iy + ROW_H
        end
    end

    g.setColor(1, 1, 1)
    g.setFont(game.fonts.ui)
end

-- Returns true if the click was handled (either hit an item or dismissed).
function ContextMenu:handle_mouse_down(sx, sy, button, game)
    -- Any click dismisses; left-click on an item also triggers it.
    local hit_item = nil
    if button == 1 then
        local iy = self.y + 4
        for _, item in ipairs(self.items) do
            if item.separator then
                iy = iy + SEP_H
            else
                if not item.disabled
                and sx >= self.x + 1 and sx < self.x + self.w - 1
                and sy >= iy and sy < iy + ROW_H then
                    hit_item = item
                end
                iy = iy + ROW_H
            end
        end
    end

    -- Always tell the caller to close the menu.
    -- Return the action so the caller can fire it after closing.
    return true, hit_item and hit_item.action or nil
end

return ContextMenu
