-- views/ComponentRenderer.lua
-- Draws a flat list of component descriptors stacked vertically.
-- Has no knowledge of what the components represent.
--
-- draw(components, panel_x, panel_w, game) → total_h
-- hitTest(components, panel_x, panel_w, cx, cy) → component or nil

local CR = {}

local DataGrid = require("views.DataGrid")
local UIConfig = require("services.UIConfigService")

local ICON_SIZE    = 64
local ICON_SPACING = 12
local ICON_ROW_H   = ICON_SIZE + 20

-- Accordion section
local ACC_HEADER_H = 26
local ACC_PAD      = 6

-- Scope selector
local SSEL_H = 30

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
    elseif t == "custom" then
        local h = comp.h or 0
        if comp.draw_fn then comp.draw_fn(px, y, pw, h, game) end
        return h
    elseif t == "datagrid" then
        local h = DataGrid.totalHeight(comp, game)
        DataGrid.draw(comp, px, pw, p, y, game)
        return h
    elseif t == "accordion_section" then
        return CR._accordionSection(comp, px, pw, p, y, game)
    elseif t == "scope_selector" then
        return CR._scopeSelector(comp, px, pw, p, y, game)
    end
    return comp.h or 0
end

-- ─── Accordion section ──────────────────────────────────────────────────────

local function accordionCollapsed(comp, game)
    if not (comp.tab_id and comp.section_id and game) then return false end
    return UIConfig.getAccordion(game, comp.tab_id, comp.section_id).collapsed == true
end

local function accordionHeight(comp, game)
    if accordionCollapsed(comp, game) then return ACC_HEADER_H end
    local h = ACC_HEADER_H
    for _, child in ipairs(comp.children or {}) do
        h = h + CR._compHeight(child, game)
    end
    return h + ACC_PAD
end

-- Measure a single component's height without drawing. Mirrors _drawComp's
-- height calculation. Keeps accordion recursion accurate.
function CR._compHeight(comp, game)
    local t = comp.type
    if t == "button" then return (function()
        local lines = comp.lines
        if not lines or #lines == 0 then return 32 end
        local h = BTN_PAD
        for _, line in ipairs(lines) do
            h = h + (LINE_H[line.style or "body"] or 20)
        end
        return h
    end)()
    elseif t == "label"    then return comp.h or 24
    elseif t == "icon_row" then return comp.h or ICON_ROW_H
    elseif t == "divider"  then return comp.h or 6
    elseif t == "spacer"   then return comp.h or 8
    elseif t == "custom"   then return comp.h or 0
    elseif t == "datagrid" then return DataGrid.totalHeight(comp, game)
    elseif t == "accordion_section" then return accordionHeight(comp, game)
    elseif t == "scope_selector"    then return SSEL_H
    end
    return comp.h or 0
end

function CR._accordionSection(comp, px, pw, p, y, game)
    local collapsed = accordionCollapsed(comp, game)
    local x = px + p
    local w = pw - p * 2

    -- Header bar
    love.graphics.setColor(0.18, 0.18, 0.24)
    love.graphics.rectangle("fill", x, y, w, ACC_HEADER_H, 3)
    love.graphics.setColor(0.30, 0.30, 0.40)
    love.graphics.rectangle("line", x, y, w, ACC_HEADER_H, 3)

    love.graphics.setFont(game.fonts.ui)
    love.graphics.setColor(0.95, 0.95, 1.0)
    local glyph = collapsed and "▶" or "▼"
    love.graphics.print(glyph, x + 8, y + (ACC_HEADER_H - game.fonts.ui:getHeight()) * 0.5)

    local header = comp.header or comp.section_id or ""
    love.graphics.print(header, x + 28, y + (ACC_HEADER_H - game.fonts.ui:getHeight()) * 0.5)

    -- Optional badge (e.g., count) right-aligned
    if comp.badge then
        local ok, badge_val = pcall(comp.badge, game)
        if ok and badge_val ~= nil then
            local text = tostring(badge_val)
            love.graphics.setFont(game.fonts.ui_small)
            love.graphics.setColor(0.65, 0.70, 0.85)
            local tw = game.fonts.ui_small:getWidth(text)
            love.graphics.print(text, x + w - tw - 10,
                y + (ACC_HEADER_H - game.fonts.ui_small:getHeight()) * 0.5)
        end
    end

    if collapsed then return ACC_HEADER_H end

    -- Expanded: draw children stacked below the header
    local child_y = y + ACC_HEADER_H
    for _, child in ipairs(comp.children or {}) do
        local ch = CR._drawComp(child, px, pw, p, child_y, game)
        child_y = child_y + (ch or 0)
    end
    return (child_y - y) + ACC_PAD
end

-- ─── Scope selector ─────────────────────────────────────────────────────────

