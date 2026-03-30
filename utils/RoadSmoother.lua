-- utils/RoadSmoother.lua
-- Traces arterial/highway roads as continuous end-to-end paths.
-- Each road is one path from terminal to terminal; intersections are
-- passed through by always picking the most-forward available tile.

local RoadSmoother = {}

local ROAD_TYPES = {
    arterial     = true,
    highway      = true,
    highway_ring = true,
    highway_ns   = true,
    highway_ew   = true,
}

local DIRS8 = {{1,0},{-1,0},{0,1},{0,-1},{1,1},{1,-1},{-1,1},{-1,-1}}

-- ── helpers ──────────────────────────────────────────────────────────────────

local function ptSegDist(px,py,ax,ay,bx,by)
    local dx,dy = bx-ax, by-ay
    local len2 = dx*dx+dy*dy
    if len2==0 then local ex,ey=px-ax,py-ay; return math.sqrt(ex*ex+ey*ey) end
    local t = math.max(0,math.min(1,((px-ax)*dx+(py-ay)*dy)/len2))
    local ex,ey = px-(ax+t*dx), py-(ay+t*dy)
    return math.sqrt(ex*ex+ey*ey)
end

local function rdp(pts,lo,hi,eps,keep)
    if hi<=lo+1 then return end
    local ax,ay = pts[lo*2-1],pts[lo*2]
    local bx,by = pts[hi*2-1],pts[hi*2]
    local maxD,maxI = 0,lo
    for i=lo+1,hi-1 do
        local d = ptSegDist(pts[i*2-1],pts[i*2],ax,ay,bx,by)
        if d>maxD then maxD,maxI=d,i end
    end
    if maxD>eps then
        keep[maxI]=true
        rdp(pts,lo,maxI,eps,keep)
        rdp(pts,maxI,hi,eps,keep)
    end
end

