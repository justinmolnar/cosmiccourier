-- lib/pathfinder.lua
-- A minimal A* pathfinding implementation for a grid.
-- Adapted from various public domain sources.
--
-- Two node types coexist:
--   Corner node  {x, y}              pixel = (x*tps,       y*tps)       -- gap between sub-cells
--   Tile node    {x, y, is_tile=true} pixel = ((x+0.5)*tps, (y+0.5)*tps) -- centre of a road tile

local Pathfinder = {}

-- Integer node key: eliminates string allocation in the A* inner loop.
-- Corner nodes: x + y * 65536
-- Tile-centre nodes: same + 2^32 offset (is_tile namespace)
-- Safe for grids up to 65535 wide/tall (world sub-cell grids are ~2000 max).
local _TILE_KEY_OFFSET = 2^32
local function nodeKey(node)
    local base = node.x + node.y * 65536
    return node.is_tile and (base + _TILE_KEY_OFFSET) or base
end

-- Integer → string tile name table for FFI grid reads (matches PathfindingService).
local _TILE_NAMES = {
    [0]="grass", [1]="road", [2]="downtown_road", [3]="arterial", [4]="highway",
    [5]="water",  [6]="mountain", [7]="river", [8]="plot", [9]="downtown_plot",
    [10]="coastal_water", [11]="deep_water", [12]="open_ocean",
}

