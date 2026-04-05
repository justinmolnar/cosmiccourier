-- views/tabs/TripsTab.lua
local TripsTab = {}

local mode_text = { road = "road", rail = "rail", water = "water", air = "air" }

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
        return comps
    end

    for i, trip in ipairs(pending) do
        local current_bonus = math.floor(trip:getCurrentBonus())
        local lines = {
            { text = string.format("Trip %d:  $%d base  +  $%d bonus", i, trip.base_payout, current_bonus),
              style = "body" },
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
    return comps
end

return TripsTab
