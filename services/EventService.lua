-- services/EventService.lua
local MapScales = require("data.map_scales")
local TripEligibilityService = require("services.TripEligibilityService")
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
        local trip_to_assign = game.entities.trips.pending[trip_index]

        if not selected_vehicle then
            print("TRIP ASSIGNMENT FAILED: No vehicle selected. Click a vehicle first.")
            return
        end

        if not trip_to_assign then return end

        if not TripEligibilityService.canAssign(selected_vehicle, trip_to_assign, game) then
            print(string.format("TRIP ASSIGNMENT FAILED: Vehicle %d cannot take this trip.", selected_vehicle.id))
            return
        end

        -- If all checks pass, remove the trip and assign it
        trip_to_assign = table.remove(game.entities.trips.pending, trip_index)
        if trip_to_assign then
            print(string.format("Assigned trip to %s %d.", selected_vehicle.type, selected_vehicle.id))
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
                -- Purge any stale inter-city trips from the pending queue
                -- (generated before the metro license was unlocked)
                if not state.metro_license_unlocked then
                    for i = #game.entities.trips.pending, 1, -1 do
                        if game.entities.trips.pending[i].is_long_distance then
                            table.remove(game.entities.trips.pending, i)
                        end
                    end
                end
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
        local next = MapScales.getNext(game.state.current_map_scale, "out")
        if next then game.maps.city:setScale(next) end
    end)

    game.EventBus:subscribe("ui_zoom_in_clicked", function()
        local next = MapScales.getNext(game.state.current_map_scale, "in")
        if next then game.maps.city:setScale(next) end
    end)
end

return EventService