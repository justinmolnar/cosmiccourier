-- controllers/SandboxController.lua
-- F9 sandbox. Uses the same WFC generation pipeline as WfcLabController.
-- Ports the lab views (zones, arterials overlay, streets, standard tile map)
-- into togglable view modes controlled from the sidebar.

local SandboxController = {}
SandboxController.__index = SandboxController

local VIEW_MODES = { "zones", "arterials", "streets", "tiles", "flood_fill", "standard" }
local VIEW_LABELS = {
    zones      = "Zones",
    arterials  = "Arterials",
    streets    = "Streets",
    tiles      = "Tiles",
    flood_fill = "Flood Fill",
    standard   = "Game Map",
}

function SandboxController:new(game)
    local inst = setmetatable({}, SandboxController)
    inst.game   = game
    inst.active = false

    inst.camera = { x = 0, y = 0, scale = 1 }
    inst.camera_dragging = false
    inst.camera_drag_start_x = 0
    inst.camera_drag_start_y = 0

    -- Generated data (mirrors what WfcLabController stored on Game.*)
    inst.sandbox_map      = nil   -- Map object for "standard" tile view
    inst.lab_grid         = nil   -- city_grid from NewCityGenService
    inst.lab_zone_grid    = nil   -- zone_grid
    inst.arterial_paths   = {}    -- arterial control paths
    inst.smooth_paths     = {}    -- catmull-rom smoothed overlays
    inst.street_segments  = {}    -- street segments (horizontal/vertical lines)

    inst.districts        = {}
    inst.district_overrides = {}
    inst.flood_fill_regions = {}
    inst.downtown_region    = nil  -- synthetic region covering the downtown area
    inst.region_cell_lookup = {}   -- [y][x] = region_id  (fast hit-test)
    inst.region_overrides   = {}   -- [region_id] = per-region algo params
    inst.zone_modal         = nil  -- ZoneModal instance or nil
    inst.status_text = ""
    inst.view_mode_idx = 1
    inst.view_mode = VIEW_MODES[1]

    inst.sidebar_manager = nil

    inst.params = {
        city_w = 200, city_h = 200,
        downtown_w = 64, downtown_h = 64,
        min_block_size    = 0,   -- 0 = dynamic
        max_block_size    = 0,   -- 0 = dynamic
        num_arterials       = 0,   -- 0 = auto
        arterial_thickness  = 1,   -- tiles wide when written to grid
        min_edge_distance   = 15,
        street_algo       = 1,
        warp_strength     = 4,
        warp_scale        = 25,
        block_variance    = 0.25,
        num_spokes        = 8,
        num_rings         = 4,
        radial_grid_fill  = 1,
        max_road_length   = 30,
        branch_chance     = 0.06,
        turn_chance       = 0.04,
        num_seeds         = 40,
        -- Display params (affect view, not generation)
        arterial_width   = 0.8,  -- multiplier of tile_size for arterial line thickness
        smooth_segments  = 8,    -- catmull-rom segments per span
    }

    return inst
end

function SandboxController:isActive() return self.active end

function SandboxController:toggle()
    if self.active then self:close() else self:open() end
end

function SandboxController:open()
    self.active = true
    if not self.sidebar_manager then
        local SandboxSidebarManager = require("views.SandboxSidebarManager")
        self.sidebar_manager = SandboxSidebarManager:new(self, self.game)
    end
end

function SandboxController:close() self.active = false end

