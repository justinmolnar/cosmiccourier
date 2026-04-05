-- views/UIManager.lua
local UIManager = {}
UIManager.__index = UIManager

local CR           = require("views.ComponentRenderer")
local TripsTab     = require("views.tabs.TripsTab")
local VehiclesTab  = require("views.tabs.VehiclesTab")
local UpgradesTab  = require("views.tabs.UpgradesTab")
local ClientsTab   = require("views.tabs.ClientsTab")

local PANEL_Y = 120   -- pixels below top of sidebar where panel begins

function UIManager:new(C, game)
    local Panel        = require("views.Panel")
    local ModalManager = require("views.modal_manager")

    local instance = setmetatable({}, UIManager)

    instance.hovered_component  = nil
    instance.hovered_trip_index = nil   -- derived from hovered_component; read by GameView
    instance.income_per_second  = 0
    instance.trips_per_second   = 0

    local screen_h = love.graphics.getHeight()
    instance.panel = Panel:new(0, PANEL_Y, C.UI.SIDEBAR_WIDTH, screen_h - PANEL_Y)

    instance.panel:registerTab({ id = "trips",    label = "Trips",    icon = "📦", priority = 1,
        build = function(g) return TripsTab.build(g, instance) end })
    instance.panel:registerTab({ id = "vehicles", label = "Vehicles", icon = "🚗", priority = 2,
        build = function(g) return VehiclesTab.build(g, instance) end })
    instance.panel:registerTab({ id = "upgrades", label = "Upgrades", icon = "⬆️", priority = 3,
        build = function(g) return UpgradesTab.build(g, instance) end })
    instance.panel:registerTab({ id = "clients",  label = "Clients",  icon = "🏢", priority = 4,
        build = function(g) return ClientsTab.build(g, instance) end })

    instance.modal_manager = ModalManager:new()

    return instance
end

-- ─── Update ──────────────────────────────────────────────────────────────────

function UIManager:handle_scroll(dy)
    self.panel:handleScroll(dy)
end

function UIManager:handle_mouse_up(x, y, button)
    if self.modal_manager:handle_mouse_up(x, y) then return end
    self.panel:handleMouseUp()
end

function UIManager:update(dt, game)
    self.modal_manager:update(dt, game)
    if self.modal_manager:isActive() then return end

    local mx, my = love.mouse.getPosition()

    self:_calculatePerSecondStats(game)

    -- Scrollbar drag
    self.panel:update(my)

    -- Hover tracking: hitTest against last frame's components
    self.hovered_component  = nil
    self.hovered_trip_index = nil
    if self.panel:isInContentArea(mx, my) then
        local comps = self.panel:getComponents()
        if comps then
            local cy = self.panel:toContentY(my)
            local hit = CR.hitTest(comps, self.panel.x, self.panel.w, mx, cy)
            if hit and hit.id then
                self.hovered_component = hit
                if hit.id == "assign_trip" and hit.data then
                    self.hovered_trip_index = hit.data.index
                end
            end
        end
    end
end

function UIManager:_calculatePerSecondStats(game)
    local stats = require("services.StatsService").computePerSecondStats(game.state)
    self.income_per_second = stats.income_per_second
    self.trips_per_second  = stats.trips_per_second
end

return UIManager
