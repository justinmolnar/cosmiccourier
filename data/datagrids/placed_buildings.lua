-- data/datagrids/placed_buildings.lua
-- Player-placed buildings (docks etc.). Rows come from game.buildings[city_idx]
-- flattened across all cities; the City tab wraps items_fn via ScopeFilterService
-- to narrow to the selected city.

local function flattenBuildings(game)
    local out = {}
    if not game.buildings then return out end
    for _, list in pairs(game.buildings) do
        for _, b in ipairs(list) do out[#out + 1] = b end
    end
    return out
end

local function buildingCityMap(item, game)
    if not item or not game.maps or not game.maps.all_cities then return nil end
    return game.maps.all_cities[item.city]
end

local columns = {
    {
        id = "icon", label = " ", width = 26, min_width = 20, align = "center",
        draw = function(x, y, w, h, item, game)
            local icon = (item.cfg and item.cfg.icon) or "🏢"
            love.graphics.setFont(game.fonts.ui)
            love.graphics.setColor(1, 1, 1)
            love.graphics.printf(icon, x, y + 2, w, "center")
        end,
    },
    {
        id = "name", label = "Name", width = 140, min_width = 80,
        format   = function(item) return item.name or "—" end,
        sort_key = function(item) return item.name or "" end,
    },
    {
        id = "type", label = "Type", width = 80, min_width = 50,
        format = function(item)
            return (item.cfg and (item.cfg.display_name or item.cfg.id)) or "?"
        end,
        sort_key = function(item)
            return (item.cfg and (item.cfg.display_name or item.cfg.id)) or ""
        end,
    },
    {
        id = "city", label = "City", width = 90, min_width = 40,
        required_scope_tier = 2,
        format = function(item, game)
            local c = buildingCityMap(item, game)
            return c and (c.name or c.id) or "—"
        end,
        sort_key = function(item, game)
            local c = buildingCityMap(item, game)
            return c and (c.name or c.id) or ""
        end,
    },
    {
        id = "cargo", label = "Cargo", width = 55, min_width = 40, align = "right",
        format   = function(item)
            return string.format("%d/%d", #(item.cargo or {}), item.capacity or 0)
        end,
        sort_key = function(item) return #(item.cargo or {}) end,
    },
}

return {
    id            = "placed_buildings",
    items_fn      = flattenBuildings,
    row_id        = function(item) return item end,
    hover_entity  = function(item) return { kind = "building", id = item } end,
    empty_message = "No placed buildings.",
    default_sort  = { column = "name", direction = "asc" },
    columns       = columns,
}