function SandboxController:cycleViewMode()
    self.view_mode_idx = (self.view_mode_idx % #VIEW_MODES) + 1
    self.view_mode = VIEW_MODES[self.view_mode_idx]
end

function SandboxController:setViewMode(mode)
    self.view_mode = mode
    for i, m in ipairs(VIEW_MODES) do
        if m == mode then self.view_mode_idx = i; break end
    end
end

function SandboxController:viewLabel()
    return VIEW_LABELS[self.view_mode] or "View: Zones"
end

function SandboxController._zoneColor(zone_type)
    local colors = {
        downtown           = {1, 1, 0},
        commercial         = {0, 0, 1},
        residential_north  = {0, 1, 0},
        residential_south  = {0, 0.7, 0},
        industrial_heavy   = {1, 0, 0},
        industrial_light   = {0.8, 0.2, 0.2},
        university         = {0.6, 0, 0.8},
        medical            = {1, 0.5, 0.8},
        entertainment      = {1, 0.5, 0},
        waterfront         = {0, 0.8, 0.8},
        warehouse          = {0.5, 0.3, 0.1},
        tech               = {0.3, 0.3, 0.8},
        park_central       = {0.2, 0.8, 0.3},
        park_nature        = {0.1, 0.6, 0.1},
    }
    return colors[zone_type] or {0.5, 0.5, 0.5}
end

-- ── Generation ───────────────────────────────────────────────────────────────

function SandboxController:generate()
    local game = self.game
    local C    = game.C
    local p    = self.params

    local city_w = math.max(32, math.floor(p.city_w))
    local city_h = math.max(32, math.floor(p.city_h))
    local dt_w   = math.max(8,  math.floor(p.downtown_w))
    local dt_h   = math.max(8,  math.floor(p.downtown_h))

    -- Temp-override constants so NewCityGenService (which reads game.C directly) sees sandbox dims
    local saved_MAP = {}
    for k, v in pairs(C.MAP) do
        if type(v) ~= "table" then saved_MAP[k] = v end
    end
    C.MAP.CITY_GRID_WIDTH      = city_w
    C.MAP.CITY_GRID_HEIGHT     = city_h
    C.MAP.DOWNTOWN_GRID_WIDTH  = dt_w
    C.MAP.DOWNTOWN_GRID_HEIGHT = dt_h

    local gen_params = {
        width  = city_w,
        height = city_h,
        use_wfc_for_zones    = true,
        use_recursive_streets = true,
        generate_arterials   = true,
    }
    if p.min_block_size > 0 then gen_params.min_block_size = math.floor(p.min_block_size) end
    if p.max_block_size > 0 then gen_params.max_block_size = math.floor(p.max_block_size) end
    if p.num_arterials  > 0 then gen_params.num_arterials  = math.floor(p.num_arterials)  end
    gen_params.arterial_thickness = math.max(1, math.floor(p.arterial_thickness))
    gen_params.min_edge_distance = p.min_edge_distance
    gen_params.street_algo      = math.floor(p.street_algo or 1)
    gen_params.warp_strength    = p.warp_strength
    gen_params.warp_scale       = p.warp_scale
    gen_params.block_variance   = p.block_variance
    gen_params.num_spokes       = math.floor(p.num_spokes or 8)
    gen_params.num_rings        = math.floor(p.num_rings or 4)
    gen_params.radial_grid_fill = (p.radial_grid_fill or 1) > 0.5
    gen_params.max_road_length  = math.floor(p.max_road_length or 30)
    gen_params.branch_chance    = p.branch_chance
    gen_params.turn_chance      = p.turn_chance
    gen_params.num_seeds        = math.floor(p.num_seeds or 40)

    local NewCityGenService = require("services.NewCityGenService")
    local ok, result = pcall(function()
        return NewCityGenService.generateDetailedCity(gen_params)
    end)

    -- Restore constants
    for k, v in pairs(saved_MAP) do C.MAP[k] = v end

    if not ok then
        self.status_text = "FAILED: " .. tostring(result)
        print("SANDBOX ERROR: " .. tostring(result))
        return
    end

    if not result or not result.city_grid then
        self.status_text = "FAILED: no city_grid returned"
        return
    end

    -- Store results (same fields WfcLabController used on Game.*)
    self.lab_grid       = result.city_grid
    self.lab_zone_grid  = result.zone_grid
    self.arterial_paths = result.arterial_paths or {}
    self.street_segments = game.street_segments or {}  -- set as side-effect by NewCityGenService
    self.smooth_paths   = {}  -- reset; user can re-trigger via sidebar if needed

    -- Build smooth arterial overlays (what WfcLabController's 'y' key did)
    self:_buildSmoothOverlays()

    -- Build a Map object for "standard" tile view
    local sandbox_MAP = {}
    for k, v in pairs(C.MAP) do sandbox_MAP[k] = v end
    sandbox_MAP.CITY_GRID_WIDTH      = city_w
    sandbox_MAP.CITY_GRID_HEIGHT     = city_h
    sandbox_MAP.DOWNTOWN_GRID_WIDTH  = dt_w
    sandbox_MAP.DOWNTOWN_GRID_HEIGHT = dt_h

    local sandbox_C = setmetatable({ MAP = sandbox_MAP }, { __index = C })
    local Map = require("models.Map")
    self.sandbox_map = Map:new(sandbox_C)
    self.sandbox_map.grid = result.city_grid
    self.sandbox_map.zone_grid = result.zone_grid
    self.sandbox_map.building_plots = self.sandbox_map:getPlotsFromGrid(result.city_grid)
    self.sandbox_map.downtown_offset = {
        x = math.floor(city_w / 2) - math.floor(dt_w / 2),
        y = math.floor(city_h / 2) - math.floor(dt_h / 2),
    }

    self:_detectDistricts()
    self:_buildFloodFill()
    self:_buildRegionLookup()
    self:_buildDowntownRegion()
    self.zone_modal = nil   -- close any open modal when regenerating
    self:_centerCameraOnMap()

    self.status_text = string.format("Generated %dx%d (DT %dx%d) | %d plots | %d arterials",
        city_w, city_h, dt_w, dt_h,
        #self.sandbox_map.building_plots,
        #self.arterial_paths)

    if self.sidebar_manager then
        self.sidebar_manager:rebuildPerDistrictPanel()
    end
end

function SandboxController:_buildSmoothOverlays()
    local WfcLabController = require("controllers.WfcLabController")
    local segs = math.max(2, math.floor(self.params.smooth_segments or 8))
    self.smooth_paths = {}
    for _, control_points in ipairs(self.arterial_paths) do
        local smooth = WfcLabController._smoothPathForOverlay(control_points, segs)
        if #smooth > 1 then
            table.insert(self.smooth_paths, smooth)
        end
    end
end

function SandboxController:_buildFloodFill()
    self.flood_fill_regions = {}
    if not self.lab_grid or not self.lab_zone_grid then return end
    local WfcLabController = require("controllers.WfcLabController")
    local ok, regions = pcall(function()
        return WfcLabController._debugFloodFillRegions(self.lab_grid, self.lab_zone_grid)
    end)
    if ok and regions then
        self.flood_fill_regions = regions
    end
end

function SandboxController:_detectDistricts()
    -- Build a lookup of existing overrides by district name so they survive regeneration
    local saved = {}
    for _, d in ipairs(self.districts or {}) do
        if self.district_overrides[d.index] then
            saved[d.name] = self.district_overrides[d.index]
        end
    end

    self.districts = {}
    self.district_overrides = {}
    if not self.lab_zone_grid then return end
    local seen = {}
    for _, row in ipairs(self.lab_zone_grid) do
        for _, zone in ipairs(row) do
            if zone and not seen[zone] then
                seen[zone] = true
                local idx = #self.districts + 1
                table.insert(self.districts, { name = zone, index = idx })
                -- Restore previous override values if this district existed before
                self.district_overrides[idx] = saved[zone] or { road_density = 20, block_size = 5 }
            end
        end
    end
end

-- ── Region lookup (for click-to-modal) ───────────────────────────────────────

function SandboxController:_buildRegionLookup()
    self.region_cell_lookup = {}
    for _, region in ipairs(self.flood_fill_regions) do
        for _, cell in ipairs(region.cells) do
            if not self.region_cell_lookup[cell.y] then
                self.region_cell_lookup[cell.y] = {}
            end
            self.region_cell_lookup[cell.y][cell.x] = region.id
        end
    end
end

function SandboxController:_buildDowntownRegion()
    self.downtown_region = nil
    if not self.lab_grid then return end
    local city_w = math.max(32, math.floor(self.params.city_w))
    local city_h = math.max(32, math.floor(self.params.city_h))
    local dt_w   = math.max(8,  math.floor(self.params.downtown_w))
    local dt_h   = math.max(8,  math.floor(self.params.downtown_h))
    local x1 = math.floor((city_w - dt_w) / 2) + 1
    local y1 = math.floor((city_h - dt_h) / 2) + 1
    local x2 = x1 + dt_w - 1
    local y2 = y1 + dt_h - 1
    local cells = {}
    for cy = y1, y2 do
        for cx = x1, x2 do
            if self.lab_grid[cy] and self.lab_grid[cy][cx]
               and self.lab_grid[cy][cx].type ~= "arterial" then
                table.insert(cells, { x = cx, y = cy })
            end
        end
    end
    -- id = "downtown" (string keeps it separate from numeric flood-fill ids)
    self.downtown_region = {
        id = "downtown", zone = "downtown",
        cells = cells,
        min_x = x1, max_x = x2, min_y = y1, max_y = y2,
    }
end

function SandboxController:_defaultRegionParams()
    local p = self.params
    return {
        street_algo     = math.floor(p.street_algo or 1),
        min_block_size  = math.max(4, math.floor(p.min_block_size > 0 and p.min_block_size or 8)),
        max_block_size  = math.max(8, math.floor(p.max_block_size > 0 and p.max_block_size or 16)),
        block_size      = math.max(6, math.floor(p.warp_scale > 0 and p.warp_scale or 18)),
        warp_strength   = math.floor(p.warp_strength or 4),
        num_spokes      = math.floor(p.num_spokes or 8),
        num_rings       = math.floor(p.num_rings or 4),
        max_road_length = math.floor(p.max_road_length or 30),
        branch_chance   = p.branch_chance or 0.06,
        num_seeds       = math.floor(p.num_seeds or 40),
    }
end

function SandboxController:openZoneModal(region, screen_x, screen_y)
    local rid = region.id
    if not self.region_overrides[rid] then
        if region.zone == "downtown" then
            -- Dense grid defaults for downtown
            local p = self.params
            self.region_overrides[rid] = {
                street_algo     = 1,
                min_block_size  = 2,
                max_block_size  = 5,
                block_size      = 8,
                warp_strength   = 2,
                num_spokes      = math.floor(p.num_spokes or 8),
                num_rings       = math.floor(p.num_rings or 4),
                max_road_length = 15,
                branch_chance   = 0.12,
                num_seeds       = math.floor(p.num_seeds or 40),
            }
        else
            self.region_overrides[rid] = self:_defaultRegionParams()
        end
    end
    local ZoneModal = require("views.sandbox.ZoneModal")
    self.zone_modal = ZoneModal:new(
        region,
        self.region_overrides[rid],
        self.game,
        function() self:regenerate_region(region) end,
        function() self.zone_modal = nil end
    )
    self.zone_modal:positionNear(screen_x, screen_y)
end

function SandboxController:regenerate_region(region)
    if not self.lab_grid or not self.lab_zone_grid then return end
    if not region then return end

    local region_id = region.id
    local rp = self.region_overrides[region_id]
    if not rp then return end

    -- Build per-cell mask
    local cell_mask = {}
    for _, cell in ipairs(region.cells) do
        if not cell_mask[cell.y] then cell_mask[cell.y] = {} end
        cell_mask[cell.y][cell.x] = true
    end

    -- Reset region cells to grass (skip arterials)
    for _, cell in ipairs(region.cells) do
        if self.lab_grid[cell.y][cell.x].type ~= "arterial" then
            self.lab_grid[cell.y][cell.x] = { type = "grass" }
        end
    end

    -- Temp-override constants so services read correct dimensions
    local C        = self.game.C
    local city_w   = math.max(32, math.floor(self.params.city_w))
    local city_h   = math.max(32, math.floor(self.params.city_h))
    local dt_w     = math.max(8,  math.floor(self.params.downtown_w))
    local dt_h     = math.max(8,  math.floor(self.params.downtown_h))
    local saved_MAP = {}
    for k, v in pairs(C.MAP) do if type(v) ~= "table" then saved_MAP[k] = v end end
    C.MAP.CITY_GRID_WIDTH      = city_w
    C.MAP.CITY_GRID_HEIGHT     = city_h
    C.MAP.DOWNTOWN_GRID_WIDTH  = dt_w
    C.MAP.DOWNTOWN_GRID_HEIGHT = dt_h

    local gen_params = {
        cell_mask       = cell_mask,
        street_algo     = math.floor(rp.street_algo),
        min_block_size  = rp.min_block_size,
        max_block_size  = rp.max_block_size,
        block_size      = rp.block_size,
        warp_strength   = rp.warp_strength,
        warp_scale      = rp.block_size,   -- OrganicStreetService reads warp_scale
        num_spokes      = rp.num_spokes,
        num_rings       = rp.num_rings,
        max_road_length = rp.max_road_length,
        branch_chance   = rp.branch_chance,
        turn_chance     = 0.04,
        num_seeds       = rp.num_seeds,
        arterial_thickness = math.max(1, math.floor(self.params.arterial_thickness)),
    }

    local ok, err = pcall(function()
        local algo = gen_params.street_algo
        if algo == 2 then
            require("services.streets.OrganicStreetService").generateStreets(
                self.lab_grid, self.lab_zone_grid, self.arterial_paths, gen_params)
        elseif algo == 3 then
            require("services.streets.RadialStreetService").generateStreets(
                self.lab_grid, self.lab_zone_grid, self.arterial_paths, gen_params)
        elseif algo == 4 then
            require("services.streets.GrowthStreetService").generateStreets(
                self.lab_grid, self.lab_zone_grid, self.arterial_paths, gen_params)
        else
            -- Algo 1: subdivide only THIS region's bounding box.
            -- Calling generateStreets() would re-process the entire map and replace
            -- Game.street_segments with whole-map data — we want zone-local only.
            local BSS = require("services.BlockSubdivisionService")
            local zone_p = BSS._getBlockSizeForZone(region.zone or "residential_north", city_w, city_h)
            local min_s = (rp.min_block_size and rp.min_block_size > 0) and rp.min_block_size or zone_p.min_size
            local max_s = (rp.max_block_size and rp.max_block_size > 0) and rp.max_block_size or zone_p.max_size
            local segs = {}
            BSS._splitBlocksCollectSegments(
                { x1 = region.min_x, y1 = region.min_y, x2 = region.max_x, y2 = region.max_y },
                min_s, max_s, 0, segs)
            BSS._drawStreetsToGrid(self.lab_grid, segs, city_w, city_h, cell_mask)
        end
    end)

    for k, v in pairs(saved_MAP) do C.MAP[k] = v end

    if not ok then
        print("Region regen failed: " .. tostring(err))
        self.status_text = "Region regen failed"
        return
    end

    -- Re-fill remaining grass cells in region with plots
    local dt_x1 = math.floor((city_w - dt_w) / 2) + 1
    local dt_y1 = math.floor((city_h - dt_h) / 2) + 1
    local dt_x2 = dt_x1 + dt_w - 1
    local dt_y2 = dt_y1 + dt_h - 1
    for _, cell in ipairs(region.cells) do
        local cx, cy = cell.x, cell.y
        if self.lab_grid[cy][cx].type == "grass" then
            local in_dt = cx >= dt_x1 and cx <= dt_x2 and cy >= dt_y1 and cy <= dt_y2
            self.lab_grid[cy][cx] = { type = in_dt and "downtown_plot" or "plot" }
        end
    end

    -- Sync sandbox_map building plots (grid is same reference, no need to reassign)
    if self.sandbox_map then
        self.sandbox_map.building_plots = self.sandbox_map:getPlotsFromGrid(self.lab_grid)
    end

    -- Switch to tiles view so the result is immediately visible
    -- (flood_fill view colours entire regions uniformly, hiding tile-level changes)
    self:setViewMode("tiles")

    self.status_text = string.format("Region %s regenerated (algo %d)", tostring(region_id), gen_params.street_algo)
end

function SandboxController:drawModal()
    if self.zone_modal then self.zone_modal:draw() end
end

-- ── Send to main game ─────────────────────────────────────────────────────────

function SandboxController:sendToMainGame()
    if not self.sandbox_map then return end
    local game = self.game
    local C    = game.C
    local p    = self.params

    C.MAP.CITY_GRID_WIDTH      = math.max(32, math.floor(p.city_w))
    C.MAP.CITY_GRID_HEIGHT     = math.max(32, math.floor(p.city_h))
    C.MAP.DOWNTOWN_GRID_WIDTH  = math.max(8,  math.floor(p.downtown_w))
    C.MAP.DOWNTOWN_GRID_HEIGHT = math.max(8,  math.floor(p.downtown_h))

    self.sandbox_map.C = C
    game.maps.city = self.sandbox_map
    game.active_map_key = "city"

    -- Clear any WFC lab grid so GameView draws the city map, not the debug overlay
    game.lab_grid       = nil
    game.wfc_final_grid = nil
    game.lab_zone_grid  = nil

    local States = require("models.vehicles.vehicle_states")
    local new_depot = game.maps.city:getRandomDowntownBuildingPlot()
    game.entities.depot_plot = new_depot

    for _, v in ipairs(game.entities.vehicles) do
        v.cargo = {}; v.trip_queue = {}; v.path = {}
        if new_depot then
            v.depot_plot  = new_depot
            v.grid_anchor = { x = new_depot.x, y = new_depot.y }
            if v.recalculatePixelPosition then v:recalculatePixelPosition(game) end
        end
        if States and States.Idle then v:changeState(States.Idle, game) end
    end

    game.entities.trips.pending = {}

    -- Respawn all clients at valid positions in the new downtown
    local num_clients = math.max(1, #game.entities.clients)
    game.entities.clients = {}
    for _ = 1, num_clients do
        game.entities:addClient(game)
    end

    -- generateRegion() overwrites Game.maps.city.grid with a freshly generated city.
    -- Save the sandbox data first, then restore it after the region is rebuilt.
    local saved_grid   = self.sandbox_map.grid
    local saved_plots  = self.sandbox_map.building_plots
    local saved_offset = self.sandbox_map.downtown_offset

    game.error_service.withErrorHandling(function()
        game.maps.region:generateRegion()
    end, "Sandbox: Region Regen")

    -- Restore the sandbox map (generateRegion overwrites Game.maps.city)
    game.maps.city = self.sandbox_map
    game.active_map_key = "city"
    game.maps.city.grid            = saved_grid
    game.maps.city.building_plots  = saved_plots
    game.maps.city.downtown_offset = saved_offset
    game.entities.depot_plot       = new_depot

    local ok, err = pcall(function() game.maps.city:setScale(C.MAP.SCALES.DOWNTOWN) end)
    if not ok then print("SandboxController: setScale failed: " .. tostring(err)) end
    self:close()
end

-- ── Camera ────────────────────────────────────────────────────────────────────

function SandboxController:_centerCameraOnMap()
    local city_w = math.max(32, math.floor(self.params.city_w))
    local city_h = math.max(32, math.floor(self.params.city_h))
    local ts = self.game.C.MAP.TILE_SIZE

    self.camera.x = city_w * ts / 2
    self.camera.y = city_h * ts / 2

    local sw, sh = love.graphics.getDimensions()
    local vw = sw - self.game.C.UI.SIDEBAR_WIDTH
    local scale = math.min(vw / (city_w * ts), sh / (city_h * ts)) * 0.95
    self.camera.scale = math.max(0.05, math.min(50, scale))
end

-- ── Rendering (called from SandboxView) ──────────────────────────────────────

function SandboxController:drawMap(offset_x, offset_y, vw, vh)
    local mode = self.view_mode
    local ts   = self.game.C.MAP.TILE_SIZE

    -- ── Standard game tile view ───────────────────────────────────────────────
    if mode == "standard" then
        if self.sandbox_map and self.sandbox_map.grid and #self.sandbox_map.grid > 0 then
            self.sandbox_map:draw()
        end
        return
    end

    -- ── Flood fill regions view ───────────────────────────────────────────────
    if mode == "flood_fill" then
        local region_colors = {
            {1.0, 0.2, 0.2}, {0.2, 1.0, 0.2}, {0.2, 0.2, 1.0},
            {1.0, 1.0, 0.2}, {1.0, 0.2, 1.0}, {0.2, 1.0, 1.0},
            {1.0, 0.5, 0.2}, {0.5, 0.2, 1.0}, {0.2, 0.5, 0.2},
            {0.5, 0.5, 0.2}, {0.2, 0.5, 0.5}, {0.5, 0.2, 0.5},
        }
        for idx, region in ipairs(self.flood_fill_regions) do
            local c = region_colors[((idx - 1) % #region_colors) + 1]
            love.graphics.setColor(c[1], c[2], c[3], 0.6)
            for _, cell in ipairs(region.cells) do
                love.graphics.rectangle("fill", (cell.x-1)*ts, (cell.y-1)*ts, ts, ts)
            end
            love.graphics.setColor(c[1], c[2], c[3], 1.0)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line",
                (region.min_x-1)*ts, (region.min_y-1)*ts,
                (region.max_x - region.min_x + 1)*ts,
                (region.max_y - region.min_y + 1)*ts)
        end
        love.graphics.setLineWidth(1)
        love.graphics.setColor(1,1,1)
        return
    end

    -- ── Tile grid view — full composite (same as lab default after 1/2/3/u) ────
    if mode == "tiles" then
        local aw = math.max(1, ts * (self.params.arterial_width or 0.8) * math.max(1, math.floor(self.params.arterial_thickness or 1)))
        -- Zone background
        if self.lab_zone_grid then
            local zg = self.lab_zone_grid
            for y = 1, #zg do
                for x = 1, #zg[y] do
                    local zone = zg[y][x]
                    if zone then
                        local col = SandboxController._zoneColor(zone)
                        love.graphics.setColor(col[1], col[2], col[3], 0.6)
                        love.graphics.rectangle("fill", (x-1)*ts, (y-1)*ts, ts, ts)
                    end
                end
            end
        end
        -- Tile types from city_grid
        if self.lab_grid then
            for y = 1, #self.lab_grid do
                local row = self.lab_grid[y]
                if row then
                    for x = 1, #row do
                        local tile = row[x]
                        if tile then
                            if tile.type == "arterial" then
                                love.graphics.setColor(0.1, 0.1, 0.1, 1.0)
                                love.graphics.rectangle("fill", (x-1)*ts, (y-1)*ts, ts, ts)
                            elseif tile.type == "road" or tile.type == "downtown_road" then
                                love.graphics.setColor(0.25, 0.25, 0.25, 1.0)
                                love.graphics.rectangle("fill", (x-1)*ts, (y-1)*ts, ts, ts)
                            elseif tile.type == "plot" or tile.type == "downtown_plot" then
                                love.graphics.setColor(0.6, 0.6, 0.6, 0.2)
                                love.graphics.rectangle("line", (x-1)*ts, (y-1)*ts, ts, ts)
                            end
                        end
                    end
                end
            end
        end
        -- Street segments
        if self.street_segments and #self.street_segments > 0 then
            love.graphics.setColor(0.35, 0.35, 0.35, 1.0)
            love.graphics.setLineWidth(math.max(1, ts * 0.15))
            for _, seg in ipairs(self.street_segments) do
                if seg.type == "horizontal" then
                    love.graphics.line((seg.x1-1)*ts, (seg.y-0.5)*ts, seg.x2*ts, (seg.y-0.5)*ts)
                elseif seg.type == "vertical" then
                    love.graphics.line((seg.x-0.5)*ts, (seg.y1-1)*ts, (seg.x-0.5)*ts, seg.y2*ts)
                end
            end
            love.graphics.setLineWidth(1)
        end
        -- Arterial control paths (thick dark lines)
        if self.arterial_paths and #self.arterial_paths > 0 then
            love.graphics.setLineWidth(math.max(2, aw))
            love.graphics.setColor(0.1, 0.1, 0.1, 0.8)
            for _, path in ipairs(self.arterial_paths) do
                if #path > 1 then
                    for i = 1, #path - 1 do
                        local n1, n2 = path[i], path[i+1]
                        love.graphics.line(
                            (n1.x-0.5)*ts, (n1.y-0.5)*ts,
                            (n2.x-0.5)*ts, (n2.y-0.5)*ts)
                    end
                end
            end
            love.graphics.setLineWidth(1)
        end
        -- Smooth highway overlays (pink curves)
        if self.smooth_paths and #self.smooth_paths > 0 then
            love.graphics.setLineWidth(math.max(2, ts / 4))
            love.graphics.setColor(1, 0.5, 0.7, 0.8)
            for _, path in ipairs(self.smooth_paths) do
                if #path > 1 then
                    local pts = {}
                    for _, node in ipairs(path) do
                        pts[#pts+1] = (node.x-1)*ts + ts/2
                        pts[#pts+1] = (node.y-1)*ts + ts/2
                    end
                    love.graphics.line(pts)
                end
            end
            love.graphics.setLineWidth(1)
        end
        love.graphics.setColor(1,1,1)
        return
    end

    -- ── Zone background (zones / arterials / streets modes) ──────────────────
    if self.lab_zone_grid then
        local zg = self.lab_zone_grid
        for y = 1, #zg do
            for x = 1, #zg[y] do
                local zone = zg[y][x]
                if zone then
                    local col = SandboxController._zoneColor(zone)
                    love.graphics.setColor(col[1], col[2], col[3], 0.7)
                    love.graphics.rectangle("fill", (x-1)*ts, (y-1)*ts, ts, ts)
                end
            end
        end
    end

    if mode == "zones" then
        love.graphics.setColor(1,1,1); return
    end

    -- ── Arterials as thick lines ──────────────────────────────────────────────
    local aw = math.max(2, ts * (self.params.arterial_width or 0.8) * math.max(1, math.floor(self.params.arterial_thickness or 1)))
    if self.arterial_paths and #self.arterial_paths > 0 then
        love.graphics.setLineWidth(aw)
        love.graphics.setColor(0.15, 0.15, 0.15, 1.0)
        for _, path in ipairs(self.arterial_paths) do
            if #path > 1 then
                for i = 1, #path - 1 do
                    local n1, n2 = path[i], path[i+1]
                    love.graphics.line(
                        (n1.x - 0.5) * ts, (n1.y - 0.5) * ts,
                        (n2.x - 0.5) * ts, (n2.y - 0.5) * ts)
                end
            end
        end
        love.graphics.setLineWidth(1)
    end

    -- Smooth highway overlays (arterials mode only)
    if mode == "arterials" and self.smooth_paths and #self.smooth_paths > 0 then
        love.graphics.setLineWidth(math.max(2, ts / 4))
        love.graphics.setColor(1, 0.5, 0.7, 0.8)
        for _, path in ipairs(self.smooth_paths) do
            if #path > 1 then
                local pts = {}
                for _, node in ipairs(path) do
                    pts[#pts+1] = (node.x - 1) * ts + ts/2
                    pts[#pts+1] = (node.y - 1) * ts + ts/2
                end
                love.graphics.line(pts)
            end
        end
        love.graphics.setLineWidth(1)
    end

    if mode == "arterials" then
        love.graphics.setColor(1,1,1); return
    end

    -- ── Street segments ───────────────────────────────────────────────────────
    if self.street_segments and #self.street_segments > 0 then
        love.graphics.setColor(0.3, 0.3, 0.3, 1.0)
        love.graphics.setLineWidth(math.max(1, ts * 0.5))
        for _, seg in ipairs(self.street_segments) do
            if seg.type == "horizontal" then
                love.graphics.line((seg.x1-1)*ts, (seg.y-0.5)*ts, seg.x2*ts, (seg.y-0.5)*ts)
            elseif seg.type == "vertical" then
                love.graphics.line((seg.x-0.5)*ts, (seg.y1-1)*ts, (seg.x-0.5)*ts, seg.y2*ts)
            end
        end
        love.graphics.setLineWidth(1)
    end

    love.graphics.setColor(1,1,1)
end

-- ── Update ────────────────────────────────────────────────────────────────────

function SandboxController:update(dt)
    if not self.active then return end
    if self.sidebar_manager then self.sidebar_manager:update(dt) end
end

-- ── Input ─────────────────────────────────────────────────────────────────────

function SandboxController:handle_mouse_down(x, y, button)
    -- Modal takes full priority while open
    if self.zone_modal then
        self.zone_modal:handle_mouse_down(x, y, button)
        return
    end

    local sidebar_w = self.game.C.UI.SIDEBAR_WIDTH
    if x < sidebar_w then
        if self.sidebar_manager then self.sidebar_manager:handle_mouse_down(x, y, button) end
    elseif button == 2 then
        self.camera_dragging = true
        self.camera_drag_start_x = x
        self.camera_drag_start_y = y
    elseif button == 1 and #self.flood_fill_regions > 0 then
        -- Convert screen → world → grid to find the clicked flood-fill region
        local C        = self.game.C
        local ts       = C.MAP.TILE_SIZE
        local sw, sh   = love.graphics.getDimensions()
        local vw       = sw - sidebar_w
        local wx = (x - sidebar_w - vw / 2) / self.camera.scale + self.camera.x
        local wy = (y - sh / 2)             / self.camera.scale + self.camera.y
        local gx = math.floor(wx / ts) + 1
        local gy = math.floor(wy / ts) + 1
        -- Check downtown first (excluded from flood-fill regions)
        local dr = self.downtown_region
        if dr and gx >= dr.min_x and gx <= dr.max_x and gy >= dr.min_y and gy <= dr.max_y then
            self:openZoneModal(dr, x, y)
        else
            local rid = self.region_cell_lookup[gy] and self.region_cell_lookup[gy][gx]
            if rid then
                for _, region in ipairs(self.flood_fill_regions) do
                    if region.id == rid then
                        self:openZoneModal(region, x, y)
                        break
                    end
                end
            end
        end
    end
end

function SandboxController:handle_mouse_up(x, y, button)
    if self.zone_modal then self.zone_modal:handle_mouse_up(x, y, button) end
    if button == 2 then self.camera_dragging = false end
    if self.sidebar_manager then self.sidebar_manager:handle_mouse_up(x, y, button) end
end

function SandboxController:handle_mouse_moved(x, y, dx, dy)
    -- Route to modal slider drags first (prevents camera pan fighting slider)
    if self.zone_modal then
        self.zone_modal:handle_mouse_moved(x, y, dx, dy)
        if self.zone_modal:is_dragging_slider() then return end
    end
    if self.camera_dragging and self.camera.scale > 0 then
        self.camera.x = self.camera.x - dx / self.camera.scale
        self.camera.y = self.camera.y - dy / self.camera.scale
    end
    if self.sidebar_manager then self.sidebar_manager:handle_mouse_moved(x, y, dx, dy) end
end

function SandboxController:handle_mouse_wheel(x, y)
    local sidebar_w = self.game.C.UI.SIDEBAR_WIDTH
    local mx, my = love.mouse.getPosition()
    if mx < sidebar_w then
        if self.sidebar_manager then self.sidebar_manager:handle_scroll(mx, my, y) end
    else
        local factor = y > 0 and 1.15 or (1/1.15)
        self.camera.scale = math.max(0.05, math.min(50, self.camera.scale * factor))
    end
end

function SandboxController:handle_keypressed(key)
    if key == "escape" then self:close(); return true end
    if self.sidebar_manager then return self.sidebar_manager:handle_keypressed(key) end
    return false
end

function SandboxController:handle_textinput(text)
    if self.sidebar_manager then return self.sidebar_manager:handle_textinput(text) end
    return false
end

return SandboxController
