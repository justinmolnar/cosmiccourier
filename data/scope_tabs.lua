-- data/scope_tabs.lua
-- Declarative definition of scope-contextual tabs. The City tab is the
-- operational cockpit: depots / vehicles / clients / trips / buildings
-- scoped to the currently-selected city.
--
-- Each section references an existing datagrid source by module path. The
-- `scope_filter` id is looked up in services/ScopeFilterService to narrow
-- the source's items to the current scope entity (city_map for kind "city").
--
-- Pure data — no logic. Section rendering order matches the order here.

return {
    city = {
        id            = "city",
        label         = "City",
        icon          = "🏙️",
        selector_kind = "city",
        sections = {
            { id = "depots",         label = "Depots",         kind = "grid",
              source_module = "data.datagrids.depots",
              scope_filter  = "depot_in_city" },
            { id = "vehicles",       label = "Vehicles",       kind = "grid",
              source_module = "data.datagrids.vehicles",
              scope_filter  = "vehicle_in_city" },
            { id = "vehicle_market", label = "Hire Vehicle",   kind = "grid",
              source_module = "data.datagrids.vehicle_market",
              scope_filter  = nil,  -- market is global
              collapsed_default = true },
            { id = "clients",        label = "Clients",        kind = "grid",
              source_module = "data.datagrids.clients",
              scope_filter  = "client_in_city" },
            { id = "client_market",  label = "Buy Client",     kind = "grid",
              source_module = "data.datagrids.client_market",
              scope_filter  = nil,
              collapsed_default = true },
            { id = "trips",          label = "Pending Trips",  kind = "grid",
              source_module = "data.datagrids.trips",
              scope_filter  = "trip_in_city" },
            { id = "buildings",      label = "Buildings",      kind = "grid",
              source_module = "data.datagrids.placed_buildings",
              scope_filter  = "building_in_city",
              collapsed_default = true },
        },
    },
}
