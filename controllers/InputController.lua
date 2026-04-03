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

    -- Debug overlay toggles
    local DEBUG_TOGGLES = {
        b = { field = "debug_building_plots",      label = "building plots overlay" },
        p = { field = "debug_pickup_locations",    label = "pickup/client overlay" },
        g = { field = "debug_road_segments",       label = "road segments overlay" },
        v = { field = "debug_smooth_roads",        label = "smooth road overlay" },
        n = { field = "debug_hide_roads",          label = "hide roads" },
        m = { field = "debug_smooth_roads_merged", label = "merged street overlay" },
        j = { field = "debug_smooth_roads_like",   label = "streets-like-big-roads overlay" },
        o = { field = "overlay_only_mode",             label = "overlay-only mode" },
        d = { field = "debug_district_overlay",    label = "district overlay" },
        i = { field = "debug_biome_overlay",       label = "biome overlay" },
        u = { field = "debug_unified_grid",        label = "unified pathfinding grid" },
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
        local src_plot = game.entities.depot_plot
        if #game.entities.clients > 0 then
            src_plot = game.entities.clients[1].plot
        end
        if not src_plot then print("DEBUG: no source plot"); return end

        local Trip = require("models.Trip")
        local t = Trip:new(500, 200)
        t:addLeg(src_plot, dest_plot, "truck")
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

        for _ = 1, 50 do game.entities:addVehicle(game, "bike")  end
        for _ = 1, 50 do game.entities:addVehicle(game, "truck") end
        for _ = 1, 25 do game.entities:addClient(game)           end

        local payout = game.C.GAMEPLAY.BASE_TRIP_PAYOUT
        local bonus  = game.C.GAMEPLAY.INITIAL_SPEED_BONUS

        local function toUnified(plot_local)
            return { x = (cmap.world_mn_x - 1) * 3 + plot_local.x,
                     y = (cmap.world_mn_y - 1) * 3 + plot_local.y }
        end

        -- 50 downtown bike trips
        for _ = 1, 50 do
            local pl = cmap:getRandomDowntownBuildingPlot()
            if pl then
                local t = TripGenerator._createDowntownTrip(toUnified(pl), payout, bonus, game)
                if t then table.insert(game.entities.trips.pending, t) end
            end
        end

        -- 25 intra-city truck trips
        for _ = 1, 25 do
            local pl = cmap:getRandomDowntownBuildingPlot()
            if pl then
                local t = TripGenerator._createCityTrip(toUnified(pl), payout, bonus, game)
                if t then table.insert(game.entities.trips.pending, t) end
            end
        end

        -- 25 inter-city truck trips (city_2 if available, else more intra-city)
        local city2 = game.maps["city_2"]
        local bp2   = city2 and city2.building_plots
        for _ = 1, 25 do
            if bp2 and #bp2 > 0 then
                local dpl = bp2[love.math.random(#bp2)]
                local dest = { x = (city2.world_mn_x - 1) * 3 + dpl.x,
                               y = (city2.world_mn_y - 1) * 3 + dpl.y }
                local spl  = cmap:getRandomDowntownBuildingPlot()
                local src  = spl and toUnified(spl) or game.entities.depot_plot
                local t = Trip:new(payout * 3, bonus * 2)
                t:addLeg(src, dest, "truck")
                table.insert(game.entities.trips.pending, t)
            else
                local pl = cmap:getRandomDowntownBuildingPlot()
                if pl then
                    local t = TripGenerator._createCityTrip(toUnified(pl), payout, bonus, game)
                    if t then table.insert(game.entities.trips.pending, t) end
                end
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

    if button == 1 then
        local sidebar_w = Game.C.UI.SIDEBAR_WIDTH
        if x >= sidebar_w then
            -- Record drag start; don't fire click yet
            self._drag_active  = true
            self._drag_panning = false
            self._drag_sx      = x
            self._drag_sy      = y
        end
    end
end

function InputController:mousereleased(x, y, button)
    if self.game.ui_manager and self.game.ui_manager.handle_mouse_up then
        self.game.ui_manager:handle_mouse_up(x, y, button)
    end
    if button == 1 and self._drag_active then
        if not self._drag_panning then
            -- Short click: fire world click at original press position
            self:handleGameWorldClick(self._drag_sx, self._drag_sy)
        end
        self._drag_active  = false
        self._drag_panning = false
    end
end

function InputController:mousemoved(x, y, dx, dy)
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

function InputController:handleGameWorldClick(x, y)
    local world_x, world_y = self.game.camera:screenToWorld(x, y, self.game)
    -- Wrap world_x into canonical [0, mpw) range for looping world
    local mpw = (self.game.world_w or 0) * self.game.C.MAP.TILE_SIZE
    if mpw > 0 then
        world_x = ((world_x % mpw) + mpw) % mpw
    end

    if self.game.event_spawner and self.game.event_spawner.handle_click then
        if self.game.event_spawner:handle_click(world_x, world_y, self.game) then
            return
        end
    end

    if self.game.entities and self.game.entities.handle_click then
        self.game.entities:handle_click(world_x, world_y, self.game)
    end
end

function InputController:update(dt)
end

return InputController
