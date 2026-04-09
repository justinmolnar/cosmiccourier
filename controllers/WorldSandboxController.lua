-- controllers/WorldSandboxController.lua

local ffi = require("ffi")
local _ffi_cdef_done = false  -- guard: ffi.cdef must only run once per Lua state
local Biomes = require("data.biomes")

local WorldGenUtils        = require("utils.WorldGenUtils")
local CityPlacementService = require("services.CityPlacementService")
local HighwayService       = require("services.HighwayService")
local CityBoundsService    = require("services.CityBoundsService")
local CityDistrictService  = require("services.CityDistrictService")
local CityStreetService    = require("services.CityStreetService")
local CityArterialService  = require("services.CityArterialService")
local WorldImageService    = require("services.WorldImageService")
local MapBuilderService    = require("services.MapBuilderService")

-- Bilinear interpolation of a 2-D array map[y][x] at fractional position (fy, fx).
local function bilinear2d(map, fy, fx, W, H)
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

-- Integer tile type encoding for the FFI unified grid.
-- Must stay in sync with C.TILE in constants.lua and _TILE_NAMES in PathfindingService.
local TILE_INT = {
    grass=0, road=1, downtown_road=2, arterial=3, highway=4,
    water=5, mountain=6, river=7, plot=8, downtown_plot=9,
}

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
    inst.city_image            = nil   -- high-res city grid image (city scope)
    inst.city_img_min_x        = 0
    inst.city_img_min_y        = 0
    inst.city_img_K            = 1
    inst.moisture_map          = nil
    inst.painted_set           = nil
    inst.lake_set              = nil
    inst.river_paths           = nil
    inst.world_image           = nil
    inst.world_image_scale     = 1
    inst.world_w        = 0
    inst.world_h        = 0
    inst.view_mode      = "height"   -- "height" | "biome" | "suitability" | "continents" | "regions" | "districts"
    inst.view_scope     = "world"    -- used internally by _buildGameImages to bake city/downtown images
    inst.status_text    = ""

    inst.sidebar_manager = nil

    inst.params = {
        -- World grid dimensions.
        world_w = 600, world_h = 300,
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
        city_count        = 32,   -- slider 1-50: how many cities to place
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
        -- Visual Quality (F8 opt-in)
        vq_mode            = "tile",  -- "tile" | "hires"
        vq_hires_scale     = 3,       -- 1-8: resolution multiplier for hi-res mode
        vq_color_variation = 0.0,     -- 0-0.3: intra-biome noise variation
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

    -- Injected math functions: same pointers as love.math so RNG stream is identical.
    -- Passed into all portable services so they have zero love.* imports.
    inst.math_fns = { noise = love.math.noise, random = love.math.random }

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

    new_map.road_v_rxs   = road_v_rxs
    new_map.road_h_rys   = road_h_rys
    new_map.road_nodes   = road_nodes
    -- Preserve original street columns/rows for unified grid road-fill in sendToGame.
    -- road_v_rxs / road_h_rys are later overwritten with zone-boundary data (empty tables).
    new_map.street_v_rxs = road_v_rxs
    new_map.street_h_rys = road_h_rys

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

            -- Building plots: plot/downtown_plot cells reachable via an adjacent zone_seg
            -- street edge, arterial, or highway. Computed here so validation matches
            -- the actual pathfinding road system (zone_seg_v/h already built above).
            local building_plots = {}
            local seen_b = {}
            for gy = 1, sub_ch do
                for gx = 1, sub_cw do
                    local t = grid[gy][gx].type
                    if t == "plot" or t == "downtown_plot" then
                        local reachable =
                            (zone_seg_v[gy] and (zone_seg_v[gy][gx-1] or zone_seg_v[gy][gx]))
                         or (zone_seg_h[gy-1] and zone_seg_h[gy-1][gx])
                         or (zone_seg_h[gy]   and zone_seg_h[gy][gx])
                         or (grid[gy][gx-1] and (grid[gy][gx-1].type == "arterial" or grid[gy][gx-1].type == "highway"))
                         or (grid[gy][gx+1] and (grid[gy][gx+1].type == "arterial" or grid[gy][gx+1].type == "highway"))
                         or (grid[gy-1] and grid[gy-1][gx] and (grid[gy-1][gx].type == "arterial" or grid[gy-1][gx].type == "highway"))
                         or (grid[gy+1] and grid[gy+1][gx] and (grid[gy+1][gx].type == "arterial" or grid[gy+1][gx].type == "highway"))
                        if reachable then
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

-- ── City build helpers ────────────────────────────────────────────────────────
-- These two functions are the single source of truth for how ANY city is built.
-- Both the starter city and every extra city go through the same pipeline:
--   _buildCityGrid  → sub-cell tile grid + ctx
--   _buildCityMap   → calls _buildCityGrid, _buildZoneGrid, _buildRoadNetwork
-- Image building is done by the caller after (starter via _buildGameImages,
-- extras via _buildCityImage directly).

function WorldSandboxController:_buildCityGrid(city_idx, mn_x, mx_x, mn_y, mx_y, art_sci, all_claimed)
    local w  = self.world_w
    local h  = self.world_h
    local sw = w * 3
    local p  = self.params

    local sub_cw   = (mx_x - mn_x + 1) * 3
    local sub_ch   = (mx_y - mn_y + 1) * 3
    local gscx_off = (mn_x - 1) * 3
    local gscy_off = (mn_y - 1) * 3

    -- dt_sci: district-1 (downtown) sub-cells for this specific city
    local dt_sci  = {}
    local dmap_dt = self.city_district_maps and self.city_district_maps[city_idx]
    if dmap_dt then
        for sci, poi_idx_v in pairs(dmap_dt) do
            if poi_idx_v == 1 then dt_sci[sci] = true end
        end
    end
    if not next(dt_sci) then
        local poi1   = self.city_pois_list and self.city_pois_list[city_idx] and self.city_pois_list[city_idx][1]
        local bounds = self.city_bounds_list and self.city_bounds_list[city_idx]
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

    -- Build sub-cell tile grid
    local grid = {}
    local p2 = self.params
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
                tile = (self.highway_map and self.highway_map[ci]) and "highway" or "arterial"
            elseif all_claimed[ci] then
                tile = dt_sci[sci] and "downtown_plot" or "plot"
            else
                local elev = (self.heightmap and self.heightmap[wcy] and self.heightmap[wcy][wcx]) or 0.5
                if     elev <= (p2.ocean_max    or 0.42) then tile = "water"
                elseif elev >= (p2.highland_max or 0.80) then tile = "mountain"
                else                                          tile = "grass" end
            end
            grid[lscy + 1][lscx + 1] = {type = tile}
        end
    end

    -- River sub-cell injection
    do
        local bdata     = self.biome_data or {}
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
        sw = sw, w = w, start_idx = city_idx,
        grid = grid, city_mn_x = mn_x, city_mn_y = mn_y,
    }
    return grid, ctx
