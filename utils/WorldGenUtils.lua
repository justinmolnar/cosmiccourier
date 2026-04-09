-- utils/WorldGenUtils.lua
-- Pure, portable world-generation helpers.
-- Zero dependencies: no require, no love.*, no game references.
-- Receive noise_fn as a parameter where noise is needed.

local WorldGenUtils = {}

-- ── Bilinear interpolation ────────────────────────────────────────────────────

-- Bilinear interpolation of a 2-D array map[y][x] at fractional position (fy, fx).
function WorldGenUtils.bilinear2d(map, fy, fx, W, H)
    local x0 = math.max(1, math.floor(fx))
    local y0 = math.max(1, math.floor(fy))
    local x1 = math.min(W, x0 + 1)
    local y1 = math.min(H, y0 + 1)
    local tx = fx - x0
    local ty = fy - y0
    local v00 = map[y0][x0] or 0
    local v10 = map[y0][x1] or 0
    local v01 = map[y1][x0] or 0
    local v11 = map[y1][x1] or 0
    return (v00*(1-tx) + v10*tx) * (1-ty)
         + (v01*(1-tx) + v11*tx) * ty
end

-- ── Sub-cell elevation ────────────────────────────────────────────────────────
-- Each world cell is subdivided 3x3 into sub-cells (gscx, gscy are global
-- sub-cell coordinates). Two noise octaves add organic texture without
-- changing the parent cell's biome family.
--
-- noise_fn must match the signature of love.math.noise:
--   noise_fn(x, y) → number in [0, 1]
--
-- Constants are kept here (not in the caller) so all services share the same
-- sub-cell character; changing them here changes them everywhere consistently.

local SC_DETAIL_FREQ = 0.55   -- high-freq: varies every ~2 sub-cells
local SC_DETAIL_AMP  = 0.08   -- ±0.08 elevation delta from fine noise
local SC_MEDIUM_FREQ = 0.18   -- mid-freq: city-scale undulation
local SC_MEDIUM_AMP  = 0.04   -- ±0.04 from medium noise

function WorldGenUtils.subcell_elev_at(gscx, gscy, hmap, noise_fn)
    local wx   = math.floor(gscx / 3)
    local wy   = math.floor(gscy / 3)
    local base = hmap[wy + 1][wx + 1]
    local d = (noise_fn(gscx * SC_DETAIL_FREQ + 100.3, gscy * SC_DETAIL_FREQ + 73.1) - 0.5) * SC_DETAIL_AMP * 2
    local m = (noise_fn(gscx * SC_MEDIUM_FREQ + 200.7, gscy * SC_MEDIUM_FREQ + 31.9) - 0.5) * SC_MEDIUM_AMP * 2
    return base + d + m
end

-- ── Min-heap helpers ──────────────────────────────────────────────────────────
-- heap entries are {priority, value}; lower priority = higher urgency.
-- heap is a plain Lua table passed in by the caller (no internal state).

function WorldGenUtils.hpush(heap, f, i)
    heap[#heap+1] = {f, i}
    local pos = #heap
    while pos > 1 do
        local par = math.floor(pos / 2)
        if heap[par][1] > heap[pos][1] then
            heap[par], heap[pos] = heap[pos], heap[par]; pos = par
        else break end
    end
end

function WorldGenUtils.hpop(heap)
    local top = heap[1]; local n = #heap
    heap[1] = heap[n]; heap[n] = nil
    local pos = 1
    while true do
        local l, r, s = pos*2, pos*2+1, pos
        if l <= #heap and heap[l][1] < heap[s][1] then s = l end
        if r <= #heap and heap[r][1] < heap[s][1] then s = r end
        if s == pos then break end
        heap[pos], heap[s] = heap[s], heap[pos]; pos = s
    end
    return top
end

return WorldGenUtils
