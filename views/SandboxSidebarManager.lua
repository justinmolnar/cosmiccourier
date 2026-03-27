-- views/SandboxSidebarManager.lua
-- Manages accordion panels for the city generation sandbox sidebar.

local Accordion     = require("views.components.Accordion")
local MapSizePanel  = require("views.sandbox.panels.MapSizePanel")
local DistrictPanel = require("views.sandbox.panels.DistrictPanel")
local RoadNetworkPanel = require("views.sandbox.panels.RoadNetworkPanel")
local ActionsPanel  = require("views.sandbox.panels.ActionsPanel")
local PerDistrictPanel = require("views.sandbox.panels.PerDistrictPanel")

local SandboxSidebarManager = {}
SandboxSidebarManager.__index = SandboxSidebarManager

function SandboxSidebarManager:new(sc, game)
    local inst = setmetatable({}, SandboxSidebarManager)
    inst.sc   = sc
    inst.game = game
    local C = game.C

    inst.map_size_acc     = Accordion:new("Map Dimensions", true,  160)
    inst.district_acc     = Accordion:new("Generation",     true,  220)
    inst.road_network_acc = Accordion:new("Road Network",   false, 320)
    inst.per_district_acc = Accordion:new("Per-District",   false, 400)
    inst.actions_acc      = Accordion:new("Actions",        true,  140)

    inst.accordions = {
        inst.map_size_acc,
        inst.district_acc,
        inst.road_network_acc,
        inst.per_district_acc,
        inst.actions_acc,
    }

    -- Build initial widget lists
    inst.map_size_widgets   = MapSizePanel.buildWidgets(sc, game)
    inst.district_widgets   = DistrictPanel.buildWidgets(sc, game)
    inst.road_network_widgets = RoadNetworkPanel.buildWidgets(sc, game)
    inst.per_district_widgets = PerDistrictPanel.buildWidgets(sc, game)

    -- Panel widget lists indexed same as accordions (actions has no widget list, drawn directly)
    inst.panel_widgets = {
        inst.map_size_widgets,
        inst.district_widgets,
        inst.road_network_widgets,
        inst.per_district_widgets,
        {}, -- actions accordion -- buttons handled directly
    }

    -- Action button rects (absolute positions, set in _doLayout)
    inst.gen_btn  = { x=0, y=0, w=0, h=38 }
    -- Six individual view toggle buttons (2x3 grid)
    inst.view_btns = {
        { mode="zones",      label="Zones",      x=0, y=0, w=0, h=26 },
        { mode="arterials",  label="Arterials",  x=0, y=0, w=0, h=26 },
        { mode="streets",    label="Streets",    x=0, y=0, w=0, h=26 },
        { mode="tiles",      label="Tiles",      x=0, y=0, w=0, h=26 },
        { mode="flood_fill", label="Flood Fill", x=0, y=0, w=0, h=26 },
        { mode="standard",   label="Game Map",   x=0, y=0, w=0, h=26 },
    }
    inst.send_btn = { x=0, y=0, w=0, h=38 }

    -- Focused text input for exclusive focus management
    inst.focused_text_input = nil

    return inst
end

function SandboxSidebarManager:rebuildPerDistrictPanel()
    self.per_district_widgets = PerDistrictPanel.buildWidgets(self.sc, self.game)
    self.panel_widgets[4] = self.per_district_widgets
end

-- ── Layout ──────────────────────────────────────────────────────────────────

