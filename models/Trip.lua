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
    
    instance.start_plot = nil
    instance.end_plot = nil

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

return Trip