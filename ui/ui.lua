-- ui/ui.lua
local UI = {}
UI.__index = UI

function UI:new(C, game)
    local instance = setmetatable({}, UI)
    
    instance.hovered_trip_index = nil

    local p = C.UI.PADDING
    local w = C.UI.SIDEBAR_WIDTH - (p * 2)
    instance.buttons = {
        { id="buy_bike",         event="ui_buy_bike_clicked",         x=p, y=C.UI.BUTTONS_Y_START + (C.UI.BUTTONS_Y_STEP * 0), w=w, h=C.UI.BUTTON_HEIGHT, text="Buy Bike",         cost_key="bike" },
        { id="upgrade_speed",    event="ui_upgrade_speed_clicked",    x=p, y=C.UI.BUTTONS_Y_START + (C.UI.BUTTONS_Y_STEP * 1), w=w, h=C.UI.BUTTON_HEIGHT, text="Upgrade Speed",    cost_key="speed" },
        { id="upgrade_capacity", event="ui_upgrade_capacity_clicked", x=p, y=C.UI.BUTTONS_Y_START + (C.UI.BUTTONS_Y_STEP * 2), w=w, h=C.UI.BUTTON_HEIGHT, text="Upgrade Capacity",   cost_key="capacity" },
        { id="upgrade_frenzy",   event="ui_upgrade_frenzy_clicked",   x=p, y=C.UI.BUTTONS_Y_START + (C.UI.BUTTONS_Y_STEP * 3), w=w, h=C.UI.BUTTON_HEIGHT, text="Upgrade Frenzy Time",cost_key="frenzy_duration" },
        { id="buy_client",       event="ui_buy_client_clicked",       x=p, y=C.UI.BUTTONS_Y_START + (C.UI.BUTTONS_Y_STEP * 5), w=w, h=C.UI.BUTTON_HEIGHT, text="New Client",       cost_key="client" },
        { id="buy_autodisp",     event="ui_buy_autodisp_clicked",     x=p, y=C.UI.BUTTONS_Y_START + (C.UI.BUTTONS_Y_STEP * 6), w=w, h=C.UI.BUTTON_HEIGHT, text="Auto-Dispatcher",  cost_key="auto_dispatch" },
    }

    return instance
end

function UI:update(dt, game)
    local C = game.C
    local mx, my = love.mouse.getPosition()
    self.hovered_trip_index = nil -- Reset each frame

    -- This check is now self-contained in the UI module
    if mx < C.UI.SIDEBAR_WIDTH then
        -- FIX: Get trips from the correct module (entities, not state)
        for i, trip in ipairs(game.entities.trips.pending) do
            local y_pos = C.UI.TRIP_LIST_Y_START + (i * C.UI.TRIP_LIST_Y_STEP)
            if my > y_pos and my < y_pos + C.UI.TRIP_LIST_Y_STEP and mx > C.UI.PADDING and mx < C.UI.SIDEBAR_WIDTH - C.UI.PADDING then
                self.hovered_trip_index = i
                break
            end
        end
    end
end

