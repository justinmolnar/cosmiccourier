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
    inst.world_image           = nil
    inst.world_w        = 0
    inst.world_h        = 0
    inst.view_mode      = "height"   -- "height" | "biome"
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
        highway_links_per_city = 3, -- slider 1-6: how many nearest-neighbor connections each city gets
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
        self.city_locations       = nil   -- cleared on each regenerate
        self.highway_map          = nil
        self.world_w              = w
        self.world_h              = h
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
    local w, h    = self.world_w, self.world_h
    local hways   = self.highway_map
    local imgdata = love.image.newImageData(w, h)
    for y = 1, h do
        for x = 1, w do
            if hways and hways[(y-1)*w + x] then
                imgdata:setPixel(x-1, y-1, 0.95, 0.78, 0.08, 1.0)  -- golden highway
            else
                local c = active[y][x]
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
    local links_k    = math.max(1, math.floor(p.highway_links_per_city or 3))

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
                    return path
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

    -- Per-continent: build MST (Prim's) + extra shortest non-MST links, then A* each edge
    for _, cits in pairs(cont_cities) do
        local n = #cits
        if n >= 2 then
            -- K-nearest neighbor graph: each city connects to its links_k nearest others.
            -- Deduplicating gives a lattice-like network rather than a bare tree.
            local edges_set = {}
            local edges     = {}
            for a = 1, n do
                local dists = {}
                for b = 1, n do
                    if b ~= a then
                        local dx = cits[a].x - cits[b].x
                        local dy = cits[a].y - cits[b].y
                        dists[#dists+1] = {b, dx*dx+dy*dy}
                    end
                end
                table.sort(dists, function(u, v) return u[2] < v[2] end)
                for k = 1, math.min(links_k, #dists) do
                    local b  = dists[k][1]
                    local ea = math.min(a, b)
                    local eb = math.max(a, b)
                    local key = ea * 10000 + eb
                    if not edges_set[key] then
                        edges_set[key] = true
                        edges[#edges+1] = {ea, eb}
                    end
                end
            end

            -- Run A* for each edge and stamp highway cells
            for _, edge in ipairs(edges) do
                local a   = cits[edge[1]]
                local b   = cits[edge[2]]
                local src = (a.y-1)*w + a.x
                local dst = (b.y-1)*w + b.x
                local path = astar(src, dst)
                if path then
                    for _, ci in ipairs(path) do highway_map[ci] = true end
                end
            end
        end
    end

    self.highway_map = highway_map
    self:_buildImage()
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
    if self.sidebar_manager then
        self.sidebar_manager:handle_mouse_moved(x, y, dx, dy)
    end
end

function WorldSandboxController:handle_textinput(text)
    -- not needed currently
end

return WorldSandboxController