local function getNeighbors(node, grid, grid_width, grid_height, map)
    local neighbors = {}
    local x, y = node.x, node.y

    if not map.road_v_rxs then
        -- Sandbox map: movement allowed if target is road type OR crosses a zone_seg edge.
        -- zone_seg_v[y][x] = N-S street between cells (x,y) and (x+1,y) [1-indexed].
        -- zone_seg_h[y][x] = E-W street between cells (x,y) and (x,y+1) [1-indexed].
        -- Highway bridge: from a highway cell, allow entry to any adjacent city cell
        -- (non-obstacle) to transition from world highways into city street network.
        local zsv = map.zone_seg_v
        local zsh = map.zone_seg_h
        -- FFI grid (unified map) or Lua grid (city/sandbox maps).
        local fgi = map.ffi_grid
        local fgw = grid_width
        local function getTT(gx, gy)
            if fgi then return _TILE_NAMES[fgi[(gy-1)*fgw + (gx-1)].type] or "grass" end
            return grid[gy] and grid[gy][gx] and grid[gy][gx].type
        end
        local cur_t = getTT(x, y)
        for _, dir in ipairs({{0,-1},{0,1},{-1,0},{1,0}}) do
            local nx, ny = x + dir[1], y + dir[2]
            if nx > 0 and nx <= grid_width and ny > 0 and ny <= grid_height then
                local target_t = getTT(nx, ny)
                local ok = map:isRoad(target_t)
                if not ok then
                    -- Check zone_seg edge between current and target cell
                    if     dir[1] ==  1 then ok = zsv and zsv[y]  and zsv[y][x]   -- East
                    elseif dir[1] == -1 then ok = zsv and zsv[y]  and zsv[y][nx]  -- West
                    elseif dir[2] ==  1 then ok = zsh and zsh[y]  and zsh[y][x]   -- South
                    elseif dir[2] == -1 then ok = zsh and zsh[ny] and zsh[ny][x]  -- North
                    end
                end
                local cur_big    = cur_t    == "highway" or cur_t    == "arterial"
                local target_big = target_t == "highway" or target_t == "arterial"
                if not ok and (cur_big or target_big) then
                    -- Bridge: vehicles can exit/enter arterial and highway tiles to reach
                    -- adjacent zone_seg cells (streets are edges, not tiles, so no isRoad
                    -- match exists when crossing from a big-road tile into a city block).
                    local other_t = cur_big and target_t or cur_t
                    ok = other_t ~= "mountain" and other_t ~= "water"
                      and other_t ~= "river"   and other_t ~= "grass"
                end
                if ok then table.insert(neighbors, {x = nx, y = ny, dist = 1}) end
            end
        end
        return neighbors
    end

    local road_nodes = map.road_nodes
    local tile_nodes = map.tile_nodes  -- may be nil on older maps

    if node.is_tile then
        -- ── Tile-centre node (truck ON a highway/arterial tile) ──────────────
        -- Moves to adjacent tile-centre nodes or bridges off onto corner nodes.
        local tx, ty = x, y

        -- Adjacent highway tiles (4-directional)
        local dirs = {{1,0},{-1,0},{0,1},{0,-1}}
        for _, d in ipairs(dirs) do
            local nx, ny = tx + d[1], ty + d[2]
            if nx >= 0 and nx < grid_width and ny >= 0 and ny < grid_height then
                if tile_nodes and tile_nodes[ny] and tile_nodes[ny][nx] then
                    table.insert(neighbors, {x = nx, y = ny, dist = 1, is_tile = true})
                end
            end
        end

        -- Bridge off: the 4 corner nodes surrounding this tile
        --   TL=(tx,ty)  TR=(tx+1,ty)  BL=(tx,ty+1)  BR=(tx+1,ty+1)
        local corners = {{tx,ty},{tx+1,ty},{tx,ty+1},{tx+1,ty+1}}
        for _, c in ipairs(corners) do
            local cx, cy = c[1], c[2]
            if road_nodes[cy] and road_nodes[cy][cx] then
                table.insert(neighbors, {x = cx, y = cy, dist = 1})
            end
        end

    elseif map.zone_seg_v then
        -- ── Corner node on the zone-boundary street network ───────────────────
        local zsv = map.zone_seg_v
        local zsh = map.zone_seg_h
        local rx, ry = x, y

        -- North
        if ry >= 1 and zsv[ry] and zsv[ry][rx]
           and road_nodes[ry - 1] and road_nodes[ry - 1][rx] then
            table.insert(neighbors, {x = rx, y = ry - 1, dist = 1})
        end
        -- South
        if ry < grid_height - 1 and zsv[ry + 1] and zsv[ry + 1][rx]
           and road_nodes[ry + 1] and road_nodes[ry + 1][rx] then
            table.insert(neighbors, {x = rx, y = ry + 1, dist = 1})
        end
        -- East
        if rx < grid_width - 1 and zsh[ry] and zsh[ry][rx + 1]
           and road_nodes[ry] and road_nodes[ry][rx + 1] then
            table.insert(neighbors, {x = rx + 1, y = ry, dist = 1})
        end
        -- West
        if rx >= 1 and zsh[ry] and zsh[ry][rx]
           and road_nodes[ry] and road_nodes[ry][rx - 1] then
            table.insert(neighbors, {x = rx - 1, y = ry, dist = 1})
        end

        -- Bridge on: the 4 highway tiles whose corner this node is
        --   SE=(rx,ry)  SW=(rx-1,ry)  NE=(rx,ry-1)  NW=(rx-1,ry-1)
        if tile_nodes then
            local tiles = {{rx,ry},{rx-1,ry},{rx,ry-1},{rx-1,ry-1}}
            for _, t in ipairs(tiles) do
                local tx, ty = t[1], t[2]
                if tx >= 0 and ty >= 0 and tile_nodes[ty] and tile_nodes[ty][tx] then
                    table.insert(neighbors, {x = tx, y = ty, dist = 1, is_tile = true})
                end
            end
        end

    else
        -- ── Original road-node map (no zone_seg) ─────────────────────────────
        for _, dir in ipairs({{0,-1},{0,1},{-1,0},{1,0}}) do
            local nx, ny = x + dir[1], y + dir[2]
            if nx >= 0 and nx < grid_width and ny >= 0 and ny < grid_height then
                if road_nodes[ny] and road_nodes[ny][nx] then
                    table.insert(neighbors, {x = nx, y = ny, dist = 1})
                end
            end
        end
    end

    return neighbors
end

