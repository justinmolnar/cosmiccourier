-- services/CityBoundsService.lua
-- Portable city bounds + POI placement: given city locations, heightmap,
-- region/biome data, and params, returns bounds, POIs, border, and fringe for
-- every city. Zero love.* imports. Zero game references. Pure computation.

local CityBoundsService = {}

-- Generate bounds and POIs for a single city.
-- Noise-perturbed Dijkstra flood-fill from the city seed cell outward through
-- region cells; two-phase inner erosion for POI placement safety.
-- Mutates city.x/y to the discovered downtown centroid.
-- Returns: claimed ({[cell_idx]=true}), pois (array of {x,y,type,...})
local function genBoundsForCity(city, region_map, heightmap, biome_data,
                                 suitability_scores, w, h, params, math_fns)
    if not region_map or not heightmap then return nil, nil end
    local p       = params
    local hmap    = heightmap
    local bdata   = biome_data
    local scores  = suitability_scores
    local noise   = math_fns.noise
    local rid     = region_map[(city.y-1)*w + city.x] or 0
    if rid == 0 then return nil, nil end

    local region_size = 0
    for i = 1, w*h do
        if region_map[i] == rid then region_size = region_size + 1 end
    end

    local size_frac    = p.city_size_fraction or 0.07
    local target_cells = math.max(4, math.floor(region_size * size_frac * (city.s or 0.5)))
    target_cells       = math.min(target_cells, region_size)

    -- Noise-perturbed terrain cost for organic blobs.
    -- dcost = diagonal multiplier (1.0 for cardinal, 1.414 for diagonal).
    local function claim_cost(nx2, ny2, dcost)
        local elev = hmap[ny2 + 1][nx2 + 1]
        if elev <= p.ocean_max then return math.huge end
        local base
        if     elev <= p.coast_max    then base = 1.5
        elseif elev <= p.plains_max   then base = 1.0
        elseif elev <= p.forest_max   then base = 2.0
        elseif elev <= p.highland_max then base = 5.0
        elseif elev <= p.mountain_max then base = 15.0
        else                               base = 30.0 end
        local ni = ny2 * w + nx2 + 1
        local bd = bdata and bdata[ni]
        if bd and (bd.is_river or bd.is_lake) then base = base + 3.0 end
        -- Noise perturbation so flat terrain doesn't produce perfect circles/diamonds
        local nv = noise(nx2 * 0.4 + city.x * 0.13, ny2 * 0.4 + city.y * 0.17)
        base = base * (0.55 + nv * 0.9)
        return base * dcost
    end

    local heap = {}
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

    -- 8-directional movement: cardinal (cost×1) + diagonal (cost×√2)
    local moves = {
        { 1, 0, 1.0}, {-1, 0, 1.0}, {0, 1, 1.0}, {0,-1, 1.0},
        { 1, 1, 1.414}, {-1, 1, 1.414}, { 1,-1, 1.414}, {-1,-1, 1.414},
    }

    local dist          = {}
    local claimed       = {}
    local claimed_count = 0
    local seed          = (city.y-1)*w + city.x
    dist[seed] = 0
    hpush(0, seed)

    while #heap > 0 and claimed_count < target_cells do
        local node = hpop()
        local d, ci = node[1], node[2]
        if not claimed[ci] then
            claimed[ci]   = true
            claimed_count = claimed_count + 1

            local cx   = (ci-1) % w
            local cy_i = math.floor((ci-1) / w)
            for _, m in ipairs(moves) do
                local nx2 = cx   + m[1]
                local ny2 = cy_i + m[2]
                if nx2 >= 0 and nx2 < w and ny2 >= 0 and ny2 < h then
                    local ni = ny2 * w + nx2 + 1
                    if region_map[ni] == rid and not claimed[ni] then
                        local cost = claim_cost(nx2, ny2, m[3])
                        if cost < math.huge then
                            local nd = d + cost
                            if not dist[ni] or nd < dist[ni] then
                                dist[ni] = nd
                                hpush(nd, ni)
                            end
                        end
                    end
                end
            end
        end
    end

    -- Fill enclosed islands: flood-fill from the world border outward through
    -- unclaimed cells to find all "exterior" unclaimed space.  Any unclaimed
    -- cell that is NOT reachable from the border is fully enclosed by city and
    -- gets absorbed.  This handles islands of any size in one O(w*h) pass.
    local exterior = {}
    local q = {}; local qh = 1

    local function seed(cx2, cy2)
        local ci = cy2 * w + cx2 + 1
        if not claimed[ci] and not exterior[ci] then
            exterior[ci] = true; q[#q+1] = ci
        end
    end
    for bx = 0, w-1 do seed(bx, 0); seed(bx, h-1) end
    for by = 1, h-2 do seed(0, by); seed(w-1, by) end

    local CARD = {{1,0},{-1,0},{0,1},{0,-1}}
    while qh <= #q do
        local ci = q[qh]; qh = qh + 1
        local cx2 = (ci-1) % w; local cy2 = math.floor((ci-1) / w)
        for _, m in ipairs(CARD) do
            local nx2 = cx2+m[1]; local ny2 = cy2+m[2]
            if nx2 >= 0 and nx2 < w and ny2 >= 0 and ny2 < h then
                local ni = ny2*w+nx2+1
                if not claimed[ni] and not exterior[ni] then
                    exterior[ni] = true; q[#q+1] = ni
                end
            end
        end
    end

    -- Claim every cell that is unclaimed AND not exterior (i.e. enclosed)
    for cy2 = 0, h-1 do
        for cx2 = 0, w-1 do
            local ci = cy2*w+cx2+1
            if not claimed[ci] and not exterior[ci] then
                claimed[ci] = true; claimed_count = claimed_count + 1
            end
        end
    end

    -- Erode claimed area: remove cells where any 8-neighbor is unclaimed.
    -- Two passes guarantee POIs are always ≥2 cells from any edge.
    local eroded = {}
    for ci in pairs(claimed) do eroded[ci] = true end
    for _ = 1, 2 do
        local next_e = {}
        for ci in pairs(eroded) do
            local cx2 = (ci-1) % w
            local cy2 = math.floor((ci-1) / w)
            local ok  = true
            for _, m in ipairs(moves) do
                local nx2 = cx2 + m[1]; local ny2 = cy2 + m[2]
                if nx2 < 0 or nx2 >= w or ny2 < 0 or ny2 >= h or not eroded[ny2*w+nx2+1] then
                    ok = false; break
                end
            end
            if ok then next_e[ci] = true end
        end
        -- If erosion wiped everything out (tiny city), stop early
        local any = next(next_e)
        if not any then break end
        eroded = next_e
    end
    -- Fall back to full claimed set if erosion left nothing
    local inner = next(eroded) and eroded or claimed

    -- POI count scales with suitability; min 1, max = slider
    local poi_max   = math.max(1, math.floor(p.city_poi_count or 5))
    local poi_count = math.max(1, math.floor(poi_max * (city.s or 0.5)))

    -- Centroid of eroded inner area — anchor for downtown placement.
    local sum_x, sum_y, n = 0, 0, 0
    for ci in pairs(inner) do
        sum_x = sum_x + (ci-1) % w + 1
        sum_y = sum_y + math.floor((ci-1) / w) + 1
        n     = n + 1
    end
    local cen_x = n > 0 and sum_x / n or city.x
    local cen_y = n > 0 and sum_y / n or city.y

    -- Step 1: Pin downtown to the inner cell closest to the centroid.
    -- This guarantees downtown is always near the geographic centre of the city.
    local dt_cell = nil
    local dt_d2   = math.huge
    local fallback_pool = (next(inner) and inner) or claimed
    for ci in pairs(fallback_pool) do
        local px = (ci-1) % w + 1; local py = math.floor((ci-1) / w) + 1
        local d2 = (px - cen_x)^2 + (py - cen_y)^2
        if d2 < dt_d2 then
            dt_d2  = d2
            dt_cell = {i=ci, x=px, y=py, s=(scores and scores[ci] or 0)}
        end
    end

    -- Step 2: Build the full sampling pool from ALL claimed cells so district
    -- POIs can reach the city periphery (eroded inner is too small for irregular
    -- city shapes and collapses all POIs into a central strip).
    local sample_list = {}
    for ci in pairs(claimed) do
        local px = (ci-1) % w + 1; local py = math.floor((ci-1) / w) + 1
        sample_list[#sample_list+1] = {i=ci, x=px, y=py, s=(scores and scores[ci] or 0)}
    end

    -- Step 3: Seed farthest-point distances from downtown's position so the
    -- first district POI is placed as far from downtown as possible, then each
    -- subsequent one maximises distance from ALL placed POIs.
    -- Suitability adds a small tie-breaking bonus; geographic spread dominates.
    local min_d2 = {}
    for _, cell in ipairs(sample_list) do
        local dx = cell.x - dt_cell.x; local dy = cell.y - dt_cell.y
        min_d2[cell.i] = dx*dx + dy*dy
    end

    -- candidates[1] = downtown (fixed); remaining placed by farthest-point
    local candidates = {{x=dt_cell.x, y=dt_cell.y, s=dt_cell.s, region_id=rid}}
    -- Mark downtown's cell as used (distance 0 so it won't be picked again)
    min_d2[dt_cell.i] = 0

    for _ = 2, poi_count do
        local best_score = -1
        local best_cell  = nil
        for _, cell in ipairs(sample_list) do
            local score = min_d2[cell.i] * (1.0 + cell.s * 0.5)
            if score > best_score then best_score = score; best_cell = cell end
        end
        if not best_cell then break end
        candidates[#candidates+1] = {x=best_cell.x, y=best_cell.y,
                                      s=best_cell.s, region_id=rid}
        for _, cell in ipairs(sample_list) do
            local dx = cell.x - best_cell.x; local dy = cell.y - best_cell.y
            local d2 = dx*dx + dy*dy
            if d2 < min_d2[cell.i] then min_d2[cell.i] = d2 end
        end
    end

    -- candidates[1] is already downtown; tag and return
    local pois = {}
    for k, c in ipairs(candidates) do
        pois[#pois+1] = {x=c.x, y=c.y, s=c.s, region_id=rid,
                         type=(k == 1 and "downtown" or "district")}
    end

    return claimed, pois
end

-- Regenerates bounds and POIs for all placed cities.
-- Mutates city.x/y to the discovered downtown centroid (same as original).
-- Returns: city_bounds_list, city_pois_list, all_city_bounds, all_city_pois, border, fringe
function CityBoundsService.genAllBounds(
    city_locations, region_map, heightmap, biome_data,
    suitability_scores, w, h, params, math_fns
)
    local new_bounds_list = {}
    local new_pois_list   = {}
    local new_bounds      = {}
    local new_pois        = {}

    for idx, city in ipairs(city_locations) do
        local claimed, pois = genBoundsForCity(
            city, region_map, heightmap, biome_data,
            suitability_scores, w, h, params, math_fns
        )
        new_bounds_list[idx] = claimed or {}
        new_pois_list[idx]   = pois or {}
        if claimed then
            for ci in pairs(claimed) do new_bounds[ci] = true end
        end
        if pois then
            for _, poi in ipairs(pois) do
                new_pois[#new_pois+1] = poi
                if poi.type == "downtown" then
                    city.x = poi.x
                    city.y = poi.y
                end
            end
        end
    end

    -- Border: claimed cells with at least one non-claimed cardinal neighbor
    local border = {}
    for ci in pairs(new_bounds) do
        local cx = (ci-1) % w
        local cy = math.floor((ci-1) / w)
        for _, m in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do
            local nx2 = cx + m[1]
            local ny2 = cy + m[2]
            if nx2 < 0 or nx2 >= w or ny2 < 0 or ny2 >= h then
                border[ci] = true; break
            else
                local ni = ny2 * w + nx2 + 1
                if not new_bounds[ni] then border[ci] = true; break end
            end
        end
    end

    -- Fringe: noise-based expansion 1 cell beyond bounds for sub-tile soft edge
    local noise  = math_fns.noise
    local fringe = {}
    for ci in pairs(new_bounds) do
        local cx = (ci-1) % w
        local cy = math.floor((ci-1) / w)
        for _, m in ipairs({{1,0},{-1,0},{0,1},{0,-1},{1,1},{-1,1},{1,-1},{-1,-1}}) do
            local nx2 = cx + m[1]
            local ny2 = cy + m[2]
            if nx2 >= 0 and nx2 < w and ny2 >= 0 and ny2 < h then
                local ni = ny2 * w + nx2 + 1
                if not new_bounds[ni] then
                    local nv = noise(nx2 * 4.3 + 0.5, ny2 * 3.7 + 0.5)
                    if nv > 0.40 then fringe[ni] = true end
                end
            end
        end
    end

    return new_bounds_list, new_pois_list, new_bounds, new_pois, border, fringe
end

return CityBoundsService
