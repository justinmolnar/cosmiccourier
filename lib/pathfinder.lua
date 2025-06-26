-- lib/pathfinder.lua
-- A minimal A* pathfinding implementation for a grid.
-- Adapted from various public domain sources.

local Pathfinder = {}

local function getNeighbors(node, grid, grid_width, grid_height, map)
    local neighbors = {}
    local x, y = node.x, node.y

    local directions = {{x, y - 1}, {x, y + 1}, {x - 1, y}, {x + 1, y}}

    for _, dir in ipairs(directions) do
        local nx, ny = dir[1], dir[2]
        if nx > 0 and nx <= grid_width and ny > 0 and ny <= grid_height then
            -- FIX: Use the map's isRoad function to check all valid road types
            if map:isRoad(grid[ny][nx].type) then
                table.insert(neighbors, {x = nx, y = ny})
            end
        end
    end
    return neighbors
end

local function reconstructPath(cameFrom, current)
    local totalPath = {current}
    while cameFrom[current.y .. ',' .. current.x] do
        current = cameFrom[current.y .. ',' .. current.x]
        table.insert(totalPath, 1, current)
    end
    return totalPath
end

local function heuristic(a, b)
    return math.abs(a.x - b.x) + math.abs(a.y - b.y) -- Manhattan distance
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

    local openSet = {[startNode.y .. ',' .. startNode.x] = startNode}
    local cameFrom = {}

    local gScore = {}
    gScore[startNode.y .. ',' .. startNode.x] = 0

    local fScore = {}
    fScore[startNode.y .. ',' .. startNode.x] = heuristic(startNode, endNode)

    while next(openSet) do
        local current = nil
        local lowestFScore = math.huge
        for _, node in pairs(openSet) do
            if fScore[node.y .. ',' .. node.x] < lowestFScore then
                lowestFScore = fScore[node.y .. ',' .. node.x]
                current = node
            end
        end

        if current.x == endNode.x and current.y == endNode.y then
            return reconstructPath(cameFrom, current)
        end

        openSet[current.y .. ',' .. current.x] = nil

        for _, neighbor in ipairs(getNeighbors(current, grid, grid_width, grid_height, map)) do
            -- THE FIX: The 'costs' variable is now a function. We must call it
            -- to get the movement cost for the specific vehicle.
            local move_cost = costs(neighbor.x, neighbor.y)
            
            local tentative_gScore = gScore[current.y .. ',' .. current.x] + move_cost
            local neighborKey = neighbor.y .. ',' .. neighbor.x
            
            if not gScore[neighborKey] or tentative_gScore < gScore[neighborKey] then
                cameFrom[neighborKey] = current
                gScore[neighborKey] = tentative_gScore
                fScore[neighborKey] = gScore[neighborKey] + heuristic(neighbor, endNode)
                if not openSet[neighborKey] then
                    openSet[neighborKey] = neighbor
                end
            end
        end
    end

    return nil -- No path found
end

return Pathfinder