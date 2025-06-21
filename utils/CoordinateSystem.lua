-- utils/CoordinateSystem.lua
local CoordinateSystem = {}

function CoordinateSystem.new(constants)
    local instance = {}
    instance.C = constants
    return setmetatable(instance, {__index = CoordinateSystem})
end

-- Grid to pixel conversions
function CoordinateSystem:gridToPixel(grid_x, grid_y)
    local TILE_SIZE = self.C.MAP.TILE_SIZE
    return (grid_x - 0.5) * TILE_SIZE, (grid_y - 0.5) * TILE_SIZE
end

function CoordinateSystem:pixelToGrid(pixel_x, pixel_y)
    local TILE_SIZE = self.C.MAP.TILE_SIZE
    return math.floor(pixel_x / TILE_SIZE + 0.5), math.floor(pixel_y / TILE_SIZE + 0.5)
end

-- Screen to world conversions (for input handling)
function CoordinateSystem:screenToWorld(screen_x, screen_y, camera)
    local game_world_w = love.graphics.getWidth() - self.C.UI.SIDEBAR_WIDTH
    local game_world_h = love.graphics.getHeight()
    
    local adjusted_x = screen_x - (self.C.UI.SIDEBAR_WIDTH + game_world_w / 2)
    local adjusted_y = screen_y - (game_world_h / 2)
    local scaled_x = adjusted_x / camera.scale
    local scaled_y = adjusted_y / camera.scale
    local world_x = scaled_x + camera.x
    local world_y = scaled_y + camera.y
    
    return world_x, world_y
end

function CoordinateSystem:worldToScreen(world_x, world_y, camera)
    local game_world_w = love.graphics.getWidth() - self.C.UI.SIDEBAR_WIDTH
    local game_world_h = love.graphics.getHeight()
    
    local camera_relative_x = world_x - camera.x
    local camera_relative_y = world_y - camera.y
    local scaled_x = camera_relative_x * camera.scale
    local scaled_y = camera_relative_y * camera.scale
    local screen_x = scaled_x + (self.C.UI.SIDEBAR_WIDTH + game_world_w / 2)
    local screen_y = scaled_y + (game_world_h / 2)
    
    return screen_x, screen_y
end

-- Distance calculations
function CoordinateSystem:gridDistance(x1, y1, x2, y2)
    return math.sqrt((x2 - x1)^2 + (y2 - y1)^2)
end

function CoordinateSystem:pixelDistance(x1, y1, x2, y2)
    return math.sqrt((x2 - x1)^2 + (y2 - y1)^2)
end

function CoordinateSystem:manhattanDistance(x1, y1, x2, y2)
    return math.abs(x2 - x1) + math.abs(y2 - y1)
end

-- Bounds checking
function CoordinateSystem:isInBounds(x, y, width, height)
    return x >= 1 and x <= width and y >= 1 and y <= height
end

function CoordinateSystem:isInRect(x, y, rect_x, rect_y, rect_w, rect_h)
    return x >= rect_x and x < rect_x + rect_w and y >= rect_y and y < rect_y + rect_h
end

function CoordinateSystem:isInDowntown(plot, downtown_offset, downtown_dimensions)
    if not plot or not downtown_offset then return false end

    local x_min = downtown_offset.x
    local y_min = downtown_offset.y
    local x_max = downtown_offset.x + downtown_dimensions.w
    local y_max = downtown_offset.y + downtown_dimensions.h

    return plot.x >= x_min and plot.x < x_max and plot.y >= y_min and plot.y < y_max
end

-- Viewport calculations
function CoordinateSystem:getGameWorldDimensions()
    local screen_w, screen_h = love.graphics.getDimensions()
    local game_world_w = screen_w - self.C.UI.SIDEBAR_WIDTH
    return game_world_w, screen_h
end

function CoordinateSystem:isInSidebar(x, y)
    return x < self.C.UI.SIDEBAR_WIDTH
end

function CoordinateSystem:isInGameWorld(x, y)
    return x >= self.C.UI.SIDEBAR_WIDTH
end

-- Static utility functions (don't require instance)
function CoordinateSystem.clamp(value, min_val, max_val)
    return math.max(min_val, math.min(max_val, value))
end

function CoordinateSystem.lerp(a, b, t)
    return a + (b - a) * t
end

function CoordinateSystem.normalizeAngle(angle)
    while angle < 0 do angle = angle + math.pi * 2 end
    while angle >= math.pi * 2 do angle = angle - math.pi * 2 end
    return angle
end

return CoordinateSystem