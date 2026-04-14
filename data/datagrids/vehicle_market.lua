-- data/datagrids/vehicle_market.lua
-- Shared datagrid source for buying vehicles. Used by VehiclesTab (global buy)
-- and DepotTab (buy-at-depot when a depot is selected).
--
-- Items are synthetic row objects: { id (string), vcfg (table), cost (number) }.
-- The datasource is MVC-clean: it doesn't mutate state. Clicking a row
-- publishes an event via game.EventBus; the handler for that event is where
-- the actual purchase happens.

local function buildItems(game)
    local out = {}
    local purchasable = game.state.purchasable_vehicles or {}
    local sorted = {}
    for id, vcfg in pairs(game.C.VEHICLES or {}) do
        sorted[#sorted + 1] = { id = id, vcfg = vcfg }
    end
    table.sort(sorted, function(a, b)
        return (a.vcfg.base_cost or 0) < (b.vcfg.base_cost or 0)
    end)
    for _, entry in ipairs(sorted) do
        local vid = entry.id:lower()
        if purchasable[vid] then
            out[#out + 1] = {
                id   = vid,
                vcfg = entry.vcfg,
                cost = (game.state.costs and game.state.costs[vid]) or entry.vcfg.base_cost,
            }
        end
    end
    return out
end

local columns = {
    {
        id = "icon", label = " ", width = 26, min_width = 20, align = "center",
        draw = function(x, y, w, h, item, game)
            love.graphics.setFont(game.fonts.ui)
            love.graphics.setColor(1, 1, 1)
            love.graphics.printf(item.vcfg.icon or "?", x, y + 2, w, "center")
        end,
    },
    {
        id = "name", label = "Name", width = 100, min_width = 50,
        format   = function(item) return item.vcfg.display_name or item.id end,
        sort_key = function(item) return item.vcfg.display_name or item.id end,
    },
    {
        id = "cost", label = "Cost", width = 70, min_width = 40, align = "right",
        format   = function(item) return string.format("$%d", item.cost or 0) end,
        sort_key = function(item) return item.cost or 0 end,
    },
    {
        id = "capacity", label = "Cap", width = 45, min_width = 30, align = "right",
        format   = function(item) return tostring(item.vcfg.base_capacity or "?") end,
        sort_key = function(item) return item.vcfg.base_capacity or 0 end,
    },
    {
        id = "speed", label = "Speed", width = 50, min_width = 30, align = "right",
        format   = function(item) return tostring(item.vcfg.base_speed or "?") end,
        sort_key = function(item) return item.vcfg.base_speed or 0 end,
    },
    {
        id = "fuel", label = "Fuel", width = 45, min_width = 30, align = "right",
        visible_default = false,
        format   = function(item) return tostring(item.vcfg.fuel_rate or "?") end,
        sort_key = function(item) return item.vcfg.fuel_rate or 0 end,
    },
    {
        id = "mode", label = "Mode", width = 55, min_width = 40,
        visible_default = false,
        format   = function(item) return item.vcfg.transport_mode or "—" end,
        sort_key = function(item) return item.vcfg.transport_mode or "" end,
    },
}

return {
    id            = "vehicle_market",
    items_fn      = buildItems,
    row_id        = function(item) return item.id end,
    on_row_click  = function(item, game)
        -- If a depot is selected, buy at that depot; else plain buy.
        local depot = game.entities and game.entities.selected_depot
        if depot then
            game.EventBus:publish("ui_buy_vehicle_at_depot_clicked",
                { vehicle_id = item.id, depot = depot })
        else
            game.EventBus:publish("ui_buy_vehicle_clicked", item.id)
        end
    end,
    empty_message = "No vehicles available to hire.",
    default_sort  = { column = "cost", direction = "asc" },
    columns       = columns,
}