local function simplify(pts,eps)
    local n=#pts/2
    if n<=2 then return pts end
    local keep={[1]=true,[n]=true}
    rdp(pts,1,n,eps,keep)
    local out={}
    for i=1,n do
        if keep[i] then out[#out+1]=pts[i*2-1]; out[#out+1]=pts[i*2] end
    end
    return out
end

local function chaikin(pts,iters)
    for _=1,iters do
        local n=#pts/2
        if n<2 then return pts end
        local out={pts[1],pts[2]}
        for i=1,n-1 do
            local x1,y1=pts[i*2-1],pts[i*2]
            local x2,y2=pts[i*2+1],pts[i*2+2]
            out[#out+1]=.75*x1+.25*x2; out[#out+1]=.75*y1+.25*y2
            out[#out+1]=.25*x1+.75*x2; out[#out+1]=.25*y1+.75*y2
        end
        out[#out+1]=pts[#pts-1]; out[#out+1]=pts[#pts]
        pts=out
    end
    return pts
end

-- ── core ─────────────────────────────────────────────────────────────────────

-- 8-connected degree: used to find road terminals (degree == 1).
local function buildDeg8(grid,gw,gh)
    local deg={}
    for gy=1,gh do
        deg[gy]={}
        for gx=1,gw do
            local t=grid[gy] and grid[gy][gx] and grid[gy][gx].type
            if ROAD_TYPES[t] then
                local d=0
                for _,dir in ipairs(DIRS8) do
                    local nx,ny=gx+dir[1],gy+dir[2]
                    if nx>=1 and nx<=gw and ny>=1 and ny<=gh then
                        local nt=grid[ny] and grid[ny][nx] and grid[ny][nx].type
                        if ROAD_TYPES[nt] then d=d+1 end
                    end
                end
                deg[gy][gx]=d
            end
        end
    end
    return deg
end

-- Walk one road from (sx,sy) to its far end.
-- Always picks the most-forward 8-connected unvisited road tile.
-- Stops only when no forward tile exists (threshold -0.7 blocks U-turns)
-- or a visited tile is encountered (closes a loop or hits a traced road).
local function walkRoad(sx,sy,grid,gw,gh,visited)
    local chain={{x=sx,y=sy}}
    local key0=sy*(gw+1)+sx
    visited[key0]=true

    -- Find initial direction from first available road neighbour
    local pdx,pdy=1,0
    for _,dir in ipairs(DIRS8) do
        local nx,ny=sx+dir[1],sy+dir[2]
        if nx>=1 and nx<=gw and ny>=1 and ny<=gh then
            local nt=grid[ny] and grid[ny][nx] and grid[ny][nx].type
            if ROAD_TYPES[nt] and not visited[ny*(gw+1)+nx] then
                pdx,pdy=dir[1],dir[2]; break
            end
        end
    end

    local cx,cy=sx+pdx,sy+pdy

    while cx>=1 and cx<=gw and cy>=1 and cy<=gh do
        local t=grid[cy] and grid[cy][cx] and grid[cy][cx].type
        if not ROAD_TYPES[t] then break end
        local key=cy*(gw+1)+cx
        if visited[key] then
            table.insert(chain,{x=cx,y=cy})   -- cap at first revisited tile
            break
        end
        visited[key]=true
        table.insert(chain,{x=cx,y=cy})

        -- Best-forward neighbour: highest dot with current direction.
        -- Threshold -0.7 ≈ 135° — prevents U-turns, allows all useful turns.
        local bx,by,bdx,bdy,bdot=nil,nil,nil,nil,-0.7
        for _,dir in ipairs(DIRS8) do
            local nx,ny=cx+dir[1],cy+dir[2]
            if nx>=1 and nx<=gw and ny>=1 and ny<=gh then
                local nt=grid[ny] and grid[ny][nx] and grid[ny][nx].type
                if ROAD_TYPES[nt] and not visited[ny*(gw+1)+nx] then
                    local dot=dir[1]*pdx+dir[2]*pdy
                    if dot>bdot then bdot=dot; bx,by,bdx,bdy=nx,ny,dir[1],dir[2] end
                end
            end
        end

        if bx then pdx,pdy=bdx,bdy; cx,cy=bx,by
        else break end
    end

    return chain
end

-- ── chain merging ────────────────────────────────────────────────────────────

-- Merge path segments that share a degree-2 endpoint into single longer chains.
-- A degree-2 node (shared by exactly 2 path endpoints) is a simple pass-through:
-- the two paths should be one continuous curve, not two separate ones with a hard
-- corner.  Degree-1 nodes (true terminals) and degree-3+ nodes (real intersections)
-- are left alone.
local function mergeChains(paths)
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
    -- adj[key] = list of {idx, which}   where which = "start" | "end"
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

    -- Check that joining next_path onto chain at the shared junction won't create a
    -- U-turn.  Computes the dot product between the chain's arriving direction and
    -- next_path's departing direction.  Returns false if the turn is sharper than
    -- ~120° (dot < -0.5), which would produce a tight loop after Chaikin smoothing.
    local function angleOK(chain, np, nrev)
        if #chain < 2 or #np < 2 then return true end
        -- Arriving direction: last segment of current chain toward junction
        local tail  = chain[#chain]
        local prev  = chain[#chain - 1]
        local ax, ay = tail.x - prev.x, tail.y - prev.y
        local al = math.sqrt(ax*ax + ay*ay)
        if al == 0 then return true end
        ax, ay = ax/al, ay/al
        -- Departing direction: first step of next path away from junction
        local ox, oy
        if nrev then
            -- appending np reversed: junction = np[#np], first new point = np[#np-1]
            ox = np[#np-1].x - np[#np].x
            oy = np[#np-1].y - np[#np].y
        else
            -- appending np forward: junction = np[1], first new point = np[2]
            ox = np[2].x - np[1].x
            oy = np[2].y - np[1].y
        end
        local ol = math.sqrt(ox*ox + oy*oy)
        if ol == 0 then return true end
        ox, oy = ox/ol, oy/ol
        return (ax*ox + ay*oy) > -0.5   -- reject turns sharper than ~120°
    end

    -- Extend the chain forward (from its current tail).
    local function extend_fwd(chain)
        while true do
            local tail_key = ptkey(chain[#chain])
            local nbrs = adj[tail_key]
            local ni, nrev = nil, false
            if nbrs then
                for _, nb in ipairs(nbrs) do
                    if not used[nb.idx] then
                        ni   = nb.idx
                        nrev = (nb.which == "end")   -- path's END is at tail → append reversed
                        break
                    end
                end
            end
            if not ni then break end
            local np = paths[ni]
            if not angleOK(chain, np, nrev) then break end  -- too sharp → leave as endpoint
            used[ni] = true
            -- Duplicate the junction point so Chaikin is pinned to pass through it.
            -- Two consecutive identical control points act as an anchor — the smoothed
            -- curve is forced through the junction, connecting to paths that end there.
            chain[#chain+1] = chain[#chain]
            if nrev then
                for j = #np - 1, 1, -1 do chain[#chain+1] = np[j] end  -- skip np[#np] (= junction)
            else
                for j = 2, #np       do chain[#chain+1] = np[j] end  -- skip np[1]   (= junction)
            end
        end
    end

    -- Extend the chain backward (from its current head), prepending.
    local function extend_bwd(chain)
        while true do
            local head_key = ptkey(chain[1])
            local nbrs = adj[head_key]
            local pi, prev_rev = nil, false
            if nbrs then
                for _, nb in ipairs(nbrs) do
                    if not used[nb.idx] then
                        pi       = nb.idx
                        prev_rev = (nb.which == "start")  -- path's START is at head → prepend reversed
                        break
                    end
                end
            end
            if not pi then break end
            local pp    = paths[pi]
            -- Build the prepend section and check angle at junction (chain[1])
            -- The prepended path arrives at chain[1]; check its last direction vs chain[1]→chain[2]
            local function bwdAngleOK()
                if #chain < 2 or #pp < 2 then return true end
                -- Departing: chain[1] → chain[2]
                local dx = chain[2].x - chain[1].x
                local dy = chain[2].y - chain[1].y
                local dl = math.sqrt(dx*dx + dy*dy)
                if dl == 0 then return true end
                dx, dy = dx/dl, dy/dl
                -- Arriving at chain[1] from pp
                local ax, ay
                if prev_rev then
                    -- prepending pp reversed: junction = pp[1], last prepended = pp[2]
                    ax = pp[1].x - pp[2].x
                    ay = pp[1].y - pp[2].y
                else
                    -- prepending pp forward: junction = pp[#pp], last prepended = pp[#pp-1]
                    ax = pp[#pp].x - pp[#pp-1].x
                    ay = pp[#pp].y - pp[#pp-1].y
                end
                local al = math.sqrt(ax*ax + ay*ay)
                if al == 0 then return true end
                ax, ay = ax/al, ay/al
                return (ax*dx + ay*dy) > -0.5
            end
            if not bwdAngleOK() then break end
            used[pi] = true
            local front = {}
            if prev_rev then
                for j = #pp, 2, -1 do front[#front+1] = pp[j] end  -- skip pp[1] (= junction)
            else
                for j = 1, #pp - 1 do front[#front+1] = pp[j] end  -- skip pp[#pp] (= junction)
            end
            -- Duplicate the junction point to pin the Chaikin curve through it
            front[#front+1] = chain[1]
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

-- ── public ───────────────────────────────────────────────────────────────────

-- Preferred path: use pre-stored ordered centerlines from world generation.
-- Each centerline is a list of {x,y} local sub-cell grid coords (1-indexed).
-- Merges degree-2 junctions before smoothing so pass-through corners get curved.
-- Returns list of Chaikin-smoothed flat pixel arrays ready for love.graphics.line.
function RoadSmoother.buildPathsFromCenterlines(centerlines, tps)
    local merged  = mergeChains(centerlines)
    local paths   = {}
    local epsilon = tps * 1.2
    for _, cl in ipairs(merged) do
        if #cl >= 2 then
            local pts = {}
            for _, c in ipairs(cl) do
                pts[#pts+1] = (c.x - 0.5) * tps
                pts[#pts+1] = (c.y - 0.5) * tps
            end
            pts = simplify(pts, epsilon)
            pts = chaikin(pts, 4)
            if #pts >= 4 then paths[#paths+1] = pts end
        end
    end
    return paths
end

function RoadSmoother.buildPaths(grid,tps)
    if not grid or #grid==0 then return {} end
    local gh=#grid
    local gw=#(grid[1] or {})
    if gw==0 then return {} end

    local deg8   = buildDeg8(grid,gw,gh)
    local visited= {}
    local paths  = {}
    local epsilon= tps*1.2

    local function process(chain)
        if #chain<2 then return end
        local pts={}
        for _,c in ipairs(chain) do
            pts[#pts+1]=(c.x-.5)*tps; pts[#pts+1]=(c.y-.5)*tps
        end
        pts=simplify(pts,epsilon)
        pts=chaikin(pts,4)
        if #pts>=4 then paths[#paths+1]=pts end
    end

    -- Pass 1: start from degree-1 terminals (true road ends).
    for gy=1,gh do
        for gx=1,gw do
            local d=deg8[gy] and deg8[gy][gx]
            if d and d==1 and not visited[gy*(gw+1)+gx] then
                process(walkRoad(gx,gy,grid,gw,gh,visited))
            end
        end
    end

    -- Pass 2: mop up any unvisited tiles (loops, isolated segments).
    for gy=1,gh do
        for gx=1,gw do
            local d=deg8[gy] and deg8[gy][gx]
            if d and not visited[gy*(gw+1)+gx] then
                process(walkRoad(gx,gy,grid,gw,gh,visited))
            end
        end
    end

    return paths
end

return RoadSmoother
