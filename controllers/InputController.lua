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

local HOTKEYS = { ["1"]=true,["2"]=true,["3"]=true,["4"]=true,["5"]=true,
                  ["6"]=true,["7"]=true,["8"]=true,["9"]=true,["0"]=true,
                  ["space"]=true }

-- Save-system keybindings. Single file, manual save / delete only.
local SAVE_KEY         = "f5"
local DELETE_KEY       = "f9"
local SAVE_FILENAME    = "savegame.json"

local COLOR_OK     = { 0.3, 1.0, 0.45 }
local COLOR_ERR    = { 1.0, 0.3, 0.3 }
local COLOR_INFO   = { 0.6, 0.75, 1.0 }
local COLOR_MUTED  = { 0.7, 0.7, 0.7 }

local function pushFeed(game, text, color)
    if game.info_feed and game.info_feed.push then
        game.info_feed:push({ text = text, color = color })
    end
end

function InputController:keypressed(key)
    -- DataGrid filter row (focused cell or popup search) takes priority over
    -- dispatch inputs and global hotkeys.
    local DataGrid = require("views.DataGrid")
    if DataGrid.routeKeyPressed(key, self.game) then return end

    -- Route to dispatch input handlers: search field first, then number slot.
    local DT = require("views.tabs.DispatchTab")
    if DT.handleSearchKey(key)  then return end
    if DT.handleKeyPressed(key) then return end

    -- Fire hotkey hat rules (1-0, space)
    if HOTKEYS[key] then
        local RE = require("services.DispatchRuleEngine")
        RE.fireEvent(self.game.state.dispatch_rules or {}, "hotkey",
            { game = self.game, key = key })
    end

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

    -- F5: Save   /   F9: Delete save
    if key == SAVE_KEY then
        local SaveService = require("services.SaveService")
        local ok, err = SaveService.saveGame(self.game, SAVE_FILENAME)
        if ok then
            local money    = self.game.state.money or 0
            local clients  = (self.game.entities and #self.game.entities.clients) or 0
            local depots   = (self.game.entities and #self.game.entities.depots)  or 0
            pushFeed(self.game, string.format("Saved  ·  $%d  ·  %d clients  ·  %d depots",
                math.floor(money), clients, depots), COLOR_OK)
        else
            pushFeed(self.game, "Save failed: " .. tostring(err or "unknown error"), COLOR_ERR)
        end
        return
    end

    if key == DELETE_KEY then
        local info = love.filesystem.getInfo(SAVE_FILENAME)
        if not info then
            pushFeed(self.game, "No save file to delete", COLOR_MUTED)
            return
        end
        local SaveService = require("services.SaveService")
        if SaveService.deleteSave(SAVE_FILENAME) then
            pushFeed(self.game, "Save file deleted", COLOR_INFO)
        else
            pushFeed(self.game, "Delete failed", COLOR_ERR)
        end
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
        local Archetypes = require("data.client_archetypes")
        for _, a in ipairs(Archetypes.list) do
            game.state.upgrades[a.id .. "_capacity_bonus"] = math.max(
                game.state.upgrades[a.id .. "_capacity_bonus"] or 0, 200)
        end

        for id, _ in pairs(game.C.VEHICLES) do
            for _ = 1, 50 do game.entities:addVehicle(game, id:lower()) end
        end
        for _ = 1, 25 do game.entities:addClient(game)           end

        local payout      = game.C.GAMEPLAY.BASE_TRIP_PAYOUT
        local bonus_ratio = game.C.GAMEPLAY.SPEED_BONUS_RATIO   or 0.5
        local base_dur    = game.C.GAMEPLAY.BASE_BONUS_DURATION or 30
        local scope_time  = (game.C.GAMEPLAY.SCOPE_TIME_MULT
                             and game.C.GAMEPLAY.SCOPE_TIME_MULT.city) or 1.5

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
                local base = payout * 3
                local sb   = math.floor(base * bonus_ratio + 0.5)
                local t    = Trip:new(base, sb)
                t.speed_bonus_initial = sb
                t.bonus_duration      = base_dur * scope_time
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
    local DataGrid = require("views.DataGrid")
    if DataGrid.routeTextInput(text, self.game) then return end

    local DT = require("views.tabs.DispatchTab")
    if DT.handleSearchInput(text) then return end  -- palette search consumes first
    DT.handleTextInput(text)
end

function InputController:mousewheelmoved(x, y)
    -- DataGrid filter popup scrolls its value list when open.
    local DataGrid = require("views.DataGrid")
    if DataGrid.isFilterPopupOpen() then
        local mx, my = love.mouse.getPosition()
        local popup  = DataGrid.filter_popup
        local px, py = popup._draw_x or popup.x, popup._draw_y or popup.y
        local pw, ph = popup._draw_w or 240, popup._draw_h or 240
        if mx >= px and mx < px + pw and my >= py and my < py + ph then
            local FilterPopup = require("views.FilterPopup")
            FilterPopup.wheelmoved(popup, y)
            return
        end
    end

    -- Modal gets scroll priority
    local mm = self.game.ui_manager and self.game.ui_manager.modal_manager
    if mm and mm:isActive() and mm.active_modal.wheelmoved then
        if mm.active_modal:wheelmoved(x, y) then return end
    end

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

    -- Reject clicks in fogged areas
    local ScopeService = require("services.ScopeService")
    local umap = self.game.maps.unified
    if umap then
        local cgx = math.floor(world_x / umap.tile_pixel_size) + 1
        local cgy = math.floor(world_y / umap.tile_pixel_size) + 1
        if cgx >= 1 and cgy >= 1 and cgx <= umap._w and cgy <= umap._h
           and not ScopeService.isRevealed(self.game, cgx, cgy) then
            return
        end
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
    local mx, my = love.mouse.getPosition()
    local DT = require("views.tabs.DispatchTab")
    DT.updateHover(dt, mx, my, self.game)
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

-- Returns the 1-based index of the city in game.maps.all_cities that owns (gx, gy), or nil.
local function _cityIdxForSubcell(gx, gy, game)
    for i, cmap in ipairs(game.maps and game.maps.all_cities or {}) do
        local ox = (cmap.world_mn_x - 1) * 3
        local oy = (cmap.world_mn_y - 1) * 3
        local lx = gx - ox
        local ly = gy - oy
        if lx >= 1 and ly >= 1
        and cmap.grid and lx <= #(cmap.grid[1] or {}) and ly <= #cmap.grid then
            return i
        end
    end
    return nil
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
    game.entities.selected_depot = depot
    require("services.FloatingTextSystem").emit("Depot Built! -$" .. cost, wx, wy, game.C)
end

-- Build and show a context-sensitive right-click menu at screen position (sx, sy).
-- Hit-tests all entity types at the click position and delegates item building
-- to data/context_menu_items.lua. Multiple overlapping entities each contribute
-- their own section to the same menu.
function InputController:openContextMenu(sx, sy, game)
    local CMI = require("data.context_menu_items")
    local ScopeService = require("services.ScopeService")
    local world_x, world_y = game.camera:screenToWorld(sx, sy, game)
    local mpw = (game.world_w or 0) * game.C.MAP.TILE_SIZE
    if mpw > 0 then world_x = ((world_x % mpw) + mpw) % mpw end

    local items    = {}
    local any_hit  = false
    local gx, gy, umap = _worldToSubcell(world_x, world_y, game)

    -- No context menu in fogged areas
    if gx and not ScopeService.isRevealed(game, gx, gy) then return end

    -- ── Hit-test: all vehicles in radius ─────────────────────────────────────
    local click_r = game.C.UI.VEHICLE_CLICK_RADIUS / game.camera.scale
    local r2 = click_r * click_r
    for _, v in ipairs(game.entities.vehicles) do
        if (world_x - v.px)^2 + (world_y - v.py)^2 < r2 then
            if any_hit then table.insert(items, { separator = true }) end
            for _, item in ipairs(CMI.vehicle(v, game)) do items[#items + 1] = item end
            any_hit = true
        end
    end

    -- ── Hit-test: depot ──────────────────────────────────────────────────────
    if umap then
        local u_uts = umap.tile_pixel_size
        local hit_r = 20 / game.camera.scale
        for _, depot in ipairs(game.entities.depots) do
            if depot.plot then
                local dpx = (depot.plot.x - 0.5) * u_uts
                local dpy = (depot.plot.y - 0.5) * u_uts
                if (world_x - dpx)^2 + (world_y - dpy)^2 < hit_r * hit_r then
                    if any_hit then table.insert(items, { separator = true }) end
                    for _, item in ipairs(CMI.depot(depot, game)) do items[#items + 1] = item end
                    any_hit = true
                    break
                end
            end
        end
    end

    -- ── Hit-test: highway tile ───────────────────────────────────────────────
    if gx then
        local IS = require("services.InfrastructureService")
        local hw_wx = math.ceil(gx / 3)
        local hw_wy = math.ceil(gy / 3)
        if IS.isHighwayCell(hw_wx, hw_wy, game) then
            if any_hit then table.insert(items, { separator = true }) end
            for _, item in ipairs(CMI.highway(hw_wx, hw_wy, game)) do items[#items + 1] = item end
            any_hit = true
        end
    end

    -- ── Fallback: empty world space ──────────────────────────────────────────
    if not any_hit then
        items = CMI.empty(world_x, world_y, sx, sy, gx, gy, umap, game)
    end

    if #items > 0 then
        game.ui_manager:showContextMenu(sx, sy, items)
    end
end

return InputController
