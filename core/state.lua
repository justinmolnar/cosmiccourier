-- core/state.lua
local State = {}
State.__index = State

function State:new(C, game)
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
    
    instance.floating_texts = {}

    -- REMOVED: vehicles, clients, trips, selected_vehicle

    -- === EVENT SUBSCRIPTIONS ===
    
    game.EventBus:subscribe("package_delivered", function(data)
        instance:addMoney(data.payout)
        local bonus_text = string.format("$%.f", data.bonus)
        local payout_text = string.format("$%.f\n+ %s\nSpeed Bonus!", data.base, bonus_text)
        table.insert(instance.floating_texts, {
            text = payout_text, x = data.x, y = data.y,
            timer = C.EFFECTS.PAYOUT_TEXT_LIFESPAN_SEC, alpha = 1
        })
    end)

    game.EventBus:subscribe("ui_assign_trip_clicked", function(trip_index)
        -- Get selected vehicle and trips from the ENTITIES module now
        local selected_vehicle = game.entities.selected_vehicle
        if selected_vehicle and selected_vehicle:isAvailable(game) then
            print("Assigning trip " .. trip_index .. " to vehicle " .. selected_vehicle.id)
            local trip_to_assign = table.remove(game.entities.trips.pending, trip_index)
            selected_vehicle:assignTrip(trip_to_assign, game)
        end
    end)

    game.EventBus:subscribe("ui_buy_bike_clicked", function()
        local cost = instance.costs.bike
        if instance.money >= cost then
            instance.money = instance.money - cost
            instance.costs.bike = instance.costs.bike * C.COSTS.BIKE_MULT
            game.entities:addVehicle(game)
        end
    end)

    game.EventBus:subscribe("ui_upgrade_speed_clicked", function()
        local cost = instance.costs.speed
        if instance.money >= cost then
            instance.money = instance.money - cost
            instance.costs.speed = instance.costs.speed * C.COSTS.SPEED_MULT
            instance.upgrades.bike_speed = instance.upgrades.bike_speed * C.COSTS.SPEED_UPGRADE_MULT
        end
    end)

    game.EventBus:subscribe("ui_upgrade_capacity_clicked", function()
        local cost = instance.costs.capacity
        if instance.money >= cost then
            instance.money = instance.money - cost
            instance.costs.capacity = math.floor(instance.costs.capacity * C.COSTS.CAPACITY_MULT)
            instance.upgrades.vehicle_capacity = instance.upgrades.vehicle_capacity + 1
            print("Vehicle capacity upgraded to " .. instance.upgrades.vehicle_capacity)
        end
    end)

    game.EventBus:subscribe("ui_upgrade_frenzy_clicked", function()
        local cost = instance.costs.frenzy_duration
        if instance.money >= cost then
            instance.costs.frenzy_duration = math.floor(instance.costs.frenzy_duration * C.COSTS.FRENZY_DURATION_MULT)
            instance.upgrades.frenzy_duration = instance.upgrades.frenzy_duration + C.EVENTS.DURATION_UPGRADE_AMOUNT
            print("Frenzy duration upgraded to " .. instance.upgrades.frenzy_duration .. "s")
        end
    end)

    game.EventBus:subscribe("ui_buy_client_clicked", function()
        local cost = instance.costs.client
        if instance.money >= cost then
            instance.money = instance.money - cost
            instance.costs.client = instance.costs.client * C.COSTS.CLIENT_MULT
            game.entities:addClient(game)
        end
    end)

    game.EventBus:subscribe("ui_buy_autodisp_clicked", function()
        local cost = instance.costs.auto_dispatch
        if instance.money >= cost and not instance.upgrades.auto_dispatch_unlocked then
            instance.money = instance.money - cost
            instance.upgrades.auto_dispatch_unlocked = true
            print("Auto-Dispatcher purchased and enabled!")
        end
    end)

    return instance
end

function State:addMoney(amount)
    self.money = self.money + amount
end

function State:update(dt, game)
    local C = game.C
    
    -- Count down the Rush Hour timer if it's active
    if self.rush_hour.active then
        self.rush_hour.timer = self.rush_hour.timer - dt
        if self.rush_hour.timer <= 0 then
            self.rush_hour.active = false
            print("Rush hour over.")
        end
    end

    -- REMOVED: The logic for updating trip speed bonuses has been moved to Entities:update

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
end

return State