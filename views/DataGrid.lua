-- views/DataGrid.lua
-- Data-driven, entity-agnostic table component. See docs/datagrid-plan.md.
-- A `datagrid` ComponentRenderer component takes a `source` module with:
--   id, items_fn, row_id, hover_entity, on_row_click, empty_message,
--   default_sort, columns
-- and renders a sortable, resizable, column-choosable table of items.

local UIConfig     = require("services.UIConfigService")
local FilterSvc    = require("services.DataGridFilterService")
local utf8         = require("utf8")

local DataGrid = {}

DataGrid.HEADER_H    = 24
DataGrid.ROW_H       = 22
DataGrid.RESIZE_HOT  = 5
DataGrid.CHOOSER_BTN_W = 20
DataGrid.ROW_PAD_X   = 4

-- Filter row (DevExpress-style search/select row under the header).
DataGrid.FILTER_ROW_H        = 26
DataGrid.FILTER_FUNNEL_W     = 16
DataGrid.FILTER_INPUT_PAD_X  = 4

-- Per-grid ephemeral state (resize drag, hovered row, hovered resize zone).
-- Persisted state (widths, hidden, sort, filters) lives in game.state.ui_config.
local _grid_state = {}

-- Single globally-focused filter input (one at a time across all grids).
DataGrid._focused_filter = nil   -- { grid_id, col_id, buffer }
-- Filter popup overlay state (same "only one open" rule as the column chooser).
DataGrid.filter_popup = nil      -- { grid_id, source, col_id, x, y, ... }

local function getState(grid_id)
    _grid_state[grid_id] = _grid_state[grid_id] or {
        resize       = nil,        -- { col_id, start_mx, start_w } while dragging
        hover_row_id = nil,        -- set by UIManager from last-frame hit
        hover_resize = nil,        -- col_id whose right-edge is hovered
    }
    return _grid_state[grid_id]
end

DataGrid.getState = getState

-- Chooser popup overlay state (only one grid can have it open at a time).
DataGrid.chooser = nil    -- { grid_id, source, x, y, w, h }

-- ─── Column resolution ───────────────────────────────────────────────────────

