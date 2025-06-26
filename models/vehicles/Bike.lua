-- models/vehicles/Bike.lua
local Vehicle = require("models.vehicles.Vehicle") -- Require the base vehicle

local Bike = {}
Bike.__index = Bike
setmetatable(Bike, {__index = Vehicle}) -- Inherit from Vehicle

function Bike:new(id, depot_plot, game)
    -- Create a basic vehicle instance using the parent's "new" function
    -- It now reads its properties directly from the constants file
    local instance = Vehicle:new(id, depot_plot, game, "bike", game.C.VEHICLES.BIKE)
    
    -- Set the metatable of the new instance to our Bike object to complete the inheritance
    setmetatable(instance, Bike)
    return instance
end

-- The draw method has been removed from this file.
-- The correct draw method will be inherited from Vehicle.lua.

function Bike:getIcon()
    return "🚲"
end

return Bike