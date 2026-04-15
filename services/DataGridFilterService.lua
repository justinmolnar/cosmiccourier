-- services/DataGridFilterService.lua
-- Pure, agnostic filter logic for the DataGrid component. Knows nothing about
-- specific columns or entity types — every operation takes a column definition
-- and/or items list and uses the column's own callbacks to extract values.
--
-- Filter model (per column):
--   query  — case-insensitive substring; empty string = no query
--   values — exact-match whitelist; empty table = no whitelist
--
-- A row passes a column when (query matches OR empty) AND (value in whitelist
-- OR whitelist empty). Column filters AND together across the grid.

local DataGridFilterService = {}

local UIConfig = require("services.UIConfigService")

-- ─── Value extraction ───────────────────────────────────────────────────────
-- Resolver chain: col.filter_value → col.sort_key → col.format → nil.
-- Everything is tostring()-normalized. Returns nil only if the column is
-- un-filterable (no extractor defined).

local function safeCall(fn, item, game)
    if not fn then return nil end
    local ok, v = pcall(fn, item, game)
    if not ok or v == nil then return nil end
    return v
end

function DataGridFilterService.extractValue(col, item, game)
    if not col then return nil end
    local v = safeCall(col.filter_value, item, game)
    if v == nil then v = safeCall(col.sort_key, item, game) end
    if v == nil then v = safeCall(col.format,   item, game) end
    if v == nil then return nil end
    return tostring(v)
end

-- A column is filterable when the caller hasn't opted out AND at least one
-- extractor callback is defined.
function DataGridFilterService.isFilterable(col)
    if not col then return false end
    if col.filterable == false then return false end
    return col.filter_value ~= nil
        or col.sort_key     ~= nil
        or col.format       ~= nil
end

-- ─── Per-column predicate ───────────────────────────────────────────────────

local function stringContainsCI(haystack, needle)
    if not haystack or needle == nil or needle == "" then return true end
    return string.find(string.lower(haystack), string.lower(needle), 1, true) ~= nil
end

local function valueInWhitelist(value, values)
    if not values or #values == 0 then return true end
    for _, v in ipairs(values) do
        if v == value then return true end
    end
    return false
end

-- filter_cfg is { query, values } (may be nil to mean "no filter on this col").
function DataGridFilterService.passesColumn(col, item, game, filter_cfg)
    if not filter_cfg then return true end
    local has_query  = filter_cfg.query  and filter_cfg.query  ~= ""
    local has_values = filter_cfg.values and #filter_cfg.values > 0
    if not has_query and not has_values then return true end

    local value = DataGridFilterService.extractValue(col, item, game)
    if value == nil then
        -- Un-filterable column with a filter set (e.g., col was removed) —
        -- treat as pass so the grid still renders.
        return true
    end

    if has_query  and not stringContainsCI(value, filter_cfg.query)    then return false end
    if has_values and not valueInWhitelist(value, filter_cfg.values)   then return false end
    return true
end

-- ─── Grid-level filter ──────────────────────────────────────────────────────

function DataGridFilterService.applyFilters(items, source, game)
    if not source or not source.columns then return items end
    local cfg = UIConfig.getGridConfig(game, source.id)
    if not cfg.filters or next(cfg.filters) == nil then return items end

    -- Only iterate columns that actually have a filter set — keeps the common
    -- no-filter case cheap.
    local active = {}
    for _, col in ipairs(source.columns) do
        local f = cfg.filters[col.id]
        if f and ((f.query and f.query ~= "") or (f.values and #f.values > 0)) then
            active[#active + 1] = { col = col, filter = f }
        end
    end
    if #active == 0 then return items end

    local out = {}
    for _, item in ipairs(items) do
        local pass = true
        for _, a in ipairs(active) do
            if not DataGridFilterService.passesColumn(a.col, item, game, a.filter) then
                pass = false; break
            end
        end
        if pass then out[#out + 1] = item end
    end
    return out
end

-- ─── Distinct-values snapshot (for FilterPopup) ─────────────────────────────

function DataGridFilterService.distinctValues(source, col_id, game)
    local col
    for _, c in ipairs(source.columns or {}) do
        if c.id == col_id then col = c; break end
    end
    if not col then return {} end
    local items = (source.items_fn and source.items_fn(game)) or {}
    local seen, out = {}, {}
    for _, item in ipairs(items) do
        local v = DataGridFilterService.extractValue(col, item, game)
        if v ~= nil and v ~= "" and not seen[v] then
            seen[v] = true
            out[#out + 1] = v
        end
    end
    table.sort(out, function(a, b) return string.lower(a) < string.lower(b) end)
    return out
end

return DataGridFilterService
