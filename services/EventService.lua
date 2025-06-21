-- services/EventService.lua
local EventService = {}

function EventService.setupGameEvents(state, game)
    EventService.setupDeliveryEvents(state, game)
    EventService.setupTripEvents(state, game)
    EventService.setupUIEvents(state, game)
    EventService.setupUpgradeEvents(state, game)
    EventService.setupVehicleEvents(state, game)
    EventService.setupZoomEvents(state, game)
end

function EventService.setupDeliveryEvents(state, game)
    game.EventBus:subscribe("package_delivered", function(data)
        state:addMoney(data.payout)
        state.trips_completed = state.trips_completed + 1
        table.insert(state.income_history, { amount = data.payout, time = love.timer.getTime() })

        local bonus_text = string.format("$%.f", data.bonus)
        local transit_text = data.transit_time and string.format(" (%.1fs)", data.transit_time) or ""
        local payout_text = string.format("$%.f\n+ %s\nSpeed Bonus!%s", data.base, bonus_text, transit_text)
        table.insert(state.floating_texts, { 
            text = payout_text, 
            x = data.x, 
            y = data.y, 
            timer = game.C.EFFECTS.PAYOUT_TEXT_LIFESPAN_SEC, 
            alpha = 1 
        })
    end)
end

function EventService.setupTripEvents(state, game)
    game.EventBus:subscribe("trip_created", function()
        table.insert(state.trip_creation_history, love.timer.getTime())
    end)

    game.EventBus:subscribe("ui_assign_trip_clicked", function(trip_index)
        local selected_vehicle = game.entities.selected_vehicle
        if selected_vehicle and selected_vehicle:isAvailable(game) then
            local trip_to_assign = table.remove(game.entities.trips.pending, trip_index)
            selected_vehicle:assignTrip(trip_to_assign, game)
        end
    end)
end

function EventService.setupUIEvents(state, game)
    game.EventBus:subscribe("ui_buy_client_clicked", function()
        local cost = state.costs.client
        if state.money >= cost then
            state.money = state.money - cost
            state.costs.client = math.floor(state.costs.client * game.C.COSTS.CLIENT_MULT)
            game.entities:addClient(game)
        end
    end)
end

function EventService.setupUpgradeEvents(state, game)
    game.EventBus:subscribe("ui_purchase_upgrade_clicked", function(upgradeId)
        state.upgrade_system:purchaseUpgrade(upgradeId)
    end)
end

function EventService.setupVehicleEvents(state, game)
    game.EventBus:subscribe("ui_buy_vehicle_clicked", function(vehicleType)
        if not vehicleType then return end

        local cost = state.costs[vehicleType]
        if not cost then return end

        if state.money >= cost then
            state.money = state.money - cost
            if vehicleType == "bike" then
                state.costs.bike = math.floor(state.costs.bike * 1.15)
            elseif vehicleType == "truck" then
                state.costs.truck = math.floor(state.costs.truck * 1.25)
            end
            game.entities:addVehicle(game, vehicleType)
        end
    end)
end

function EventService.setupZoomEvents(state, game)
    game.EventBus:subscribe("ui_purchase_metro_license_clicked", function()
        local cost = game.C.ZOOM.METRO_LICENSE_COST
        if state.money >= cost and not state.metro_license_unlocked then
            state.money = state.money - cost
            state.metro_license_unlocked = true
            print("Metropolitan Expansion License purchased! City-scale operations unlocked.")
        end
    end)

    game.EventBus:subscribe("ui_zoom_out_clicked", function()
        local current_scale = game.state.current_map_scale
        local city_map = game.maps.city

        if current_scale == game.C.MAP.SCALES.DOWNTOWN then
            city_map:setScale(game.C.MAP.SCALES.CITY)
        elseif current_scale == game.C.MAP.SCALES.CITY then
            city_map:setScale(game.C.MAP.SCALES.REGION)
        end
    end)

    game.EventBus:subscribe("ui_zoom_in_clicked", function()
        local current_scale = game.state.current_map_scale
        local city_map = game.maps.city
        
        if current_scale == game.C.MAP.SCALES.REGION then
            city_map:setScale(game.C.MAP.SCALES.CITY)
        elseif current_scale == game.C.MAP.SCALES.CITY then
            city_map:setScale(game.C.MAP.SCALES.DOWNTOWN)
        end
    end)
end

return EventService