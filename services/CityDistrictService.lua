-- services/CityDistrictService.lua
-- Portable district flood-fill: given city bounds + POIs, heightmap, and biome
-- data, assigns every city sub-cell to a POI district and returns color tables.
-- Zero love.* imports. Zero game references. Pure computation.

local WorldGenUtils = require("utils.WorldGenUtils")

local CityDistrictService = {}

-- Distinct colours for up to 10 POIs. Index 1 = downtown (gold), rest = districts.
local DISTRICT_PALETTE = {
    {1.00, 0.82, 0.15},   -- downtown: gold
    {0.28, 0.55, 0.92},   -- blue
    {0.22, 0.78, 0.42},   -- green
    {0.88, 0.32, 0.22},   -- red
    {0.72, 0.38, 0.88},   -- purple
    {0.92, 0.56, 0.18},   -- orange
    {0.20, 0.80, 0.84},   -- cyan
    {0.88, 0.28, 0.60},   -- pink
    {0.62, 0.88, 0.18},   -- lime
    {0.44, 0.28, 0.88},   -- indigo
}

-- Multi-source Dijkstra at sub-cell resolution (3×3 per world cell).
-- Sub-cell elevations come from WorldGenUtils.subcell_elev_at(), which adds
-- noise on top of the world-cell baseline. This gives genuine intra-cell
-- elevation variation, so the flood-fill can draw district boundaries that
-- meander through sub-cells.
-- Returns district_map ([sub_cell_idx] = poi_idx) and color table ([poi_idx] = {r,g,b}).
local function genDistrictsForCity(city_idx, bounds, pois, heightmap, biome_data,
                                    w, h, params, math_fns)
    if not bounds or not pois or #pois == 0 then return {}, {} end

    local sub_w = w * 3
    local sub_h = h * 3
    local hmap  = heightmap
    local bdata = biome_data
    local noise = math_fns.noise

    local function in_bounds(gscx, gscy)
        local wx = math.floor(gscx / 3)
        local wy = math.floor(gscy / 3)
        if wx < 0 or wx >= w or wy < 0 or wy >= h then return false end
        return bounds[wy * w + wx + 1] == true
    end

    -- Binary min-heap (same pattern used throughout this file)
    local heap = {}
    local function hpush(f, i)
        heap[#heap+1] = {f, i}
        local pos = #heap
        while pos > 1 do
            local par = math.floor(pos / 2)
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

    local dist  = {}
    local owner = {}  -- [sub_cell_idx] = poi_idx

    -- Seed each POI at the centre sub-cell of its world cell
    for poi_idx, poi in ipairs(pois) do
        local gscx = (poi.x - 1) * 3 + 1
        local gscy = (poi.y - 1) * 3 + 1
        if in_bounds(gscx, gscy) then
            local sci  = gscy * sub_w + gscx + 1
            dist[sci]  = 0
            owner[sci] = poi_idx
            hpush(0, sci)
        end
    end

    local dirs = {-1, 1, -sub_w, sub_w}

    while #heap > 0 do
        local node = hpop()
        local d, sci = node[1], node[2]
        if dist[sci] == d then
            local gscx   = (sci - 1) % sub_w
            local gscy   = math.floor((sci - 1) / sub_w)
            local from_e = WorldGenUtils.subcell_elev_at(gscx, gscy, hmap, noise)

            for _, dir in ipairs(dirs) do
                local ni = sci + dir
                if ni >= 1 and ni <= sub_w * sub_h then
                    local nx2 = (ni - 1) % sub_w
                    local ny2 = math.floor((ni - 1) / sub_w)
                    local valid = (dir == -1     and nx2 == gscx - 1) or
                                  (dir ==  1     and nx2 == gscx + 1) or
                                  (dir == -sub_w and ny2 == gscy - 1) or
                                  (dir ==  sub_w and ny2 == gscy + 1)
                    if valid and in_bounds(nx2, ny2) then
                        local to_e   = WorldGenUtils.subcell_elev_at(nx2, ny2, hmap, noise)
                        local elev_d = math.abs(to_e - from_e)
                        -- elev_d now includes sub-cell noise variation,
                        -- so intra-cell steps have genuine cost differences
                        local cost   = 1.0 + elev_d * 12.0

                        local wni = math.floor(ny2 / 3) * w + math.floor(nx2 / 3) + 1
                        local bd  = bdata and bdata[wni]
                        if bd and (bd.is_river or bd.is_lake) then cost = cost + 6.0 end

                        local nd = d + cost
                        if not dist[ni] or nd < dist[ni] then
                            dist[ni]  = nd
                            owner[ni] = owner[sci]
                            hpush(nd, ni)
                        end
                    end
                end
            end
        end
    end

    -- Enforce per-district cell budget.
    -- effective budget = max(floor(total_owned * pct), min_cells)
    -- Trim strategy: sort the district's cells by Euclidean distance from its POI
    -- seed (farthest first), mark the excess as nil, then BFS from all remaining
    -- owned cells to re-fill the vacated territory.  Geographic distance reliably
    -- identifies outer cells; the BFS fill lets adjacent districts absorb them
    -- without needing a direct non-district neighbour at the moment of removal.
    -- Expand: BFS outward from boundary until minimum is met.
    local p = params
    local total_owned = 0
    for _ in pairs(owner) do total_owned = total_owned + 1 end

    local function apply_district_budget(target_poi, pct, min_cells)
        local budget = math.max(min_cells, math.floor(total_owned * pct))

        local poi    = pois[target_poi]
        local seed_x = (poi.x - 1) * 3 + 1
        local seed_y = (poi.y - 1) * 3 + 1

        local cells = {}
        for sci, pid in pairs(owner) do
            if pid == target_poi then
                local cx2 = (sci - 1) % sub_w
                local cy2 = math.floor((sci - 1) / sub_w)
                local dx, dy = cx2 - seed_x, cy2 - seed_y
                cells[#cells+1] = {sci=sci, d2=dx*dx + dy*dy}
            end
        end

        if #cells > budget then
            -- Sort farthest-first, vacate excess cells
            table.sort(cells, function(a, b) return a.d2 > b.d2 end)
            for i = 1, #cells - budget do
                owner[cells[i].sci] = nil
            end

            -- BFS from every still-owned cell to fill the vacated territory
            local q    = {}
            local in_q = {}
            for sci, pid in pairs(owner) do
                q[#q+1]  = sci
                in_q[sci] = true
            end
            local qi = 1
            while qi <= #q do
                local sci = q[qi]; qi = qi + 1
                local cx2 = (sci - 1) % sub_w
                local cy2 = math.floor((sci - 1) / sub_w)
                for _, dir in ipairs(dirs) do
                    local ni = sci + dir
                    if ni >= 1 and ni <= sub_w * sub_h then
                        local nx2 = (ni - 1) % sub_w
                        local ny2 = math.floor((ni - 1) / sub_w)
                        local valid = (dir == -1     and nx2 == cx2 - 1) or
                                      (dir ==  1     and nx2 == cx2 + 1) or
                                      (dir == -sub_w and ny2 == cy2 - 1) or
                                      (dir ==  sub_w and ny2 == cy2 + 1)
                        if valid and owner[ni] == nil and not in_q[ni]
                                and in_bounds(nx2, ny2) then
                            owner[ni] = owner[sci]
                            q[#q+1]   = ni
                            in_q[ni]  = true
                        end
                    end
                end
            end

        elseif #cells < budget then
            -- BFS-expand outward from the district boundary
            local frontier = {}
            local in_f     = {}
            for _, dc in ipairs(cells) do
                local sci = dc.sci
                local cx2 = (sci - 1) % sub_w
                local cy2 = math.floor((sci - 1) / sub_w)
                for _, dir in ipairs(dirs) do
                    local ni = sci + dir
                    if ni >= 1 and ni <= sub_w * sub_h then
                        local nx2 = (ni - 1) % sub_w
                        local ny2 = math.floor((ni - 1) / sub_w)
                        local valid = (dir == -1     and nx2 == cx2 - 1) or
                                      (dir ==  1     and nx2 == cx2 + 1) or
                                      (dir == -sub_w and ny2 == cy2 - 1) or
                                      (dir ==  sub_w and ny2 == cy2 + 1)
                        if valid and owner[ni] and owner[ni] ~= target_poi and not in_f[ni] then
                            frontier[#frontier+1] = ni
                            in_f[ni] = true
                        end
                    end
                end
            end
            local fi    = 1
            local count = #cells
            while count < budget and fi <= #frontier do
                local sci = frontier[fi]; fi = fi + 1
                if owner[sci] and owner[sci] ~= target_poi then
                    owner[sci] = target_poi
                    count = count + 1
                    local cx2 = (sci - 1) % sub_w
                    local cy2 = math.floor((sci - 1) / sub_w)
                    for _, dir in ipairs(dirs) do
                        local ni = sci + dir
                        if ni >= 1 and ni <= sub_w * sub_h then
                            local nx2 = (ni - 1) % sub_w
                            local ny2 = math.floor((ni - 1) / sub_w)
                            local valid = (dir == -1     and nx2 == cx2 - 1) or
                                          (dir ==  1     and nx2 == cx2 + 1) or
                                          (dir == -sub_w and ny2 == cy2 - 1) or
                                          (dir ==  sub_w and ny2 == cy2 + 1)
                            if valid and owner[ni] and owner[ni] ~= target_poi and not in_f[ni] then
                                frontier[#frontier+1] = ni
                                in_f[ni] = true
                            end
                        end
                    end
                end
            end
        end
    end

    -- Apply downtown budget: % cap with hard minimum in absolute sub-cells
    apply_district_budget(1, p.downtown_pct or 0.05, p.downtown_min_cells or 11)

    -- Build colour table (index 1 = downtown gold, rest cycle through palette)
    local colors = {}
    for poi_idx = 1, #pois do
        colors[poi_idx] = DISTRICT_PALETTE[((poi_idx - 1) % #DISTRICT_PALETTE) + 1]
    end

    return owner, colors
end

-- Generate district maps and color tables for all cities.
-- Returns: city_district_maps ([city_idx] = owner), city_district_colors ([city_idx] = colors)
function CityDistrictService.genAllDistricts(
    city_locations, city_bounds_list, city_pois_list,
    heightmap, biome_data, w, h, params, math_fns
)
    local maps   = {}
    local colors = {}
    for idx = 1, #(city_locations or {}) do
        local bounds = city_bounds_list and city_bounds_list[idx]
        local pois   = city_pois_list   and city_pois_list[idx]
        maps[idx], colors[idx] = genDistrictsForCity(
            idx, bounds, pois, heightmap, biome_data, w, h, params, math_fns
        )
    end
    return maps, colors
end

return CityDistrictService
