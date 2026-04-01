-- services/CoordinateService.lua
-- Single authority for coordinate conversions.
-- Phase 4.1: full interface implemented, CoordinateSystem.lua deleted.

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

-- Tile center in pixel space. tps = tile pixel size.
function CoordinateService.gridToPixel(gx, gy, tps)
    return (gx - 0.5) * tps, (gy - 0.5) * tps
end

-- Pixel position to nearest tile coordinate.
function CoordinateService.pixelToGrid(px, py, tps)
    return math.floor(px / tps + 0.5), math.floor(py / tps + 0.5)
end

-- Road-node coordinate to pixel. is_tile nodes (arterial centers) are offset
-- by half a cell; corner nodes are exact road-line intersections.
function CoordinateService.roadNodeToPixel(rx, ry, tps, is_tile)
    if is_tile then
        return (rx + 0.5) * tps, (ry + 0.5) * tps
    end
    return rx * tps, ry * tps
end

-- Vehicle draw position when viewed on the region map.
-- city_origin: { x, y } region-grid cell where the city's top-left sits (1-indexed).
function CoordinateService.applyRegionOffset(px, py, city_origin, tile_size)
    local off_x = (city_origin.x - 1) * tile_size
    local off_y = (city_origin.y - 1) * tile_size
    return off_x + px, off_y + py
end

-- Screen coordinate → world coordinate given camera state and constants.
function CoordinateService.screenToWorld(sx, sy, C, camera)
    local game_world_w = love.graphics.getWidth() - C.UI.SIDEBAR_WIDTH
    local game_world_h = love.graphics.getHeight()
    local wx = (sx - (C.UI.SIDEBAR_WIDTH + game_world_w / 2)) / camera.scale + camera.x
    local wy = (sy - game_world_h / 2) / camera.scale + camera.y
    return wx, wy
end

-- World coordinate → screen coordinate given camera state and constants.
function CoordinateService.worldToScreen(wx, wy, C, camera)
    local game_world_w = love.graphics.getWidth() - C.UI.SIDEBAR_WIDTH
    local game_world_h = love.graphics.getHeight()
    local sx = (wx - camera.x) * camera.scale + (C.UI.SIDEBAR_WIDTH + game_world_w / 2)
    local sy = (wy - camera.y) * camera.scale + game_world_h / 2
    return sx, sy
end

return CoordinateService
