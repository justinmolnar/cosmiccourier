-- services/streets/RadialStreetService.lua
-- Spokes radiate from center, concentric rings connect them.
-- Within each sector, a few arc-parallel connectors subdivide the pie slices.
-- NO grid fill over the whole map.
local RadialStreetService = {}

function RadialStreetService.generateStreets(city_grid, zone_grid, arterial_paths, params)
    local C_MAP = require("data.constants").MAP
    local width  = #city_grid[1]
    local height = #city_grid

    local num_spokes = math.floor(params.num_spokes or 8)
    local num_rings  = math.floor(params.num_rings  or 4)

    local hub_x = width  / 2
    local hub_y = height / 2
    local max_r = math.min(width, height) * 0.47
    local ring_gap = max_r / (num_rings + 1)

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

    local PI = math.pi

    -- Spoke angles (evenly distributed, small random jitter)
    local spoke_angles = {}
    for i = 0, num_spokes - 1 do
        local base = (i / num_spokes) * PI * 2
        local jitter = (love.math.random() * 2 - 1) * 0.08 * (PI * 2 / num_spokes)
        table.insert(spoke_angles, base + jitter)
    end

    -- Draw spokes: from just outside downtown edge to map edge
    local dt_r = math.sqrt((downtown_w/2)^2 + (downtown_h/2)^2) * 1.1
    for _, angle in ipairs(spoke_angles) do
        local sx = hub_x + math.cos(angle) * dt_r
        local sy = hub_y + math.sin(angle) * dt_r
        local ex = hub_x + math.cos(angle) * max_r
        local ey = hub_y + math.sin(angle) * max_r
        draw_line(sx, sy, ex, ey)
    end

    -- Draw rings (approximated with line segments, skip inside downtown)
    local circle_segs = 128
    for ring = 1, num_rings do
        local r = ring_gap * ring
        for seg = 0, circle_segs - 1 do
            local a1 = (seg     / circle_segs) * PI * 2
            local a2 = ((seg+1) / circle_segs) * PI * 2
            local rx1 = hub_x + math.cos(a1) * r
            local ry1 = hub_y + math.sin(a1) * r
            local rx2 = hub_x + math.cos(a2) * r
            local ry2 = hub_y + math.sin(a2) * r
            -- Skip segment if it's inside downtown bounds
            local mid_x = (rx1 + rx2) / 2
            local mid_y = (ry1 + ry2) / 2
            if not (mid_x >= dt_x1 and mid_x <= dt_x2 and mid_y >= dt_y1 and mid_y <= dt_y2) then
                draw_line(rx1, ry1, rx2, ry2)
            end
        end
    end

    -- Arc-parallel connectors within each sector to make usable blocks.
    -- For each sector (between consecutive spokes), draw 1-2 roads that run
    -- parallel to the rings (connecting the two bounding spokes at mid-radius points).
    for i = 1, #spoke_angles do
        local a1 = spoke_angles[i]
        local a2 = spoke_angles[(i % #spoke_angles) + 1]
        -- Ensure we go the short way around
        local da = a2 - a1
        if da >  PI then da = da - PI * 2 end
        if da < -PI then da = da + PI * 2 end

        -- Add connectors between consecutive rings within this sector
        for ring = 0, num_rings do
            local r_inner = ring_gap * ring + ring_gap * 0.5
            local r_outer = ring_gap * (ring + 1) + ring_gap * 0.5
            if r_inner > max_r then break end
            -- Mid-arc: connect from spoke a1 side to spoke a2 side at a middle radius
            local mid_r = (r_inner + r_outer) / 2
            if mid_r > dt_r then
                local cx1 = hub_x + math.cos(a1) * mid_r
                local cy1 = hub_y + math.sin(a1) * mid_r
                local cx2 = hub_x + math.cos(a2) * mid_r
                local cy2 = hub_y + math.sin(a2) * mid_r
                -- Only draw if the arc is wide enough to be worth it
                local arc_len = math.abs(da) * mid_r
                if arc_len > ring_gap * 0.8 then
                    draw_line(cx1, cy1, cx2, cy2)
                end
            end
        end
    end

    -- Dense grid inside downtown
    local dt_block = 6
    for dy = dt_y1, dt_y2, dt_block do
        for dx = dt_x1, dt_x2 do write_road(dx, dy) end
    end
    for dx = dt_x1, dt_x2, dt_block do
        for dy = dt_y1, dt_y2 do write_road(dx, dy) end
    end

    Game.street_segments = {}
    return true
end

return RadialStreetService
