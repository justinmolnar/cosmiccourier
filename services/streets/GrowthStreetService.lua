local GrowthStreetService = {}

function GrowthStreetService.generateStreets(city_grid, zone_grid, arterial_paths, params)
    local C_MAP = require("data.constants").MAP
    local width  = #city_grid[1]
    local height = #city_grid

    local max_length   = math.floor(params.max_road_length or 30)
    local branch_ch    = params.branch_chance  or 0.06
    local turn_ch      = params.turn_chance    or 0.04
    local num_seeds    = math.floor(params.num_seeds or 40)

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

    local function is_road(x, y)
        if x < 1 or x > width or y < 1 or y > height then return false end
        local t = city_grid[y][x].type
        return t=="road" or t=="downtown_road" or t=="arterial"
    end

    -- Directions: 1=right(+x), 2=down(+y), 3=left(-x), 4=up(-y)
    local DX = {1, 0, -1,  0}
    local DY = {0, 1,  0, -1}

    local function turn_cw(d)  return (d % 4) + 1 end
    local function turn_ccw(d) return ((d-2) % 4) + 1 end

    local agents = {}

    -- Seed from arterial borders
    local arterial_seeds = 0
    local max_art_seeds = math.floor(num_seeds * 0.6)
    for y2 = 1, height do
        for x2 = 1, width do
            if city_grid[y2][x2].type == "arterial" and arterial_seeds < max_art_seeds then
                for d = 1, 4 do
                    local nx, ny = x2 + DX[d], y2 + DY[d]
                    if nx>=1 and nx<=width and ny>=1 and ny<=height
                       and city_grid[ny][nx].type == "grass"
                       and love.math.random() < 0.12 then
                        local ml = math.floor(max_length * (0.6 + love.math.random()*0.8))
                        table.insert(agents, {x=nx, y=ny, dir=d, len=0, max=ml})
                        arterial_seeds = arterial_seeds + 1
                        if arterial_seeds >= max_art_seeds then break end
                    end
                end
                if arterial_seeds >= max_art_seeds then break end
            end
        end
        if arterial_seeds >= max_art_seeds then break end
    end

    -- Random seeds for the rest
    local attempts = 0
    while #agents < num_seeds and attempts < num_seeds * 10 do
        attempts = attempts + 1
        local x2 = love.math.random(5, width-5)
        local y2 = love.math.random(5, height-5)
        local d  = love.math.random(1, 4)
        local ml = math.floor(max_length * (0.6 + love.math.random()*0.8))
        table.insert(agents, {x=x2, y=y2, dir=d, len=0, max=ml})
    end

    -- Run agents
    local max_iters = width * height
    local iters = 0
    while #agents > 0 and iters < max_iters do
        iters = iters + 1
        local next_agents = {}
        for _, ag in ipairs(agents) do
            if ag.len >= ag.max then goto skip end

            local nx = ag.x + DX[ag.dir]
            local ny = ag.y + DY[ag.dir]

            if nx<1 or nx>width or ny<1 or ny>height then goto skip end
            if is_road(nx, ny) then goto skip end

            write_road(ag.x, ag.y)

            -- Branch
            if ag.len > 4 and love.math.random() < branch_ch then
                local bd = love.math.random()<0.5 and turn_cw(ag.dir) or turn_ccw(ag.dir)
                local bx, by = ag.x + DX[bd], ag.y + DY[bd]
                if bx>=1 and bx<=width and by>=1 and by<=height and not is_road(bx,by) then
                    local bml = math.floor(ag.max * (0.4 + love.math.random()*0.4))
                    table.insert(next_agents, {x=bx, y=by, dir=bd, len=0, max=bml})
                end
            end

            -- Turn (don't reverse)
            if love.math.random() < turn_ch then
                local nd = love.math.random()<0.5 and turn_cw(ag.dir) or turn_ccw(ag.dir)
                ag.dir = nd
                nx = ag.x + DX[ag.dir]
                ny = ag.y + DY[ag.dir]
            end

            ag.x, ag.y = nx, ny
            ag.len = ag.len + 1
            table.insert(next_agents, ag)

            ::skip::
        end
        agents = next_agents
    end

    -- Dense downtown grid on top
    local dt_block = 6
    for dy = dt_y1, dt_y2, dt_block do
        for dx = dt_x1, dt_x2 do write_road(dx, dy) end
    end
    for dx = dt_x1, dt_x2, dt_block do
        for dy = dt_y1, dt_y2 do write_road(dx, dy) end
    end

    -- Prune orphaned roads: keep only road tiles that can reach an arterial
    -- through a chain of adjacent road tiles. Isolated floaters are removed.
    local connected = {}
    local queue     = {}
    local head      = 1

    -- Seed: any road tile directly neighbouring an arterial tile
    local function try_seed(x, y)
        if x < 1 or x > width or y < 1 or y > height then return end
        if cell_mask and (not cell_mask[y] or not cell_mask[y][x]) then return end
        local t = city_grid[y][x].type
        if t ~= "road" and t ~= "downtown_road" then return end
        if connected[y] and connected[y][x] then return end
        for d = 1, 4 do
            local nx, ny = x + DX[d], y + DY[d]
            if nx >= 1 and nx <= width and ny >= 1 and ny <= height
               and city_grid[ny][nx].type == "arterial" then
                if not connected[y] then connected[y] = {} end
                connected[y][x] = true
                table.insert(queue, { x = x, y = y })
                return
            end
        end
    end

    if cell_mask then
        for cy, row in pairs(cell_mask) do
            for cx in pairs(row) do try_seed(cx, cy) end
        end
    else
        for sy = 1, height do
            for sx = 1, width do try_seed(sx, sy) end
        end
    end

    -- BFS through adjacent road tiles
    while head <= #queue do
        local c = queue[head]; head = head + 1
        for d = 1, 4 do
            local nx, ny = c.x + DX[d], c.y + DY[d]
            if nx >= 1 and nx <= width and ny >= 1 and ny <= height then
                local in_mask = not cell_mask or (cell_mask[ny] and cell_mask[ny][nx])
                if in_mask and (not connected[ny] or not connected[ny][nx]) then
                    local t = city_grid[ny][nx].type
                    if t == "road" or t == "downtown_road" then
                        if not connected[ny] then connected[ny] = {} end
                        connected[ny][nx] = true
                        table.insert(queue, { x = nx, y = ny })
                    end
                end
            end
        end
    end

    -- Remove any road tile not reached by the BFS
    local function prune(x, y)
        local t = city_grid[y][x].type
        if (t == "road" or t == "downtown_road")
           and (not connected[y] or not connected[y][x]) then
            city_grid[y][x] = { type = "grass" }
        end
    end

    if cell_mask then
        for cy, row in pairs(cell_mask) do
            for cx in pairs(row) do prune(cx, cy) end
        end
    else
        for py = 1, height do
            for px = 1, width do prune(px, py) end
        end
    end

    Game.street_segments = {}
    return true
end

return GrowthStreetService
