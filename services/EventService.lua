-- services/EventService.lua
local TripEligibilityService = require("services.TripEligibilityService")
local FloatingTextSystem = require("services.FloatingTextSystem")
local EventService = {}

function EventService.setupGameEvents(state, game)
    EventService.setupDeliveryEvents(state, game)
    EventService.setupTripEvents(state, game)
    EventService.setupUIEvents(state, game)
    EventService.setupUpgradeEvents(state, game)
    EventService.setupVehicleEvents(state, game)
    EventService.setupCameraEvents(state, game)
end

function EventService.setupDeliveryEvents(state, game)
    game.EventBus:subscribe("package_delivered", function(data)
        state:addMoney(data.payout)
        state.trips_completed = state.trips_completed + 1
        table.insert(state.income_history, { amount = data.payout, time = love.timer.getTime() })

        local bonus_text = string.format("$%.f", data.bonus)
        local transit_text = data.transit_time and string.format(" (%.1fs)", data.transit_time) or ""
        local payout_text = string.format("$%.f\n+ %s\nSpeed Bonus!%s", data.base, bonus_text, transit_text)
        FloatingTextSystem.emit(payout_text, data.x, data.y, game.C)
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

        local vcfg = game.C.VEHICLES[vehicleType:upper()]
        if not vcfg then return end

        local cost = state.costs[vehicleType]
        if not cost or state.money < cost then return end

        state.money = state.money - cost
        state.costs[vehicleType] = math.floor(cost * vcfg.cost_multiplier)
        game.entities:addVehicle(game, vehicleType)
    end)
end

function EventService.setupCameraEvents(state, game)
    -- Apply camera position and active map key when setScale() fires (e.g. sendToGame).
    game.EventBus:subscribe("map_scale_changed", function(data)
        if data then
            game.active_map_key = data.active_map_key
            game.camera.x       = data.camera.x
            game.camera.y       = data.camera.y
            game.camera.scale   = data.camera.scale
        end
    end)
end

return EventService