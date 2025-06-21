-- models/vehicles/Bike.lua
local Vehicle = require("models.vehicles.Vehicle") -- Require the base vehicle

local Bike = {}
Bike.__index = Bike
setmetatable(Bike, {__index = Vehicle}) -- Inherit from Vehicle

Bike.PROPERTIES = {
    cost = 150,
    cost_multiplier = 1.15,
    speed = 80,
    pathfinding_costs = {
        road = 5,
        downtown_road = 8,
        arterial = 3,
        highway = 500,
        highway_ring = 500,
        highway_ns = 500,
        highway_ew = 500,
    }
}

function Bike:new(id, depot_plot, game)
    -- Create a basic vehicle instance using the parent's "new" function
    local instance = Vehicle:new(id, depot_plot, game, "bike", Bike.PROPERTIES)
    -- Set the metatable of the new instance to our Bike object to complete the inheritance
    setmetatable(instance, Bike)
    return instance
end

-- The draw method has been removed from this file.
-- The correct draw method will be inherited from Vehicle.lua.

return Bike