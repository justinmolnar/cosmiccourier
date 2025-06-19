-- core/state.lua
local State = {}
State.__index = State

function State:new(C, game)
    local instance = setmetatable({}, State)

    -- MODIFIED: We now store the entire upgrades table, which includes the new structure
    -- and the flat map for easy lookups.
    instance.Upgrades = require("game.upgrades")
    
    instance.money = C.GAMEPLAY.INITIAL_MONEY
    instance.trips_completed = 0
    instance.income_history = {}
    instance.trip_creation_history = {}
    
    instance.costs = {
        bike = C.COSTS.BIKE,
        truck = C.COSTS.TRUCK,
        client = C.COSTS.CLIENT,
    }

    instance.upgrades_purchased = {}
    instance.upgrades_discovered = {}
    
    instance.upgrades = {
        bike_speed = C.GAMEPLAY.INITIAL_BIKE_SPEED,
        truck_speed = C.GAMEPLAY.INITIAL_TRUCK_SPEED,
        auto_dispatch_unlocked = false,
        vehicle_capacity = 1,
        frenzy_duration = C.EVENTS.INITIAL_DURATION_SEC,
        trip_gen_min_mult = 1.0,
        trip_gen_max_mult = 1.0,
        multi_trip_chance = 0,
        multi_trip_amount = 2,
        max_pending_trips = C.GAMEPLAY.MAX_PENDING_TRIPS,
    }
    
    instance.rush_hour = { active = false, timer = 0 }
    instance.floating_texts = {}
    instance.current_map_scale = C.GAMEPLAY.CURRENT_MAP_SCALE
    instance.metro_license_unlocked = false

    -- EVENT LISTENERS
    game.EventBus:subscribe("package_delivered", function(data)
        instance:addMoney(data.payout)
        instance.trips_completed = instance.trips_completed + 1
        table.insert(instance.income_history, { amount = data.payout, time = love.timer.getTime() })

        local bonus_text = string.format("$%.f", data.bonus)
        local transit_text = data.transit_time and string.format(" (%.1fs)", data.transit_time) or ""
        local payout_text = string.format("$%.f\n+ %s\nSpeed Bonus!%s", data.base, bonus_text, transit_text)
        table.insert(instance.floating_texts, { text = payout_text, x = data.x, y = data.y, timer = C.EFFECTS.PAYOUT_TEXT_LIFESPAN_SEC, alpha = 1 })
    end)
    
    game.EventBus:subscribe("trip_created", function()
        table.insert(instance.trip_creation_history, love.timer.getTime())
    end)

    game.EventBus:subscribe("ui_assign_trip_clicked", function(trip_index)
        local selected_vehicle = game.entities.selected_vehicle
        if selected_vehicle and selected_vehicle:isAvailable(game) then
            local trip_to_assign = table.remove(game.entities.trips.pending, trip_index)
            selected_vehicle:assignTrip(trip_to_assign, game)
        end
    end)

    game.EventBus:subscribe("ui_purchase_upgrade_clicked", function(upgradeId)
        -- MODIFIED: The lookup now uses the .AllUpgrades map inside our new table.
        local upgrade = instance.Upgrades.AllUpgrades[upgradeId]
        if not upgrade then return end
        local current_level = instance.upgrades_purchased[upgradeId] or 0
        if current_level >= upgrade.max_level then return end
        local cost = upgrade.cost * (upgrade.cost_multiplier ^ current_level)
        if instance.money >= cost then
            instance.money = instance.money - cost
            upgrade.effect(instance, C)
            instance.upgrades_purchased[upgradeId] = current_level + 1
        end
    end)

    game.EventBus:subscribe("ui_buy_vehicle_clicked", function(vehicleType)
        if not vehicleType then return end

        local cost = instance.costs[vehicleType]
        if not cost then return end

        if instance.money >= cost then
            instance.money = instance.money - cost
            if vehicleType == "bike" then
                instance.costs.bike = math.floor(instance.costs.bike * C.COSTS.BIKE_MULT)
            elseif vehicleType == "truck" then
                instance.costs.truck = math.floor(instance.costs.truck * C.COSTS.TRUCK_MULT)
            end
            game.entities:addVehicle(game, vehicleType)
        end
    end)

    game.EventBus:subscribe("ui_buy_client_clicked", function()
        local cost = instance.costs.client
        if instance.money >= cost then
            instance.money = instance.money - cost
            instance.costs.client = math.floor(instance.costs.client * C.COSTS.CLIENT_MULT)
            game.entities:addClient(game)
        end
    end)

    game.EventBus:subscribe("ui_purchase_metro_license_clicked", function()
        local cost = C.ZOOM.METRO_LICENSE_COST
        if instance.money >= cost and not instance.metro_license_unlocked then
            instance.money = instance.money - cost
            instance.metro_license_unlocked = true
            print("Metropolitan Expansion License purchased! City-scale operations unlocked.")
        end
    end)

    game.EventBus:subscribe("ui_zoom_out_clicked", function()
        if instance.metro_license_unlocked and game.map:getCurrentScale() == C.MAP.SCALES.DOWNTOWN then
            game.map:setScale(C.MAP.SCALES.CITY)
            print("Zoomed out to city view")
        end
    end)

    game.EventBus:subscribe("ui_zoom_in_clicked", function()
        if game.map:getCurrentScale() == C.MAP.SCALES.CITY then
            game.map:setScale(C.MAP.SCALES.DOWNTOWN)
            print("Zoomed in to downtown view")
        end
    end)

    return instance
end

function State:addMoney(amount)
    self.money = self.money + amount
end

function State:update(dt, game)
    local C = game.C
    
    if self.rush_hour.active then
        self.rush_hour.timer = self.rush_hour.timer - dt
        if self.rush_hour.timer <= 0 then
            self.rush_hour.active = false
            print("Rush hour over.")
        end
    end

    for i = #self.floating_texts, 1, -1 do
        local text = self.floating_texts[i]
        text.y = text.y + C.EFFECTS.PAYOUT_TEXT_FLOAT_SPEED * dt
        text.timer = text.timer - dt
        text.alpha = text.timer / C.EFFECTS.PAYOUT_TEXT_LIFESPAN_SEC
        
        if text.timer <= 0 then
            table.remove(self.floating_texts, i)
        end
    end
end

function State:isUpgradeAvailable(upgradeId)
    local upgrade = self.Upgrades.AllUpgrades[upgradeId]
    if not upgrade then return false end

    -- Check if all prerequisite upgrades have been purchased to at least level 1
    for _, prereqId in ipairs(upgrade.prerequisites) do
        if (self.upgrades_purchased[prereqId] or 0) < 1 then
            return false -- A prerequisite is not met
        end
    end
    
    return true -- All prerequisites are met
end

return State