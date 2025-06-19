-- ui/ui.lua
local UI = {}
UI.__index = UI

function UI:new(C, game)
    local Accordion = require("ui.accordion")
    local ModalManager = require("ui.modal_manager") -- NEW: Require the modal manager

    local instance = setmetatable({}, UI)
    
    instance.hovered_trip_index = nil
    
    instance.trips_accordion = Accordion:new("Pending Trips", true, 120)
    instance.upgrades_accordion = Accordion:new("Upgrades", true, 250)
    instance.vehicles_accordion = Accordion:new("Vehicles", false, 150)
    instance.clients_accordion = Accordion:new("Clients", false, 150)
    
    instance.modal_manager = ModalManager:new() -- NEW: Create an instance of the manager

    instance.layout_cache = {}
    instance.income_per_second = 0
    instance.trips_per_second = 0
    instance.accordion_stats = {
        trips = "",
        upgrades = "",
        vehicles = "",
        clients = ""
    }

    return instance
end

function UI:handle_scroll(dy)
    local mx, my = love.mouse.getPosition()
    if self.trips_accordion:handle_scroll(mx, my, dy) then return end
end

function UI:handle_mouse_down(x, y, button, game)
    -- MODIFIED: The modal manager now correctly receives the `game` object to pass down.
    if self.modal_manager:handle_mouse_down(x, y, game) then return true end

    if self.trips_accordion:handle_mouse_down(x, y, button) then return true end
    if self.upgrades_accordion:handle_mouse_down(x, y, button) then return true end
    if self.vehicles_accordion:handle_mouse_down(x, y, button) then return true end
    if self.clients_accordion:handle_mouse_down(x, y, button) then return true end
    return false
end

function UI:handle_mouse_up(x, y, button)
    if self.modal_manager:handle_mouse_up(x, y) then return end

    self.trips_accordion:handle_mouse_up(x, y, button)
    self.upgrades_accordion:handle_mouse_up(x, y, button)
    self.vehicles_accordion:handle_mouse_up(x, y, button)
    self.clients_accordion:handle_mouse_up(x, y, button)
end