end

function WorldSandboxController:_buildCityMap(city_idx, mn_x, mx_x, mn_y, mx_y, art_sci, all_claimed)
    local pois    = self.city_pois_list    and self.city_pois_list[city_idx]
    local dmap    = self.city_district_maps and self.city_district_maps[city_idx]
    local bounds  = self.city_bounds_list  and self.city_bounds_list[city_idx]
    local smap    = self.city_street_maps  and self.city_street_maps[city_idx]
    local pre_dt  = self.city_district_types and self.city_district_types[city_idx]

    local map, zone_grid, zone_offsets, district_types = MapBuilderService.buildCityMap(
        city_idx, mn_x, mx_x, mn_y, mx_y, art_sci, all_claimed,
        dmap, pois, bounds, self.highway_map, self.heightmap, self.biome_data, smap,
        pre_dt, self.params, self.math_fns, self.game.C, self.world_w, self.world_h
    )

    -- Cache zone grid and district types so _buildCityImage can read them
    if not self.city_district_types then self.city_district_types = {} end
    if not self.city_zone_grids     then self.city_zone_grids     = {} end
    if not self.city_zone_offsets   then self.city_zone_offsets   = {} end
    self.city_district_types[city_idx] = district_types
    self.city_zone_grids[city_idx]     = zone_grid
    self.city_zone_offsets[city_idx]   = zone_offsets

    -- district_colors are computed by CityDistrictService, not MapBuilderService
    map.district_colors = self.city_district_colors and self.city_district_colors[city_idx]

    return map
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

    -- all_claimed[ci] = city_idx for every world-cell owned by any city
    local all_claimed = {}
    for idx = 1, #self.city_locations do
        local bnds = self.city_bounds_list and self.city_bounds_list[idx]
        if bnds then
            for ci in pairs(bnds) do all_claimed[ci] = idx end
        end
    end
    game.hw_all_claimed = all_claimed

    -- Build starter city: grid + zone + road network (identical pipeline to extra cities)
    local new_map = self:_buildCityMap(start_idx, city_mn_x, city_mx_x, city_mn_y, city_mx_y, art_sci, all_claimed)
    -- Build HUD images (world/region/continent + starter city image)
    self:_buildGameImages(game, start_idx, city_mn_x, city_mx_x, city_mn_y, city_mx_y, w, h)
    -- Attach city image produced by _buildGameImages
    new_map.city_image     = game.world_gen_city_image
    new_map.city_img_min_x = game.world_gen_city_img_min_x
    new_map.city_img_min_y = game.world_gen_city_img_min_y
    new_map.city_img_K     = game.world_gen_city_img_K

    -- Stamp onto game
    game.maps.city      = new_map
    game.active_map_key = "city"

    -- Build extra city maps using the same pipeline
    game.maps.extra_cities = {}
    for ec_idx = 1, #self.city_locations do
        if ec_idx ~= start_idx then
            local ec_bounds = self.city_bounds_list[ec_idx]
            if ec_bounds then
                local mn_x, mx_x = w + 1, 0
                local mn_y, mx_y = h + 1, 0
                for ci in pairs(ec_bounds) do
                    local cx = (ci-1)%w+1; local cy = math.floor((ci-1)/w)+1
                    if cx < mn_x then mn_x = cx end; if cx > mx_x then mx_x = cx end
                    if cy < mn_y then mn_y = cy end; if cy > mx_y then mx_y = cy end
                end
                if mn_x <= mx_x then
                    local ec_map = self:_buildCityMap(ec_idx, mn_x, mx_x, mn_y, mx_y, art_sci, all_claimed)
                    -- Build city image
                    local sv_mode  = self.view_mode
                    local sv_scope = self.view_scope
                    self.view_mode = (self.city_district_maps and self.city_district_maps[ec_idx])
                                      and "districts"
                                      or  (self.biome_colormap and "biome" or "height")
                    local cox1 = math.max(1, mn_x-2); local cox2 = math.min(w, mx_x+2)
                    local coy1 = math.max(1, mn_y-2); local coy2 = math.min(h, mx_y+2)
                    self:_buildCityImage(ec_idx, cox1, cox2, coy1, coy2)
                    ec_map.city_image     = self.city_image
                    ec_map.city_img_min_x = self.city_img_min_x
                    ec_map.city_img_min_y = self.city_img_min_y
                    ec_map.city_img_K     = self.city_img_K
                    self.view_mode  = sv_mode
                    self.view_scope = sv_scope
                    game.maps.extra_cities[#game.maps.extra_cities + 1] = ec_map
                end
            end
        end
    end

    -- Unified list of all cities for rendering (starter first, then extras)
    game.maps.all_cities = {game.maps.city}
    for _, ec in ipairs(game.maps.extra_cities) do
        game.maps.all_cities[#game.maps.all_cities + 1] = ec
    end
    -- Named keys for city maps ("city_1", "city_2", …) used by rendering
    for i, m in ipairs(game.maps.all_cities) do game.maps["city_" .. i] = m end

    -- Clear stale path cache before building new unified grid and pre-warming trunk paths.
    require("services.PathCacheService").invalidate()

    -- Build the unified navigation grid: one sub-cell grid spanning the entire world.
    -- Each world cell (wx,wy) maps to 3×3 sub-cells at unified coords
    -- ((wx-1)*3+1 … wx*3, same for y).
    -- Stored as a flat LuaJIT FFI C array (CosmicTile[uw*uh]) instead of a 2D
    -- Lua table, keeping it outside the GC heap. Index: (uy-1)*uw + (ux-1).
    do
        if not _ffi_cdef_done then
            ffi.cdef[[ typedef struct { uint8_t type; uint8_t _pad[3]; } CosmicTile; ]]
            _ffi_cdef_done = true
        end

        local hw   = self.highway_map or {}
        local ww   = self.world_w
        local wh   = self.world_h
        local uw   = ww * 3
        local uh   = wh * 3

        -- ffi.new zeroes the array, so all cells start as type=0 (GRASS).
        local ffi_grid = ffi.new("CosmicTile[?]", uw * uh)

        -- Copy city sub-cell grids into the unified FFI grid.
        for _, cmap in ipairs(game.maps.all_cities) do
            local ox = (cmap.world_mn_x - 1) * 3
            local oy = (cmap.world_mn_y - 1) * 3
            for cy = 1, #cmap.grid do
                local row = cmap.grid[cy]
                local base = (oy + cy - 1) * uw + ox
                for cx = 1, #row do
                    ffi_grid[base + cx - 1].type = TILE_INT[row[cx].type] or 0
                end
            end
        end

        -- Stamp highway AFTER city copy.
        -- For world cells outside city territory: always stamp as highway.
        -- For world cells inside city territory: only stamp boundary cells
        -- (those adjacent to a non-city cell) so inner-city pathfinding keeps
        -- using zone_seg streets rather than snapping to the highway band.
        local dirs4 = {{1,0},{-1,0},{0,1},{0,-1}}
        for ci, _ in pairs(hw) do
            local wx = (ci - 1) % ww + 1
            local wy = math.floor((ci - 1) / ww) + 1
            local is_city = all_claimed[ci]
            local is_boundary = false
            if is_city then
                for _, d in ipairs(dirs4) do
                    local nx, ny = wx + d[1], wy + d[2]
                    if nx >= 1 and nx <= ww and ny >= 1 and ny <= wh then
                        if not all_claimed[(ny - 1) * ww + nx] then
                            is_boundary = true; break
                        end
                    else
                        is_boundary = true; break
                    end
                end
            end
            if not is_city or is_boundary then
                for dy = 0, 2 do
                    local base = ((wy - 1) * 3 + dy) * uw + (wx - 1) * 3
                    for dx = 0, 2 do
                        ffi_grid[base + dx].type = 4  -- HIGHWAY
                    end
                end
            end
        end

        -- Unified zone_seg: copy each city's street edges into unified coordinates.
        -- zone_seg_v[gy][rx] = N-S street between cells (rx,gy) and (rx+1,gy) [1-indexed].
        -- zone_seg_h[ry][gx] = E-W street between cells (gx,ry) and (gx,ry+1) [1-indexed].
        -- Offset by city origin (ox,oy). No tiles stamped — streets remain as edges.
        -- The pathfinder sandbox branch reads these to allow movement across street edges.
        local uzsv, uzsh = {}, {}
        for _, cmap in ipairs(game.maps.all_cities) do
            local ox = (cmap.world_mn_x - 1) * 3
            local oy = (cmap.world_mn_y - 1) * 3
            if cmap.zone_seg_v then
                for gy, row in pairs(cmap.zone_seg_v) do
                    local uy = oy + gy
                    if uy >= 1 and uy <= uh then
                        for rx in pairs(row) do
                            local ux = ox + rx
                            if ux >= 1 and ux <= uw then
                                if not uzsv[uy] then uzsv[uy] = {} end
                                uzsv[uy][ux] = true
                            end
                        end
                    end
                end
            end
            if cmap.zone_seg_h then
                for ry, row in pairs(cmap.zone_seg_h) do
                    local uy = oy + ry
                    if uy >= 1 and uy <= uh then
                        for gx in pairs(row) do
                            local ux = ox + gx
                            if ux >= 1 and ux <= uw then
                                if not uzsh[uy] then uzsh[uy] = {} end
                                uzsh[uy][ux] = true
                            end
                        end
                    end
                end
            end
        end

        local uts = C.MAP.TILE_SIZE / 3
        -- grid = nil: tile data lives in ffi_grid. Pathfinder and PathfindingService
        -- use _w/_h for dimensions and ffi_grid for tile type reads.
        local umap = { grid = nil, ffi_grid = ffi_grid, tile_pixel_size = uts, _w = uw, _h = uh }
        umap.zone_seg_v = uzsv
        umap.zone_seg_h = uzsh
        function umap:isRoad(t)
            -- Accepts integer (FFI grid) or string (city map fallback).
            if type(t) == "number" then return t >= 1 and t <= 4 end
            return t == "road" or t == "downtown_road" or t == "arterial" or t == "highway"
        end
        function umap:getPixelCoords(x, y)
            return (x - 0.5) * self.tile_pixel_size, (y - 0.5) * self.tile_pixel_size
        end
        function umap:findNearestRoadTile(plot)
            local gw, gh = self._w, self._h
            local fg = self.ffi_grid
            local sx = math.max(1, math.min(gw, plot.x))
            local sy = math.max(1, math.min(gh, plot.y))
            local visited = {[sy * (gw + 1) + sx] = true}
            local q, qi = {{sx, sy}}, 1
            while qi <= #q and qi <= 4000 do
                local cx, cy = q[qi][1], q[qi][2]; qi = qi + 1
                if self:isRoad(fg[(cy-1)*gw + (cx-1)].type) then return {x=cx, y=cy} end
                for _, d in ipairs({{0,-1},{0,1},{-1,0},{1,0}}) do
                    local nx, ny = cx+d[1], cy+d[2]
                    local k = ny*(gw+1)+nx
                    if nx>=1 and nx<=gw and ny>=1 and ny<=gh and not visited[k] then
                        visited[k]=true; q[#q+1]={nx,ny}
                    end
                end
            end
            return nil
        end
        game.maps.unified = umap
        umap.world_w = ww

        -- ── Attachment nodes ──────────────────────────────────────────────────
        -- An attachment node is the centre sub-cell of a highway world cell that
        -- directly borders a city. These are the fixed endpoints for trunk caching.
        -- game.hw_attachment_nodes[city_idx] = {{ux,uy,key}, ...}
        local attachment_nodes = {}

        for ci, _ in pairs(hw) do
            local wx2 = (ci - 1) % ww + 1
            local wy2 = math.floor((ci - 1) / ww) + 1
            local this_city = all_claimed[ci]
            for _, d in ipairs(dirs4) do
                local nx2, ny2 = wx2 + d[1], wy2 + d[2]
                if nx2 >= 1 and nx2 <= ww and ny2 >= 1 and ny2 <= wh then
                    local neighbor_city = all_claimed[(ny2 - 1) * ww + nx2]
                    local relevant_city = this_city or neighbor_city
                    if relevant_city and this_city ~= neighbor_city then
                        -- Always use this highway cell (wx2,wy2) as the attachment node.
                        local ux2 = (wx2 - 1) * 3 + 2
                        local uy2 = (wy2 - 1) * 3 + 2
                        if not attachment_nodes[relevant_city] then attachment_nodes[relevant_city] = {} end
                        local key2 = uy2 * 10000 + ux2
                        local already = false
                        for _, n in ipairs(attachment_nodes[relevant_city]) do
                            if n.key == key2 then already = true; break end
                        end
                        if not already then
                            attachment_nodes[relevant_city][#attachment_nodes[relevant_city]+1] = {ux=ux2, uy=uy2, key=key2}
                        end
                    end
                end
            end
        end

        game.hw_attachment_nodes = attachment_nodes

        -- ── City edges via highway connected-component analysis ───────────────
        -- Cities are never directly adjacent — they're separated by unclaimed
        -- highway cells. BFS the world-level highway graph to find components,
        -- then two cities share an edge iff they have attachment nodes on the
        -- same component. Trunk paths are computed lazily on first vehicle use.
        local hw_comp = {}   -- [world_ci] = component_id
        local n_comp  = 0
        for hci, _ in pairs(hw) do
            if not hw_comp[hci] then
                n_comp = n_comp + 1
                local bq, bqi = {hci}, 1
                hw_comp[hci] = n_comp
                while bqi <= #bq do
                    local cc = bq[bqi]; bqi = bqi + 1
                    local cwx2 = (cc - 1) % ww + 1
                    local cwy2 = math.floor((cc - 1) / ww) + 1
                    for _, d2 in ipairs(dirs4) do
                        local nwx2, nwy2 = cwx2 + d2[1], cwy2 + d2[2]
                        if nwx2 >= 1 and nwx2 <= ww and nwy2 >= 1 and nwy2 <= wh then
                            local nci2 = (nwy2 - 1) * ww + nwx2
                            if hw[nci2] and not hw_comp[nci2] then
                                hw_comp[nci2] = n_comp
                                bq[#bq + 1] = nci2
                            end
                        end
                    end
                end
            end
        end

        -- Map each city to its component(s) via its attachment nodes.
        local city_comp = {}  -- [city_idx][comp_id] = attachment node
        for city_idx, nodes2 in pairs(attachment_nodes) do
            city_comp[city_idx] = {}
            for _, att in ipairs(nodes2) do
                local awx = math.ceil(att.ux / 3)
                local awy = math.ceil(att.uy / 3)
                local comp2 = hw_comp[(awy - 1) * ww + awx]
                if comp2 and not city_comp[city_idx][comp2] then
                    city_comp[city_idx][comp2] = att
                end
            end
        end

        -- Build city_edges: cities sharing a highway component are connected.
        local city_edges = {}
        for city_a, comps_a in pairs(city_comp) do
            for city_b, comps_b in pairs(city_comp) do
                if city_a < city_b then
                    for comp3, att_a in pairs(comps_a) do
                        local att_b = comps_b[comp3]
                        if att_b then
                            if not city_edges[city_a] then city_edges[city_a] = {} end
                            if not city_edges[city_a][city_b] then
                                city_edges[city_a][city_b] = {from={ux=att_a.ux,uy=att_a.uy}, to={ux=att_b.ux,uy=att_b.uy}}
                            end
                            if not city_edges[city_b] then city_edges[city_b] = {} end
                            if not city_edges[city_b][city_a] then
                                city_edges[city_b][city_a] = {from={ux=att_b.ux,uy=att_b.uy}, to={ux=att_a.ux,uy=att_a.uy}}
                            end
                        end
                    end
                end
            end
        end

        game.hw_city_edges = city_edges

        -- ── City sub-cell bounding boxes ──────────────────────────────────────
        -- Used by PathfindingService to limit Tier 1 / Tier 4 A* to the city's
        -- sub-cell area (+ margin), preventing them from exploring the full 1800×900
        -- unified grid and causing per-frame stutter.
        local city_sc_bounds = {}
        local MARGIN = 6   -- extra sub-cells beyond city border (covers highway attachment nodes)
        local cbl = self.city_bounds_list or {}
        for city_idx, bounds_set in pairs(cbl) do
            local mn_wx, mx_wx = ww + 1, 0
            local mn_wy, mx_wy = wh + 1, 0
            for ci in pairs(bounds_set) do
                local cwx2 = (ci - 1) % ww + 1
                local cwy2 = math.floor((ci - 1) / ww) + 1
                if cwx2 < mn_wx then mn_wx = cwx2 end
                if cwx2 > mx_wx then mx_wx = cwx2 end
                if cwy2 < mn_wy then mn_wy = cwy2 end
                if cwy2 > mx_wy then mx_wy = cwy2 end
            end
            if mn_wx <= mx_wx then
                city_sc_bounds[city_idx] = {
                    x1 = math.max(1,  (mn_wx - 1) * 3 + 1 - MARGIN),
                    y1 = math.max(1,  (mn_wy - 1) * 3 + 1 - MARGIN),
                    x2 = math.min(uw, mx_wx * 3 + MARGIN),
                    y2 = math.min(uh, mx_wy * 3 + MARGIN),
                }
            end
        end
        game.hw_city_sc_bounds = city_sc_bounds
    end

    -- Reset vehicles using unified sub-cell coordinates
    local States = require("models.vehicles.vehicle_states")
    local city_depot_local = new_map:getRandomDowntownBuildingPlot() or new_map:getRandomBuildingPlot()
    local new_depot = city_depot_local and {
        x = (new_map.world_mn_x - 1) * 3 + city_depot_local.x,
        y = (new_map.world_mn_y - 1) * 3 + city_depot_local.y,
    }
    -- Snap depot to the nearest city road tile (type 1-3, not highway=4) so
    -- vehicles start on the street network, not on the world highway band.
    if new_depot then
        local _umap = game.maps.unified
        local _fg, _gw, _gh = _umap.ffi_grid, _umap._w, _umap._h
        local _sx = math.max(1, math.min(_gw, new_depot.x))
        local _sy = math.max(1, math.min(_gh, new_depot.y))
        local _visited = {[_sy*(_gw+1)+_sx] = true}
        local _q, _qi = {{_sx, _sy}}, 1
        local _snapped = nil
        while _qi <= #_q and _qi <= 4000 do
            local _cx, _cy = _q[_qi][1], _q[_qi][2]; _qi = _qi + 1
            local _ti = _fg[(_cy-1)*_gw + (_cx-1)].type
            if _ti == 1 or _ti == 2 then _snapped = {x=_cx, y=_cy}; break end
            for _, _d in ipairs({{0,-1},{0,1},{-1,0},{1,0}}) do
                local _nx, _ny = _cx+_d[1], _cy+_d[2]
                local _k = _ny*(_gw+1)+_nx
                if _nx>=1 and _nx<=_gw and _ny>=1 and _ny<=_gh and not _visited[_k] then
                    _visited[_k]=true; _q[#_q+1]={_nx, _ny}
                end
            end
        end
        if _snapped then new_depot = _snapped end
    end
    
    if new_depot then
        local Depot = require("models.Depot")
        game.entities.depots = {}
        local depot_obj = Depot:new("sandbox_1", new_depot, game)
        table.insert(game.entities.depots, depot_obj)
    end
    
    local uts = game.maps.unified.tile_pixel_size
    require("services.PathScheduler").clear()
    for _, v in ipairs(game.entities.vehicles) do
        v.cargo = {}; v.trip_queue = {}; v.path = {}; v.path_i = 1; v.smooth_path = nil; v.smooth_path_i = nil
        v._path_pending = false
        v.operational_map_key = "unified"
        if new_depot and game.entities.depots[1] then
            v.depot       = game.entities.depots[1]
            v.depot_plot  = new_depot
            v.grid_anchor = {x = new_depot.x, y = new_depot.y}
            v.px = (new_depot.x - 0.5) * uts
            v.py = (new_depot.y - 0.5) * uts
        end
        if States and States.Idle then v:changeState(States.Idle, game) end
    end

    -- Persist world dimensions FIRST so district lookups work during client respawn
    game.world_city_locations   = self.city_locations
    game.world_w                = self.world_w
    game.world_h                = self.world_h

    -- Reset trips and respawn clients (must be after world_w is set)
    game.entities.trips.pending = {}
    local num_clients = math.max(1, #game.entities.clients)
    game.entities.clients = {}
    local depots = game.entities.depots
    for i = 1, num_clients do
        local depot = depots[((i - 1) % math.max(1, #depots)) + 1]
        game.entities:addClient(game, depot)
    end
    game.world_highway_paths   = self.highway_paths or {}
    game.world_highway_map     = self.highway_map  or {}
    game._world_highway_smooth = nil   -- reset cached smooth paths on new world
    -- Reset per-city canvas caches (new map objects have nil canvas already, but be explicit)
    -- Also pre-build street smooth paths so the snap lookup is ready before the first update tick.
    local RS = require("utils.RoadSmoother")
    for _, m in ipairs(game.maps and game.maps.all_cities or {}) do
        m._overlay_canvas = nil
        m._tile_canvas    = nil
        local m_tps = m.tile_pixel_size or C.MAP.TILE_SIZE
        m._street_smooth_paths_like_v5 = RS.buildStreetPathsLike(
            m.zone_seg_v, m.zone_seg_h, m.zone_grid, m_tps, m.grid)
    end
    if game.maps and game.maps.unified then
        game.maps.unified._snap_lookup = nil  -- force rebuild now that streets are ready
    end

    -- Zoom to downtown and close sandbox
    local ok, err = pcall(function()
        game.maps.city:setScale(C.MAP.SCALES.DOWNTOWN, game)
    end)
    if not ok then print("WorldSandbox sendToGame: setScale failed: " .. tostring(err)) end

    -- Pre-build region border segment cache before freeing region_map
    if self.region_map then
        local ww     = self.world_w
        local wh     = self.world_h
        local ts     = C.MAP.TILE_SIZE   -- 2 pixels per world tile
        local rmap   = self.region_map
        local segs   = {}
        local n      = 0
        for y = 1, wh do
            local row_i = (y - 1) * ww
            for x = 1, ww do
                local rid = rmap[row_i + x] or 0
                if x < ww and (rmap[row_i + x + 1] or 0) ~= rid then
                    n = n + 1
                    segs[n] = { x1 = x * ts,     y1 = (y-1) * ts,
                                x2 = x * ts,     y2 = y     * ts }
                end
                if y < wh and (rmap[row_i + ww + x] or 0) ~= rid then
                    n = n + 1
                    segs[n] = { x1 = (x-1) * ts, y1 = y * ts,
                                x2 = x     * ts, y2 = y * ts }
                end
            end
        end
        game._region_borders      = segs
        game._region_borders_n    = n
    end

    -- Build world hierarchy: world → continent → region → city.
    -- Each city gets its region_id and continent_id; the game gets a nested
    -- lookup table so gameplay systems can find "all cities in this region" etc.
    do
        local ww2         = self.world_w
        local rmap2       = self.region_map
        local cmap2       = self.continent_map
        -- continents[cid] = { id=cid, regions={ [rid]={ id=rid, continent_id=cid, cities={} } } }
        local continents  = {}

        for _, city in ipairs(game.maps.all_cities or {}) do
            local half_w = math.floor((city.city_grid_width  or 30) / 6)
            local half_h = math.floor((city.city_grid_height or 30) / 6)
            local cwx    = (city.world_mn_x or 1) + half_w
            local cwy    = (city.world_mn_y or 1) + half_h
            local ci2    = (cwy - 1) * ww2 + cwx

            local rid = rmap2  and rmap2[ci2]  or 0
            local cid = cmap2  and cmap2[ci2]  or 0

            city.region_id    = rid
            city.continent_id = cid

            if not continents[cid] then
                continents[cid] = { id = cid, regions = {} }
            end
            local cont = continents[cid]
            if not cont.regions[rid] then
                cont.regions[rid] = { id = rid, continent_id = cid, cities = {} }
            end
            table.insert(cont.regions[rid].cities, city)
        end

        game.world_continents = continents
    end

    -- Free all generation-time scratch data. These fields are no longer needed once
    -- the game world is built. Game and map objects hold the only live references.
    self.heightmap            = nil
    self.colormap             = nil
    self.biome_colormap       = nil
    self.biome_data           = nil  -- maps keep their own ref via map.world_biome_data
    self.suitability_colormap = nil
    self.suitability_scores   = nil
    self.continent_colormap   = nil
    self.continent_map        = nil
    self.continents           = nil
    self.region_colormap      = nil
    self.region_map           = nil
    self.regions_list         = nil
    self.moisture_map         = nil
    self.painted_set          = nil
    self.lake_set             = nil
    self.river_paths          = nil
    self.city_district_maps   = nil
    self.city_district_colors = nil
    self.city_district_types  = nil
    self.city_arterial_maps   = nil
    self.city_street_maps     = nil
    self.city_zone_grids      = nil
    self.city_zone_offsets    = nil
    self.city_bounds_list     = nil
    self.city_pois_list       = nil
    self.city_image           = nil  -- transferred to map.city_image above
    self.world_image          = nil  -- transferred to game.world_gen_* above
    self.city_locations       = nil  -- transferred to game.world_city_locations above
    self.highway_map          = nil  -- transferred to game.world_highway_map above
    self.highway_paths        = nil  -- transferred to game.world_highway_paths above
    collectgarbage("collect")

    -- Signal GameView to pre-warm all lazy render caches on the next draw frame,
    -- so the player doesn't hit spikes when first panning or zooming.
    game._prewarm_pending = true

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
        self.moisture_map         = result.moisture_map
        self.biome_colormap       = result.biome_colormap
        self.biome_data           = result.biome_data
        -- Build lake_set (for hi-res water mask) and painted_set from biome_data.
        -- River cells are excluded from lake_set; they're drawn as vector lines instead.
        do
            local bdata = result.biome_data
            local lset, pset = {}, {}
            for y = 1, h do
                for x = 1, w do
                    local i  = (y-1)*w + x
                    local bd = bdata[i]
                    if bd then
                        if bd.is_lake                    then lset[i] = true end
                        if bd.is_river or bd.is_lake     then pset[i] = true end
                    end
                end
            end
            self.lake_set    = lset
            self.painted_set = pset
        end
        self.river_paths = result.river_paths or {}
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
        self.highway_paths         = nil
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
    if self.params.vq_mode == "hires" and self.heightmap and self.moisture_map then
        self:_buildImageHiRes(self.params.vq_hires_scale or 3)
        return
    end
    local active = (self.view_mode == "biome"        and self.biome_colormap)
               or  (self.view_mode == "suitability"  and self.suitability_colormap)
               or  (self.view_mode == "continents"   and self.continent_colormap)
               or  (self.view_mode == "regions"      and self.region_colormap)
               or   self.colormap
    if not active then return end
    self.world_image_scale = 1
    self.world_image = WorldImageService.buildWorldImage(
        active, self.world_w, self.world_h,
        self.city_bounds, self.city_border, self.city_fringe, self.selected_city_bounds,
        self.continent_map, self.region_map,
        self.view_scope, self.selected_continent_id, self.selected_region_id,
        self.selected_downtown_bounds
    )
end

-- Hi-res terrain render: bilinear elevation + analytic temp + bilinear moisture.
-- Lakes get a smooth water-mask overlay.  Rivers are NOT drawn here — they are
-- rendered as smooth vector lines in WorldSandboxView on top of this image.
function WorldSandboxController:_buildImageHiRes(scale)
    if not self.heightmap or not self.moisture_map then
        self:_buildImage()
        return
    end
    local img, s = WorldImageService.buildWorldImageHiRes(
        self.heightmap, self.moisture_map, self.lake_set,
        self.biome_colormap or self.colormap,
        self.world_w, self.world_h, self.params, scale
    )
    self.world_image       = img
    self.world_image_scale = s
end

function WorldSandboxController:set_view(mode)
    self.view_mode = mode
    if self.colormap then self:_buildImage() end
end

function WorldSandboxController:place_cities()
    if not self.suitability_scores then return end
    self.city_locations = CityPlacementService.placeCities(
        self.suitability_scores, self.continent_map, self.continents,
        self.region_map, self.regions_list, self.world_w, self.world_h, self.params
    )
    -- Generate bounds + POIs for all placed cities right away
    if self.region_map and self.heightmap then
        self:_gen_all_bounds()
    end
end

function WorldSandboxController:build_highways()
    if not self.city_locations or #self.city_locations == 0 then return end
    if not self.heightmap or not self.continent_map then return end

    self.highway_map, self.highway_paths = HighwayService.buildHighways(
        self.city_locations, self.heightmap, self.biome_data, self.continent_map,
        self.world_w, self.world_h, self.params
    )
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
    local bounds_list, pois_list, all_bounds, all_pois, border, fringe =
        CityBoundsService.genAllBounds(
            self.city_locations, self.region_map, self.heightmap, self.biome_data,
            self.suitability_scores, self.world_w, self.world_h, self.params, self.math_fns
        )
    self.city_bounds_list = bounds_list
    self.city_pois_list   = pois_list
    self.city_bounds      = all_bounds
    self.city_pois        = all_pois
    self.city_border      = border
    self.city_fringe      = fringe
    -- Invalidate subsystem maps so sendToGame() or regen_bounds() regenerates them fresh
    self.city_district_maps  = nil
    self.city_district_types = nil
    self.city_arterial_maps  = nil
    self.city_street_maps    = nil
    self.city_zone_grids     = nil
    self.city_zone_offsets   = nil
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
    self.city_district_maps, self.city_district_colors = CityDistrictService.genAllDistricts(
        self.city_locations, self.city_bounds_list, self.city_pois_list,
        self.heightmap, self.biome_data, self.world_w, self.world_h, self.params, self.math_fns
    )
end

-- (kept for reference during Batch C extraction — body replaced by CityDistrictService)
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
    self.city_arterial_maps = CityArterialService.genAllArterials(
        self.city_locations, self.city_bounds_list, self.city_pois_list,
        self.highway_map, self.heightmap, self.biome_data,
        self.world_w, self.world_h, self.params, self.math_fns
    )
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
    self.city_street_maps = CityStreetService.genAllStreets(
        self.city_locations, self.city_bounds_list, self.city_pois_list,
        self.city_district_maps, self.world_w, self.world_h
    )
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
    self.status_text = string.format("Bounds + districts regenerated for %d cities", #self.city_locations)
end

-- Builds a high-resolution city image: ~200 city cells across, each CELL_PX×CELL_PX image pixels.
-- Grid lines separate every city cell so the full granularity is visible on screen.
function WorldSandboxController:_buildCityImage(city_idx, min_x, max_x, min_y, max_y)
    local bounds = self.city_bounds_list and self.city_bounds_list[city_idx]
    if not bounds then return end

    local use_districts  = (self.view_mode == "districts")
    local fog_downtown   = (self.view_scope == "downtown")
    local dist_colors    = use_districts and self.city_district_colors and self.city_district_colors[city_idx]
    local dist_owner_map = (use_districts or fog_downtown) and self.city_district_maps and self.city_district_maps[city_idx]
    local pois_for_city  = (use_districts and self.city_pois_list and self.city_pois_list[city_idx]) or {}
    local art_city_map   = self.city_arterial_maps and self.city_arterial_maps[city_idx]
    local street_city_map = self.city_street_maps  and self.city_street_maps[city_idx]
    local terrain_cmap   = self.biome_colormap or self.colormap
    local active
    if not use_districts then
        active = (self.view_mode == "biome"       and self.biome_colormap)
              or (self.view_mode == "suitability" and self.suitability_colormap)
              or  self.colormap
    end

    local img, ix, iy, ik = WorldImageService.buildCityImage(
        city_idx, min_x, max_x, min_y, max_y,
        bounds, self.view_mode, self.view_scope,
        dist_colors, dist_owner_map, pois_for_city,
        self.world_w, art_city_map, street_city_map,
        terrain_cmap, active, self.heightmap,
        self.city_zone_grids   and self.city_zone_grids[city_idx],
        self.city_zone_offsets and self.city_zone_offsets[city_idx]
    )
    if not img then return end
    self.city_image     = img
    self.city_img_min_x = ix
    self.city_img_min_y = iy
    -- pixels per world cell = 3 sub-cells × STRIDE px/sub-cell = 12
    -- GameView uses ts/K as draw scale, so 1 image px = ts/12 world px
    self.city_img_K     = ik
end

-- ── Input ─────────────────────────────────────────────────────────────────────

function WorldSandboxController:handle_keypressed(key)
    if key == "escape" then
        self:close()
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
        local factor    = 1.15 ^ y
        local _, sh     = love.graphics.getDimensions()
        local min_scale = sh / (self.world_h * self.game.C.MAP.TILE_SIZE)
        self.camera.scale = math.max(min_scale, math.min(80, self.camera.scale * factor))
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
        -- Clamp vertical pan so world stays visible
        local ts = self.game.C.MAP.TILE_SIZE
        self.camera.y = math.max(0, math.min(self.world_h * ts, self.camera.y))
    end
    if self.sidebar_manager then
        self.sidebar_manager:handle_mouse_moved(x, y, dx, dy)
    end
end

function WorldSandboxController:handle_textinput(text)
    -- not needed currently
end

-- Center the world image in the viewport at a scale that fits the full world height.
function WorldSandboxController:_centerCamera()
    local C            = self.game.C
    local ts           = C.MAP.TILE_SIZE
    local sw, sh       = love.graphics.getDimensions()
    local sidebar_w    = C.UI.SIDEBAR_WIDTH
    local vw           = sw - sidebar_w
    local world_px_w   = self.world_w * ts
    local world_px_h   = self.world_h * ts
    local scale_fit_w  = vw / world_px_w
    local scale_fit_h  = sh / world_px_h
    self.camera.scale  = math.min(scale_fit_w, scale_fit_h)
    self.camera.x      = world_px_w / 2
    self.camera.y      = world_px_h / 2
end

return WorldSandboxController
