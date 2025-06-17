-- game/bike.lua
local Vehicle = require("game.vehicle") -- Require the new base vehicle

local Bike = {}
Bike.__index = Bike
setmetatable(Bike, {__index = Vehicle}) -- Inherit from Vehicle

function Bike:new(id, depot_plot, game)
    -- Create a basic vehicle instance using the parent's "new" function
    local instance = Vehicle:new(id, depot_plot, game)
    -- Set the metatable of the new instance to our Bike object to complete the inheritance
    setmetatable(instance, Bike)
    return instance
end

-- Override the draw method for bikes
function Bike:draw(game)
    -- Call the parent's draw function to draw the selection circle and debug info
    Vehicle.draw(self, game)

    -- Draw the bike-specific emoji
    love.graphics.setFont(game.fonts.emoji)
    love.graphics.setColor(0, 0, 0) -- Black
    love.graphics.print("🚲", self.px - 14, self.py - 14)
    love.graphics.setFont(game.fonts.ui) -- Switch back to default UI font
end

return Bike