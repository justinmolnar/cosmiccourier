-- data/entity_details/depot.lua

return {
    title_fn = function(item) return item.name or item.id or "Depot" end,
    width = 420,
    sections = {
        { type = "fields", label = "Info", rows = {
            { label = "Name",     value_fn = function(d) return d.name or d.id or "—" end },
            { label = "City",     value_fn = function(d, g) local c = d:getCity(g); return c and (c.name or c.id) or "—" end },
            { label = "District", value_fn = function(d, g) return d:getDistrict(g) or "—" end },
            { label = "Vehicles", value_fn = function(d) return tostring(#(d.assigned_vehicles or {})) end },
            { label = "Cargo",    value_fn = function(d) return string.format("%d / %d", #(d.cargo or {}), d.capacity or 0) end },
            { label = "Trips",    value_fn = function(d) return tostring(d.analytics and d.analytics.trips_completed or 0) end },
            { label = "Income",   value_fn = function(d) return string.format("$%d", d.analytics and d.analytics.income_generated or 0) end },
        }},
        { type = "list", label = "Assigned Vehicles",
          items_fn  = function(d) return d.assigned_vehicles or {} end,
          format_fn = function(v) return (v.driver_name or "?") .. " — " .. (v.state and v.state.name or "?") end,
          empty     = "No vehicles assigned" },
    },
}
