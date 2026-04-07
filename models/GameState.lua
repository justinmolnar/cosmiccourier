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
    
    -- Initialize vehicle costs from definitions; non-vehicle costs are kept separately.
    instance.costs = { client = C.COSTS.CLIENT }
    for id, vcfg in pairs(C.VEHICLES) do
        instance.costs[id:lower()] = vcfg.base_cost
    end

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
    -- Named counters and flags available to dispatch rules (persistent, saved with game)
    instance.counters         = { A = 0, B = 0, C = 0, D = 0, E = 0 }
    instance.flags            = { X = false, Y = false, Z = false }
    instance.text_vars        = { A = "", B = "", C = "" }
    instance.broadcast_queue  = {}
    instance.rule_timers      = {}   -- keyed by rule.id; used by hat_every_n / hat_after_n

    -- Default fallback rule: assign any eligible vehicle to any pending trip.
    -- Sits at the bottom of the list; player rules inserted at index 1 take priority.
    instance.dispatch_rules = {
        {
            id      = "rule_default",
            enabled = true,
            stack   = {
                { kind = "hat",   def_id = "trigger_trip",      slots = {} },
                { kind = "stack", def_id = "action_assign_any", slots = {} },
            },
        },
    }

    -- Create upgrade system
    instance.upgrade_system = require("models.UpgradeSystem"):new(instance, C, game)

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

    local was_rush_hour = self.rush_hour.active

    if self.rush_hour.active then
        self.rush_hour.timer = self.rush_hour.timer - dt
        if self.rush_hour.timer <= 0 then
            self.rush_hour.active = false
            print("Rush hour over.")
        end
    end

    -- Fire rush_hour events on state transitions
    local RE = require("services.DispatchRuleEngine")
    local rules = self.dispatch_rules or {}
    if self.rush_hour.active and not was_rush_hour then
        RE.fireEvent(rules, "rush_hour_start", { game = game })
    elseif not self.rush_hour.active and was_rush_hour then
        RE.fireEvent(rules, "rush_hour_end", { game = game })
    end

    -- Decay screen shake
    local ss = game.screen_shake
    if ss and ss.timer then
        ss.timer = ss.timer - dt
        if ss.timer <= 0 then game.screen_shake = nil end
    end
end

return State