function CR._scopeSelector(comp, px, pw, p, y, game)
    local x = px + p
    local w = pw - p * 2
    local h = SSEL_H

    -- Background (subtle — this is a header affordance, not a call-to-action)
    love.graphics.setColor(0.14, 0.14, 0.20)
    love.graphics.rectangle("fill", x, y, w, h, 3)
    love.graphics.setColor(0.30, 0.30, 0.40)
    love.graphics.rectangle("line", x, y, w, h, 3)

    love.graphics.setFont(game.fonts.ui)
    local fh = game.fonts.ui:getHeight()
    local label = comp.label or "Scope:"
    local name  = comp.value_fn and comp.value_fn(game) or "—"

    love.graphics.setColor(0.65, 0.70, 0.85)
    love.graphics.print(label, x + 8, y + (h - fh) * 0.5)
    local prefix_w = game.fonts.ui:getWidth(label) + 14

    love.graphics.setColor(1.0, 1.0, 1.0)
    love.graphics.print(name, x + prefix_w, y + (h - fh) * 0.5)

    -- Chevron on the right
    love.graphics.setColor(0.7, 0.7, 0.85)
    love.graphics.print("▾", x + w - 20, y + (h - fh) * 0.5)

    return h
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
    local h        = buttonH(comp)
    local disabled = comp.disabled

    -- Disabled overlay
    if disabled then
        love.graphics.setColor(0.15, 0.15, 0.15, 0.6)
        love.graphics.rectangle("fill", px + p, y, pw - p * 2, h)
    -- Hover highlight (only when not disabled)
    elseif comp.hovered then
        love.graphics.setColor(1, 1, 0, 0.15)
        love.graphics.rectangle("fill", px + p, y, pw - p * 2, h)
    end

    love.graphics.setColor(disabled and 0.35 or 0.8, disabled and 0.35 or 0.8, disabled and 0.35 or 0.8, 0.4)
    love.graphics.rectangle("line", px + p, y + 1, pw - p * 2, h - 2)

    -- Draw each line
    local cursor = y + 4
    for _, line in ipairs(comp.lines or {}) do
        local style = line.style or "body"
        local lh    = LINE_H[style] or 20

        if disabled then
            love.graphics.setFont(style == "small" and game.fonts.ui_small or game.fonts.ui)
            love.graphics.setColor(0.4, 0.4, 0.4)
        elseif style == "small" then
            love.graphics.setFont(game.fonts.ui_small)
            love.graphics.setColor(0.8, 0.8, 0.5)
        elseif style == "muted" then
            love.graphics.setFont(game.fonts.ui_small)
            love.graphics.setColor(0.55, 0.55, 0.55)
        elseif style == "heading" then
            love.graphics.setFont(game.fonts.ui)
            love.graphics.setColor(0.7, 0.7, 0.9)
        elseif style == "warning" then
            love.graphics.setFont(game.fonts.ui)
            love.graphics.setColor(1.0, 0.65, 0.1)
        else
            love.graphics.setFont(game.fonts.ui)
            love.graphics.setColor(1, 1, 1)
        end

        local indent = (style == "body" or style == "heading" or style == "warning") and 4 or 10
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

function CR.hitTest(components, panel_x, panel_w, cx, cy, game)
    if not components then return nil end
    local cursor_y = 0
    local p = 10
    local _game = game

    for _, comp in ipairs(components) do
        local h

        if comp.type == "button" then
            h = buttonH(comp)
            if not comp.disabled
            and cy >= cursor_y and cy < cursor_y + h
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

        elseif comp.type == "custom" then
            h = comp.h or 0
            if comp.hit_fn and cy >= cursor_y and cy < cursor_y + h then
                local result = comp.hit_fn(panel_x, cursor_y, panel_w, h, cx, cy)
                if result then return result end
            end

        elseif comp.type == "datagrid" then
            -- Need game for totalHeight; pass through arg if provided.
            h = DataGrid.totalHeight(comp, _game)
            if cy >= cursor_y and cy < cursor_y + h then
                local hit = DataGrid.hitTest(comp, panel_x, panel_w, p,
                    cy - cursor_y, cx, cy, _game)
                if hit then return hit end
            end

        elseif comp.type == "accordion_section" then
            h = accordionHeight(comp, _game)
            -- Header: toggle
            if cy >= cursor_y and cy < cursor_y + ACC_HEADER_H then
                return { id = "accordion_toggle", data = {
                    tab_id = comp.tab_id, section_id = comp.section_id,
                }}
            end
            -- Body: recurse children at their own y offset
            if cy >= cursor_y + ACC_HEADER_H and cy < cursor_y + h
               and not accordionCollapsed(comp, _game) then
                local child_cursor = cursor_y + ACC_HEADER_H
                for _, child in ipairs(comp.children or {}) do
                    local child_h = CR._compHeight(child, _game)
                    if cy >= child_cursor and cy < child_cursor + child_h then
                        local hit = CR.hitTest({ child }, panel_x, panel_w,
                            cx, cy - child_cursor, _game)
                        if hit then return hit end
                        break
                    end
                    child_cursor = child_cursor + child_h
                end
            end

        elseif comp.type == "scope_selector" then
            h = SSEL_H
            if cy >= cursor_y and cy < cursor_y + h then
                return { id = "scope_select_open", data = {
                    sx = cx, sy = cy,
                }}
            end

        else
            h = comp.h or 0
        end

        cursor_y = cursor_y + (h or 0)
    end

    return nil
end

return CR
