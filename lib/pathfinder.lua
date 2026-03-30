-- lib/pathfinder.lua
-- A minimal A* pathfinding implementation for a grid.
-- Adapted from various public domain sources.
--
-- Two node types coexist:
--   Corner node  {x, y}              pixel = (x*tps,       y*tps)       -- gap between sub-cells
--   Tile node    {x, y, is_tile=true} pixel = ((x+0.5)*tps, (y+0.5)*tps) -- centre of a road tile

local Pathfinder = {}

-- Unique string key that distinguishes corner nodes from tile-centre nodes.
local function nodeKey(node)
    return (node.is_tile and "t" or "") .. node.y .. "," .. node.x
end

local function getNeighbors(node, grid, grid_width, grid_height, map)
    local neighbors = {}
    local x, y = node.x, node.y

    if not map.road_v_rxs then
        -- Sandbox map: sub-cell coords, single-step, check tile type directly.
        for _, dir in ipairs({{0,-1},{0,1},{-1,0},{1,0}}) do
            local nx, ny = x + dir[1], y + dir[2]
            if nx > 0 and nx <= grid_width and ny > 0 and ny <= grid_height then
                if map:isRoad(grid[ny][nx].type) then
                    table.insert(neighbors, {x = nx, y = ny, dist = 1})
                end
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

local function reconstructPath(cameFrom, current)
    local totalPath = {current}
    while cameFrom[nodeKey(current)] do
        current = cameFrom[nodeKey(current)]
        table.insert(totalPath, 1, current)
    end
    return totalPath
end

local function heuristic(a, b)
    return math.abs(a.x - b.x) + math.abs(a.y - b.y)
end

function Pathfinder.findPath(grid, startNode, endNode, costs, map)
    if not costs then
        error("FATAL: Pathfinder.findPath was called without a 'costs' function or table. This is a required argument. Please check the function call.", 0)
        return nil
    end
    if not map then
        error("FATAL: Pathfinder.findPath was called without a 'map' object. This is a required argument.", 0)
        return nil
    end

    local grid_height = #grid
    local grid_width = #grid[1]

    local startKey = nodeKey(startNode)
    local endKey   = nodeKey(endNode)

    local openSet = {[startKey] = startNode}
    local cameFrom = {}
    local gScore   = {[startKey] = 0}
    local fScore   = {[startKey] = heuristic(startNode, endNode)}

    while next(openSet) do
        local current, lowestF = nil, math.huge
        for _, node in pairs(openSet) do
            local f = fScore[nodeKey(node)]
            if f < lowestF then lowestF = f; current = node end
        end

        if nodeKey(current) == endKey then
            return reconstructPath(cameFrom, current)
        end

        local curKey = nodeKey(current)
        openSet[curKey] = nil

        for _, neighbor in ipairs(getNeighbors(current, grid, grid_width, grid_height, map)) do
            local move_cost = costs(neighbor.x, neighbor.y) * (neighbor.dist or 1)
            local tentative  = gScore[curKey] + move_cost
            local nk         = nodeKey(neighbor)

            if not gScore[nk] or tentative < gScore[nk] then
                cameFrom[nk]  = current
                gScore[nk]    = tentative
                fScore[nk]    = tentative + heuristic(neighbor, endNode)
                if not openSet[nk] then openSet[nk] = neighbor end
            end
        end
    end

    return nil
end

return Pathfinder
