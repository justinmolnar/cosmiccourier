-- lib/path_utils.lua
-- Shared path/curve algorithms. Single source of truth — no copies elsewhere.
--
-- All functions operate on flat arrays: { x1, y1, x2, y2, ... }

local PathUtils = {}

-- Ramer-Douglas-Peucker point-to-segment distance helper (internal).
local function ptSegDist(px,py,ax,ay,bx,by)
    local dx,dy = bx-ax, by-ay
    local len2 = dx*dx+dy*dy
    if len2 == 0 then local ex,ey=px-ax,py-ay; return math.sqrt(ex*ex+ey*ey) end
    local t = math.max(0, math.min(1, ((px-ax)*dx+(py-ay)*dy)/len2))
    local ex,ey = px-(ax+t*dx), py-(ay+t*dy)
    return math.sqrt(ex*ex+ey*ey)
end

-- Ramer-Douglas-Peucker recursive core (internal).
local function rdp_recurse(pts, lo, hi, eps, keep)
    if hi <= lo+1 then return end
    local ax,ay = pts[lo*2-1], pts[lo*2]
    local bx,by = pts[hi*2-1], pts[hi*2]
    local maxD, maxI = 0, lo
    for i = lo+1, hi-1 do
        local d = ptSegDist(pts[i*2-1], pts[i*2], ax,ay,bx,by)
        if d > maxD then maxD,maxI = d,i end
    end
    if maxD > eps then
        keep[maxI] = true
        rdp_recurse(pts, lo,   maxI, eps, keep)
        rdp_recurse(pts, maxI, hi,   eps, keep)
    end
end

-- Simplify a flat point array using Ramer-Douglas-Peucker.
-- eps: max deviation in pixels before a point is kept (typical: 1.0–3.0).
function PathUtils.simplify(pts, eps)
    local n = #pts/2
    if n <= 2 then return pts end
    local keep = {[1]=true, [n]=true}
    rdp_recurse(pts, 1, n, eps, keep)
    local out = {}
    for i = 1, n do
        if keep[i] then out[#out+1]=pts[i*2-1]; out[#out+1]=pts[i*2] end
    end
    return out
end

-- Endpoint-preserving Chaikin curve smoothing.
-- iters: smoothing passes (typical: 3–5; more = rounder, loses sharpness).
-- Preserving endpoints prevents drift at junctions.
function PathUtils.chaikin(pts, iters)
    for _ = 1, iters do
        local n = #pts/2
        if n < 2 then return pts end
        local out = {pts[1], pts[2]}
        for i = 1, n-1 do
            local x1,y1 = pts[i*2-1], pts[i*2]
            local x2,y2 = pts[i*2+1], pts[i*2+2]
            out[#out+1] = 0.75*x1+0.25*x2;  out[#out+1] = 0.75*y1+0.25*y2
            out[#out+1] = 0.25*x1+0.75*x2;  out[#out+1] = 0.25*y1+0.75*y2
        end
        out[#out+1] = pts[#pts-1];  out[#out+1] = pts[#pts]
        pts = out
    end
    return pts
end

return PathUtils