-- O(n) path reconstruction: append in reverse order then flip once.
-- The old approach used table.insert(path, 1, node) which is O(n) per step → O(n²) total.
local function reconstructPath(cameFrom, current)
    local path = {}
    local k = nodeKey(current)
    path[1] = current
    local parent = cameFrom[k]
    while parent do
        current = parent
        path[#path + 1] = current
        k = nodeKey(current)
        parent = cameFrom[k]
    end
    -- Reverse in-place: path is [end … start], need [start … end]
    local n = #path
    for i = 1, math.floor(n / 2) do
        path[i], path[n - i + 1] = path[n - i + 1], path[i]
    end
    return path
end

local function heuristic(a, b)
    return math.abs(a.x - b.x) + math.abs(a.y - b.y)
end

-- Cost threshold above which a tile is considered impassable.
-- Matches IMPASSABLE_COST in WorldGenConfig and vehicle pathfinding_costs tables.
local _IMPASSABLE = 9999

function Pathfinder.findPath(grid, startNode, endNode, costs, map, turn_costs)
    if not costs then
        error("FATAL: Pathfinder.findPath was called without a 'costs' function or table. This is a required argument. Please check the function call.", 0)
        return nil
    end
    if not map then
        error("FATAL: Pathfinder.findPath was called without a 'map' object. This is a required argument.", 0)
        return nil
    end

    local grid_height = map._h or (grid and #grid or 0)
    local grid_width  = map._w or (grid and grid[1] and #grid[1] or 0)

    -- ── Direction-aware A* (turn_costs provided) ──────────────────────────────
    -- Used for shipline generation and any other trunk that needs smooth curves.
    -- Node state = (x, y, dir): dir 0=N 1=E 2=S 3=W.
    -- Bypasses getNeighbors entirely — raw 4-directional expansion, cost function
    -- determines traversability. Turn penalty added per direction change.
    -- When turn_costs is nil this block is skipped; existing behaviour unchanged.
    if turn_costs then
        local tc90     = turn_costs.turn_90  or 0
        local tc180    = turn_costs.turn_180 or 0
        -- dx, dy, dir_id for each cardinal direction
        local DIRS     = {{0,-1,0},{1,0,1},{0,1,2},{-1,0,3}}
        -- Key encodes (x, y, dir): dir offset = dir * 65536²
        local DIR_STR  = 65536 * 65536
        local SEED_DIR = 4   -- sentinel: start node has no incoming direction
        local function dk(x, y, d) return x + y * 65536 + d * DIR_STR end

        local heap, cameFrom, gScore, closed = {}, {}, {}, {}
        local function hpush(f, node)
            local i = #heap + 1; heap[i] = {f=f, node=node}
            while i > 1 do
                local p = math.floor(i/2)
                if heap[p].f > heap[i].f then heap[p],heap[i]=heap[i],heap[p]; i=p else break end
            end
        end
        local function hpop()
            local top=heap[1]; local n=#heap; heap[1]=heap[n]; heap[n]=nil
            local i=1
            while true do
                local l,r,s=2*i,2*i+1,i
                if l<=#heap and heap[l].f<heap[s].f then s=l end
                if r<=#heap and heap[r].f<heap[s].f then s=r end
                if s==i then break end
                heap[i],heap[s]=heap[s],heap[i]; i=s
            end
            return top
        end

        local sk = dk(startNode.x, startNode.y, SEED_DIR)
        gScore[sk] = 0
        hpush(heuristic(startNode, endNode), {x=startNode.x, y=startNode.y, dir=SEED_DIR})

        while #heap > 0 do
            local entry = hpop()
            local cur   = entry.node
            local curk  = dk(cur.x, cur.y, cur.dir)
            if not closed[curk] then
                closed[curk] = true

                if cur.x == endNode.x and cur.y == endNode.y then
                    -- Reconstruct path, stripping direction from output nodes.
                    local path, k, node = {}, curk, cur
                    while node do
                        path[#path+1] = {x=node.x, y=node.y}
                        local parent   = cameFrom[k]
                        if not parent then break end
                        k    = dk(parent.x, parent.y, parent.dir)
                        node = parent
                    end
                    local pn = #path
                    for i = 1, math.floor(pn/2) do
                        path[i], path[pn-i+1] = path[pn-i+1], path[i]
                    end
                    return path
                end

                local base_g = gScore[curk]
                for _, dv in ipairs(DIRS) do
                    local nx, ny, ndir = cur.x+dv[1], cur.y+dv[2], dv[3]
                    if nx>=1 and nx<=grid_width and ny>=1 and ny<=grid_height then
                        local move_cost = costs(nx, ny)
                        if move_cost < _IMPASSABLE then
                            -- Turn penalty: none from seed, 90° or 180° otherwise.
                            local turn_pen = 0
                            if cur.dir ~= SEED_DIR then
                                local diff = math.abs(ndir - cur.dir)
                                if     diff == 2            then turn_pen = tc180
                                elseif diff == 1 or diff == 3 then turn_pen = tc90
                                end
                            end
                            local nk = dk(nx, ny, ndir)
                            local tg = base_g + move_cost + turn_pen
                            if not gScore[nk] or tg < gScore[nk] then
                                gScore[nk]   = tg
                                cameFrom[nk] = cur
                                hpush(tg + heuristic({x=nx,y=ny}, endNode),
                                      {x=nx, y=ny, dir=ndir})
                            end
                        end
                    end
                end
            end
        end

        local closed_count = 0
        for _ in pairs(closed) do closed_count = closed_count + 1 end
        print(string.format("DEBUG pathfinder (turn): no path found. start=(%d,%d) end=(%d,%d) explored=%d",
            startNode.x, startNode.y, endNode.x, endNode.y, closed_count))
        return nil
    end
    -- ── End direction-aware A* ────────────────────────────────────────────────

    local startKey = nodeKey(startNode)
    local endKey   = nodeKey(endNode)

    -- Binary min-heap ordered by fScore.
    -- Lazy deletion: when a shorter path to an already-queued node is found,
    -- push a new entry with the better score. When popping, skip nodes already
    -- in closedSet (their best path was already processed).
    local heap = {}
    local function heap_push(f, node)
        local i = #heap + 1
        heap[i] = {f = f, node = node}
        while i > 1 do
            local p = math.floor(i / 2)
            if heap[p].f > heap[i].f then
                heap[p], heap[i] = heap[i], heap[p]; i = p
            else break end
        end
    end
    local function heap_pop()
        local top = heap[1]
        local n = #heap
        heap[1] = heap[n]; heap[n] = nil
        local i = 1
        while true do
            local l, r, s = 2*i, 2*i+1, i
            if l <= #heap and heap[l].f < heap[s].f then s = l end
            if r <= #heap and heap[r].f < heap[s].f then s = r end
            if s == i then break end
            heap[i], heap[s] = heap[s], heap[i]; i = s
        end
        return top
    end

    local cameFrom  = {}
    local gScore    = {[startKey] = 0}
    local closedSet = {}

    heap_push(heuristic(startNode, endNode), startNode)

    while #heap > 0 do
        local entry   = heap_pop()
        local current = entry.node
        local curKey  = nodeKey(current)

        if not closedSet[curKey] then
            closedSet[curKey] = true

            if curKey == endKey then
                return reconstructPath(cameFrom, current)
            end

            for _, neighbor in ipairs(getNeighbors(current, grid, grid_width, grid_height, map)) do
                local nk = nodeKey(neighbor)
                if not closedSet[nk] then
                    local move_cost = costs(neighbor.x, neighbor.y, neighbor) * (neighbor.dist or 1)
                    local tentative = gScore[curKey] + move_cost
                    if not gScore[nk] or tentative < gScore[nk] then
                        cameFrom[nk] = current
                        gScore[nk]   = tentative
                        heap_push(tentative + heuristic(neighbor, endNode), neighbor)
                    end
                end
            end
        end
    end

    -- Heap exhausted: no path exists between start and end.
    local closed_count = 0
    for _ in pairs(closedSet) do closed_count = closed_count + 1 end
    print(string.format("DEBUG pathfinder: no path found. start=%s end=%s explored=%d", startKey, endKey, closed_count))
    return nil
end

return Pathfinder
