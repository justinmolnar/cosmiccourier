-- views/WorldSandboxSidebarManager.lua
-- Accordion sidebar for the F8 world gen sandbox.

local Accordion = require("views.components.Accordion")
local Slider    = require("views.components.Slider")

local WorldSandboxSidebarManager = {}
WorldSandboxSidebarManager.__index = WorldSandboxSidebarManager

-- ── Constructor ───────────────────────────────────────────────────────────────

function WorldSandboxSidebarManager:new(wsc, game)
    local inst = setmetatable({}, WorldSandboxSidebarManager)
    inst.wsc  = wsc
    inst.game = game

    -- Accordions
    inst.world_acc        = Accordion:new("World",              true,  172)
    inst.continental_acc  = Accordion:new("Continental",        true,  110)
    inst.terrain_acc      = Accordion:new("Terrain",            true,  175)
    inst.detail_acc       = Accordion:new("Mountains & Detail", false, 276)
    inst.biomes_acc       = Accordion:new("Biome Heights",      false, 240)
    inst.suitability_acc  = Accordion:new("Suitability",        false, 240)
    inst.regions_acc      = Accordion:new("Regions",            false, 150)
    inst.highways_acc     = Accordion:new("Highways",           false, 120)
    inst.citygen_acc      = Accordion:new("City Gen",           false, 110)
    inst.actions_acc      = Accordion:new("Actions",            true,  340)

    inst.accordions = {
        inst.world_acc, inst.continental_acc, inst.terrain_acc,
        inst.detail_acc, inst.biomes_acc, inst.suitability_acc,
        inst.regions_acc, inst.highways_acc, inst.citygen_acc, inst.actions_acc,
    }

    local p = wsc.params

    -- World sliders
    inst.world_sliders = {
        Slider:new("Width",      100, 1400, p.world_w,    true,  function(v) wsc.params.world_w    = v end, game),
        Slider:new("Height",      50, 1000, p.world_h,    true,  function(v) wsc.params.world_h    = v end, game),
        Slider:new("Seed X",       0, 9999, p.seed_x,     true,  function(v) wsc.params.seed_x     = v end, game),
        Slider:new("Seed Y",       0, 9999, p.seed_y,     true,  function(v) wsc.params.seed_y     = v end, game),
        Slider:new("Edge Margin", 0, 0.40,  p.edge_margin,false, function(v) wsc.params.edge_margin = v end, game),
    }
    inst.seed_x_slider = inst.world_sliders[3]
    inst.seed_y_slider = inst.world_sliders[4]

    -- Continental sliders
    inst.continental_sliders = {
        Slider:new("Scale",    0.001, 0.020, p.continental_scale,   false, function(v) wsc.params.continental_scale   = v end, game),
        Slider:new("Octaves",  1,     6,     p.continental_octaves, true,  function(v) wsc.params.continental_octaves = v end, game),
        Slider:new("Weight",   0,     1,     p.continental_weight,  false, function(v) wsc.params.continental_weight  = v end, game),
    }

    -- Terrain sliders
    inst.terrain_sliders = {
        Slider:new("Scale",      0.002, 0.050, p.terrain_scale,   false, function(v) wsc.params.terrain_scale   = v end, game),
        Slider:new("Octaves",    1,     8,     p.terrain_octaves, true,  function(v) wsc.params.terrain_octaves = v end, game),
        Slider:new("Weight",     0,     1,     p.terrain_weight,  false, function(v) wsc.params.terrain_weight  = v end, game),
        Slider:new("Persistence",0.1,   0.9,   p.persistence,     false, function(v) wsc.params.persistence    = v end, game),
        Slider:new("Lacunarity", 1.0,   4.0,   p.lacunarity,      false, function(v) wsc.params.lacunarity     = v end, game),
    }

    -- Detail, Mountain & Moisture sliders
    inst.detail_sliders = {
        Slider:new("Mtn Scale",     0.005, 0.060, p.mountain_scale,    false, function(v) wsc.params.mountain_scale    = v end, game),
        Slider:new("Mtn Octaves",   1,     5,     p.mountain_octaves,  true,  function(v) wsc.params.mountain_octaves  = v end, game),
        Slider:new("Mtn Strength",  0,     0.8,   p.mountain_strength, false, function(v) wsc.params.mountain_strength = v end, game),
        Slider:new("Detail Scale",  0.01,  0.20,  p.detail_scale,      false, function(v) wsc.params.detail_scale      = v end, game),
        Slider:new("Detail Weight", 0,     0.5,   p.detail_weight,     false, function(v) wsc.params.detail_weight     = v end, game),
        Slider:new("Moisture Scale",0.002, 0.030, p.moisture_scale,    false, function(v) wsc.params.moisture_scale    = v end, game),
        Slider:new("Moisture Oct",  1,     4,     p.moisture_octaves,  true,  function(v) wsc.params.moisture_octaves  = v end, game),
        Slider:new("Rivers",        0,     300,   p.river_count,        true,  function(v) wsc.params.river_count       = v end, game),
        Slider:new("Meander",       0,     0.15,  p.meander_strength,   false, function(v) wsc.params.meander_strength  = v end, game),
        Slider:new("Lake Size",     0,     0.05,  p.lake_delta,         false, function(v) wsc.params.lake_delta        = v end, game),
        Slider:new("River Influence", 0,  100,   p.river_influence,    true,  function(v) wsc.params.river_influence   = v end, game),
        Slider:new("Latitude Str.",  0,  1,     p.latitude_strength,  false, function(v) wsc.params.latitude_strength = v end, game),
    }

    -- Biome threshold sliders (enforce ascending order in on_change).
    -- coast_max is "sea level" — drag it to control how much of the map is ocean.
    local function make_biome_slider(label, key, neighbor_above_key)
        return Slider:new(label, 0.0, 1.0, p[key], false, function(v)
            if neighbor_above_key then
                v = math.min(v, wsc.params[neighbor_above_key] - 0.01)
            end
            wsc.params[key] = math.max(0, v)
        end, game)
    end
    inst.biome_sliders = {
        make_biome_slider("Deep Ocean",  "deep_ocean_max", "ocean_max"),
        make_biome_slider("Ocean",       "ocean_max",      "coast_max"),
        make_biome_slider("Coast",       "coast_max",      "plains_max"),
        make_biome_slider("Plains",      "plains_max",     "forest_max"),
        make_biome_slider("Forest",      "forest_max",     "highland_max"),
        make_biome_slider("Highland",    "highland_max",   "mountain_max"),
        make_biome_slider("Mountain",    "mountain_max",   nil),
    }

    -- Suitability sliders
    inst.suitability_sliders = {
        Slider:new("Coast Radius",   0,   200,  p.suit_coast_radius,   true,  function(v) wsc.params.suit_coast_radius   = v end, game),
        Slider:new("River Radius",   0,   80,   p.suit_river_radius,   true,  function(v) wsc.params.suit_river_radius   = v end, game),
        Slider:new("Elev. Weight",   0,   1,    p.suit_elev_weight,    false, function(v) wsc.params.suit_elev_weight    = v end, game),
        Slider:new("Coast Weight",   0,   1,    p.suit_coast_weight,   false, function(v) wsc.params.suit_coast_weight   = v end, game),
        Slider:new("River Weight",   0,   1,    p.suit_river_weight,   false, function(v) wsc.params.suit_river_weight   = v end, game),
        Slider:new("Climate Weight", 0,   1,    p.suit_climate_weight, false, function(v) wsc.params.suit_climate_weight = v end, game),
        Slider:new("Island Thresh.", 0,   0.15, p.island_threshold,    false, function(v) wsc.params.island_threshold    = v end, game),
        Slider:new("City Count",     1,   50,   p.city_count,          true,  function(v) wsc.params.city_count          = v end, game),
        Slider:new("City Spacing",   5,   100,  p.city_min_sep,        true,  function(v) wsc.params.city_min_sep        = v end, game),
    }

    -- City Gen sliders
    inst.citygen_sliders = {
        Slider:new("City Size",    0.01, 0.50, p.city_size_fraction, false, function(v) wsc.params.city_size_fraction = v end, game),
        Slider:new("POI Count",    2,    20,   p.city_poi_count,   true,  function(v) wsc.params.city_poi_count   = v end, game),
        Slider:new("POI Spread",   0.3,  3.0,  p.city_poi_spacing, false, function(v) wsc.params.city_poi_spacing = v end, game),
        Slider:new("Downtown %",   0.05, 0.30, p.downtown_pct,       false, function(v) wsc.params.downtown_pct       = v end, game),
        Slider:new("DT Min Cells", 1,    50,   p.downtown_min_cells, true,  function(v) wsc.params.downtown_min_cells = v end, game),
    }

    -- Highway sliders
    inst.highway_sliders = {
        Slider:new("Mtn Cost",    1,  30,  p.highway_mountain_cost, false, function(v) wsc.params.highway_mountain_cost = v end, game),
        Slider:new("River Cross", 0,  15,  p.highway_river_cost,    false, function(v) wsc.params.highway_river_cost    = v end, game),
        Slider:new("Slope Cost",  0,  40,  p.highway_slope_cost,    false, function(v) wsc.params.highway_slope_cost    = v end, game),
        Slider:new("City Budget", 100, 3000, p.highway_budget_scale,  true,  function(v) wsc.params.highway_budget_scale  = v end, game),
    }

    -- Region sliders
    inst.region_sliders = {
        Slider:new("Region Count",  1,  80,   p.region_count,         true,  function(v) wsc.params.region_count         = v end, game),
        Slider:new("Mtn Barrier",   0,  20,   p.region_mountain_cost, false, function(v) wsc.params.region_mountain_cost = v end, game),
        Slider:new("River Barrier", 0,  20,   p.region_river_cost,    false, function(v) wsc.params.region_river_cost    = v end, game),
        Slider:new("Seed Spacing",  5,  80,   p.region_min_sep,       true,  function(v) wsc.params.region_min_sep       = v end, game),
    }

    -- Panel widget lists aligned with accordions (index 10 = actions, handled directly)
    inst.panel_widgets = {
        inst.world_sliders,
        inst.continental_sliders,
        inst.terrain_sliders,
        inst.detail_sliders,
        inst.biome_sliders,
        inst.suitability_sliders,
        inst.region_sliders,
        inst.highway_sliders,
        inst.citygen_sliders,
        {},
    }

    -- Action button rects (set in _doLayout)
    inst.btn_randomize    = { x = 0, y = 0, w = 0, h = 34 }
    inst.btn_generate     = { x = 0, y = 0, w = 0, h = 38 }
    inst.btn_view_height  = { x = 0, y = 0, w = 0, h = 32 }
    inst.btn_view_biome   = { x = 0, y = 0, w = 0, h = 32 }
    inst.btn_view_suit    = { x = 0, y = 0, w = 0, h = 32 }
    inst.btn_view_conts   = { x = 0, y = 0, w = 0, h = 32 }
    inst.btn_view_regions   = { x = 0, y = 0, w = 0, h = 32 }
    inst.btn_view_districts = { x = 0, y = 0, w = 0, h = 32 }
    inst.btn_scope_world    = { x = 0, y = 0, w = 0, h = 30 }
    inst.btn_scope_cont     = { x = 0, y = 0, w = 0, h = 30 }
    inst.btn_scope_region   = { x = 0, y = 0, w = 0, h = 30 }
    inst.btn_scope_city     = { x = 0, y = 0, w = 0, h = 30 }
    inst.btn_scope_downtown = { x = 0, y = 0, w = 0, h = 30 }
    inst.btn_place_cities   = { x = 0, y = 0, w = 0, h = 34 }
    inst.btn_build_highways = { x = 0, y = 0, w = 0, h = 34 }
    inst.btn_gen_city       = { x = 0, y = 0, w = 0, h = 34 }
    inst.btn_send_to_game   = { x = 0, y = 0, w = 0, h = 42 }

    return inst
