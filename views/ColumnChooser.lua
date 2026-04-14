-- views/ColumnChooser.lua
-- Overlay popup used by DataGrid. Lists every column in the grid's source with
-- a checkbox; clicking toggles visibility (persisted via UIConfigService).
--
-- Rendered by UIManager after Panel so it sits on top; clicks are consumed
-- in UIController before panel hit-tests (same precedence as ContextMenu).

local UIConfig = require("services.UIConfigService")

local ColumnChooser = {}

local ITEM_H = 22
local PADDING = 8
local WIDTH  = 220

local function isColumnVisible(cfg, col)
    local override = cfg.hidden[col.id]
    if override == true then return false end
    if override == false then return true end
    return col.visible_default ~= false
end

function ColumnChooser.size(source)
    local h = PADDING * 2 + #source.columns * ITEM_H
    return WIDTH, h
end

function ColumnChooser.clampToScreen(x, y, w, h)
    local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()
    if x + w > sw - 4 then x = sw - w - 4 end
    if y + h > sh - 4 then y = sh - h - 4 end
    if x < 4 then x = 4 end
    if y < 4 then y = 4 end
    return x, y
end

function ColumnChooser.draw(chooser, game)
    local source = chooser.source
    local w, h = ColumnChooser.size(source)
    local x, y = ColumnChooser.clampToScreen(chooser.x, chooser.y, w, h)
    chooser._draw_x, chooser._draw_y, chooser._draw_w, chooser._draw_h = x, y, w, h

    -- Shadow + background
    love.graphics.setColor(0, 0, 0, 0.55)
    love.graphics.rectangle("fill", x + 2, y + 3, w, h, 3)
    love.graphics.setColor(0.16, 0.16, 0.22, 0.98)
    love.graphics.rectangle("fill", x, y, w, h, 3)
    love.graphics.setColor(0.45, 0.6, 1.0, 0.9)
    love.graphics.rectangle("line", x, y, w, h, 3)

    local cfg = UIConfig.getGridConfig(game, chooser.grid_id)

    love.graphics.setFont(game.fonts.ui_small)
    local row_y = y + PADDING
    for _, col in ipairs(source.columns) do
        local visible = isColumnVisible(cfg, col)

        -- Checkbox
        love.graphics.setColor(0.3, 0.3, 0.4)
        love.graphics.rectangle("fill", x + PADDING, row_y + 4, 14, 14)
        love.graphics.setColor(0.6, 0.6, 0.8)
        love.graphics.rectangle("line", x + PADDING, row_y + 4, 14, 14)
        if visible then
            love.graphics.setColor(0.4, 0.9, 0.4)
            love.graphics.rectangle("fill", x + PADDING + 3, row_y + 7, 8, 8)
        end

        -- Label
        love.graphics.setColor(0.95, 0.95, 1.0)
        local label = col.label
        if not label or label == "" or label == " " then label = col.id end
        love.graphics.print(label, x + PADDING + 22, row_y + 4)

        row_y = row_y + ITEM_H
    end
end

-- Returns col_id if the click landed on a row, else nil. Also returns a
-- "clicked_outside" bool if the click was outside the chooser's bounds.
function ColumnChooser.hitTest(chooser, mx, my)
    local x = chooser._draw_x or chooser.x
    local y = chooser._draw_y or chooser.y
    local w = chooser._draw_w or WIDTH
    local h = chooser._draw_h or (PADDING * 2 + #chooser.source.columns * ITEM_H)

    if mx < x or mx >= x + w or my < y or my >= y + h then
        return nil, true  -- outside
    end

    local row_y0 = y + PADDING
    local rel = my - row_y0
    if rel < 0 then return nil, false end
    local idx = math.floor(rel / ITEM_H) + 1
    local col = chooser.source.columns[idx]
    if col then return col.id, false end
    return nil, false
end

function ColumnChooser.toggle(chooser, col_id, game)
    local cfg = UIConfig.getGridConfig(game, chooser.grid_id)
    local col
    for _, c in ipairs(chooser.source.columns) do
        if c.id == col_id then col = c; break end
    end
    if not col then return end
    local currently_visible = isColumnVisible(cfg, col)
    UIConfig.setColumnHidden(game, chooser.grid_id, col_id, currently_visible)
end

return ColumnChooser
