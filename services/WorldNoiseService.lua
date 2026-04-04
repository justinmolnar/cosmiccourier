-- services/WorldNoiseService.lua
-- Pure FBM noise → normalized heightmap + colormap.
-- Multiple islands emerge naturally from noise topology wherever peaks exceed sea level.
-- No artificial island placement. sea level is implicitly the coast_max threshold.

local WorldNoiseService = {}
local Biomes = require("data.biomes")

local RIVER_COLOR = { 0.22, 0.52, 0.88 }
local LAKE_COLOR  = { 0.07, 0.20, 0.55 }

-- Standard FBM — smooth hills, used for continental shape and moisture.
local function fbm(px, py, scale, octaves, persistence, lacunarity, ox, oy)
    local val, amp, freq, total = 0, 1, scale, 0
    for _ = 1, math.floor(octaves) do
        val   = val + amp * love.math.noise(px * freq + ox, py * freq + oy)
        total = total + amp
        amp   = amp * persistence
        freq  = freq * lacunarity
    end
    return val / total
end

-- Ridged FBM — sharp peaks instead of smooth domes, used for mountain ranges.
-- Each octave is inverted so valleys become ridges; squaring sharpens the peaks.
local function ridge_fbm(px, py, scale, octaves, persistence, lacunarity, ox, oy)
    local val, amp, freq, total = 0, 1, scale, 0
    for _ = 1, math.floor(octaves) do
        local n = love.math.noise(px * freq + ox, py * freq + oy)
        n = 1 - 2 * math.abs(n - 0.5)   -- flip: valleys → peaks
        n = n * n                          -- square: sharpens ridges
        val   = val + amp * n
        total = total + amp
        amp   = amp * persistence
        freq  = freq * lacunarity
    end
    return val / total
end


-- Returns 0 at map edges, 1 once you're `margin` fraction inside.
-- Used to suppress land near borders without touching ocean floor depth.
local function edge_mask(x, y, w, h, margin)
    local nx = (x - 1) / math.max(1, w - 1)
    local ny = (y - 1) / math.max(1, h - 1)
    local dx = math.min(nx, 1 - nx)
    local dy = math.min(ny, 1 - ny)
    local fx = math.min(1, dx / math.max(0.001, margin))
    local fy = math.min(1, dy / math.max(0.001, margin))
    return fx * fy
end

-- Discrete biome colors — flat per band, no lerp between biomes.
-- This gives crisp colour bands like a classic tile map, not a smooth haze.
local function biome_color(h, m, p)
    if h < p.deep_ocean_max then
        return { 0.04, 0.08, 0.30 }
    elseif h < p.ocean_max then
        return { 0.07, 0.15, 0.45 }
    elseif h < p.coast_max then
        return { 0.76, 0.70, 0.48 }
    elseif h < p.plains_max then
        return (m > 0.5) and { 0.35, 0.62, 0.20 } or { 0.55, 0.52, 0.20 }
    elseif h < p.forest_max then
        return (m > 0.5) and { 0.14, 0.40, 0.10 } or { 0.32, 0.44, 0.14 }
    elseif h < p.highland_max then
        return { 0.40, 0.44, 0.26 }
    elseif h < p.mountain_max then
        return { 0.52, 0.48, 0.42 }
    else
        return { 0.88, 0.90, 0.95 }
    end
end

-- ── Phase 1: heightmap ────────────────────────────────────────────────────────
-- Generates FBM noise heightmap, normalises, applies edge mask and mountain
-- ridges.  Returns the heightmap, the initial biome-color colormap, the
-- pre-ridge smooth heights used by river routing, and the moisture map.
local function generateHeightMap(w, h, p)
    local sx     = p.seed_x or 0
    local sy     = p.seed_y or 0
    local margin = p.edge_margin or 0.22

    -- Pass 1: island shapes via smooth FBM only.
    -- Terrain layer is plain FBM here — ridge noise is NOT mixed in so it
    -- doesn't fragment coastlines.
    local heightmap = {}
    local min_h, max_h = math.huge, -math.huge
    for y = 1, h do
        heightmap[y] = {}
        for x = 1, w do
            local continental = fbm(x, y, p.continental_scale, p.continental_octaves, 0.6,           2.0,          sx,        sy)
            local terrain     = fbm(x, y, p.terrain_scale,     p.terrain_octaves,     p.persistence, p.lacunarity, sx + 1000, sy + 1000)
            local detail      = fbm(x, y, p.detail_scale,      p.detail_octaves,      0.5,           2.0,          sx + 2000, sy + 2000)
            local raw = continental * p.continental_weight
                      + terrain     * p.terrain_weight
                      + detail      * p.detail_weight
            heightmap[y][x] = raw
            if raw < min_h then min_h = raw end
            if raw > max_h then max_h = raw end
        end
    end

    -- Pass 2: normalize, apply edge mask, then overlay mountain ridges ONLY on
    -- land cells so island shapes are completely untouched.
    -- Also capture pre-ridge smooth heights for river flow routing.
    local range = max_h - min_h
    if range < 0.0001 then range = 0.0001 end

    local colormap    = {}
    local pre_ridge   = {}   -- flat 1-D array of smooth heights (before mountain overlay)
    local moisture_map = {}  -- [y][x] moisture value, reused in Pass 4 for climate biomes

    for y = 1, h do
        colormap[y]     = {}
        moisture_map[y] = {}
        local base = (y - 1) * w
        for x = 1, w do
            local norm = (heightmap[y][x] - min_h) / range

            -- Edge mask: suppress land near map borders
            local em = edge_mask(x, y, w, h, margin)
            if norm > p.deep_ocean_max then
                norm = p.deep_ocean_max + (norm - p.deep_ocean_max) * em
            end

            -- Store smooth height before mountain overlay — used by river routing
            -- so ridge spikes don't fragment the drainage network.
            pre_ridge[base + x] = norm

            -- Mountain pass: ridge noise added on top of land only.
            -- land_t ramps from 0 at the coastline to 1 at the interior peak,
            -- so mountains concentrate inland and fade to zero at the shore.
            if norm > p.coast_max then
                local land_t  = (norm - p.coast_max) / (1.0 - p.coast_max)
                local ridge   = ridge_fbm(x, y, p.mountain_scale, p.mountain_octaves, 0.5, 2.0, sx + 3000, sy + 3000)
                norm = norm + ridge * p.mountain_strength * land_t
                norm = math.min(1.0, norm)
            end

            heightmap[y][x] = norm
            local moisture = fbm(x, y, p.moisture_scale, p.moisture_octaves, 0.5, 2.0, sx + 5000, sy + 5000)
            moisture_map[y][x] = moisture
            colormap[y][x] = biome_color(norm, moisture, p)
        end
    end

    return heightmap, colormap, pre_ridge, moisture_map
