-- game/trip.lua
local Trip = {}
Trip.__index = Trip

function Trip:new(base_payout, initial_bonus)
    local instance = setmetatable({}, Trip)
    instance.base_payout = base_payout
    instance.speed_bonus = initial_bonus
    -- We are no longer passing in start/end plots here, they will be set by the client
    instance.start_plot = nil
    instance.end_plot = nil
    return instance
end

return Trip