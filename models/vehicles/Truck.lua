-- models/vehicles/Truck.lua
local Vehicle = require("models.vehicles.Vehicle") -- Require the base vehicle

local Truck = {}
Truck.__index = Truck
setmetatable(Truck, {__index = Vehicle}) -- Inherit from Vehicle

Truck.PROPERTIES = {
    cost = 1200,
    cost_multiplier = 1,
    speed = 10000,
    pathfinding_costs = {
        road = 10,
        downtown_road = 20,
        arterial = 5,
        highway = 1,
        highway_ring = 1,
        highway_ns = 1,
        highway_ew = 1,
    }
}

function Truck:new(id, depot_plot, game)
    -- Create a basic vehicle instance using the parent's "new" function
    local instance = Vehicle:new(id, depot_plot, game, "truck", Truck.PROPERTIES)
    setmetatable(instance, Truck)

    -- A truck starts at the same depot as a bike. Its anchor should be the
    -- road tile nearest to the main depot plot.
    local depot_road_anchor = game.maps.city:findNearestRoadTile(depot_plot)
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

-- The recalculatePixelPosition and draw methods have been removed from this file.
-- The correct methods will be inherited from Vehicle.lua.

return Truck