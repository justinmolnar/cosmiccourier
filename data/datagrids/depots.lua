-- data/datagrids/depots.lua
-- All depots as rows. Row click selects (for map highlight + scoping other
-- grids like the hire-at-depot market).

local ContextMenuItems = require("data.context_menu_items")

local columns = {
    {
        id = "name", label = "Name", width = 100, min_width = 60,
        format   = function(item) return item.name or item.id or "Depot" end,
        sort_key = function(item) return item.name or item.id or "" end,
    },
    {
        id = "city", label = "City", width = 80, min_width = 40,
        format = function(item, game)
            local c = item:getCity(game)
            return c and (c.name or c.id) or "—"
        end,
        sort_key = function(item, game)
            local c = item:getCity(game)
            return c and (c.name or c.id) or ""
        end,
    },
    {
        id = "district", label = "District", width = 90, min_width = 40,
        format   = function(item, game) return item:getDistrict(game) or "—" end,
        sort_key = function(item, game) return item:getDistrict(game) or "" end,
    },
    {
        id = "vehicles", label = "Veh", width = 40, min_width = 30, align = "right",
        format   = function(item) return tostring(#(item.assigned_vehicles or {})) end,
        sort_key = function(item) return #(item.assigned_vehicles or {}) end,
    },
    {
        id = "cargo", label = "Cargo", width = 55, min_width = 40, align = "right",
        format   = function(item) return string.format("%d/%d", #(item.cargo or {}), item.capacity or 0) end,
        sort_key = function(item) return #(item.cargo or {}) end,
    },
    {
        id = "trips", label = "Trips", width = 45, min_width = 30, align = "right",
        format   = function(item)
            return tostring((item.analytics and item.analytics.trips_completed) or 0)
        end,
        sort_key = function(item)
            return (item.analytics and item.analytics.trips_completed) or 0
        end,
    },
    {
        id = "income", label = "Income", width = 70, min_width = 50, align = "right",
        format   = function(item)
            return string.format("$%d", (item.analytics and item.analytics.income_generated) or 0)
        end,
        sort_key = function(item)
            return (item.analytics and item.analytics.income_generated) or 0
        end,
    },
    {
        id = "vol_in", label = "In", width = 45, min_width = 30, align = "right",
        visible_default = false,
        format   = function(item) return tostring((item.analytics and item.analytics.volume_in) or 0) end,
        sort_key = function(item) return (item.analytics and item.analytics.volume_in) or 0 end,
    },
    {
        id = "vol_out", label = "Out", width = 45, min_width = 30, align = "right",
        visible_default = false,
        format   = function(item) return tostring((item.analytics and item.analytics.volume_out) or 0) end,
        sort_key = function(item) return (item.analytics and item.analytics.volume_out) or 0 end,
    },
}

return {
    id            = "depots",
    items_fn      = function(game) return game.entities.depots end,
    row_id        = function(item) return item end,
    hover_entity  = function(item) return { kind = "depot", id = item } end,
    selected_id   = function(game) return game.entities.selected_depot end,
    on_row_click  = function(item, game)
        if game.entities.selected_depot == item then
            game.entities.selected_depot = nil
        else
            game.entities.selected_depot = item
        end
    end,
    on_row_context_menu = function(item, game, sx, sy)
        return ContextMenuItems.depot(item, game)
    end,
    empty_message = "No depots.",
    default_sort  = { column = "income", direction = "desc" },
    columns       = columns,
}
