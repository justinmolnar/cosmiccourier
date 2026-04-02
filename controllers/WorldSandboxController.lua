-- controllers/WorldSandboxController.lua

local WorldSandboxController = {}
WorldSandboxController.__index = WorldSandboxController

function WorldSandboxController:new(game)
    local inst = setmetatable({}, WorldSandboxController)
    inst.game   = game
    inst.active = false

    inst.camera          = { x = 0, y = 0, scale = 1 }
    inst.camera_dragging = false
    inst.camera_drag_sx  = 0
    inst.camera_drag_sy  = 0

    inst.heightmap             = nil
    inst.colormap              = nil
    inst.biome_colormap        = nil
    inst.biome_data            = nil
    inst.suitability_colormap  = nil
    inst.suitability_scores    = nil
    inst.continent_colormap    = nil
    inst.continent_map         = nil
    inst.continents            = nil
    inst.region_colormap       = nil
    inst.region_map            = nil
    inst.regions_list          = nil
    inst.city_locations        = nil
    inst.highway_map           = nil
    inst.city_bounds           = nil
    inst.city_border           = nil
    inst.city_fringe           = nil
    inst.city_pois             = nil
    inst.city_pois_list        = nil   -- [city_idx] = {pois array} for that city
    inst.city_bounds_list      = nil
    inst.city_district_maps    = nil   -- [city_idx] = {[cell_idx] = poi_idx}
    inst.city_district_colors  = nil   -- [city_idx] = {[poi_idx] = {r,g,b}}
    inst.city_district_types   = nil   -- [city_idx] = {[poi_idx] = "residential"|"commercial"|"industrial"|"downtown"}
    inst.city_arterial_maps    = nil   -- [city_idx] = {[sci] = true}  sub-cell roads
    inst.city_street_maps      = nil   -- [city_idx] = {v={},h={}}  world-cell boundary streets (fallback)
    inst.city_zone_grids       = nil   -- [city_idx] = zone_grid result from WFC (sub-cell level)
    inst.city_zone_offsets     = nil   -- [city_idx] = {x=gscx_off, y=gscy_off} WFC grid origin
    inst.selected_city_idx       = nil
    inst.selected_city_bounds    = nil
    inst.selected_downtown_bounds = nil
    inst.city_image            = nil   -- high-res city grid image (city scope)
    inst.city_img_min_x        = 0
    inst.city_img_min_y        = 0
    inst.city_img_K            = 1
    inst.world_image           = nil
    inst.world_w        = 0
    inst.world_h        = 0
    inst.view_mode      = "height"   -- "height" | "biome" | "suitability" | "continents" | "regions" | "districts"
    inst.view_scope     = "world"    -- "world" | "continent" | "region"
    inst.scope_mode     = nil        -- nil | "picking_continent" | "picking_region"
    inst.selected_continent_id = nil
    inst.selected_region_id    = nil
    inst.status_text    = ""

    inst.sidebar_manager = nil

    inst.params = {
        -- World grid dimensions.
        world_w = 400, world_h = 300,
        -- Noise seed
        seed_x = 0, seed_y = 0,
        -- Continental layer: controls landmass size/count.
        -- scale=0.004 → ~1 feature per 250px → 1-2 large peaks across a 400px map.
        -- Raise scale for more smaller islands; lower for fewer bigger ones.
        continental_scale   = 0.004,
        continental_octaves = 4,
        continental_weight  = 0.80,
        -- Terrain layer (smooth FBM — internal elevation variation within islands)
        terrain_scale   = 0.015,
        terrain_octaves = 3,
        terrain_weight  = 0.15,
        persistence     = 0.50,
        lacunarity      = 2.00,
        -- Mountain layer (ridge FBM — applied on top of land only, never affects coastlines).
        -- scale=0.025 → ridge every ~40px → 2-4 ranges per island.
        mountain_scale    = 0.025,
        mountain_octaves  = 3,
        mountain_strength = 0.35,
        -- Detail layer (coastline roughness only)
        detail_scale   = 0.050,
        detail_octaves = 2,
        detail_weight  = 0.05,
        -- Moisture (biome variation at same elevation)
        moisture_scale   = 0.012,
        moisture_octaves = 3,
        -- Rivers: fraction of total cells needed as upstream catchment to show a river.
        -- Lower = more rivers; 0 = disabled.
        river_count      = 30,   -- slider 0-300: number of river sources to trace
        meander_strength = 0.08,  -- slider 0-0.15: noise perturbation added to flow heights to create winding paths
        lake_delta       = 0.010, -- slider 0-0.05: how far above a pit floor cells are included in the lake basin
        river_influence  = 50,   -- slider 0-100: BFS radius (cells) that rivers fertilize in biome view
        latitude_strength = 0.7, -- slider 0-1: how strongly latitude (north/south position) drives temperature
        -- Suitability mapping (city placement scoring)
        suit_coast_radius   = 80,  -- slider 0-200: coast proximity radius (cells)
        suit_river_radius   = 20,  -- slider 0-80:  river corridor radius (keep tight for distinct corridors)
        suit_elev_weight    = 0.40, -- slider 0-1: elevation score weight
        suit_coast_weight   = 0.35, -- slider 0-1: coast proximity weight
        suit_river_weight   = 0.65, -- slider 0-1: river proximity weight (rivers are primary)
        suit_climate_weight = 0.20, -- slider 0-1: climate modifier weight
        -- City placement
        city_count        = 12,   -- slider 1-50: how many cities to place
        city_min_sep      = 30,   -- slider 5-100: minimum cell distance between cities
        island_threshold  = 0.03, -- slider 0-0.15: land fraction below which a landmass is an island
        -- Region subdivision (Dijkstra within each continent)
        region_count         = 20, -- slider 1-80: total regions across all major continents
        region_mountain_cost = 8,  -- slider 0-20: extra crossing cost per unit highland fraction
        region_river_cost    = 4,  -- slider 0-20: extra crossing cost for river/lake cells
        region_min_sep       = 20, -- slider 5-80: min cell distance between region seed points
        -- Highway network (A* between cities, MST + extra links)
        highway_mountain_cost = 10, -- slider 1-30: crossing cost multiplier for mountain terrain
        highway_river_cost    = 3,  -- slider 0-15: extra cost to cross a river or lake cell
        highway_slope_cost    = 15, -- slider 0-40: cost per unit of elevation change (makes roads contour)
        highway_budget_scale   = 800, -- slider 100-3000: budget per unit of suitability² (larger = more roads)
        -- City bounds generation (Dijkstra flood-fill from city seed)
        city_size_fraction = 0.07, -- slider 0.01-0.50: fraction of region cells the city can claim (scaled by suitability)
        city_poi_count     = 10,   -- slider 2-20: POIs to identify (downtown + districts)
        city_poi_spacing   = 1.0,  -- slider 0.3-3.0: multiplier on auto-spacing (1.0 = evenly distribute across footprint)
        downtown_pct       = 0.05, -- slider 0.05-0.30: target fraction of city cells for the downtown district
        downtown_min_cells = 11,   -- slider 1-50: hard minimum sub-cells for downtown regardless of % result
        -- Edge margin: outer X% of map is forced to deep ocean (0 = disabled)
        edge_margin = 0.14,
        -- Biome thresholds on the normalized [0,1] height.
        -- coast_max is effectively "sea level" — raise it for more ocean, lower for more land.
        deep_ocean_max = 0.42,
        ocean_max      = 0.50,
        coast_max      = 0.55,
        plains_max     = 0.70,
        forest_max     = 0.80,
        highland_max   = 0.88,
        mountain_max   = 0.94,
    }

    return inst
end

-- ── Lifecycle ─────────────────────────────────────────────────────────────────

function WorldSandboxController:isActive()
    return self.active
end

function WorldSandboxController:toggle()
    if self.active then
        self:close()
    else
        self:open()
    end
end

function WorldSandboxController:open()
    self.active = true
    if not self.sidebar_manager then
        self.sidebar_manager = require("views.WorldSandboxSidebarManager"):new(self, self.game)
    end
    self.status_text = "Press Generate →"
end

function WorldSandboxController:close()
    self.active = false
end

-- ── sendToGame helpers ────────────────────────────────────────────────────────

