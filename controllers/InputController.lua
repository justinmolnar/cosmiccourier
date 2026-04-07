-- controllers/InputController.lua

local InputController = {}
InputController.__index = InputController

function InputController:new(game)
    local instance = setmetatable({}, InputController)
    instance.game = game
    local UIController = require("controllers.UIController")
    instance.ui_controller = UIController:new(game)
    -- Drag-pan state
    instance._drag_active   = false
    instance._drag_panning  = false
    instance._drag_sx       = 0
    instance._drag_sy       = 0
    return instance
end

function InputController:keypressed(key)
    if key == "escape" then
        -- Close context menu first; only quit if nothing to close
        if self.game.ui_manager and self.game.ui_manager.context_menu then
            self.game.ui_manager:closeContextMenu()
            return
        end
        -- Cancel highway build mode
        if self.game.entities.build_highway_mode then
            self.game.entities.build_highway_mode = false
            self.game.entities.highway_build_nodes = {}
            self.game._hw_ghost_cache = nil
            return
        end
        -- Cancel depot build mode
        if self.game.entities.build_depot_mode then
            self.game.entities.build_depot_mode = false
            return
        end
        love.event.quit()
        return
    end

    -- F3: Minecraft-style debug overlay
    if key == "f3" then
        self.game.debug_f3 = not (self.game.debug_f3 or false)
        return
    end

    -- Debug mode toggle
    if key == "tab" then
        self.game.debug_mode = not self.game.debug_mode
        if self.game.error_service then
            self.game.error_service.logInfo("Input", "Debug mode set to: " .. tostring(self.game.debug_mode))
        end
        return
    end

    -- HUD strip intercepts its registered overlay keys first
    if self.game.hud_strip and self.game.hud_strip:handleKey(key, self.game) then
        return
    end

    -- Debug overlay toggles (dev tools — not routed through HUD strip)
    local DEBUG_TOGGLES = {
        h = { field = "debug_hide_vehicles",       label = "vehicle + payout text draw" },
        c = { field = "debug_dot_vehicles",        label = "dot vehicle rendering (circles instead of emoji)" },
        b = { field = "debug_building_plots",      label = "building plots overlay" },
        g = { field = "debug_road_segments",       label = "road segments overlay" },
        v = { field = "debug_smooth_roads",        label = "smooth road overlay" },
        n = { field = "debug_hide_roads",          label = "hide roads" },
        m = { field = "debug_smooth_roads_merged", label = "merged street overlay" },
        j = { field = "debug_smooth_roads_like",   label = "streets-like-big-roads overlay" },
        o = { field = "overlay_only_mode",         label = "overlay-only mode" },
        i = { field = "debug_biome_overlay",       label = "biome overlay" },
        u = { field = "debug_unified_grid",        label = "unified pathfinding grid" },
        t = { field = "debug_trip_hover",          label = "trip hover delivery debug (hover trip in sidebar)" },
        k = { field = "debug_stuck_vehicles",      label = "stuck vehicle delivery debug" },
        z = { field = "debug_logistics_overlay",   label = "logistics zone overlay (0=dead 1=receive 2=send+receive)" },
    }
    local toggle = DEBUG_TOGGLES[key]
    if toggle then
        self.game[toggle.field] = not (self.game[toggle.field] or false)
        print("DEBUG: " .. toggle.label .. " " .. (self.game[toggle.field] and "ON" or "OFF"))
        return
    end

    -- S: toggle smooth vehicle movement; rebuild smooth paths for vehicles already mid-path
    if key == "s" then
        local g = self.game
        g.debug_smooth_vehicle_movement = not (g.debug_smooth_vehicle_movement or false)
        print("DEBUG: smooth vehicle movement " .. (g.debug_smooth_vehicle_movement and "ON" or "OFF"))
        if g.debug_smooth_vehicle_movement then
            local PSS = require("services.PathSmoothingService")
            if g.maps.unified and not g.maps.unified._snap_lookup then
                PSS.buildSnapLookup(g)
            end
            for _, v in ipairs(g.entities.vehicles) do
                if v.path and (v.path_i or 1) <= #v.path then
                    PSS.buildSmoothPath(v, g)
                end
            end
        end
        return
    end

    -- Force-enable autodispatch (debug cheat)
    if key == "a" then
        self.game.state.upgrades.auto_dispatch_unlocked = true
        print("DEBUG: Force enabled autodispatch")
        return
    end

    -- Spawn a test inter-city trip (requires city_2 to exist)
    if key == "l" then
        local game = self.game
        local city2 = game.maps and game.maps["city_2"]
        if not city2 then
            print("DEBUG: No city_2 — generate and send a multi-city world first")
            return
        end
        local city1 = game.maps.city
        -- pick a random building plot in city2 as destination
        local dest_plots = city2.building_plots
        if not dest_plots or #dest_plots == 0 then
            print("DEBUG: city_2 has no building plots")
            return
        end
        local dest_plot_local = dest_plots[love.math.random(#dest_plots)]
        -- Convert dest_plot from city2-local to unified sub-cell coords
        local dest_plot = {
            x = (city2.world_mn_x - 1) * 3 + dest_plot_local.x,
            y = (city2.world_mn_y - 1) * 3 + dest_plot_local.y,
        }
        -- find a client plot in city1 (use depot if no clients)
        local src_plot = game.entities.depots[1] and game.entities.depots[1].plot
        if #game.entities.clients > 0 then
            src_plot = game.entities.clients[1].plot
        end
        if not src_plot then print("DEBUG: no source plot"); return end

        local Trip = require("models.Trip")
        local t = Trip:new(500, 200)
        t:addLeg(src_plot, dest_plot, 1, "road")
        table.insert(game.entities.trips.pending, t)
        print(string.format("DEBUG: spawned inter-city trip → city_2 unified (%d,%d)", dest_plot.x, dest_plot.y))
        return
    end

    -- Stress test: 50 bikes + 50 trucks + 25 clients + 100 trips, autodispatch on
    if key == "f" then
        local game = self.game
        if not game.maps or not game.maps.unified then
            print("DEBUG: Stress test requires world to be generated first (press F9)")
            return
        end
        local TripGenerator = require("services.TripGenerator")
        local Trip = require("models.Trip")
        local cmap = game.maps.city

        game.state.money = game.state.money + 9999999
        game.state.upgrades.auto_dispatch_unlocked = true
        game.state.upgrades.max_pending_trips  = math.max(game.state.upgrades.max_pending_trips,  200)

        for id, _ in pairs(game.C.VEHICLES) do
            for _ = 1, 50 do game.entities:addVehicle(game, id:lower()) end
        end
        for _ = 1, 25 do game.entities:addClient(game)           end

        local payout = game.C.GAMEPLAY.BASE_TRIP_PAYOUT
        local bonus  = game.C.GAMEPLAY.INITIAL_SPEED_BONUS

        local function toUnified(plot_local)
            return { x = (cmap.world_mn_x - 1) * 3 + plot_local.x,
                     y = (cmap.world_mn_y - 1) * 3 + plot_local.y }
        end

        -- 100 trips from random building plots across the city
        for _ = 1, 100 do
            local pl = cmap:getRandomBuildingPlot()
            if pl then
                local t = TripGenerator.generateTrip(toUnified(pl), game, cmap)
                if t then table.insert(game.entities.trips.pending, t) end
            end
        end

        -- 25 inter-city trips (city_2 if available)
        local city2 = game.maps["city_2"]
        local bp2   = city2 and city2.building_plots
        if bp2 and #bp2 > 0 then
            for _ = 1, 25 do
                local dpl  = bp2[love.math.random(#bp2)]
                local dest = { x = (city2.world_mn_x - 1) * 3 + dpl.x,
                               y = (city2.world_mn_y - 1) * 3 + dpl.y }
                local spl  = cmap:getRandomBuildingPlot()
                local src  = spl and toUnified(spl) or (game.entities.depots[1] and game.entities.depots[1].plot)
                local t    = Trip:new(payout * 3, bonus * 2)
                t:addLeg(src, dest, 1, "road")
                table.insert(game.entities.trips.pending, t)
            end
        end

        print(string.format("DEBUG: Stress test — 50 bikes, 50 trucks, 25 clients, %d trips queued",
            #game.entities.trips.pending))
        return
    end

    -- Money cheats
    if key == "-" then
        if self.game.state then
            self.game.state.money = self.game.state.money - 10000
            if self.game.error_service then
                self.game.error_service.logInfo("Input", "DEBUG: Removed 10,000 money.")
            end
        end
        return
    elseif key == "=" then
        if self.game.state then
            self.game.state.money = self.game.state.money + 10000
            if self.game.error_service then
                self.game.error_service.logInfo("Input", "DEBUG: Added 10,000 money.")
            end
        end
        return
    end
end

function InputController:textinput(text)
end

function InputController:mousewheelmoved(x, y)
    local mx, my = love.mouse.getPosition()
    -- Sidebar: pass vertical scroll to UI manager
    if mx < self.game.C.UI.SIDEBAR_WIDTH then
        if self.game.ui_manager and self.game.ui_manager.handle_scroll then
            self.game.ui_manager:handle_scroll(y)
        end
        return
    end
    -- World area: zoom toward cursor
    if y ~= 0 then
        local cam    = self.game.camera
        local Z      = self.game.C.ZOOM
        local factor = y > 0 and Z.SCROLL_FACTOR or (1 / Z.SCROLL_FACTOR)
        local sw     = self.game.C.UI.SIDEBAR_WIDTH
        local vw     = love.graphics.getWidth() - sw
        local vh     = love.graphics.getHeight()
        -- World position under cursor before zoom
        local wx = (mx - (sw + vw / 2)) / cam.scale + cam.x
        local wy = (my - vh / 2)        / cam.scale + cam.y
        -- Apply zoom, clamped; min scale keeps map height filling the viewport
        local map_h_px  = (self.game.world_h or 0) * self.game.C.MAP.TILE_SIZE
        local min_scale = (map_h_px > 0) and (vh / map_h_px) or Z.MIN_SCALE
        local new_scale = math.max(min_scale, math.min(Z.MAX_SCALE, cam.scale * factor))
        cam.scale = new_scale
        -- Adjust so cursor stays on same world point
        cam.x = wx - (mx - (sw + vw / 2)) / new_scale
        cam.y = wy - (my - vh / 2)        / new_scale
        -- Clamp y to map bounds after zoom
        local mph = (self.game.world_h or 0) * self.game.C.MAP.TILE_SIZE
        if mph > 0 then
            local half_h = vh * 0.5 / new_scale
            cam.y = math.max(half_h, math.min(mph - half_h, cam.y))
        end
    end
end

function InputController:mousepressed(x, y, button)
    local Game = self.game

    if self.ui_controller:handleMouseDown(x, y, button) then
        return
    end

    if button == 2 then
        -- Close any existing context menu first
        if Game.ui_manager then Game.ui_manager:closeContextMenu() end
        local sidebar_w = Game.C.UI.SIDEBAR_WIDTH
        if x >= sidebar_w then
            self:openContextMenu(x, y, Game)
        end
        return
    end

    -- Any left-click closes an open context menu (handled before the drag logic)
    if button == 1 and Game.ui_manager and Game.ui_manager.context_menu then
        if Game.ui_manager:handleContextMenuMouseDown(x, y, button, Game) then
            return
        end
    end

    if button == 1 then
        local sidebar_w = Game.C.UI.SIDEBAR_WIDTH
        if x >= sidebar_w then
            -- HUD strip (overlay toggle buttons) sits over the world view
            if Game.hud_strip and Game.hud_strip:handleMouseDown(x, y, Game) then
                return
            end
            -- Record drag start; don't fire click yet
            self._drag_active  = true
            self._drag_panning = false
            self._drag_sx      = x
            self._drag_sy      = y
        end
    end
end

function InputController:mousereleased(x, y, button)
    -- Let UIController commit any dispatch drag-and-drop first
    self.ui_controller:handleMouseUp(x, y, button, self.game)

    if self.game.ui_manager and self.game.ui_manager.handle_mouse_up then
        self.game.ui_manager:handle_mouse_up(x, y, button)
    end
    if button == 1 and self._drag_active then
        if not self._drag_panning then
            self:handleGameWorldClick(self._drag_sx, self._drag_sy)
        end
        self._drag_active  = false
        self._drag_panning = false
    end
end

function InputController:mousemoved(x, y, dx, dy)
    -- Track sidebar drag-and-drop
    local sidebar_w = self.game.C.UI.SIDEBAR_WIDTH
    if x < sidebar_w then
        self.ui_controller:handleMouseMoved(x, y)
    end

    if not self._drag_active then return end
    local total_dist = math.abs(x - self._drag_sx) + math.abs(y - self._drag_sy)
    if not self._drag_panning and total_dist > 5 then
        self._drag_panning = true
    end
    if self._drag_panning then
        local cam = self.game.camera
        cam.x = cam.x - dx / cam.scale
        cam.y = cam.y - dy / cam.scale
        -- Clamp vertical pan to map bounds
        local mph = (self.game.world_h or 0) * self.game.C.MAP.TILE_SIZE
        if mph > 0 then
            local half_h = love.graphics.getHeight() * 0.5 / cam.scale
            cam.y = math.max(half_h, math.min(mph - half_h, cam.y))
        end
    end
end

function InputController:handleGameWorldClick(x, y, button)
    local world_x, world_y = self.game.camera:screenToWorld(x, y, self.game)
    -- Wrap world_x into canonical [0, mpw) range for looping world
    local mpw = (self.game.world_w or 0) * self.game.C.MAP.TILE_SIZE
    if mpw > 0 then
        world_x = ((world_x % mpw) + mpw) % mpw
    end

    -- build_highway_mode: route click to highway builder
    if self.game.entities.build_highway_mode then
        self:_handleHighwayBuildClick(world_x, world_y)
        return
    end

    -- build_depot_mode: left-click now places depot directly
    if self.game.entities.build_depot_mode then
        self:_tryPlaceDepot(world_x, world_y, x, y)
        return
    end

    if self.game.event_spawner and self.game.event_spawner.handle_click then
        if self.game.event_spawner:handle_click(world_x, world_y, self.game) then
            return
        end
    end

    if self.game.entities and self.game.entities.handle_click then
        local hit = self.game.entities:handle_click(world_x, world_y, self.game)
        -- tab unchanged: user stays on whichever tab they had open
    end
end

function InputController:update(dt)
end

-- ─── Coordinate helpers ──────────────────────────────────────────────────────

-- Returns the unified sub-cell (gx, gy) under world pixel (wx, wy), or nil.
local function _worldToSubcell(wx, wy, game)
    local umap = game.maps.unified
    if not umap then return nil end
    local gx = math.floor(wx / umap.tile_pixel_size) + 1
    local gy = math.floor(wy / umap.tile_pixel_size) + 1
    if gx < 1 or gy < 1 or gx > umap._w or gy > umap._h then return nil end
    return gx, gy, umap
end

-- Returns true if unified sub-cell (gx, gy) is a valid depot build site.
local function _isValidDepotSite(gx, gy, umap)
    if umap.ffi_grid then
        local ti = umap.ffi_grid[(gy - 1) * umap._w + (gx - 1)].type
        if ti == 8 or ti == 9 then return true end  -- plot / downtown_plot
    end
    local zsv, zsh = umap.zone_seg_v, umap.zone_seg_h
    if (zsv and zsv[gy] and (zsv[gy][gx] or zsv[gy][gx - 1]))
    or (zsh and zsh[gy]     and zsh[gy][gx])
    or (zsh and zsh[gy - 1] and zsh[gy - 1][gx]) then
        return true
    end
    return false
end

-- ─── Highway build ───────────────────────────────────────────────────────────

-- Handles a left-click during highway build mode.
-- wx_px, wy_px: world-pixel coordinates of the click.
function InputController:_handleHighwayBuildClick(wx_px, wy_px)
    local game = self.game
    local IS   = require("services.InfrastructureService")

    local gx, gy, umap = _worldToSubcell(wx_px, wy_px, game)
    if not gx then
        require("services.FloatingTextSystem").emit("Out of bounds!", wx_px, wy_px, game.C)
        return
    end

    local wx = math.ceil(gx / 3)
    local wy = math.ceil(gy / 3)

    local nodes = game.entities.highway_build_nodes or {}

    if #nodes == 0 then
        -- First click: must be an existing highway tile
        if IS.isHighwayCell(wx, wy, game) then
            game.entities.highway_build_nodes = {{ wx = wx, wy = wy }}
        else
            require("services.FloatingTextSystem").emit("Start on a highway!", wx_px, wy_px, game.C)
        end
        return
    end

    -- Subsequent click: highway tile = finish segment, anything else = waypoint
    if IS.isHighwayCell(wx, wy, game) then
        -- Finish segment at this highway tile
        local all_nodes = {}
        for _, n in ipairs(nodes) do all_nodes[#all_nodes+1] = n end
        all_nodes[#all_nodes+1] = { wx = wx, wy = wy }

        local new_cells, cost = IS.computeSegment(all_nodes, game)
        if #new_cells == 0 then
            -- Route already exists or entirely impassable — just cancel mode
            game.entities.build_highway_mode = false
            game.entities.highway_build_nodes = {}
            game._hw_ghost_cache = nil
            return
        end
        if game.state.money < cost then
            require("services.FloatingTextSystem").emit(
                string.format("Need $%d!", cost), wx_px, wy_px, game.C)
            return
        end
        game.state.money = game.state.money - cost
        IS.applyHighway(new_cells, game)
        require("services.FloatingTextSystem").emit(
            string.format("Highway built! -$%d", cost), wx_px, wy_px, game.C)
        game.entities.build_highway_mode = false
        game.entities.highway_build_nodes = {}
        game._hw_ghost_cache = nil

    else
        -- Add intermediate waypoint — any click is valid; impassable cells are snapped
        -- to their nearest passable neighbour automatically by findPath.
        nodes[#nodes+1] = { wx = wx, wy = wy }
        game.entities.highway_build_nodes = nodes
    end
end

-- ─── Context menu ────────────────────────────────────────────────────────────

-- Immediately place a depot at (wx, wy) — used when build_depot_mode is active.
function InputController:_tryPlaceDepot(wx, wy, sx, sy)
    local game = self.game
    local gx, gy, umap = _worldToSubcell(wx, wy, game)
    if not gx then
        require("services.FloatingTextSystem").emit("Invalid location!", wx, wy, game.C)
        return
    end
    if not _isValidDepotSite(gx, gy, umap) then
        require("services.FloatingTextSystem").emit("Invalid location!", wx, wy, game.C)
        return
    end
    -- 1-depot-per-district check: compute new depot's district and compare
    local Depot = require("models.Depot")
    local candidate = Depot:new("_candidate", {x=gx, y=gy}, game)
    local new_district = candidate:getDistrict(game)
    local new_city     = candidate:getCity(game)
    if new_district then
        for _, existing in ipairs(game.entities.depots) do
            if existing:getCity(game) == new_city and existing:getDistrict(game) == new_district then
                require("services.FloatingTextSystem").emit("District already has a depot!", wx, wy, game.C)
                return
            end
        end
    end

    local cost = 500
    if game.state.money < cost then
        require("services.FloatingTextSystem").emit("Not enough money!", wx, wy, game.C)
        return
    end
    game.state.money = game.state.money - cost
    local depot    = Depot:new("depot_" .. love.math.random(1000, 9999), {x=gx, y=gy}, game)
    table.insert(game.entities.depots, depot)
    game.entities.build_depot_mode = false
    if game.ui_manager and game.ui_manager.panel then
        game.ui_manager.panel.depot_view = depot
    end
    require("services.FloatingTextSystem").emit("Depot Built! -$" .. cost, wx, wy, game.C)
end

-- Build and show a context-sensitive right-click menu at screen position (sx, sy).
function InputController:openContextMenu(sx, sy, game)
    local world_x, world_y = game.camera:screenToWorld(sx, sy, game)
    local mpw = (game.world_w or 0) * game.C.MAP.TILE_SIZE
    if mpw > 0 then world_x = ((world_x % mpw) + mpw) % mpw end

    local items = {}
    local gx, gy, umap = _worldToSubcell(world_x, world_y, game)

    -- ── Hit-test: highway tile ───────────────────────────────────────────────
    local hit_highway = false
    local hw_wx, hw_wy
    if gx then
        local IS = require("services.InfrastructureService")
        hw_wx = math.ceil(gx / 3)
        hw_wy = math.ceil(gy / 3)
        hit_highway = IS.isHighwayCell(hw_wx, hw_wy, game)
    end

    -- ── Hit-test: depot ──────────────────────────────────────────────────────
    local hit_depot = nil
    if umap then
        local u_uts = umap.tile_pixel_size
        local hit_r = 20 / game.camera.scale
        for _, depot in ipairs(game.entities.depots) do
            if depot.plot then
                local dpx = (depot.plot.x - 0.5) * u_uts
                local dpy = (depot.plot.y - 0.5) * u_uts
                if (world_x - dpx)^2 + (world_y - dpy)^2 < hit_r * hit_r then
                    hit_depot = depot
                    break
                end
            end
        end
    end

    -- ── Hit-test: vehicle ────────────────────────────────────────────────────
    local hit_vehicle = nil
    do
        local click_r = game.C.UI.VEHICLE_CLICK_RADIUS / game.camera.scale
        local r2 = click_r * click_r
        for _, v in ipairs(game.entities.vehicles) do
            if (world_x - v.px)^2 + (world_y - v.py)^2 < r2 then
                hit_vehicle = v
                break
            end
        end
    end

    -- ── Context: on a depot ──────────────────────────────────────────────────
    if hit_depot then
        table.insert(items, { label = hit_depot.id or "Depot", disabled = true })
        table.insert(items, { separator = true })
        table.insert(items, { icon = "📊", label = "View Depot Info",
            action = function(g)
                g.ui_manager.panel.depot_view = hit_depot
            end })
        -- Hire menu per vehicle type
        local sorted = {}
        for id, vcfg in pairs(game.C.VEHICLES) do
            sorted[#sorted+1] = { id = id, vcfg = vcfg }
        end
        table.sort(sorted, function(a, b) return a.vcfg.base_cost < b.vcfg.base_cost end)
        for _, entry in ipairs(sorted) do
            local vid  = entry.id:lower()
            local vcfg = entry.vcfg
            local cost = game.state.costs[vid] or vcfg.base_cost
            local can_afford = game.state.money >= cost
            local district_ok = true
            if vcfg.required_depot_district then
                district_ok = (hit_depot:getDistrict(game) == vcfg.required_depot_district)
            end
            local suffix = (not district_ok)
                and (" [needs " .. vcfg.required_depot_district .. "]") or ""
            table.insert(items, {
                icon     = vcfg.icon,
                label    = string.format("Hire %s ($%d)%s", vcfg.display_name, cost, suffix),
                disabled = not can_afford or not district_ok,
                action   = function(g)
                    g.EventBus:publish("ui_buy_vehicle_at_depot_clicked",
                        { vehicle_id = vid, depot = hit_depot })
                end,
            })
        end
        table.insert(items, { separator = true })
        table.insert(items, { icon = "📢", label = "Market for Clients ($100)",
            disabled = true })  -- placeholder

    -- ── Context: on a vehicle ────────────────────────────────────────────────
    elseif hit_vehicle then
        local vcfg = game.C.VEHICLES[hit_vehicle.type_upper]
        local name = (vcfg and vcfg.display_name or hit_vehicle.type)
                  .. " #" .. hit_vehicle.id
        table.insert(items, { label = name, disabled = true })
        table.insert(items, { separator = true })
        table.insert(items, { icon = "🚗", label = "Select Vehicle",
            action = function(g)
                g.entities.selected_vehicle = hit_vehicle
                g.entities.selected_depot   = nil
            end })
        table.insert(items, { icon = "🏠", label = "Recall to Depot",
            action = function(g)
                local States = require("models.vehicles.vehicle_states")
                hit_vehicle:unassign(g)
            end })

    -- ── Context: highway tile ────────────────────────────────────────────────
    elseif hit_highway then
        table.insert(items, { label = "Highway", disabled = true })
        table.insert(items, { separator = true })
        table.insert(items, { icon = "🛣️", label = "Extend Highway from here",
            action = function(g)
                g.entities.build_highway_mode = true
                g.entities.highway_build_nodes = {{ wx = hw_wx, wy = hw_wy }}
            end })

    -- ── Context: empty world space ───────────────────────────────────────────
    else
        local valid_site = gx and _isValidDepotSite(gx, gy, umap)
        local depot_cost = 500
        -- Check district uniqueness for the context menu disabled state
        local district_taken = false
        local depot_district_label = nil
        if valid_site then
            local Depot_cls = require("models.Depot")
            local cand = Depot_cls:new("_cand", {x=gx, y=gy}, game)
            local cand_district = cand:getDistrict(game)
            local cand_city     = cand:getCity(game)
            if cand_district then
                for _, existing in ipairs(game.entities.depots) do
                    if existing:getCity(game) == cand_city and existing:getDistrict(game) == cand_district then
                        district_taken = true
                        depot_district_label = "District already has a depot"
                        break
                    end
                end
            end
        end
        local depot_disabled = not valid_site or game.state.money < depot_cost or district_taken
        local depot_label = "Build Depot ($" .. depot_cost .. ")"
        if district_taken then depot_label = "Build Depot — " .. (depot_district_label or "unavailable") end
        table.insert(items, { icon = "🏢", label = depot_label,
            disabled = depot_disabled,
            action   = function(g)
                g.entities.build_depot_mode = true
                local ic = g.input_controller
                if ic then ic:_tryPlaceDepot(world_x, world_y, sx, sy) end
            end })
        table.insert(items, { separator = true })
        table.insert(items, { icon = "📍", label = "Set Camera Here",
            action = function(g)
                g.camera.x = world_x
                g.camera.y = world_y
            end })
    end

    if #items > 0 then
        game.ui_manager:showContextMenu(sx, sy, items)
    end
end

return InputController
