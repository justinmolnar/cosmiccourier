-- ui/ui.lua
local UI = {}
UI.__index = UI

function UI:new(C, game)
    local Accordion = require("ui.accordion")
    local instance = setmetatable({}, UI)
    
    instance.hovered_trip_index = nil
    instance.hovered_upgrade_id = nil
    
    -- Create instances of the accordion for all our lists
    instance.trips_accordion = Accordion:new("Pending Trips", true, 120)
    instance.upgrades_accordion = Accordion:new("Upgrades", true, 250)
    instance.vehicles_accordion = Accordion:new("Vehicles", false, 150) -- Starts closed
    instance.clients_accordion = Accordion:new("Clients", false, 150) -- Starts closed
    
    instance.sorted_upgrades = {}
    
    -- This will hold the calculated positions of UI elements each frame
    instance.layout_cache = {}

    return instance
end

function UI:handle_scroll(dy)
    local mx, my = love.mouse.getPosition()
    -- Give each accordion a chance to handle the scroll
    if self.trips_accordion:handle_scroll(mx, my, dy) then return end
    if self.upgrades_accordion:handle_scroll(mx, my, dy) then return end
end

function UI:handle_mouse_down(x, y, button)
    if self.trips_accordion:handle_mouse_down(x, y, button) then return true end
    if self.upgrades_accordion:handle_mouse_down(x, y, button) then return true end
    if self.vehicles_accordion:handle_mouse_down(x, y, button) then return true end
    if self.clients_accordion:handle_mouse_down(x, y, button) then return true end
    return false
end

function UI:handle_mouse_up(x, y, button)
    self.trips_accordion:handle_mouse_up(x, y, button)
    self.upgrades_accordion:handle_mouse_up(x, y, button)
    self.vehicles_accordion:handle_mouse_up(x, y, button)
    self.clients_accordion:handle_mouse_up(x, y, button)
end

