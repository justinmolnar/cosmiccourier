-- game/truck.lua
local Vehicle = require("game.vehicle") -- Require the base vehicle

local Truck = {}
Truck.__index = Truck
setmetatable(Truck, {__index = Vehicle}) -- Inherit from Vehicle

function Truck:new(id, depot_plot, game)
    -- Create a basic vehicle instance using the parent's "new" function
    local instance = Vehicle:new(id, depot_plot, game, "truck")
    -- Set the metatable of the new instance to our Truck object
    setmetatable(instance, Truck)
    return instance
end

-- Override the draw method for trucks
function Truck:draw(game)
    -- Call the parent's draw function first. It handles visibility,
    -- selection circles, and debug info.
    Vehicle.draw(self, game)

    local current_scale = game.map:getCurrentScale()
    if self.type == "truck" and (current_scale == game.C.MAP.SCALES.DOWNTOWN or current_scale == game.C.MAP.SCALES.CITY) then
        love.graphics.setFont(game.fonts.emoji)
        love.graphics.setColor(0, 0, 0) -- Black
        
        -- Draw a bigger emoji for the city view
        local size = (current_scale == game.C.MAP.SCALES.CITY) and 2 or 1
        love.graphics.push()
        love.graphics.translate(self.px, self.py)
        love.graphics.scale(size, size)
        love.graphics.print("🚚", -14, -14) -- Center the emoji
        love.graphics.pop()
        
        love.graphics.setFont(game.fonts.ui) -- Switch back to default UI font
    end
end

return Truck