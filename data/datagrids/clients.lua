-- data/datagrids/clients.lua
-- Active clients datagrid. Surfaces earnings and trips_generated — data that
-- previously lived on the Client model but wasn't rendered anywhere.

local Archetypes = require("data.client_archetypes")

local function archetypeOf(item)
    return Archetypes.by_id[item.archetype]
end

local columns = {
    {
        id = "icon", label = " ", width = 26, min_width = 20, align = "center",
        draw = function(x, y, w, h, item, game)
            local a = archetypeOf(item)
            love.graphics.setFont(game.fonts.ui)
            love.graphics.setColor(1, 1, 1)
            love.graphics.printf(a and a.icon or "?", x, y + 2, w, "center")
        end,
    },
    {
        id = "archetype", label = "Type", width = 80, min_width = 50,
        format   = function(item)
            local a = archetypeOf(item)
            return a and a.display_name or item.archetype or "?"
        end,
        sort_key = function(item) return item.archetype or "" end,
    },
    {
        id = "district", label = "District", width = 90, min_width = 40,
        format   = function(item, game) return item:getDistrict(game) or "—" end,
        sort_key = function(item, game) return item:getDistrict(game) or "" end,
    },
    {
        id = "city", label = "City", width = 70, min_width = 40,
        visible_default = false,
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
        id = "cargo", label = "Cargo", width = 50, min_width = 30, align = "right",
        format = function(item, game)
            return string.format("%d/%d", #item.cargo, item:getEffectiveCapacity(game))
        end,
        sort_key = function(item) return #item.cargo end,
    },
    {
        id = "trips", label = "Trips", width = 45, min_width = 30, align = "right",
        format   = function(item) return tostring(item.trips_generated or 0) end,
        sort_key = function(item) return item.trips_generated or 0 end,
    },
    {
        id = "earnings", label = "Earned", width = 60, min_width = 40, align = "right",
        format   = function(item) return string.format("$%d", item.earnings or 0) end,
        sort_key = function(item) return item.earnings or 0 end,
    },
    {
        id = "freq_mult", label = "Freq", width = 45, min_width = 30, align = "right",
        visible_default = false,
        format   = function(item) return string.format("%.2f", item.freq_mult or 1) end,
        sort_key = function(item) return item.freq_mult or 1 end,
    },
    {
        id = "active", label = "On", width = 32, min_width = 28, align = "center",
        visible_default = false,
        format   = function(item) return item.active and "●" or "○" end,
        sort_key = function(item) return item.active and 1 or 0 end,
    },
}

return {
    id            = "clients",
    items_fn      = function(game) return game.entities.clients end,
    row_id        = function(item) return item end,
    hover_entity  = function(item) return { kind = "client", id = item } end,
    selected_id   = function(game) return game.entities.selected_client end,
    on_row_click  = function(item, game)
        if game.entities.selected_client == item then
            game.entities.selected_client = nil
        else
            game.entities.selected_client = item
        end
    end,
    empty_message = "No active clients.",
    default_sort  = { column = "earnings", direction = "desc" },
    columns       = columns,
}
