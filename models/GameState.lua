-- core/state.lua
local State = {}
State.__index = State

-- Data-driven save: everything on a State instance persists EXCEPT these.
-- Adding a new persistable field to GameState:new costs zero — it ships.
-- Only add to this list when introducing a computed/ref/transient field.
State.TRANSIENTS = {
    Upgrades       = true,  -- static module reference (data.upgrades)
    upgrade_system = true,  -- runtime system instance
    income_history = true,  -- rolling per-session stats (not persisted)
    trip_creation_history = true,
}
State.REFS = {}  -- no entity refs on state

function State:new(C, game)
    local instance = setmetatable({}, State)

    -- Load upgrade data
    instance.Upgrades = require("data.upgrades")
    
    instance.money = C.GAMEPLAY.INITIAL_MONEY
    instance.trips_completed = 0
    instance.income_history = {}
    instance.trip_creation_history = {}
    
    -- Initialize vehicle costs from definitions. Client market cost lives
    -- on each archetype in data/client_archetypes.lua; no global client cost.
    instance.costs = {}
    for id, vcfg in pairs(C.VEHICLES) do
        instance.costs[id:lower()] = vcfg.base_cost
    end

    instance.upgrades_purchased = {}
    instance.upgrades_discovered = {}
    
    instance.upgrades = {
        auto_dispatch_unlocked = false,
        frenzy_duration = C.EVENTS.INITIAL_DURATION_SEC,
        trip_gen_min_mult = 1.0,
        trip_gen_max_mult = 1.0,
    }

    -- Per-archetype upgrade fields. Seeded from the archetype registry so
    -- no archetype ids appear in this model — the loop is the source of truth.
    local Archetypes = require("data.client_archetypes")
    for _, a in ipairs(Archetypes.list) do
        instance.upgrades[a.id .. "_spawn_rate_mult"]   = 1.0
        instance.upgrades[a.id .. "_payout_mult"]       = 1.0
        instance.upgrades[a.id .. "_cargo_size_bias"]   = 0
        instance.upgrades[a.id .. "_rush_probability"]  = 0   -- additive, 0..1; raised by per-archetype rush upgrades
        instance.upgrades[a.id .. "_capacity_bonus"]    = 0
    end
    
    -- Per-user UI layout config (datagrid widths / hidden / sort).
    -- Keys are datagrid ids defined in data/datagrids/*.lua.
    instance.ui_config = { datagrids = {} }

    instance.rush_hour = { active = false, timer = 0 }
    instance.current_map_scale = C.GAMEPLAY.CURRENT_MAP_SCALE
    instance.metro_license_unlocked = false
    instance.licenses = { downtown_license = true }
    instance.purchasable_vehicles = { bike = true }
    -- Unified name-based variable system available to dispatch rules
    instance.vars             = {}
    instance.broadcast_queue  = {}
    instance.rule_timers      = {}   -- keyed by rule.id; used by hat_every_n / hat_after_n
    -- Rule pack unlock system: flat set of "namespace:id" keys
    instance.unlocked         = {}

    -- Dispatch rules: empty until player unlocks auto-dispatch and receives packs.
    instance.dispatch_rules = {}

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

-- Data-driven serialize / apply — same pattern as the models.
function State:serialize()
    local AutoSerializer = require("services.AutoSerializer")
    return AutoSerializer.serialize(self, State.TRANSIENTS, State.REFS)
end

function State:applySerialized(data)
    -- `upgrades` merges (so new-since-save fields keep their default zeros);
    -- everything else wholesale-replaces.
    for k, v in pairs(data or {}) do
        if v == nil then
            -- skip
        elseif State.TRANSIENTS and State.TRANSIENTS[k] then
            -- skip — not meant to be restored
        elseif k == "upgrades" and type(v) == "table" and type(self.upgrades) == "table" then
            for uk, uv in pairs(v) do self.upgrades[uk] = uv end
        else
            self[k] = v
        end
    end
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