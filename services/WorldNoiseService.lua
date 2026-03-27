-- services/WorldNoiseService.lua
-- Pure FBM noise → normalized heightmap + colormap.
-- Multiple islands emerge naturally from noise topology wherever peaks exceed sea level.
-- No artificial island placement. sea level is implicitly the coast_max threshold.

local WorldNoiseService = {}

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

-- Biome name — mirrors biome_color_climate exactly, returns string label.
local function biome_name_climate(h, temp, wet, p)
    if h < p.deep_ocean_max then return "Deep Ocean" end
    if h < p.ocean_max      then return "Ocean" end
    if h < p.coast_max      then return "Beach" end
    if h >= p.mountain_max  then return "Snow Cap" end
    if h >= p.highland_max  then
        if temp < 0.25 then return "Frozen Rock" end
        return "Mountain Rock"
    end
    if h >= p.forest_max then
        if temp < 0.22 then return "Cold Highland" end
        if temp < 0.45 then return "Boreal Highland" end
        return "Highland"
    end
    if h < p.plains_max and wet > 0.72 and temp > 0.35 then
        if temp > 0.62 then return "Tropical Swamp" end
        return "Swamp"
    end
    if temp < 0.22 then
        if wet > 0.50 then return "Boreal / Taiga" end
        return "Tundra"
    elseif temp < 0.45 then
        if wet > 0.60 then return "Temp. Rainforest" end
        if wet > 0.35 then return "Temp. Forest" end
        if wet > 0.15 then return "Grassland" end
        return "Shrubland"
    elseif temp < 0.68 then
        if wet > 0.60 then return "Subtropical Forest" end
        if wet > 0.35 then return "Woodland" end
        if wet > 0.15 then return "Savanna" end
        return "Semi-arid"
    else
        if wet > 0.55 then return "Jungle" end
        if wet > 0.30 then return "Tropical Forest" end
        if wet > 0.12 then return "Tropical Savanna" end
        return "Desert"
    end
end

-- Climate-based biome colors.
-- temp: 0=arctic, 1=tropical (latitude + elevation)
-- wet:  0=desert, 1=swamp/jungle (water proximity + moisture noise)
local function biome_color_climate(h, temp, wet, p)
    if h < p.deep_ocean_max then return { 0.04, 0.08, 0.30 } end
    if h < p.ocean_max      then return { 0.07, 0.15, 0.45 } end
    if h < p.coast_max      then return { 0.76, 0.70, 0.48 } end  -- beach

    -- Snow caps (elevation always wins)
    if h >= p.mountain_max then return { 0.88, 0.90, 0.95 } end

    -- Mountain rock
    if h >= p.highland_max then
        if temp < 0.25 then return { 0.65, 0.66, 0.70 } end  -- frozen rock
        return { 0.52, 0.48, 0.42 }
    end

    -- Highlands / uplands
    if h >= p.forest_max then
        if temp < 0.22 then return { 0.58, 0.62, 0.55 } end  -- cold tundra highland
        if temp < 0.45 then return { 0.30, 0.42, 0.24 } end  -- boreal highland
        return { 0.40, 0.44, 0.26 }                           -- dry highland
    end

    -- Swamp: low elevation + very wet + warm enough
    if h < p.plains_max and wet > 0.72 and temp > 0.35 then
        if temp > 0.62 then return { 0.18, 0.26, 0.12 } end  -- tropical swamp
        return { 0.22, 0.30, 0.16 }                           -- temperate swamp
    end

    -- Land biome matrix: temperature × wetness
    if temp < 0.22 then
        -- Arctic
        if wet > 0.50 then return { 0.22, 0.38, 0.24 } end   -- boreal/taiga
        return { 0.60, 0.64, 0.52 }                           -- tundra
    elseif temp < 0.45 then
        -- Cold temperate
        if wet > 0.60 then return { 0.18, 0.40, 0.16 } end   -- temperate rainforest
        if wet > 0.35 then return { 0.24, 0.46, 0.18 } end   -- temperate forest
        if wet > 0.15 then return { 0.42, 0.58, 0.22 } end   -- grassland
        return { 0.52, 0.46, 0.24 }                           -- shrubland
    elseif temp < 0.68 then
        -- Warm temperate
        if wet > 0.60 then return { 0.16, 0.44, 0.12 } end   -- subtropical forest
        if wet > 0.35 then return { 0.34, 0.54, 0.20 } end   -- woodland
        if wet > 0.15 then return { 0.65, 0.60, 0.24 } end   -- savanna
        return { 0.76, 0.64, 0.32 }                           -- semi-arid
    else
        -- Tropical
        if wet > 0.55 then return { 0.08, 0.30, 0.06 } end   -- jungle
        if wet > 0.30 then return { 0.20, 0.48, 0.12 } end   -- tropical forest
        if wet > 0.12 then return { 0.68, 0.62, 0.22 } end   -- tropical savanna
        return { 0.80, 0.66, 0.28 }                           -- desert
    end
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

function WorldNoiseService.generate(w, h, p)
    local sx = p.seed_x or 0
    local sy = p.seed_y or 0
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

    -- Pass 3: Source-tracing rivers with fill-and-spill lakes.
    --
    -- Pick N well-spaced highland sources.  Trace each downstream via strict
    -- D8 flow.  When a trace hits a pit (inland depression), flood-fill the
    -- basin upward until the lowest rim is found, paint the basin as a lake,
    -- then continue the river from that rim — rivers never end mid-land.
    -- Two traces that reach the same cell merge naturally.
    -- Hoisted so Pass 4 (biome map) can read which cells are water.
    local RIVER_COLOR = { 0.22, 0.52, 0.88 }
    local LAKE_COLOR  = { 0.07, 0.20, 0.55 }
    local painted = {}   -- river + lake cell indices
    local is_lake = {}   -- lake-only subset for merging

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
        for _, src in ipairs(sources) do
            local i     = src.i
            local steps = 0
            while i and i > 0 and steps < w * h do
                steps = steps + 1
                if is_ocean[i]  then break end
                if painted[i]   then break end
                painted[i] = true
                local cy = math.floor((i - 1) / w) + 1
                local cx = (i - 1) % w + 1
                colormap[cy][cx] = RIVER_COLOR
                local nxt = choose_next(i)
                if nxt == nil then
                    nxt = fill_and_spill(i)
                    if nxt == nil then nxt = carve_step(i) end
                end
                i = nxt
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

    -- Pass 4: Water-proximity biome map.
    -- Multi-source BFS from all river/lake cells.  Cells close to water get
    -- high fertility (lush green); cells far away get low fertility (arid brown).
    -- Ocean and coast bands are rendered identically to the height view.
    local river_influence = math.max(1, p.river_influence or 30)
    local biome_colormap  = {}
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
        local biome_data   = {}   -- flat array [i] = { name, temp, wet, is_river, is_lake }
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
                    biome_colormap[y][x] = biome_color_climate(h_val, temp, wet, p)
                    biome_data[i] = { name = biome_name_climate(h_val, temp, wet, p),
                                      temp = temp, wet = wet, is_river = false, is_lake = false }
                end
            end
        end
        return { heightmap = heightmap, colormap = colormap,
                 biome_colormap = biome_colormap, biome_data = biome_data }
    end

end

return WorldNoiseService
