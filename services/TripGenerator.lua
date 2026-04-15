-- services/TripGenerator.lua
-- Trip generation driven by client archetypes. Each generated trip's cargo
-- size, destination scope, and payout come from the archetype config
-- (data/client_archetypes.lua). Scope-gating: if the rolled scope exceeds
-- the player's current license tier, the trip is eaten silently (return nil)
-- and the client's timer resets on the next update cycle.

local Trip               = require("models.Trip")
local GameplayConfig     = require("data.GameplayConfig")
local Archetypes         = require("data.client_archetypes")
local LicenseService     = require("services.LicenseService")
local DebugTripFactory   = require("services.DebugTripFactory")

local TripGenerator = {}

-- Scope id → license tier. MVP scopes are district / city / region; continent
-- and world remain valid destination ids but are unreachable without licenses
-- the MVP does not grant, so any such roll is eaten silently.
local SCOPE_TIER = { district = 1, city = 2, region = 3, continent = 4, world = 5 }

local function resolveArchetype(archetype_id)
    local a = Archetypes.by_id[archetype_id or Archetypes.default_id]
    return a or Archetypes.by_id[Archetypes.default_id]
end

-- Weighted pick across archetype.dest_scope_weights. Returns a scope id.
local function rollScope(weights)
    local total = 0
    for _, w in pairs(weights) do total = total + (w or 0) end
    if total <= 0 then return "district" end
    local r = love.math.random() * total
    local acc = 0
    for scope, w in pairs(weights) do
        acc = acc + (w or 0)
        if r <= acc then return scope end
    end
    return "district"
end

function TripGenerator.calculateNextTripTime(game, archetype_id)
    local archetype = resolveArchetype(archetype_id)
    local upgrades  = game.state.upgrades
    local spawn_mult = upgrades[archetype.id .. "_spawn_rate_mult"] or 1.0
    local min_time = archetype.base_spawn_seconds[1] * upgrades.trip_gen_min_mult * spawn_mult
    local max_time = archetype.base_spawn_seconds[2] * upgrades.trip_gen_max_mult * spawn_mult
    if max_time < min_time then max_time = min_time end
    return love.math.random(math.floor(min_time + 0.5), math.floor(max_time + 0.5))
end

function TripGenerator.generateTrip(client_plot, game, city_map, archetype_id)
    local C_GAMEPLAY = game.C.GAMEPLAY
    local upgrades   = game.state.upgrades

    local archetype = resolveArchetype(archetype_id)

    -- Cargo size: random within archetype range plus a per-archetype upgrade
    -- bias. Clamp floor to 1 so we never roll zero-size cargo.
    local bias = upgrades[archetype.id .. "_cargo_size_bias"] or 0
    local min_cargo = math.max(1, archetype.cargo_size_range[1] + bias)
    local max_cargo = math.max(min_cargo, archetype.cargo_size_range[2] + bias)
    local cargo_size = love.math.random(min_cargo, max_cargo)

    -- Destination scope: weighted archetype roll. Eat silently if the
    -- player's current license doesn't cover the rolled scope — the client's
    -- timer resets on its normal update cycle.
    local scope = rollScope(archetype.dest_scope_weights)
    local rolled_tier = SCOPE_TIER[scope] or 1
    if rolled_tier > LicenseService.getCurrentTier(game) then
        return nil
    end

    -- Destination plot: delegate to DebugTripFactory's scope-aware pools.
    local depot = game.entities.depots and game.entities.depots[1]
    if not depot then return nil end
    local dest_plot = DebugTripFactory.pickDestination(scope, depot, game)
    if not dest_plot then return nil end
    if dest_plot.x == client_plot.x and dest_plot.y == client_plot.y then return nil end

    -- Scope scaling reads from the canonical tables in data/constants.lua.
    local scope_payout = (C_GAMEPLAY.SCOPE_PAYOUT_MULT and C_GAMEPLAY.SCOPE_PAYOUT_MULT[scope]) or 1.0
    local scope_time   = (C_GAMEPLAY.SCOPE_TIME_MULT   and C_GAMEPLAY.SCOPE_TIME_MULT[scope])   or 1.0

    -- Payout: base × archetype multiplier × scope multiplier × cargo size
    -- × per-archetype payout upgrade (default 1.0 when unpurchased).
    -- Cargo scaling makes bigger loads pay proportionally more, so carrying
    -- a 10-cargo warehouse shipment meaningfully out-pays a 1-cargo errand.
    local payout_mult = upgrades[archetype.id .. "_payout_mult"] or 1.0
    local base_payout = math.floor(
        (C_GAMEPLAY.BASE_TRIP_PAYOUT or 0)
        * (archetype.payout_multiplier or 1.0)
        * scope_payout
        * cargo_size
        * payout_mult
    )

    -- Speed bonus is proportional to payout so it stays meaningful across
    -- scopes; its decay window scales with scope so farther trips get more
    -- travel headroom before the bonus zeroes out.
    local bonus_ratio    = C_GAMEPLAY.SPEED_BONUS_RATIO   or 0.5
    local base_duration  = C_GAMEPLAY.BASE_BONUS_DURATION or 30
    local speed_bonus    = math.floor(base_payout * bonus_ratio + 0.5)
    local bonus_duration = base_duration * scope_time

    local new_trip = Trip:new(base_payout, speed_bonus)
    new_trip.scope               = scope
    new_trip.speed_bonus_initial = speed_bonus
    new_trip.bonus_duration      = bonus_duration
    new_trip:addLeg(client_plot, dest_plot, cargo_size, "road")

    -- Rush roll. Probability is driven entirely by per-archetype rush upgrades
    -- (state.upgrades[id.."_rush_probability"], 0..1, additive). Archetypes
    -- without rush upgrades purchased never roll Rush. Deadline scales by
    -- scope so world rushes have much longer windows than district ones.
    local rush_prob = math.min(1, upgrades[archetype.id .. "_rush_probability"] or 0)
    if rush_prob > 0 and love.math.random() < rush_prob then
        local deadline_base   = archetype.rush_deadline_seconds or 60
        new_trip.is_rush      = true
        new_trip.deadline     = love.timer.getTime() + deadline_base * scope_time
        new_trip.speed_bonus  = new_trip.speed_bonus * (archetype.rush_bonus_multiplier or 1)
        new_trip.speed_bonus_initial = new_trip.speed_bonus
    end

    return new_trip
end

return TripGenerator
