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
        o = { field = "overlay_only_mode",         label = "overlay-only mode" },
        d = { field = "debug_district_overlay",    label = "district overlay" },
        i = { field = "debug_biome_overlay",       label = "biome overlay" },
    }
    local toggle = DEBUG_TOGGLES[key]
    if toggle then
        self.game[toggle.field] = not (self.game[toggle.field] or false)
        print("DEBUG: " .. toggle.label .. " " .. (self.game[toggle.field] and "ON" or "OFF"))
        return
    end

    -- Force-enable autodispatch (debug cheat)
    if key == "a" then
        self.game.state.upgrades.auto_dispatch_unlocked = true
        print("DEBUG: Force enabled autodispatch")
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
        -- Apply zoom, clamped
        local new_scale = math.max(Z.MIN_SCALE, math.min(Z.MAX_SCALE, cam.scale * factor))
        cam.scale = new_scale
        -- Adjust so cursor stays on same world point
        cam.x = wx - (mx - (sw + vw / 2)) / new_scale
        cam.y = wy - (my - vh / 2)        / new_scale
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
    end
end

function InputController:handleGameWorldClick(x, y)
    local world_x, world_y = self.game.camera:screenToWorld(x, y, self.game)

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
