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
        -- Here we call the new getIcon() method
        local text = string.format("%s %s %d | %s | %s%s", v:getIcon(), v.type, v.id, v.state.name, cap, transit_info)
        love.graphics.setColor(1,1,1)
        love.graphics.print(text, l.x + 5, l.y + 5)
    end
    
    local bike_btn = ui_manager.layout_cache.buttons.hire_bike
    if bike_btn then 
        love.graphics.setColor(1,1,1)
        love.graphics.rectangle("line", bike_btn.x, bike_btn.y, bike_btn.w, bike_btn.h)
        love.graphics.printf("Hire New Bike ($"..state.costs.bike..")", bike_btn.x, bike_btn.y+8, bike_btn.w, "center") 
    end
    
    local truck_btn = ui_manager.layout_cache.buttons.hire_truck
    if truck_btn then 
        love.graphics.setColor(1,1,1)
        love.graphics.rectangle("line", truck_btn.x, truck_btn.y, truck_btn.w, truck_btn.h)
        love.graphics.printf("Hire New Truck ($"..state.costs.truck..")", truck_btn.x, truck_btn.y+8, truck_btn.w, "center") 
    end
end

return VehiclesPanelView