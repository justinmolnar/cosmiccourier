-- views/tabs/TripsTab.lua
local TripsTab = {}

local mode_text = { road = "road", rail = "rail", water = "water", air = "air" }

local DEBUG_SCOPES = { "district", "city", "region", "continent", "world" }

function TripsTab.build(game, ui_manager)
    local comps   = {}
    local pending = game.entities.trips.pending

    local hovered_idx = nil
    local hc = ui_manager.hovered_component
    if hc and hc.id == "assign_trip" and hc.data then
        hovered_idx = hc.data.index
    end

    if #pending == 0 then
        table.insert(comps, { type = "label", text = "No pending trips.", style = "muted", h = 30 })
    end

    local now = love.timer.getTime()
    for i, trip in ipairs(pending) do
        local current_bonus = math.floor(trip:getCurrentBonus())
        local header
        if trip.is_rush then
            local remaining = math.max(0, math.floor((trip.deadline or now) - now + 0.5))
            header = string.format("⚡ RUSH  Trip %d:  $%d base  +  $%d bonus  —  %ds left",
                i, trip.base_payout, current_bonus, remaining)
        else
            header = string.format("Trip %d:  $%d base  +  $%d bonus", i, trip.base_payout, current_bonus)
        end
        local lines = {
            { text = header, style = trip.is_rush and "warning" or "body" },
        }
        for leg_idx, leg in ipairs(trip.legs) do
            local mode = mode_text[leg.transport_mode] or leg.transport_mode or "road"
            local status
            if leg_idx < trip.current_leg then
                status = "done"
            elseif leg_idx == trip.current_leg then
                status = trip.is_in_transit and "moving" or "waiting"
            else
                status = "queued"
            end
            table.insert(lines, {
                text  = string.format("  leg %d  [%s]  %s", leg_idx, mode, status),
                style = "small",
            })
        end
        table.insert(comps, {
            type    = "button",
            id      = "assign_trip",
            data    = { index = i },
            hovered = (i == hovered_idx),
            lines   = lines,
        })
    end
    -- ── Debug trip spawner ────────────────────────────────────────────────────
    -- ── Debug controls ────────────────────────────────────────────────────────
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
