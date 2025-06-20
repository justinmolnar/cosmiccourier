-- views/UIManager.lua
local UIManager = {}
UIManager.__index = UIManager

function UIManager:new(C, game)
    -- CORRECTED: The paths now correctly point to the new locations of the components.
    local Accordion = require("views.components.Accordion")
    local ModalManager = require("views.modal_manager")

    local instance = setmetatable({}, UIManager)
    
    instance.hovered_trip_index = nil
    
    instance.trips_accordion = Accordion:new("Pending Trips", true, 120)
    instance.upgrades_accordion = Accordion:new("Upgrades", true, 250)
    instance.vehicles_accordion = Accordion:new("Vehicles", false, 150)
    instance.clients_accordion = Accordion:new("Clients", false, 150)
    
    instance.modal_manager = ModalManager:new()

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

function UIManager:handle_scroll(dy)
    local mx, my = love.mouse.getPosition()
    if self.trips_accordion:handle_scroll(mx, my, dy) then return end
end

function UIManager:handle_mouse_down(x, y, button, game)
    if self.modal_manager:handle_mouse_down(x, y, game) then return true end
    if self.trips_accordion:handle_mouse_down(x, y, button) then return true end
    if self.upgrades_accordion:handle_mouse_down(x, y, button) then return true end
    if self.vehicles_accordion:handle_mouse_down(x, y, button) then return true end
    if self.clients_accordion:handle_mouse_down(x, y, button) then return true end
    return false
end

function UIManager:handle_mouse_up(x, y, button)
    if self.modal_manager:handle_mouse_up(x, y) then return end
    self.trips_accordion:handle_mouse_up(x, y, button)
    self.upgrades_accordion:handle_mouse_up(x, y, button)
    self.vehicles_accordion:handle_mouse_up(x, y, button)
    self.clients_accordion:handle_mouse_up(x, y, button)
end

function UIManager:update(dt, game)
    self.modal_manager:update(dt, game)

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

function UIManager:_calculateUpgradesLayoutHeight(categories)
    local total_height = 10
    local category_header_height = 25
    local icon_row_height = 85

    for _, category in ipairs(categories) do
        total_height = total_height + category_header_height
        total_height = total_height + icon_row_height
    end
    return total_height
end

function UIManager:_calculatePerSecondStats(game)
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

function UIManager:_calculateAccordionStats(game)
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

function UIManager:_doLayout(game)
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
                    h = icon_size + 15,
                    event = "ui_upgrade_button_clicked",
                    data = sub_type
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

return UIManager