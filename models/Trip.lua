-- game/trip.lua
local Trip = {}
Trip.__index = Trip

-- Module-level uid counter. Persisted/restored by SaveService so that new trips
-- created after a save-load never collide with already-serialized trip uids.
local _next_uid = 1

function Trip.getNextUid()      return _next_uid   end
function Trip.setNextUid(n)     _next_uid = n      end

function Trip:new(base_payout, initial_bonus)
    local instance = setmetatable({}, Trip)
    instance.uid = _next_uid
    _next_uid = _next_uid + 1

    instance.base_payout = base_payout
    instance.speed_bonus = initial_bonus
    -- `speed_bonus_initial` + `bonus_duration` power scope-aware decay: the
    -- per-second decay rate = initial / duration, so the bonus reaches zero
    -- at the end of the scope-scaled window. TripGenerator populates both at
    -- creation; pre-change saves without them fall back to the legacy 1/sec
    -- rate (see :thaw / :getCurrentBonus).
    instance.speed_bonus_initial = initial_bonus
    instance.bonus_duration      = nil

    instance.legs = {}
    instance.current_leg = 1

    instance.scope         = nil   -- "district"|"city"|"region"|"continent"|"world"|nil
    instance.wait_time     = 0    -- seconds this trip has spent in the pending queue
    instance.is_in_transit = false
    instance.transit_start_time = 0
    instance.last_update_time = love.timer.getTime()

    -- Rush / deadline state. Populated by TripGenerator when an archetype rolls
    -- Rush; checked by EntityManager's per-frame expiry pass. `deadline` is an
    -- absolute wall-clock time from love.timer.getTime(); SaveService stores it
    -- as remaining-seconds and rebases on load.
    instance.is_rush          = false
    instance.deadline         = nil
    instance.payout_forfeited = false   -- set on in-transit expiry; consumed at delivery
    
    instance.start_plot = nil
    instance.end_plot = nil

    instance.route_plan = nil  -- RoutePlan computed by RoutePlannerService; populated lazily

    return instance
end

function Trip:freeze()
    self.is_in_transit = true
    self.transit_start_time = love.timer.getTime()
end

-- Per-trip decay rate (bonus lost per second of wait/transit). When
-- `bonus_duration` and `speed_bonus_initial` are present the bonus reaches
-- exactly zero after `bonus_duration` seconds regardless of the initial
-- magnitude. Legacy trips without these fields fall back to 1/sec.
function Trip:getBonusDecayRate()
    local init = self.speed_bonus_initial
    local dur  = self.bonus_duration
    if init and dur and dur > 0 then
        return init / dur
    end
    return 1.0
end

function Trip:thaw()
    if self.is_in_transit then
        local time_in_transit = love.timer.getTime() - self.transit_start_time
        self.speed_bonus = math.max(0, self.speed_bonus - time_in_transit * self:getBonusDecayRate())
        self.is_in_transit = false
        self.last_update_time = love.timer.getTime()
    end
end

function Trip:getCurrentBonus()
    if self.is_in_transit then
        local time_in_transit = love.timer.getTime() - self.transit_start_time
        return math.max(0, self.speed_bonus - time_in_transit * self:getBonusDecayRate())
    else
        return self.speed_bonus
    end
end

function Trip:addLeg(start_plot, end_plot, cargo_size, transport_mode)
    table.insert(self.legs, {
        start_plot     = start_plot,
        end_plot       = end_plot,
        cargo_size     = cargo_size     or 1,
        transport_mode = transport_mode or "road",
    })
end

-- Atomic "how much cargo is this trip" — sum across legs, for UI display.
-- Player-facing code treats a trip as one scalar; legs are dispatch-internal.
function Trip:getCargoSize()
    local total = 0
    for _, leg in ipairs(self.legs) do total = total + (leg.cargo_size or 0) end
    return total
end

-- Final dropoff plot for the trip, regardless of intermediate legs. UI code
-- must never reach into legs[] — call this instead.
function Trip:getFinalDestination()
    if self.final_destination then return self.final_destination end
    if self.end_plot then return self.end_plot end
    local last = self.legs and self.legs[#self.legs]
    return last and last.end_plot or nil
end

-- Source pickup plot — first leg's start, or the cached start_plot.
function Trip:getSourcePlot()
    if self.start_plot then return self.start_plot end
    local first = self.legs and self.legs[1]
    return first and first.start_plot or nil
end

-- ─── Serialization (data-driven) ─────────────────────────────────────────────
-- legs are pure data tables (no metatables) so they round-trip through JSON
-- naturally — no special handling needed. The few non-trivial fields
-- (absolute-time deadlines, source_client ref) get custom handling below.
Trip.TRANSIENTS = {
    transit_start_time = true, -- rewritten as transit_elapsed below
    deadline           = true, -- rewritten as deadline_remaining below
    route_plan         = true, -- regenerable cache
    last_update_time   = true, -- transient timing
    source_client      = true, -- replaced by source_client_id below
}
Trip.REFS = {}  -- legs are pure data, cargo collections are ref-fields on their owner

local AutoSerializer = require("services.AutoSerializer")

function Trip:serialize()
    local out = AutoSerializer.serialize(self, Trip.TRANSIENTS, Trip.REFS)
    -- Absolute-clock fields rewritten as relative so cross-session clock
    -- resets don't instant-expire.
    if self.is_rush and self.deadline then
        out.deadline_remaining = math.max(0, self.deadline - love.timer.getTime())
    end
    if self.is_in_transit and self.transit_start_time then
        out.transit_elapsed = math.max(0, love.timer.getTime() - self.transit_start_time)
    end
    out.source_client_id = self.source_client and self.source_client.id or nil
    return out
end

function Trip.fromSerialized(data)
    local trip = Trip:new(data.base_payout or 0, data.speed_bonus or 0)
    AutoSerializer.apply(trip, data, Trip.REFS, function() return nil end)
    trip.uid = data.uid   -- overwrite the counter-allocated uid with the saved one
    -- Re-anchor relative-time fields to the current clock.
    if data.is_rush and data.deadline_remaining then
        trip.deadline = love.timer.getTime() + data.deadline_remaining
    end
    if data.is_in_transit and data.transit_elapsed then
        trip.transit_start_time = love.timer.getTime() - data.transit_elapsed
    end
    return trip
end

return Trip