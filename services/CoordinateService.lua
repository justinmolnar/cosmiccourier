-- services/CoordinateService.lua
-- Single authority for coordinate conversions.
-- Phase 4.1 will fill out the full interface (gridToPixel, pixelToGrid,
-- roadNodeToPixel, screenToWorld, worldToScreen, etc.).

local CoordinateService = {}

-- Returns the bounding box of the downtown region within a grid of size grid_w × grid_h.
-- Result: { x1, y1, x2, y2 } (1-indexed, inclusive).
function CoordinateService.getDowntownBounds(grid_w, grid_h, constants)
    local dw = constants.MAP.DOWNTOWN_GRID_WIDTH
    local dh = constants.MAP.DOWNTOWN_GRID_HEIGHT
    local x1 = math.floor((grid_w - dw) / 2) + 1
    local y1 = math.floor((grid_h - dh) / 2) + 1
    return { x1 = x1, y1 = y1, x2 = x1 + dw - 1, y2 = y1 + dh - 1 }
end

return CoordinateService
