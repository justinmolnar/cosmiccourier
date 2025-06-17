-- core/state.lua
local State = {}
State.__index = State

function State:new(C)
    local instance = setmetatable({}, State)
    
    instance.money = C.GAMEPLAY.INITIAL_MONEY
    instance.upgrades = {
        bike_speed = C.GAMEPLAY.INITIAL_BIKE_SPEED,
        auto_dispatch_unlocked = false,
        vehicle_capacity = 1,
        frenzy_duration = C.EVENTS.INITIAL_DURATION_SEC,
    }
    
    instance.costs = {
        bike = C.COSTS.BIKE,
        speed = C.COSTS.SPEED,
        client = C.COSTS.CLIENT,
        auto_dispatch = C.COSTS.AUTO_DISPATCH,
        capacity = C.COSTS.CAPACITY,
        frenzy_duration = C.COSTS.FRENZY_DURATION,
    }

    instance.rush_hour = {
        active = false,
        timer = 0
    }
    
    instance.vehicles = {}
    instance.clients = {}
    instance.trips = { pending = {} }
    instance.floating_texts = {}


    instance.selected_vehicle = nil
    instance.hovered_trip_index = nil

    local p = C.UI.PADDING
    local w = C.UI.SIDEBAR_WIDTH - (p * 2)
    instance.ui_buttons = {
        { id="buy_bike",         x=p, y=C.UI.BUTTONS_Y_START + (C.UI.BUTTONS_Y_STEP * 0), w=w, h=C.UI.BUTTON_HEIGHT, text="Buy Bike",         cost_key="bike" },
        { id="upgrade_speed",    x=p, y=C.UI.BUTTONS_Y_START + (C.UI.BUTTONS_Y_STEP * 1), w=w, h=C.UI.BUTTON_HEIGHT, text="Upgrade Speed",    cost_key="speed" },
        { id="upgrade_capacity", x=p, y=C.UI.BUTTONS_Y_START + (C.UI.BUTTONS_Y_STEP * 2), w=w, h=C.UI.BUTTON_HEIGHT, text="Upgrade Capacity",   cost_key="capacity" },
        { id="upgrade_frenzy",   x=p, y=C.UI.BUTTONS_Y_START + (C.UI.BUTTONS_Y_STEP * 3), w=w, h=C.UI.BUTTON_HEIGHT, text="Upgrade Frenzy Time",cost_key="frenzy_duration" },
        { id="buy_client",       x=p, y=C.UI.BUTTONS_Y_START + (C.UI.BUTTONS_Y_STEP * 5), w=w, h=C.UI.BUTTON_HEIGHT, text="New Client",       cost_key="client" },
        { id="buy_autodisp",     x=p, y=C.UI.BUTTONS_Y_START + (C.UI.BUTTONS_Y_STEP * 6), w=w, h=C.UI.BUTTON_HEIGHT, text="Auto-Dispatcher",  cost_key="auto_dispatch" },
    }

    return instance
end

function State:addMoney(amount)
    self.money = self.money + amount
end

function State:update(dt, game)
    local C = game.C
    local mx, my = love.mouse.getPosition()
    self.hovered_trip_index = nil -- Reset each frame

    -- Count down the Rush Hour timer if it's active
    if self.rush_hour.active then
        self.rush_hour.timer = self.rush_hour.timer - dt
        if self.rush_hour.timer <= 0 then
            self.rush_hour.active = false
            print("Rush hour over.")
        end
    end

    -- Tick down the speed bonus for all pending trips
    for _, trip in ipairs(self.trips.pending) do
        trip.speed_bonus = trip.speed_bonus - dt
        if trip.speed_bonus < 0 then
            trip.speed_bonus = 0
        end
    end

    -- Update all floating texts
    for i = #self.floating_texts, 1, -1 do
        local text = self.floating_texts[i]
        text.y = text.y + C.EFFECTS.PAYOUT_TEXT_FLOAT_SPEED * dt -- Move up
        text.timer = text.timer - dt
        text.alpha = text.timer / C.EFFECTS.PAYOUT_TEXT_LIFESPAN_SEC -- Fade out
        
        if text.timer <= 0 then
            table.remove(self.floating_texts, i)
        end
    end

    if mx < C.UI.SIDEBAR_WIDTH then
        for i, trip in ipairs(self.trips.pending) do
            local y_pos = C.UI.TRIP_LIST_Y_START + (i * C.UI.TRIP_LIST_Y_STEP)
            if my > y_pos and my < y_pos + C.UI.TRIP_LIST_Y_STEP and mx > C.UI.PADDING and mx < C.UI.SIDEBAR_WIDTH - C.UI.PADDING then
                self.hovered_trip_index = i
                break
            end
        end
    end