-- WFC zone grid + downtown_subcells.  Mutates new_map.zone_grid, .all_city_plots,
-- .downtown_subcells; also caches zone grid on self for later image building.
-- ctx fields: sub_cw, sub_ch, gscx_off, gscy_off, sw, w, start_idx, grid,
--             city_mn_x, city_mn_y
function WorldSandboxController:_buildZoneGrid(new_map, ctx)
    local sub_cw    = ctx.sub_cw;    local sub_ch    = ctx.sub_ch
    local gscx_off  = ctx.gscx_off;  local gscy_off  = ctx.gscy_off
    local sw        = ctx.sw;        local w         = ctx.w
    local start_idx = ctx.start_idx; local grid      = ctx.grid
    local city_mn_x = ctx.city_mn_x; local city_mn_y = ctx.city_mn_y

    local WFC = require("lib.wfc")
    local ZT  = require("data.zones")

    local dmap  = self.city_district_maps and self.city_district_maps[start_idx] or {}

    if not self.city_district_types then self.city_district_types = {} end
    if not self.city_district_types[start_idx] then
        local pois    = self.city_pois_list and self.city_pois_list[start_idx] or {}
        local rules   = ZT.DISTRICT_RULES or {}
        local choices = ZT.RANDOM_DISTRICT_TYPES

        -- Build POI neighbor graph from dmap (check right + down neighbors only; symmetric)
        local neighbors = {}  -- neighbors[poi_idx] = {[neighbor_poi_idx] = true}
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


        -- wfc_neighbors: used for soft adjacency penalty during assignment
        local wfc_neighbors = neighbors

        -- Tally world tile composition per POI from dmap + biome_data
        local bdata = self.biome_data or {}
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
                if bn == "Beach"                         then t.beach  = t.beach  + 1 end
                if bn == "Desert" or bn:find("arid")     then t.desert = t.desert + 1 end
            end
        end

        -- Sequential weighted assignment with uniqueness decay.
        -- Each district type has a global pool weight that decays sharply each time
        -- it's chosen, naturally pushing toward unused types — same spirit as WFC
        -- entropy but enforced across the whole city.
        local type_pool = {}
        for _, c in ipairs(choices) do type_pool[c] = 1.0 end

        local dtypes = {[1] = "downtown"}

        -- Randomise assignment order so no POI index gets systematic bias
        local order = {}
        for i = 2, #pois do order[#order+1] = i end
        for i = #order, 2, -1 do
            local j = love.math.random(1, i)
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
                -- Hard bans: these districts literally require these world tiles
                if (c ~= "riverfront" or rf >= 0.05) and
                   (c ~= "waterfront" or wf >= 0.05) then
                    local w = type_pool[c]
                    -- Soft biome boosts
                    if c == "riverfront"      and rf >= 0.05 then w = w * math.min(1 + rf * 1.5, 2.0) end
                    if c == "waterfront"      and wf >= 0.05 then w = w * math.min(1 + wf * 1.5, 2.0) end
                    if c == "rural_outskirts" and ff >= 0.2  then w = w * math.min(1 + ff * 1.5, 2.0) end
                    if c == "industrial"      and df >= 0.3  then w = w * math.min(1 + df * 1.5, 2.0) end
                    -- Soft adjacency penalty: discourage cannot-pairs that are already assigned
                    for nbr in pairs(wfc_neighbors[poi_i] or {}) do
                        if dtypes[nbr] then
                            for _, cant in ipairs((rules[c] and rules[c].cannot) or {}) do
                                if cant == dtypes[nbr] then w = w * 0.3; break end
                            end
                        end
                    end
                    if w > 0 then candidates[#candidates+1] = {t=c, w=w}; tw = tw + w end
                end
            end

            local chosen
            if tw > 0 then
                local rand, cumw = love.math.random() * tw, 0
                chosen = candidates[#candidates].t
                for _, cand in ipairs(candidates) do
                    cumw = cumw + cand.w
                    if rand <= cumw then chosen = cand.t; break end
                end
            else
                chosen = choices[love.math.random(1, #choices)]
            end

            dtypes[poi_i] = chosen
            type_pool[chosen] = type_pool[chosen] * 0.15  -- ~7× less likely next time
        end

        self.city_district_types[start_idx] = dtypes
    end
    local district_types = self.city_district_types[start_idx]
    local bdata = self.biome_data or {}

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
                    table.insert(all_city_plots, {x=gx, y=gy})
                end
            end
        end
    end
    new_map.all_city_plots = all_city_plots

    local wfc = WFC.new(sub_cw, sub_ch, ZT.STATES, ZT.ADJACENCY)
    for lscy = 0, sub_ch - 1 do
        local gy = lscy + 1
        for lscx = 0, sub_cw - 1 do
            local gx = lscx + 1
            if not plot_set[gy * 100000 + gx] then
                for _, s in ipairs(ZT.STATES) do wfc.grid[gy][gx][s] = (s == "none") end
                wfc.entropy_grid[gy][gx] = 1
            elseif grid[gy][gx].type == "river" then
                -- Pre-collapse: river sub-cells are pinned to "river" zone
                for _, s in ipairs(ZT.STATES) do wfc.grid[gy][gx][s] = (s == "river") end
                wfc.entropy_grid[gy][gx] = 1
            else
                local gscx2   = gscx_off + lscx
                local gscy2   = gscy_off + lscy
                local sci     = gscy2 * sw + gscx2 + 1
                local poi_idx = dmap[sci]
                local dtype   = (poi_idx and district_types[poi_idx]) or "residential"
                local base_w  = ZT.DISTRICT_WEIGHTS[dtype] or ZT.DISTRICT_WEIGHTS.residential
                local wcx2    = city_mn_x + math.floor(lscx / 3)
                local wcy2    = city_mn_y + math.floor(lscy / 3)
                local ci2     = (wcy2 - 1) * w + wcx2
                local bd      = bdata[ci2]
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
                    local w = s == "none" and 0 or ((base_w[s] or 0) * (bmul[s] or 1.0))
                    WFC.setWeight(wfc, gx, gy, s, w > 0 and math.max(0.01, w) or 0)
                end
                -- Biome-specific sub-cell zone injection via strong weight boosts
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
    wfc.coherence_factor = 6.0  -- each collapsed neighbour multiplies matching state weight by this
    WFC.solve(wfc)
    local result = WFC.getResult(wfc)

    -- Fallback for contradiction cells
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
                    local base_w  = ZT.DISTRICT_WEIGHTS[dtype] or ZT.DISTRICT_WEIGHTS.residential
                    local best, best_w = ZT.STATES[1], 0
                    for _, s in ipairs(ZT.STATES) do
                        if s ~= "none" and (base_w[s] or 0) > best_w then best = s; best_w = base_w[s] end
                    end
                    result[gy][gx] = best
                end
            end
        end
    end
    new_map.zone_grid = result

    -- Per-subcell downtown set (district owner == 1) for fog rendering in GameView
    do
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
        new_map.downtown_subcells = dt_cells
    end

    if not self.city_zone_grids   then self.city_zone_grids   = {} end
    if not self.city_zone_offsets then self.city_zone_offsets = {} end
    self.city_zone_grids[start_idx]   = result
    self.city_zone_offsets[start_idx] = {x = gscx_off, y = gscy_off}
end

-- Connect isolated zone-boundary road clusters to the arterial/highway network.
-- Mutates zone_seg_v, zone_seg_h, new_nodes (all passed by reference), and
-- new_map.zone_grid (zg) for visual correctness of bridging segments.
function WorldSandboxController:_fixIslandConnectivity(new_map, grid, sub_cw, sub_ch, zone_seg_v, zone_seg_h, new_nodes)
    local zg = new_map.zone_grid
    if not zg then return end

    -- BFS from arterial/highway nodes along the zone_seg graph
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

    -- Multi-source BFS outward from reachable set to find shortest path to every node
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

    local ZT = require("data.zones")
    local _road_z0 = ZT.STATES[1]
    local _road_z1 = _road_z0
    for _, s in ipairs(ZT.STATES) do
        if s ~= "none" and s ~= _road_z0 then _road_z1 = s; break end
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

    -- Walk parent chain from each unreachable node to the reachable set
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

-- Road-node graph + zone-boundary streets + island connectivity.
-- Mutates new_map.road_v_rxs, .road_h_rys, .road_nodes, .zone_seg_v,
-- .zone_seg_h, .tile_nodes, .building_plots.
-- Requires new_map.zone_grid to be set first (_buildZoneGrid).
-- ctx: same fields as _buildZoneGrid.
function WorldSandboxController:_buildRoadNetwork(new_map, ctx)
    local sub_cw    = ctx.sub_cw;    local sub_ch    = ctx.sub_ch
    local gscx_off  = ctx.gscx_off;  local gscy_off  = ctx.gscy_off
    local sw        = ctx.sw;        local w         = ctx.w
    local start_idx = ctx.start_idx; local grid      = ctx.grid

    local road_v_rxs = {}
    local road_h_rys = {}
    local road_nodes = {}

    -- road_v_rxs / road_h_rys from city_street_maps[start_idx] only.
    do
        local smap = self.city_street_maps and self.city_street_maps[start_idx]
        local miss_cx, miss_cy = {}, {}
        if smap then
            for key in pairs(smap.v or {}) do
                local cx   = math.floor(key / 1000)
                local lscx = cx * 3 - gscx_off
                if lscx >= 0 and lscx < sub_cw then road_v_rxs[lscx] = true
                else miss_cx[cx] = true end
            end
            for key in pairs(smap.h or {}) do
                local cy   = math.floor(key / 1000)
                local lscy = cy * 3 - gscy_off
                if lscy >= 0 and lscy < sub_ch then road_h_rys[lscy] = true
                else miss_cy[cy] = true end
            end
        end
        local miss_cx_list, miss_cy_list = {}, {}
        for cx in pairs(miss_cx) do table.insert(miss_cx_list, cx) end
        for cy in pairs(miss_cy) do table.insert(miss_cy_list, cy) end
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

    -- road_nodes from city_street_maps[start_idx] (city streets only).
    do
        local smap = self.city_street_maps and self.city_street_maps[start_idx]
        if smap then
            for key in pairs(smap.v or {}) do
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
            for key in pairs(smap.h or {}) do
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

    -- Arterial/highway corners: add road_nodes only at inner edges or street junctions.
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

    new_map.road_v_rxs = road_v_rxs
    new_map.road_h_rys = road_h_rys
    new_map.road_nodes = road_nodes

    -- Diagnostic
    do
        local vc, hc, nc = 0, 0, 0
        for _ in pairs(road_v_rxs) do vc = vc + 1 end
        for _ in pairs(road_h_rys) do hc = hc + 1 end
        for _, row in pairs(road_nodes) do for _ in pairs(row) do nc = nc + 1 end end
        print(string.format("DEBUG road_v_rxs=%d road_h_rys=%d road_nodes=%d sub_cw=%d sub_ch=%d", vc, hc, nc, sub_cw, sub_ch))
        local svc, shc = 0, 0
        for idx2 = 1, #self.city_locations do
            local smap2 = self.city_street_maps and self.city_street_maps[idx2]
            if smap2 then
                for _ in pairs(smap2.v or {}) do svc = svc + 1 end
                for _ in pairs(smap2.h or {}) do shc = shc + 1 end
            end
        end
        print(string.format("DEBUG city_street_maps total: v=%d h=%d", svc, shc))
        local vrx_list = {}
        for rx in pairs(road_v_rxs) do table.insert(vrx_list, rx) end
        table.sort(vrx_list)
        print("DEBUG road_v_rxs columns: " .. table.concat(vrx_list, ","))
        local hry_list = {}
        for ry in pairs(road_h_rys) do table.insert(hry_list, ry) end
        table.sort(hry_list)
        print("DEBUG road_h_rys rows: " .. table.concat(hry_list, ","))
    end

    -- Building plots: plot/downtown_plot cells beside a street line or arterial/highway.
    local function is_road_tile(x, y)
        if x < 1 or x > sub_cw or y < 1 or y > sub_ch then return false end
        local tt = grid[y] and grid[y][x] and grid[y][x].type
        return tt == "arterial" or tt == "highway"
    end
    local building_plots = {}
    local seen_b = {}
    for gy = 1, sub_ch do
        for gx = 1, sub_cw do
            local t = grid[gy][gx].type
            if t == "plot" or t == "downtown_plot" then
                if road_v_rxs[gx-1] or road_v_rxs[gx] or
                   road_h_rys[gy-1] or road_h_rys[gy] or
                   is_road_tile(gx-1,gy) or is_road_tile(gx+1,gy) or
                   is_road_tile(gx,gy-1) or is_road_tile(gx,gy+1) then
                    local key = gy * 10000 + gx
                    if not seen_b[key] then
                        seen_b[key] = true
                        table.insert(building_plots, {x=gx, y=gy})
                    end
                end
            end
        end
    end
    print(string.format("DEBUG building_plots=%d (total plot/dt_plot cells scanned in %dx%d grid)", #building_plots, sub_cw, sub_ch))
    new_map.building_plots = building_plots

    -- Override road_v_rxs / road_h_rys / road_nodes with sub-cell zone boundaries.
    do
        local zg = new_map.zone_grid
        if zg then
            local zone_seg_v = {}
            for gy = 1, sub_ch do
                for rx = 1, sub_cw - 1 do
                    local z1 = zg[gy][rx]
                    local z2 = zg[gy][rx + 1]
                    if z1 and z1 ~= "none" and z2 and z2 ~= "none" and z1 ~= z2 then
                        if not zone_seg_v[gy] then zone_seg_v[gy] = {} end
                        zone_seg_v[gy][rx] = true
                    end
                end
            end
            local zone_seg_h = {}
            for ry = 1, sub_ch - 1 do
                for gx = 1, sub_cw do
                    local z1 = zg[ry][gx]
                    local z2 = zg[ry + 1][gx]
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
            -- Preserve arterial/highway nodes from the street-based map.
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

            -- ── Island connectivity ─────────────────────────────────────────────
            self:_fixIslandConnectivity(new_map, grid, sub_cw, sub_ch, zone_seg_v, zone_seg_h, new_nodes)

            -- Bridge detection: river sub-cells flanked by non-river zones on opposite sides.
            -- 10% chance per crossing so the river doesn't get a bridge at every street boundary.
            local bridge_cells = {}
            local function nrz(gy2, gx2)
                if gy2 < 1 or gy2 > sub_ch or gx2 < 1 or gx2 > sub_cw then return false end
                local z = zg[gy2] and zg[gy2][gx2]
                return z and z ~= "none" and z ~= "river"
            end
            for gy = 1, sub_ch do
                for gx = 1, sub_cw do
                    if zg[gy] and zg[gy][gx] == "river" then
                        local entry = {}
                        if nrz(gy, gx - 1) and nrz(gy, gx + 1) then entry.ew = true end
                        if nrz(gy - 1, gx) and nrz(gy + 1, gx) then entry.ns = true end
                        if (entry.ew or entry.ns) and love.math.random() < 0.10 then
                            if not bridge_cells[gy] then bridge_cells[gy] = {} end
                            bridge_cells[gy][gx] = entry
                        end
                    end
                end
            end
            new_map.bridge_cells = bridge_cells

            -- road_v_rxs must remain truthy so PathfindingService treats this as a road-node map.
            new_map.road_v_rxs  = {}
            new_map.road_h_rys  = {}
            new_map.road_nodes  = new_nodes
            new_map.zone_seg_v  = zone_seg_v
            new_map.zone_seg_h  = zone_seg_h

            -- tile_nodes: bridge between corner nodes and arterial/highway tile-centre nodes.
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
end

-- Build all zoom-level images and camera-fit params, then stamp them onto game.
-- Mutates game.world_gen_city_image, .world_gen_cam_params, etc.
function WorldSandboxController:_buildGameImages(game, start_idx, city_mn_x, city_mx_x, city_mn_y, city_mx_y, w, h)
    local C  = game.C
    local ts = C.MAP.TILE_SIZE

    local function buildCityImg(mode, bx1, bx2, by1, by2, scope)
        local sv_mode  = self.view_mode
        local sv_scope = self.view_scope
        self.view_mode  = mode
        if scope then self.view_scope = scope end
        self:_buildCityImage(start_idx, bx1, bx2, by1, by2)
        self.view_mode  = sv_mode
        self.view_scope = sv_scope
        return self.city_image
    end

    local function buildWorldImg(scope, cid, rid)
        local sv_scope  = self.view_scope
        local sv_cid    = self.selected_continent_id
        local sv_rid    = self.selected_region_id
        local sv_mode   = self.view_mode
        local sv_bounds = self.city_bounds
        local sv_border = self.city_border
        local sv_fringe = self.city_fringe
        self.view_scope = scope
        self.selected_continent_id = cid
        self.selected_region_id    = rid
        self.view_mode = self.biome_colormap and "biome" or "height"
        self.city_bounds = nil
        self.city_border = nil
        self.city_fringe = nil
        self:_buildImage()
        self.view_scope = sv_scope
        self.selected_continent_id = sv_cid
        self.selected_region_id    = sv_rid
        self.view_mode  = sv_mode
        self.city_bounds = sv_bounds
        self.city_border = sv_border
        self.city_fringe = sv_fringe
        return self.world_image
    end

    local city_mode = (self.city_district_maps and self.city_district_maps[start_idx])
                      and "districts"
                      or  (self.biome_colormap and "biome" or "height")

    local cox1 = math.max(1, city_mn_x - 2); local cox2 = math.min(w, city_mx_x + 2)
    local coy1 = math.max(1, city_mn_y - 2); local coy2 = math.min(h, city_mx_y + 2)
    game.world_gen_downtown_fogged_image = buildCityImg(city_mode, cox1, cox2, coy1, coy2, "downtown")
    game.world_gen_city_image            = buildCityImg(city_mode, cox1, cox2, coy1, coy2)
    game.world_gen_city_img_x            = cox1
    game.world_gen_city_img_y            = coy1
    game.world_gen_city_mn_x             = city_mn_x
    game.world_gen_city_mn_y             = city_mn_y

    local start_loc = self.city_locations[start_idx]
    local start_ci  = (start_loc.y - 1) * w + start_loc.x
    local start_cid = self.continent_map and self.continent_map[start_ci]
    local start_rid = self.region_map    and self.region_map[start_ci]

    game.world_gen_region_image    = buildWorldImg(start_rid and "region" or "world", nil, start_rid)
    game.world_gen_continent_image = buildWorldImg(start_cid and "continent" or "world", start_cid, nil)
    game.world_gen_world_image     = buildWorldImg("world", nil, nil)

    game.world_gen_city_img_min_x = self.city_img_min_x
    game.world_gen_city_img_min_y = self.city_img_min_y
    game.world_gen_city_img_K     = self.city_img_K

    -- Precompute camera params for all 5 zoom levels
    do
        local sw2, sh2 = love.graphics.getDimensions()
        local vw2 = sw2 - C.UI.SIDEBAR_WIDTH

        local function fitArea(mn_x, mx_x, mn_y, mx_y)
            local aw = (mx_x - mn_x + 1) * ts
            local ah = (mx_y - mn_y + 1) * ts
            return {
                scale = math.min(vw2 / aw, sh2 / ah) * 0.88,
                x = ((mn_x + mx_x) * 0.5 - 0.5) * ts,
                y = ((mn_y + mx_y) * 0.5 - 0.5) * ts,
            }
        end

        local cp = {}
        local S2 = C.MAP.SCALES

        do
            local dmap2  = self.city_district_maps and self.city_district_maps[start_idx]
            local sub_w2 = w * 3
            local sub_h2 = h * 3
            local mn_scx, mx_scx = sub_w2, -1
            local mn_scy, mx_scy = sub_h2, -1
            if dmap2 then
                for sci2, poi_idx2 in pairs(dmap2) do
                    if poi_idx2 == 1 then
                        local gscx2 = (sci2 - 1) % sub_w2
                        local gscy2 = math.floor((sci2 - 1) / sub_w2)
                        if gscx2 < mn_scx then mn_scx = gscx2 end
                        if gscx2 > mx_scx then mx_scx = gscx2 end
                        if gscy2 < mn_scy then mn_scy = gscy2 end
                        if gscy2 > mx_scy then mx_scy = gscy2 end
                    end
                end
            end
            if mx_scx >= mn_scx then
                local px_x1 = mn_scx / 3 * ts
                local px_x2 = (mx_scx + 1) / 3 * ts
                local px_y1 = mn_scy / 3 * ts
                local px_y2 = (mx_scy + 1) / 3 * ts
                local area_w2 = px_x2 - px_x1
                local area_h2 = px_y2 - px_y1
                cp[S2.DOWNTOWN] = {
                    scale = math.min(vw2 / area_w2, sh2 / area_h2) * 0.88,
                    x = (px_x1 + px_x2) * 0.5,
                    y = (px_y1 + px_y2) * 0.5,
                }
            else
                cp[S2.DOWNTOWN] = fitArea(city_mn_x, city_mx_x, city_mn_y, city_mx_y)
            end
        end

        cp[S2.CITY] = fitArea(city_mn_x, city_mx_x, city_mn_y, city_mx_y)

        do
            local rmin_x, rmax_x, rmin_y, rmax_y = w+1, 0, h+1, 0
            if start_rid and self.region_map then
                for i = 1, w*h do
                    if self.region_map[i] == start_rid then
                        local rx = (i-1)%w+1; local ry = math.floor((i-1)/w)+1
                        if rx<rmin_x then rmin_x=rx end; if rx>rmax_x then rmax_x=rx end
                        if ry<rmin_y then rmin_y=ry end; if ry>rmax_y then rmax_y=ry end
                    end
                end
            end
            cp[S2.REGION] = (rmax_x >= rmin_x) and fitArea(rmin_x, rmax_x, rmin_y, rmax_y)
                                                 or  fitArea(1, w, 1, h)
        end

        do
            local cmin_x, cmax_x, cmin_y, cmax_y = w+1, 0, h+1, 0
            if start_cid and self.continent_map then
                for i = 1, w*h do
                    if self.continent_map[i] == start_cid then
                        local cx2 = (i-1)%w+1; local cy2 = math.floor((i-1)/w)+1
                        if cx2<cmin_x then cmin_x=cx2 end; if cx2>cmax_x then cmax_x=cx2 end
                        if cy2<cmin_y then cmin_y=cy2 end; if cy2>cmax_y then cmax_y=cy2 end
                    end
                end
            end
            cp[S2.CONTINENT] = (cmax_x >= cmin_x) and fitArea(cmin_x, cmax_x, cmin_y, cmax_y)
                                                    or  fitArea(1, w, 1, h)
        end

        cp[S2.WORLD] = fitArea(1, w, 1, h)
        game.world_gen_cam_params = cp
    end
end

-- ── Send to Game ──────────────────────────────────────────────────────────────
-- Converts the world sandbox data into a game Map (1 world-cell = 1 game tile)
-- and replaces game.maps.city, then resets vehicles/clients exactly like F9's
-- SandboxController:sendToMainGame().

function WorldSandboxController:sendToGame()
    local game = self.game
    local C    = game.C
    local w    = self.world_w
    local h    = self.world_h

    if not self.city_locations or #self.city_locations == 0 then
        self.status_text = "Place cities first"; return
    end
    if not self.city_bounds_list then
        self.status_text = "Run Regen Bounds first"; return
    end

    -- Auto-generate sub-systems if regen_bounds was run but sub-steps are missing
    if not self.city_district_maps then self:_gen_all_districts() end
    if not self.city_arterial_maps  then self:_gen_all_arterials() end
    if not self.city_street_maps    then self:_gen_all_streets() end

    -- Pick a random starting city
    local start_idx = love.math.random(1, #self.city_locations)
    local start_bounds = self.city_bounds_list[start_idx]
    if not start_bounds then start_idx = 1; start_bounds = self.city_bounds_list[1] end

    -- Compute starting city bounding box in world coords
    local city_mn_x, city_mx_x, city_mn_y, city_mx_y = w+1, 0, h+1, 0
    for ci in pairs(start_bounds) do
        local cx = (ci-1)%w+1; local cy = math.floor((ci-1)/w)+1
        if cx < city_mn_x then city_mn_x = cx end; if cx > city_mx_x then city_mx_x = cx end
        if cy < city_mn_y then city_mn_y = cy end; if cy > city_mx_y then city_mx_y = cy end
    end
    -- Safety fallback
    if city_mn_x > city_mx_x then city_mn_x=1; city_mx_x=30; city_mn_y=1; city_mx_y=30 end

    local sw = w * 3   -- sub-cell row width (global)

    -- art_sci[sci] = true for sub-cells with arterial roads (direct, no conversion)
    local art_sci = {}
    for idx = 1, #self.city_locations do
        local amap = self.city_arterial_maps and self.city_arterial_maps[idx]
        if amap then
            for sci in pairs(amap) do art_sci[sci] = true end
        end
    end

    -- dt_sci[sci] = true for district-1 (downtown) sub-cells
    local poi1 = self.city_pois_list and self.city_pois_list[start_idx]
                 and self.city_pois_list[start_idx][1]
    local dt_sci = {}
    local dmap_dt = self.city_district_maps and self.city_district_maps[start_idx]
    if dmap_dt then
        for sci, poi_idx_v in pairs(dmap_dt) do
            if poi_idx_v == 1 then dt_sci[sci] = true end
        end
    end
    if not next(dt_sci) and poi1 then
        -- Fallback: DT_RADIUS circle of world cells → mark all 9 sub-cells each
        local DT_RADIUS = 6
        for ci in pairs(start_bounds) do
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

    -- all_claimed[ci] = city_idx (world-cell, for city vs terrain distinction)
    local all_claimed = {}
    for idx = 1, #self.city_locations do
        local bnds = self.city_bounds_list and self.city_bounds_list[idx]
        if bnds then
            for ci in pairs(bnds) do all_claimed[ci] = idx end
        end
    end

    -- Sub-cell grid dimensions
    local cw = city_mx_x - city_mn_x + 1
    local ch = city_mx_y - city_mn_y + 1
    local sub_cw = cw * 3
    local sub_ch = ch * 3
    local gscx_off = (city_mn_x - 1) * 3  -- global sub-cell x offset for local (0,0)
    local gscy_off = (city_mn_y - 1) * 3  -- global sub-cell y offset for local (0,0)

    -- Augmented street maps: original streets PLUS a street boundary on every side
    -- of each arterial / highway world cell, giving the |arterial| pattern.
    local aug_street_maps = {}
    do
        local art_sw = w * 3
        for idx = 1, #self.city_locations do
            local orig = self.city_street_maps and self.city_street_maps[idx]
            local aug_v, aug_h = {}, {}
            if orig then
                for k in pairs(orig.v or {}) do aug_v[k] = true end
                for k in pairs(orig.h or {}) do aug_h[k] = true end
            end
            -- Streets alongside arterial sub-cells (per-city map)
            local amap = self.city_arterial_maps and self.city_arterial_maps[idx]
            if amap then
                local done = {}
                for sci in pairs(amap) do
                    local gscx_a = (sci - 1) % art_sw
                    local gscy_a = math.floor((sci - 1) / art_sw)
                    local wcx = math.floor(gscx_a / 3) + 1
                    local wcy = math.floor(gscy_a / 3) + 1
                    local ci  = (wcy - 1) * w + wcx
                    if not done[ci] then
                        done[ci] = true
                        aug_v[(wcx - 1) * 1000 + wcy] = true
                        aug_v[wcx       * 1000 + wcy] = true
                        aug_h[(wcy - 1) * 1000 + wcx] = true
                        aug_h[wcy       * 1000 + wcx] = true
                    end
                end
            end
            -- Streets alongside highway world cells (global map, filtered to city bounds)
            local hmap = self.highway_map
            local bnds = self.city_bounds_list and self.city_bounds_list[idx]
            if hmap and bnds then
                for ci in pairs(bnds) do
                    if hmap[ci] then
                        local wcx = (ci - 1) % w + 1
                        local wcy = math.floor((ci - 1) / w) + 1
                        aug_v[(wcx - 1) * 1000 + wcy] = true
                        aug_v[wcx       * 1000 + wcy] = true
                        aug_h[(wcy - 1) * 1000 + wcx] = true
                        aug_h[wcy       * 1000 + wcx] = true
                    end
                end
            end
            aug_street_maps[idx] = { v = aug_v, h = aug_h }
        end
        self.aug_street_maps = aug_street_maps
    end

    -- is_street_sc[lscy*sub_cw+lscx] = true for street boundary sub-cells
    local is_street_sc = {}
    local function mark_street_sc(lscx, lscy)
        if lscx >= 0 and lscx < sub_cw and lscy >= 0 and lscy < sub_ch then
            is_street_sc[lscy * sub_cw + lscx] = true
        end
    end

    -- Original city streets (world-cell boundaries from city_street_maps)
    for idx = 1, #self.city_locations do
        local smap = self.city_street_maps and self.city_street_maps[idx]
        if smap then
            for key in pairs(smap.v or {}) do
                local cx  = math.floor(key / 1000); local wy = key % 1000
                local lscx  = cx * 3 - gscx_off
                local lscy0 = (wy - 1) * 3 - gscy_off
                for dlscy = 0, 2 do mark_street_sc(lscx, lscy0 + dlscy) end
            end
            for key in pairs(smap.h or {}) do
                local cy  = math.floor(key / 1000); local wx = key % 1000
                local lscy  = cy * 3 - gscy_off
                local lscx0 = (wx - 1) * 3 - gscx_off
                for dlscx = 0, 2 do mark_street_sc(lscx0 + dlscx, lscy) end
            end
        end
    end


    -- Build tile grid at SUB-CELL resolution: 1 tile = 1 sub-cell = 1/3 world cell
    local grid = {}
    local p = self.params
    for lscy = 0, sub_ch - 1 do
        grid[lscy + 1] = {}
        local wcy  = city_mn_y + math.floor(lscy / 3)
        local gscy = gscy_off + lscy
        for lscx = 0, sub_cw - 1 do
            local wcx  = city_mn_x + math.floor(lscx / 3)
            local gscx = gscx_off + lscx
            local ci   = (wcy - 1) * w + wcx
            local sci  = gscy * sw + gscx + 1
            local tile
            if art_sci[sci] then
                -- Sub-cell-level check: only the actual road-path sub-cells are typed
                -- as highway/arterial. Sub-cells in the same world cell that the path
                -- did NOT touch remain as plot, so buildings can be placed beside roads.
                if self.highway_map and self.highway_map[ci] then
                    tile = "highway"
                else
                    tile = "arterial"
                end
            elseif all_claimed[ci] then
                -- Roads are lines between sub-cells, not tiles.  All claimed
                -- city sub-cells (including former road positions) are plots.
                tile = dt_sci[sci] and "downtown_plot" or "plot"
            else
                local elev = (self.heightmap and self.heightmap[wcy] and self.heightmap[wcy][wcx]) or 0.5
                if     elev <= (p.ocean_max    or 0.42) then tile = "water"
                elseif elev >= (p.highland_max or 0.80) then tile = "mountain"
                else                                          tile = "grass" end
            end
            grid[lscy + 1][lscx + 1] = {type = tile}
        end
    end

    -- River sub-cell injection: organic corridors following world-tile river paths.
    --
    -- Each tile has a "hub" at (hub_r, hub_c) derived deterministically from world coords.
    -- All connections (N/S/E/W) route straight to the hub, so every tile is internally
    -- connected and adjacent tiles always share the same edge sub-cell → guaranteed continuity.
    --
    -- Hub column (hub_c) is consistent per world-x column  → N-S connections always match.
    -- Hub row    (hub_r) is consistent per world-y row     → E-W connections always match.
    -- Period-7 lookup tables produce 0/1/2 with no short cycles, so the path varies.
    --
    -- Arterials/highways are skipped — the gap implies a bridge crossing.
    do
        local bdata = self.biome_data or {}

        local _COL_HASH = {0, 2, 1, 2, 0, 1, 2}  -- period 7 → hub column per wx
        local _ROW_HASH = {1, 0, 2, 0, 2, 1, 0}  -- period 7 → hub row per wy
        local function hub_col(wx2) return _COL_HASH[wx2 % 7 + 1] end
        local function hub_row(wy2) return _ROW_HASH[wy2 % 7 + 1] end

        local function mr(gx, gy)
            if gx < 1 or gx > sub_cw or gy < 1 or gy > sub_ch then return end
            local t = grid[gy][gx].type
            if t ~= "arterial" and t ~= "highway" then
                grid[gy][gx] = {type = "river"}
            end
        end

        -- Straight path from (r1,c1) to (r2,c2) via row-first L (then column).
        local function route(lb_x, lb_y, r1, c1, r2, c2)
            local r, c = r1, c1
            mr(lb_x+c+1, lb_y+r+1)
            while r ~= r2 do r = r + (r2 > r and 1 or -1); mr(lb_x+c+1, lb_y+r+1) end
            while c ~= c2 do c = c + (c2 > c and 1 or -1); mr(lb_x+c+1, lb_y+r+1) end
        end

        local function is_riv(wx2, wy2)
            if wx2 < 1 or wx2 > w or wy2 < 1 or wy2 > h then return false end
            local bd2 = bdata[(wy2-1)*w+wx2]
            return bd2 and bd2.is_river
        end

        for wy = city_mn_y, city_mx_y do
            for wx = city_mn_x, city_mx_x do
                local ci = (wy - 1) * w + wx
                local bd = bdata[ci]
                if bd and bd.is_river then
                    local lb_x = (wx - city_mn_x) * 3
                    local lb_y = (wy - city_mn_y) * 3
                    local hc   = hub_col(wx)   -- 0-indexed hub column (N/S axis)
                    local hr   = hub_row(wy)   -- 0-indexed hub row    (E/W axis)

                    local has_n = is_riv(wx, wy-1)
                    local has_e = is_riv(wx+1, wy)
                    local has_s = is_riv(wx, wy+1)
                    local has_w = is_riv(wx-1, wy)

                    -- Always mark the hub (keeps isolated/terminus tiles visible)
                    mr(lb_x+hc+1, lb_y+hr+1)

                    -- Route each connection straight to the hub
                    if has_n then route(lb_x, lb_y, 0,  hc, hr, hc) end  -- top-edge → hub
                    if has_s then route(lb_x, lb_y, 2,  hc, hr, hc) end  -- bottom-edge → hub
                    if has_w then route(lb_x, lb_y, hr,  0, hr, hc) end  -- left-edge → hub
                    if has_e then route(lb_x, lb_y, hr,  2, hr, hc) end  -- right-edge → hub

                    -- Diagonal connections: rivers use D8 flow.
                    -- Route hub to the corner sub-cell facing the diagonal neighbor.
                    -- Both tiles touch at their corners → 8-directional connectivity.
                    local DIAG = {{1,1},{1,-1},{-1,1},{-1,-1}}
                    for _, dv in ipairs(DIAG) do
                        local dx, dy = dv[1], dv[2]
                        if is_riv(wx+dx, wy+dy)
                           and not is_riv(wx+dx, wy)
                           and not is_riv(wx, wy+dy)
                        then
                            local cr = dy == 1 and 2 or 0
                            local cc = dx == 1 and 2 or 0
                            route(lb_x, lb_y, hr, hc, cr, cc)
                        end
                    end
                end
            end
        end
    end

    -- Downtown bounding box: scan sub-cell tile grid for downtown_road / downtown_plot
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
        -- Fallback: use POI position converted to sub-cell local coords
        local poi = self.city_pois_list and self.city_pois_list[start_idx] and self.city_pois_list[start_idx][1]
        if poi then
            local lscx = (poi.x - city_mn_x) * 3 + 1
            local lscy = (poi.y - city_mn_y) * 3 + 1
            local r = 18  -- ~6 world cells * 3
            dt_mn_x = math.max(1, lscx - r); dt_mx_x = math.min(sub_cw, lscx + r)
            dt_mn_y = math.max(1, lscy - r); dt_mx_y = math.min(sub_ch, lscy + r)
        else
            dt_mn_x = 1; dt_mx_x = 30; dt_mn_y = 1; dt_mx_y = 30
        end
    end

    local Map     = require("models.Map")
    local new_map = Map:new(C)
    new_map.city_grid_width      = sub_cw
    new_map.city_grid_height     = sub_ch
    new_map.downtown_grid_width  = math.max(1, dt_mx_x - dt_mn_x + 1)
    new_map.downtown_grid_height = math.max(1, dt_mx_y - dt_mn_y + 1)
    new_map.grid            = grid
    new_map.downtown_offset = {x = dt_mn_x, y = dt_mn_y}
    new_map.tile_pixel_size = C.MAP.TILE_SIZE / 3   -- 2/3 world px per sub-cell tile
    new_map.building_plots  = {}  -- populated below in road-node block

    -- ── Zone grid, road network, and image building ───────────────────────────
    local ctx = {
        sub_cw = sub_cw, sub_ch = sub_ch,
        gscx_off = gscx_off, gscy_off = gscy_off,
        sw = sw, w = w, start_idx = start_idx,
        grid = grid, city_mn_x = city_mn_x, city_mn_y = city_mn_y,
    }
    self:_buildZoneGrid(new_map, ctx)
    self:_buildRoadNetwork(new_map, ctx)
    self:_buildGameImages(game, start_idx, city_mn_x, city_mx_x, city_mn_y, city_mx_y, w, h)

    -- Store district data on map for the district overlay in GameView
    new_map.district_map    = self.city_district_maps and self.city_district_maps[start_idx]
    new_map.district_types  = self.city_district_types and self.city_district_types[start_idx]
    new_map.district_colors = self.city_district_colors and self.city_district_colors[start_idx]
    new_map.district_pois   = self.city_pois_list and self.city_pois_list[start_idx]
    new_map.zone_gscx_off   = gscx_off
    new_map.zone_gscy_off   = gscy_off
    new_map.zone_sw         = sw

    -- Store world biome data for the biome overlay in GameView
    new_map.world_biome_data = self.biome_data
    new_map.world_city_mn_x  = city_mn_x
    new_map.world_city_mn_y  = city_mn_y
    new_map.world_city_mx_x  = city_mx_x
    new_map.world_city_mx_y  = city_mx_y
    new_map.world_w          = w

    -- Stamp onto game
    game.maps.city      = new_map
    game.active_map_key = "city"

    -- Reset vehicles
    local States    = require("models.vehicles.vehicle_states")
    local new_depot = new_map:getRandomDowntownBuildingPlot() or new_map:getRandomBuildingPlot()
    game.entities.depot_plot = new_depot
    -- Find the road node (gap position) adjacent to the depot.
    -- Check all 4 corners of the depot sub-cell; prefer road_v column positions
    -- so the pathfinder can navigate there directly via horizontal movement.
    local depot_road = nil
    if new_depot then
        local gx, gy = new_depot.x, new_depot.y
        local road_v = new_map.road_v_rxs
        for _, c in ipairs({{gx-1, gy-1}, {gx, gy-1}, {gx-1, gy}, {gx, gy}}) do
            local rx, ry = c[1], c[2]
            if new_map.road_nodes and new_map.road_nodes[ry] and new_map.road_nodes[ry][rx] then
                if not road_v or road_v[rx] then
                    depot_road = {x=rx, y=ry}
                    break
                elseif not depot_road then
                    depot_road = {x=rx, y=ry}
                end
            end
        end
    end
    for _, v in ipairs(game.entities.vehicles) do
        v.cargo = {}; v.trip_queue = {}; v.path = {}
        if new_depot then
            v.depot_plot  = new_depot
            v.grid_anchor = depot_road or {x = new_depot.x - 1, y = new_depot.y - 1}
            if v.recalculatePixelPosition then v:recalculatePixelPosition(game) end
        end
        if States and States.Idle then v:changeState(States.Idle, game) end
    end

    -- Reset trips and respawn clients
    game.entities.trips.pending = {}
    local num_clients = math.max(1, #game.entities.clients)
    game.entities.clients = {}
    for _ = 1, num_clients do
        game.entities:addClient(game)
    end

    -- Persist city markers for game-view world map rendering
    game.world_city_locations = self.city_locations
    game.world_w              = self.world_w
    game.world_h              = self.world_h

    -- Zoom to downtown and close sandbox
    local ok, err = pcall(function()
        game.maps.city:setScale(C.MAP.SCALES.DOWNTOWN, game)
    end)
    if not ok then print("WorldSandbox sendToGame: setScale failed: " .. tostring(err)) end

    self:close()
end

-- ── Generation ────────────────────────────────────────────────────────────────

function WorldSandboxController:generate()
    local p  = self.params
    local w  = math.max(50, math.floor(p.world_w))
    local h  = math.max(50, math.floor(p.world_h))
    self.status_text = "Generating..."

    local ok, result = pcall(function()
        return require("services.WorldNoiseService").generate(w, h, p)
    end)

    if ok then
        self.heightmap            = result.heightmap
        self.colormap             = result.colormap
        self.biome_colormap       = result.biome_colormap
        self.biome_data           = result.biome_data
        self.suitability_colormap = result.suitability_colormap
        self.suitability_scores   = result.suitability_scores
        self.continent_colormap   = result.continent_colormap
        self.continent_map        = result.continent_map
        self.continents           = result.continents
        self.region_colormap      = result.region_colormap
        self.region_map           = result.region_map
        self.regions_list         = result.regions_list
        self.city_locations        = nil
        self.highway_map           = nil
        self.city_bounds           = nil
        self.city_border           = nil
        self.city_fringe           = nil
        self.city_pois             = nil
        self.city_bounds_list      = nil
        self.selected_city_idx     = nil
        self.selected_city_bounds  = nil
        self.city_image            = nil
        self.view_scope            = "world"
        self.scope_mode            = nil
        self.selected_continent_id = nil
        self.selected_region_id    = nil
        self.world_w               = w
        self.world_h               = h
        self:_buildImage()
        self:_centerCamera()
        self.status_text = string.format("Generated %dx%d  |  F8 close  |  RMB pan  |  Wheel zoom", w, h)
    else
        self.status_text = "FAILED: " .. tostring(result)
    end
end

function WorldSandboxController:_buildImage()
    local active = (self.view_mode == "biome"        and self.biome_colormap)
               or  (self.view_mode == "suitability"  and self.suitability_colormap)
               or  (self.view_mode == "continents"   and self.continent_colormap)
               or  (self.view_mode == "regions"      and self.region_colormap)
               or   self.colormap
    local w, h      = self.world_w, self.world_h
    local hways     = self.highway_map
    local cbounds   = self.city_bounds
    local cborder   = self.city_border
    local cfringe   = self.city_fringe
    local sel_city_b = self.selected_city_bounds
    local cont_map  = self.continent_map
    local reg_map   = self.region_map
    local scope     = self.view_scope
    local sel_cid   = self.selected_continent_id
    local sel_rid   = self.selected_region_id
    local imgdata   = love.image.newImageData(w, h)
    for y = 1, h do
        for x = 1, w do
            local i = (y-1)*w + x
            -- Determine if this cell is in the current scope
            local in_scope = true
            if scope == "continent" and sel_cid then
                in_scope = (cont_map and cont_map[i] == sel_cid)
            elseif scope == "region" and sel_rid then
                in_scope = (reg_map and reg_map[i] == sel_rid)
            elseif scope == "city" and sel_city_b then
                in_scope = (sel_city_b[i] == true)
            elseif scope == "downtown" then
                in_scope = (self.selected_downtown_bounds ~= nil and self.selected_downtown_bounds[i] == true)
            end

            local c = active[y][x]
            if not in_scope then
                imgdata:setPixel(x-1, y-1, c[1]*0.18+0.01, c[2]*0.18+0.02, c[3]*0.18+0.06, 1.0)
            elseif hways and hways[i] then
                imgdata:setPixel(x-1, y-1, 0.95, 0.78, 0.08, 1.0)
            elseif cborder and cborder[i] then
                imgdata:setPixel(x-1, y-1, 0.72, 0.42, 0.08, 1.0)
            elseif cbounds and cbounds[i] then
                imgdata:setPixel(x-1, y-1, c[1]*0.55+0.38, c[2]*0.55+0.30, c[3]*0.55+0.12, 1.0)
            elseif cfringe and cfringe[i] then
                -- Soft fringe beyond border: subtle warm bleed, breaks tile-grid hard edge
                imgdata:setPixel(x-1, y-1, c[1]*0.82+0.10, c[2]*0.82+0.07, c[3]*0.82+0.03, 1.0)
            else
                imgdata:setPixel(x-1, y-1, c[1], c[2], c[3], 1.0)
            end
        end
    end
    self.world_image = love.graphics.newImage(imgdata)
    self.world_image:setFilter("nearest", "nearest")
end

function WorldSandboxController:set_view(mode)
    self.view_mode = mode
    if self.colormap then self:_buildImage() end
    if self.view_scope == "city" and self.selected_city_idx then
        local idx = self.selected_city_idx
        local bounds = self.city_bounds_list and self.city_bounds_list[idx]
        if bounds then
            local w, h = self.world_w, self.world_h
            local min_x, max_x, min_y, max_y = w+1, 0, h+1, 0
            for ci in pairs(bounds) do
                local x = (ci-1) % w + 1; local y = math.floor((ci-1) / w) + 1
                if x < min_x then min_x = x end; if x > max_x then max_x = x end
                if y < min_y then min_y = y end; if y > max_y then max_y = y end
            end
            self:_buildCityImage(idx, min_x, max_x, min_y, max_y)
        end
    end
end

-- ── Scope (zoom level) ────────────────────────────────────────────────────────

function WorldSandboxController:enter_scope_pick(mode)
    -- mode = "picking_continent" | "picking_region"
    self.scope_mode = mode
    if mode == "picking_continent" then
        self.status_text = "Click a continent to zoom in  |  Esc to cancel"
    elseif mode == "picking_region" then
        self.status_text = "Click a region to zoom in  |  Esc to cancel"
    else
        self.status_text = "Click a city area to zoom in  |  Esc to cancel"
    end
end

function WorldSandboxController:set_scope_world()
    self.view_scope            = "world"
    self.scope_mode            = nil
    self.selected_continent_id = nil
    self.selected_region_id    = nil
    if self.colormap then
        self:_buildImage()
        self:_centerCamera()
    end
    self.status_text = string.format("World view  |  %dx%d  |  RMB pan  |  Wheel zoom", self.world_w, self.world_h)
end

function WorldSandboxController:_fitToArea(min_x, max_x, min_y, max_y)
    local C  = self.game.C
    local ts = C.MAP.TILE_SIZE
    local sw, sh = love.graphics.getDimensions()
    local vw = sw - C.UI.SIDEBAR_WIDTH
    local area_w = (max_x - min_x + 1) * ts
    local area_h = (max_y - min_y + 1) * ts
    self.camera.scale = math.min(vw / area_w, sh / area_h) * 0.88
    self.camera.x = ((min_x + max_x) * 0.5 - 0.5) * ts
    self.camera.y = ((min_y + max_y) * 0.5 - 0.5) * ts
end

function WorldSandboxController:_selectContinent(cid)
    if not self.continent_map or not cid or cid == 0 then return end
    local w, h   = self.world_w, self.world_h
    local cmap   = self.continent_map
    local min_x, max_x, min_y, max_y = w+1, 0, h+1, 0
    for i = 1, w*h do
        if cmap[i] == cid then
            local x = (i-1) % w + 1
            local y = math.floor((i-1) / w) + 1
            if x < min_x then min_x = x end
            if x > max_x then max_x = x end
            if y < min_y then min_y = y end
            if y > max_y then max_y = y end
        end
    end
    if max_x < min_x then return end
    self.selected_continent_id = cid
    self.selected_region_id    = nil
    self.view_scope            = "continent"
    self.scope_mode            = nil
    self:_buildImage()
    self:_fitToArea(min_x, max_x, min_y, max_y)
    self.status_text = string.format("Continent view  |  RMB pan  |  Wheel zoom  |  Click 'World' to zoom out")
end

function WorldSandboxController:_selectRegion(rid)
    if not self.region_map or not rid or rid == 0 then return end
    local w, h   = self.world_w, self.world_h
    local rmap   = self.region_map
    local min_x, max_x, min_y, max_y = w+1, 0, h+1, 0
    for i = 1, w*h do
        if rmap[i] == rid then
            local x = (i-1) % w + 1
            local y = math.floor((i-1) / w) + 1
            if x < min_x then min_x = x end
            if x > max_x then max_x = x end
            if y < min_y then min_y = y end
            if y > max_y then max_y = y end
        end
    end
    if max_x < min_x then return end
    -- Keep selected continent consistent with the region
    local sample_cid = nil
    for i = 1, w*h do
        if rmap[i] == rid then
            sample_cid = self.continent_map and self.continent_map[i]
            break
        end
    end
    self.selected_region_id    = rid
    self.selected_continent_id = sample_cid
    self.view_scope            = "region"
    self.scope_mode            = nil
    self:_buildImage()
    self:_fitToArea(min_x, max_x, min_y, max_y)
    self.status_text = "Region view  |  RMB pan  |  Wheel zoom  |  Click 'World' to zoom out"
end

function WorldSandboxController:place_cities()
    if not self.suitability_scores then return end
    local total_count = math.max(1, math.floor(self.params.city_count  or 12))
    local min_sep     = math.max(1, math.floor(self.params.city_min_sep or 30))
    local w           = self.world_w
    local scores      = self.suitability_scores
    local cont_map    = self.continent_map
    local conts       = self.continents
    local reg_map     = self.region_map
    local reg_list    = self.regions_list

    -- Fall back to flat greedy if no continent/region data
    if not cont_map or not conts or #conts == 0 or not reg_map or not reg_list then
        local cands = {}
        for i = 1, w * self.world_h do
            local s = scores[i] or 0
            if s > 0 then
                cands[#cands + 1] = { x=(i-1)%w+1, y=math.floor((i-1)/w)+1, s=s }
            end
        end
        table.sort(cands, function(a, b) return a.s > b.s end)
        local cities, sq = {}, min_sep * min_sep
        for _, c in ipairs(cands) do
            local ok = true
            for _, p2 in ipairs(cities) do
                local dx, dy = c.x-p2.x, c.y-p2.y
                if dx*dx+dy*dy < sq then ok=false; break end
            end
            if ok then cities[#cities+1]=c end
            if #cities >= total_count then break end
        end
        self.city_locations = cities
        return
    end

    -- Step 1: proportional city allocation per continent (largest-remainder)
    local total_land = 0
    for _, c in ipairs(conts) do total_land = total_land + c.size end
    if total_land == 0 then return end

    local allocs     = {}
    local alloc_sum  = 0
    local remainders = {}
    for i, c in ipairs(conts) do
        local exact   = total_count * c.size / total_land
        local floor_v = math.floor(exact)
        allocs[i]     = floor_v
        alloc_sum     = alloc_sum + floor_v
        remainders[i] = { idx = i, rem = exact - floor_v }
    end
    table.sort(remainders, function(a, b) return a.rem > b.rem end)
    for k = 1, math.min(total_count - alloc_sum, #remainders) do
        allocs[remainders[k].idx] = allocs[remainders[k].idx] + 1
    end

    -- Step 2: build per-region sorted candidate lists, grouped by continent
    local cont_id_to_idx = {}
    for i, c in ipairs(conts) do cont_id_to_idx[c.id] = i end

    -- reg_cands[rid] = sorted candidates; cont_regions[ci] = list of rids
    local reg_cands    = {}
    local cont_regions = {}
    for i = 1, #conts do cont_regions[i] = {} end

    for i = 1, w * self.world_h do
        local s   = scores[i] or 0
        local rid = reg_map[i] or 0
        if s > 0 and rid > 0 and reg_list[rid] then
            local ci = cont_id_to_idx[reg_list[rid].continent_id]
            if ci then
                if not reg_cands[rid] then
                    reg_cands[rid] = {}
                    cont_regions[ci][#cont_regions[ci]+1] = rid
                end
                local t = reg_cands[rid]
                t[#t+1] = { x=(i-1)%w+1, y=math.floor((i-1)/w)+1, s=s }
            end
        end
    end
    for _, cands in pairs(reg_cands) do
        table.sort(cands, function(a, b) return a.s > b.s end)
    end

    local reg_count = {}
    local reg_ptr   = {}
    for rid in pairs(reg_cands) do
        reg_count[rid] = 0
        reg_ptr[rid]   = 1
    end

    -- All placed cities (global, for min_sep enforcement across continents)
    local all_cities = {}
    local sq         = min_sep * min_sep

    -- Step 3: per-continent placement. Each pick selects the globally highest-
    -- scoring candidate from any region on that continent that is currently at
    -- the minimum city count. Regions above the minimum are locked until all
    -- catch up, ensuring every region gets one city before any gets two.
    for ci, c_rids in ipairs(cont_regions) do
        local want = allocs[ci]
        local placed = 0

        while placed < want do
            -- Find minimum city count among regions with remaining candidates
            local min_count = math.huge
            for _, rid in ipairs(c_rids) do
                if reg_ptr[rid] <= #reg_cands[rid] then
                    min_count = math.min(min_count, reg_count[rid])
                end
            end
            if min_count == math.huge then break end  -- all regions exhausted

            -- Among all regions at the minimum, find the single best unblocked candidate
            local best_c   = nil
            local best_rid = nil
            local best_idx = nil
            local best_s   = -1

            for _, rid in ipairs(c_rids) do
                if reg_count[rid] == min_count then
                    local cands = reg_cands[rid]
                    for idx = reg_ptr[rid], #cands do
                        local c = cands[idx]
                        local ok = true
                        for _, p2 in ipairs(all_cities) do
                            local dx, dy = c.x-p2.x, c.y-p2.y
                            if dx*dx+dy*dy < sq then ok=false; break end
                        end
                        if ok then
                            if c.s > best_s then
                                best_s = c.s; best_c = c; best_rid = rid; best_idx = idx
                            end
                            break  -- candidates sorted; first unblocked is best for this region
                        end
                    end
                end
            end

            if not best_c then break end  -- nothing placeable (min_sep too large)

            reg_ptr[best_rid] = best_idx + 1
            all_cities[#all_cities+1] = best_c
            reg_count[best_rid] = reg_count[best_rid] + 1
            placed = placed + 1
        end
    end

    self.city_locations = all_cities
    -- Generate bounds + POIs for all placed cities right away
    if self.region_map and self.heightmap then
        self:_gen_all_bounds()
    end
end

function WorldSandboxController:build_highways()
    if not self.city_locations or #self.city_locations == 0 then return end
    if not self.heightmap or not self.continent_map then return end

    local p        = self.params
    local w, h     = self.world_w, self.world_h
    local cities   = self.city_locations
    local cont_map = self.continent_map
    local hmap     = self.heightmap
    local bdata    = self.biome_data
    local mtn_cost   = math.max(1, p.highway_mountain_cost or 10)
    local riv_cost   = math.max(0, p.highway_river_cost    or 3)
    local slope_cost = math.max(0, p.highway_slope_cost    or 15)
    local budget_scale = math.max(1, p.highway_budget_scale or 800)

    local highway_map = {}

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
                        for _, ci in ipairs(path) do highway_map[ci] = true end
                        local fa = budget[ai] / combined
                        budget[ai] = math.max(0, budget[ai] - path_cost * fa)
                        budget[bi] = math.max(0, budget[bi] - path_cost * (1 - fa))
                    end
                end
            end
        end
    end

    self.highway_map = highway_map
    self:_buildImage()
    if self.view_scope == "city" and self.selected_city_idx then
        local idx    = self.selected_city_idx
        local bnds   = self.city_bounds_list and self.city_bounds_list[idx]
        if bnds then
            local ww, wh = self.world_w, self.world_h
            local mn_x, mx_x, mn_y, mx_y = ww+1, 0, wh+1, 0
            for ci in pairs(bnds) do
                local bx = (ci-1) % ww + 1; local by = math.floor((ci-1) / ww) + 1
                if bx < mn_x then mn_x = bx end; if bx > mx_x then mx_x = bx end
                if by < mn_y then mn_y = by end; if by > mx_y then mx_y = by end
            end
            self:_buildCityImage(idx, mn_x, mx_x, mn_y, mx_y)
        end
    end
end

-- Generates bounds + POIs for a single city. Returns claimed (hash), pois (array).
-- Uses noise-perturbed costs + 8-directional movement for organic blob shape.
-- Two-phase: inner 65% of target used for POI placement so they're never on the edge.
-- Downtown = POI candidate closest to centroid of inner area.
function WorldSandboxController:_gen_bounds_for_city(city)
    if not self.region_map or not self.heightmap then return nil, nil end
    local p       = self.params
    local w, h    = self.world_w, self.world_h
    local reg_map = self.region_map
    local hmap    = self.heightmap
    local bdata   = self.biome_data
    local scores  = self.suitability_scores
    local rid     = reg_map[(city.y-1)*w + city.x] or 0
    if rid == 0 then return nil, nil end

    local region_size = 0
    for i = 1, w*h do
        if reg_map[i] == rid then region_size = region_size + 1 end
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
        local nv = love.math.noise(nx2 * 0.4 + city.x * 0.13, ny2 * 0.4 + city.y * 0.17)
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
                    if reg_map[ni] == rid and not claimed[ni] then
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

-- Regenerates city_bounds and city_pois for all currently placed cities.
function WorldSandboxController:_gen_all_bounds()
    if not self.city_locations then return end
    local new_bounds      = {}
    local new_bounds_list = {}
    local new_pois        = {}
    local new_pois_list   = {}
    for idx, city in ipairs(self.city_locations) do
        local claimed, pois = self:_gen_bounds_for_city(city)
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
    self.city_bounds_list = new_bounds_list
    self.city_pois_list   = new_pois_list
    self.city_bounds = new_bounds
    self.city_pois   = new_pois
    -- Invalidate subsystem maps so sendToGame() or regen_bounds() regenerates them fresh
    self.city_district_maps  = nil
    self.city_district_types = nil
    self.city_arterial_maps  = nil
    self.city_street_maps    = nil
    self.city_zone_grids     = nil
    self.city_zone_offsets   = nil

    local w, h = self.world_w, self.world_h

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
    self.city_border = border

    -- Fringe: noise-based expansion 1 cell beyond bounds for sub-tile soft edge
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
                    local nv = love.math.noise(nx2 * 4.3 + 0.5, ny2 * 3.7 + 0.5)
                    if nv > 0.40 then fringe[ni] = true end
                end
            end
        end
    end
    self.city_fringe = fringe

end

-- ── Sub-cell elevation ────────────────────────────────────────────────────────

-- Each world cell contains 3×3 sub-cells. Their elevations are derived by
-- combining the parent world-cell elevation with two noise octaves at sub-cell
-- frequency. This gives each sub-cell its own character (biome variation,
-- organic district boundaries) without touching the world-gen pipeline.
--
-- Noise seeds are offset far from world-gen seeds so they don't correlate.
-- Amplitudes are kept small so sub-cells stay in the same biome family as
-- their parent; they add texture, not radical terrain changes.
local SC_DETAIL_FREQ = 0.55   -- high-freq: varies every ~2 sub-cells
local SC_DETAIL_AMP  = 0.08   -- ±0.08 elevation delta from fine noise
local SC_MEDIUM_FREQ = 0.18   -- mid-freq: city-scale undulation
local SC_MEDIUM_AMP  = 0.04   -- ±0.04 from medium noise

local function subcell_elev_at(gscx, gscy, hmap)
    local wx   = math.floor(gscx / 3)
    local wy   = math.floor(gscy / 3)
    local base = hmap[wy + 1][wx + 1]
    local d = (love.math.noise(gscx * SC_DETAIL_FREQ + 100.3, gscy * SC_DETAIL_FREQ + 73.1) - 0.5) * SC_DETAIL_AMP * 2
    local m = (love.math.noise(gscx * SC_MEDIUM_FREQ + 200.7, gscy * SC_MEDIUM_FREQ + 31.9) - 0.5) * SC_MEDIUM_AMP * 2
    return base + d + m
end

-- ── District flood-fill ───────────────────────────────────────────────────────

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

function WorldSandboxController:_gen_all_districts()
    local maps   = {}
    local colors = {}
    for idx = 1, #(self.city_locations or {}) do
        maps[idx], colors[idx] = self:_gen_districts_for_city(idx)
    end
    self.city_district_maps   = maps
    self.city_district_colors = colors
end

-- Multi-source Dijkstra at sub-cell resolution (3×3 per world cell).
-- Sub-cell elevations come from subcell_elev_at(), which adds noise on top of
-- the world-cell baseline. This gives genuine intra-cell elevation variation,
-- so the flood-fill can draw district boundaries that meander through sub-cells.
-- Returns district_map ([sub_cell_idx] = poi_idx) and color table ([poi_idx] = {r,g,b}).
function WorldSandboxController:_gen_districts_for_city(city_idx)
    local bounds = self.city_bounds_list and self.city_bounds_list[city_idx]
    local pois   = self.city_pois_list   and self.city_pois_list[city_idx]
    if not bounds or not pois or #pois == 0 then return {}, {} end

    local w     = self.world_w
    local h     = self.world_h
    local sub_w = w * 3
    local sub_h = h * 3
    local hmap  = self.heightmap
    local bdata = self.biome_data

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
            local from_e = subcell_elev_at(gscx, gscy, hmap)

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
                        local to_e   = subcell_elev_at(nx2, ny2, hmap)
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
    local p = self.params
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

-- ── Arterial roads ────────────────────────────────────────────────────────────
-- Phase 1 – rasterise world-level highway onto the sub-cell grid within city
--           bounds (centre sub-cell of each highway world-cell + the two
--           bridging sub-cells between adjacent highway world-cells).
-- Phase 2 – direction-aware 8-directional Dijkstra from each POI to the
--           growing road network (nearest-first so the trunk forms first).
--           State = sci*8+dir.  Sub-cell slope cost from subcell_elev_at()
--           makes routes curve around terrain naturally.
-- Phase 3 – close the loop: sort POIs by angle from city centroid and route
--           each to the next (wrapping last→first) so no road ends blind.

local ART_TURN_45   = 1    -- near-free: allows smooth curves
local ART_TURN_90   = 10   -- moderate heading change
local ART_TURN_135  = 28   -- heavy
local ART_TURN_180  = 65   -- brutal U-turn
local ART_ON_ROAD   = 0.05 -- cost multiplier on existing arterial sub-cell
local ART_ON_HWY    = 0.65 -- cost multiplier inside a highway world-cell
local ART_NOISE_AMP = 2.2  -- additive noise amplitude (forces organic deviation)
local ART_SLOPE_W   = 28.0 -- sub-cell slope penalty weight

function WorldSandboxController:_gen_arterials_for_city(city_idx)
    local bounds = self.city_bounds_list and self.city_bounds_list[city_idx]
    local pois   = self.city_pois_list   and self.city_pois_list[city_idx]
    if not bounds or not pois or #pois == 0 then return {} end

    local w     = self.world_w
    local h     = self.world_h
    local sw    = w * 3
    local sh    = h * 3
    local hmap  = self.heightmap
    local bdata = self.biome_data
    local hways = self.highway_map or {}
    local p     = self.params

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
        local from_e = subcell_elev_at(fx, fy, hmap)
        local to_e   = subcell_elev_at(tx, ty, hmap)
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

        base = base + love.math.noise(tx * 0.22 + 50.3, ty * 0.22 + 27.9) * ART_NOISE_AMP
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

function WorldSandboxController:_gen_all_arterials()
    local maps = {}
    for idx = 1, #(self.city_locations or {}) do
        maps[idx] = self:_gen_arterials_for_city(idx)
    end
    self.city_arterial_maps = maps
end

-- ── Zone-boundary street generator ───────────────────────────────────────────
-- World cells are grouped into BLOCK×BLOCK-cell blocks; each block gets a
-- zone type (residential/commercial/industrial/park) chosen by district weights
-- + a deterministic position hash.  Streets appear wherever two adjacent world
-- cells belong to blocks of DIFFERENT zone type.  This produces SimCity-style
-- irregular block layouts with street grids that follow zone boundaries.
--
-- Street key format: v[cx*1000+cy]  h[cy*1000+cx]  (unchanged)

local ZONE_BLOCK = 2        -- world cells per block side (controls block coarseness)

function WorldSandboxController:_gen_streets_for_city(city_idx)
    local bounds   = self.city_bounds_list   and self.city_bounds_list[city_idx]
    local pois     = self.city_pois_list     and self.city_pois_list[city_idx]
    local dist_map = self.city_district_maps and self.city_district_maps[city_idx]
    if not bounds or not pois or #pois == 0 then return {v={},h={}} end

    local w  = self.world_w
    local h  = self.world_h
    local sw = w * 3
    local ZT = require("data.zones")
    local ZONE_STATES = {}
    for _, s in ipairs(ZT.STATES) do
        if s ~= "none" then ZONE_STATES[#ZONE_STATES + 1] = s end
    end

    local function sci_of(gscx, gscy) return gscy * sw + gscx + 1 end
    local function get_poi(wx, wy)
        if not dist_map then return 0 end
        return dist_map[sci_of((wx-1)*3+1, (wy-1)*3+1)] or 0
    end

    -- Deterministic district type for a poi index (mirrors sendToGame logic)
    local RDTYPES = ZT.RANDOM_DISTRICT_TYPES
    local function poi_dtype(poi_idx)
        if poi_idx <= 1 then return "downtown" end
        return RDTYPES[((city_idx * 7 + poi_idx * 13) % #RDTYPES) + 1]
    end

    -- Cache: zone type per (block_x, block_y, poi_idx) triple
    local block_cache = {}
    local function block_zone(bx, by, poi_idx)
        local key = bx * 1000000 + by * 1000 + poi_idx
        if block_cache[key] then return block_cache[key] end
        local dtype   = poi_dtype(poi_idx)
        local weights = ZT.DISTRICT_WEIGHTS[dtype] or ZT.DISTRICT_WEIGHTS["residential"]
        local total   = 0
        for _, z in ipairs(ZONE_STATES) do total = total + (weights[z] or 0) end
        -- Deterministic positional hash (no love.math.random dependency)
        local r = ((bx * 741455 + by * 1234577 + bx * by * 89137 + poi_idx * 531731) % 100000)
                  / 100000.0 * total
        if r < 0 then r = r + total end
        local zone = ZONE_STATES[#ZONE_STATES]
        local cum  = 0
        for _, z in ipairs(ZONE_STATES) do
            cum = cum + (weights[z] or 0)
            if r < cum then zone = z; break end
        end
        block_cache[key] = zone
        return zone
    end

    local function cell_zone(cx, cy)
        local bx = math.floor((cx - 1) / ZONE_BLOCK)
        local by = math.floor((cy - 1) / ZONE_BLOCK)
        return block_zone(bx, by, get_poi(cx, cy))
    end

    local sv, sh = {}, {}
    for ci in pairs(bounds) do
        local cx = (ci-1) % w + 1
        local cy = math.floor((ci-1) / w) + 1
        local z1 = cell_zone(cx, cy)

        -- Vertical boundary: right edge of (cx,cy) / left edge of (cx+1,cy)
        if cx < w then
            local r_ci = (cy-1)*w + (cx+1)
            if bounds[r_ci] and cell_zone(cx+1, cy) ~= z1 then
                sv[cx * 1000 + cy] = true
            end
        end
        -- Horizontal boundary: bottom of (cx,cy) / top of (cx,cy+1)
        if cy < h then
            local b_ci = cy*w + cx
            if bounds[b_ci] and cell_zone(cx, cy+1) ~= z1 then
                sh[cy * 1000 + cx] = true
            end
        end
    end

    return {v=sv, h=sh}
end

function WorldSandboxController:_gen_all_streets()
    local maps = {}
    for idx = 1, #(self.city_locations or {}) do
        maps[idx] = self:_gen_streets_for_city(idx)
    end
    self.city_street_maps = maps
end

function WorldSandboxController:regen_bounds()
    if not self.city_locations then
        self.status_text = "Place cities first"
        return
    end
    self:_gen_all_bounds()
    self:_gen_all_districts()
    self:_gen_all_arterials()
    self:_gen_all_streets()
    self:_buildImage()
    if self.view_scope == "city" and self.selected_city_idx then
        local idx    = self.selected_city_idx
        local bounds = self.city_bounds_list and self.city_bounds_list[idx]
        if bounds then
            local ww, wh = self.world_w, self.world_h
            local min_x, max_x, min_y, max_y = ww+1, 0, wh+1, 0
            for ci in pairs(bounds) do
                local x = (ci-1) % ww + 1; local y = math.floor((ci-1) / ww) + 1
                if x < min_x then min_x = x end; if x > max_x then max_x = x end
                if y < min_y then min_y = y end; if y > max_y then max_y = y end
            end
            self:_buildCityImage(idx, min_x, max_x, min_y, max_y)
        end
    end
    self.status_text = string.format("Bounds + districts regenerated for %d cities", #self.city_locations)
end

function WorldSandboxController:_selectCity(city_idx)
    if not self.city_bounds_list or not self.city_bounds_list[city_idx] then return end
    local bounds = self.city_bounds_list[city_idx]
    local w, h   = self.world_w, self.world_h

    local min_x, max_x, min_y, max_y = w+1, 0, h+1, 0
    for ci in pairs(bounds) do
        local x = (ci-1) % w + 1
        local y = math.floor((ci-1) / w) + 1
        if x < min_x then min_x = x end
        if x > max_x then max_x = x end
        if y < min_y then min_y = y end
        if y > max_y then max_y = y end
    end
    if max_x < min_x then return end

    self.selected_city_idx    = city_idx
    self.selected_city_bounds = bounds
    self.view_scope           = "city"
    self.scope_mode           = nil
    self:_buildImage()
    self:_buildCityImage(city_idx, min_x, max_x, min_y, max_y)
    self:_fitToArea(min_x, max_x, min_y, max_y)
    self.status_text = "City view  |  RMB pan  |  Wheel zoom  |  Esc to zoom out"
end

function WorldSandboxController:_selectDowntown()
    local idx = self.selected_city_idx
    if not idx or not self.city_district_maps then return end
    local dmap = self.city_district_maps[idx]
    if not dmap then return end
    local w, h  = self.world_w, self.world_h
    local sub_w = w * 3
    local sub_h = h * 3
    -- Find sub-cell bounds in 0-indexed gscx/gscy space
    local min_scx, max_scx = sub_w,  -1
    local min_scy, max_scy = sub_h,  -1
    for sci, poi_idx in pairs(dmap) do
        if poi_idx == 1 then
            local gscx = (sci - 1) % sub_w
            local gscy = math.floor((sci - 1) / sub_w)
            if gscx < min_scx then min_scx = gscx end
            if gscx > max_scx then max_scx = gscx end
            if gscy < min_scy then min_scy = gscy end
            if gscy > max_scy then max_scy = gscy end
        end
    end
    if max_scx < min_scx then return end
    -- Set view_scope BEFORE building city_image so fog is baked in
    self.view_scope = "downtown"
    self.scope_mode = nil
    -- Rebuild city_image with downtown fog baked in at sub-cell precision
    local bounds = self.city_bounds_list and self.city_bounds_list[idx]
    if bounds then
        local bx1, bx2, by1, by2 = w+1, 0, h+1, 0
        for ci in pairs(bounds) do
            local bx = (ci-1)%w+1; local by = math.floor((ci-1)/w)+1
            if bx<bx1 then bx1=bx end; if bx>bx2 then bx2=bx end
            if by<by1 then by1=by end; if by>by2 then by2=by end
        end
        self:_buildCityImage(idx, bx1, bx2, by1, by2)
    end
    -- Set camera from sub-cell world-pixel extent: gscx (0-indexed) → world px = gscx/3 * ts
    local C2  = self.game.C
    local ts  = C2.MAP.TILE_SIZE
    local sw2, sh2 = love.graphics.getDimensions()
    local vw2 = sw2 - C2.UI.SIDEBAR_WIDTH
    local px_x1 = min_scx / 3 * ts
    local px_x2 = (max_scx + 1) / 3 * ts
    local px_y1 = min_scy / 3 * ts
    local px_y2 = (max_scy + 1) / 3 * ts
    local area_w = px_x2 - px_x1
    local area_h = px_y2 - px_y1
    self.camera.scale = math.min(vw2 / area_w, sh2 / area_h) * 0.88
    self.camera.x = (px_x1 + px_x2) / 2
    self.camera.y = (px_y1 + px_y2) / 2
    self.status_text = "Downtown view  |  RMB pan  |  Wheel zoom  |  Esc to zoom out"
end

-- Builds a high-resolution city image: ~200 city cells across, each CELL_PX×CELL_PX image pixels.
-- Grid lines separate every city cell so the full granularity is visible on screen.
function WorldSandboxController:_buildCityImage(city_idx, min_x, max_x, min_y, max_y)
    local bounds = self.city_bounds_list and self.city_bounds_list[city_idx]
    if not bounds then return end

    -- Districts view: colour looked up from the sub-cell Dijkstra owner map.
    local use_districts  = (self.view_mode == "districts")
    local fog_downtown   = (self.view_scope == "downtown")
    local dist_colors    = use_districts and self.city_district_colors and self.city_district_colors[city_idx]
    local dist_owner_map = (use_districts or fog_downtown) and self.city_district_maps and self.city_district_maps[city_idx]
    local pois_for_city  = (use_districts and self.city_pois_list and self.city_pois_list[city_idx]) or {}
    local sub_w          = self.world_w * 3   -- total sub-cell width (for owner map key)
    local art_city_map    = self.city_arterial_maps and self.city_arterial_maps[city_idx]
    local street_city_map = self.city_street_maps   and self.city_street_maps[city_idx]
    -- street_city_map = {v={[sx*1000+wy]=true}, h={[sy*1000+wx]=true}}

    -- Terrain colormap used for out-of-bounds background in all modes (including districts)
    local terrain_cmap = self.biome_colormap or self.colormap
    local active
    if not use_districts then
        active = (self.view_mode == "biome"       and self.biome_colormap)
              or (self.view_mode == "suitability" and self.suitability_colormap)
              or  self.colormap
        if not active then return end
    elseif not terrain_cmap then
        return
    end

    local w      = self.world_w
    local bbox_w = max_x - min_x + 1
    local bbox_h = max_y - min_y + 1

    -- Sub-cell-centric image. Each sub-cell = K_SC content pixels + 1px gap.
    -- The loop is over sub-cells directly; world cells only appear when
    -- looking up world-level data (bounds, color, height).
    -- Streets and arterial boundaries live on the gap pixels between sub-cells.
    local K_SC   = 8                      -- content pixels per sub-cell
    local STRIDE = K_SC + 1              -- 9px total per sub-cell (1 gap + 8 content)
    local sc_min_x = (min_x - 1) * 3    -- global gscx (0-indexed) of first image column
    local sc_min_y = (min_y - 1) * 3
    local sc_bbox_w = bbox_w * 3
    local sc_bbox_h = bbox_h * 3
    local img_w = sc_bbox_w * STRIDE
    local img_h = sc_bbox_h * STRIDE

    local imgdata = love.image.newImageData(img_w, img_h)

    for py = 0, img_h - 1 do
        local scy  = math.floor(py / STRIDE)
        local iy   = py % STRIDE                   -- 0=gap, 1..K_SC=content
        local gscy = sc_min_y + scy
        local wy   = math.floor(gscy / 3) + 1     -- world cell y (1-indexed)
        for px = 0, img_w - 1 do
            local scx  = math.floor(px / STRIDE)
            local ix   = px % STRIDE               -- 0=gap, 1..K_SC=content
            local gscx = sc_min_x + scx
            local wx   = math.floor(gscx / 3) + 1 -- world cell x (1-indexed)
            local ci   = (wy - 1) * w + wx

            local is_gap = (ix == 0) or (iy == 0)

            -- Base colour from this sub-cell
            local c
            if use_districts then
                local best_poi = dist_owner_map and dist_owner_map[gscy * sub_w + gscx + 1]
                if not best_poi and #pois_for_city > 0 then
                    local best_wd = math.huge
                    for poi_idx, poi in ipairs(pois_for_city) do
                        local px2 = (poi.x - 1) * 3 + 1
                        local py2 = (poi.y - 1) * 3 + 1
                        local dx  = gscx - px2
                        local dy  = gscy - py2
                        local wd  = dx*dx + dy*dy
                        if wd < best_wd then best_wd = wd; best_poi = poi_idx end
                    end
                end
                c = (best_poi and dist_colors and dist_colors[best_poi]) or {0.25, 0.25, 0.28}
            else
                local bc      = active[wy] and active[wy][wx] or {0.1, 0.1, 0.1}
                local world_e = self.heightmap[wy][wx]
                local sub_e   = subcell_elev_at(gscx, gscy, self.heightmap)
                local adjust  = (sub_e - world_e) * 3.0
                c = {
                    math.max(0, math.min(1, bc[1] + adjust)),
                    math.max(0, math.min(1, bc[2] + adjust)),
                    math.max(0, math.min(1, bc[3] + adjust)),
                }
            end

            -- Arterial overlay
            if art_city_map and art_city_map[gscy * sub_w + gscx + 1] then
                c = {0.20, 0.19, 0.17}
            end

            if bounds[ci] then
                -- Streets: gap pixel between two sub-cells of different zone types.
                local is_street = false
                local zg      = self.city_zone_grids   and self.city_zone_grids[city_idx]
                local zg_orig = self.city_zone_offsets and self.city_zone_offsets[city_idx]
                local zg_ox   = zg_orig and zg_orig.x or sc_min_x
                local zg_oy   = zg_orig and zg_orig.y or sc_min_y
                if zg and is_gap then
                    local lscx = gscx - zg_ox + 1
                    local lscy = gscy - zg_oy + 1
                    if ix == 0 and lscx > 1 then
                        local z1 = zg[lscy] and zg[lscy][lscx-1]
                        local z2 = zg[lscy] and zg[lscy][lscx]
                        if z1 and z1 ~= "none" and z2 and z2 ~= "none" and z1 ~= z2 then
                            is_street = true
                        end
                    end
                    if not is_street and iy == 0 and lscy > 1 then
                        local z1 = zg[lscy-1] and zg[lscy-1][lscx]
                        local z2 = zg[lscy] and zg[lscy][lscx]
                        if z1 and z1 ~= "none" and z2 and z2 ~= "none" and z1 ~= z2 then
                            is_street = true
                        end
                    end
                elseif street_city_map and is_gap then
                    -- Fallback for cities without zone_grid: world-cell boundary streets
                    local sv, sh = street_city_map.v, street_city_map.h
                    if ix == 0 and gscx > sc_min_x and gscx % 3 == 0 then
                        if sv and sv[(math.floor(gscx / 3)) * 1000 + wy] then is_street = true end
                    end
                    if not is_street and iy == 0 and gscy > sc_min_y and gscy % 3 == 0 then
                        if sh and sh[(math.floor(gscy / 3)) * 1000 + wx] then is_street = true end
                    end
                end

                -- Arterial boundary: bright gap wherever arterial meets non-arterial.
                -- Works at ANY sub-cell boundary, not just world-cell boundaries.
                if not is_street and art_city_map and is_gap then
                    if ix == 0 and gscx > sc_min_x then
                        local curr = art_city_map[gscy * sub_w + gscx + 1]
                        local left = art_city_map[gscy * sub_w + (gscx - 1) + 1]
                        if (curr and not left) or (left and not curr) then is_street = true end
                    end
                    if not is_street and iy == 0 and gscy > sc_min_y then
                        local curr  = art_city_map[gscy * sub_w + gscx + 1]
                        local above = art_city_map[(gscy - 1) * sub_w + gscx + 1]
                        if (curr and not above) or (above and not curr) then is_street = true end
                    end
                end

                local r, g, b
                if is_street then
                    r, g, b = 0.88, 0.86, 0.80
                else
                    r, g, b = c[1], c[2], c[3]
                end

                if fog_downtown and dist_owner_map and not is_street then
                    local sci2 = gscy * sub_w + gscx + 1
                    if dist_owner_map[sci2] ~= 1 then
                        r = r*0.18+0.01; g = g*0.18+0.02; b = b*0.18+0.06
                    end
                end
                imgdata:setPixel(px, py, r, g, b, 1.0)
            else
                local tc = (terrain_cmap and terrain_cmap[wy] and terrain_cmap[wy][wx]) or {0.08, 0.08, 0.10}
                imgdata:setPixel(px, py, tc[1]*0.18+0.01, tc[2]*0.18+0.02, tc[3]*0.18+0.06, 1.0)
            end
        end
    end

    local img = love.graphics.newImage(imgdata)
    img:setFilter("nearest", "nearest")
    self.city_image     = img
    self.city_img_min_x = min_x
    self.city_img_min_y = min_y
    -- pixels per world cell = 3 sub-cells × STRIDE px/sub-cell = 12
    -- GameView uses ts/K as draw scale, so 1 image px = ts/12 world px
    self.city_img_K     = 3 * STRIDE
end

function WorldSandboxController:_centerCamera()
    local C   = self.game.C
    local ts  = C.MAP.TILE_SIZE
    local sw, sh = love.graphics.getDimensions()
    local vw  = sw - C.UI.SIDEBAR_WIDTH
    local mpw = self.world_w * ts
    local mph = self.world_h * ts
    self.camera.scale = math.min(vw / mpw, sh / mph) * 0.92
    self.camera.x = mpw / 2
    self.camera.y = mph / 2
end

-- ── Input ─────────────────────────────────────────────────────────────────────

function WorldSandboxController:handle_keypressed(key)
    if key == "escape" then
        if self.scope_mode then
            self.scope_mode  = nil
            self.status_text = "Cancelled"
        elseif self.view_scope == "downtown" then
            if self.selected_city_idx then
                self:_selectCity(self.selected_city_idx)
            else
                self:set_scope_world()
            end
        elseif self.view_scope == "city" then
            if self.selected_region_id then
                self:_selectRegion(self.selected_region_id)
            else
                self:set_scope_world()
            end
        elseif self.view_scope == "region" then
            if self.selected_continent_id then
                self:_selectContinent(self.selected_continent_id)
            else
                self:set_scope_world()
            end
        elseif self.view_scope ~= "world" then
            self:set_scope_world()
        else
            self:close()
        end
    end
end

function WorldSandboxController:handle_mouse_wheel(x, y)
    local C         = self.game.C
    local sidebar_w = C.UI.SIDEBAR_WIDTH
    local mx, my    = love.mouse.getPosition()

    if mx < sidebar_w then
        -- Sidebar scroll
        if self.sidebar_manager then
            self.sidebar_manager:handle_scroll(mx, my, y)
        end
    else
        -- Viewport zoom
        local factor = 1.15 ^ y
        self.camera.scale = math.max(0.05, math.min(80, self.camera.scale * factor))
    end
end

function WorldSandboxController:handle_mouse_down(x, y, button)
    local C         = self.game.C
    local sidebar_w = C.UI.SIDEBAR_WIDTH

    if x < sidebar_w then
        if self.sidebar_manager then
            self.sidebar_manager:handle_mouse_down(x, y, button)
        end
        return
    end

    -- Scope picking: LMB selects the continent/region under the cursor
    if button == 1 and self.scope_mode and self.colormap then
        local ts         = C.MAP.TILE_SIZE
        local sw, sh     = love.graphics.getDimensions()
        local vw         = sw - sidebar_w
        local wpx        = self.camera.x + (x - sidebar_w - vw * 0.5) / self.camera.scale
        local wpy        = self.camera.y + (y - sh * 0.5) / self.camera.scale
        local cx         = math.floor(wpx / ts) + 1
        local cy         = math.floor(wpy / ts) + 1
        if cx >= 1 and cx <= self.world_w and cy >= 1 and cy <= self.world_h then
            local i = (cy-1)*self.world_w + cx
            if self.scope_mode == "picking_continent" then
                local cid = self.continent_map and self.continent_map[i] or 0
                if cid > 0 then self:_selectContinent(cid) end
            elseif self.scope_mode == "picking_region" then
                local rid = self.region_map and self.region_map[i] or 0
                if rid > 0 then self:_selectRegion(rid) end
            elseif self.scope_mode == "picking_city" then
                for idx, bounds in ipairs(self.city_bounds_list or {}) do
                    if bounds[i] then self:_selectCity(idx); break end
                end
            end
        end
        return
    end

    if button == 2 then
        self.camera_dragging = true
        self.camera_drag_sx  = x
        self.camera_drag_sy  = y
    end
end

function WorldSandboxController:handle_mouse_up(x, y, button)
    if button == 2 then
        self.camera_dragging = false
    end
    if self.sidebar_manager then
        self.sidebar_manager:handle_mouse_up(x, y, button)
    end
end

function WorldSandboxController:handle_mouse_moved(x, y, dx, dy)
    if self.camera_dragging then
        self.camera.x = self.camera.x - dx / self.camera.scale
        self.camera.y = self.camera.y - dy / self.camera.scale
    end
    -- Show hover name during scope picking
    if self.scope_mode and self.colormap then
        local C      = self.game.C
        local sw, sh = love.graphics.getDimensions()
        local vw     = sw - C.UI.SIDEBAR_WIDTH
        local ts     = C.MAP.TILE_SIZE
        local wpx    = self.camera.x + (x - C.UI.SIDEBAR_WIDTH - vw * 0.5) / self.camera.scale
        local wpy    = self.camera.y + (y - sh * 0.5) / self.camera.scale
        local cx     = math.floor(wpx / ts) + 1
        local cy     = math.floor(wpy / ts) + 1
        if cx >= 1 and cx <= self.world_w and cy >= 1 and cy <= self.world_h then
            local i = (cy-1)*self.world_w + cx
            if self.scope_mode == "picking_continent" then
                local cid = self.continent_map and self.continent_map[i] or 0
                if cid > 0 then
                    self.status_text = string.format("Continent %d  |  Click to select  |  Esc to cancel", cid)
                else
                    self.status_text = "Click a continent to zoom in  |  Esc to cancel"
                end
            elseif self.scope_mode == "picking_region" then
                local rid = self.region_map and self.region_map[i] or 0
                if rid > 0 then
                    self.status_text = string.format("Region %d  |  Click to select  |  Esc to cancel", rid)
                else
                    self.status_text = "Click a region to zoom in  |  Esc to cancel"
                end
            elseif self.scope_mode == "picking_city" then
                local found = false
                for idx, bounds in ipairs(self.city_bounds_list or {}) do
                    if bounds[i] then
                        self.status_text = string.format("City %d  |  Click to zoom in  |  Esc to cancel", idx)
                        found = true; break
                    end
                end
                if not found then
                    self.status_text = "Click a city area to zoom in  |  Esc to cancel"
                end
            end
        end
    end
    if self.sidebar_manager then
        self.sidebar_manager:handle_mouse_moved(x, y, dx, dy)
    end
end

function WorldSandboxController:handle_textinput(text)
    -- not needed currently
end

return WorldSandboxController
