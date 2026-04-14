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
        widths = {},
        hidden = {},
        sort   = nil,
    }
    local cfg = root.datagrids[grid_id]
    cfg.widths = cfg.widths or {}
    cfg.hidden = cfg.hidden or {}
    return cfg
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
    if cfg.sort and cfg.sort.column and not valid[cfg.sort.column] then
        cfg.sort = nil
    end
end

return UIConfigService
