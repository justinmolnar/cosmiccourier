-- views/components/TripsPanelView.lua
local TripsPanelView = {}

function TripsPanelView.draw(game, ui_manager)
    love.graphics.setFont(game.fonts.ui)

    for i, l in ipairs(ui_manager.layout_cache.trips) do
        local trip = l.trip
        love.graphics.setColor(1,1,1)
        local current_bonus = math.floor(trip:getCurrentBonus())
        local text = string.format("Trip %d: $%d + $%d", i, trip.base_payout, current_bonus)
        if ui_manager.hovered_trip_index == i then 
            love.graphics.setColor(1, 1, 0, 0.2)
            love.graphics.rectangle("fill", l.x, l.y-2, l.w, l.h+4) 
        end
        love.graphics.setColor(1,1,1)
        love.graphics.print(text, l.x + 5, l.y)
        love.graphics.setFont(game.fonts.ui_small)
        for leg_idx, leg in ipairs(trip.legs) do
            local leg_y = l.y + 18 + ((leg_idx - 1) * 15)
            local icon = (leg.vehicleType == "bike") and "🚲" or "🚚"
            local status_text
            if leg_idx < trip.current_leg then
                status_text = "(Done)"
                love.graphics.setColor(0.5, 1, 0.5, 0.8)
            elseif leg_idx == trip.current_leg then
                status_text = trip.is_in_transit and "(In Transit)" or "(Waiting)"
                love.graphics.setColor(1, 1, 0.5, 1)
            else
                status_text = "(Pending)"
                love.graphics.setColor(1, 1, 1, 0.6)
            end
            local leg_line = string.format("%s Leg %d %s", icon, leg_idx, status_text)
            love.graphics.print(leg_line, l.x + 15, leg_y)
        end
        love.graphics.setFont(game.fonts.ui)
    end
end

return TripsPanelView