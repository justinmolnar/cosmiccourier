-- models/RoutePlan.lua
-- Pure data container for a multi-modal route.
-- A route plan is a sequence of segments. Each segment is one of:
--   local    — free pathfinding between a position and an entrance
--              (or between two positions when start/end are in the same city)
--   trunk    — a cached inter-city trunk path between two entrances of the same mode
--   transfer — an intra-city mode switch between two entrances of different modes
--
-- RoutePlanner produces these. GameView renders them. Nothing else mutates them.

local RoutePlan = {}

function RoutePlan.new(total_cost, segments)
    return {
        total_cost = total_cost,
        segments   = segments or {},
    }
end

return RoutePlan
