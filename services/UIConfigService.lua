-- services/UIConfigService.lua
-- Thin helpers around state.ui_config so grids, panels, and future UI widgets
-- read/write persisted user layout without each site reinventing the structure.

local UIConfigService = {}

local function ensureRoot(game)
    local s = game.state
    s.ui_config = s.ui_config or {}
    s.ui_config.datagrids = s.ui_config.datagrids or {}
    return s.ui_config
end

function UIConfigService.getGridConfig(game, grid_id)
    local root = ensureRoot(game)
    root.datagrids[grid_id] = root.datagrids[grid_id] or {
        widths  = {},
        hidden  = {},
        sort    = nil,
        filters = {},
    }
    local cfg = root.datagrids[grid_id]
    cfg.widths  = cfg.widths  or {}
    cfg.hidden  = cfg.hidden  or {}
    cfg.filters = cfg.filters or {}
    return cfg
end

-- ─── Accordion collapsed state ──────────────────────────────────────────────
-- Parallel structure to datagrids; state.ui_config.accordions[tab_id][section_id].collapsed.

local function ensureAccordions(game)
    local root = ensureRoot(game)
    root.accordions = root.accordions or {}
    return root.accordions
end

function UIConfigService.getAccordion(game, tab_id, section_id, default_collapsed)
    local acc = ensureAccordions(game)
    acc[tab_id] = acc[tab_id] or {}
    if acc[tab_id][section_id] == nil then
        acc[tab_id][section_id] = { collapsed = default_collapsed and true or false }
    end
    return acc[tab_id][section_id]
end

function UIConfigService.setAccordionCollapsed(game, tab_id, section_id, collapsed)
    local entry = UIConfigService.getAccordion(game, tab_id, section_id)
    entry.collapsed = collapsed and true or false
end

function UIConfigService.toggleAccordion(game, tab_id, section_id)
    local entry = UIConfigService.getAccordion(game, tab_id, section_id)
    entry.collapsed = not entry.collapsed
    return entry.collapsed
end

-- Drop accordion entries for sections/tabs that no longer exist in the UI definition.
function UIConfigService.pruneAccordionOrphans(game, tab_id, valid_section_ids)
    local acc = ensureAccordions(game)
    if not acc[tab_id] then return end
    local valid = {}
    for _, id in ipairs(valid_section_ids) do valid[id] = true end
    for id in pairs(acc[tab_id]) do
        if not valid[id] then acc[tab_id][id] = nil end
    end
end

function UIConfigService.setColumnWidth(game, grid_id, col_id, width)
    local cfg = UIConfigService.getGridConfig(game, grid_id)
    cfg.widths[col_id] = width
end

-- Record an explicit override. Storing `false` (not nil) is required so a
-- column whose default is `visible_default=false` can be turned ON and stay on.
function UIConfigService.setColumnHidden(game, grid_id, col_id, hidden)
    local cfg = UIConfigService.getGridConfig(game, grid_id)
    cfg.hidden[col_id] = hidden and true or false
end

function UIConfigService.setSort(game, grid_id, column_id, direction)
    local cfg = UIConfigService.getGridConfig(game, grid_id)
    if not column_id then
        cfg.sort = nil
    else
        cfg.sort = { column = column_id, direction = direction or "asc" }
    end
end

-- ─── Filters ────────────────────────────────────────────────────────────────
-- Per-column filter state has up to two independent pieces:
--   query  — case-insensitive substring match; empty string means "no query"
--   values — whitelist of exact-match values; empty/nil means "no whitelist"
-- A row passes a column when query matches AND whitelist matches (or either
-- is empty). Column filters combine with AND across the grid.

local function ensureFilter(cfg, col_id)
    cfg.filters[col_id] = cfg.filters[col_id] or { query = "", values = {} }
    local f = cfg.filters[col_id]
    f.query  = f.query  or ""
    f.values = f.values or {}
    return f
end

function UIConfigService.getFilter(game, grid_id, col_id)
    local cfg = UIConfigService.getGridConfig(game, grid_id)
    return ensureFilter(cfg, col_id)
end

function UIConfigService.setFilterQuery(game, grid_id, col_id, query)
    local cfg = UIConfigService.getGridConfig(game, grid_id)
    local f   = ensureFilter(cfg, col_id)
    f.query   = query or ""
    -- Drop the entry entirely when both sides are empty.
    if f.query == "" and (not f.values or #f.values == 0) then
        cfg.filters[col_id] = nil
    end
end

function UIConfigService.setFilterValues(game, grid_id, col_id, values)
    local cfg = UIConfigService.getGridConfig(game, grid_id)
    local f   = ensureFilter(cfg, col_id)
    f.values  = values or {}
    if f.query == "" and #f.values == 0 then
        cfg.filters[col_id] = nil
    end
end

function UIConfigService.clearFilter(game, grid_id, col_id)
    local cfg = UIConfigService.getGridConfig(game, grid_id)
    cfg.filters[col_id] = nil
end

function UIConfigService.isFilterActive(game, grid_id, col_id)
    local cfg = UIConfigService.getGridConfig(game, grid_id)
    local f   = cfg.filters[col_id]
    if not f then return false end
    return (f.query ~= nil and f.query ~= "") or (f.values and #f.values > 0)
end

-- Strip entries whose column ids no longer exist in the datasource. Called on
-- load before applying so renamed/removed columns don't linger in the save.
function UIConfigService.pruneOrphans(game, grid_id, valid_column_ids)
    local cfg = UIConfigService.getGridConfig(game, grid_id)
    local valid = {}
    for _, id in ipairs(valid_column_ids) do valid[id] = true end
    for id in pairs(cfg.widths) do
        if not valid[id] then cfg.widths[id] = nil end
    end
    for id in pairs(cfg.hidden) do
        if not valid[id] then cfg.hidden[id] = nil end
    end
    if cfg.filters then
        for id in pairs(cfg.filters) do
            if not valid[id] then cfg.filters[id] = nil end
        end
    end
    if cfg.sort and cfg.sort.column and not valid[cfg.sort.column] then
        cfg.sort = nil
    end
end

return UIConfigService
