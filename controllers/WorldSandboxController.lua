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

    inst.heightmap   = nil
    inst.colormap    = nil
    inst.world_image = nil
    inst.world_w     = 0
    inst.world_h     = 0
    inst.status_text = ""

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
        continental_weight  = 0.70,
        -- Terrain layer (smooth FBM — internal elevation variation within islands)
        terrain_scale   = 0.015,
        terrain_octaves = 3,
        terrain_weight  = 0.25,
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
        -- Edge margin: outer X% of map is forced to deep ocean (0 = disabled)
        edge_margin = 0.22,
        -- Biome thresholds on the normalized [0,1] height.
        -- coast_max is effectively "sea level" — raise it for more ocean, lower for more land.
        deep_ocean_max = 0.45,
        ocean_max      = 0.55,
        coast_max      = 0.60,
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
        self.heightmap = result.heightmap
        self.colormap  = result.colormap
        self.world_w   = w
        self.world_h   = h
        self:_buildImage()
        self:_centerCamera()
        self.status_text = string.format("Generated %dx%d  |  F8 close  |  RMB pan  |  Wheel zoom", w, h)
    else
        self.status_text = "FAILED: " .. tostring(result)
    end
end

function WorldSandboxController:_buildImage()
    local imgdata = love.image.newImageData(self.world_w, self.world_h)
    for y = 1, self.world_h do
        for x = 1, self.world_w do
            local c = self.colormap[y][x]
            imgdata:setPixel(x - 1, y - 1, c[1], c[2], c[3], 1.0)
        end
    end
    self.world_image = love.graphics.newImage(imgdata)
    self.world_image:setFilter("nearest", "nearest")
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