function UI:draw(game)
    local C = game.C
    local state = game.state
    local entities = game.entities -- A shortcut to the entities module
    love.graphics.setFont(game.fonts.ui)
    love.graphics.setColor(1, 1, 1)

    -- Draw main stats at the top of the sidebar
    love.graphics.print("Money: $" .. math.floor(state.money), C.UI.PADDING, C.UI.STATS_Y_START + (C.UI.STATS_Y_STEP * 0))
    love.graphics.print("Bikes: " .. #entities.vehicles, C.UI.PADDING, C.UI.STATS_Y_START + (C.UI.STATS_Y_STEP * 1))
    love.graphics.print("Clients: " .. #entities.clients, C.UI.PADDING, C.UI.STATS_Y_START + (C.UI.STATS_Y_STEP * 2))
    
    if state.rush_hour.active then
        love.graphics.setColor(1,1,0)
        local timer_text = string.format("RUSH HOUR: %ds", math.ceil(state.rush_hour.timer))
        love.graphics.printf(timer_text, 0, C.UI.STATS_Y_START + (C.UI.STATS_Y_STEP * 3.5), C.UI.SIDEBAR_WIDTH, "center")
        love.graphics.setColor(1,1,1)
    end

    love.graphics.line(C.UI.PADDING, C.UI.DIVIDER_Y, C.UI.SIDEBAR_WIDTH - C.UI.PADDING, C.UI.DIVIDER_Y)

    -- Draw Pending Trips UI
    love.graphics.print("Pending Trips:", C.UI.PADDING, C.UI.TRIP_LIST_Y_START)
    for i, trip in ipairs(entities.trips.pending) do
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
    if entities.selected_vehicle then
        local v = entities.selected_vehicle
        local status_name = v.state and v.state.name or "Unknown"
        local capacity_text = string.format("Bike %d | Status: %s | Capacity: %d/%d", v.id, status_name, #v.cargo + #v.trip_queue, state.upgrades.vehicle_capacity)
        love.graphics.print(capacity_text, C.UI.PADDING, love.graphics.getHeight() - (C.UI.PADDING * 8))
        love.graphics.print("Cargo (" .. #v.cargo .. "):", C.UI.PADDING, love.graphics.getHeight() - (C.UI.PADDING * 7))
        love.graphics.print("Queue (" .. #v.trip_queue .. "):", C.UI.PADDING, love.graphics.getHeight() - (C.UI.PADDING * 5))
    end

    -- Draw UI Buttons
    for _, btn in ipairs(self.buttons) do
        local cost = state.costs[btn.cost_key]
        local btn_text = ""
        if btn.id == "upgrade_capacity" then
            btn_text = string.format("%s (%d->%d)", btn.text, state.upgrades.vehicle_capacity, state.upgrades.vehicle_capacity + 1)
        elseif btn.id == "upgrade_frenzy" then
            btn_text = string.format("%s (%ds->%ds)", btn.text, state.upgrades.frenzy_duration, state.upgrades.frenzy_duration + C.EVENTS.DURATION_UPGRADE_AMOUNT)
        else
            btn_text = btn.text
        end

        if state.money < cost then
            love.graphics.setColor(0.5, 0.5, 0.5)
        else
            love.graphics.setColor(1, 1, 1)
        end
        love.graphics.rectangle("line", btn.x, btn.y, btn.w, btn.h)

        if btn.id == "buy_autodisp" and state.upgrades.auto_dispatch_unlocked then
            love.graphics.printf("PURCHASED", btn.x, btn.y + 8, btn.w, "center")
        else
            local cost_text = string.format("%s ($%d)", btn_text, cost)
            love.graphics.printf(cost_text, btn.x, btn.y + 8, btn.w, "center")
        end
    end
end

function UI:handle_click(x, y, game)
    local C = game.C
    local entities = game.entities -- Get entities module

    -- First, check for clicks on the pending trips list
    if x > C.UI.PADDING and x < C.UI.SIDEBAR_WIDTH - C.UI.PADDING then 
        -- Reference the trips list from the entities module
        for i, trip in ipairs(entities.trips.pending) do
            local y_pos = C.UI.TRIP_LIST_Y_START + (i * C.UI.TRIP_LIST_Y_STEP)
            if y > y_pos and y < y_pos + C.UI.TRIP_LIST_Y_STEP then
                -- Publish an event with the necessary data
                game.EventBus:publish("ui_assign_trip_clicked", i)
                return true
            end
        end
    end

    -- If no trip was clicked, check for clicks on the main UI buttons
    for _, btn in ipairs(self.buttons) do
        if x > btn.x and x < btn.x + btn.w and y > btn.y and y < btn.y + btn.h then
            -- Publish the generic event for the clicked button
            game.EventBus:publish(btn.event)
            return true
        end
    end

    return false
end

return UI