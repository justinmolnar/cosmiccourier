-- controllers/WorldSandboxController.lua
-- F8 world generation sandbox. Completely standalone; no effect on main game or F9 sandbox.

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
    inst.city_arterial_maps    = nil   -- [city_idx] = {[sci] = true}  sub-cell roads
    inst.city_street_maps      = nil   -- [city_idx] = {[sci] = true}  sub-cell streets (between cells)
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

    local sw = w * 3   -- sub-cell row width

    -- art_wc[ci] = true when world cell ci contains at least one arterial sub-cell
    local art_wc = {}
    for idx = 1, #self.city_locations do
        local amap = self.city_arterial_maps and self.city_arterial_maps[idx]
        if amap then
            for sci in pairs(amap) do
                local gscx = (sci - 1) % sw
                local gscy = math.floor((sci - 1) / sw)
                local wx   = math.floor(gscx / 3) + 1
                local wy   = math.floor(gscy / 3) + 1
                art_wc[(wy - 1) * w + wx] = true
            end
        end
    end

    -- has_street[ci] = true when world cell ci is the cell "before" a street boundary
    local has_street = {}
    for idx = 1, #self.city_locations do
        local smap = self.city_street_maps and self.city_street_maps[idx]
        if smap then
            for key in pairs(smap.v or {}) do
                local cx = math.floor(key / 1000); local cy = key % 1000
                has_street[(cy - 1) * w + cx] = true
            end
            for key in pairs(smap.h or {}) do
                local cy = math.floor(key / 1000); local cx = key % 1000
                has_street[(cy - 1) * w + cx] = true
            end
        end
    end

    -- all_claimed[ci] = city_idx
    local all_claimed = {}
    for idx = 1, #self.city_locations do
        local bnds = self.city_bounds_list and self.city_bounds_list[idx]
        if bnds then
            for ci in pairs(bnds) do all_claimed[ci] = idx end
        end
    end

    -- downtown_cells: world cells within DT_RADIUS of starting city's first POI
    local downtown_cells = {}
    local poi1 = self.city_pois_list and self.city_pois_list[start_idx]
                 and self.city_pois_list[start_idx][1]
    local DT_RADIUS = 6   -- world-cell radius around downtown POI
    if poi1 then
        for ci in pairs(start_bounds) do
            local cx = (ci-1)%w+1; local cy = math.floor((ci-1)/w)+1
            local dx = cx - poi1.x; local dy = cy - poi1.y
            if dx*dx + dy*dy <= DT_RADIUS*DT_RADIUS then
                downtown_cells[ci] = true
            end
        end
    end

    -- Build tile grid for the starting city's bounding box only
    local cw = city_mx_x - city_mn_x + 1
    local ch = city_mx_y - city_mn_y + 1
    local grid = {}
    local p = self.params
    for gy = 1, ch do
        grid[gy] = {}
        local world_gy = city_mn_y + gy - 1
        for gx = 1, cw do
            local world_gx = city_mn_x + gx - 1
            local ci       = (world_gy - 1) * w + world_gx
            local tile
            if self.highway_map and self.highway_map[ci] then
                tile = "highway"
            elseif art_wc[ci] then
                tile = "arterial"
            elseif has_street[ci] and all_claimed[ci] then
                tile = downtown_cells[ci] and "downtown_road" or "road"
            elseif all_claimed[ci] then
                tile = downtown_cells[ci] and "downtown_plot" or "plot"
            else
                local elev = (self.heightmap and self.heightmap[world_gy] and self.heightmap[world_gy][world_gx]) or 0.5
                if     elev <= (p.ocean_max    or 0.42) then tile = "water"
                elseif elev >= (p.highland_max or 0.80) then tile = "mountain"
                else                                          tile = "grass" end
            end
            grid[gy][gx] = {type = tile}
        end
    end

    -- Downtown bounding box in city-grid-local coords (starting city's district-1 cells)
    local dt_mn_x, dt_mx_x, dt_mn_y, dt_mx_y = cw+1, 0, ch+1, 0
    for ci in pairs(downtown_cells) do
        local cx = (ci-1)%w+1; local cy = math.floor((ci-1)/w)+1
        local lx = cx - city_mn_x + 1; local ly = cy - city_mn_y + 1
        if lx < dt_mn_x then dt_mn_x = lx end; if lx > dt_mx_x then dt_mx_x = lx end
        if ly < dt_mn_y then dt_mn_y = ly end; if ly > dt_mx_y then dt_mx_y = ly end
    end
    if dt_mn_x > dt_mx_x then
        -- Fallback: POI of starting city
        local poi = self.city_pois_list and self.city_pois_list[start_idx] and self.city_pois_list[start_idx][1]
        local r = 4
        if poi then
            local lx = poi.x - city_mn_x + 1; local ly = poi.y - city_mn_y + 1
            dt_mn_x = math.max(1, lx-r); dt_mx_x = math.min(cw, lx+r)
            dt_mn_y = math.max(1, ly-r); dt_mx_y = math.min(ch, ly+r)
        else
            dt_mn_x=1; dt_mx_x=10; dt_mn_y=1; dt_mx_y=10
        end
    end

    C.MAP.CITY_GRID_WIDTH      = cw
    C.MAP.CITY_GRID_HEIGHT     = ch
    C.MAP.DOWNTOWN_GRID_WIDTH  = math.max(1, dt_mx_x - dt_mn_x + 1)
    C.MAP.DOWNTOWN_GRID_HEIGHT = math.max(1, dt_mx_y - dt_mn_y + 1)

    local Map     = require("models.Map")
    local new_map = Map:new(C)
    new_map.grid            = grid
    new_map.downtown_offset = {x = dt_mn_x, y = dt_mn_y}
    new_map.building_plots  = new_map:getPlotsFromGrid(grid)

    -- Helper: build city scope image with a specific view_mode (and optional scope), returns love.graphics.Image
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

    -- Helper: build world_image with specific scope/continent/region
    local function buildWorldImg(scope, cid, rid)
        local sv_scope = self.view_scope
        local sv_cid   = self.selected_continent_id
        local sv_rid   = self.selected_region_id
        local sv_mode  = self.view_mode
        self.view_scope = scope
        self.selected_continent_id = cid
        self.selected_region_id    = rid
        -- world images always use biome (or height as fallback)
        self.view_mode = self.biome_colormap and "biome" or "height"
        self:_buildImage()
        self.view_scope = sv_scope
        self.selected_continent_id = sv_cid
        self.selected_region_id    = sv_rid
        self.view_mode = sv_mode
        return self.world_image
    end

    -- Choose richest city-scope colour mode
    local city_mode = (self.city_district_maps and self.city_district_maps[start_idx])
                      and "districts"
                      or  (self.biome_colormap and "biome" or "height")

    -- City F8 image: full city bounds (padded 2 cells)
    local cox1=math.max(1,city_mn_x-2); local cox2=math.min(w,city_mx_x+2)
    local coy1=math.max(1,city_mn_y-2); local coy2=math.min(h,city_mx_y+2)
    -- Downtown fogged version: same bounds as city image but with fog baked in
    game.world_gen_downtown_fogged_image = buildCityImg(city_mode, cox1, cox2, coy1, coy2, "downtown")
    -- Unfogged city image
    game.world_gen_city_image     = buildCityImg(city_mode, cox1, cox2, coy1, coy2)
    game.world_gen_city_img_x     = cox1
    game.world_gen_city_img_y     = coy1

    -- Store city origin for vehicle coord mapping
    game.world_gen_city_mn_x = city_mn_x   -- world cell of city grid top-left
    game.world_gen_city_mn_y = city_mn_y

    -- Determine starting city's continent and region IDs
    local start_loc = self.city_locations[start_idx]
    local start_ci  = (start_loc.y - 1) * w + start_loc.x
    local start_cid = self.continent_map and self.continent_map[start_ci]
    local start_rid = self.region_map    and self.region_map[start_ci]

    -- Region image: scope = starting city's region (darkened outside), fallback to world
    game.world_gen_region_image =
        buildWorldImg(start_rid and "region" or "world", nil, start_rid)

    -- Continent image: scope = starting city's continent, fallback to world
    game.world_gen_continent_image =
        buildWorldImg(start_cid and "continent" or "world", start_cid, nil)

    -- World image: full world
    game.world_gen_world_image = buildWorldImg("world", nil, nil)

    -- Store city image metadata (set by the last _buildCityImage call = city-scope)
    game.world_gen_city_img_min_x = self.city_img_min_x   -- cox1
    game.world_gen_city_img_min_y = self.city_img_min_y   -- coy1
    game.world_gen_city_img_K     = self.city_img_K       -- 9

    -- Precompute camera params for all 5 zoom levels (world-pixel coords, mirrors _fitToArea)
    do
        local ts2 = C.MAP.TILE_SIZE
        local sw2, sh2 = love.graphics.getDimensions()
        local vw2 = sw2 - C.UI.SIDEBAR_WIDTH

        local function fitArea(mn_x, mx_x, mn_y, mx_y)
            local aw = (mx_x - mn_x + 1) * ts2
            local ah = (mx_y - mn_y + 1) * ts2
            return {
                scale = math.min(vw2 / aw, sh2 / ah) * 0.88,
                x = ((mn_x + mx_x) * 0.5 - 0.5) * ts2,
                y = ((mn_y + mx_y) * 0.5 - 0.5) * ts2,
            }
        end

        local cp = {}
        local S2 = C.MAP.SCALES

        -- DOWNTOWN: sub-cell bounds of district poi_idx==1 (matches F8 _selectDowntown logic)
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
                local ts2 = C.MAP.TILE_SIZE
                local px_x1 = mn_scx / 3 * ts2
                local px_x2 = (mx_scx + 1) / 3 * ts2
                local px_y1 = mn_scy / 3 * ts2
                local px_y2 = (mx_scy + 1) / 3 * ts2
                local area_w2 = px_x2 - px_x1
                local area_h2 = px_y2 - px_y1
                cp[S2.DOWNTOWN] = {
                    scale = math.min(vw2 / area_w2, sh2 / area_h2) * 0.88,
                    x = (px_x1 + px_x2) * 0.5,
                    y = (px_y1 + px_y2) * 0.5,
                }
            else
                -- Fallback: city bounds
                cp[S2.DOWNTOWN] = fitArea(city_mn_x, city_mx_x, city_mn_y, city_mx_y)
            end
        end

        -- CITY: full starting city bounds
        cp[S2.CITY] = fitArea(city_mn_x, city_mx_x, city_mn_y, city_mx_y)

        -- REGION: bounding box of starting city's region
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

        -- CONTINENT: bounding box of starting city's continent
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

        -- WORLD: full map
        cp[S2.WORLD] = fitArea(1, w, 1, h)

        game.world_gen_cam_params = cp
    end

    -- Stamp onto game
    game.maps.city      = new_map
    game.active_map_key = "city"
    game.lab_grid       = nil
    game.wfc_final_grid = nil
    game.lab_zone_grid  = nil

    -- Reset vehicles
    local States    = require("models.vehicles.vehicle_states")
    local new_depot = new_map:getRandomDowntownBuildingPlot() or new_map:getRandomBuildingPlot()
    game.entities.depot_plot = new_depot
    for _, v in ipairs(game.entities.vehicles) do
        v.cargo = {}; v.trip_queue = {}; v.path = {}
        if new_depot then
            v.depot_plot  = new_depot
            v.grid_anchor = {x = new_depot.x, y = new_depot.y}
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

    -- Zoom to downtown and close sandbox
    local ok, err = pcall(function()
        game.maps.city:setScale(C.MAP.SCALES.DOWNTOWN)
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
    -- Re-rasterise arterials now that highway data is available
    if self.city_bounds_list then
        self:_gen_all_arterials()
    end
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

    self:_gen_all_districts()
    self:_gen_all_arterials()
    self:_gen_all_streets()
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

-- ── Downtown street generator ─────────────────────────────────────────────────
-- Recursive binary-space-partition of the downtown district bounding box.
-- Streets run BETWEEN world cells (at the shared edge), not ON them, so they
-- occupy the 2 sub-cells that straddle each boundary:
--   vertical boundary after world column wx   → gscx = wx*3+2  AND  (wx+1)*3+0
--   horizontal boundary after world row wy    → gscy = wy*3+2  AND  (wy+1)*3+0
-- Each boundary sub-cell column/row runs the full height/width of the block
-- being split (3 sub-cells per world cell tall/wide).

local ST_MIN_BLOCK = 2   -- min block side in world cells before we stop splitting
local ST_MAX_BLOCK = 3   -- max block side before we force a split

function WorldSandboxController:_gen_streets_for_city(city_idx)
    local bounds   = self.city_bounds_list   and self.city_bounds_list[city_idx]
    local pois     = self.city_pois_list     and self.city_pois_list[city_idx]
    local dist_map = self.city_district_maps and self.city_district_maps[city_idx]
    if not bounds or not pois or #pois == 0 then return {v={},h={}} end

    local w  = self.world_w
    local sw = w * 3
    local function sci_of(gscx, gscy) return gscy * sw + gscx + 1 end

    -- Build set of world cells owned by downtown (district owner index 1)
    local dt_cells = {}
    if dist_map then
        for ci in pairs(bounds) do
            local cx = (ci-1) % w + 1
            local cy = math.floor((ci-1) / w) + 1
            if dist_map[sci_of((cx-1)*3+1, (cy-1)*3+1)] == 1 then
                dt_cells[ci] = true
            end
        end
    end
    -- Fallback: fixed radius around downtown POI if district map absent or tiny
    if not next(dt_cells) then
        local dt = pois[1]; local r = 3
        local mn_x = math.max(1, dt.x-r); local mx_x = math.min(w, dt.x+r)
        local mn_y = math.max(1, dt.y-r); local mx_y = math.min(self.world_h, dt.y+r)
        for cy = mn_y, mx_y do
            for cx = mn_x, mx_x do
                dt_cells[(cy-1)*w+cx] = true
            end
        end
    end

    -- Regular grid: draw a street boundary between two cells when BOTH are
    -- downtown AND the boundary falls on a grid line (every SPACING cells).
    -- Grid is aligned to a global origin so all cities share the same phase.
    -- This handles irregular downtown shapes naturally: lines only appear where
    -- both neighbours are inside the district, so the grid clips to the shape.
    local sv, sh = {}, {}
    for ci in pairs(dt_cells) do
        local cx = (ci-1) % w + 1
        local cy = math.floor((ci-1) / w) + 1

        -- Vertical boundary: between col cx and cx+1, if cx is a grid line
        if cx % ST_MIN_BLOCK == 0 and cx < w then
            local r_ci = (cy-1)*w + (cx+1)
            if dt_cells[r_ci] then sv[cx * 1000 + cy] = true end
        end
        -- Horizontal boundary: between row cy and cy+1, if cy is a grid line
        if cy % ST_MIN_BLOCK == 0 and cy < self.world_h then
            local b_ci = cy*w + cx
            if dt_cells[b_ci] then sh[cy * 1000 + cx] = true end
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

    -- Each world cell = 9×9 image pixels; lines at 0,3,6 create a tic-tac-toe grid
    local CELL  = 9
    local img_w = bbox_w * CELL
    local img_h = bbox_h * CELL

    local imgdata = love.image.newImageData(img_w, img_h)

    for py = 0, img_h - 1 do
        local wy = min_y + math.floor(py / CELL)
        local iy = py % CELL
        for px = 0, img_w - 1 do
            local wx = min_x + math.floor(px / CELL)
            local ci = (wy-1)*w + wx

            -- Sub-cell coordinates for this pixel
            local gscx = (wx - 1) * 3 + math.floor((px % CELL) / 3)
            local gscy = (wy - 1) * 3 + math.floor(iy / 3)

            -- Determine base colour for this cell
            local c
            if use_districts then
                -- Look up this sub-cell's district owner from the precomputed
                -- terrain-aware sub-cell Dijkstra map.  The owner map key is the
                -- same formula used during flood-fill: gscy*sub_w + gscx + 1.
                local best_poi = dist_owner_map and dist_owner_map[gscy * sub_w + gscx + 1]

                -- Fallback: nearest-POI if Dijkstra map is absent (e.g. just placed
                -- cities but haven't run Regen Bounds yet).
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
                -- World-cell base colour, modulated by sub-cell elevation delta
                -- so each sub-cell shows its own character within the world cell.
                local bc      = active[wy] and active[wy][wx] or {0.1, 0.1, 0.1}
                local world_e = self.heightmap[wy][wx]
                local sub_e   = subcell_elev_at(gscx, gscy, self.heightmap)
                local adjust  = (sub_e - world_e) * 3.0   -- amplify delta for visibility
                c = {
                    math.max(0, math.min(1, bc[1] + adjust)),
                    math.max(0, math.min(1, bc[2] + adjust)),
                    math.max(0, math.min(1, bc[3] + adjust)),
                }
            end

            -- Arterial road overlay (always visible regardless of view mode)
            if art_city_map and art_city_map[gscy * sub_w + gscx + 1] then
                c = {0.20, 0.19, 0.17}   -- dark asphalt
            end

            if bounds[ci] then
                local ix    = px % CELL
                local outer = (ix == 0 or iy == 0)
                local inner = (ix == 3 or ix == 6 or iy == 3 or iy == 6)

                -- Streets run between world cells: paint the 2 boundary pixels
                -- (ix=8 of the left/top cell AND ix=0 of the right/bottom cell)
                -- at full brightness so they appear as thin bright lines, not
                -- colored sub-cells.  Arterials painted above still take priority
                -- because the arterial check already changed c; we only override
                -- the per-pixel dimming logic here, not c itself.
                -- Streets are 1px: only the outer border pixel (ix=0 / iy=0) of the
                -- right/bottom cell at each boundary.  ix=0 is already the cell-border
                -- line drawn everywhere; we just paint it bright instead of dark.
                local is_street = false
                if street_city_map and (ix == 0 or iy == 0) then
                    local sv, sh = street_city_map.v, street_city_map.h
                    -- ix=0 → boundary is after col wx-1
                    if ix == 0 and wx > min_x then
                        is_street = sv and sv[(wx-1) * 1000 + wy]
                    end
                    -- iy=0 → boundary is after row wy-1
                    if iy == 0 and wy > min_y then
                        is_street = is_street or (sh and sh[(wy-1) * 1000 + wx])
                    end
                end

                local r, g, b
                if is_street then
                    r, g, b = 0.88, 0.86, 0.80
                elseif outer then
                    r, g, b = c[1]*0.20, c[2]*0.20, c[3]*0.20
                elseif inner then
                    r, g, b = c[1]*0.55, c[2]*0.55, c[3]*0.55
                else
                    r, g, b = c[1], c[2], c[3]
                end
                -- Bake downtown fog: darken non-district-1 sub-cells at pixel precision
                if fog_downtown and dist_owner_map then
                    local sci2 = gscy * sub_w + gscx + 1
                    if dist_owner_map[sci2] ~= 1 then
                        r = r*0.18+0.01; g = g*0.18+0.02; b = b*0.18+0.06
                    end
                end
                imgdata:setPixel(px, py, r, g, b, 1.0)
            else
                -- Outside city bounds: terrain colour, dimmed
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
    self.city_img_K     = CELL
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