end

-- ── Phase 2: rivers + lakes ───────────────────────────────────────────────────
-- Traces rivers downstream and fills pits as lakes.  Modifies colormap
-- in-place for water cells.  Returns painted (river+lake set) and is_lake.
local function traceRiversAndLakes(w, h, p, heightmap, colormap, pre_ridge)
    local sx = p.seed_x or 0
    local sy = p.seed_y or 0

    -- Pass 3: Source-tracing rivers with fill-and-spill lakes.
    --
    -- Pick N well-spaced highland sources.  Trace each downstream via strict
    -- D8 flow.  When a trace hits a pit (inland depression), flood-fill the
    -- basin upward until the lowest rim is found, paint the basin as a lake,
    -- then continue the river from that rim — rivers never end mid-land.
    -- Two traces that reach the same cell merge naturally.
    -- Hoisted so Pass 4 (biome map) can read which cells are water.
    local painted     = {}   -- river + lake cell indices
    local is_lake     = {}   -- lake-only subset for merging
    local river_paths = {}   -- [{x,y}, ...] per river for vector rendering

    local river_count = math.floor(p.river_count or 0)
    if river_count > 0 then
        local D8 = { {-1,-1},{0,-1},{1,-1},{-1,0},{1,0},{-1,1},{0,1},{1,1} }
        local D4 = { {0,-1},{-1,0},{1,0},{0,1} }

        -- Mark true ocean: BFS from all 4 map edges expanding through cells at or
        -- below ocean_max.  Only edge-connected ocean is marked — isolated inland
        -- depressions are NOT ocean even if their height is below the threshold.
        -- River/lake painting never touches is_ocean cells.
        local is_ocean = {}
        do
            local q  = {}
            local qi = 1
            local function seed(ci)
                if not is_ocean[ci] then
                    is_ocean[ci] = true
                    q[#q + 1]    = ci
                end
            end
            for x = 1, w do seed(x);           seed((h - 1) * w + x) end
            for y = 1, h do seed((y - 1) * w + 1); seed((y - 1) * w + w) end
            while qi <= #q do
                local ci  = q[qi]; qi = qi + 1
                local cy2 = math.floor((ci - 1) / w) + 1
                local cx2 = (ci - 1) % w + 1
                for _, d in ipairs(D4) do
                    local nx2, ny2 = cx2 + d[1], cy2 + d[2]
                    if nx2 >= 1 and nx2 <= w and ny2 >= 1 and ny2 <= h then
                        local ni = (ny2 - 1) * w + nx2
                        if not is_ocean[ni] and pre_ridge[ni] <= p.ocean_max then
                            is_ocean[ni] = true
                            q[#q + 1]    = ni
                        end
                    end
                end
            end
        end

        -- Box-blur pre_ridge (radius 3) to smooth micro-pits before routing.
        local SR   = 3
        local flat = {}
        for y = 1, h do
            local base = (y - 1) * w
            for x = 1, w do
                local sum, cnt = 0, 0
                for dy2 = math.max(1, y - SR), math.min(h, y + SR) do
                    for dx2 = math.max(1, x - SR), math.min(w, x + SR) do
                        sum = sum + pre_ridge[(dy2 - 1) * w + dx2]
                        cnt = cnt + 1
                    end
                end
                flat[base + x] = sum / cnt
            end
        end

        local meander_strength = p.meander_strength or 0.020

        -- Strict-downhill D8 flow from unperturbed flat[].
        -- Pits (no lower neighbour) stay flow_to=0.
        -- Meander noise is NOT baked in here — adding it to flat[] globally creates
        -- fake pits everywhere so rivers stop after a few steps at high strength.
        -- Instead, meander is applied per-step during tracing (see choose_next).
        local flow_to = {}
        for y = 1, h do
            local base = (y - 1) * w
            for x = 1, w do
                local i     = base + x
                local min_v = flat[i]
                local best  = 0
                for _, d in ipairs(D8) do
                    local nx2, ny2 = x + d[1], y + d[2]
                    if nx2 >= 1 and nx2 <= w and ny2 >= 1 and ny2 <= h then
                        local j = (ny2 - 1) * w + nx2
                        if flat[j] < min_v then min_v = flat[j]; best = j end
                    end
                end
                flow_to[i] = best
            end
        end

        -- Source selection: highland land cells with a downhill path, sorted by
        -- elevation descending, greedy-spaced so sources spread across the map.
        local min_sep = math.max(6, math.floor(math.min(w, h) / (river_count + 1)))
        local candidates = {}
        for y = 1, h do
            local base = (y - 1) * w
            for x = 1, w do
                local i = base + x
                if not is_ocean[i] and pre_ridge[i] > p.coast_max and flow_to[i] ~= 0 then
                    candidates[#candidates + 1] = { i = i, x = x, y = y, elev = flat[i] }
                end
            end
        end
        table.sort(candidates, function(a, b) return a.elev > b.elev end)

        local sources = {}
        for _, c in ipairs(candidates) do
            local ok = true
            for _, s in ipairs(sources) do
                local ddx = c.x - s.x
                local ddy = c.y - s.y
                if ddx * ddx + ddy * ddy < min_sep * min_sep then
                    ok = false; break
                end
            end
            if ok then
                sources[#sources + 1] = c
                if #sources >= river_count then break end
            end
        end

        local lake_delta  = p.lake_delta or 0.010
        local MAX_LAKE    = 150

        -- Carve step: absolute lowest D8 neighbour, even uphill.
        -- Fallback when a pit has no valid spillway.
        local function carve_step(ci)
            local cy2 = math.floor((ci - 1) / w) + 1
            local cx2 = (ci - 1) % w + 1
            local best_h, best_j = math.huge, nil
            for _, d in ipairs(D8) do
                local nx2, ny2 = cx2 + d[1], cy2 + d[2]
                if nx2 >= 1 and nx2 <= w and ny2 >= 1 and ny2 <= h then
                    local j = (ny2 - 1) * w + nx2
                    if flat[j] < best_h then best_h = flat[j]; best_j = j end
                end
            end
            return best_j
        end

        -- Stochastic downhill step for river tracing.
        -- Scores each valid downhill D8 neighbour as (height_drop + noise*meander).
        -- At meander=0 always picks steepest (straight lines).
        -- At higher meander, noise competes with drop → winding paths.
        -- Unlike baking noise into flat[], this never creates fake pits.
        local MNS = 0.15   -- noise sample scale for meander
        local function choose_next(ci)
            local cy2 = math.floor((ci - 1) / w) + 1
            local cx2 = (ci - 1) % w + 1
            local cur  = flat[ci]
            local best_score, best_j = -math.huge, nil
            for _, d in ipairs(D8) do
                local nx2, ny2 = cx2 + d[1], cy2 + d[2]
                if nx2 >= 1 and nx2 <= w and ny2 >= 1 and ny2 <= h then
                    local j = (ny2 - 1) * w + nx2
                    if flat[j] < cur then
                        local drop  = cur - flat[j]
                        local noise = love.math.noise(nx2 * MNS + sx + 8321, ny2 * MNS + sy + 8321)
                        local score = drop + noise * meander_strength
                        if score > best_score then
                            best_score = score
                            best_j     = j
                        end
                    end
                end
            end
            return best_j  -- nil if no downhill neighbour (true pit)
        end

        -- Fill-and-spill lake.
        -- Only triggered for lowland pits (pre_ridge < forest_max).
        -- Lake boundary uses per-cell noise so edges are ragged/organic rather
        -- than following smooth flat[] contour lines.
        -- Adjacent lake cells (is_lake) are pulled in to merge overlapping lakes.
        -- Returns spillway cell, or nil; caller uses carve_step as fallback.
        local LNS = 0.25   -- noise scale for lake edge irregularity
        local function fill_and_spill(pit_i)
            if lake_delta <= 0 then return nil end
            if pre_ridge[pit_i] >= p.forest_max then return nil end

            local water_flat = flat[pit_i] + lake_delta
            local in_basin = {}
            local basin_list = {}
            local function add(ci)
                if not in_basin[ci] then
                    in_basin[ci] = true
                    basin_list[#basin_list + 1] = ci
                end
            end
            add(pit_i)
            local qi = 1
            while qi <= #basin_list and #basin_list < MAX_LAKE do
                local ci  = basin_list[qi]; qi = qi + 1
                local cy2 = math.floor((ci - 1) / w) + 1
                local cx2 = (ci - 1) % w + 1
                for _, d in ipairs(D8) do
                    local nx2, ny2 = cx2 + d[1], cy2 + d[2]
                    if nx2 >= 1 and nx2 <= w and ny2 >= 1 and ny2 <= h then
                        local ni = (ny2 - 1) * w + nx2
                        if not in_basin[ni] and not is_ocean[ni] then
                            -- Per-cell noise shifts the threshold independently of
                            -- lake_delta so the edge is always ragged regardless of size.
                            local edge_n = love.math.noise(nx2 * LNS + sx + 9001, ny2 * LNS + sy + 9001)
                            local thresh = water_flat + (edge_n - 0.5) * 0.04
                            if flat[ni] <= thresh or is_lake[ni] then
                                add(ni)
                            end
                        end
                    end
                end
            end
            -- Find lowest rim outside basin
            local best_rim_h, best_rim_i = math.huge, nil
            for _, ci in ipairs(basin_list) do
                local cy2 = math.floor((ci - 1) / w) + 1
                local cx2 = (ci - 1) % w + 1
                for _, d in ipairs(D8) do
                    local nx2, ny2 = cx2 + d[1], cy2 + d[2]
                    if nx2 >= 1 and nx2 <= w and ny2 >= 1 and ny2 <= h then
                        local ni = (ny2 - 1) * w + nx2
                        if not in_basin[ni] and flat[ni] < best_rim_h then
                            best_rim_h = flat[ni]
                            best_rim_i = ni
                        end
                    end
                end
            end
            -- Paint basin as lake
            for _, ci in ipairs(basin_list) do
                painted[ci] = true
                is_lake[ci]  = true
                local cy2 = math.floor((ci - 1) / w) + 1
                local cx2 = (ci - 1) % w + 1
                colormap[cy2][cx2] = LAKE_COLOR
            end
            return best_rim_i
        end

        -- Trace each source downstream to the ocean (or merge with existing river/lake).
        -- Uses choose_next (stochastic downhill) for meandering paths.
        -- True pits (no downhill neighbour) → fill_and_spill lake → carve fallback.
        -- Also capture each river as a sequence of {x,y} cells for vector rendering.
        river_paths = {}
        for _, src in ipairs(sources) do
            local i     = src.i
            local steps = 0
            local path  = {}
            while i and i > 0 and steps < w * h do
                steps = steps + 1
                if is_ocean[i]  then break end
                if painted[i]   then break end
                painted[i] = true
                local cy = math.floor((i - 1) / w) + 1
                local cx = (i - 1) % w + 1
                colormap[cy][cx] = RIVER_COLOR
                path[#path + 1] = { x = cx, y = cy }
                local nxt = choose_next(i)
                if nxt == nil then
                    nxt = fill_and_spill(i)
                    if nxt == nil then nxt = carve_step(i) end
                end
                i = nxt
            end
            if #path >= 2 then
                river_paths[#river_paths + 1] = path
            end
        end

        -- Lake edge smoothing: 2 passes of cellular automaton.
        -- Land cells surrounded by mostly lake (≥5 of 8 D8 neighbours) get
        -- absorbed into the lake, rounding concave corners and filling notches.
        -- This breaks the straight-contour look without needing to restore colours.
        for _ = 1, 2 do
            local to_add = {}
            for y2 = 1, h do
                for x2 = 1, w do
                    local ci = (y2 - 1) * w + x2
                    if not is_lake[ci] and not is_ocean[ci] then
                        local cnt = 0
                        for _, d in ipairs(D8) do
                            local nx2, ny2 = x2 + d[1], y2 + d[2]
                            if nx2 >= 1 and nx2 <= w and ny2 >= 1 and ny2 <= h then
                                if is_lake[(ny2 - 1) * w + nx2] then cnt = cnt + 1 end
                            end
                        end
                        if cnt >= 5 then to_add[#to_add + 1] = ci end
                    end
                end
            end
            for _, ci in ipairs(to_add) do
                is_lake[ci]  = true
                painted[ci]  = true
                local cy2 = math.floor((ci - 1) / w) + 1
                local cx2 = (ci - 1) % w + 1
                colormap[cy2][cx2] = LAKE_COLOR
            end
        end
    end

    return painted, is_lake, river_paths
end

-- ── Phase 3: biomes + suitability ─────────────────────────────────────────────
-- Builds climate biome colormap (Pass 4) and city-suitability scores (Pass 5).
local function assignBiomesAndSuitability(w, h, p, heightmap, pre_ridge, moisture_map, painted, is_lake)
    local sx = p.seed_x or 0
    local sy = p.seed_y or 0

    -- Pass 4: Water-proximity biome map.
    -- Multi-source BFS from all river/lake cells.  Cells close to water get
    -- high fertility (lush green); cells far away get low fertility (arid brown).
    -- Ocean and coast bands are rendered identically to the height view.
    local river_influence = math.max(1, p.river_influence or 30)
    local biome_colormap  = {}
    local biome_data      = {}   -- hoisted so Pass 5 can reference it
    do
        local D4b = { {0,-1},{-1,0},{1,0},{0,1} }
        local wdist = {}
        local bq, bqi = {}, 1
        for i = 1, w * h do
            if painted[i] then
                wdist[i] = 0
                bq[#bq + 1] = i
            end
        end
        while bqi <= #bq do
            local ci  = bq[bqi]; bqi = bqi + 1
            local nd  = wdist[ci] + 1
            if nd <= river_influence then
                local cy2 = math.floor((ci - 1) / w) + 1
                local cx2 = (ci - 1) % w + 1
                for _, d in ipairs(D4b) do
                    local nx2, ny2 = cx2 + d[1], cy2 + d[2]
                    if nx2 >= 1 and nx2 <= w and ny2 >= 1 and ny2 <= h then
                        local ni = (ny2 - 1) * w + nx2
                        if not wdist[ni] then
                            wdist[ni] = nd
                            bq[#bq + 1] = ni
                        end
                    end
                end
            end
        end

        local lat_strength = p.latitude_strength or 0.7
        -- biome_data declared above so Pass 5 can access it after this do..end
        for y = 1, h do
            biome_colormap[y] = {}
            local base       = (y - 1) * w
            -- lat_factor 0 = top of map (north/cold), 1 = bottom (south/warm)
            local lat_factor = (y - 1) / math.max(1, h - 1)
            for x = 1, w do
                local i = base + x
                if painted[i] then
                    local is_r = not is_lake[i]
                    biome_colormap[y][x] = is_lake[i] and LAKE_COLOR or RIVER_COLOR
                    biome_data[i] = { name = is_r and "River" or "Lake", temp = 0, wet = 1,
                                      is_river = is_r, is_lake = is_lake[i] }
                else
                    local h_val  = heightmap[y][x]
                    local dist   = wdist[i] or (river_influence + 1)
                    local fert   = math.max(0, 1 - dist / river_influence)
                    local moist  = moisture_map[y][x]
                    -- Temperature: latitude sets base warmth; elevation cools
                    local temp_base = lat_factor * lat_strength + 0.5 * (1 - lat_strength)
                    local elev_t = 0
                    if h_val > p.coast_max then
                        elev_t = (h_val - p.coast_max) / (1.0 - p.coast_max)
                    end
                    local temp = math.max(0, math.min(1, temp_base - elev_t * 0.4))
                    -- Wetness: water proximity (fertility) blended with moisture noise
                    local wet = math.max(0, math.min(1, fert * 0.7 + moist * 0.3))
                    biome_colormap[y][x] = Biomes.getColor(h_val, temp, wet, p)
                    biome_data[i] = { name = Biomes.getName(h_val, temp, wet, p),
                                      temp = temp, wet = wet, is_river = false, is_lake = false }
                end
            end
        end
        -- biome_data now populated in outer scope; Pass 5 runs after this block
    end

    -- Pass 5: City suitability map.
    -- Combines elevation sweetspot, coast proximity, river proximity, and climate
    -- into a per-cell [0,1] score.  Rendered as a colour ramp (grey→gold→green).
    -- All weights and radii are sliders — no magic numbers baked in.
    local suitability_colormap = {}
    local raw_suit             = {}   -- hoisted so the return statement can reference it
    do
        local D4s = { {0,-1},{-1,0},{1,0},{0,1} }

        -- Coast proximity BFS: seed from all cells at or below coast_max,
        -- expand outward onto land.  Distance = cells from nearest coastline.
        local suit_coast_radius = math.max(1, p.suit_coast_radius or 80)
        local coast_dist = {}
        do
            local bq2, bqi2 = {}, 1
            for i = 1, w * h do
                if pre_ridge[i] <= p.coast_max then
                    coast_dist[i] = 0
                    bq2[#bq2 + 1] = i
                end
            end
            while bqi2 <= #bq2 do
                local ci  = bq2[bqi2]; bqi2 = bqi2 + 1
                local nd  = coast_dist[ci] + 1
                if nd <= suit_coast_radius then
                    local cy2 = math.floor((ci - 1) / w) + 1
                    local cx2 = (ci - 1) % w + 1
                    for _, d in ipairs(D4s) do
                        local nx2, ny2 = cx2 + d[1], cy2 + d[2]
                        if nx2 >= 1 and nx2 <= w and ny2 >= 1 and ny2 <= h then
                            local ni = (ny2 - 1) * w + nx2
                            if not coast_dist[ni] then
                                coast_dist[ni] = nd
                                bq2[#bq2 + 1] = ni
                            end
                        end
                    end
                end
            end
        end

        -- River proximity BFS: seed from painted (river/lake) cells.
        local suit_river_radius = math.max(1, p.suit_river_radius or 60)
        local rdist = {}
        do
            local bq3, bqi3 = {}, 1
            for i = 1, w * h do
                if painted[i] then
                    rdist[i] = 0
                    bq3[#bq3 + 1] = i
                end
            end
            while bqi3 <= #bq3 do
                local ci  = bq3[bqi3]; bqi3 = bqi3 + 1
                local nd  = rdist[ci] + 1
                if nd <= suit_river_radius then
                    local cy2 = math.floor((ci - 1) / w) + 1
                    local cx2 = (ci - 1) % w + 1
                    for _, d in ipairs(D4s) do
                        local nx2, ny2 = cx2 + d[1], cy2 + d[2]
                        if nx2 >= 1 and nx2 <= w and ny2 >= 1 and ny2 <= h then
                            local ni = (ny2 - 1) * w + nx2
                            if not rdist[ni] then
                                rdist[ni] = nd
                                bq3[#bq3 + 1] = ni
                            end
                        end
                    end
                end
            end
        end

        -- Per-cell suitability score.
        -- Rivers appear as sharp corridors (tight radius, quadratic decay).
        -- Coast provides a broad baseline across the island perimeter.
        -- Elevation declines gently toward highlands so river paths aren't killed.
        -- Cells far from BOTH water sources get an isolation penalty near zero.
        local suit_elev_weight    = p.suit_elev_weight    or 0.40
        local suit_coast_weight   = p.suit_coast_weight   or 0.35
        local suit_river_weight   = p.suit_river_weight   or 0.65
        local suit_climate_weight = p.suit_climate_weight or 0.20

        -- raw_suit declared above (hoisted)
        for y = 1, h do
            local base = (y - 1) * w
            for x = 1, w do
                local i     = base + x
                local h_val = heightmap[y][x]
                if h_val <= p.coast_max or h_val >= p.mountain_max then
                    raw_suit[i] = 0
                else
                    -- Elevation: gentle quadratic decline from coast up to mountain.
                    -- Using the full coast→mountain range so rivers in highlands still score.
                    local rel = (h_val - p.coast_max) / math.max(0.001, p.mountain_max - p.coast_max)
                    local elev_score = math.max(0, 1 - rel * rel) * suit_elev_weight

                    -- Coast score: broad linear gradient inward from shore
                    local cd          = coast_dist[i] or (suit_coast_radius + 1)
                    local coast_score = math.max(0, 1 - cd / suit_coast_radius) * suit_coast_weight

                    -- River score: TIGHT radius with QUADRATIC decay so rivers show
                    -- as distinct narrow corridors of high suitability, not a blurry haze.
                    local rd          = rdist[i] or (suit_river_radius + 1)
                    local rf          = math.max(0, 1 - rd / suit_river_radius)
                    local river_score = rf * rf * suit_river_weight   -- quadratic = sharp near river

                    -- Climate: modifier 0.5 (hostile) → 1.0 (ideal temperate)
                    local bd = biome_data[i]
                    local climate_mod = 0.6
                    if bd and not bd.is_river and not bd.is_lake then
                        local t  = bd.temp
                        local wt = bd.wet
                        local dt = (t  - 0.50) / 0.30
                        local dw = (wt - 0.42) / 0.25
                        climate_mod = 0.5 + 0.5 * math.exp(-0.5 * dt * dt) * math.exp(-0.5 * dw * dw)
                    end
                    local climate_score = climate_mod * suit_climate_weight

                    -- Additive: both river and coast contribute visibly
                    local water = river_score + coast_score

                    -- Isolation penalty: if far from both, collapse score toward 0
                    local best_proximity = math.max(rf, math.max(0, 1 - cd / suit_coast_radius))
                    local isolation = math.min(1, best_proximity / 0.15)

                    raw_suit[i] = (water + elev_score + climate_score) * isolation
                end
            end
        end

        -- Normalize raw scores to [0,1] in place; raw_suit becomes suitability_scores
        local max_suit = 0.0001
        for i = 1, w * h do
            if raw_suit[i] and raw_suit[i] > max_suit then max_suit = raw_suit[i] end
        end
        for i = 1, w * h do
            raw_suit[i] = (raw_suit[i] or 0) / max_suit
        end

        -- Build colormap: water=ocean blue, land lerped grey→gold→green by score
        for y = 1, h do
            suitability_colormap[y] = {}
            local base = (y - 1) * w
            for x = 1, w do
                local i     = base + x
                local score = raw_suit[i]
                local hv    = heightmap[y][x]
                if hv <= p.ocean_max then
                    suitability_colormap[y][x] = { 0.04, 0.08, 0.30 }
                elseif hv <= p.coast_max then
                    suitability_colormap[y][x] = { 0.10, 0.12, 0.38 }
                elseif score < 0.5 then
                    -- grey (0,0.5) → gold (0.5)
                    local t = score * 2
                    suitability_colormap[y][x] = {
                        0.22 + t * (0.82 - 0.22),
                        0.20 + t * (0.72 - 0.20),
                        0.18 + t * (0.10 - 0.18),
                    }
                else
                    -- gold (0.5) → bright green (1.0)
                    local t = (score - 0.5) * 2
                    suitability_colormap[y][x] = {
                        0.82 + t * (0.10 - 0.82),
                        0.72 + t * (0.85 - 0.72),
                        0.10 + t * (0.20 - 0.10),
                    }
                end
            end
        end
    end

    return biome_colormap, biome_data, suitability_colormap, raw_suit
end

-- ── Phase 4: continents + regions ─────────────────────────────────────────────
-- BFS continent labelling (Pass 6) then weighted-Dijkstra region subdivision
-- (Pass 7).
local function detectContinentsAndRegions(w, h, p, heightmap, pre_ridge, painted)
    local sx = p.seed_x or 0
    local sy = p.seed_y or 0

    -- Pass 6: Continent detection via BFS flood fill.
    -- Every connected land component (pre_ridge > ocean_max) is one continent.
    -- Components whose land fraction is below island_threshold are "islands".
    -- Major continents get distinct palette colours; islands share a neutral tone.
    -- Brightness is modulated by elevation so terrain relief remains visible.
    local continent_colormap = {}
    local continent_map      = {}   -- flat [i] = component id (0 = ocean)
    local continents         = {}   -- list of { id, size, frac, is_island, color }
    do
        local PALETTE = {
            { 0.85, 0.20, 0.20 }, { 0.20, 0.52, 0.90 }, { 0.15, 0.75, 0.30 },
            { 0.92, 0.78, 0.10 }, { 0.65, 0.20, 0.88 }, { 0.92, 0.45, 0.10 },
            { 0.15, 0.80, 0.78 }, { 0.90, 0.28, 0.65 }, { 0.58, 0.88, 0.14 },
            { 0.30, 0.35, 0.90 },
        }
        local ISLAND_COLOR = { 0.55, 0.52, 0.48 }
        local D4c = { {0,-1},{-1,0},{1,0},{0,1} }

        -- BFS flood fill: label each connected land component
        local cell_comp = {}   -- flat [i] -> component id
        local comp_sizes = {}
        local comp_id   = 0
        for y = 1, h do
            for x = 1, w do
                local i = (y - 1) * w + x
                if pre_ridge[i] > p.ocean_max and not cell_comp[i] then
                    comp_id = comp_id + 1
                    local size = 0
                    local bq, bqi = { i }, 1
                    cell_comp[i] = comp_id
                    while bqi <= #bq do
                        local ci  = bq[bqi]; bqi = bqi + 1
                        size = size + 1
                        local cy2 = math.floor((ci - 1) / w) + 1
                        local cx2 = (ci - 1) % w + 1
                        for _, d in ipairs(D4c) do
                            local nx2, ny2 = cx2 + d[1], cy2 + d[2]
                            if nx2 >= 1 and nx2 <= w and ny2 >= 1 and ny2 <= h then
                                local ni = (ny2 - 1) * w + nx2
                                if pre_ridge[ni] > p.ocean_max and not cell_comp[ni] then
                                    cell_comp[ni] = comp_id
                                    bq[#bq + 1]   = ni
                                end
                            end
                        end
                    end
                    comp_sizes[comp_id] = size
                end
            end
        end

        -- Sort components by size descending, classify continent vs island
        local total_land = 0
        for _, sz in pairs(comp_sizes) do total_land = total_land + sz end

        local sorted = {}
        for id, sz in pairs(comp_sizes) do
            sorted[#sorted + 1] = { id = id, size = sz, frac = sz / math.max(1, total_land) }
        end
        table.sort(sorted, function(a, b) return a.size > b.size end)

        local island_threshold = p.island_threshold or 0.03
        local color_by_comp    = {}
        local palette_idx      = 0
        for _, comp in ipairs(sorted) do
            local is_island = comp.frac < island_threshold
            local col
            if is_island then
                col = ISLAND_COLOR
            else
                palette_idx = palette_idx + 1
                col = PALETTE[((palette_idx - 1) % #PALETTE) + 1]
            end
            color_by_comp[comp.id] = col
            continents[#continents + 1] = {
                id       = comp.id,
                size     = comp.size,
                frac     = comp.frac,
                is_island = is_island,
                color    = col,
            }
        end

        -- Build per-cell outputs
        for y = 1, h do
            continent_colormap[y] = {}
            local base = (y - 1) * w
            for x = 1, w do
                local i   = base + x
                local cid = cell_comp[i]
                continent_map[i] = cid or 0
                local hv = heightmap[y][x]
                if cid and color_by_comp[cid] then
                    local c   = color_by_comp[cid]
                    -- Modulate brightness with elevation so terrain stays readable
                    local rel = math.max(0, (hv - p.ocean_max) / math.max(0.001, 1 - p.ocean_max))
                    local br  = 0.55 + 0.45 * rel
                    continent_colormap[y][x] = { c[1] * br, c[2] * br, c[3] * br }
                elseif hv <= p.ocean_max then
                    continent_colormap[y][x] = { 0.04, 0.08, 0.30 }
                else
                    continent_colormap[y][x] = { 0.08, 0.12, 0.42 }
                end
            end
        end
    end

    -- Pass 7: Region subdivision within continents via weighted Dijkstra.
    -- Crossing cost for each cell = 1 + mountain bonus + river bonus.
    -- Mountains and rivers act as natural barriers so borders follow terrain.
    -- Islands get 1 region each; major continents share region_count proportionally.
    local region_colormap = {}
    local region_map      = {}   -- flat [i] = region_id  (0 = ocean)
    local regions_list    = {}   -- [region_id] = { id, continent_id, seed_x, seed_y, color, size }
    do
        local D4r = { {0,-1},{-1,0},{1,0},{0,1} }
        local total_regions   = math.max(1, math.floor(p.region_count        or 20))
        local mountain_cost   = p.region_mountain_cost or 8
        local river_cost_r    = p.region_river_cost    or 4
        local reg_min_sep     = math.max(3, math.floor(p.region_min_sep      or 20))
        -- Brightness tones cycled per region so neighbours contrast within a continent
        local TONES = { 1.00, 0.68, 0.86, 0.58, 0.78, 0.62, 0.92, 0.72 }

        -- Allocation: islands always get 1; major continents share total_regions.
        local major_land = 0
        for _, c in ipairs(continents) do
            if not c.is_island then major_land = major_land + c.size end
        end
        local allocs = {}
        do
            local rems, asum = {}, 0
            for i, c in ipairs(continents) do
                if c.is_island then
                    allocs[i] = 1; asum = asum + 1
                else
                    local exact = total_regions * c.size / math.max(1, major_land)
                    local fv    = math.max(1, math.floor(exact))
                    allocs[i]   = fv; asum = asum + fv
                    rems[#rems+1] = { idx=i, rem=exact - math.floor(exact) }
                end
            end
            table.sort(rems, function(a,b) return a.rem > b.rem end)
            for k = 1, math.max(0, math.min(total_regions - asum, #rems)) do
                allocs[rems[k].idx] = allocs[rems[k].idx] + 1
            end
        end

        -- Group cells by continent id
        local cont_cells = {}
        for _, c in ipairs(continents) do cont_cells[c.id] = {} end
        for i = 1, w * h do
            local cid = continent_map[i]
            if cid and cid > 0 and cont_cells[cid] then
                cont_cells[cid][#cont_cells[cid]+1] = i
            end
        end

        -- Place region seeds and register entries
        local reg_id       = 0
        local seed_of_cell = {}   -- cell_i -> region_id
        for ci, c in ipairs(continents) do
            local cells = cont_cells[c.id]
            if cells and #cells > 0 then
                local want = allocs[ci]
                -- Pseudo-random ordering for spatial spread (deterministic via noise)
                local scored = {}
                for _, idx in ipairs(cells) do
                    local cx2 = (idx-1) % w + 1
                    local cy2 = math.floor((idx-1) / w) + 1
                    scored[#scored+1] = { idx=idx, x=cx2, y=cy2,
                        rank = love.math.noise(cx2*0.07+sx+7777, cy2*0.07+sy+7777) }
                end
                table.sort(scored, function(a,b) return a.rank > b.rank end)
                -- Greedy min-sep selection
                local seeds, min_sq = {}, reg_min_sep * reg_min_sep
                for _, s in ipairs(scored) do
                    local ok = true
                    for _, p2 in ipairs(seeds) do
                        local dx, dy = s.x-p2.x, s.y-p2.y
                        if dx*dx+dy*dy < min_sq then ok=false; break end
                    end
                    if ok then seeds[#seeds+1] = s end
                    if #seeds >= want then break end
                end
                if #seeds == 0 then seeds[1] = scored[1] end
                -- Register region records
                local bc, ti = c.color, 0
                for _, s in ipairs(seeds) do
                    reg_id = reg_id + 1; ti = ti + 1
                    local tone = TONES[((ti-1) % #TONES) + 1]
                    regions_list[reg_id] = { id=reg_id, continent_id=c.id,
                        seed_x=s.x, seed_y=s.y, size=0,
                        color={ bc[1]*tone, bc[2]*tone, bc[3]*tone } }
                    seed_of_cell[s.idx] = reg_id
                end
            end
        end

        -- Multi-source weighted Dijkstra using a binary min-heap.
        -- Each region's expansion is bounded to its own continent.
        local wdist  = {}
        local hd, hs = {}, 0
        local function hpush(d, i)
            hs=hs+1; hd[hs]={d,i}
            local pos=hs
            while pos>1 do
                local par=math.floor(pos/2)
                if hd[par][1]>hd[pos][1] then hd[par],hd[pos]=hd[pos],hd[par]; pos=par else break end
            end
        end
        local function hpop()
            if hs==0 then return nil,nil end
            local top=hd[1]; hd[1]=hd[hs]; hd[hs]=nil; hs=hs-1
            local pos=1
            while true do
                local l,r,sm=pos*2,pos*2+1,pos
                if l<=hs and hd[l][1]<hd[sm][1] then sm=l end
                if r<=hs and hd[r][1]<hd[sm][1] then sm=r end
                if sm==pos then break end
                hd[pos],hd[sm]=hd[sm],hd[pos]; pos=sm
            end
            return top[1],top[2]
        end

        for cell_i, rid in pairs(seed_of_cell) do
            wdist[cell_i]=0; region_map[cell_i]=rid; hpush(0,cell_i)
        end
        while hs > 0 do
            local d, ci = hpop()
            if not (wdist[ci] and d > wdist[ci]) then
                local rid  = region_map[ci]
                local cid  = regions_list[rid] and regions_list[rid].continent_id
                local cy2  = math.floor((ci-1)/w)+1
                local cx2  = (ci-1)%w+1
                for _, d4 in ipairs(D4r) do
                    local nx2,ny2 = cx2+d4[1], cy2+d4[2]
                    if nx2>=1 and nx2<=w and ny2>=1 and ny2<=h then
                        local ni   = (ny2-1)*w+nx2
                        local ncid = continent_map[ni]
                        if ncid and ncid>0 and ncid==cid then
                            local hv   = pre_ridge[ni]
                            local cost = 1.0
                            if hv >= p.highland_max then
                                local t = (hv-p.highland_max)/math.max(0.001,p.mountain_max-p.highland_max)
                                cost = cost + mountain_cost * math.min(1, t)
                            end
                            if painted[ni] then cost = cost + river_cost_r end
                            local nd = d + cost
                            if not wdist[ni] or nd < wdist[ni] then
                                wdist[ni]=nd; region_map[ni]=rid; hpush(nd,ni)
                            end
                        end
                    end
                end
            end
        end

        -- Count sizes
        for i = 1, w*h do
            local rid = region_map[i]
            if rid and rid>0 and regions_list[rid] then
                regions_list[rid].size = regions_list[rid].size + 1
            end
        end

        -- Build colormap: dark border lines + elevation shading within regions
        for y = 1, h do
            region_colormap[y] = {}
            local bi = (y-1)*w
            for x = 1, w do
                local i   = bi+x
                local rid = region_map[i] or 0
                local hv  = heightmap[y][x]
                if rid == 0 then
                    region_colormap[y][x] = hv<=p.ocean_max
                        and {0.04,0.08,0.30} or {0.08,0.12,0.42}
                else
                    local border = false
                    for _, d4 in ipairs(D4r) do
                        local nx2,ny2 = x+d4[1],y+d4[2]
                        if nx2>=1 and nx2<=w and ny2>=1 and ny2<=h then
                            if (region_map[(ny2-1)*w+nx2] or 0) ~= rid then
                                border=true; break
                            end
                        end
                    end
                    if border then
                        region_colormap[y][x] = {0.04,0.04,0.06}
                    else
                        local col = regions_list[rid].color
                        local rel = math.max(0,(hv-p.ocean_max)/math.max(0.001,1-p.ocean_max))
                        local br  = 0.60 + 0.40*rel
                        region_colormap[y][x] = {col[1]*br, col[2]*br, col[3]*br}
                    end
                end
            end
        end
    end

    return continent_colormap, continent_map, continents,
           region_colormap, region_map, regions_list
end

-- ── Public entry point ────────────────────────────────────────────────────────
function WorldNoiseService.generate(w, h, p)
    local heightmap, colormap, pre_ridge, moisture_map =
        generateHeightMap(w, h, p)

    local painted, is_lake, river_paths =
        traceRiversAndLakes(w, h, p, heightmap, colormap, pre_ridge)

    local biome_colormap, biome_data, suitability_colormap, raw_suit =
        assignBiomesAndSuitability(w, h, p, heightmap, pre_ridge, moisture_map, painted, is_lake)

    local continent_colormap, continent_map, continents,
          region_colormap, region_map, regions_list =
        detectContinentsAndRegions(w, h, p, heightmap, pre_ridge, painted)

    return {
        heightmap            = heightmap,
        colormap             = colormap,
        moisture_map         = moisture_map,
        biome_colormap       = biome_colormap,
        biome_data           = biome_data,
        suitability_colormap = suitability_colormap,
        suitability_scores   = raw_suit,
        continent_colormap   = continent_colormap,
        continent_map        = continent_map,
        continents           = continents,
        region_colormap      = region_colormap,
        region_map           = region_map,
        regions_list         = regions_list,
        river_paths          = river_paths,
    }
end

return WorldNoiseService
