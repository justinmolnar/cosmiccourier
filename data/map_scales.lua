-- data/map_scales.lua
-- Defines the zoom hierarchy and provides navigation helpers.
-- Scale values match C.MAP.SCALES; listed from outermost to innermost.

local C = require("data.constants")
local S = C.MAP.SCALES

local MapScales = {}

-- Ordered from outermost (world) to innermost (downtown).
MapScales.HIERARCHY = {
    S.WORLD, S.CONTINENT, S.REGION, S.CITY, S.DOWNTOWN
}

-- Returns the next scale when zooming in (toward downtown), or nil at the innermost.
-- Returns the next scale when zooming out (toward world), or nil at the outermost.
function MapScales.getNext(current, direction)
    local h = MapScales.HIERARCHY
    for i, v in ipairs(h) do
        if v == current then
            if direction == "in" then
                return h[i + 1]  -- closer to downtown
            else
                return h[i - 1]  -- closer to world
            end
        end
    end
    return nil
end

return MapScales
