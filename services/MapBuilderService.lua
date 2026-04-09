-- services/MapBuilderService.lua
-- Portable city map assembly: WFC zone grid, road network, island connectivity,
-- sub-cell grid, and city map construction.
-- Zero love.* imports. Receives math_fns for any random calls.

local WorldGenUtils = require("utils.WorldGenUtils")

local MapBuilderService = {}

-- ── WFC zone grid + district type assignment ─────────────────────────────────
-- Returns: zone_grid, zone_offsets, district_types, downtown_subcells, all_city_plots
local function buildZoneGrid(city_idx, grid, ctx, dmap, pois, biome_data, pre_district_types, math_fns)
    local sub_cw    = ctx.sub_cw;    local sub_ch    = ctx.sub_ch
    local gscx_off  = ctx.gscx_off;  local gscy_off  = ctx.gscy_off
    local sw        = ctx.sw;        local w         = ctx.w
    local city_mn_x = ctx.city_mn_x; local city_mn_y = ctx.city_mn_y

    local random    = math_fns.random

    local WFC = require("lib.wfc")
    local ZT  = require("data.zones")

    dmap = dmap or {}

    -- ── District type assignment (lazy — skip if pre_district_types supplied) ──
    local district_types = pre_district_types
    if not district_types then
        local rules   = ZT.DISTRICT_RULES or {}
        local choices = ZT.RANDOM_DISTRICT_TYPES

        local neighbors = {}
        for sci, poi_idx in pairs(dmap) do
            for _, offset in ipairs({1, sw}) do
                local nbr = dmap[sci + offset]
                if nbr and nbr ~= poi_idx then
                    if not neighbors[poi_idx] then neighbors[poi_idx] = {} end
                    if not neighbors[nbr]     then neighbors[nbr]     = {} end
                    neighbors[poi_idx][nbr] = true
                    neighbors[nbr][poi_idx] = true
                end
            end
        end

        local bdata     = biome_data or {}
        local poi_biome = {}
        for sci, poi_idx in pairs(dmap) do
            if not poi_biome[poi_idx] then
                poi_biome[poi_idx] = { total=0, river=0, lake=0, forest=0, beach=0, desert=0 }
            end
            local t = poi_biome[poi_idx]
            t.total = t.total + 1
            local sci0  = sci - 1
            local gscx2 = sci0 % sw
            local gscy2 = math.floor(sci0 / sw)
            local lscx  = gscx2 - gscx_off
            local lscy  = gscy2 - gscy_off
            local wcx   = city_mn_x + math.floor(lscx / 3)
            local wcy   = city_mn_y + math.floor(lscy / 3)
            local bd    = bdata[(wcy - 1) * w + wcx]
            if bd then
                if bd.is_river then t.river = t.river + 1 end
                if bd.is_lake  then t.lake  = t.lake  + 1 end
                local bn = bd.name or ""
                if bn:find("Forest") or bn == "Woodland" or bn == "Jungle"
                   or bn:find("Rainforest") or bn:find("Taiga") then
                    t.forest = t.forest + 1
                end
                if bn == "Beach"                     then t.beach  = t.beach  + 1 end
                if bn == "Desert" or bn:find("arid") then t.desert = t.desert + 1 end
            end
        end

        local type_pool = {}
        for _, c in ipairs(choices) do type_pool[c] = 1.0 end

        local dtypes = {[1] = "downtown"}

        local order = {}
        for i = 2, #pois do order[#order+1] = i end
        for i = #order, 2, -1 do
            local j = random(1, i)
            order[i], order[j] = order[j], order[i]
        end

        for _, poi_i in ipairs(order) do
            local pb      = poi_biome[poi_i] or { total=1, river=0, lake=0, forest=0, beach=0, desert=0 }
            local total_b = math.max(1, pb.total)
            local rf = pb.river  / total_b
            local bf = pb.beach  / total_b
            local ff = pb.forest / total_b
            local df = pb.desert / total_b
            local wf = rf + (pb.lake / total_b) + bf

            local candidates, tw = {}, 0
            for _, c in ipairs(choices) do
                if (c ~= "riverfront" or rf >= 0.05) and
                   (c ~= "waterfront" or wf >= 0.05) then
                    local wt = type_pool[c]
                    if c == "riverfront"      and rf >= 0.05 then wt = wt * math.min(1 + rf * 1.5, 2.0) end
                    if c == "waterfront"      and wf >= 0.05 then wt = wt * math.min(1 + wf * 1.5, 2.0) end
                    if c == "rural_outskirts" and ff >= 0.2  then wt = wt * math.min(1 + ff * 1.5, 2.0) end
                    if c == "industrial"      and df >= 0.3  then wt = wt * math.min(1 + df * 1.5, 2.0) end
                    for nbr in pairs(neighbors[poi_i] or {}) do
                        if dtypes[nbr] then
                            for _, cant in ipairs((rules[c] and rules[c].cannot) or {}) do
                                if cant == dtypes[nbr] then wt = wt * 0.3; break end
                            end
                        end
                    end
                    if wt > 0 then candidates[#candidates+1] = {t=c, w=wt}; tw = tw + wt end
                end
            end

            local chosen
            if tw > 0 then
                local rand, cumw = random() * tw, 0
                chosen = candidates[#candidates].t
                for _, cand in ipairs(candidates) do
                    cumw = cumw + cand.w
                    if rand <= cumw then chosen = cand.t; break end
                end
            else
                chosen = choices[random(1, #choices)]
            end

            dtypes[poi_i] = chosen
            type_pool[chosen] = type_pool[chosen] * 0.15
        end

        district_types = dtypes
    end

    local bdata2 = biome_data or {}

    local plot_set = {}
    local all_city_plots = {}
    for lscy = 0, sub_ch - 1 do
        local gy = lscy + 1
        for lscx = 0, sub_cw - 1 do
            local gx = lscx + 1
            local t = grid[gy][gx].type
            if t == "plot" or t == "downtown_plot" or t == "river" then
                plot_set[gy * 100000 + gx] = true
                if t ~= "river" then
                    all_city_plots[#all_city_plots+1] = {x=gx, y=gy}
                end
            end
        end
    end

    local wfc = WFC.new(sub_cw, sub_ch, ZT.STATES, ZT.ADJACENCY)
    for lscy = 0, sub_ch - 1 do
        local gy = lscy + 1
        for lscx = 0, sub_cw - 1 do
            local gx = lscx + 1
            if not plot_set[gy * 100000 + gx] then
                for _, s in ipairs(ZT.STATES) do wfc.grid[gy][gx][s] = (s == "none") end
                wfc.entropy_grid[gy][gx] = 1
            elseif grid[gy][gx].type == "river" then
                for _, s in ipairs(ZT.STATES) do wfc.grid[gy][gx][s] = (s == "river") end
                wfc.entropy_grid[gy][gx] = 1
            else
                local gscx2   = gscx_off + lscx
                local gscy2   = gscy_off + lscy
                local sci     = gscy2 * sw + gscx2 + 1
                local poi_idx = dmap[sci]
                local dtype   = (poi_idx and district_types[poi_idx]) or "residential"
                local base_wt = ZT.DISTRICT_WEIGHTS[dtype] or ZT.DISTRICT_WEIGHTS.residential
                local wcx2    = city_mn_x + math.floor(lscx / 3)
                local wcy2    = city_mn_y + math.floor(lscy / 3)
                local ci2     = (wcy2 - 1) * w + wcx2
                local bd      = bdata2[ci2]
                local bmul    = (bd and bd.name and ZT.BIOME_MULTS[bd.name]) or {}
                if bd and (bd.is_river or bd.is_lake) then
                    bmul = {}
                    if bd.name and ZT.BIOME_MULTS[bd.name] then
                        for k, v in pairs(ZT.BIOME_MULTS[bd.name]) do bmul[k] = v end
                    end
                    bmul.waterfront     = (bmul.waterfront     or 1.0) * 2.5
                    bmul.restaurant_row = (bmul.restaurant_row or 1.0) * 1.8
                    bmul.retail_strip   = (bmul.retail_strip   or 1.0) * 1.3
                end
                for _, s in ipairs(ZT.STATES) do
                    local wt = s == "none" and 0 or ((base_wt[s] or 0) * (bmul[s] or 1.0))
                    WFC.setWeight(wfc, gx, gy, s, wt > 0 and math.max(0.01, wt) or 0)
                end
                local bn2 = bd and bd.name or ""
                if bn2:find("Forest") or bn2 == "Woodland" or bn2:find("Jungle")
                   or bn2:find("Rainforest") or bn2:find("Taiga") then
                    WFC.setWeight(wfc, gx, gy, "forest_clearing", 3.0)
                end
                if bn2 == "Swamp" or bn2:find("Wetland") or bn2:find("Marsh")
                   or bn2:find("Mangrove") then
                    WFC.setWeight(wfc, gx, gy, "wetlands", 3.0)
                end
            end
        end
    end
    wfc.coherence_factor = 6.0
    WFC.solve(wfc)
    local result = WFC.getResult(wfc)

    for lscy = 0, sub_ch - 1 do
        local gy = lscy + 1
        for lscx = 0, sub_cw - 1 do
            local gx = lscx + 1
            if plot_set[gy * 100000 + gx] and not result[gy][gx] then
                if grid[gy][gx].type == "river" then
                    result[gy][gx] = "river"
                else
                    local gscx2   = gscx_off + lscx
                    local gscy2   = gscy_off + lscy
                    local sci     = gscy2 * sw + gscx2 + 1
                    local poi_idx = dmap[sci]
                    local dtype   = (poi_idx and district_types[poi_idx]) or "residential"
                    local base_wt = ZT.DISTRICT_WEIGHTS[dtype] or ZT.DISTRICT_WEIGHTS.residential
                    local best, best_w = ZT.STATES[1], 0
                    for _, s in ipairs(ZT.STATES) do
                        if s ~= "none" and (base_wt[s] or 0) > best_w then best = s; best_w = base_wt[s] end
                    end
                    result[gy][gx] = best
                end
            end
        end
    end

    local zone_grid    = result
    local zone_offsets = {x = gscx_off, y = gscy_off}

    local sw2 = w * 3
    local dt_cells = {}
    for lscy = 0, sub_ch - 1 do
        local gscy2 = gscy_off + lscy
        local gy    = lscy + 1
        for lscx = 0, sub_cw - 1 do
            local gscx2 = gscx_off + lscx
            local sci2  = gscy2 * sw2 + gscx2 + 1
            if dmap[sci2] == 1 then
                if not dt_cells[gy] then dt_cells[gy] = {} end
                dt_cells[gy][lscx + 1] = true
            end
        end
    end

    return zone_grid, zone_offsets, district_types, dt_cells, all_city_plots
end

-- ── Island connectivity repair ────────────────────────────────────────────────
local function fixIslandConnectivity(zone_grid, grid, sub_cw, sub_ch, zone_seg_v, zone_seg_h, new_nodes)
    local zg = zone_grid
    if not zg then return end

    local ZT = require("data.zones")
    local _road_z0 = ZT.STATES[1]
    local _road_z1 = _road_z0
    for _, s in ipairs(ZT.STATES) do
        if s ~= "none" and s ~= _road_z0 then _road_z1 = s; break end
    end

    local reachable = {}
    local rq = {}
    for ry2, row in pairs(new_nodes) do
        for rx2 in pairs(row) do
            local t2 = grid[ry2 + 1] and grid[ry2 + 1][rx2 + 1]
            if t2 and (t2.type == "arterial" or t2.type == "highway") then
                local k2 = ry2 * 100000 + rx2
                if not reachable[k2] then reachable[k2] = true; rq[#rq + 1] = {rx2, ry2} end
            end
        end
    end
    local rqi = 1
    while rqi <= #rq do
        local rx2, ry2 = rq[rqi][1], rq[rqi][2]; rqi = rqi + 1
        local checks = {
            {rx2,   ry2-1, ry2 >= 1 and zone_seg_v[ry2] and zone_seg_v[ry2][rx2]},
            {rx2,   ry2+1, zone_seg_v[ry2+1] and zone_seg_v[ry2+1][rx2]},
            {rx2+1, ry2,   zone_seg_h[ry2] and zone_seg_h[ry2][rx2+1]},
            {rx2-1, ry2,   rx2 >= 1 and zone_seg_h[ry2] and zone_seg_h[ry2][rx2]},
        }
        for _, c in ipairs(checks) do
            local nx2, ny2, ok = c[1], c[2], c[3]
            if ok and new_nodes[ny2] and new_nodes[ny2][nx2] then
                local nk = ny2 * 100000 + nx2
                if not reachable[nk] then reachable[nk] = true; rq[#rq + 1] = {nx2, ny2} end
            end
        end
    end

    local par = {}
    local pq = {}
    for ry2, row in pairs(new_nodes) do
        for rx2 in pairs(row) do
            local k2 = ry2 * 100000 + rx2
            if reachable[k2] then par[k2] = true; pq[#pq + 1] = {rx2, ry2} end
        end
    end
    local pqi = 1
    while pqi <= #pq do
        local rx2, ry2 = pq[pqi][1], pq[pqi][2]; pqi = pqi + 1
        for _, d in ipairs({{0,-1},{0,1},{-1,0},{1,0}}) do
            local nx2, ny2 = rx2 + d[1], ry2 + d[2]
            if nx2 >= 0 and nx2 <= sub_cw - 2 and ny2 >= 0 and ny2 <= sub_ch - 2 then
                local nk = ny2 * 100000 + nx2
                if not par[nk] then par[nk] = {rx2, ry2}; pq[#pq + 1] = {nx2, ny2} end
            end
        end
    end

    local function makeVisible(gr1, gc1, gr2, gc2)
        if not zg[gr1] then zg[gr1] = {} end
        if not zg[gr2] then zg[gr2] = {} end
        local z1 = zg[gr1][gc1]
        local z2 = zg[gr2][gc2]
        if not z1 or z1 == "none" then z1 = _road_z0; zg[gr1][gc1] = z1 end
        if not z2 or z2 == "none" or z2 == z1 then
            zg[gr2][gc2] = (z1 ~= _road_z1) and _road_z1 or _road_z0
        end
    end

    local function tileIsPlot(gx, gy)
        local t = grid[gy] and grid[gy][gx] and grid[gy][gx].type
        return t == "plot" or t == "downtown_plot"
    end

    local function addSeg(rx1, ry1, rx2, ry2)
        if rx2 == rx1 + 1 then
            if tileIsPlot(rx1+1, ry1) and tileIsPlot(rx1+1, ry1+1) then
                if not zone_seg_h[ry1] then zone_seg_h[ry1] = {} end
                zone_seg_h[ry1][rx1+1] = true; makeVisible(ry1, rx1+1, ry1+1, rx1+1)
            end
        elseif rx2 == rx1 - 1 then
            if tileIsPlot(rx1, ry1) and tileIsPlot(rx1, ry1+1) then
                if not zone_seg_h[ry1] then zone_seg_h[ry1] = {} end
                zone_seg_h[ry1][rx1] = true; makeVisible(ry1, rx1, ry1+1, rx1)
            end
        elseif ry2 == ry1 + 1 then
            if tileIsPlot(rx1, ry1+1) and tileIsPlot(rx1+1, ry1+1) then
                if not zone_seg_v[ry1+1] then zone_seg_v[ry1+1] = {} end
                zone_seg_v[ry1+1][rx1] = true; makeVisible(ry1+1, rx1, ry1+1, rx1+1)
            end
        elseif ry2 == ry1 - 1 then
            if tileIsPlot(rx1, ry1) and tileIsPlot(rx1+1, ry1) then
                if not zone_seg_v[ry1] then zone_seg_v[ry1] = {} end
                zone_seg_v[ry1][rx1] = true; makeVisible(ry1, rx1, ry1, rx1+1)
            end
        end
        if not new_nodes[ry1] then new_nodes[ry1] = {} end; new_nodes[ry1][rx1] = true
        if not new_nodes[ry2] then new_nodes[ry2] = {} end; new_nodes[ry2][rx2] = true
    end

    local unreachable = {}
    for ry2, row in pairs(new_nodes) do
        for rx2 in pairs(row) do
            if not reachable[ry2 * 100000 + rx2] then
                unreachable[#unreachable + 1] = {rx2, ry2}
            end
        end
    end
    for _, unode in ipairs(unreachable) do
        local ux, uy = unode[1], unode[2]
        if not reachable[uy * 100000 + ux] then
            local cx, cy = ux, uy
            for _ = 1, sub_cw + sub_ch do
                local ck = cy * 100000 + cx
                if reachable[ck] then break end
                local p = par[ck]
                if not p or p == true then break end
                addSeg(cx, cy, p[1], p[2])
                reachable[ck] = true
                cx, cy = p[1], p[2]
            end
        end
    end
end

-- ── Road network ──────────────────────────────────────────────────────────────
-- Returns: road data fields (mutates new_map directly)
local function buildRoadNetwork(new_map, grid, zone_grid, ctx, street_map, math_fns)
    local sub_cw    = ctx.sub_cw;    local sub_ch    = ctx.sub_ch
    local gscx_off  = ctx.gscx_off;  local gscy_off  = ctx.gscy_off
    local random    = math_fns.random

    local road_v_rxs = {}
    local road_h_rys = {}
    local road_nodes = {}

    do
        local miss_cx, miss_cy = {}, {}
        if street_map then
            for key in pairs(street_map.v or {}) do
                local cx   = math.floor(key / 1000)
                local lscx = cx * 3 - gscx_off
                if lscx >= 0 and lscx < sub_cw then road_v_rxs[lscx] = true
                else miss_cx[cx] = true end
            end
            for key in pairs(street_map.h or {}) do
                local cy   = math.floor(key / 1000)
                local lscy = cy * 3 - gscy_off
                if lscy >= 0 and lscy < sub_ch then road_h_rys[lscy] = true
                else miss_cy[cy] = true end
            end
        end
        local miss_cx_list, miss_cy_list = {}, {}
        for cx in pairs(miss_cx) do miss_cx_list[#miss_cx_list+1] = cx end
        for cy in pairs(miss_cy) do miss_cy_list[#miss_cy_list+1] = cy end
        table.sort(miss_cx_list); table.sort(miss_cy_list)
        if #miss_cx_list > 0 then
            print(string.format("DEBUG v-streets OUT OF RANGE cx (gscx_off=%d,sub_cw=%d): %s",
                gscx_off, sub_cw, table.concat(miss_cx_list, ",")))
        end
        if #miss_cy_list > 0 then
            print(string.format("DEBUG h-streets OUT OF RANGE cy (gscy_off=%d,sub_ch=%d): %s",
                gscy_off, sub_ch, table.concat(miss_cy_list, ",")))
        end
    end

    do
        if street_map then
            for key in pairs(street_map.v or {}) do
                local cx    = math.floor(key / 1000)
                local wy    = key % 1000
                local lscx  = cx * 3 - gscx_off
                local lscy0 = (wy - 1) * 3 - gscy_off
                if lscx >= 0 and lscx < sub_cw then
                    for dlscy = 0, 2 do
                        local lscy = lscy0 + dlscy
                        if lscy >= 0 and lscy < sub_ch then
                            if not road_nodes[lscy] then road_nodes[lscy] = {} end
                            road_nodes[lscy][lscx] = true
                        end
                    end
                end
            end
            for key in pairs(street_map.h or {}) do
                local cy    = math.floor(key / 1000)
                local wx    = key % 1000
                local lscy  = cy * 3 - gscy_off
                local lscx0 = (wx - 1) * 3 - gscx_off
                if lscy >= 0 and lscy < sub_ch then
                    for dlscx = 0, 2 do
                        local lscx = lscx0 + dlscx
                        if lscx >= 0 and lscx < sub_cw then
                            if not road_nodes[lscy] then road_nodes[lscy] = {} end
                            road_nodes[lscy][lscx] = true
                        end
                    end
                end
            end
        end
    end

    local function is_road_type(x, y)
        if x < 1 or x > sub_cw or y < 1 or y > sub_ch then return false end
        local tt = grid[y] and grid[y][x] and grid[y][x].type
        return tt == "arterial" or tt == "highway"
    end
    for gy = 1, sub_ch do
        for gx = 1, sub_cw do
            local t = grid[gy][gx].type
            if t == "arterial" or t == "highway" then
                for dy2 = 0, 1 do
                    for dx2 = 0, 1 do
                        local rx2 = gx - 1 + dx2
                        local ry2 = gy - 1 + dy2
                        if rx2 >= 0 and rx2 < sub_cw and ry2 >= 0 and ry2 < sub_ch then
                            local nx1, ny1 = gx + dx2 - 1, gy
                            local nx2, ny2 = gx,            gy + dy2 - 1
                            local nx3, ny3 = gx + dx2 - 1, gy + dy2 - 1
                            local inner = is_road_type(nx1, ny1) or
                                          is_road_type(nx2, ny2) or
                                          is_road_type(nx3, ny3)
                            local on_street = road_v_rxs[rx2] or road_h_rys[ry2]
                            if inner or on_street then
                                if not road_nodes[ry2] then road_nodes[ry2] = {} end
                                road_nodes[ry2][rx2] = true
                            end
                        end
                    end
                end
            end
        end
    end

    new_map.road_v_rxs   = road_v_rxs
    new_map.road_h_rys   = road_h_rys
    new_map.road_nodes   = road_nodes
    new_map.street_v_rxs = road_v_rxs
    new_map.street_h_rys = road_h_rys

    do
        local vc, hc, nc = 0, 0, 0
        for _ in pairs(road_v_rxs) do vc = vc + 1 end
        for _ in pairs(road_h_rys) do hc = hc + 1 end
        for _, row in pairs(road_nodes) do for _ in pairs(row) do nc = nc + 1 end end
        print(string.format("DEBUG road_v_rxs=%d road_h_rys=%d road_nodes=%d sub_cw=%d sub_ch=%d", vc, hc, nc, sub_cw, sub_ch))
        local vrx_list = {}
        for rx in pairs(road_v_rxs) do vrx_list[#vrx_list+1] = rx end
        table.sort(vrx_list)
        print("DEBUG road_v_rxs columns: " .. table.concat(vrx_list, ","))
        local hry_list = {}
        for ry in pairs(road_h_rys) do hry_list[#hry_list+1] = ry end
        table.sort(hry_list)
        print("DEBUG road_h_rys rows: " .. table.concat(hry_list, ","))
    end

    if zone_grid then
        local zone_seg_v = {}
        for gy = 1, sub_ch do
            for rx = 1, sub_cw - 1 do
                local z1 = zone_grid[gy][rx]
                local z2 = zone_grid[gy][rx + 1]
                if z1 and z1 ~= "none" and z2 and z2 ~= "none" and z1 ~= z2 then
                    if not zone_seg_v[gy] then zone_seg_v[gy] = {} end
                    zone_seg_v[gy][rx] = true
                end
            end
        end
        local zone_seg_h = {}
        for ry = 1, sub_ch - 1 do
            for gx = 1, sub_cw do
                local z1 = zone_grid[ry][gx]
                local z2 = zone_grid[ry + 1][gx]
                if z1 and z1 ~= "none" and z2 and z2 ~= "none" and z1 ~= z2 then
                    if not zone_seg_h[ry] then zone_seg_h[ry] = {} end
                    zone_seg_h[ry][gx] = true
                end
            end
        end

        local new_nodes = {}
        for ry = 0, sub_ch - 1 do
            for rx = 0, sub_cw - 1 do
                local has_north = ry >= 1 and zone_seg_v[ry] and zone_seg_v[ry][rx]
                local has_south = zone_seg_v[ry + 1] and zone_seg_v[ry + 1][rx]
                local has_east  = zone_seg_h[ry] and zone_seg_h[ry][rx + 1]
                local has_west  = rx >= 1 and zone_seg_h[ry] and zone_seg_h[ry][rx]
                if has_north or has_south or has_east or has_west then
                    if not new_nodes[ry] then new_nodes[ry] = {} end
                    new_nodes[ry][rx] = true
                end
            end
        end
        for ry, row in pairs(new_map.road_nodes) do
            for rx in pairs(row) do
                local gx2, gy2 = rx + 1, ry + 1
                local tile2 = grid[gy2] and grid[gy2][gx2]
                if tile2 and (tile2.type == "arterial" or tile2.type == "highway") then
                    if not new_nodes[ry] then new_nodes[ry] = {} end
                    new_nodes[ry][rx] = true
                end
            end
        end

        fixIslandConnectivity(zone_grid, grid, sub_cw, sub_ch, zone_seg_v, zone_seg_h, new_nodes)

        local bridge_cells = {}
        local function nrz(gy2, gx2)
            if gy2 < 1 or gy2 > sub_ch or gx2 < 1 or gx2 > sub_cw then return false end
            local z = zone_grid[gy2] and zone_grid[gy2][gx2]
            return z and z ~= "none" and z ~= "river"
        end
        for gy = 1, sub_ch do
            for gx = 1, sub_cw do
                if zone_grid[gy] and zone_grid[gy][gx] == "river" then
                    local entry = {}
                    if nrz(gy, gx - 1) and nrz(gy, gx + 1) then entry.ew = true end
                    if nrz(gy - 1, gx) and nrz(gy + 1, gx) then entry.ns = true end
                    if (entry.ew or entry.ns) and random() < 0.10 then
                        if not bridge_cells[gy] then bridge_cells[gy] = {} end
                        bridge_cells[gy][gx] = entry
                    end
                end
            end
        end
        new_map.bridge_cells = bridge_cells

        local building_plots = {}
        local seen_b = {}
        for gy = 1, sub_ch do
            for gx = 1, sub_cw do
                local t = grid[gy][gx].type
                if t == "plot" or t == "downtown_plot" then
                    local reachable2 =
                        (zone_seg_v[gy] and (zone_seg_v[gy][gx-1] or zone_seg_v[gy][gx]))
                     or (zone_seg_h[gy-1] and zone_seg_h[gy-1][gx])
                     or (zone_seg_h[gy]   and zone_seg_h[gy][gx])
                     or (grid[gy][gx-1] and (grid[gy][gx-1].type == "arterial" or grid[gy][gx-1].type == "highway"))
                     or (grid[gy][gx+1] and (grid[gy][gx+1].type == "arterial" or grid[gy][gx+1].type == "highway"))
                     or (grid[gy-1] and grid[gy-1][gx] and (grid[gy-1][gx].type == "arterial" or grid[gy-1][gx].type == "highway"))
                     or (grid[gy+1] and grid[gy+1][gx] and (grid[gy+1][gx].type == "arterial" or grid[gy+1][gx].type == "highway"))
                    if reachable2 then
                        local key = gy * 10000 + gx
                        if not seen_b[key] then
                            seen_b[key] = true
                            building_plots[#building_plots+1] = {x=gx, y=gy}
                        end
                    end
                end
            end
        end
        new_map.building_plots = building_plots

        new_map.road_v_rxs  = {}
        new_map.road_h_rys  = {}
        new_map.road_nodes  = new_nodes
        new_map.zone_seg_v  = zone_seg_v
        new_map.zone_seg_h  = zone_seg_h

        local tile_nodes_tbl = {}
        for tgy = 1, sub_ch do
            for tgx = 1, sub_cw do
                local tt = grid[tgy][tgx].type
                if tt == "arterial" or tt == "highway" then
                    local tty = tgy - 1
                    local ttx = tgx - 1
                    if not tile_nodes_tbl[tty] then tile_nodes_tbl[tty] = {} end
                    tile_nodes_tbl[tty][ttx] = true
                end
            end
        end
        new_map.tile_nodes = tile_nodes_tbl
    end
end

-- ── Sub-cell grid builder ─────────────────────────────────────────────────────
local function buildCityGrid(city_idx, mn_x, mx_x, mn_y, mx_y, art_sci, all_claimed,
    highway_map, heightmap, biome_data, district_map, pois, bounds, params, w, h)
    local sw = w * 3

    local sub_cw   = (mx_x - mn_x + 1) * 3
    local sub_ch   = (mx_y - mn_y + 1) * 3
    local gscx_off = (mn_x - 1) * 3
    local gscy_off = (mn_y - 1) * 3

    local dt_sci  = {}
    local dmap_dt = district_map
    if dmap_dt then
        for sci, poi_idx_v in pairs(dmap_dt) do
            if poi_idx_v == 1 then dt_sci[sci] = true end
        end
    end
    if not next(dt_sci) then
        local poi1   = pois and pois[1]
        if poi1 and bounds then
            local DT_RADIUS = 6
            for ci in pairs(bounds) do
                local cx = (ci-1)%w+1; local cy = math.floor((ci-1)/w)+1
                local dx = cx - poi1.x; local dy = cy - poi1.y
                if dx*dx + dy*dy <= DT_RADIUS*DT_RADIUS then
                    local gscx0 = (cx-1)*3; local gscy0 = (cy-1)*3
                    for dy2 = 0, 2 do for dx2 = 0, 2 do
                        dt_sci[(gscy0+dy2)*sw + (gscx0+dx2) + 1] = true
                    end end
                end
            end
        end
    end

    local grid = {}
    local p    = params
    for lscy = 0, sub_ch - 1 do
        grid[lscy + 1] = {}
        local wcy  = mn_y + math.floor(lscy / 3)
        local gscy = gscy_off + lscy
        for lscx = 0, sub_cw - 1 do
            local wcx  = mn_x + math.floor(lscx / 3)
            local gscx = gscx_off + lscx
            local ci   = (wcy - 1) * w + wcx
            local sci  = gscy * sw + gscx + 1
            local tile
            if art_sci[sci] then
                tile = (highway_map and highway_map[ci]) and "highway" or "arterial"
            elseif all_claimed[ci] then
                tile = dt_sci[sci] and "downtown_plot" or "plot"
            else
                local elev = (heightmap and heightmap[wcy] and heightmap[wcy][wcx]) or 0.5
                if     elev <= (p.ocean_max    or 0.42) then tile = "water"
                elseif elev >= (p.highland_max or 0.80) then tile = "mountain"
                else                                          tile = "grass" end
            end
            grid[lscy + 1][lscx + 1] = {type = tile}
        end
    end

    do
        local bdata     = biome_data or {}
        local _COL_HASH = {0, 2, 1, 2, 0, 1, 2}
        local _ROW_HASH = {1, 0, 2, 0, 2, 1, 0}
        local function hub_col(wx2) return _COL_HASH[wx2 % 7 + 1] end
        local function hub_row(wy2) return _ROW_HASH[wy2 % 7 + 1] end
        local function mr(gx, gy)
            if gx < 1 or gx > sub_cw or gy < 1 or gy > sub_ch then return end
            local t = grid[gy][gx].type
            if t ~= "arterial" and t ~= "highway" then grid[gy][gx] = {type = "river"} end
        end
        local function route(lb_x, lb_y, r1, c1, r2, c2)
            local r, c = r1, c1
            mr(lb_x+c+1, lb_y+r+1)
            while r ~= r2 do r = r+(r2>r and 1 or -1); mr(lb_x+c+1, lb_y+r+1) end
            while c ~= c2 do c = c+(c2>c and 1 or -1); mr(lb_x+c+1, lb_y+r+1) end
        end
        local function is_riv(wx2, wy2)
            if wx2 < 1 or wx2 > w or wy2 < 1 or wy2 > h then return false end
            local bd2 = bdata[(wy2-1)*w+wx2]; return bd2 and bd2.is_river
        end
        for wy = mn_y, mx_y do
            for wx = mn_x, mx_x do
                local bd = bdata[(wy-1)*w+wx]
                if bd and bd.is_river then
                    local lb_x = (wx-mn_x)*3; local lb_y = (wy-mn_y)*3
                    local hc   = hub_col(wx);  local hr   = hub_row(wy)
                    mr(lb_x+hc+1, lb_y+hr+1)
                    if is_riv(wx,wy-1) then route(lb_x,lb_y,0,  hc,hr,hc) end
                    if is_riv(wx,wy+1) then route(lb_x,lb_y,2,  hc,hr,hc) end
                    if is_riv(wx-1,wy) then route(lb_x,lb_y,hr,  0,hr,hc) end
                    if is_riv(wx+1,wy) then route(lb_x,lb_y,hr,  2,hr,hc) end
                    for _, dv in ipairs({{1,1},{1,-1},{-1,1},{-1,-1}}) do
                        local dx, dy = dv[1], dv[2]
                        if is_riv(wx+dx,wy+dy) and not is_riv(wx+dx,wy) and not is_riv(wx,wy+dy) then
                            route(lb_x, lb_y, hr, hc, dy==1 and 2 or 0, dx==1 and 2 or 0)
                        end
                    end
                end
            end
        end
    end

    local ctx = {
        sub_cw   = sub_cw,   sub_ch   = sub_ch,
        gscx_off = gscx_off, gscy_off = gscy_off,
        sw = sw, w = w, city_mn_x = mn_x, city_mn_y = mn_y,
        grid = grid,
    }
    return grid, ctx
end

-- ── Public: build a full city map ────────────────────────────────────────────
-- Returns: Map instance, zone_grid, zone_offsets, district_types
function MapBuilderService.buildCityMap(
    city_idx, mn_x, mx_x, mn_y, mx_y, art_sci, all_claimed,
    district_map, pois, bounds, highway_map, heightmap, biome_data, street_map,
    pre_district_types, params, math_fns, C, w, h
)
    local Map = require("models.Map")

    local grid, ctx = buildCityGrid(city_idx, mn_x, mx_x, mn_y, mx_y, art_sci, all_claimed,
        highway_map, heightmap, biome_data, district_map, pois, bounds, params, w, h)
    local sub_cw = ctx.sub_cw
    local sub_ch = ctx.sub_ch

    local dt_mn_x, dt_mx_x, dt_mn_y, dt_mx_y = sub_cw + 1, 0, sub_ch + 1, 0
    for gy = 1, sub_ch do
        for gx = 1, sub_cw do
            local t = grid[gy][gx].type
            if t == "downtown_road" or t == "downtown_plot" then
                if gx < dt_mn_x then dt_mn_x = gx end
                if gx > dt_mx_x then dt_mx_x = gx end
                if gy < dt_mn_y then dt_mn_y = gy end
                if gy > dt_mx_y then dt_mx_y = gy end
            end
        end
    end
    if dt_mn_x > dt_mx_x then
        local poi = pois and pois[1]
        if poi then
            local lscx = (poi.x - mn_x) * 3 + 1
            local lscy = (poi.y - mn_y) * 3 + 1
            local r = 18
            dt_mn_x = math.max(1, lscx-r); dt_mx_x = math.min(sub_cw, lscx+r)
            dt_mn_y = math.max(1, lscy-r); dt_mx_y = math.min(sub_ch, lscy+r)
        else
            dt_mn_x = 1; dt_mx_x = 30; dt_mn_y = 1; dt_mx_y = 30
        end
    end

    local map = Map:new(C)
    map.city_grid_width      = sub_cw
    map.city_grid_height     = sub_ch
    map.downtown_grid_width  = math.max(1, dt_mx_x - dt_mn_x + 1)
    map.downtown_grid_height = math.max(1, dt_mx_y - dt_mn_y + 1)
    map.grid            = grid
    map.downtown_offset = {x = dt_mn_x, y = dt_mn_y}
    map.tile_pixel_size = C.MAP.TILE_SIZE / 3
    map.building_plots  = {}

    local zone_grid, zone_offsets, district_types, dt_cells, all_city_plots =
        buildZoneGrid(city_idx, grid, ctx, district_map, pois, biome_data, pre_district_types, math_fns)

    map.all_city_plots    = all_city_plots
    map.zone_grid         = zone_grid
    map.downtown_subcells = dt_cells

    buildRoadNetwork(map, grid, zone_grid, ctx, street_map, math_fns)

    map.district_map    = district_map
    map.district_types  = district_types
    map.district_colors = nil   -- caller supplies after build (from city_district_colors)
    map.district_pois   = pois
    map.zone_gscx_off   = ctx.gscx_off
    map.zone_gscy_off   = ctx.gscy_off
    map.zone_sw         = ctx.sw
    map.world_biome_data = biome_data
    map.world_city_mn_x  = mn_x
    map.world_city_mn_y  = mn_y
    map.world_city_mx_x  = mx_x
    map.world_city_mx_y  = mx_y
    map.world_w          = ctx.w
    map.world_mn_x       = mn_x
    map.world_mn_y       = mn_y

    return map, zone_grid, zone_offsets, district_types
end

return MapBuilderService
