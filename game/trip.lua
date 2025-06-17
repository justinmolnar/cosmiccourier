-- game/trip.lua
local Trip = {}
Trip.__index = Trip

function Trip:new(base_payout, initial_bonus)
    local instance = setmetatable({}, Trip)
    instance.base_payout = base_payout
    instance.speed_bonus = initial_bonus
    
    -- A trip is now composed of a series of delivery "legs"
    instance.legs = {}
    instance.current_leg = 1
    
    -- DEPRECATED: These will be stored in the leg object instead.
    instance.start_plot = nil
    instance.end_plot = nil

    return instance
end

return Trip