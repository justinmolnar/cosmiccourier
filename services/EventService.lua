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
    EventService.setupFuelEvents(state, game)
    EventService.setupPackEvents(state, game)
    EventService.setupLicenseEvents(state, game)
end

function EventService.setupLicenseEvents(state, game)
    -- Pure scope gate: on purchase, surface a floating-text confirmation and
    -- let the modal (if open) refresh on next frame. No bundled effects.
    game.EventBus:subscribe("license_purchased", function(data)
        local lic = data and data.license
        if not lic then return end
        local msg = string.format("License acquired!\n%s", lic.display_name)
        FloatingTextSystem.emit(msg, love.graphics.getWidth() / 2, love.graphics.getHeight() / 2, game.C)
        print(string.format("Licenses: now operating with %s (tier %d)", lic.display_name, lic.scope_tier))
    end)
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

        -- If all checks pass, remove the trip and assign it. The trip stays in
        -- source_client.cargo (the building's "inventory") until DoPickup runs.
        trip_to_assign = table.remove(game.entities.trips.pending, trip_index)
        if trip_to_assign then
            print(string.format("Assigned trip to %s %d.", selected_vehicle.type, selected_vehicle.id))
            selected_vehicle:assignTrip(trip_to_assign, game)
        end
    end)
end

function EventService.setupUIEvents(state, game)
    local Archetypes     = require("data.client_archetypes")
    local LicenseService = require("services.LicenseService")

    -- Shared helper: validate an archetype purchase and charge the market.
    -- Returns the archetype on success, or nil on rejection (logs reason).
    local function validateAndCharge(archetype_id)
        local archetype = archetype_id and Archetypes.by_id[archetype_id]
        if not archetype then
            print(string.format("Market: unknown archetype_id '%s'", tostring(archetype_id)))
            return nil
        end
        if LicenseService.getCurrentTier(game) < archetype.required_scope_tier then
            print(string.format("Market: '%s' requires license tier %d",
                archetype.id, archetype.required_scope_tier))
            return nil
        end
        local cost = archetype.market_cost or 0
        if (state.money or 0) < cost then
            print(string.format("Market: insufficient funds for '%s' ($%d)",
                archetype.id, cost))
            return nil
        end
        state.money = state.money - cost
        return archetype
    end

    game.EventBus:subscribe("ui_buy_client_clicked", function(data)
        local archetype_id = data and data.archetype_id
        local archetype    = validateAndCharge(archetype_id)
        if not archetype then return end
        game.entities:addClient(game, game.entities.depots[1], archetype.id)
    end)

    game.EventBus:subscribe("ui_market_for_clients_clicked", function(data)
        if not data or not data.depot then return end
        local archetype = validateAndCharge(data.archetype_id)
        if not archetype then return end
        game.entities:addClient(game, data.depot, archetype.id)
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
        if not state.purchasable_vehicles[vehicleType] then return end

        local vcfg = game.C.VEHICLES[vehicleType:upper()]
        if not vcfg then return end

        local cost = state.costs[vehicleType]
        if not cost or state.money < cost then return end

        state.money = state.money - cost
        state.costs[vehicleType] = math.floor(cost * vcfg.cost_multiplier)
        game.entities:addVehicle(game, vehicleType)
    end)

    game.EventBus:subscribe("ui_buy_vehicle_at_depot_clicked", function(data)
        if not data or not data.vehicle_id or not data.depot then return end
        local vehicleType = data.vehicle_id
        if not state.purchasable_vehicles[vehicleType] then return end

        local vcfg = game.C.VEHICLES[vehicleType:upper()]
        if not vcfg then return end

        -- District requirement check (e.g. bikes require a downtown depot)
        if vcfg.required_depot_district then
            local depot_district = data.depot:getDistrict(game)
            if depot_district ~= vcfg.required_depot_district then return end
        end

        local cost = state.costs[vehicleType]
        if not cost or state.money < cost then return end

        state.money = state.money - cost
        state.costs[vehicleType] = math.floor(cost * vcfg.cost_multiplier)
        game.entities:addVehicle(game, vehicleType, data.depot)
    end)
end

function EventService.setupFuelEvents(state, game)
    game.EventBus:subscribe("fuel_consumed", function(data)
        local text = string.format("-$%.f fuel", data.amount)
        FloatingTextSystem.emit(text, data.x, data.y, game.C)
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

function EventService.setupPackEvents(state, game)
    game.EventBus:subscribe("pack_opened", function(data)
        local PackModal = require("views.components.PackModal")
        local on_close  = function() game.ui_manager.modal_manager:hide() end
        local modal     = PackModal:new(data.pack, data.result, on_close)
        game.ui_manager.modal_manager:show(modal)
    end)
end

return EventService