function UI:update(dt, game)
    local C = game.C
    local state = game.state
    local mx, my = love.mouse.getPosition()
    
    local available_upgrades = {}
    for id, upgrade_data in pairs(state.AllUpgrades) do
        local current_level = state.upgrades_purchased[id] or 0
        if current_level < upgrade_data.max_level then
            local should_show = false
            if current_level > 0 then should_show = true
            else
                if state.upgrades_discovered[id] then should_show = true
                else
                    if state.money >= (upgrade_data.cost * 0.75) then
                        state.upgrades_discovered[id] = "discovered"
                        should_show = true
                    end
                end
                if state.upgrades_discovered[id] == "discovered" and state.money >= (upgrade_data.cost * 0.90) then
                    state.upgrades_discovered[id] = "price_revealed"
                end
            end
            if should_show then
                local cost = upgrade_data.cost * (upgrade_data.cost_multiplier ^ current_level)
                table.insert(available_upgrades, { id = id, data = upgrade_data, display_cost = cost, level = current_level })
            end
        end
    end
    table.sort(available_upgrades, function(a, b) return a.display_cost < b.display_cost end)
    self.sorted_upgrades = available_upgrades

    self.trips_accordion:update(#game.entities.trips.pending * C.UI.TRIP_LIST_Y_STEP, my)
    self.upgrades_accordion:update(#self.sorted_upgrades * 55, my)
    self.vehicles_accordion:update((#game.entities.vehicles * 30) + 40, my)
    self.clients_accordion:update((#game.entities.clients * 20) + 40, my)

    self:_doLayout(game)
    
    self.hovered_trip_index, self.hovered_upgrade_id, self.hovered_vehicle_id, self.hovered_client_id = nil, nil, nil, nil
    if mx < C.UI.SIDEBAR_WIDTH then
        if self.trips_accordion.is_open and mx > self.trips_accordion.x and mx < self.trips_accordion.x + self.trips_accordion.w and my > self.trips_accordion.y + self.trips_accordion.header_h and my < self.trips_accordion.y + self.trips_accordion.header_h + self.trips_accordion.content_h then
            local y_in_content = my - (self.trips_accordion.y + self.trips_accordion.header_h) + self.trips_accordion.scroll_y
            local index = math.floor(y_in_content / C.UI.TRIP_LIST_Y_STEP) + 1
            if index > 0 and index <= #game.entities.trips.pending then self.hovered_trip_index = index end
        end
        if self.upgrades_accordion.is_open and mx > self.upgrades_accordion.x and mx < self.upgrades_accordion.x + self.upgrades_accordion.w and my > self.upgrades_accordion.y + self.upgrades_accordion.header_h and my < self.upgrades_accordion.y + self.upgrades_accordion.header_h + self.upgrades_accordion.content_h then
            local y_in_content = my - (self.upgrades_accordion.y + self.upgrades_accordion.header_h) + self.upgrades_accordion.scroll_y
            local index = math.floor(y_in_content / 55) + 1
            if index > 0 and index <= #self.sorted_upgrades then self.hovered_upgrade_id = self.sorted_upgrades[index].id end
        end
    end
end

function UI:_doLayout(game)
    self.layout_cache = {
        trips = {},
        upgrades = {},
        vehicles = {},
        clients = {},
        buttons = {}
    }
    local C = game.C
    local p = C.UI.PADDING
    local w = C.UI.SIDEBAR_WIDTH - (p * 2)
    local y_cursor = 100

    -- == Trips Accordion ==
    self.trips_accordion.x, self.trips_accordion.y, self.trips_accordion.w = p, y_cursor, w
    local content_y = y_cursor + self.trips_accordion.header_h
    if self.trips_accordion.is_open then
        for i, trip in ipairs(game.entities.trips.pending) do
            self.layout_cache.trips[i] = { trip = trip, x = p, y = content_y + ((i-1) * C.UI.TRIP_LIST_Y_STEP), w = w, h = C.UI.TRIP_LIST_Y_STEP }
        end
    end
    y_cursor = y_cursor + self.trips_accordion.header_h + (self.trips_accordion.is_open and self.trips_accordion.content_h or 0) + 10

    -- == Upgrades Accordion ==
    self.upgrades_accordion.x, self.upgrades_accordion.y, self.upgrades_accordion.w = p, y_cursor, w
    content_y = y_cursor + self.upgrades_accordion.header_h
    if self.upgrades_accordion.is_open then
        for i, upgrade_entry in ipairs(self.sorted_upgrades) do
            self.layout_cache.upgrades[upgrade_entry.id] = { upgrade_entry = upgrade_entry, x = p, y = content_y + ((i-1) * 55), w = w, h = 50 }
        end
    end
    y_cursor = y_cursor + self.upgrades_accordion.header_h + (self.upgrades_accordion.is_open and self.upgrades_accordion.content_h or 0) + 10

    -- == Vehicles Accordion ==
    self.vehicles_accordion.x, self.vehicles_accordion.y, self.vehicles_accordion.w = p, y_cursor, w
    content_y = y_cursor + self.vehicles_accordion.header_h
    if self.vehicles_accordion.is_open then
        -- Button is now at the top of the content area
        self.layout_cache.buttons.hire_vehicle = { x = p + 5, y = content_y + 5, w = w - 10, h = 30 }
        local list_start_y = content_y + 40 -- List starts below the button
        for i, vehicle in ipairs(game.entities.vehicles) do
            self.layout_cache.vehicles[i] = { vehicle = vehicle, x = p, y = list_start_y + ((i-1) * 30), w = w, h = 30 }
        end
    end
    y_cursor = y_cursor + self.vehicles_accordion.header_h + (self.vehicles_accordion.is_open and self.vehicles_accordion.content_h or 0) + 10

    -- == Clients Accordion ==
    self.clients_accordion.x, self.clients_accordion.y, self.clients_accordion.w = p, y_cursor, w
    content_y = y_cursor + self.clients_accordion.header_h
    if self.clients_accordion.is_open then
        -- Button is now at the top of the content area
        self.layout_cache.buttons.buy_client = { x = p + 5, y = content_y + 5, w = w - 10, h = 30 }
        local list_start_y = content_y + 40 -- List starts below the button
        for i, client in ipairs(game.entities.clients) do
            self.layout_cache.clients[i] = { client = client, x = p, y = list_start_y + ((i-1) * 20), w = w, h = 20 }
        end
    end
end

function UI:draw(game)
    local C = game.C
    local state = game.state
    local entities = game.entities
    love.graphics.setFont(game.fonts.ui)
    love.graphics.setColor(1, 1, 1)

    love.graphics.print("Money: $" .. math.floor(state.money), 10, 10)
    love.graphics.print("Scale: " .. game.map:getScaleName(), 10, 30)
    love.graphics.print("Bikes: " .. #entities.vehicles, 10, 50)
    love.graphics.print("Clients: " .. #entities.clients, 10, 70)
    if state.rush_hour.active then
        love.graphics.setColor(1,1,0)
        love.graphics.printf(string.format("RUSH HOUR: %ds", math.ceil(state.rush_hour.timer)), 0, 90, C.UI.SIDEBAR_WIDTH, "center")
    end

    self.trips_accordion:beginDraw()
    if self.trips_accordion.is_open then
        for i, l in ipairs(self.layout_cache.trips) do
            love.graphics.setColor(1,1,1)
            local current_bonus = math.floor(l.trip:getCurrentBonus())
            local status_text = l.trip.is_in_transit and " (moving)" or ""
            local text = string.format("Trip %d: $%d + $%d%s", i, l.trip.base_payout, current_bonus, status_text)
            
            if self.hovered_trip_index == i then 
                love.graphics.setColor(1, 1, 0, 0.2)
                love.graphics.rectangle("fill", l.x, l.y-2, l.w, l.h+4) 
            end
            love.graphics.setColor(1,1,1)
            love.graphics.print(text, l.x + 5, l.y)
        end
    end
    self.trips_accordion:endDraw(); self.trips_accordion:drawScrollbar()
    
    self.upgrades_accordion:beginDraw()
    if self.upgrades_accordion.is_open then
        for id, l in pairs(self.layout_cache.upgrades) do
            local upgrade_entry = l.upgrade_entry
            local cost = upgrade_entry.display_cost; local upgrade = upgrade_entry.data; local level = upgrade_entry.level
            if self.hovered_upgrade_id == id then love.graphics.setColor(1, 1, 0, 0.1); love.graphics.rectangle("fill", l.x, l.y, l.w, l.h) end
            if state.money < cost then love.graphics.setColor(0.5,0.5,0.5) else love.graphics.setColor(1,1,1) end
            love.graphics.setFont(game.fonts.emoji_ui); love.graphics.print(upgrade.icon, l.x+5, l.y+5); love.graphics.setFont(game.fonts.ui)
            love.graphics.print(upgrade.name, l.x+45, l.y+7); love.graphics.setFont(game.fonts.ui_small); love.graphics.print(upgrade.description, l.x+45, l.y+28)
            local text = level > 0 and ("$"..math.floor(cost)) or (state.upgrades_discovered[id] == "price_revealed" and ("$"..math.floor(cost)) or "???")
            love.graphics.setFont(game.fonts.ui); love.graphics.printf(text, l.x, l.y+15, l.w-10, "right")
        end
    end
    self.upgrades_accordion:endDraw(); self.upgrades_accordion:drawScrollbar()

    self.vehicles_accordion:beginDraw()
    if self.vehicles_accordion.is_open then
        for i, l in ipairs(self.layout_cache.vehicles) do
            local v = l.vehicle
            local in_transit_count = 0
            for _, trip in ipairs(v.cargo) do
                if trip.is_in_transit then in_transit_count = in_transit_count + 1 end
            end
            local cap = string.format("%d/%d", #v.cargo + #v.trip_queue, state.upgrades.vehicle_capacity)
            local transit_info = in_transit_count > 0 and string.format(" (%d moving)", in_transit_count) or ""
            local text = string.format("Bike %d | %s | %s%s", v.id, v.state.name, cap, transit_info)
            love.graphics.setColor(1,1,1)
            love.graphics.print(text, l.x + 5, l.y + 5)
        end
        local btn = self.layout_cache.buttons.hire_vehicle
        if btn then love.graphics.setColor(1,1,1); love.graphics.rectangle("line", btn.x, btn.y, btn.w, btn.h); love.graphics.printf("Hire New Bike ($"..state.costs.bike..")", btn.x, btn.y+8, btn.w, "center") end
    end
    self.vehicles_accordion:endDraw(); self.vehicles_accordion:drawScrollbar()

    self.clients_accordion:beginDraw()
    if self.clients_accordion.is_open then
        for i, l in ipairs(self.layout_cache.clients) do
            love.graphics.setColor(1,1,1); love.graphics.print("Client #"..i, l.x+5, l.y)
        end
        local btn = self.layout_cache.buttons.buy_client
        if btn then love.graphics.setColor(1,1,1); love.graphics.rectangle("line", btn.x, btn.y, btn.w, btn.h); love.graphics.printf("Market for New Client ($"..state.costs.client..")", btn.x, btn.y+8, btn.w, "center") end
    end
    self.clients_accordion:endDraw(); self.clients_accordion:drawScrollbar()
end

function UI:handle_click(x, y, game)
    if self.trips_accordion:handle_click(x, y) then return true end
    if self.upgrades_accordion:handle_click(x, y) then return true end
    if self.vehicles_accordion:handle_click(x, y) then return true end
    if self.clients_accordion:handle_click(x, y) then return true end

    -- Handle clicks on content within open accordions
    if self.hovered_trip_index then game.EventBus:publish("ui_assign_trip_clicked", self.hovered_trip_index); return true end
    if self.hovered_upgrade_id then game.EventBus:publish("ui_purchase_upgrade_clicked", self.hovered_upgrade_id); return true end

    -- Handle clicks on the new buttons
    local hire_btn = self.layout_cache.buttons.hire_vehicle
    if hire_btn and x > hire_btn.x and x < hire_btn.x + hire_btn.w and y > hire_btn.y and y < hire_btn.y + hire_btn.h then
        game.EventBus:publish("ui_buy_vehicle_clicked", "bike")
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