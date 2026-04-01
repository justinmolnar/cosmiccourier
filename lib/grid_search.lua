-- lib/grid_search.lua
-- Generic BFS/flood-fill algorithms with no domain knowledge.

local GridSearch = {}

-- BFS flood-fill from (start_x, start_y).
-- passable_fn(x, y) -> bool: return true if the cell can be entered.
-- Returns a list of all reachable {x, y} cells including the start.
function GridSearch.floodFill(grid, start_x, start_y, passable_fn)
    local h, w = #grid, #grid[1]
    local function inBounds(x, y) return x >= 1 and x <= w and y >= 1 and y <= h end
    if not inBounds(start_x, start_y) or not passable_fn(start_x, start_y) then
        return {}
    end
    local visited = {[start_y .. "," .. start_x] = true}
    local q = {{x=start_x, y=start_y}}
    local result = {}
    local qi = 1
    while qi <= #q do
        local cur = q[qi]; qi = qi + 1
        result[#result+1] = cur
        for _, d in ipairs({{0,-1},{0,1},{-1,0},{1,0}}) do
            local nx, ny = cur.x+d[1], cur.y+d[2]
            local k = ny .. "," .. nx
            if inBounds(nx, ny) and not visited[k] and passable_fn(nx, ny) then
                visited[k] = true
                q[#q+1] = {x=nx, y=ny}
            end
        end
    end
    return result
end

return GridSearch
