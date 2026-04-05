-- views/ComponentRenderer.lua
-- Draws a flat list of component descriptors stacked vertically.
-- Has no knowledge of what the components represent.
--
-- draw(components, panel_x, panel_w, game) → total_h
-- hitTest(components, panel_x, panel_w, cx, cy) → component or nil

local CR = {}

local ICON_SIZE    = 64
local ICON_SPACING = 12
local ICON_ROW_H   = ICON_SIZE + 20

-- Line heights per style (must match font sizes in game.fonts)
local LINE_H = { body = 20, small = 16, heading = 22, muted = 20 }
local BTN_PAD = 8   -- total vertical padding inside a button (top+bottom)

-- ─── Button height (shared by draw and hitTest) ───────────────────────────────

local function buttonH(comp)
    local lines = comp.lines
    if not lines or #lines == 0 then return 32 end
    local h = BTN_PAD
    for _, line in ipairs(lines) do
        h = h + (LINE_H[line.style or "body"] or 20)
    end
    return h
end

-- ─── Draw ────────────────────────────────────────────────────────────────────

function CR.draw(components, panel_x, panel_w, game)
    if not components then return 0 end
    local cursor_y = 0
    local p = 10

    for _, comp in ipairs(components) do
        local h = CR._drawComp(comp, panel_x, panel_w, p, cursor_y, game)
        cursor_y = cursor_y + h
    end
    return cursor_y
end

function CR._drawComp(comp, px, pw, p, y, game)
    local t = comp.type

    if t == "label" then
        return CR._label(comp, px, pw, p, y, game)
    elseif t == "button" then
        return CR._button(comp, px, pw, p, y, game)
    elseif t == "icon_row" then
        return CR._iconRow(comp, px, pw, p, y, game)
    elseif t == "divider" then
        love.graphics.setColor(0.3, 0.3, 0.4)
        love.graphics.rectangle("fill", px + p, y + 2, pw - p * 2, 1)
        return comp.h or 6
    elseif t == "spacer" then
        return comp.h or 8
    end
    return comp.h or 0
end

function CR._label(comp, px, pw, p, y, game)
    local h     = comp.h or 24
    local style = comp.style or "body"

    love.graphics.setFont(style == "small" and game.fonts.ui_small or game.fonts.ui)

    if style == "heading" then
        love.graphics.setColor(0.7, 0.7, 0.9)
        love.graphics.print(comp.text or "", px + p, y + 4)
        love.graphics.setColor(0.4, 0.4, 0.6)
        love.graphics.rectangle("fill", px + p, y + h - 2, pw - p * 2, 1)
    elseif style == "muted" then
        love.graphics.setColor(0.5, 0.5, 0.5)
        love.graphics.print(comp.text or "", px + p, y + 4)
    else
        love.graphics.setColor(1, 1, 1)
        love.graphics.print(comp.text or "", px + p, y + 4)
    end
    return h
end

function CR._button(comp, px, pw, p, y, game)
    local h = buttonH(comp)

    -- Hover highlight
    if comp.hovered then
        love.graphics.setColor(1, 1, 0, 0.15)
        love.graphics.rectangle("fill", px + p, y, pw - p * 2, h)
    end

    love.graphics.setColor(0.8, 0.8, 0.8, 0.4)
    love.graphics.rectangle("line", px + p, y + 1, pw - p * 2, h - 2)

    -- Draw each line
    local cursor = y + 4
    for _, line in ipairs(comp.lines or {}) do
        local style = line.style or "body"
        local lh    = LINE_H[style] or 20

        if style == "small" then
            love.graphics.setFont(game.fonts.ui_small)
            love.graphics.setColor(0.8, 0.8, 0.5)
        elseif style == "muted" then
            love.graphics.setFont(game.fonts.ui_small)
            love.graphics.setColor(0.55, 0.55, 0.55)
        elseif style == "heading" then
            love.graphics.setFont(game.fonts.ui)
            love.graphics.setColor(0.7, 0.7, 0.9)
        else
            love.graphics.setFont(game.fonts.ui)
            love.graphics.setColor(1, 1, 1)
        end

        local indent = (style == "body" or style == "heading") and 4 or 10
        love.graphics.printf(line.text or "", px + p + indent, cursor, pw - p * 2 - indent - 4, "left")
        cursor = cursor + lh
    end

    return h
end

function CR._iconRow(comp, px, pw, p, y, game)
    local h = comp.h or ICON_ROW_H
    local icon_x = px + p + 5

    for _, item in ipairs(comp.items or {}) do
        love.graphics.setColor(0.3, 0.3, 0.35)
        love.graphics.rectangle("fill", icon_x, y + 4, ICON_SIZE, ICON_SIZE)
        love.graphics.setColor(1, 1, 1)
        love.graphics.rectangle("line", icon_x, y + 4, ICON_SIZE, ICON_SIZE)

        love.graphics.setFont(game.fonts.emoji_ui)
        love.graphics.printf(item.icon or "?", icon_x, y + 8, ICON_SIZE, "center")

        local label_h = 16
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.rectangle("fill", icon_x + 1, y + 4 + ICON_SIZE - label_h, ICON_SIZE - 2, label_h - 1)
        love.graphics.setFont(game.fonts.ui_small)
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf(item.name or "", icon_x, y + 4 + ICON_SIZE - label_h + 2, ICON_SIZE, "center")

        icon_x = icon_x + ICON_SIZE + ICON_SPACING
    end

    return h
end

-- ─── Hit test ────────────────────────────────────────────────────────────────

function CR.hitTest(components, panel_x, panel_w, cx, cy)
    if not components then return nil end
    local cursor_y = 0
    local p = 10

    for _, comp in ipairs(components) do
        local h

        if comp.type == "button" then
            h = buttonH(comp)
            if cy >= cursor_y and cy < cursor_y + h
            and cx >= panel_x + p and cx < panel_x + panel_w - p then
                return comp
            end

        elseif comp.type == "icon_row" then
            h = comp.h or ICON_ROW_H
            if cy >= cursor_y and cy < cursor_y + (ICON_SIZE + 4) then
                local icon_x = panel_x + p + 5
                for _, item in ipairs(comp.items or {}) do
                    if cx >= icon_x and cx < icon_x + ICON_SIZE then
                        return item
                    end
                    icon_x = icon_x + ICON_SIZE + ICON_SPACING
                end
            end

        else
            h = comp.h or 0
        end

        cursor_y = cursor_y + (h or 0)
    end

    return nil
end

return CR