end

function State:draw(game)
    local C = game.C
    love.graphics.setFont(game.fonts.ui)
    love.graphics.setColor(1, 1, 1)

    -- Draw main stats at the top of the sidebar
    love.graphics.print("Money: $" .. math.floor(self.money), C.UI.PADDING, C.UI.STATS_Y_START + (C.UI.STATS_Y_STEP * 0))
    love.graphics.print("Bikes: " .. #self.vehicles, C.UI.PADDING, C.UI.STATS_Y_START + (C.UI.STATS_Y_STEP * 1))
    love.graphics.print("Clients: " .. #self.clients, C.UI.PADDING, C.UI.STATS_Y_START + (C.UI.STATS_Y_STEP * 2))
    
    if self.rush_hour.active then
        love.graphics.setColor(1,1,0)
        local timer_text = string.format("RUSH HOUR: %ds", math.ceil(self.rush_hour.timer))
        love.graphics.printf(timer_text, 0, C.UI.STATS_Y_START + (C.UI.STATS_Y_STEP * 3.5), C.UI.SIDEBAR_WIDTH, "center")
        love.graphics.setColor(1,1,1)
    end

    love.graphics.line(C.UI.PADDING, C.UI.DIVIDER_Y, C.UI.SIDEBAR_WIDTH - C.UI.PADDING, C.UI.DIVIDER_Y)

    -- Draw Pending Trips UI
    love.graphics.print("Pending Trips:", C.UI.PADDING, C.UI.TRIP_LIST_Y_START)
    for i, trip in ipairs(self.trips.pending) do
        local y_pos = C.UI.TRIP_LIST_Y_START + (i * C.UI.TRIP_LIST_Y_STEP)
        -- Create the dynamic text showing the base + ticking bonus
        local bonus = math.floor(trip.speed_bonus)
        local trip_text = string.format("Trip %d: $%d + $%d", i, trip.base_payout, bonus)
        
        if i == self.hovered_trip_index then
            local hover_color = C.MAP.COLORS.HOVER
            love.graphics.setColor(hover_color[1], hover_color[2], hover_color[3], 0.2)
            love.graphics.rectangle("fill", C.UI.PADDING / 2, y_pos - 2, C.UI.SIDEBAR_WIDTH - C.UI.PADDING, C.UI.TRIP_LIST_Y_STEP)
            love.graphics.setColor(1, 1, 1)
        end

        love.graphics.print(trip_text, C.UI.PADDING + 5, y_pos)
    end

    -- Draw selected vehicle info
    if self.selected_vehicle then
        local v = self.selected_vehicle
        local status_name = v.state and v.state.name or "Unknown"
        local capacity_text = string.format("Bike %d | Status: %s | Capacity: %d/%d", v.id, status_name, #v.cargo + #v.trip_queue, self.upgrades.vehicle_capacity)
        love.graphics.print(capacity_text, C.UI.PADDING, love.graphics.getHeight() - (C.UI.PADDING * 8))
        love.graphics.print("Cargo (" .. #v.cargo .. "):", C.UI.PADDING, love.graphics.getHeight() - (C.UI.PADDING * 7))
        love.graphics.print("Queue (" .. #v.trip_queue .. "):", C.UI.PADDING, love.graphics.getHeight() - (C.UI.PADDING * 5))
    end

    -- Draw UI Buttons
    for _, btn in ipairs(self.ui_buttons) do
        local cost = self.costs[btn.cost_key]
        local btn_text = ""
        if btn.id == "upgrade_capacity" then
            btn_text = string.format("%s (%d->%d)", btn.text, self.upgrades.vehicle_capacity, self.upgrades.vehicle_capacity + 1)
        elseif btn.id == "upgrade_frenzy" then
            btn_text = string.format("%s (%ds->%ds)", btn.text, self.upgrades.frenzy_duration, self.upgrades.frenzy_duration + C.EVENTS.DURATION_UPGRADE_AMOUNT)
        else
            btn_text = btn.text
        end

        if self.money < cost then
            love.graphics.setColor(0.5, 0.5, 0.5)
        else
            love.graphics.setColor(1, 1, 1)
        end
        love.graphics.rectangle("line", btn.x, btn.y, btn.w, btn.h)

        if btn.id == "buy_autodisp" and self.upgrades.auto_dispatch_unlocked then
            love.graphics.printf("PURCHASED", btn.x, btn.y + 8, btn.w, "center")
        else
            local cost_text = string.format("%s ($%d)", btn_text, cost)
            love.graphics.printf(cost_text, btn.x, btn.y + 8, btn.w, "center")
        end
    end
end

function State:handle_click(x, y, game)
    local C = game.C
    -- First, check for clicks on the pending trips list
    if x > C.UI.PADDING and x < C.UI.SIDEBAR_WIDTH - C.UI.PADDING then 
        for i, trip in ipairs(self.trips.pending) do
            local y_pos = C.UI.TRIP_LIST_Y_START + (i * C.UI.TRIP_LIST_Y_STEP)
            if y > y_pos and y < y_pos + C.UI.TRIP_LIST_Y_STEP then
                if game.state.selected_vehicle and game.state.selected_vehicle:isAvailable(game) then
                    print("Assigning trip " .. i .. " to vehicle " .. game.state.selected_vehicle.id)
                    local trip_to_assign = table.remove(self.trips.pending, i)
                    game.state.selected_vehicle:assignTrip(trip_to_assign, game)
                    return true
                end
            end
        end
    end

    -- If no trip was clicked, check for clicks on the main UI buttons
    for _, btn in ipairs(self.ui_buttons) do
        if x > btn.x and x < btn.x + btn.w and y > btn.y and y < btn.y + btn.h then
            local cost = self.costs[btn.cost_key]
            if self.money >= cost then
                if btn.id == "buy_bike" then
                    self.money = self.money - cost
                    self.costs.bike = self.costs.bike * C.COSTS.BIKE_MULT
                    game.entities:addVehicle(game)
                elseif btn.id == "upgrade_speed" then
                    self.money = self.money - cost
                    self.costs.speed = self.costs.speed * C.COSTS.SPEED_MULT
                    self.upgrades.bike_speed = self.upgrades.bike_speed * C.COSTS.SPEED_UPGRADE_MULT
                elseif btn.id == "upgrade_capacity" then
                    self.money = self.money - cost
                    self.costs.capacity = math.floor(self.costs.capacity * C.COSTS.CAPACITY_MULT)
                    self.upgrades.vehicle_capacity = self.upgrades.vehicle_capacity + 1
                    print("Vehicle capacity upgraded to " .. self.upgrades.vehicle_capacity)
                elseif btn.id == "upgrade_frenzy" then
                    self.money = self.money - cost
                    self.costs.frenzy_duration = math.floor(self.costs.frenzy_duration * C.COSTS.FRENZY_DURATION_MULT)
                    self.upgrades.frenzy_duration = self.upgrades.frenzy_duration + C.EVENTS.DURATION_UPGRADE_AMOUNT
                    print("Frenzy duration upgraded to " .. self.upgrades.frenzy_duration .. "s")
                elseif btn.id == "buy_client" then
                    self.money = self.money - cost
                    self.costs.client = self.costs.client * C.COSTS.CLIENT_MULT
                    game.entities:addClient(game)
                elseif btn.id == "buy_autodisp" and not self.upgrades.auto_dispatch_unlocked then
                    self.money = self.money - cost
                    self.upgrades.auto_dispatch_unlocked = true
                    print("Auto-Dispatcher purchased and enabled!")
                end
            end
            return true
        end
    end
    return false
end


return State