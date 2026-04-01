-- data/road_categories.lua
-- Maps tile type string → pathfinding cost category string.
-- PathfindingService uses this instead of inline type checks.
-- Valid categories match the keys in each vehicle's pathfinding_costs table
-- in data/constants.lua VEHICLES: "road", "arterial", "highway".

local RoadCategories = {
    road          = "road",
    downtown_road = "road",
    arterial      = "arterial",
    highway       = "highway",
}

return RoadCategories
