-- data/datagrids/trips.lua
-- Pending-trips datagrid. A trip row is atomic — no legs, no sub-rows.
-- Columns read via Trip model methods (getCargoSize, getFinalDestination,
-- getSourcePlot, getCurrentBonus) so the UI never reaches into legs[].

local Archetypes = require("data.client_archetypes")

-- Look up the district identifier for a plot on the unified map. Reuses the
-- Depot:getDistrict idiom — same coord convention.
local function districtOfPlot(plot, game)
    if not plot or not game.maps then return nil end
    for _, cmap in ipairs(game.maps.all_cities or {}) do
        local ox = (cmap.world_mn_x - 1) * 3
        local oy = (cmap.world_mn_y - 1) * 3
        local lx = plot.x - ox
        local ly = plot.y - oy
        if lx >= 1 and ly >= 1
        and cmap.grid and lx <= #(cmap.grid[1] or {}) and ly <= #cmap.grid then
            if cmap.district_map and cmap.district_types then
                local sub_w = (game.world_w or 0) * 3
                if sub_w > 0 then
                    local sci = (plot.y - 1) * sub_w + plot.x
                    local poi_idx = cmap.district_map[sci]
                    if poi_idx then
                        return cmap.district_types[poi_idx], cmap
                    end
                end
            end
            return nil, cmap
        end
    end
    return nil, nil
end

local function cityNameOfPlot(plot, game)
    local _, cmap = districtOfPlot(plot, game)
    return cmap and (cmap.name or cmap.id) or nil
end

local function sourceArchetypeIcon(trip)
    local sc = trip.source_client
    if not sc then return "•" end
    local a = Archetypes.by_id[sc.archetype]
    return a and a.icon or "•"
end

local function destLabel(trip, game)
    local plot = trip:getFinalDestination()
    if not plot then return "—" end
    local d = districtOfPlot(plot, game)
    if d then return d end
    return cityNameOfPlot(plot, game) or "—"
end

local columns = {
    {
        id = "rush", label = "⚡", width = 22, min_width = 20, align = "center",
        draw = function(x, y, w, h, item, game)
            if item.is_rush then
                love.graphics.setColor(1.0, 0.65, 0.1)
                love.graphics.setFont(game.fonts.ui)
                love.graphics.printf("⚡", x, y + 2, w, "center")
            end
        end,
        sort_key = function(item) return item.is_rush and 1 or 0 end,
    },
    {
        id = "scope", label = "Scope", width = 60, min_width = 40,
        format   = function(item) return item.scope or "—" end,
        sort_key = function(item) return item.scope or "" end,
    },
    {
        id = "from", label = "From", width = 55, min_width = 40, align = "center",
        draw = function(x, y, w, h, item, game)
            love.graphics.setFont(game.fonts.ui)
            love.graphics.setColor(1, 1, 1)
            love.graphics.printf(sourceArchetypeIcon(item), x, y + 2, w, "center")
        end,
        sort_key = function(item)
            return item.source_client and item.source_client.archetype or ""
        end,
    },
    {
        id = "dest", label = "To", width = 100, min_width = 50,
        format   = function(item, game) return destLabel(item, game) end,
        sort_key = function(item, game) return destLabel(item, game) end,
    },
    {
        id = "cargo", label = "Cargo", width = 50, min_width = 30, align = "right",
        format   = function(item) return tostring(item:getCargoSize()) end,
        sort_key = function(item) return item:getCargoSize() end,
    },
    {
        id = "payout", label = "$", width = 60, min_width = 40, align = "right",
        format   = function(item) return string.format("$%d", item.base_payout or 0) end,
        sort_key = function(item) return item.base_payout or 0 end,
    },
    {
        id = "bonus", label = "Bonus", width = 55, min_width = 40, align = "right",
        format   = function(item) return string.format("%.0f", item:getCurrentBonus() or 0) end,
        sort_key = function(item) return item:getCurrentBonus() or 0 end,
    },
    {
        id = "deadline", label = "Time", width = 50, min_width = 40, align = "right",
        format = function(item)
            if not item.is_rush or not item.deadline then return "—" end
            local remaining = math.max(0, item.deadline - love.timer.getTime())
            return string.format("%ds", math.floor(remaining))
        end,
        sort_key = function(item)
            if not item.is_rush or not item.deadline then return math.huge end
            return math.max(0, item.deadline - love.timer.getTime())
        end,
    },
    {
        id = "wait", label = "Wait", width = 45, min_width = 30, align = "right",
        visible_default = false,
        format   = function(item) return string.format("%ds", math.floor(item.wait_time or 0)) end,
        sort_key = function(item) return item.wait_time or 0 end,
    },
}

return {
    id            = "trips",
    items_fn      = function(game) return game.entities.trips and game.entities.trips.pending or {} end,
    row_id        = function(item) return item end,   -- table identity; trips have no stable id
    hover_entity  = function(item)
        -- Trip hover. GameView looks up the trip by table identity and
        -- draws the route preview + pickup/dropoff dots. The trip's
        -- source client is highlighted by cascading logic in GameView.
        return { kind = "trip", id = item }
    end,
    on_row_click  = function(item, game)
        -- Existing assign-trip event uses index into the pending list.
        local pending = game.entities.trips and game.entities.trips.pending or {}
        for i, t in ipairs(pending) do
            if t == item then
                game.EventBus:publish("ui_assign_trip_clicked", i)
                return
            end
        end
    end,
    empty_message = "No pending trips.",
    -- Rush-first (desc on is_rush=1), then payout desc.
    default_sort  = { column = "rush", direction = "desc" },
    columns       = columns,
}
