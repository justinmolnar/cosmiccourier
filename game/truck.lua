-- game/truck.lua
local Vehicle = require("game.vehicle") -- Require the base vehicle

local Truck = {}
Truck.__index = Truck
setmetatable(Truck, {__index = Vehicle}) -- Inherit from Vehicle

function Truck:new(id, depot_plot, game)
    -- Create a basic vehicle instance using the parent's "new" function
    local instance = Vehicle:new(id, depot_plot, game, "truck")
    setmetatable(instance, Truck)

    -- FIX: A truck starts at the same depot as a bike. Its anchor should be the
    -- road tile nearest to the main depot plot.
    local depot_road_anchor = game.map:findNearestRoadTile(depot_plot)
    if depot_road_anchor then
        instance.grid_anchor = depot_road_anchor
    else
        -- Fallback if no road is found (should be rare)
        instance.grid_anchor = {x = depot_plot.x, y = depot_plot.y}
    end
    
    -- Recalculate its pixel position based on its new correct grid anchor.
    instance:recalculatePixelPosition(game)

    return instance
end

function Truck:recalculatePixelPosition(game)
    local current_scale = game.map:getCurrentScale()
    local truck_anchor = self.grid_anchor -- This is a city-grid coordinate

    if current_scale == game.C.MAP.SCALES.CITY then
        -- Zoomed out: Simple calculation on the city map
        self.px, self.py = game.map:getPixelCoords(truck_anchor.x, truck_anchor.y)
    else -- current_scale is DOWNTOWN
        -- Zoomed in: Calculate truck's position relative to the downtown view
        local downtown_offset = game.map.downtown_offset -- The top-left of downtown on the city map
        local DOWNTOWN_TILE_SIZE = 16
        
        -- Find the truck's position relative to the downtown area, in city-grid units
        local relative_x = truck_anchor.x - downtown_offset.x
        local relative_y = truck_anchor.y - downtown_offset.y
        
        -- Convert that relative position to pixels using the downtown tile size
        self.px = (relative_x - 0.5) * DOWNTOWN_TILE_SIZE
        self.py = (relative_y - 0.5) * DOWNTOWN_TILE_SIZE
    end
end

-- Override the draw method for trucks
function Truck:draw(game)
    Vehicle.draw(self, game)

    love.graphics.setFont(game.fonts.emoji)
    love.graphics.setColor(0, 0, 0) -- Black

    -- FIX: Apply a counter-scale to keep the icon size consistent
    love.graphics.push()
    love.graphics.translate(self.px, self.py)
    love.graphics.scale(1 / game.camera.scale, 1 / game.camera.scale)
    love.graphics.print("🚚", -14, -14) -- Center the emoji
    love.graphics.pop()

    love.graphics.setFont(game.fonts.ui) -- Switch back to default UI font
end

return Truck