function SandboxSidebarManager:_doLayout()
    local C = self.game.C
    local sidebar_w = C.UI.SIDEBAR_WIDTH
    local wx = 10
    local ww = sidebar_w - 20

    -- Update accordion content heights from current widget lists
    for i, acc in ipairs(self.accordions) do
        local panel = self.panel_widgets[i]
        local total_h = 4
        for _, w in ipairs(panel) do
            total_h = total_h + w.h
        end
        -- Actions accordion has buttons, not panel_widgets
        if i == 5 then
            local view_h = 0
            for _, vb in ipairs(self.view_btns) do view_h = view_h + vb.h + 4 end
            total_h = self.gen_btn.h + view_h + self.send_btn.h + 60
        end
        local _, my = love.mouse.getPosition()
        acc:update(total_h, my)
    end

    -- Stack accordions vertically (start below the title bar)
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

    -- Assign absolute positions to panel widgets
    for i, acc in ipairs(self.accordions) do
        if i == 5 then break end -- actions handled separately
        local panel = self.panel_widgets[i]
        local wy = acc.y + acc.header_h
        for _, w in ipairs(panel) do
            w.x = wx
            w.y = wy
            w.w = ww
            wy = wy + w.h
        end
    end

    -- Actions accordion buttons
    local aa = self.actions_acc
    local bx = wx
    local bw = ww
    self.gen_btn.x = bx
    self.gen_btn.y = aa.y + aa.header_h + 4
    self.gen_btn.w = bw

    -- View toggle buttons: two per row
    local half_w = math.floor((bw - 4) / 2)
    local vy = self.gen_btn.y + self.gen_btn.h + 8
    for i, vb in ipairs(self.view_btns) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        vb.x = bx + col * (half_w + 4)
        vb.y = vy + row * (vb.h + 4)
        vb.w = half_w
    end
    local last_vb = self.view_btns[#self.view_btns]
    self.send_btn.x = bx
    self.send_btn.y = last_vb.y + last_vb.h + 8
    self.send_btn.w = bw
end

-- ── Update ───────────────────────────────────────────────────────────────────

function SandboxSidebarManager:update(dt)
    self:_doLayout()

    -- Update text inputs (cursor blink)
    for _, panel in ipairs(self.panel_widgets) do
        for _, w in ipairs(panel) do
            if w.update then w:update(dt) end
        end
    end
end

-- ── Draw ─────────────────────────────────────────────────────────────────────

function SandboxSidebarManager:draw()
    local game = self.game

    love.graphics.setFont(game.fonts.ui)

    -- Sidebar background
    local sidebar_w = game.C.UI.SIDEBAR_WIDTH
    local _, sh = love.graphics.getDimensions()
    love.graphics.setColor(0.08, 0.08, 0.12)
    love.graphics.rectangle("fill", 0, 0, sidebar_w, sh)
    love.graphics.setColor(0.25, 0.25, 0.35)
    love.graphics.line(sidebar_w, 0, sidebar_w, sh)

    -- Title
    love.graphics.setFont(game.fonts.ui_small)
    love.graphics.setColor(0.6, 0.8, 1.0)
    love.graphics.printf("CITY GEN SANDBOX", 0, 4, sidebar_w, "center")
    love.graphics.setColor(0.25, 0.25, 0.35)
    love.graphics.line(0, 20, sidebar_w, 20)

    -- Shift accordions down by title height
    -- (handled by _doLayout offset; here we just draw)

    -- Draw each accordion and its panel
    for i, acc in ipairs(self.accordions) do
        acc:beginDraw()

        if acc.is_open then
            if i == 5 then
                -- Actions panel
                ActionsPanel.draw(self.gen_btn, self.view_btns, self.send_btn, self.sc, game)
            else
                local panel_draw = {
                    MapSizePanel.draw,
                    DistrictPanel.draw,
                    RoadNetworkPanel.draw,
                    PerDistrictPanel.draw,
                }
                panel_draw[i](self.panel_widgets[i], self.sc, game)
            end
        end

        acc:endDraw()
        acc:drawScrollbar()
    end

    love.graphics.setColor(1, 1, 1)
end

-- ── Input ────────────────────────────────────────────────────────────────────

function SandboxSidebarManager:_focusTextInput(ti)
    if self.focused_text_input and self.focused_text_input ~= ti then
        self.focused_text_input:defocus()
    end
    self.focused_text_input = ti
end

function SandboxSidebarManager:handle_mouse_down(x, y, button)
    -- 1. Accordion header clicks
    for _, acc in ipairs(self.accordions) do
        if acc:handle_click(x, y) then return true end
    end

    -- 2. Accordion scrollbar drags
    for _, acc in ipairs(self.accordions) do
        if acc.is_open and acc:handle_mouse_down(x, y, button) then return true end
    end

    -- 3. Action buttons (actions accordion, index 5)
    if self.actions_acc.is_open then
        if button == 1 then
            local sy = y + self.actions_acc.scroll_y
            if self:_pointInRect(x, sy, self.gen_btn) then
                if self.focused_text_input then
                    self.focused_text_input:defocus()
                    self.focused_text_input = nil
                end
                self.sc:generate()
                return true
            end
            for _, vb in ipairs(self.view_btns) do
                if self:_pointInRect(x, sy, vb) then
                    self.sc:setViewMode(vb.mode)
                    return true
                end
            end
            if self:_pointInRect(x, sy, self.send_btn) then
                if self.sc.sandbox_map then
                    self.sc:sendToMainGame()
                end
                return true
            end
        end
    end

    -- 4. Panel widgets in open accordions
    for i, acc in ipairs(self.accordions) do
        if i == 5 then break end -- actions handled above
        if acc.is_open then
            -- Only process clicks that are within this accordion's visible content area
            local content_top    = acc.y + acc.header_h
            local content_bottom = content_top + acc.content_h
            if y >= content_top and y < content_bottom then
                local sy = y + acc.scroll_y
                for _, w in ipairs(self.panel_widgets[i]) do
                    if sy >= w.y and sy < w.y + w.h then
                        if w.focus then self:_focusTextInput(w) end
                        if w:handle_mouse_down(x, sy, button) then return true end
                    end
                end
            end
        end
    end

    -- Defocus any active text input if clicking elsewhere in sidebar
    if x < self.game.C.UI.SIDEBAR_WIDTH then
        if self.focused_text_input then
            self.focused_text_input:defocus()
            self.focused_text_input = nil
        end
    end

    return false
end

function SandboxSidebarManager:handle_mouse_up(x, y, button)
    for _, acc in ipairs(self.accordions) do
        acc:handle_mouse_up(x, y, button)
    end
    for _, panel in ipairs(self.panel_widgets) do
        for _, w in ipairs(panel) do
            if w.handle_mouse_up then w:handle_mouse_up(x, y, button) end
        end
    end
end

function SandboxSidebarManager:handle_mouse_moved(x, y, dx, dy)
    for _, panel in ipairs(self.panel_widgets) do
        for _, w in ipairs(panel) do
            if w.handle_mouse_moved then w:handle_mouse_moved(x, y, dx, dy) end
        end
    end
end

function SandboxSidebarManager:handle_scroll(mx, my, dy)
    for _, acc in ipairs(self.accordions) do
        if acc.is_open and mx >= acc.x and mx <= acc.x + acc.w and
           my >= acc.y + acc.header_h and my <= acc.y + acc.header_h + acc.content_h then
            acc.scroll_y = acc.scroll_y - (dy * 20)
            return true
        end
    end
    return false
end

function SandboxSidebarManager:handle_textinput(text)
    if self.focused_text_input then
        return self.focused_text_input:handle_textinput(text)
    end
    return false
end

function SandboxSidebarManager:handle_keypressed(key)
    if self.focused_text_input then
        local handled = self.focused_text_input:handle_keypressed(key)
        if key == "return" or key == "escape" then
            self.focused_text_input = nil
        end
        if handled then return true end
    end
    return false
end

function SandboxSidebarManager:_pointInRect(x, y, r)
    return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
end

return SandboxSidebarManager
