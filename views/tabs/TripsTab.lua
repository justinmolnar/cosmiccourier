-- views/tabs/TripsTab.lua
-- Trips = one atomic row per pending trip. No legs, no sub-rows. Legs are
-- dispatch-internal; the UI is unaware of them.
local TripsTab = {}

local DEBUG_SCOPES = { "district", "city", "region", "continent", "world" }

function TripsTab.build(game, ui_manager)
    local comps = {
        { type = "datagrid", source = require("data.datagrids.trips") },
    }

    -- ── Debug controls (scoped below the grid; not game-facing UI) ──────────
    table.insert(comps, { type = "label", style = "muted", h = 12, text = "" })
    table.insert(comps, { type = "label", style = "muted", h = 18, text = "── Debug ──" })

    local paused = game.entities.pause_trip_generation or false
    table.insert(comps, {
        type  = "button",
        id    = "toggle_pause_trip_gen",
        data  = {},
        lines = {{ text = paused and "Resume Trip Gen" or "Pause Trip Gen", style = "body" }},
    })

    local sel = game.entities.selected_depot
    if sel then
        table.insert(comps, { type = "label", style = "muted", h = 8, text = "" })
        table.insert(comps, { type = "label", style = "muted", h = 16,
            text = "Spawn from depot:" })
        for _, scope in ipairs(DEBUG_SCOPES) do
            table.insert(comps, {
                type  = "button",
                id    = "debug_spawn_trip",
                data  = { scope = scope },
                lines = {{ text = scope:sub(1,1):upper() .. scope:sub(2), style = "body" }},
            })
        end
    else
        table.insert(comps, { type = "label", style = "muted", h = 16,
            text = "Select a depot to spawn trips" })
    end

    return comps
end

return TripsTab