end

-- ── Layout ────────────────────────────────────────────────────────────────────

function WorldSandboxSidebarManager:_doLayout()
    local C         = self.game.C
    local sidebar_w = C.UI.SIDEBAR_WIDTH
    local pad       = 10
    local ww        = sidebar_w - pad * 2
    local _, my     = love.mouse.getPosition()

    -- Update accordion content heights
    for i, acc in ipairs(self.accordions) do
        local panel = self.panel_widgets[i]
        local total_h = 4
        if i == 10 then
            -- Actions: randomize + generate + view grid (2-col ×2 + 2-col regions/districts) + scope row + place cities + build highways + gen city
            total_h = self.btn_randomize.h + self.btn_generate.h
                    + self.btn_view_height.h + self.btn_view_suit.h   -- two 2-col rows
                    + self.btn_view_regions.h                          -- regions|districts row
                    + self.btn_scope_world.h                           -- scope row
                    + self.btn_place_cities.h + self.btn_build_highways.h
                    + self.btn_gen_city.h + self.btn_send_to_game.h + 150
        else
            for _, w in ipairs(panel) do
                total_h = total_h + w.h
            end
        end
        acc:update(total_h, my)
    end

    -- Stack accordions vertically below title bar
    local cursor = 24
    for _, acc in ipairs(self.accordions) do
        acc.x = 0
        acc.y = cursor
        acc.w = sidebar_w
        cursor = cursor + acc.header_h
        if acc.is_open then
            cursor = cursor + acc.content_h
        end
    end

    -- Position widgets inside open accordions
    for i, acc in ipairs(self.accordions) do
        if i == 10 then break end
        local panel = self.panel_widgets[i]
        local wy    = acc.y + acc.header_h
        for _, w in ipairs(panel) do
            w.x = pad
            w.y = wy
            w.w = ww
            wy  = wy + w.h
        end
    end

    -- Actions accordion buttons
    local aa    = self.actions_acc
    local bx    = pad
    local btn_y = aa.y + aa.header_h + 6
    local half_w = math.floor((ww - 4) / 2)
    self.btn_randomize.x = bx
    self.btn_randomize.y = btn_y
    self.btn_randomize.w = ww
    self.btn_generate.x  = bx
    self.btn_generate.y  = btn_y + self.btn_randomize.h + 6
    self.btn_generate.w  = ww
    -- View buttons: 2×2 grid (Height|Biome / Suitability|Continents)
    local view_y1 = self.btn_generate.y + self.btn_generate.h + 10
    local view_y2 = view_y1 + self.btn_view_height.h + 4
    self.btn_view_height.x = bx;              self.btn_view_height.y = view_y1; self.btn_view_height.w = half_w
    self.btn_view_biome.x  = bx + half_w + 4; self.btn_view_biome.y  = view_y1; self.btn_view_biome.w  = half_w
    self.btn_view_suit.x   = bx;              self.btn_view_suit.y   = view_y2; self.btn_view_suit.w   = half_w
    self.btn_view_conts.x  = bx + half_w + 4; self.btn_view_conts.y  = view_y2; self.btn_view_conts.w  = half_w
    local view_y3 = view_y2 + self.btn_view_suit.h + 4
    self.btn_view_regions.x   = bx;              self.btn_view_regions.y   = view_y3; self.btn_view_regions.w   = half_w
    self.btn_view_districts.x = bx + half_w + 4; self.btn_view_districts.y = view_y3; self.btn_view_districts.w = half_w
    -- Scope buttons row 1: World | Continent | Region | City
    local scope_y = view_y3 + self.btn_view_regions.h + 8
    local qtr_w   = math.floor((ww - 12) / 4)
    self.btn_scope_world.x  = bx;                 self.btn_scope_world.y  = scope_y; self.btn_scope_world.w  = qtr_w
    self.btn_scope_cont.x   = bx + qtr_w + 4;    self.btn_scope_cont.y   = scope_y; self.btn_scope_cont.w   = qtr_w
    self.btn_scope_region.x = bx + 2*(qtr_w+4);  self.btn_scope_region.y = scope_y; self.btn_scope_region.w = qtr_w
    self.btn_scope_city.x   = bx + 3*(qtr_w+4);  self.btn_scope_city.y   = scope_y; self.btn_scope_city.w   = qtr_w
    -- Scope buttons row 2: Downtown (full width, sub-scope of city)
    local scope_y2 = scope_y + self.btn_scope_world.h + 4
    self.btn_scope_downtown.x = bx; self.btn_scope_downtown.y = scope_y2; self.btn_scope_downtown.w = ww
    local city_y = scope_y2 + self.btn_scope_downtown.h + 8
    self.btn_place_cities.x   = bx; self.btn_place_cities.y   = city_y;                               self.btn_place_cities.w   = ww
    self.btn_build_highways.x = bx; self.btn_build_highways.y = city_y + self.btn_place_cities.h + 4; self.btn_build_highways.w = ww
    self.btn_gen_city.x       = bx; self.btn_gen_city.y       = self.btn_build_highways.y + self.btn_build_highways.h + 8; self.btn_gen_city.w = ww
    self.btn_send_to_game.x   = bx; self.btn_send_to_game.y   = self.btn_gen_city.y + self.btn_gen_city.h + 12;            self.btn_send_to_game.w = ww
