-- game/trip.lua
local Trip = {}
Trip.__index = Trip

function Trip:new(base_payout, initial_bonus)
    local instance = setmetatable({}, Trip)
    instance.base_payout = base_payout
    instance.speed_bonus = initial_bonus
    
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

function Trip:thaw()
    if self.is_in_transit then
        local time_in_transit = love.timer.getTime() - self.transit_start_time
        self.speed_bonus = math.max(0, self.speed_bonus - time_in_transit)
        self.is_in_transit = false
        self.last_update_time = love.timer.getTime()
    end
end

function Trip:getCurrentBonus()
    if self.is_in_transit then
        local time_in_transit = love.timer.getTime() - self.transit_start_time
        return math.max(0, self.speed_bonus - time_in_transit)
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

return Trip