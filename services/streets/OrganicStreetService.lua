-- services/streets/OrganicStreetService.lua
-- Jitter-grid: a regular grid where each intersection point is randomly offset.
-- Roads connect adjacent jittered intersections via Bresenham lines.
-- Result: irregular quadrilateral blocks that feel organic without being chaotic.
local OrganicStreetService = {}

function OrganicStreetService.generateStreets(city_grid, zone_grid, arterial_paths, params)
    local C_MAP = require("data.constants").MAP
    local width  = #city_grid[1]
    local height = #city_grid

    local block_size = params.block_size or params.min_block_size or 18
    if block_size <= 0 then block_size = 18 end
    local jitter = math.floor(block_size * (params.warp_strength or 4) / 10.0)
    jitter = math.max(1, math.min(jitter, math.floor(block_size * 0.45)))

    local downtown_w = C_MAP.DOWNTOWN_GRID_WIDTH
    local downtown_h = C_MAP.DOWNTOWN_GRID_HEIGHT
    local dt_x1 = math.floor((width  - downtown_w) / 2) + 1
    local dt_y1 = math.floor((height - downtown_h) / 2) + 1
    local dt_x2 = dt_x1 + downtown_w - 1
    local dt_y2 = dt_y1 + downtown_h - 1

    local cell_mask = params.cell_mask
    local function write_road(x, y)
        x, y = math.floor(x + 0.5), math.floor(y + 0.5)
        if x < 1 or x > width or y < 1 or y > height then return end
        if cell_mask and (not cell_mask[y] or not cell_mask[y][x]) then return end
        if city_grid[y][x].type == "arterial" then return end
        local in_dt = (x >= dt_x1 and x <= dt_x2 and y >= dt_y1 and y <= dt_y2)
        city_grid[y][x] = { type = in_dt and "downtown_road" or "road" }
    end

    local function draw_line(x1, y1, x2, y2)
        x1,y1 = math.floor(x1+0.5), math.floor(y1+0.5)
        x2,y2 = math.floor(x2+0.5), math.floor(y2+0.5)
        local dx, dy = math.abs(x2-x1), math.abs(y2-y1)
        local sx = x1 < x2 and 1 or -1
        local sy = y1 < y2 and 1 or -1
        local err = dx - dy
        local cx, cy = x1, y1
        while true do
            write_road(cx, cy)
            if cx == x2 and cy == y2 then break end
            local e2 = 2 * err
            if e2 > -dy then err = err - dy; cx = cx + sx end
            if e2 <  dx then err = err + dx; cy = cy + sy end
        end
    end

    -- Build grid of jittered control points
    local cols = math.floor(width  / block_size) + 2
    local rows = math.floor(height / block_size) + 2

    local pts = {}
    for row = 0, rows do
        pts[row] = {}
        for col = 0, cols do
            local base_x = col * block_size
            local base_y = row * block_size
            local ox = love.math.random(-jitter, jitter)
            local oy = love.math.random(-jitter, jitter)
            pts[row][col] = {
                x = math.max(1, math.min(width,  base_x + ox)),
                y = math.max(1, math.min(height, base_y + oy)),
            }
        end
    end

    -- Horizontal roads: connect across each row
    for row = 0, rows do
        for col = 0, cols - 1 do
            local a, b = pts[row][col], pts[row][col + 1]
            draw_line(a.x, a.y, b.x, b.y)
        end
    end

    -- Vertical roads: connect down each column
    for col = 0, cols do
        for row = 0, rows - 1 do
            local a, b = pts[row][col], pts[row + 1][col]
            draw_line(a.x, a.y, b.x, b.y)
        end
    end

    -- Dense grid override inside downtown
    local dt_block = math.max(4, math.floor(block_size / 2))
    for dy = dt_y1, dt_y2, dt_block do
        for dx = dt_x1, dt_x2 do write_road(dx, dy) end
    end
    for dx = dt_x1, dt_x2, dt_block do
        for dy = dt_y1, dt_y2 do write_road(dx, dy) end
    end

    Game.street_segments = {}
    return true
end

return OrganicStreetService
