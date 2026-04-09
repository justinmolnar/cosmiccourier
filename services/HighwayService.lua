-- services/HighwayService.lua
-- Portable highway routing: given city locations, heightmap, biome data,
-- and world dimensions + params, returns a highway_map and highway_paths.
-- Zero love.* imports. Zero game references. Pure computation (A* on terrain).

local HighwayService = {}

-- Build the highway network connecting cities on the same continent.
-- Returns:
--   highway_map    [cell_idx] = true  (cells that carry a highway)
--   highway_paths  array of {x, y} world-cell chain tables (one per A* route)
--
-- city_locations   array of {x, y, s, ...}
-- heightmap        [y][x] = elevation value
-- biome_data       [cell_idx] = {is_river, is_lake, ...}  (may be nil)
-- continent_map    [cell_idx] = continent_id
-- w, h             world dimensions
-- params           .ocean_max, .coast_max, .plains_max, .forest_max,
--                  .highland_max, .mountain_max,
--                  .highway_mountain_cost, .highway_river_cost,
--                  .highway_slope_cost, .highway_budget_scale
function HighwayService.buildHighways(
    city_locations, heightmap, biome_data, continent_map, w, h, params
)
    local p        = params
    local cities   = city_locations
    local cont_map = continent_map
    local hmap     = heightmap
    local bdata    = biome_data
    local mtn_cost    = math.max(1, p.highway_mountain_cost or 10)
    local riv_cost    = math.max(0, p.highway_river_cost    or 3)
    local slope_cost  = math.max(0, p.highway_slope_cost    or 15)
    local budget_scale = math.max(1, p.highway_budget_scale or 800)

    local highway_map   = {}
    local highway_paths = {}   -- list of {x,y} world-cell chains, one per A* route built

    -- Terrain crossing cost for entering cell ni from a cell with elevation from_elev.
    -- Slope penalty makes roads naturally contour around terrain rather than going straight over.
    -- Existing highway cells are nearly free to encourage route sharing.
    local function cell_cost(ni, from_elev)
        local ny   = math.floor((ni-1)/w) + 1
        local nx   = (ni-1) % w + 1
        local elev = hmap[ny][nx]
        if elev <= p.ocean_max then return math.huge, elev end

        local base
        if     elev <= p.coast_max    then base = 1.0
        elseif elev <= p.plains_max   then base = 1.0
        elseif elev <= p.forest_max   then base = 1.4
        elseif elev <= p.highland_max then base = 1.0 + mtn_cost * 0.25
        elseif elev <= p.mountain_max then base = mtn_cost
        else                               base = mtn_cost * 1.5 end

        base = base + math.abs(elev - from_elev) * slope_cost

        local bd = bdata and bdata[ni]
        if bd and (bd.is_river or bd.is_lake) then base = base + riv_cost end
        if highway_map[ni] then base = base * 0.05 end  -- follow existing roads

        return base, elev
    end

    -- A* between two cell indices; returns list of cell indices or nil.
    local function astar(src, dst)
        if src == dst then return {src} end
        local dx_dst = (dst-1) % w
        local dy_dst = math.floor((dst-1) / w)
        local function heur(i)
            local dx = (i-1) % w - dx_dst
            local dy = math.floor((i-1) / w) - dy_dst
            return math.sqrt(dx*dx + dy*dy)
        end

        local g, came, closed, heap = {}, {}, {}, {}
        local function hpush(f, i)
            heap[#heap+1] = {f, i}
            local pos = #heap
            while pos > 1 do
                local par = math.floor(pos/2)
                if heap[par][1] > heap[pos][1] then
                    heap[par], heap[pos] = heap[pos], heap[par]; pos = par
                else break end
            end
        end
        local function hpop()
            local top = heap[1]; local n2 = #heap
            heap[1] = heap[n2]; heap[n2] = nil
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

        -- Store per-cell elevation so slope cost can be computed edge-by-edge
        local cell_elev = {}
        local src_ny = math.floor((src-1)/w) + 1
        local src_nx = (src-1) % w + 1
        cell_elev[src] = hmap[src_ny][src_nx]

        g[src] = 0
        hpush(heur(src), src)
        local dirs = {-1, 1, -w, w}

        while #heap > 0 do
            local node = hpop()
            local ci   = node[2]
            if not closed[ci] then
                if ci == dst then
                    local path, cur = {}, dst
                    while cur do path[#path+1] = cur; cur = came[cur] end
                    return path, g[dst]
                end
                closed[ci] = true
                local cx       = (ci-1) % w
                local cy       = math.floor((ci-1) / w)
                local from_e   = cell_elev[ci] or 0
                for _, d in ipairs(dirs) do
                    local ni = ci + d
                    if ni >= 1 and ni <= w*h and not closed[ni] then
                        local nx2 = (ni-1) % w
                        local ny2 = math.floor((ni-1) / w)
                        local valid = (d==-1 and nx2==cx-1) or (d==1 and nx2==cx+1) or
                                      (d==-w and ny2==cy-1) or (d==w  and ny2==cy+1)
                        if valid then
                            local cost, to_e = cell_cost(ni, from_e)
                            if cost < math.huge then
                                local ng = g[ci] + cost
                                if not g[ni] or ng < g[ni] then
                                    g[ni] = ng; came[ni] = ci
                                    cell_elev[ni] = to_e
                                    hpush(ng + heur(ni), ni)
                                end
                            end
                        end
                    end
                end
            end
        end
        return nil
    end

    -- Group cities by continent id
    local cont_cities = {}
    for _, city in ipairs(cities) do
        local cid = cont_map[(city.y-1)*w + city.x] or 0
        if cid > 0 then
            if not cont_cities[cid] then cont_cities[cid] = {} end
            cont_cities[cid][#cont_cities[cid]+1] = city
        end
    end

    -- Per-continent: gravity model + budget constraints.
    -- City size = suitability². Budget = size * budget_scale.
    -- Pairs are sorted by gravity (size_a * size_b / dist²) — large nearby cities
    -- connect first. A road is built when combined budget ≥ A* terrain cost;
    -- each city pays proportional to its budget share.
    for _, cits in pairs(cont_cities) do
        local n = #cits
        if n >= 2 then
            local budget = {}
            for a = 1, n do
                budget[a] = (cits[a].s or 0.5) ^ 2 * budget_scale
            end

            -- All pairs sorted by gravity (descending)
            local pairs_list = {}
            for a = 1, n do
                for b = a+1, n do
                    local dx = cits[a].x - cits[b].x
                    local dy = cits[a].y - cits[b].y
                    local dist_sq = math.max(1, dx*dx + dy*dy)
                    local gravity = (cits[a].s or 0.5) * (cits[b].s or 0.5) / dist_sq
                    pairs_list[#pairs_list+1] = {a, b, gravity}
                end
            end
            table.sort(pairs_list, function(u, v) return u[3] > v[3] end)

            for _, pair in ipairs(pairs_list) do
                local ai, bi    = pair[1], pair[2]
                local combined  = budget[ai] + budget[bi]
                if combined > 0 then
                    local a   = cits[ai]
                    local b   = cits[bi]
                    local src = (a.y-1)*w + a.x
                    local dst = (b.y-1)*w + b.x
                    local path, path_cost = astar(src, dst)
                    if path and path_cost and path_cost <= combined then
                        local chain = {}
                        for _, ci in ipairs(path) do
                            highway_map[ci] = true
                            chain[#chain+1] = {x = (ci-1) % w + 1, y = math.floor((ci-1) / w) + 1}
                        end
                        highway_paths[#highway_paths+1] = chain
                        local fa = budget[ai] / combined
                        budget[ai] = math.max(0, budget[ai] - path_cost * fa)
                        budget[bi] = math.max(0, budget[bi] - path_cost * (1 - fa))
                    end
                end
            end
        end
    end

    return highway_map, highway_paths
end

return HighwayService