-- Returns { {col, width}, ... } for visible columns in definition order.
function DataGrid.effectiveColumns(source, game)
    local cfg = UIConfig.getGridConfig(game, source.id)
    local out = {}
    for _, col in ipairs(source.columns) do
        local override = cfg.hidden[col.id]
        local shown
        if override == true then shown = false
        elseif override == false then shown = true
        else shown = col.visible_default ~= false end
        if shown then
            local w = cfg.widths[col.id] or col.width or 60
            out[#out+1] = { col = col, width = w }
        end
    end
    return out
end

function DataGrid.effectiveSort(source, game)
    local cfg = UIConfig.getGridConfig(game, source.id)
    local valid = {}
    for _, c in ipairs(source.columns) do valid[c.id] = true end
    if cfg.sort and cfg.sort.column and valid[cfg.sort.column] then
        return cfg.sort
    end
    if source.default_sort and valid[source.default_sort.column] then
        return source.default_sort
    end
    return nil
end

-- ─── Sort ────────────────────────────────────────────────────────────────────

local function sortItems(items, source, game)
    local sort = DataGrid.effectiveSort(source, game)
    if not sort then return items end
    local col
    for _, c in ipairs(source.columns) do
        if c.id == sort.column then col = c; break end
    end
    if not col or not col.sort_key then return items end
    local out = {}
    for _, it in ipairs(items) do out[#out+1] = it end
    local dir = (sort.direction == "desc") and -1 or 1
    local ok = pcall(function()
        table.sort(out, function(a, b)
            local ka = col.sort_key(a, game)
            local kb = col.sort_key(b, game)
            if ka == kb then return false end
            if type(ka) == "string" or type(kb) == "string" then
                ka = tostring(ka or "")
                kb = tostring(kb or "")
                if dir == 1 then return ka < kb else return ka > kb end
            end
            if ka == nil then ka = 0 end
            if kb == nil then kb = 0 end
            if dir == 1 then return ka < kb else return ka > kb end
        end)
    end)
    if not ok then return items end
    return out
end

-- ─── Height ──────────────────────────────────────────────────────────────────

-- A source shows a filter row when at least one column is filterable. Kept as
-- a helper so layout, hit tests and row offsets all agree on the same predicate.
function DataGrid.hasFilterRow(source)
    if not source or not source.columns then return false end
    for _, c in ipairs(source.columns) do
        if FilterSvc.isFilterable(c) then return true end
    end
    return false
end

function DataGrid.totalHeight(comp, game)
    local source = comp.source
    local items  = source.items_fn(game) or {}
    items        = FilterSvc.applyFilters(items, source, game)
    local nrows  = math.max(1, #items)   -- reserve one row for "empty" message
    local filter_h = DataGrid.hasFilterRow(source) and DataGrid.FILTER_ROW_H or 0
    return DataGrid.HEADER_H + filter_h + nrows * DataGrid.ROW_H + 4
end

-- ─── Draw ────────────────────────────────────────────────────────────────────

local function drawCell(col, cw, x, y, h, item, game)
    if col.draw then
        local ok = pcall(col.draw, x, y, cw, h, item, game)
        if ok then return end
        love.graphics.setColor(1, 0.3, 0.3)
        love.graphics.setFont(game.fonts.ui_small)
        love.graphics.printf("?", x, y + 4, cw, "center")
        return
    end
    local text = "—"
    if col.format then
        local ok, v = pcall(col.format, item, game)
        if ok and v ~= nil then text = tostring(v) end
    end
    love.graphics.setFont(game.fonts.ui_small)
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf(text, x + DataGrid.ROW_PAD_X, y + 4,
        cw - DataGrid.ROW_PAD_X * 2, col.align or "left")
end

function DataGrid.draw(comp, panel_x, panel_w, p, y, game)
    local source   = comp.source
    local eff_cols = DataGrid.effectiveColumns(source, game)
    local sort     = DataGrid.effectiveSort(source, game)
    local state    = getState(source.id)
    local show_filters = DataGrid.hasFilterRow(source)

    local items = source.items_fn(game) or {}
    items = FilterSvc.applyFilters(items, source, game)
    items = sortItems(items, source, game)

    local gx = panel_x + p
    local gw = panel_w - p * 2
    local avail_w = gw - DataGrid.CHOOSER_BTN_W

    -- Header background
    love.graphics.setColor(0.18, 0.18, 0.24)
    love.graphics.rectangle("fill", gx, y, gw, DataGrid.HEADER_H)

    -- Chooser button
    local chooser_x = gx + gw - DataGrid.CHOOSER_BTN_W
    love.graphics.setColor(0.25, 0.25, 0.32)
    love.graphics.rectangle("fill", chooser_x, y, DataGrid.CHOOSER_BTN_W, DataGrid.HEADER_H)
    love.graphics.setColor(0.7, 0.7, 0.9)
    love.graphics.setFont(game.fonts.ui)
    love.graphics.printf("⋯", chooser_x, y + 2, DataGrid.CHOOSER_BTN_W, "center")

    -- Header cells
    love.graphics.setFont(game.fonts.ui_small)
    local cell_x = gx
    for i, e in ipairs(eff_cols) do
        local col = e.col
        local cw = e.width
        if cell_x + cw > gx + avail_w then cw = (gx + avail_w) - cell_x end
        if cw <= 0 then break end

        love.graphics.setColor(0.9, 0.9, 0.95)
        local label = col.label or col.id
        if sort and sort.column == col.id then
            label = label .. (sort.direction == "desc" and " v" or " ^")
        end
        love.graphics.printf(label, cell_x + DataGrid.ROW_PAD_X, y + 5,
            cw - DataGrid.ROW_PAD_X * 2, col.align or "left")

        -- Separator / resize handle hint
        love.graphics.setColor(0.4, 0.4, 0.5)
        love.graphics.rectangle("fill", cell_x + cw - 1, y + 2, 1, DataGrid.HEADER_H - 4)
        if state.hover_resize == col.id or (state.resize and state.resize.col_id == col.id) then
            love.graphics.setColor(0.6, 0.7, 1.0, 0.4)
            love.graphics.rectangle("fill", cell_x + cw - DataGrid.RESIZE_HOT, y,
                DataGrid.RESIZE_HOT * 2, DataGrid.HEADER_H)
        end

        cell_x = cell_x + cw
    end

    -- Filter row (DevExpress-style search/whitelist per column).
    local filter_y = y + DataGrid.HEADER_H
    if show_filters then
        -- Row background
        love.graphics.setColor(0.12, 0.12, 0.16)
        love.graphics.rectangle("fill", gx, filter_y, gw, DataGrid.FILTER_ROW_H)

        cell_x = gx
        love.graphics.setFont(game.fonts.ui_small)
        for _, e in ipairs(eff_cols) do
            local col = e.col
            local cw  = e.width
            if cell_x + cw > gx + avail_w then cw = (gx + avail_w) - cell_x end
            if cw <= 0 then break end

            if FilterSvc.isFilterable(col) then
                local funnel_w = DataGrid.FILTER_FUNNEL_W
                local pad      = DataGrid.FILTER_INPUT_PAD_X
                local input_x  = cell_x + 2
                local input_y  = filter_y + 3
                local input_w  = cw - funnel_w - 4
                local input_h  = DataGrid.FILTER_ROW_H - 6

                -- Background + border (focused input brighter).
                local is_focused = DataGrid._focused_filter
                               and DataGrid._focused_filter.grid_id == source.id
                               and DataGrid._focused_filter.col_id  == col.id
                if is_focused then
                    love.graphics.setColor(0.05, 0.08, 0.15)
                else
                    love.graphics.setColor(0.08, 0.08, 0.12)
                end
                love.graphics.rectangle("fill", input_x, input_y, input_w, input_h, 2)
                if is_focused then
                    love.graphics.setColor(0.45, 0.65, 1.0)
                else
                    love.graphics.setColor(0.3, 0.3, 0.4)
                end
                love.graphics.rectangle("line", input_x, input_y, input_w, input_h, 2)

                -- Text: either the focused buffer or the persisted query.
                local text
                if is_focused then
                    text = DataGrid._focused_filter.buffer or ""
                else
                    local f = UIConfig.getFilter(game, source.id, col.id)
                    text = f.query or ""
                end

                local fh = game.fonts.ui_small:getHeight()
                local ty = input_y + (input_h - fh) * 0.5
                if text == "" and not is_focused then
                    love.graphics.setColor(0.5, 0.5, 0.55)
                    love.graphics.printf("Filter…", input_x + pad, ty,
                        input_w - pad * 2, "left")
                else
                    love.graphics.setColor(1, 1, 1)
                    love.graphics.printf(text, input_x + pad, ty,
                        input_w - pad * 2, "left")
                end

                -- Cursor on focus (blink).
                if is_focused then
                    local tw = game.fonts.ui_small:getWidth(text or "")
                    local cx = math.min(input_x + input_w - 3, input_x + pad + tw)
                    local blink = math.floor(love.timer.getTime() * 2) % 2 == 0
                    if blink then
                        love.graphics.setColor(1, 1, 1)
                        love.graphics.line(cx, input_y + 2, cx, input_y + input_h - 2)
                    end
                end

                -- Funnel icon (highlighted if a filter is set for this column).
                local funnel_x = cell_x + cw - funnel_w - 2
                local active   = UIConfig.isFilterActive(game, source.id, col.id)
                if active then
                    love.graphics.setColor(0.25, 0.55, 0.90)
                    love.graphics.rectangle("fill", funnel_x, input_y,
                        funnel_w, input_h, 2)
                    love.graphics.setColor(1, 1, 1)
                else
                    love.graphics.setColor(0.22, 0.22, 0.30)
                    love.graphics.rectangle("fill", funnel_x, input_y,
                        funnel_w, input_h, 2)
                    love.graphics.setColor(0.7, 0.7, 0.85)
                end
                love.graphics.printf("▼", funnel_x, input_y + 2,
                    funnel_w, "center")
            else
                -- Non-filterable column: empty greyed cell.
                love.graphics.setColor(0.10, 0.10, 0.14)
                love.graphics.rectangle("fill", cell_x + 2, filter_y + 3,
                    cw - 4, DataGrid.FILTER_ROW_H - 6, 2)
            end

            -- Column separator (same as header).
            love.graphics.setColor(0.4, 0.4, 0.5)
            love.graphics.rectangle("fill", cell_x + cw - 1, filter_y + 2, 1,
                DataGrid.FILTER_ROW_H - 4)
            cell_x = cell_x + cw
        end
    end

    -- Rows
    local row_y = filter_y + (show_filters and DataGrid.FILTER_ROW_H or 0)

    if #items == 0 then
        love.graphics.setFont(game.fonts.ui_small)
        love.graphics.setColor(0.5, 0.5, 0.5)
        love.graphics.printf(source.empty_message or "No items.",
            gx + DataGrid.ROW_PAD_X, row_y + 4,
            gw - DataGrid.ROW_PAD_X * 2, "left")
        return
    end

    local selected_id = source.selected_id and source.selected_id(game)
    for idx, item in ipairs(items) do
        local row_id      = source.row_id and source.row_id(item) or idx
        local is_hover    = state.hover_row_id ~= nil and state.hover_row_id == row_id
        local is_selected = selected_id ~= nil and selected_id == row_id

        if is_selected then
            love.graphics.setColor(0.35, 0.55, 0.85, 0.55)
            love.graphics.rectangle("fill", gx, row_y, gw, DataGrid.ROW_H)
        end
        if is_hover then
            love.graphics.setColor(0.2, 0.75, 1.0, 0.30)
            love.graphics.rectangle("fill", gx, row_y, gw, DataGrid.ROW_H)
        elseif not is_selected and (idx % 2) == 0 then
            love.graphics.setColor(0, 0, 0, 0.15)
            love.graphics.rectangle("fill", gx, row_y, gw, DataGrid.ROW_H)
        end

        cell_x = gx
        for _, e in ipairs(eff_cols) do
            local col = e.col
            local cw = e.width
            if cell_x + cw > gx + avail_w then cw = (gx + avail_w) - cell_x end
            if cw <= 0 then break end
            drawCell(col, cw, cell_x, row_y, DataGrid.ROW_H, item, game)
            cell_x = cell_x + cw
        end

        row_y = row_y + DataGrid.ROW_H
    end
end

-- ─── Hit test ────────────────────────────────────────────────────────────────
-- Returns a hit table with one of these `id`s:
--   "datagrid_resize_start" — data: { grid_id, col_id, start_w, start_mx }
--   "datagrid_sort"         — data: { grid_id, col_id }
--   "datagrid_chooser"      — data: { grid_id, source }
--   "datagrid_row"          — data: { grid_id, source, item, row_id, hover_entity }
--
-- `cy_rel` is cursor-y relative to the component's top (0 at header top).

function DataGrid.hitTest(comp, panel_x, panel_w, p, cy_rel, cx, cy, game)
    local source   = comp.source
    local eff_cols = DataGrid.effectiveColumns(source, game)
    local gx       = panel_x + p
    local gw       = panel_w - p * 2
    local avail_w  = gw - DataGrid.CHOOSER_BTN_W
    local show_filters = DataGrid.hasFilterRow(source)

    -- In header row?
    if cy_rel >= 0 and cy_rel < DataGrid.HEADER_H then
        -- Chooser button?
        local chooser_x = gx + gw - DataGrid.CHOOSER_BTN_W
        if cx >= chooser_x and cx < chooser_x + DataGrid.CHOOSER_BTN_W then
            return { id = "datagrid_chooser", data = { grid_id = source.id, source = source } }
        end

        -- Walk columns: resize hot zone wins, otherwise sort.
        local cell_x = gx
        for _, e in ipairs(eff_cols) do
            local cw = e.width
            if cell_x + cw > gx + avail_w then cw = (gx + avail_w) - cell_x end
            if cw <= 0 then break end

            local right_edge = cell_x + cw
            if cx >= right_edge - DataGrid.RESIZE_HOT and cx <= right_edge + DataGrid.RESIZE_HOT then
                return { id = "datagrid_resize_start", data = {
                    grid_id  = source.id,
                    col_id   = e.col.id,
                    start_w  = e.width,
                    start_mx = cx,
                    min_width = e.col.min_width or 20,
                } }
            end
            if cx >= cell_x and cx < right_edge then
                return { id = "datagrid_sort", data = {
                    grid_id = source.id,
                    col_id  = e.col.id,
                } }
            end
            cell_x = cell_x + cw
        end
        return nil
    end

    -- In the filter row?
    if show_filters
       and cy_rel >= DataGrid.HEADER_H
       and cy_rel <  DataGrid.HEADER_H + DataGrid.FILTER_ROW_H then
        local cell_x = gx
        for _, e in ipairs(eff_cols) do
            local col = e.col
            local cw  = e.width
            if cell_x + cw > gx + avail_w then cw = (gx + avail_w) - cell_x end
            if cw <= 0 then break end
            if FilterSvc.isFilterable(col) and cx >= cell_x and cx < cell_x + cw then
                local funnel_x = cell_x + cw - DataGrid.FILTER_FUNNEL_W - 2
                if cx >= funnel_x then
                    return { id = "datagrid_filter_popup", data = {
                        grid_id = source.id, source = source, col_id = col.id,
                        anchor_x = funnel_x,
                        anchor_y = cell_x * 0 + cx,  -- unused; popup positions off mouse below
                    }}
                end
                return { id = "datagrid_filter_focus", data = {
                    grid_id = source.id, col_id = col.id,
                }}
            end
            cell_x = cell_x + cw
        end
        return nil
    end

    -- In a row?
    local items = source.items_fn(game) or {}
    items = FilterSvc.applyFilters(items, source, game)
    items = sortItems(items, source, game)
    if #items == 0 then return nil end

    local row_rel = cy_rel - DataGrid.HEADER_H
                  - (show_filters and DataGrid.FILTER_ROW_H or 0)
    local idx = math.floor(row_rel / DataGrid.ROW_H) + 1
    if idx < 1 or idx > #items then return nil end

    local item = items[idx]
    local row_id = source.row_id and source.row_id(item) or idx
    local hover_entity = source.hover_entity and source.hover_entity(item) or nil
    return { id = "datagrid_row", data = {
        grid_id       = source.id,
        source        = source,
        item          = item,
        row_id        = row_id,
        hover_entity  = hover_entity,
    } }
end

-- ─── Resize drag ─────────────────────────────────────────────────────────────

function DataGrid.isResizing()
    for _, s in pairs(_grid_state) do
        if s.resize then return true end
    end
    return false
end

function DataGrid.updateResize(mx, game)
    for _, s in pairs(_grid_state) do
        if s.resize then
            local r = s.resize
            local new_w = math.max(r.min_width or 20, r.start_w + (mx - r.start_mx))
            UIConfig.setColumnWidth(game, r.grid_id, r.col_id, new_w)
        end
    end
end

function DataGrid.endResize()
    for _, s in pairs(_grid_state) do s.resize = nil end
end

-- ─── Hover tracking ─────────────────────────────────────────────────────────
-- Called each frame by UIManager after hitTest. Clears previous hover state
-- if the hit is nil or on a different grid.

function DataGrid.applyHover(hit, game)
    -- Clear hover state on every grid first
    for _, s in pairs(_grid_state) do
        s.hover_row_id = nil
        s.hover_resize = nil
    end

    if not hit then
        game.ui = game.ui or {}
        game.ui.hovered_entity = nil
        return
    end

    if hit.id == "datagrid_row" then
        local d = hit.data
        local st = getState(d.grid_id)
        st.hover_row_id = d.row_id
        game.ui = game.ui or {}
        game.ui.hovered_entity = d.hover_entity
    elseif hit.id == "datagrid_resize_start" then
        local d = hit.data
        local st = getState(d.grid_id)
        st.hover_resize = d.col_id
        game.ui = game.ui or {}
        game.ui.hovered_entity = nil
    else
        game.ui = game.ui or {}
        game.ui.hovered_entity = nil
    end
end

-- ─── Column chooser ─────────────────────────────────────────────────────────

function DataGrid.openChooser(grid_id, source, anchor_x, anchor_y)
    DataGrid.chooser = {
        grid_id = grid_id,
        source  = source,
        x       = anchor_x,
        y       = anchor_y,
    }
end

function DataGrid.closeChooser()
    DataGrid.chooser = nil
end

function DataGrid.isChooserOpen()
    return DataGrid.chooser ~= nil
end

-- ─── Filter row: focus + input routing ──────────────────────────────────────

local function commitFocusedBuffer(game)
    local f = DataGrid._focused_filter
    if not (f and game) then return end
    UIConfig.setFilterQuery(game, f.grid_id, f.col_id, f.buffer or "")
end

-- Start editing the filter cell for (grid_id, col_id). Seeds the buffer from
-- the currently-stored query so typing appends rather than replacing.
function DataGrid.focusFilter(grid_id, col_id, game)
    -- Commit any previously focused filter before swapping.
    if DataGrid._focused_filter then commitFocusedBuffer(game) end
    local f = UIConfig.getFilter(game, grid_id, col_id)
    DataGrid._focused_filter = {
        grid_id = grid_id,
        col_id  = col_id,
        buffer  = f.query or "",
    }
end

-- Blur the active filter cell (if any), committing the buffer to persisted state.
function DataGrid.blurFilter(game)
    if DataGrid._focused_filter then
        commitFocusedBuffer(game)
        DataGrid._focused_filter = nil
    end
end

-- Handle a mouse-down hit from DataGrid.hitTest — dispatches filter-row clicks.
function DataGrid.handleFilterHit(hit, game)
    if not hit then return false end
    if hit.id == "datagrid_filter_focus" then
        DataGrid.focusFilter(hit.data.grid_id, hit.data.col_id, game)
        return true
    end
    if hit.id == "datagrid_filter_popup" then
        -- Source is carried on the hit so callers don't need the tab context.
        local mx, my = love.mouse.getPosition()
        DataGrid.openFilterPopup(hit.data.grid_id, hit.data.source,
                                 hit.data.col_id, mx, my, game)
        -- Also blur any focused filter input — popup is exclusive.
        DataGrid.blurFilter(game)
        return true
    end
    return false
end

-- Character from love.textinput. Routes to the filter popup's search input
-- first (if focused), then to the focused filter cell. Live-writes cell
-- queries to UIConfig so rows filter in real time.
function DataGrid.routeTextInput(text, game)
    -- Popup search input wins when focused.
    if DataGrid.filter_popup and DataGrid.filter_popup.search_focused then
        local FilterPopup = require("views.FilterPopup")
        return FilterPopup.handleTextInput(DataGrid.filter_popup, text)
    end
    local f = DataGrid._focused_filter
    if not f then return false end
    f.buffer = (f.buffer or "") .. (text or "")
    if game then
        UIConfig.setFilterQuery(game, f.grid_id, f.col_id, f.buffer)
    end
    return true
end

-- Key from love.keypressed. Handles editing + commit/cancel keys.
function DataGrid.routeKeyPressed(key, game)
    -- Popup first: its search field absorbs editing keys, and Escape closes
    -- the whole popup when no field is focused.
    if DataGrid.filter_popup then
        local FilterPopup = require("views.FilterPopup")
        if DataGrid.filter_popup.search_focused then
            if FilterPopup.handleKeyPressed(DataGrid.filter_popup, key) then
                return true
            end
        end
        if key == "escape" then
            DataGrid.closeFilterPopup()
            return true
        end
    end
    local f = DataGrid._focused_filter
    if not f then return false end
    if key == "backspace" then
        local s = f.buffer or ""
        local offset = utf8.offset(s, -1)
        if offset then
            f.buffer = s:sub(1, offset - 1)
        else
            f.buffer = ""
        end
        if game then UIConfig.setFilterQuery(game, f.grid_id, f.col_id, f.buffer) end
        return true
    elseif key == "delete" then
        f.buffer = ""
        if game then UIConfig.setFilterQuery(game, f.grid_id, f.col_id, "") end
        return true
    elseif key == "escape" then
        -- Abandon edits: revert buffer to whatever's persisted and blur.
        local stored = UIConfig.getFilter(game, f.grid_id, f.col_id)
        f.buffer = stored.query or ""
        DataGrid._focused_filter = nil
        return true
    elseif key == "return" or key == "kpenter" or key == "tab" then
        DataGrid.blurFilter(game)
        return true
    end
    return false
end

-- ─── Filter popup overlay ───────────────────────────────────────────────────

function DataGrid.openFilterPopup(grid_id, source, col_id, anchor_x, anchor_y, game)
    -- Snapshot distinct values at open time so the list doesn't reshuffle
    -- beneath the user while the popup is visible.
    local values = FilterSvc.distinctValues(source, col_id, game)
    DataGrid.filter_popup = {
        grid_id = grid_id,
        source  = source,
        col_id  = col_id,
        x       = anchor_x,
        y       = anchor_y,
        values  = values,      -- all distinct values in this column
        search  = "",          -- narrows the visible subset (popup-local)
        scroll  = 0,
        search_focused = false,
    }
end

function DataGrid.closeFilterPopup()
    DataGrid.filter_popup = nil
end

function DataGrid.isFilterPopupOpen()
    return DataGrid.filter_popup ~= nil
end

return DataGrid
