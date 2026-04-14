-- views/UIManager.lua
local UIManager = {}
UIManager.__index = UIManager

local CR            = require("views.ComponentRenderer")
local DataGrid      = require("views.DataGrid")
local ColumnChooser = require("views.ColumnChooser")
local TripsTab      = require("views.tabs.TripsTab")
local VehiclesTab  = require("views.tabs.VehiclesTab")
local UpgradesTab  = require("views.tabs.UpgradesTab")
local ClientsTab   = require("views.tabs.ClientsTab")

local DepotTab            = require("views.tabs.DepotTab")
local InfrastructureTab   = require("views.tabs.InfrastructureTab")
local DispatchTab         = require("views.tabs.DispatchTab")

local PANEL_Y = 148   -- pixels below top of sidebar where panel begins

function UIManager:new(C, game)
    local Panel        = require("views.Panel")
    local ModalManager = require("views.modal_manager")

    local instance = setmetatable({}, UIManager)

    instance.hovered_component  = nil
    instance.income_per_second  = 0
    instance.trips_per_second   = 0

    local screen_h = love.graphics.getHeight()
    instance.panel = Panel:new(0, PANEL_Y, C.UI.SIDEBAR_WIDTH, screen_h - PANEL_Y)

    instance.panel:registerTab({ id = "trips",    label = "Trips",    icon = "📦", priority = 1,
        build = function(g) return TripsTab.build(g, instance) end })
    instance.panel:registerTab({ id = "vehicles", label = "Vehicles", icon = "🚗", priority = 2,
        build = function(g) return VehiclesTab.build(g, instance) end })
    instance.panel:registerTab({ id = "dispatch", label = "Dispatch", icon = "⚡", priority = 3,
        build = function(g) return DispatchTab.build(g, instance) end,
        visible_when = function(g) return g.state.upgrades.auto_dispatch_unlocked == true end })
    instance.panel:registerTab({ id = "upgrades", label = "Upgrades", icon = "⬆️", priority = 4,
        build = function(g) return UpgradesTab.build(g, instance) end })
    instance.panel:registerTab({ id = "clients",  label = "Clients",  icon = "🏢", priority = 5,
        build = function(g) return ClientsTab.build(g, instance) end })
    instance.panel:registerTab({ id = "depot",    label = "Depot",    icon = "🏗️", priority = 6,
        build = function(g) return DepotTab.build(g, instance) end })
    instance.panel:registerTab({ id = "infrastructure", label = "Roads", icon = "🛣️", priority = 7,
        build = function(g) return InfrastructureTab.build(g, instance) end })

    instance.modal_manager  = ModalManager:new()
    instance.context_menu   = nil   -- active ContextMenu instance or nil

    return instance
end

-- ─── Update ──────────────────────────────────────────────────────────────────

function UIManager:handle_scroll(dy)
    -- If a dropdown is open in the dispatch tab, scroll it instead of the panel.
    local DT = require("views.tabs.DispatchTab")
    local ds = DT.getState()
    if ds and ds.active_dropdown then
        if ds.active_dropdown.wheelmoved then
            ds.active_dropdown:wheelmoved(0, dy)
        end
        return
    end
    self.panel:handleScroll(dy)
end

function UIManager:showContextMenu(sx, sy, items)
    local ContextMenu = require("views.ContextMenu")
    self.context_menu = ContextMenu:new(sx, sy, items)
end

function UIManager:closeContextMenu()
    self.context_menu = nil
end

-- Returns true if a context menu click was handled (caller should swallow the event).
function UIManager:handleContextMenuMouseDown(sx, sy, button, game)
    if not self.context_menu then return false end
    local handled, action = self.context_menu:handle_mouse_down(sx, sy, button, game)
    self.context_menu = nil
    if action then action(game) end
    return handled
end

function UIManager:handle_mouse_up(x, y, button)
    if self.modal_manager:handle_mouse_up(x, y) then return end
    self.panel:handleMouseUp()
end

function UIManager:drawContextMenu(game)
    if self.context_menu then
        self.context_menu:draw(game)
    end
end

function UIManager:update(dt, game)
    self.modal_manager:update(dt, game)
    if self.modal_manager:isActive() then
        DataGrid.applyHover(nil, game)
        return
    end
    if self.context_menu then
        DataGrid.applyHover(nil, game)
        return
    end  -- freeze hover etc. while menu is open

    local mx, my = love.mouse.getPosition()

    self:_calculatePerSecondStats(game)

    -- Scrollbar drag
    self.panel:update(my)

    -- Hover tracking: hitTest against last frame's components
    self.hovered_component = nil
    local last_hit = nil
    if self.panel:isInContentArea(mx, my) then
        local comps = self.panel:getComponents()
        if comps then
            local cy = self.panel:toContentY(my)
            local hit = CR.hitTest(comps, self.panel.x, self.panel.w, mx, cy, game)
            if hit then
                last_hit = hit
                if hit.id then self.hovered_component = hit end
            end
        end
    end
    -- Route last-frame hit through DataGrid so it can update row-hover +
    -- game.ui.hovered_entity (consumed by world renderers).
    DataGrid.applyHover(last_hit, game)
end

function UIManager:drawDataGridOverlay(game)
    if DataGrid.isChooserOpen() then
        ColumnChooser.draw(DataGrid.chooser, game)
    end
end

function UIManager:_calculatePerSecondStats(game)
    local stats = require("services.StatsService").computePerSecondStats(game.state)
    self.income_per_second = stats.income_per_second
    self.trips_per_second  = stats.trips_per_second
end

return UIManager
