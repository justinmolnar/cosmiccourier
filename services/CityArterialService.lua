-- services/CityArterialService.lua
-- Portable arterial road generation: direction-aware 8-directional Dijkstra
-- connecting city POIs into a road network anchored on the highway grid.
-- Zero love.* imports. Zero game references. Pure computation.

local WorldGenUtils = require("utils.WorldGenUtils")

local CityArterialService = {}

-- Routing constants (tuned for organic, readable arterial networks)
local ART_TURN_45   = 1    -- near-free: allows smooth curves
local ART_TURN_90   = 10   -- moderate heading change
local ART_TURN_135  = 28   -- heavy
local ART_TURN_180  = 65   -- brutal U-turn
local ART_ON_ROAD   = 0.05 -- cost multiplier on existing arterial sub-cell
local ART_ON_HWY    = 0.65 -- cost multiplier inside a highway world-cell
local ART_NOISE_AMP = 2.2  -- additive noise amplitude (forces organic deviation)
local ART_SLOPE_W   = 28.0 -- sub-cell slope penalty weight

-- Generate arterial roads for a single city.
-- Returns art_map ({[sub_cell_idx] = true}).
local function genArterialsForCity(city_idx, bounds, pois,
                                    highway_map, heightmap, biome_data,
                                    w, h, params, math_fns)
    if not bounds or not pois or #pois == 0 then return {} end

    local sw   = w * 3
    local sh   = h * 3
    local hmap = heightmap
    local bdata = biome_data
    local hways = highway_map or {}
    local p    = params
    local noise = math_fns.noise

    local function sci_of(gscx, gscy) return gscy * sw + gscx + 1 end

    local function in_city(gscx, gscy)
        if gscx < 0 or gscx >= sw or gscy < 0 or gscy >= sh then return false end
        local wx = math.floor(gscx / 3)
        local wy = math.floor(gscy / 3)
        return bounds[wy * w + wx + 1] == true
    end

    local art_map = {}   -- mutated as routes are laid; discounts later routes onto it

    -- Edge cost from (from_x,from_y) → (to_x,to_y).
    -- Includes terrain type, sub-cell slope, river/lake, existing-road discount,
    -- and noise for organic routing.  Diagonal steps scaled by √2.
    -- no_road_discount=true suppresses the ART_ON_ROAD multiplier (used by ring pass
    -- so that ring connections forge new paths instead of retracing Phase-2 spokes).
    local function edge_cost(fx, fy, tx, ty, is_diag, no_road_discount)
        local wx   = math.floor(tx / 3)
        local wy   = math.floor(ty / 3)
        local wci  = wy * w + wx + 1
        local elev = (hmap[wy+1] and hmap[wy+1][wx+1]) or 0.5
        if elev <= (p.ocean_max or 0.42) then return math.huge end

        local base
        if     elev <= (p.coast_max    or 0.47) then base = 1.2
        elseif elev <= (p.plains_max   or 0.60) then base = 1.0
        elseif elev <= (p.forest_max   or 0.70) then base = 1.6
        elseif elev <= (p.highland_max or 0.80) then base = 4.0
        else                                         base = 10.0 end

        -- Sub-cell slope: forces routing around terrain at fine scale
        local from_e = WorldGenUtils.subcell_elev_at(fx, fy, hmap, noise)
        local to_e   = WorldGenUtils.subcell_elev_at(tx, ty, hmap, noise)
        base = base + math.abs(to_e - from_e) * ART_SLOPE_W

        local bd = bdata and bdata[wci]
        if bd and (bd.is_river or bd.is_lake) then base = base + 5.0 end
        if hways[wci]                          then base = base * ART_ON_HWY  end
        local dest_sci = sci_of(tx, ty)
        if not no_road_discount and art_map[dest_sci] then
            base = base * ART_ON_ROAD
        elseif not art_map[dest_sci] then
            -- Penalise running alongside an existing road (prevents 2-wide parallel bands).
            -- Merging onto a road (ART_ON_ROAD) is still far cheaper than running beside one.
            if art_map[dest_sci+1] or art_map[dest_sci-1] or
               art_map[dest_sci+sw] or art_map[dest_sci-sw] then
                base = base * 4.0
            end
        end

        base = base + noise(tx * 0.22 + 50.3, ty * 0.22 + 27.9) * ART_NOISE_AMP
        if is_diag then base = base * 1.414 end
        return base
    end

    -- 8 directions: {sci_Δ, gscx_Δ, gscy_Δ, dir_idx, is_diagonal}
    local DIRS = {
        { 1,      1,  0, 0, false},   -- E
        { sw+1,   1,  1, 1, true },   -- SE
        { sw,     0,  1, 2, false},   -- S
        { sw-1,  -1,  1, 3, true },   -- SW
        {-1,     -1,  0, 4, false},   -- W
        {-sw-1,  -1, -1, 5, true },   -- NW
        {-sw,     0, -1, 6, false},   -- N
        {-sw+1,   1, -1, 7, true },   -- NE
    }

    local function turn_cost(fd, td)
        local d = math.abs(fd - td)
        if d > 4 then d = 8 - d end
        if     d == 0 then return 0
        elseif d == 1 then return ART_TURN_45
        elseif d == 2 then return ART_TURN_90
        elseif d == 3 then return ART_TURN_135
        else               return ART_TURN_180 end
    end

    -- Direction-aware Dijkstra from src_sci to any cell in target_net.
    -- State = sci*8+dir.  Seeds all 8 dirs at src (no first-step turn penalty).
    -- no_road_discount=true → ring pass: suppresses road discount so ring connections
    -- forge new paths rather than retracing Phase-2 spokes.
    -- Returns {sci, …} from junction→src, or nil.
    local function route_to_net(src_sci, target_net, no_road_discount)
        local g    = {}
        local came = {}   -- false=seed root, number=parent state
        local heap = {}

        local function hpush(f, st)
            heap[#heap+1] = {f, st}
            local pos = #heap
            while pos > 1 do
                local par = math.floor(pos/2)
                if heap[par][1] > heap[pos][1] then
                    heap[par], heap[pos] = heap[pos], heap[par]; pos = par
                else break end
            end
        end
        local function hpop()
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

        for d = 0, 7 do
            local st = src_sci * 8 + d
            g[st]    = 0
            came[st] = false
            hpush(0, st)
        end

        local closed = {}
        while #heap > 0 do
            local node = hpop()
            local st   = node[2]
            if not closed[st] then
                closed[st]    = true
                local sci     = math.floor(st / 8)
                local cur_dir = st % 8
                local gscx    = (sci - 1) % sw
                local gscy    = math.floor((sci - 1) / sw)

                if target_net[sci] then
                    local path, cur = {}, st
                    repeat
                        path[#path+1] = math.floor(cur / 8)
                        cur = came[cur]
                    until not cur
                    return path
                end

                for _, dir in ipairs(DIRS) do
                    local nx = gscx + dir[2]
                    local ny = gscy + dir[3]
                    local ni = sci  + dir[1]
                    local nd = dir[4]
                    if nx >= 0 and nx < sw and ny >= 0 and ny < sh
                            and (in_city(nx, ny) or target_net[ni]) then
                        local tc = turn_cost(cur_dir, nd)
                        local bc = edge_cost(gscx, gscy, nx, ny, dir[5], no_road_discount)
                        if bc < math.huge then
                            local new_st = ni * 8 + nd
                            local ng     = (g[st] or 0) + bc + tc
                            if not g[new_st] or ng < g[new_st] then
                                g[new_st]    = ng
                                came[new_st] = st
                                hpush(ng, new_st)
                            end
                        end
                    end
                end
            end
        end
        return nil
    end

    local function lay_path(path, road_net)
        if not path then return end
        for _, sci in ipairs(path) do
            art_map[sci]  = true
            road_net[sci] = true
        end
    end

    -- ── Phase 1: rasterise world highway onto sub-cell grid ─────────────────
    local road_net = {}

    -- Pass 1a: stamp center sub-cell of every in-bounds highway cell.
    -- Pass 1b: bridge toward ANY adjacent highway cell (in- or out-of-bounds)
    --   s=1 always stays inside the current world cell, so it is always rendered.
    --   s=2 may cross into a neighbouring cell; it is stamped anyway and clipped
    --   by the renderer if that cell is outside bounds.
    for ci in pairs(bounds) do
        if hways[ci] then
            local wx  = (ci-1) % w
            local wy  = math.floor((ci-1) / w)
            local cx  = wx * 3 + 1
            local cy  = wy * 3 + 1
            art_map[sci_of(cx, cy)]  = true
            road_net[sci_of(cx, cy)] = true
            for _, m in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do
                local nwx = wx + m[1]; local nwy = wy + m[2]
                if nwx >= 0 and nwx < w and nwy >= 0 and nwy < h then
                    local nci = nwy * w + nwx + 1
                    if hways[nci] then   -- bridge regardless of bounds
                        for s = 1, 2 do
                            local lsci = sci_of(cx + m[1]*s, cy + m[2]*s)
                            art_map[lsci]  = true
                            road_net[lsci] = true
                        end
                    end
                end
            end
        end
    end

    -- Pass 1c: highway passes adjacent to (but not through) city bounds.
    -- Stamp the facing edge sub-cell of the bounds cell as a highway entry.
    if not next(road_net) then
        for ci in pairs(bounds) do
            local wx = (ci-1) % w
            local wy = math.floor((ci-1) / w)
            for _, m in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do
                local nwx = wx + m[1]; local nwy = wy + m[2]
                if nwx >= 0 and nwx < w and nwy >= 0 and nwy < h then
                    local nci = nwy * w + nwx + 1
                    if hways[nci] then
                        local cx = wx * 3 + 1; local cy = wy * 3 + 1
                        -- center sub-cell + edge facing the highway
                        art_map[sci_of(cx, cy)]           = true
                        road_net[sci_of(cx, cy)]          = true
                        art_map[sci_of(cx+m[1], cy+m[2])] = true
                        road_net[sci_of(cx+m[1], cy+m[2])]= true
                    end
                end
            end
        end
    end

    -- Final fallback: seed from downtown if no highway is near this city at all
    if not next(road_net) then
        local dt   = pois[1]
        local dsci = sci_of((dt.x-1)*3+1, (dt.y-1)*3+1)
        art_map[dsci]  = true
        road_net[dsci] = true
    end

    -- ── Phase 2: spanning tree – each POI to nearest road (nearest-first) ───
    -- Approximate distance: from POI sub-cell to highway centroid in sub-cell space
    local hcx, hcy, hn = 0, 0, 0
    for sci in pairs(road_net) do
        hcx = hcx + (sci-1) % sw
        hcy = hcy + math.floor((sci-1) / sw)
        hn  = hn  + 1
    end
    hcx = hn > 0 and hcx/hn or sw/2
    hcy = hn > 0 and hcy/hn or sh/2

    local poi_scis = {}
    local poi_order = {}
    for _, poi in ipairs(pois) do
        local pgx = (poi.x-1)*3+1
        local pgy = (poi.y-1)*3+1
        local ps  = sci_of(pgx, pgy)
        poi_scis[#poi_scis+1] = ps
        local d = math.sqrt((pgx-hcx)^2 + (pgy-hcy)^2)
        poi_order[#poi_order+1] = {sci=ps, d=d, gscx=pgx, gscy=pgy}
    end
    table.sort(poi_order, function(a, b) return a.d < b.d end)

    for _, po in ipairs(poi_order) do
        if not road_net[po.sci] then
            lay_path(route_to_net(po.sci, road_net), road_net)
        end
    end

    -- ── Phase 3: close the loop – angle-sort POIs, ring-route consecutive ───
    local cen_x, cen_y = 0, 0
    for _, ps in ipairs(poi_scis) do
        cen_x = cen_x + (ps-1) % sw
        cen_y = cen_y + math.floor((ps-1) / sw)
    end
    cen_x = cen_x / #poi_scis
    cen_y = cen_y / #poi_scis

    local ring = {}
    for _, ps in ipairs(poi_scis) do
        local rx = (ps-1) % sw - cen_x
        local ry = math.floor((ps-1) / sw) - cen_y
        ring[#ring+1] = {sci=ps, angle=math.atan2(ry, rx)}
    end
    table.sort(ring, function(a, b) return a.angle < b.angle end)

    -- Ring pass: no road discount so each segment finds a genuinely new path
    -- instead of retracing the Phase-2 spokes.  Fall back to road-discount
    -- routing only if the no-discount Dijkstra can't reach the target.
    for i = 1, #ring do
        local a_sci = ring[i].sci
        local b_sci = ring[i % #ring + 1].sci
        local path = route_to_net(a_sci, {[b_sci]=true}, true)
        if not path then
            path = route_to_net(a_sci, {[b_sci]=true}, false)
        end
        lay_path(path, road_net)
    end

    -- ── Phase 4: dead-end cleanup ────────────────────────────────────────────
    -- If a POI sub-cell still has ≤1 road neighbour after the ring pass it is a
    -- visual dead-end (road enters but doesn't exit, e.g. a coastal peninsula).
    -- Force a new connection to the nearest other POI using no-road-discount so
    -- the path runs through different (adjacent) sub-cells in the same corridor,
    -- giving the POI a second visible exit.
    local function road_degree(sci)
        local n = 0
        for _, dir in ipairs(DIRS) do
            if art_map[sci + dir[1]] then n = n + 1 end
        end
        return n
    end

    for _, a_sci in ipairs(poi_scis) do
        if road_degree(a_sci) <= 1 then
            local ax = (a_sci-1) % sw
            local ay = math.floor((a_sci-1) / sw)
            -- Find nearest other POI by Manhattan distance in sub-cell space
            local best_d, best_sci = math.huge, nil
            for _, b_sci in ipairs(poi_scis) do
                if b_sci ~= a_sci then
                    local bx = (b_sci-1) % sw; local by = math.floor((b_sci-1) / sw)
                    local d = math.abs(ax-bx) + math.abs(ay-by)
                    if d < best_d then best_d = d; best_sci = b_sci end
                end
            end
            if best_sci then
                local path = route_to_net(a_sci, {[best_sci]=true}, true)
                if not path then
                    path = route_to_net(a_sci, {[best_sci]=true}, false)
                end
                lay_path(path, road_net)
            end
        end
    end

    return art_map
end

-- Generate arterial maps for all cities.
-- Returns: city_arterial_maps ([city_idx] = art_map)
function CityArterialService.genAllArterials(
    city_locations, city_bounds_list, city_pois_list,
    highway_map, heightmap, biome_data, w, h, params, math_fns
)
    local maps = {}
    for idx = 1, #(city_locations or {}) do
        local bounds = city_bounds_list and city_bounds_list[idx]
        local pois   = city_pois_list   and city_pois_list[idx]
        maps[idx] = genArterialsForCity(
            idx, bounds, pois, highway_map, heightmap, biome_data, w, h, params, math_fns
        )
    end
    return maps
end

return CityArterialService
