-- data/datagrids/vehicles.lua
-- Vehicles DataGrid datasource. See views/DataGrid.lua for the schema.

local function fmtDuration(seconds)
    if not seconds or seconds <= 0 then return "—" end
    if seconds < 60 then return string.format("%ds", math.floor(seconds)) end
    if seconds < 3600 then return string.format("%dm", math.floor(seconds / 60)) end
    return string.format("%dh", math.floor(seconds / 3600))
end

local function depotCity(item, game)
    local d = item.depot
    if not d or not d.getCity then return nil end
    return d:getCity(game)
end

local columns = {
    {
        id = "icon", label = " ", width = 26, min_width = 20, align = "center",
        draw = function(x, y, w, h, item, game)
            local vcfg = item.type_upper and game.C.VEHICLES[item.type_upper]
            local icon = (vcfg and vcfg.icon) or item:getIcon() or "?"
            love.graphics.setFont(game.fonts.ui)
            love.graphics.setColor(1, 1, 1)
            love.graphics.printf(icon, x, y + 2, w, "center")
        end,
    },
    {
        id = "type", label = "Type", width = 60, min_width = 40,
        format   = function(item) return tostring(item.type or "?") end,
        sort_key = function(item) return tostring(item.type or "") end,
    },
    {
        id = "state", label = "State", width = 80, min_width = 50,
        format   = function(item) return item.state and item.state.name or "?" end,
        sort_key = function(item) return item.state and item.state.name or "" end,
    },
    {
        id = "city", label = "City", width = 90, min_width = 40,
        format = function(item, game)
            local c = depotCity(item, game)
            return c and (c.name or c.id) or "—"
        end,
        sort_key = function(item, game)
            local c = depotCity(item, game)
            return c and (c.name or c.id) or ""
        end,
    },
    {
        id = "district", label = "District", width = 90, min_width = 40,
        visible_default = false,
        format = function(item, game)
            local d = item.depot
            if not d or not d.getDistrict then return "—" end
            return d:getDistrict(game) or "—"
        end,
        sort_key = function(item, game)
            local d = item.depot
            if not d or not d.getDistrict then return "" end
            return d:getDistrict(game) or ""
        end,
    },
    {
        id = "capacity", label = "Cap", width = 55, min_width = 30, align = "right",
        format = function(item, game)
            local used = (#item.cargo) + (#item.trip_queue)
            local max  = item:getEffectiveCapacity(game)
            return string.format("%d/%d", used, max)
        end,
        sort_key = function(item, game) return item:getEffectiveCapacity(game) end,
    },
    {
        id = "speed", label = "Speed", width = 55, min_width = 30, align = "right",
        format   = function(item) return string.format("%.1f", item:getSpeed()) end,
        sort_key = function(item) return item:getSpeed() end,
    },
    {
        id = "fuel_rate", label = "Fuel", width = 50, min_width = 30, align = "right",
        visible_default = false,
        format   = function(item, game) return string.format("%.2f", item:getEffectiveFuelRate(game)) end,
        sort_key = function(item, game) return item:getEffectiveFuelRate(game) end,
    },
    {
        id = "trips", label = "Trips", width = 45, min_width = 30, align = "right",
        format   = function(item) return tostring(item.trips_completed or 0) end,
        sort_key = function(item) return item.trips_completed or 0 end,
    },
    {
        id = "last_trip", label = "Last", width = 45, min_width = 30, align = "right",
        visible_default = false,
        format = function(item)
            local t = item.last_trip_end_time or 0
            if t <= 0 then return "—" end
            return fmtDuration(love.timer.getTime() - t)
        end,
        sort_key = function(item) return item.last_trip_end_time or 0 end,
    },
}

local ContextMenuItems = require("data.context_menu_items")

return {
    id            = "vehicles",
    items_fn      = function(game) return game.entities.vehicles end,
    row_id        = function(item) return item.id end,
    hover_entity  = function(item) return { kind = "vehicle", id = item.id } end,
    selected_id   = function(game)
        local s = game.entities.selected_vehicle
        return s and s.id or nil
    end,
    on_row_click  = function(item, game)
        -- Toggle selection: clicking the already-selected row clears it.
        if game.entities.selected_vehicle == item then
            game.entities.selected_vehicle = nil
        else
            game.entities.selected_vehicle = item
        end
    end,
    on_row_context_menu = function(item, game, sx, sy)
        return ContextMenuItems.vehicle(item, game)
    end,
    empty_message = "No vehicles hired.",
    default_sort  = { column = "type", direction = "asc" },
    columns       = columns,
}
