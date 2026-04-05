-- views/components/VehiclesPanelView.lua
local VehiclesPanelView = {}

function VehiclesPanelView.draw(game, ui_manager)
    local state = game.state
    love.graphics.setFont(game.fonts.ui)

    for i, l in ipairs(ui_manager.layout_cache.vehicles) do
        local v = l.vehicle
        local in_transit_count = 0
        for _, trip in ipairs(v.cargo) do if trip.is_in_transit then in_transit_count = in_transit_count + 1 end end
        local cap = string.format("%d/%d", #v.cargo + #v.trip_queue, state.upgrades.vehicle_capacity)
        local transit_info = in_transit_count > 0 and string.format(" (%d moving)", in_transit_count) or ""
        local text = string.format("%s %s %d | %s | %s%s", v:getIcon(), v.type, v.id, v.state.name, cap, transit_info)
        love.graphics.setColor(1,1,1)
        love.graphics.print(text, l.x + 5, l.y + 5)
    end

    local hire_btns = ui_manager.layout_cache.buttons.hire_vehicles or {}
    for _, btn in pairs(hire_btns) do
        local def = game.C.VEHICLES[(btn.vehicle_id or ""):upper()]
        if def and btn then
            local cost = state.costs[btn.vehicle_id] or def.base_cost
            love.graphics.setColor(1,1,1)
            love.graphics.rectangle("line", btn.x, btn.y, btn.w, btn.h)
            love.graphics.printf(
                string.format("Hire %s %s ($%d)", def.icon, def.display_name, cost),
                btn.x, btn.y + 8, btn.w, "center"
            )
        end
    end
end

return VehiclesPanelView
