-- data/road_categories.lua
-- Maps tile type string → pathfinding cost category string.
-- PathfindingService uses this instead of inline type checks.
-- Valid categories match the keys in each vehicle's pathfinding_costs table
-- in data/constants.lua VEHICLES: "road", "arterial", "highway".

local json = require("lib.json")

local raw           = love.filesystem.read("data/road_categories.json")
local RoadCategories = json.decode(raw)

return RoadCategories
