-- core/state.lua
local State = {}
State.__index = State

function State:new(C, game)
    local instance = setmetatable({}, State)

    -- Load upgrade data
    instance.Upgrades = require("data.upgrades")
    
    instance.money = C.GAMEPLAY.INITIAL_MONEY
    instance.trips_completed = 0
    instance.income_history = {}
    instance.trip_creation_history = {}
    
    instance.costs = {
        bike = 150,
        truck = 1200,
        client = C.COSTS.CLIENT,
    }

    instance.upgrades_purchased = {}
    instance.upgrades_discovered = {}
    
    instance.upgrades = {
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
    instance.current_map_scale = C.GAMEPLAY.CURRENT_MAP_SCALE
    instance.metro_license_unlocked = false

    -- Create upgrade system
    instance.upgrade_system = require("models.UpgradeSystem"):new(instance, C)

    -- Delegate event setup to EventService
    local EventService = require("services.EventService")
    EventService.setupGameEvents(instance, game)

    return instance
end

function State:isUpgradeAvailable(upgradeId)
    return self.upgrade_system:isUpgradeAvailable(upgradeId)
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

end

return State