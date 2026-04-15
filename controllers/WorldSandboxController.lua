-- controllers/WorldSandboxController.lua

local C      = require("data.constants")
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
local GameBridgeService    = require("services.GameBridgeService")

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

    -- Starting city: smallest city in a region that contains ≥ 2 cities.
    -- If no region qualifies, regenerate the world — the Region license tier
    -- is meaningless without at least one neighbor city to expand toward.
    local function boundsCount(bnds)
        if not bnds then return 0 end
        local n = 0
        for _ in pairs(bnds) do n = n + 1 end
        return n
    end

    local function pickStartIdx()
        if not self.region_map or not self.city_bounds_list or not self.city_locations then
            return nil
        end
        local region_to_cities = {}
        for idx = 1, #self.city_locations do
            local bnds = self.city_bounds_list[idx]
            local any_ci = bnds and next(bnds)
            local rid = any_ci and self.region_map[any_ci]
            if rid then
                region_to_cities[rid] = region_to_cities[rid] or {}
                table.insert(region_to_cities[rid], idx)
            end
        end
        local qualifying = {}
        for rid, cities in pairs(region_to_cities) do
            if #cities >= C.WORLD_GEN.STARTING_CITY_MIN_REGION_SIZE then table.insert(qualifying, rid) end
        end
        if #qualifying == 0 then return nil, nil end
        local chosen_rid = qualifying[love.math.random(1, #qualifying)]
        local best_idx, best_n = nil, math.huge
        for _, idx in ipairs(region_to_cities[chosen_rid]) do
            local n = boundsCount(self.city_bounds_list[idx])
            if n > 0 and n < best_n then best_n = n; best_idx = idx end
        end
        return best_idx, chosen_rid
    end

    local MAX_REGEN_ATTEMPTS = C.WORLD_GEN.STARTING_CITY_MAX_REGEN_ATTEMPTS
    local start_idx, chosen_rid = pickStartIdx()
    local regen_attempts = 0
    while not start_idx and regen_attempts < MAX_REGEN_ATTEMPTS do
        regen_attempts = regen_attempts + 1
        print(string.format(
            "WorldSandboxController: no region with ≥%d cities; regenerating world (attempt %d/%d)",
            C.WORLD_GEN.STARTING_CITY_MIN_REGION_SIZE, regen_attempts, MAX_REGEN_ATTEMPTS))
        self:generate()
        self:place_cities()
        start_idx, chosen_rid = pickStartIdx()
    end

    if not start_idx then
        error(string.format(
            "World generation failed to produce a region with ≥%d cities after %d attempts. Adjust world params.",
            C.WORLD_GEN.STARTING_CITY_MIN_REGION_SIZE, MAX_REGEN_ATTEMPTS))
    end

    print(string.format(
        "WorldSandboxController: starting city idx=%d region=%s bounds=%d",
        start_idx, tostring(chosen_rid), boundsCount(self.city_bounds_list[start_idx])))

    -- Subsystem maps were invalidated by _gen_all_bounds during regen; rebuild.
    if not self.city_district_maps then self:_gen_all_districts() end
    if not self.city_arterial_maps  then self:_gen_all_arterials() end
    if not self.city_street_maps    then self:_gen_all_streets() end

    local start_bounds = self.city_bounds_list[start_idx]
    if not start_bounds then
        error(string.format(
            "WorldSandboxController: picker returned idx=%d but city_bounds_list[%d] is nil",
            start_idx, start_idx))
    end

    -- Compute starting city bounding box in world coords
    local city_mn_x, city_mx_x, city_mn_y, city_mx_y = w+1, 0, h+1, 0
    for ci in pairs(start_bounds) do
        local cx = (ci-1)%w+1; local cy = math.floor((ci-1)/w)+1
        if cx < city_mn_x then city_mn_x = cx end; if cx > city_mx_x then city_mx_x = cx end
        if cy < city_mn_y then city_mn_y = cy end; if cy > city_mx_y then city_mx_y = cy end
    end
    if city_mn_x > city_mx_x then
        error(string.format(
            "WorldSandboxController: starting city idx=%d has empty/invalid bounds (bbox degenerate)",
            start_idx))
    end

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

    -- Wire city maps and world data into the running game.
    local start_dmap = self.city_district_maps and self.city_district_maps[start_idx]
    GameBridgeService.wire(
        game, new_map, all_claimed,
        self.highway_map, self.city_bounds_list,
        self.region_map, self.continent_map,
        self.city_locations, self.highway_paths,
        w, h,
        self.water_tile_types,
        start_dmap
    )

    -- Expose raw continent / region lists for the naming pass (and any later
    -- consumer that needs by-id lookup). The hierarchy set up by GameBridge
    -- is cities→regions→continents; these tables carry the per-entity feature
    -- flags added by WorldNoiseService.enrichGeography.
    game.world_continents_list  = self.continents or {}
    game.world_continents_by_id = {}
    for _, c in ipairs(game.world_continents_list) do
        game.world_continents_by_id[c.id] = c
    end
    game.world_regions_by_id = self.regions_list or {}
    game.world_regions_list  = {}
    for rid, r in pairs(game.world_regions_by_id) do
        r.id = r.id or rid
        table.insert(game.world_regions_list, r)
    end
    table.sort(game.world_regions_list, function(a, b) return (a.id or 0) < (b.id or 0) end)

    -- Name continents → regions → cities (hierarchy order).
    local WorldNamingService = require("services.WorldNamingService")
    WorldNamingService.nameWorld(game)

    -- Free all generation-time scratch data. These fields are no longer needed once
    -- the game world is built. Game and map objects hold the only live references.
    self.water_tile_types     = nil
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
        self.water_tile_types     = result.water_tile_types
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

function WorldSandboxController:_gen_all_districts()
    self.city_district_maps, self.city_district_colors = CityDistrictService.genAllDistricts(
        self.city_locations, self.city_bounds_list, self.city_pois_list,
        self.heightmap, self.biome_data, self.world_w, self.world_h, self.params, self.math_fns
    )
end

function WorldSandboxController:_gen_all_arterials()
    self.city_arterial_maps = CityArterialService.genAllArterials(
        self.city_locations, self.city_bounds_list, self.city_pois_list,
        self.highway_map, self.heightmap, self.biome_data,
        self.world_w, self.world_h, self.params, self.math_fns
    )
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
    local dist_colors    = use_districts and self.city_district_colors and self.city_district_colors[city_idx]
    local dist_owner_map = use_districts and self.city_district_maps and self.city_district_maps[city_idx]
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
