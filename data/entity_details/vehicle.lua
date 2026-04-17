-- data/entity_details/vehicle.lua

return {
    title_fn = function(item, game)
        return (item.driver_name or "Vehicle") .. " — " .. (item.type or "?")
    end,
    width = 420,
    sections = {
        { type = "fields", label = "Info", rows = {
            { label = "Driver",   value_fn = function(v) return v.driver_name or "—" end },
            { label = "Type",     value_fn = function(v) return v.type or "?" end },
            { label = "State",    value_fn = function(v) return v.state and v.state.name or "?" end },
            { label = "Depot",    value_fn = function(v) return v.depot and v.depot.name or "—" end },
            { label = "Speed",    value_fn = function(v) return string.format("%.1f", v:getSpeed()) end },
            { label = "Capacity", value_fn = function(v, g)
                local used = #v.cargo + #v.trip_queue
                return string.format("%d / %d", used, v:getEffectiveCapacity(g))
            end },
            { label = "Trips",    value_fn = function(v) return tostring(v.trips_completed or 0) end },
        }},
        { type = "actions", label = "Actions", items = {
            { label = "Recall to Depot",
              action_fn  = function(v, g) v:returnToDepot(g) end,
              enabled_fn = function(v) return v.state and v.state.name ~= "Idle" and v.state.name ~= "Returning" end,
              closes = true },
            { label = "Unassign All Trips",
              action_fn  = function(v, g) v:unassign(g) end,
              enabled_fn = function(v) return #v.trip_queue > 0 or #v.cargo > 0 end,
              closes = true },
        }},
        { type = "list", label = "Trip Queue",
          items_fn  = function(v) return v.trip_queue end,
          format_fn = function(t) return (t.scope or "?") .. "  $" .. (t.base_payout or 0) end,
          empty     = "No trips queued" },
        { type = "list", label = "Cargo (In Transit)",
          items_fn  = function(v) return v.cargo end,
          format_fn = function(t) return (t.scope or "?") .. "  $" .. (t.base_payout or 0) end,
          empty     = "Empty" },
    },
}
