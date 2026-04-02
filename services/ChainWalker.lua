-- services/ChainWalker.lua
-- Low-level road-graph utilities: builds a degree table and merges path
-- segments that share degree-2 (pass-through) endpoints into longer chains.
-- Used by RoadSmoother to post-process raw road segments.

local ChainWalker = {}

local DIRS8 = {{1,0},{-1,0},{0,1},{0,-1},{1,1},{1,-1},{-1,1},{-1,-1}}

local ROAD_TYPES = { arterial = true, highway = true }

-- 8-connected degree table for road tiles.
-- deg[gy][gx] = number of same-type neighbours (nil for non-matching tiles).
-- types: optional set of tile types to count (defaults to ROAD_TYPES).
function ChainWalker.buildDeg8(grid, gw, gh, types)
    types = types or ROAD_TYPES
    local deg = {}
    for gy = 1, gh do
        deg[gy] = {}
        for gx = 1, gw do
            local t = grid[gy] and grid[gy][gx] and grid[gy][gx].type
            if types[t] then
                local d = 0
                for _, dir in ipairs(DIRS8) do
                    local nx, ny = gx + dir[1], gy + dir[2]
                    if nx >= 1 and nx <= gw and ny >= 1 and ny <= gh then
                        local nt = grid[ny] and grid[ny][nx] and grid[ny][nx].type
                        if types[nt] then d = d + 1 end
                    end
                end
                deg[gy][gx] = d
            end
        end
    end
    return deg
end

-- Merge path segments that share a degree-2 endpoint into single longer chains.
-- A degree-2 node (shared by exactly 2 path endpoints) is a simple pass-through:
-- the two paths should be one continuous curve, not two separate ones with a hard
-- corner.  Degree-1 nodes (true terminals) and degree-3+ nodes (real intersections)
-- are left alone.
function ChainWalker.mergeChains(paths)
    if #paths == 0 then return paths end

    local function ptkey(c) return c.x * 100003 + c.y end

    -- Count how many path-endpoints land on each coordinate.
    local deg = {}
    for _, p in ipairs(paths) do
        if #p >= 2 then
            local sk, ek = ptkey(p[1]), ptkey(p[#p])
            deg[sk] = (deg[sk] or 0) + 1
            if sk ~= ek then deg[ek] = (deg[ek] or 0) + 1 end
        end
    end

    -- At degree-2 nodes, index which paths touch that node and from which end.
    local adj = {}
    for i, p in ipairs(paths) do
        if #p >= 2 then
            local sk, ek = ptkey(p[1]), ptkey(p[#p])
            if (deg[sk] or 0) == 2 then
                adj[sk] = adj[sk] or {}
                adj[sk][#adj[sk]+1] = {idx=i, which="start"}
            end
            if sk ~= ek and (deg[ek] or 0) == 2 then
                adj[ek] = adj[ek] or {}
                adj[ek][#adj[ek]+1] = {idx=i, which="end"}
            end
        end
    end

    local used   = {}
    local result = {}

    -- Check that joining next_path onto chain at the shared junction won't create
    -- a U-turn (dot < -0.5 ≈ sharper than ~120°).
    local function angleOK(chain, np, nrev)
        if #chain < 2 or #np < 2 then return true end
        local tail, prev = chain[#chain], chain[#chain - 1]
        local ax, ay = tail.x - prev.x, tail.y - prev.y
        local al = math.sqrt(ax*ax + ay*ay)
        if al == 0 then return true end
        ax, ay = ax/al, ay/al
        local ox, oy
        if nrev then
            ox = np[#np-1].x - np[#np].x; oy = np[#np-1].y - np[#np].y
        else
            ox = np[2].x - np[1].x;       oy = np[2].y - np[1].y
        end
        local ol = math.sqrt(ox*ox + oy*oy)
        if ol == 0 then return true end
        return (ax*(ox/ol) + ay*(oy/ol)) > -0.5
    end

    local function extend_fwd(chain)
        while true do
            local tail_key = ptkey(chain[#chain])
            local nbrs = adj[tail_key]
            local ni, nrev = nil, false
            if nbrs then
                for _, nb in ipairs(nbrs) do
                    if not used[nb.idx] then ni = nb.idx; nrev = (nb.which == "end"); break end
                end
            end
            if not ni then break end
            local np = paths[ni]
            if not angleOK(chain, np, nrev) then break end
            used[ni] = true
            chain[#chain+1] = chain[#chain]   -- duplicate junction to pin Chaikin curve
            if nrev then
                for j = #np - 1, 1, -1 do chain[#chain+1] = np[j] end
            else
                for j = 2, #np       do chain[#chain+1] = np[j] end
            end
        end
    end

    local function extend_bwd(chain)
        while true do
            local head_key = ptkey(chain[1])
            local nbrs = adj[head_key]
            local pi, prev_rev = nil, false
            if nbrs then
                for _, nb in ipairs(nbrs) do
                    if not used[nb.idx] then pi = nb.idx; prev_rev = (nb.which == "start"); break end
                end
            end
            if not pi then break end
            local pp = paths[pi]
            local function bwdAngleOK()
                if #chain < 2 or #pp < 2 then return true end
                local dx = chain[2].x - chain[1].x; local dy = chain[2].y - chain[1].y
                local dl = math.sqrt(dx*dx + dy*dy)
                if dl == 0 then return true end
                dx, dy = dx/dl, dy/dl
                local ax, ay
                if prev_rev then ax = pp[1].x - pp[2].x; ay = pp[1].y - pp[2].y
                else              ax = pp[#pp].x - pp[#pp-1].x; ay = pp[#pp].y - pp[#pp-1].y end
                local al = math.sqrt(ax*ax + ay*ay)
                if al == 0 then return true end
                return ((ax/al)*dx + (ay/al)*dy) > -0.5
            end
            if not bwdAngleOK() then break end
            used[pi] = true
            local front = {}
            if prev_rev then
                for j = #pp, 2, -1 do front[#front+1] = pp[j] end
            else
                for j = 1, #pp - 1 do front[#front+1] = pp[j] end
            end
            front[#front+1] = chain[1]   -- duplicate junction to pin Chaikin curve
            for _, pt in ipairs(chain) do front[#front+1] = pt end
            chain = front
        end
        return chain
    end

    for start_i = 1, #paths do
        if not used[start_i] and #paths[start_i] >= 2 then
            used[start_i] = true
            local chain = {}
            for _, pt in ipairs(paths[start_i]) do chain[#chain+1] = pt end
            extend_fwd(chain)
            chain = extend_bwd(chain)
            result[#result+1] = chain
        end
    end

    return result
end

return ChainWalker
