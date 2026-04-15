-- views/FilterPopup.lua
-- Anchored overlay for DataGrid's per-column value filter. Shows a search
-- input (popup-local, narrows the visible list) plus a scrollable checkbox
-- list of distinct column values. Checking/unchecking writes straight through
-- to UIConfigService.setFilterValues.
--
-- Shape is intentionally parallel to views/ColumnChooser.lua — same anchored-
-- overlay style, same clampToScreen, same "UIController owns outside-click"
-- contract. No modal manager.

local UIConfig      = require("services.UIConfigService")
local ColumnChooser = require("views.ColumnChooser")   -- reused for clampToScreen
local utf8          = require("utf8")

local FilterPopup = {}

-- Tunables (module-level, matches DataGrid's pattern).
FilterPopup.WIDTH           = 240
FilterPopup.HEADER_H        = 26
FilterPopup.SEARCH_H        = 24
FilterPopup.ITEM_H          = 22
FilterPopup.MAX_VISIBLE     = 14   -- rows before the list scrolls
FilterPopup.PADDING         = 6
FilterPopup.CLEAR_BTN_W     = 48
FilterPopup.CHECK_SIZE      = 14

-- ─── Derived layout ──────────────────────────────────────────────────────────

local function filteredValues(popup)
    local q = popup.search and popup.search:lower() or ""
    if q == "" then return popup.values end
    local out = {}
    for _, v in ipairs(popup.values) do
        if v:lower():find(q, 1, true) then out[#out + 1] = v end
    end
    return out
end

function FilterPopup.size(popup)
    local list    = filteredValues(popup)
    local visible = math.min(#list, FilterPopup.MAX_VISIBLE)
    visible       = math.max(visible, 1)
    local w = FilterPopup.WIDTH
    local h = FilterPopup.HEADER_H
            + FilterPopup.SEARCH_H
            + visible * FilterPopup.ITEM_H
            + FilterPopup.PADDING * 2
    return w, h
end

local function listBounds(popup, x, y)
    local lx = x + FilterPopup.PADDING
    local ly = y + FilterPopup.HEADER_H + FilterPopup.SEARCH_H + FilterPopup.PADDING
    local lw = FilterPopup.WIDTH - FilterPopup.PADDING * 2
    local list   = filteredValues(popup)
    local visible = math.min(#list, FilterPopup.MAX_VISIBLE)
    visible       = math.max(visible, 1)
    local lh = visible * FilterPopup.ITEM_H
    return lx, ly, lw, lh, list, visible
end

-- Build the set of currently-whitelisted values for O(1) checkbox lookup.
local function whitelistSet(game, grid_id, col_id)
    local f = UIConfig.getFilter(game, grid_id, col_id)
    local set = {}
    for _, v in ipairs(f.values or {}) do set[v] = true end
    return set
end

-- ─── Drawing ─────────────────────────────────────────────────────────────────

local function drawHeader(popup, x, y, w, game)
    -- Bar
    love.graphics.setColor(0.20, 0.22, 0.30)
    love.graphics.rectangle("fill", x, y, w, FilterPopup.HEADER_H, 3, 3)
    -- Title ("Filter: <col.label>" if resolvable)
    local col
    for _, c in ipairs(popup.source.columns) do
        if c.id == popup.col_id then col = c; break end
    end
    love.graphics.setFont(game.fonts.ui_small)
    love.graphics.setColor(0.95, 0.95, 1.0)
    local title = "Filter: " .. ((col and (col.label or col.id)) or popup.col_id)
    love.graphics.printf(title,
        x + FilterPopup.PADDING, y + (FilterPopup.HEADER_H - game.fonts.ui_small:getHeight()) * 0.5,
        w - FilterPopup.PADDING * 2 - FilterPopup.CLEAR_BTN_W - 4, "left")

    -- "Clear" button (right-aligned)
    local bx = x + w - FilterPopup.PADDING - FilterPopup.CLEAR_BTN_W
    local by = y + 3
    local bw, bh = FilterPopup.CLEAR_BTN_W, FilterPopup.HEADER_H - 6
    popup._clear_bounds = { x = bx, y = by, w = bw, h = bh }
    local active = UIConfig.isFilterActive(game, popup.grid_id, popup.col_id)
    love.graphics.setColor(active and {0.60, 0.25, 0.25} or {0.25, 0.25, 0.30})
    love.graphics.rectangle("fill", bx, by, bw, bh, 2)
    love.graphics.setColor(active and {1, 1, 1} or {0.7, 0.7, 0.8})
    love.graphics.printf("Clear", bx, by + (bh - game.fonts.ui_small:getHeight()) * 0.5,
        bw, "center")
end

local function drawSearch(popup, x, y, w, game)
    local sx = x + FilterPopup.PADDING
    local sy = y + FilterPopup.HEADER_H + 2
    local sw = w - FilterPopup.PADDING * 2
    local sh = FilterPopup.SEARCH_H - 4
    popup._search_bounds = { x = sx, y = sy, w = sw, h = sh }

    if popup.search_focused then
        love.graphics.setColor(0.05, 0.08, 0.15)
    else
        love.graphics.setColor(0.08, 0.08, 0.12)
    end
    love.graphics.rectangle("fill", sx, sy, sw, sh, 2)
    love.graphics.setColor(popup.search_focused and {0.45, 0.65, 1.0} or {0.3, 0.3, 0.4})
    love.graphics.rectangle("line", sx, sy, sw, sh, 2)

    love.graphics.setFont(game.fonts.ui_small)
    local text = popup.search or ""
    local fh   = game.fonts.ui_small:getHeight()
    local ty   = sy + (sh - fh) * 0.5
    if text == "" and not popup.search_focused then
        love.graphics.setColor(0.5, 0.5, 0.55)
        love.graphics.printf("Search values…", sx + 4, ty, sw - 8, "left")
    else
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf(text, sx + 4, ty, sw - 8, "left")
    end

    if popup.search_focused then
        local tw    = game.fonts.ui_small:getWidth(text)
        local cx    = math.min(sx + sw - 3, sx + 4 + tw)
        local blink = math.floor(love.timer.getTime() * 2) % 2 == 0
        if blink then
            love.graphics.setColor(1, 1, 1)
            love.graphics.line(cx, sy + 2, cx, sy + sh - 2)
        end
    end
end

local function drawList(popup, x, y, w, game)
    local lx, ly, lw, lh, list, visible = listBounds(popup, x, y)
    love.graphics.setColor(0.10, 0.10, 0.14)
    love.graphics.rectangle("fill", lx, ly, lw, lh)

    local set = whitelistSet(game, popup.grid_id, popup.col_id)
    popup._row_bounds = {}
    local first = math.max(1, math.min(#list - visible + 1, (popup.scroll or 0) + 1))
    love.graphics.setFont(game.fonts.ui_small)
    for i = 0, visible - 1 do
        local idx = first + i
        local val = list[idx]
        if not val then break end
        local ry = ly + i * FilterPopup.ITEM_H
        -- Hover tint
        local mx, my = love.mouse.getPosition()
        if mx >= lx and mx < lx + lw and my >= ry and my < ry + FilterPopup.ITEM_H then
            love.graphics.setColor(0.20, 0.28, 0.42, 0.55)
            love.graphics.rectangle("fill", lx, ry, lw, FilterPopup.ITEM_H)
        end

        -- Checkbox
        local cb_x = lx + 4
        local cb_y = ry + (FilterPopup.ITEM_H - FilterPopup.CHECK_SIZE) * 0.5
        love.graphics.setColor(0.30, 0.30, 0.40)
        love.graphics.rectangle("fill", cb_x, cb_y, FilterPopup.CHECK_SIZE, FilterPopup.CHECK_SIZE)
        love.graphics.setColor(0.60, 0.60, 0.80)
        love.graphics.rectangle("line", cb_x, cb_y, FilterPopup.CHECK_SIZE, FilterPopup.CHECK_SIZE)
        if set[val] then
            love.graphics.setColor(0.40, 0.90, 0.40)
            love.graphics.rectangle("fill", cb_x + 3, cb_y + 3, FilterPopup.CHECK_SIZE - 6, FilterPopup.CHECK_SIZE - 6)
        end

        -- Label
        love.graphics.setColor(0.95, 0.95, 1.0)
        love.graphics.printf(val,
            cb_x + FilterPopup.CHECK_SIZE + 6,
            ry + (FilterPopup.ITEM_H - game.fonts.ui_small:getHeight()) * 0.5,
            lw - (cb_x + FilterPopup.CHECK_SIZE + 6 - lx) - 4, "left")

        popup._row_bounds[#popup._row_bounds + 1] = {
            x = lx, y = ry, w = lw, h = FilterPopup.ITEM_H, value = val,
        }
    end

    -- Scrollbar hint when there are more values than visible slots.
    if #list > visible then
        local track_x = lx + lw - 3
        love.graphics.setColor(0.25, 0.25, 0.30)
        love.graphics.rectangle("fill", track_x, ly, 2, lh)
        local thumb_h = math.max(8, lh * visible / #list)
        local thumb_y = ly + (lh - thumb_h) * ((first - 1) / math.max(1, #list - visible))
        love.graphics.setColor(0.5, 0.6, 0.9)
        love.graphics.rectangle("fill", track_x, thumb_y, 2, thumb_h)
    end
end

function FilterPopup.draw(popup, game)
    local w, h = FilterPopup.size(popup)
    local x, y = ColumnChooser.clampToScreen(popup.x, popup.y, w, h)
    popup._draw_x, popup._draw_y, popup._draw_w, popup._draw_h = x, y, w, h

    -- Shadow + background
    love.graphics.setColor(0, 0, 0, 0.55)
    love.graphics.rectangle("fill", x + 2, y + 3, w, h, 3)
    love.graphics.setColor(0.16, 0.16, 0.22, 0.98)
    love.graphics.rectangle("fill", x, y, w, h, 3)
    love.graphics.setColor(0.45, 0.60, 1.0, 0.9)
    love.graphics.rectangle("line", x, y, w, h, 3)

    drawHeader(popup, x, y, w, game)
    drawSearch(popup, x, y, w, game)
    drawList  (popup, x, y, w, game)
end

-- ─── Hit testing ─────────────────────────────────────────────────────────────
-- Returns (kind, payload). Kinds: "outside", "close", "clear", "search",
-- "toggle_value" (payload = value string), nil (inside but nothing hit).

function FilterPopup.hitTest(popup, mx, my)
    local x = popup._draw_x or popup.x
    local y = popup._draw_y or popup.y
    local w = popup._draw_w or FilterPopup.WIDTH
    local h = popup._draw_h or FilterPopup.size(popup)

    if mx < x or mx >= x + w or my < y or my >= y + h then
        return "outside", nil
    end

    -- Clear button
    local cb = popup._clear_bounds
    if cb and mx >= cb.x and mx < cb.x + cb.w and my >= cb.y and my < cb.y + cb.h then
        return "clear", nil
    end

    -- Search field
    local sb = popup._search_bounds
    if sb and mx >= sb.x and mx < sb.x + sb.w and my >= sb.y and my < sb.y + sb.h then
        return "search", nil
    end

    -- List rows
    for _, r in ipairs(popup._row_bounds or {}) do
        if mx >= r.x and mx < r.x + r.w and my >= r.y and my < r.y + r.h then
            return "toggle_value", r.value
        end
    end

    return nil, nil
end

-- Toggle a value in the whitelist.
function FilterPopup.toggleValue(popup, value, game)
    local f = UIConfig.getFilter(game, popup.grid_id, popup.col_id)
    local values = {}
    local found = false
    for _, v in ipairs(f.values or {}) do
        if v == value then found = true
        else values[#values + 1] = v end
    end
    if not found then values[#values + 1] = value end
    UIConfig.setFilterValues(game, popup.grid_id, popup.col_id, values)
end

-- Wipe both query and whitelist for this column.
function FilterPopup.clearAll(popup, game)
    UIConfig.clearFilter(game, popup.grid_id, popup.col_id)
end

-- ─── Popup-local search input ───────────────────────────────────────────────

function FilterPopup.handleTextInput(popup, text)
    if not popup.search_focused then return false end
    popup.search = (popup.search or "") .. (text or "")
    popup.scroll = 0
    return true
end

function FilterPopup.handleKeyPressed(popup, key)
    if not popup.search_focused then return false end
    if key == "backspace" then
        local s = popup.search or ""
        local offset = utf8.offset(s, -1)
        popup.search = offset and s:sub(1, offset - 1) or ""
        popup.scroll = 0
        return true
    elseif key == "escape" then
        popup.search_focused = false
        return true
    elseif key == "return" or key == "kpenter" or key == "tab" then
        popup.search_focused = false
        return true
    end
    return false
end

-- Mouse wheel scroll within the list.
function FilterPopup.wheelmoved(popup, dy)
    local list    = filteredValues(popup)
    local visible = math.min(#list, FilterPopup.MAX_VISIBLE)
    local max_scroll = math.max(0, #list - visible)
    popup.scroll = math.max(0, math.min(max_scroll, (popup.scroll or 0) - dy))
end

return FilterPopup
