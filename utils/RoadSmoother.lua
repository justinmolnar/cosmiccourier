-- utils/RoadSmoother.lua
-- Traces arterial/highway roads as continuous end-to-end paths.
-- Each road is one path from terminal to terminal; intersections are
-- passed through by always picking the most-forward available tile.

local RoadSmoother = {}

local ROAD_TYPES = { arterial = true, highway = true }
local DIRS8      = {{1,0},{-1,0},{0,1},{0,-1},{1,1},{1,-1},{-1,1},{-1,-1}}

local PathUtils    = require("lib.path_utils")
local chaikin      = PathUtils.chaikin
local simplify     = PathUtils.simplify
local ChainWalker  = require("services.ChainWalker")
local buildDeg8    = ChainWalker.buildDeg8
local mergeChains  = ChainWalker.mergeChains

-- ── street paths ─────────────────────────────────────────────────────────────

-- Draw zone-boundary city streets as Chaikin-smoothed paths.
-- Builds H/V segments with exact boundary coords so L-turn corners share
-- identical endpoints.  Chains are joined WITHOUT duplicate junction pins —
-- pins would make the corner a zero-length segment that Chaikin cannot curve.
-- Only chains with an actual bend (3+ points) get Chaikin-smoothed.
function RoadSmoother.buildStreetPaths(zone_seg_v, zone_seg_h, zone_grid, tps, grid)
    local zg   = zone_grid
    local segs = {}   -- {p1={x,y}, p2={x,y}}

    -- Vertical segments: one per zone-row cell (NOT pre-merged).
    -- Keeping individual unit segments lets follow() split correctly at T-junctions —
    -- a merged long segment would have T-junction endpoints in its interior, causing
    -- other streets to end at non-endpoint positions that Chaikin then deviates from.
    for gy, row in pairs(zone_seg_v or {}) do
        for rx in pairs(row) do
            local z1 = zg and zg[gy] and zg[gy][rx]
            local z2 = zg and zg[gy] and zg[gy][rx+1]
            if z1 and z1 ~= "none" and z2 and z2 ~= "none" and z1 ~= z2 then
                local cx = rx * tps
                segs[#segs+1] = {p1={x=cx, y=(gy-1)*tps}, p2={x=cx, y=gy*tps}}
            end
        end
    end

    -- Horizontal segments: one per zone-col cell (NOT pre-merged).
    for ry, row in pairs(zone_seg_h or {}) do
        for gx in pairs(row) do
            local z1 = zg and zg[ry] and zg[ry][gx]
            local z2 = zg and zg[ry+1] and zg[ry+1][gx]
            if z1 and z1 ~= "none" and z2 and z2 ~= "none" and z1 ~= z2 then
                local cy = ry * tps
                segs[#segs+1] = {p1={x=(gx-1)*tps, y=cy}, p2={x=gx*tps, y=cy}}
            end
        end
    end

    -- Build endpoint→segment index (without junction pins so Chaikin can curve corners).
    local function ptkey(p) return p.x * 100003 + p.y end
    local ep_deg  = {}   -- number of seg-endpoints landing on each coord
    local ep_refs = {}   -- ep_refs[key] = list of {idx, side}
    for i, s in ipairs(segs) do
        local k1, k2 = ptkey(s.p1), ptkey(s.p2)
        ep_deg[k1]  = (ep_deg[k1]  or 0) + 1
        ep_deg[k2]  = (ep_deg[k2]  or 0) + 1
        ep_refs[k1] = ep_refs[k1] or {}; ep_refs[k1][#ep_refs[k1]+1] = {idx=i, side=1}
        ep_refs[k2] = ep_refs[k2] or {}; ep_refs[k2][#ep_refs[k2]+1] = {idx=i, side=2}
    end

    local used  = {}
    local paths = {}

    local function other(s, side) return side == 1 and s.p2 or s.p1 end

    -- Follow a degree-2 chain in one direction; returns the new tip point.
    local function follow(chain, tip_key, prepend)
        while true do
            if (ep_deg[tip_key] or 0) ~= 2 then break end
            local found = false
            for _, ref in ipairs(ep_refs[tip_key] or {}) do
                if not used[ref.idx] then
                    used[ref.idx] = true
                    local ns   = segs[ref.idx]
                    local next = other(ns, ref.side)
                    if prepend then
                        table.insert(chain, 1, next)
                    else
                        chain[#chain+1] = next
                    end
                    tip_key = ptkey(next)
                    found   = true
                    break
                end
            end
            if not found then break end
        end
        return tip_key
    end

    -- Extend a chain endpoint by tps/2 if the tile immediately beyond it is a road type.
    -- pa = endpoint, pb = next-interior point (gives the direction away from the chain).
    -- Tile coordinates: endpoint pixel divided by tps gives the zone-boundary index.
    local function tryExtend(chain, ia, ib)
        if not grid then return end
        local pa, pb = chain[ia], chain[ib]
        local dxs = pa.x - pb.x
        local dys = pa.y - pb.y
        if dxs == 0 and dys == 0 then return end
        local sx = dxs > 0 and 1 or (dxs < 0 and -1 or 0)
        local sy = dys > 0 and 1 or (dys < 0 and -1 or 0)
        local rx  = math.floor(pa.x / tps + 0.001)
        local ry  = math.floor(pa.y / tps + 0.001)
        -- Two tiles to check (one boundary straddles two tile positions)
        local rows, cols
        if sx ~= 0 then   -- horizontal extension
            cols = {rx + (sx > 0 and 1 or 0), rx + (sx > 0 and 1 or 0)}
            rows = {ry, ry + 1}
        else              -- vertical extension
            rows = {ry + (sy > 0 and 1 or 0), ry + (sy > 0 and 1 or 0)}
            cols = {rx, rx + 1}
        end
        for k = 1, 2 do
            local r = grid[rows[k]]
            local t = r and r[cols[k]] and r[cols[k]].type
            if ROAD_TYPES[t] then
                chain[ia] = {x = pa.x + sx * tps * 0.5, y = pa.y + sy * tps * 0.5}
                return
            end
        end
    end

    for i = 1, #segs do
        if not used[i] then
            used[i] = true
            local s     = segs[i]
            local chain = {s.p1, s.p2}
            follow(chain, ptkey(s.p2), false)
            follow(chain, ptkey(chain[1]), true)

            -- Extend endpoints toward adjacent arterial/highway tiles
            if #chain >= 2 then
                tryExtend(chain, 1, 2)
                tryExtend(chain, #chain, #chain - 1)
            end

            local first, last = chain[1], chain[#chain]
            local closed = (first.x == last.x and first.y == last.y)
            local pts = {}
            for _, p in ipairs(chain) do
                pts[#pts+1] = p.x
                pts[#pts+1] = p.y
            end
            -- Only smooth chains that have an actual corner (3+ distinct points).
            if not closed and #pts >= 6 then
                pts = chaikin(pts, 3)
            end
            if #pts >= 4 then paths[#paths+1] = pts end
        end
    end

    return paths
end

-- Same as buildStreetPaths but pre-merges consecutive zone-row/col segments into
-- longer runs before chaining.  T-junction points land in the interior of merged
-- segments so Chaikin can deviate from them, but long straight stretches look cleaner.
function RoadSmoother.buildStreetPathsMerged(zone_seg_v, zone_seg_h, zone_grid, tps, grid)
    local zg   = zone_grid
    local segs = {}

    local v_cols = {}
    for gy, row in pairs(zone_seg_v or {}) do
        for rx in pairs(row) do
            local z1 = zg and zg[gy] and zg[gy][rx]
            local z2 = zg and zg[gy] and zg[gy][rx+1]
            if z1 and z1 ~= "none" and z2 and z2 ~= "none" and z1 ~= z2 then
                if not v_cols[rx] then v_cols[rx] = {} end
                v_cols[rx][#v_cols[rx]+1] = gy
            end
        end
    end
    for rx, gys in pairs(v_cols) do
        table.sort(gys)
        local rs, re = gys[1], gys[1]
        local cx = rx * tps
        for i = 2, #gys do
            if gys[i] == re + 1 then re = gys[i]
            else
                segs[#segs+1] = {p1={x=cx,y=(rs-1)*tps}, p2={x=cx,y=re*tps}}
                rs, re = gys[i], gys[i]
            end
        end
        segs[#segs+1] = {p1={x=cx,y=(rs-1)*tps}, p2={x=cx,y=re*tps}}
    end

    local h_rows = {}
    for ry, row in pairs(zone_seg_h or {}) do
        for gx in pairs(row) do
            local z1 = zg and zg[ry] and zg[ry][gx]
            local z2 = zg and zg[ry+1] and zg[ry+1][gx]
            if z1 and z1 ~= "none" and z2 and z2 ~= "none" and z1 ~= z2 then
                if not h_rows[ry] then h_rows[ry] = {} end
                h_rows[ry][#h_rows[ry]+1] = gx
            end
        end
    end
    for ry, gxs in pairs(h_rows) do
        table.sort(gxs)
        local rs, re = gxs[1], gxs[1]
        local cy = ry * tps
        for i = 2, #gxs do
            if gxs[i] == re + 1 then re = gxs[i]
            else
                segs[#segs+1] = {p1={x=(rs-1)*tps,y=cy}, p2={x=re*tps,y=cy}}
                rs, re = gxs[i], gxs[i]
            end
        end
        segs[#segs+1] = {p1={x=(rs-1)*tps,y=cy}, p2={x=re*tps,y=cy}}
    end

    local function ptkey(p) return p.x * 100003 + p.y end
    local ep_deg  = {}
    local ep_refs = {}
    for i, s in ipairs(segs) do
        local k1, k2 = ptkey(s.p1), ptkey(s.p2)
        ep_deg[k1]  = (ep_deg[k1]  or 0) + 1
        ep_deg[k2]  = (ep_deg[k2]  or 0) + 1
        ep_refs[k1] = ep_refs[k1] or {}; ep_refs[k1][#ep_refs[k1]+1] = {idx=i, side=1}
        ep_refs[k2] = ep_refs[k2] or {}; ep_refs[k2][#ep_refs[k2]+1] = {idx=i, side=2}
    end

    local used  = {}
    local paths = {}
    local function other(s, side) return side == 1 and s.p2 or s.p1 end
    local function follow(chain, tip_key, prepend)
        while true do
            if (ep_deg[tip_key] or 0) ~= 2 then break end
            local found = false
            for _, ref in ipairs(ep_refs[tip_key] or {}) do
                if not used[ref.idx] then
                    used[ref.idx] = true
                    local ns   = segs[ref.idx]
                    local next = other(ns, ref.side)
                    if prepend then table.insert(chain, 1, next)
                    else chain[#chain+1] = next end
                    tip_key = ptkey(next); found = true; break
                end
            end
            if not found then break end
        end
        return tip_key
    end

    local function tryExtend(chain, ia, ib)
        if not grid then return end
        local pa, pb = chain[ia], chain[ib]
        local dxs = pa.x - pb.x; local dys = pa.y - pb.y
        if dxs == 0 and dys == 0 then return end
        local sx = dxs > 0 and 1 or (dxs < 0 and -1 or 0)
        local sy = dys > 0 and 1 or (dys < 0 and -1 or 0)
        local rx  = math.floor(pa.x / tps + 0.001)
        local ry  = math.floor(pa.y / tps + 0.001)
        local rows, cols
        if sx ~= 0 then
            cols = {rx + (sx > 0 and 1 or 0), rx + (sx > 0 and 1 or 0)}; rows = {ry, ry + 1}
        else
            rows = {ry + (sy > 0 and 1 or 0), ry + (sy > 0 and 1 or 0)}; cols = {rx, rx + 1}
        end
        for k = 1, 2 do
            local r = grid[rows[k]]
            local t = r and r[cols[k]] and r[cols[k]].type
            if ROAD_TYPES[t] then
                chain[ia] = {x = pa.x + sx * tps * 0.5, y = pa.y + sy * tps * 0.5}; return
            end
        end
    end

    for i = 1, #segs do
        if not used[i] then
            used[i] = true
            local s     = segs[i]
            local chain = {s.p1, s.p2}
            follow(chain, ptkey(s.p2), false)
            follow(chain, ptkey(chain[1]), true)
            if #chain >= 2 then tryExtend(chain, 1, 2); tryExtend(chain, #chain, #chain-1) end
            local first, last = chain[1], chain[#chain]
            local closed = (first.x == last.x and first.y == last.y)
            local pts = {}
            for _, p in ipairs(chain) do pts[#pts+1] = p.x; pts[#pts+1] = p.y end
            if not closed and #pts >= 6 then pts = chaikin(pts, 3) end
            if #pts >= 4 then paths[#paths+1] = pts end
        end
    end
    return paths
end

-- Trace zone-boundary streets using the same junction-stop + mergeChains algorithm
-- as buildPaths (used for arterials/highways).  Uses an explicit edge set built from
-- zone_seg data so only actual zone-boundary connections are traversed.  Degree-2
-- corner nodes get stitched by mergeChains, and Chaikin smoothing rounds the 90°
-- turns into curves, producing a clean result similar to the arterial overlay.
function RoadSmoother.buildStreetPathsLike(zone_seg_v, zone_seg_h, zone_grid, tps, grid)
    local zg = zone_grid

    -- node key: unique integer per (rx,ry)
    local MAX_W = 4096
    local function nkey(rx, ry) return ry * MAX_W + rx end

    -- nodes[key] = {rx, ry}
    -- adj[key]   = list of {nk, dx, dy}  (dx,dy always ±1, 0 — axis-aligned unit steps)
    local nodes    = {}
    local adj      = {}
    local node_ord = {}  -- insertion-order list of keys

    local function ensure(rx, ry)
        local k = nkey(rx, ry)
        if not nodes[k] then
            nodes[k] = {rx=rx, ry=ry}
            adj[k]   = {}
            node_ord[#node_ord+1] = k
        end
        return k
    end

    local function add_edge(rx1, ry1, rx2, ry2)
        local k1 = ensure(rx1, ry1)
        local k2 = ensure(rx2, ry2)
        adj[k1][#adj[k1]+1] = {nk=k2, dx=rx2-rx1, dy=ry2-ry1}
        adj[k2][#adj[k2]+1] = {nk=k1, dx=rx1-rx2, dy=ry1-ry2}
    end

    local function tile_is_road(r, c)
        local t = grid and grid[r] and grid[r][c] and grid[r][c].type
        return t and ROAD_TYPES[t]
    end

    -- Iterate zone_seg directly so visual roads match the pathfinder road network exactly.
    -- zone_grid scanning caused cascading visual edges from makeVisible modifications
    -- that weren't in zone_seg and couldn't be used for pathfinding.
    if zone_seg_v then
        for gy, row in pairs(zone_seg_v) do
            for rx in pairs(row) do
                if not tile_is_road(gy, rx) and not tile_is_road(gy, rx + 1) then
                    add_edge(rx, gy - 1, rx, gy)
                end
            end
        end
        for ry, row in pairs(zone_seg_h or {}) do
            for gx in pairs(row) do
                if not tile_is_road(ry, gx) and not tile_is_road(ry + 1, gx) then
                    add_edge(gx - 1, ry, gx, ry)
                end
            end
        end
    elseif zg then
        local gh = #zg
        for gy = 1, gh do
            local zrow = zg[gy]
            if zrow then
                local gw = #zrow
                for rx = 1, gw - 1 do
                    local z1 = zrow[rx]; local z2 = zrow[rx + 1]
                    if z1 and z1 ~= "none" and z2 and z2 ~= "none" and z1 ~= z2
                       and not tile_is_road(gy, rx) and not tile_is_road(gy, rx + 1) then
                        add_edge(rx, gy - 1, rx, gy)
                    end
                end
            end
        end
        for ry = 1, gh - 1 do
            local zrow1 = zg[ry]; local zrow2 = zg[ry + 1]
            if zrow1 and zrow2 then
                local gw = #zrow1
                for gx = 1, gw do
                    local z1 = zrow1[gx]; local z2 = zrow2[gx]
                    if z1 and z1 ~= "none" and z2 and z2 ~= "none" and z1 ~= z2
                       and not tile_is_road(ry, gx) and not tile_is_road(ry + 1, gx) then
                        add_edge(gx - 1, ry, gx, ry)
                    end
                end
            end
        end
    else
        for gy, row in pairs(zone_seg_v or {}) do
            for rx in pairs(row) do add_edge(rx, gy - 1, rx, gy) end
        end
        for ry, row in pairs(zone_seg_h or {}) do
            for gx in pairs(row) do add_edge(gx - 1, ry, gx, ry) end
        end
    end
    if #node_ord == 0 then return {} end

    -- Degree from actual edges
    local deg = {}
    for _, k in ipairs(node_ord) do
        deg[k] = #adj[k]
    end

    local interior_used = {}

    local function walkSeg(sk, pdx, pdy)
        local sn = nodes[sk]
        local chain = {{x=sn.rx, y=sn.ry}}
        local ck = sk
        while true do
            local d  = deg[ck] or 0
            -- pick best forward neighbor along actual edges
            local best_nk, best_dx, best_dy, best_dot = nil, nil, nil, -0.7
            for _, e in ipairs(adj[ck]) do
                if not interior_used[e.nk] then
                    local dot = e.dx * pdx + e.dy * pdy  -- edges are unit steps
                    if dot > best_dot then
                        best_dot = dot
                        best_nk, best_dx, best_dy = e.nk, e.dx, e.dy
                    end
                end
            end
            if not best_nk then break end
            local nn = nodes[best_nk]
            chain[#chain+1] = {x=nn.rx, y=nn.ry}
            local nd = deg[best_nk] or 0
            if nd ~= 2 then break end
            if interior_used[best_nk] then break end
            interior_used[best_nk] = true
            pdx, pdy = best_dx, best_dy
            ck = best_nk
        end
        return chain
    end

    local raw = {}

    -- Walk from every terminal (d==1) and junction (d>=3)
    for _, sk in ipairs(node_ord) do
        local d = deg[sk] or 0
        if d ~= 2 then
            for _, e in ipairs(adj[sk]) do
                local nd = deg[e.nk] or 0
                local ok
                if nd == 2 then
                    ok = not interior_used[e.nk]
                else
                    ok = sk < e.nk   -- canonical: only walk each junction-junction edge once
                end
                if ok then
                    local c = walkSeg(sk, e.dx, e.dy)
                    if #c >= 2 then raw[#raw+1] = c end
                end
            end
        end
    end

    -- Mop up degree-2 loops
    for _, sk in ipairs(node_ord) do
        local d = deg[sk] or 0
        if d == 2 and not interior_used[sk] then
            for _, e in ipairs(adj[sk]) do
                if not interior_used[e.nk] then
                    local c = walkSeg(sk, e.dx, e.dy)
                    if #c >= 2 then raw[#raw+1] = c end
                    break
                end
            end
        end
    end

    -- Extend chain endpoints by 0.5 boundary units (= tps/2 pixels) when the tile
    -- immediately beyond them is a road type, so streets physically touch arterials.
    -- Chain coords are boundary-grid integers; road tiles straddle two boundary rows/cols.
    local function tryExtendB(chain, ia, ib)
        if not grid then return end
        local pa, pb = chain[ia], chain[ib]
        local dx = pa.x - pb.x
        local dy = pa.y - pb.y
        if dx == 0 and dy == 0 then return end
        local sx = dx > 0 and 1 or (dx < 0 and -1 or 0)
        local sy = dy > 0 and 1 or (dy < 0 and -1 or 0)
        local rx, ry = pa.x, pa.y   -- already boundary-grid integers
        local rows, cols
        if sx ~= 0 then
            cols = {rx + (sx > 0 and 1 or 0), rx + (sx > 0 and 1 or 0)}
            rows = {ry, ry + 1}
        else
            rows = {ry + (sy > 0 and 1 or 0), ry + (sy > 0 and 1 or 0)}
            cols = {rx, rx + 1}
        end
        for k = 1, 2 do
            local r = grid[rows[k]]
            local t = r and r[cols[k]] and r[cols[k]].type
            if ROAD_TYPES[t] then
                chain[ia] = {x = pa.x + sx * 0.5, y = pa.y + sy * 0.5}
                return
            end
        end
    end

    local merged  = mergeChains(raw)
    local paths   = {}
    local epsilon = tps * 0.5
    for _, chain in ipairs(merged) do
        if #chain >= 2 then
            tryExtendB(chain, 1, 2)
            tryExtendB(chain, #chain, #chain - 1)
            local pts = {}
            for _, c in ipairs(chain) do
                pts[#pts+1] = c.x * tps
                pts[#pts+1] = c.y * tps
            end
            pts = simplify(pts, epsilon)
            pts = chaikin(pts, 4)
            if #pts >= 4 then paths[#paths+1] = pts end
        end
    end
    return paths
end

-- ── public ───────────────────────────────────────────────────────────────────

-- Preferred path: use pre-stored ordered centerlines from world generation.
-- Each centerline is a list of {x,y} local sub-cell grid coords (1-indexed).
-- Merges degree-2 junctions before smoothing so pass-through corners get curved.
-- Returns list of Chaikin-smoothed flat pixel arrays ready for love.graphics.line.
function RoadSmoother.buildPathsFromCenterlines(centerlines, tps)
    local merged  = mergeChains(centerlines)
    local paths   = {}
    local epsilon = tps * 0.5
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

function RoadSmoother.buildPaths(grid, tps)
    if not grid or #grid == 0 then return {} end
    local gh = #grid
    local gw = #(grid[1] or {})
    if gw == 0 then return {} end

    local deg8 = buildDeg8(grid, gw, gh)

    -- interior_used: degree-2 pass-through tiles that have been walked.
    -- Junction/terminal tiles are never marked so multiple chains can share them as endpoints.
    local interior_used = {}

    -- Walk from (sx,sy) in direction (pdx,pdy), following road tiles until hitting a
    -- junction (degree≠2), terminal, or already-walked interior tile.
    local function walkSegment(sx, sy, pdx, pdy)
        local chain = {{x=sx, y=sy}}
        local cx, cy = sx + pdx, sy + pdy
        while cx >= 1 and cx <= gw and cy >= 1 and cy <= gh do
            local t = grid[cy] and grid[cy][cx] and grid[cy][cx].type
            if not ROAD_TYPES[t] then break end
            local key = cy*(gw+1)+cx
            local d   = (deg8[cy] and deg8[cy][cx]) or 0
            chain[#chain+1] = {x=cx, y=cy}
            if d ~= 2 then break end              -- stop at junction or terminal
            if interior_used[key] then break end  -- stop if already walked this stretch
            interior_used[key] = true
            -- Pick most-forward unvisited neighbour (8-connected, -0.7 threshold)
            local bx, by, bdx, bdy, bdot = nil, nil, nil, nil, -0.7
            for _, dir in ipairs(DIRS8) do
                local nx, ny = cx+dir[1], cy+dir[2]
                if nx>=1 and nx<=gw and ny>=1 and ny<=gh then
                    local nt = grid[ny] and grid[ny][nx] and grid[ny][nx].type
                    if ROAD_TYPES[nt] and not interior_used[ny*(gw+1)+nx] then
                        local dot = dir[1]*pdx + dir[2]*pdy
                        if dot > bdot then bdot=dot; bx,by,bdx,bdy=nx,ny,dir[1],dir[2] end
                    end
                end
            end
            if not bx then break end
            pdx, pdy = bdx, bdy; cx, cy = bx, by
        end
        return chain
    end

    local raw = {}

    -- From every terminal (d==1) and junction (d>=3): walk one segment per road direction.
    -- For adjacent junction pairs use canonical order (lower grid index first) to avoid
    -- producing the same 2-tile segment twice.
    for gy = 1, gh do
        for gx = 1, gw do
            local d = deg8[gy] and deg8[gy][gx]
            if d and d ~= 2 then
                for _, dir in ipairs(DIRS8) do
                    local nx, ny = gx+dir[1], gy+dir[2]
                    if nx>=1 and nx<=gw and ny>=1 and ny<=gh then
                        local nt = grid[ny] and grid[ny][nx] and grid[ny][nx].type
                        if ROAD_TYPES[nt] then
                            local nk = ny*(gw+1)+nx
                            local nd = (deg8[ny] and deg8[ny][nx]) or 0
                            local ok
                            if nd == 2 then
                                ok = not interior_used[nk]   -- unwalked interior stretch
                            else
                                ok = gy < ny or (gy == ny and gx < nx)  -- canonical for adjacent junctions
                            end
                            if ok then
                                local c = walkSegment(gx, gy, dir[1], dir[2])
                                if #c >= 2 then raw[#raw+1] = c end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Mop up degree-2 loops (roads with no terminals anywhere in the loop)
    for gy = 1, gh do
        for gx = 1, gw do
            local d = deg8[gy] and deg8[gy][gx]
            if d == 2 and not interior_used[gy*(gw+1)+gx] then
                for _, dir in ipairs(DIRS8) do
                    local nx, ny = gx+dir[1], gy+dir[2]
                    if nx>=1 and nx<=gw and ny>=1 and ny<=gh then
                        local nt = grid[ny] and grid[ny][nx] and grid[ny][nx].type
                        if ROAD_TYPES[nt] and not interior_used[ny*(gw+1)+nx] then
                            local c = walkSegment(gx, gy, dir[1], dir[2])
                            if #c >= 2 then raw[#raw+1] = c end
                            break
                        end
                    end
                end
            end
        end
    end

    -- Merge degree-2 junction nodes (false junctions from 8-connectivity, or
    -- genuine pass-throughs where only 2 segments meet).
    local merged  = mergeChains(raw)
    local paths   = {}
    local epsilon = tps * 0.5
    for _, chain in ipairs(merged) do
        if #chain >= 2 then
            local pts = {}
            for _, c in ipairs(chain) do
                pts[#pts+1] = (c.x-0.5)*tps
                pts[#pts+1] = (c.y-0.5)*tps
            end
            pts = simplify(pts, epsilon)
            pts = chaikin(pts, 4)
            if #pts >= 4 then paths[#paths+1] = pts end
        end
    end
    return paths
end

return RoadSmoother
