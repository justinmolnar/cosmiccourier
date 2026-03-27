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
    inst.city_bounds_list      = nil
    inst.selected_city_idx     = nil
    inst.selected_city_bounds  = nil
    inst.city_image            = nil   -- high-res city grid image (city scope)
    inst.city_img_min_x        = 0
    inst.city_img_min_y        = 0
    inst.city_img_K            = 1
    inst.world_image           = nil
    inst.world_w        = 0
    inst.world_h        = 0
    inst.view_mode      = "height"   -- "height" | "biome" | "suitability" | "continents" | "regions"
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
        city_poi_count     = 5,    -- slider 2-10: POIs to identify (downtown + districts)
        city_poi_spacing   = 1.0,  -- slider 0.3-3.0: multiplier on auto-spacing (1.0 = evenly distribute across footprint)
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

    -- Separation spreads POIs evenly across the inner footprint
    local spacing    = p.city_poi_spacing or 1.0
    local inner_size = 0
    for _ in pairs(inner) do inner_size = inner_size + 1 end
    local poi_sep    = math.max(2, math.floor(math.sqrt(inner_size / math.max(1, poi_count)) * spacing))
    local poi_sep_sq = poi_sep * poi_sep

    -- Build candidate list from INNER cells only (guaranteed padding from edge)
    local suit_cells = {}
    for ci in pairs(inner) do
        suit_cells[#suit_cells+1] = { i=ci, s=(scores and scores[ci] or 0) }
    end
    table.sort(suit_cells, function(a, b) return a.s > b.s end)

    local used       = {}
    local candidates = {}
    for _, sc in ipairs(suit_cells) do
        local px = (sc.i-1) % w + 1
        local py = math.floor((sc.i-1) / w) + 1
        local ok = true
        for _, c in ipairs(candidates) do
            local ddx, ddy = px-c.x, py-c.y
            if ddx*ddx+ddy*ddy < poi_sep_sq then ok=false; break end
        end
        if ok then
            used[sc.i] = true
            candidates[#candidates+1] = { x=px, y=py, s=sc.s, region_id=rid }
        end
        if #candidates >= poi_count then break end
    end
    -- Fallback: fill remaining ignoring separation so every city always gets POIs
    if #candidates < poi_count then
        for _, sc in ipairs(suit_cells) do
            if not used[sc.i] then
                candidates[#candidates+1] = { x=(sc.i-1)%w+1, y=math.floor((sc.i-1)/w)+1,
                                               s=sc.s, region_id=rid }
            end
            if #candidates >= poi_count then break end
        end
    end

    -- Centroid of eroded inner area; downtown = candidate closest to it
    local sum_x, sum_y, n = 0, 0, 0
    for ci in pairs(inner) do
        sum_x = sum_x + (ci-1) % w + 1
        sum_y = sum_y + math.floor((ci-1) / w) + 1
        n     = n + 1
    end
    local cen_x = n > 0 and sum_x / n or city.x
    local cen_y = n > 0 and sum_y / n or city.y

    local best_d2, dt_idx = math.huge, 1
    for k, c in ipairs(candidates) do
        local d2 = (c.x - cen_x)^2 + (c.y - cen_y)^2
        if d2 < best_d2 then best_d2 = d2; dt_idx = k end
    end

    local pois = {}
    for k, c in ipairs(candidates) do
        pois[#pois+1] = { x=c.x, y=c.y, s=c.s, region_id=rid,
                          type=(k == dt_idx and "downtown" or "district") }
    end
    if #pois > 1 then pois[1], pois[dt_idx] = pois[dt_idx], pois[1] end

    return claimed, pois
end

-- Regenerates city_bounds and city_pois for all currently placed cities.
function WorldSandboxController:_gen_all_bounds()
    if not self.city_locations then return end
    local new_bounds      = {}
    local new_bounds_list = {}
    local new_pois        = {}
    for idx, city in ipairs(self.city_locations) do
        local claimed, pois = self:_gen_bounds_for_city(city)
        new_bounds_list[idx] = claimed or {}
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
end

function WorldSandboxController:regen_bounds()
    if not self.city_locations then
        self.status_text = "Place cities first"
        return
    end
    self:_gen_all_bounds()
    self:_buildImage()
    self.status_text = string.format("Bounds regenerated for %d cities", #self.city_locations)
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

-- Builds a high-resolution city image: ~200 city cells across, each CELL_PX×CELL_PX image pixels.
-- Grid lines separate every city cell so the full granularity is visible on screen.
function WorldSandboxController:_buildCityImage(city_idx, min_x, max_x, min_y, max_y)
    local bounds = self.city_bounds_list and self.city_bounds_list[city_idx]
    if not bounds then return end
    local active = (self.view_mode == "biome"       and self.biome_colormap)
               or  (self.view_mode == "suitability" and self.suitability_colormap)
               or   self.colormap
    if not active then return end

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
            local c  = active[wy] and active[wy][wx] or {0.1, 0.1, 0.1}
            if bounds[ci] then
                local ix = px % CELL
                local outer = (ix == 0 or iy == 0)
                local inner = (ix == 3 or ix == 6 or iy == 3 or iy == 6)
                if outer then
                    imgdata:setPixel(px, py, c[1]*0.20, c[2]*0.20, c[3]*0.20, 1.0)
                elseif inner then
                    imgdata:setPixel(px, py, c[1]*0.60, c[2]*0.60, c[3]*0.60, 1.0)
                else
                    imgdata:setPixel(px, py, c[1], c[2], c[3], 1.0)
                end
            else
                imgdata:setPixel(px, py, c[1]*0.18+0.01, c[2]*0.18+0.02, c[3]*0.18+0.06, 1.0)
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
