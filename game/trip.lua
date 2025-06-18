-- game/trip.lua
local Trip = {}
Trip.__index = Trip

function Trip:new(base_payout, initial_bonus)
    local instance = setmetatable({}, Trip)
    instance.base_payout = base_payout
    instance.speed_bonus = initial_bonus
    
    instance.legs = {}
    instance.current_leg = 1
    
    -- NEW: Time-delta tracking properties
    instance.is_in_transit = false
    instance.transit_start_time = 0
    instance.last_update_time = love.timer.getTime()
    
    -- DEPRECATED: These will be stored in the leg object instead.
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

function Trip:addLeg(start_plot, end_plot, vehicle_type)
    table.insert(self.legs, {
        start_plot = start_plot,
        end_plot = end_plot,
        vehicleType = vehicle_type
    })
end

return Trip