function UI:update(dt, game)
    -- NEW: Update the modal manager
    self.modal_manager:update(dt, game)

    -- Don't update the rest of the UI if a modal is active
    if self.modal_manager:isActive() then return end

    local C = game.C
    local mx, my = love.mouse.getPosition()
    
    self:_calculatePerSecondStats(game)
    self:_calculateAccordionStats(game)

    local upgrades_content_height = self:_calculateUpgradesLayoutHeight(game.state.Upgrades.categories)
    
    self.trips_accordion:update(#game.entities.trips.pending * 50, my) 
    self.upgrades_accordion:update(upgrades_content_height, my)
    self.vehicles_accordion:update((#game.entities.vehicles * 30) + 80, my)
    self.clients_accordion:update((#game.entities.clients * 20) + 40, my)

    self:_doLayout(game)
    
    self.hovered_trip_index = nil
    if mx < C.UI.SIDEBAR_WIDTH then
        if self.trips_accordion.is_open and mx > self.trips_accordion.x and mx < self.trips_accordion.x + self.trips_accordion.w and my > self.trips_accordion.y + self.trips_accordion.header_h and my < self.trips_accordion.y + self.trips_accordion.header_h + self.trips_accordion.content_h then
            local y_in_content = my - (self.trips_accordion.y + self.trips_accordion.header_h) + self.trips_accordion.scroll_y
            local index = math.floor(y_in_content / 50) + 1
            if index > 0 and index <= #game.entities.trips.pending then self.hovered_trip_index = index end
        end
    end
end

function UI:_calculateUpgradesLayoutHeight(categories)
    local total_height = 10
    local category_header_height = 25
    local icon_row_height = 85

    for _, category in ipairs(categories) do
        total_height = total_height + category_header_height
        total_height = total_height + icon_row_height
    end
    return total_height
end

function UI:_calculatePerSecondStats(game)
    local state = game.state
    local now = love.timer.getTime()
    local window = 15

    local total_income = 0
    for i = #state.income_history, 1, -1 do
        if now - state.income_history[i].time > window then
            table.remove(state.income_history, i)
        else
            total_income = total_income + state.income_history[i].amount
        end
    end
    self.income_per_second = total_income / window

    local trip_count = 0
    for i = #state.trip_creation_history, 1, -1 do
        if now - state.trip_creation_history[i] > window then
            table.remove(state.trip_creation_history, i)
        else
            trip_count = trip_count + 1
        end
    end
    self.trips_per_second = trip_count / window
end

function UI:_calculateAccordionStats(game)
    local state = game.state
    local is_downtown = game.map:getCurrentScale() == game.C.MAP.SCALES.DOWNTOWN

    local core_trips, city_trips = 0, 0
    for _, trip in ipairs(game.entities.trips.pending) do
        local final_leg = trip.legs[#trip.legs]
        if final_leg then
            if game.map:isPlotInDowntown(final_leg.end_plot) then
                core_trips = core_trips + 1
            else
                city_trips = city_trips + 1
            end
        end
    end
    self.accordion_stats.trips = string.format("%d (🏢%d 🏙️%d)", #game.entities.trips.pending, core_trips, city_trips)
    self.accordion_stats.upgrades = "" 

    local bike_count, truck_count, idle_count = 0, 0, 0
    for _, v in ipairs(game.entities.vehicles) do
        local vehicle_is_in_downtown = game.map:isPlotInDowntown(v.grid_anchor)
        if (is_downtown and vehicle_is_in_downtown) or not is_downtown then
            if v.type == "bike" then bike_count = bike_count + 1 end
            if v.type == "truck" then truck_count = truck_count + 1 end
            if v.state.name == "Idle" then idle_count = idle_count + 1 end
        end
    end
    self.accordion_stats.vehicles = string.format("🚲%d 🚚%d 😴%d", bike_count, truck_count, idle_count)

    local client_count = 0
    for _, c in ipairs(game.entities.clients) do
        local client_is_in_downtown = game.map:isPlotInDowntown(c.plot)
        if (is_downtown and client_is_in_downtown) or not is_downtown then
            client_count = client_count + 1
        end
    end
    self.accordion_stats.clients = string.format("%d (%.2f t/s)", client_count, self.trips_per_second)
end

function UI:_doLayout(game)
    self.layout_cache = { trips = {}, upgrades = { buttons = {} }, vehicles = {}, clients = {}, buttons = {} }
    local C = game.C
    local p = C.UI.PADDING
    local w = C.UI.SIDEBAR_WIDTH - (p * 2)
    local y_cursor = 120

    self.trips_accordion.x, self.trips_accordion.y, self.trips_accordion.w = p, y_cursor, w
    local content_y = y_cursor + self.trips_accordion.header_h
    if self.trips_accordion.is_open then
        for i, trip in ipairs(game.entities.trips.pending) do
            self.layout_cache.trips[i] = { trip = trip, x = p, y = content_y + ((i-1) * 50), w = w, h = 50 } 
        end
    end
    y_cursor = y_cursor + self.trips_accordion.header_h + (self.trips_accordion.is_open and self.trips_accordion.content_h or 0) + 10

    self.upgrades_accordion.x, self.upgrades_accordion.y, self.upgrades_accordion.w = p, y_cursor, w
    content_y = y_cursor + self.upgrades_accordion.header_h
    if self.upgrades_accordion.is_open then
        local upgrade_y_cursor = content_y + 10
        local icon_size = 64
        local icon_padding = 15

        for _, category in ipairs(game.state.Upgrades.categories) do
            self.layout_cache.upgrades[category.id] = { type = "header", text = category.name, x = p, y = upgrade_y_cursor, w = w }
            upgrade_y_cursor = upgrade_y_cursor + 25
            local icon_x_cursor = p + icon_padding
            for _, sub_type in ipairs(category.sub_types) do
                table.insert(self.layout_cache.upgrades.buttons, {
                    id = sub_type.id,
                    icon = sub_type.icon,
                    name = sub_type.name,
                    x = icon_x_cursor,
                    y = upgrade_y_cursor,
                    w = icon_size,
                    h = icon_size + 15
                })
                icon_x_cursor = icon_x_cursor + icon_size + icon_padding
            end
            upgrade_y_cursor = upgrade_y_cursor + icon_size + 30
        end
    end
    y_cursor = y_cursor + self.upgrades_accordion.header_h + (self.upgrades_accordion.is_open and self.upgrades_accordion.content_h or 0) + 10

    self.vehicles_accordion.x, self.vehicles_accordion.y, self.vehicles_accordion.w = p, y_cursor, w
    content_y = y_cursor + self.vehicles_accordion.header_h
    if self.vehicles_accordion.is_open then
        self.layout_cache.buttons.hire_bike = { x = p + 5, y = content_y + 5, w = w - 10, h = 30 }
        self.layout_cache.buttons.hire_truck = { x = p + 5, y = content_y + 40, w = w - 10, h = 30 }
        local list_start_y = content_y + 80
        for i, vehicle in ipairs(game.entities.vehicles) do
            self.layout_cache.vehicles[i] = { vehicle = vehicle, x = p, y = list_start_y + ((i-1) * 30), w = w, h = 30 }
        end
    end
    y_cursor = y_cursor + self.vehicles_accordion.header_h + (self.vehicles_accordion.is_open and self.vehicles_accordion.content_h or 0) + 10

    self.clients_accordion.x, self.clients_accordion.y, self.clients_accordion.w = p, y_cursor, w
    content_y = y_cursor + self.clients_accordion.header_h
    if self.clients_accordion.is_open then
        self.layout_cache.buttons.buy_client = { x = p + 5, y = content_y + 5, w = w - 10, h = 30 }
        local list_start_y = content_y + 40
        for i, client in ipairs(game.entities.clients) do
            self.layout_cache.clients[i] = { client = client, x = p, y = list_start_y + ((i-1) * 20), w = w, h = 20 }
        end
    end
end

function UI:draw(game)
    local C = game.C
    local state = game.state
    love.graphics.setFont(game.fonts.ui)
    love.graphics.setColor(1, 1, 1)

    love.graphics.print("Money: $" .. math.floor(state.money), 10, 10)
    love.graphics.printf(string.format("$%.2f/s", self.income_per_second), 0, 10, C.UI.SIDEBAR_WIDTH - 10, "right")
    love.graphics.print("Trips Completed: " .. state.trips_completed, 10, 30)
    love.graphics.print("Vehicles: " .. #game.entities.vehicles, 10, 50)
    love.graphics.print("Clients: " .. #game.entities.clients, 10, 70)

    if state.rush_hour.active then
        love.graphics.setColor(1,1,0)
        love.graphics.printf(string.format("RUSH HOUR: %ds", math.ceil(state.rush_hour.timer)), 0, 95, C.UI.SIDEBAR_WIDTH, "center")
    end

    self.trips_accordion:beginDraw(self.accordion_stats.trips)
    if self.trips_accordion.is_open then
        for i, l in ipairs(self.layout_cache.trips) do
            local trip = l.trip
            love.graphics.setColor(1,1,1)
            local current_bonus = math.floor(trip:getCurrentBonus())
            local text = string.format("Trip %d: $%d + $%d", i, trip.base_payout, current_bonus)
            if self.hovered_trip_index == i then 
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
    self.trips_accordion:endDraw(); self.trips_accordion:drawScrollbar()
    
    self.upgrades_accordion:beginDraw(self.accordion_stats.upgrades)
    if self.upgrades_accordion.is_open then
        love.graphics.setFont(game.fonts.ui)
        for id, l in pairs(self.layout_cache.upgrades) do
            if l.type == "header" then
                love.graphics.setColor(0.7, 0.7, 0.8)
                love.graphics.print(l.text, l.x + 5, l.y)
                love.graphics.line(l.x, l.y + 20, l.x + l.w, l.y + 20)
            end
        end
        for _, btn in ipairs(self.layout_cache.upgrades.buttons) do
            love.graphics.setColor(0.3, 0.3, 0.35)
            love.graphics.rectangle("fill", btn.x, btn.y, btn.w, btn.w)
            love.graphics.setColor(1, 1, 1)
            love.graphics.rectangle("line", btn.x, btn.y, btn.w, btn.w)
            love.graphics.setFont(game.fonts.emoji_ui)
            love.graphics.printf(btn.icon, btn.x, btn.y + 5, btn.w, "center")
            love.graphics.setFont(game.fonts.ui_small)
            love.graphics.printf(btn.name, btn.x, btn.y + btn.w - 5, btn.w, "center")
        end
    end
    self.upgrades_accordion:endDraw(); self.upgrades_accordion:drawScrollbar()

    self.vehicles_accordion:beginDraw(self.accordion_stats.vehicles)
    if self.vehicles_accordion.is_open then
        love.graphics.setFont(game.fonts.ui)
        for i, l in ipairs(self.layout_cache.vehicles) do
            local v = l.vehicle
            local in_transit_count = 0
            for _, trip in ipairs(v.cargo) do if trip.is_in_transit then in_transit_count = in_transit_count + 1 end end
            local cap = string.format("%d/%d", #v.cargo + #v.trip_queue, state.upgrades.vehicle_capacity)
            local transit_info = in_transit_count > 0 and string.format(" (%d moving)", in_transit_count) or ""
            local text = string.format("%s %d | %s | %s%s", v.type, v.id, v.state.name, cap, transit_info)
            love.graphics.setColor(1,1,1)
            love.graphics.print(text, l.x + 5, l.y + 5)
        end
        local bike_btn = self.layout_cache.buttons.hire_bike
        if bike_btn then love.graphics.setColor(1,1,1); love.graphics.rectangle("line", bike_btn.x, bike_btn.y, bike_btn.w, bike_btn.h); love.graphics.printf("Hire New Bike ($"..state.costs.bike..")", bike_btn.x, bike_btn.y+8, bike_btn.w, "center") end
        local truck_btn = self.layout_cache.buttons.hire_truck
        if truck_btn then love.graphics.setColor(1,1,1); love.graphics.rectangle("line", truck_btn.x, truck_btn.y, truck_btn.w, truck_btn.h); love.graphics.printf("Hire New Truck ($"..state.costs.truck..")", truck_btn.x, truck_btn.y+8, truck_btn.w, "center") end
    end
    self.vehicles_accordion:endDraw(); self.vehicles_accordion:drawScrollbar()

    self.clients_accordion:beginDraw(self.accordion_stats.clients)
    if self.clients_accordion.is_open then
        love.graphics.setFont(game.fonts.ui)
        for i, l in ipairs(self.layout_cache.clients) do
            love.graphics.setColor(1,1,1); love.graphics.print("Client #"..i, l.x+5, l.y)
        end
        local btn = self.layout_cache.buttons.buy_client
        if btn then love.graphics.setColor(1,1,1); love.graphics.rectangle("line", btn.x, btn.y, btn.w, btn.h); love.graphics.printf("Market for New Client ($"..state.costs.client..")", btn.x, btn.y+8, btn.w, "center") end
    end
    self.clients_accordion:endDraw(); self.clients_accordion:drawScrollbar()
end

function UI:handle_click(x, y, game)
    -- The modal manager gets the first chance to handle clicks. If it handles it, we stop.
    if self.modal_manager:handle_mouse_down(x, y, game) then return true end

    if self.trips_accordion:handle_click(x, y) then return true end
    if self.upgrades_accordion:handle_click(x, y) then return true end
    if self.vehicles_accordion:handle_click(x, y) then return true end
    if self.clients_accordion:handle_click(x, y) then return true end

    if self.hovered_trip_index then game.EventBus:publish("ui_assign_trip_clicked", self.hovered_trip_index); return true end
    
    if self.upgrades_accordion.is_open then
        local Modal = require("ui.modal")
        for _, btn in ipairs(self.layout_cache.upgrades.buttons) do
            if x > btn.x and x < btn.x + btn.w and y > btn.y and y < btn.y + btn.h then
                -- NEW: Find the correct tech tree data and pass it to the modal
                local tech_tree_data = nil
                for _, category in ipairs(game.state.Upgrades.categories) do
                    for _, sub_type in ipairs(category.sub_types) do
                        if sub_type.id == btn.id then
                            tech_tree_data = sub_type
                            break
                        end
                    end
                    if tech_tree_data then break end
                end

                if tech_tree_data then
                    local modal_title = btn.name .. " Upgrades"
                    local on_close = function() self.modal_manager:hide() end
                    -- Pass the tech tree data into the modal's constructor
                    local new_modal = Modal:new(modal_title, 800, 600, on_close, tech_tree_data)
                    self.modal_manager:show(new_modal)
                end
                return true
            end
        end
    end

    local hire_bike_btn = self.layout_cache.buttons.hire_bike
    if hire_bike_btn and x > hire_bike_btn.x and x < hire_bike_btn.x + hire_bike_btn.w and y > hire_bike_btn.y and y < hire_bike_btn.y + hire_bike_btn.h then
        game.EventBus:publish("ui_buy_vehicle_clicked", "bike")
        return true
    end

    local hire_truck_btn = self.layout_cache.buttons.hire_truck
    if hire_truck_btn and x > hire_truck_btn.x and x < hire_truck_btn.x + hire_truck_btn.w and y > hire_truck_btn.y and y < hire_truck_btn.y + hire_truck_btn.h then
        game.EventBus:publish("ui_buy_vehicle_clicked", "truck")
        return true
    end

    local client_btn = self.layout_cache.buttons.buy_client
    if client_btn and x > client_btn.x and x < client_btn.x + client_btn.w and y > client_btn.y and y < client_btn.y + client_btn.h then
        game.EventBus:publish("ui_buy_client_clicked")
        return true
    end

    return false
end

return UI