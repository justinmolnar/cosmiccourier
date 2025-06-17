-- core/time.lua
local Time = {}
Time.__index = Time

function Time:new()
    return setmetatable({}, Time)
end

function Time:update(dt)
end

return Time