end

-- ── Draw ─────────────────────────────────────────────────────────────────────

local function point_in_rect(x, y, r)
    return x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h
end

local function draw_button(rect, label, active, game)
    local bg = active and { 0.20, 0.60, 0.20 } or { 0.15, 0.15, 0.20 }
    love.graphics.setColor(bg[1], bg[2], bg[3])
    love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 3, 3)
    love.graphics.setColor(0.50, 0.70, 0.50)
    love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h, 3, 3)
    love.graphics.setColor(1, 1, 1)
    love.graphics.setFont(game.fonts.ui_small)
    love.graphics.printf(label, rect.x, rect.y + (rect.h - 14) / 2, rect.w, "center")
end

function WorldSandboxSidebarManager:draw()
    local game      = self.game
    local C         = game.C
    local sidebar_w = C.UI.SIDEBAR_WIDTH
    local _, sh     = love.graphics.getDimensions()

    self:_doLayout()

    -- Background
    love.graphics.setColor(0.08, 0.08, 0.12)
    love.graphics.rectangle("fill", 0, 0, sidebar_w, sh)
    love.graphics.setColor(0.25, 0.25, 0.35)
    love.graphics.line(sidebar_w, 0, sidebar_w, sh)

    -- Title
    love.graphics.setFont(game.fonts.ui_small)
    love.graphics.setColor(0.6, 0.8, 1.0)
    love.graphics.printf("WORLD GEN SANDBOX", 0, 4, sidebar_w, "center")
    love.graphics.setColor(0.25, 0.25, 0.35)
    love.graphics.line(0, 20, sidebar_w, 20)

    -- Accordions
    for i, acc in ipairs(self.accordions) do
        acc:beginDraw()
        if acc.is_open then
            if i == 10 then
                draw_button(self.btn_randomize,      "Randomize Seed",  false, game)
                draw_button(self.btn_generate,       "Generate",        true,  game)
                draw_button(self.btn_view_height,    "Height",      self.wsc.view_mode == "height",      game)
                draw_button(self.btn_view_biome,     "Biome",       self.wsc.view_mode == "biome",       game)
                draw_button(self.btn_view_suit,      "Suitability", self.wsc.view_mode == "suitability", game)
                draw_button(self.btn_view_conts,     "Continents",  self.wsc.view_mode == "continents",  game)
                draw_button(self.btn_view_regions,    "Regions",     self.wsc.view_mode == "regions",     game)
                draw_button(self.btn_view_districts,  "Districts",   self.wsc.view_mode == "districts",   game)
                local sc = self.wsc.view_scope
                local sm = self.wsc.scope_mode
                draw_button(self.btn_scope_world,    "World",    sc == "world",                                          game)
                draw_button(self.btn_scope_cont,     "Cont",     sc == "continent" or sm == "picking_continent",         game)
                draw_button(self.btn_scope_region,   "Region",   sc == "region"    or sm == "picking_region",            game)
                draw_button(self.btn_scope_city,     "City",     sc == "city"      or sm == "picking_city",              game)
                draw_button(self.btn_scope_downtown, "Downtown", sc == "downtown",                                       game)
                local has_suit = self.wsc.suitability_scores ~= nil
                draw_button(self.btn_place_cities,   "Place Cities",   has_suit and self.wsc.city_locations ~= nil, game)
                draw_button(self.btn_build_highways, "Build Highways", self.wsc.highway_map ~= nil, game)
                draw_button(self.btn_gen_city, "Regen Bounds", self.wsc.city_bounds ~= nil, game)
                -- Send to Game: gold border when ready, greyed out otherwise
                local ready = self.wsc.city_bounds_list ~= nil
                love.graphics.setColor(ready and 0.55 or 0.15, ready and 0.42 or 0.15, ready and 0.08 or 0.15)
                love.graphics.rectangle("fill", self.btn_send_to_game.x, self.btn_send_to_game.y,
                    self.btn_send_to_game.w, self.btn_send_to_game.h, 4, 4)
                love.graphics.setColor(ready and 0.9 or 0.35, ready and 0.72 or 0.35, ready and 0.15 or 0.15)
                love.graphics.rectangle("line", self.btn_send_to_game.x, self.btn_send_to_game.y,
                    self.btn_send_to_game.w, self.btn_send_to_game.h, 4, 4)
                love.graphics.setColor(1, 1, 1)
                love.graphics.setFont(game.fonts.ui_small)
                love.graphics.printf("Send to Game", self.btn_send_to_game.x,
                    self.btn_send_to_game.y + (self.btn_send_to_game.h - 14) / 2,
                    self.btn_send_to_game.w, "center")
            else
                for _, w in ipairs(self.panel_widgets[i]) do
                    w:draw()
                end
            end
        end
        acc:endDraw()
        acc:drawScrollbar()
    end

    love.graphics.setColor(1, 1, 1)
end

-- ── Input ─────────────────────────────────────────────────────────────────────

function WorldSandboxSidebarManager:handle_mouse_down(x, y, button)
    -- 1. Accordion headers
    for _, acc in ipairs(self.accordions) do
        if acc:handle_click(x, y) then return true end
    end

    -- 2. Accordion scrollbars
    for _, acc in ipairs(self.accordions) do
        if acc.is_open and acc:handle_mouse_down(x, y, button) then return true end
    end

    -- 3. Actions buttons (accordion index 10)
    if self.actions_acc.is_open and button == 1 then
        local sy = y + self.actions_acc.scroll_y
        if point_in_rect(x, sy, self.btn_randomize) then
            local rx = love.math.random(0, 9999)
            local ry = love.math.random(0, 9999)
            self.wsc.params.seed_x = rx
            self.wsc.params.seed_y = ry
            self.seed_x_slider.value = rx
            self.seed_y_slider.value = ry
            return true
        end
        if point_in_rect(x, sy, self.btn_generate) then
            self.wsc:generate()
            return true
        end
        if point_in_rect(x, sy, self.btn_view_height) then
            self.wsc:set_view("height")
            return true
        end
        if point_in_rect(x, sy, self.btn_view_biome) then
            self.wsc:set_view("biome")
            return true
        end
        if point_in_rect(x, sy, self.btn_view_suit) then
            self.wsc:set_view("suitability")
            return true
        end
        if point_in_rect(x, sy, self.btn_view_conts) then
            self.wsc:set_view("continents")
            return true
        end
        if point_in_rect(x, sy, self.btn_view_regions) then
            self.wsc:set_view("regions")
            return true
        end
        if point_in_rect(x, sy, self.btn_view_districts) then
            self.wsc:set_view("districts")
            return true
        end
        if point_in_rect(x, sy, self.btn_place_cities) and self.wsc.suitability_scores then
            self.wsc:place_cities()
            return true
        end
        if point_in_rect(x, sy, self.btn_build_highways) and self.wsc.city_locations then
            self.wsc:build_highways()
            return true
        end
        if point_in_rect(x, sy, self.btn_gen_city) and self.wsc.city_locations then
            self.wsc:regen_bounds()
            return true
        end
        if point_in_rect(x, sy, self.btn_send_to_game) and self.wsc.city_bounds_list then
            self.wsc:sendToGame()
            return true
        end
        if point_in_rect(x, sy, self.btn_scope_world) then
            self.wsc:set_scope_world()
            return true
        end
        if point_in_rect(x, sy, self.btn_scope_cont) and self.wsc.continent_map then
            self.wsc:enter_scope_pick("picking_continent")
            return true
        end
        if point_in_rect(x, sy, self.btn_scope_region) and self.wsc.region_map then
            self.wsc:enter_scope_pick("picking_region")
            return true
        end
        if point_in_rect(x, sy, self.btn_scope_city) and self.wsc.city_bounds_list then
            self.wsc:enter_scope_pick("picking_city")
            return true
        end
        if point_in_rect(x, sy, self.btn_scope_downtown) and self.wsc.selected_city_idx then
            self.wsc:_selectDowntown()
            return true
        end
    end

    -- 4. Widgets in open accordions
    for i, acc in ipairs(self.accordions) do
        if i == 10 then break end
        if acc.is_open then
            local content_top    = acc.y + acc.header_h
            local content_bottom = content_top + acc.content_h
            if y >= content_top and y < content_bottom then
                local sy = y + acc.scroll_y
                for _, w in ipairs(self.panel_widgets[i]) do
                    if sy >= w.y and sy < w.y + w.h then
                        if w:handle_mouse_down(x, sy, button) then return true end
                    end
                end
            end
        end
    end

    return false
end

function WorldSandboxSidebarManager:handle_mouse_up(x, y, button)
    for _, acc in ipairs(self.accordions) do
        acc:handle_mouse_up(x, y, button)
    end
    for i = 1, 9 do
        for _, w in ipairs(self.panel_widgets[i]) do
            if w.handle_mouse_up then w:handle_mouse_up(x, y, button) end
        end
    end
end

function WorldSandboxSidebarManager:handle_mouse_moved(x, y, dx, dy)
    local _, my = love.mouse.getPosition()
    for i = 1, 9 do
        for _, w in ipairs(self.panel_widgets[i]) do
            if w.handle_mouse_moved then w:handle_mouse_moved(x, my, dx, dy) end
        end
    end
end

function WorldSandboxSidebarManager:handle_scroll(mx, my, dy)
    for _, acc in ipairs(self.accordions) do
        if acc:handle_scroll(mx, my, dy) then return true end
    end
    return false
end

return WorldSandboxSidebarManager
