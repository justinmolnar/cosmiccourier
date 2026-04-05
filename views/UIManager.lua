-- views/UIManager.lua
local UIManager = {}
UIManager.__index = UIManager

local PANEL_Y = 120   -- pixels below top of sidebar where panel begins

function UIManager:new(C, game)
    local Panel       = require("views.Panel")
    local ModalManager = require("views.modal_manager")

    local instance = setmetatable({}, UIManager)

    instance.hovered_trip_index = nil

    local screen_h = love.graphics.getHeight()
    instance.panel = Panel:new(0, PANEL_Y, C.UI.SIDEBAR_WIDTH, screen_h - PANEL_Y)

    -- Register the four tabs. draw functions call existing panel views (Phase 1 scaffolding).
    local TripsPanelView    = require("views.components.TripsPanelView")
    local UpgradesPanelView = require("views.components.UpgradesPanelView")
    local VehiclesPanelView = require("views.components.VehiclesPanelView")
    local ClientsPanelView  = require("views.components.ClientsPanelView")

    instance.panel:registerTab({ id = "trips",    label = "Trips",    icon = "📦", priority = 1,
        draw = function(g) TripsPanelView.draw(g, instance) end })
    instance.panel:registerTab({ id = "vehicles", label = "Vehicles", icon = "🚗", priority = 2,
        draw = function(g) VehiclesPanelView.draw(g, instance) end })
    instance.panel:registerTab({ id = "upgrades", label = "Upgrades", icon = "⬆️", priority = 3,
        draw = function(g) UpgradesPanelView.draw(g, instance) end })
    instance.panel:registerTab({ id = "clients",  label = "Clients",  icon = "🏢", priority = 4,
        draw = function(g) ClientsPanelView.draw(g, instance) end })

    instance.modal_manager = ModalManager:new()

    instance.layout_cache = {}
    instance.income_per_second = 0
    instance.trips_per_second  = 0
    instance.accordion_stats = {
        trips    = "",
        upgrades = "",
        vehicles = "",
        clients  = "",
    }
    instance._layout_key = nil
    instance._stats_key  = nil

    return instance
end

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

    local C  = game.C
    local mx, my = love.mouse.getPosition()

    self:_calculatePerSecondStats(game)

    local skey = self:_buildStatsKey(game)
    if skey ~= self._stats_key then
        self:_calculateAccordionStats(game)
        self._stats_key = skey
    end

    -- Update panel scrollbar drag
    self.panel:update(my)

    -- Update per-tab content heights
    local upgrades_h = self:_calculateUpgradesLayoutHeight(game.state.Upgrades.categories)
    local num_vehicle_types = 0
    for _ in pairs(game.C.VEHICLES) do num_vehicle_types = num_vehicle_types + 1 end

    self.panel:updateScrollTotalH("trips",    #game.entities.trips.pending * 50)
    self.panel:updateScrollTotalH("upgrades", upgrades_h)
    self.panel:updateScrollTotalH("vehicles", (num_vehicle_types * 35) + 15 + (#game.entities.vehicles * 30))
    self.panel:updateScrollTotalH("clients",  (#game.entities.clients * 20) + 40)

    -- Rebuild layout when entity counts or active tab changes
    local lkey = self:_buildLayoutKey(game)
    if lkey ~= self._layout_key then
        self:_doLayout(game)
        self._layout_key = lkey
    end

    -- Hovered trip index (for click-to-assign)
    self.hovered_trip_index = nil
    if self.panel.active_tab_id == "trips" and self.panel:isInContentArea(mx, my) then
        local y_in_content = self.panel:toContentY(my)
        local index = math.floor(y_in_content / 50) + 1
        if index >= 1 and index <= #game.entities.trips.pending then
            self.hovered_trip_index = index
        end
    end
end

function UIManager:_calculateUpgradesLayoutHeight(categories)
    local total_h = 10
    for _ in ipairs(categories) do
        total_h = total_h + 25 + 79   -- category header + icon row
    end
    return total_h
end

function UIManager:_calculatePerSecondStats(game)
    local stats = require("services.StatsService").computePerSecondStats(game.state)
    self.income_per_second = stats.income_per_second
    self.trips_per_second  = stats.trips_per_second
end

function UIManager:_calculateAccordionStats(game)
    local state = game.state
    local is_downtown = (game.camera.scale >= game.C.ZOOM.FOG_THRESHOLD)

    local core_trips, city_trips = 0, 0
    for _, trip in ipairs(game.entities.trips.pending) do
        local final_leg = trip.legs[#trip.legs]
        if final_leg then
            if game.maps.city:isPlotInDowntown(final_leg.end_plot) then
                core_trips = core_trips + 1
            else
                city_trips = city_trips + 1
            end
        end
    end
    self.accordion_stats.trips = string.format("%d (🏢%d 🏙️%d)", #game.entities.trips.pending, core_trips, city_trips)
    self.accordion_stats.upgrades = ""

    local vehicle_counts = {}
    local idle_count = 0
    for _, v in ipairs(game.entities.vehicles) do
        local vehicle_is_in_downtown = game.maps.city:isPlotInDowntown(v.grid_anchor)
        if (is_downtown and vehicle_is_in_downtown) or not is_downtown then
            vehicle_counts[v.type] = (vehicle_counts[v.type] or 0) + 1
            if v.state.name == "Idle" then idle_count = idle_count + 1 end
        end
    end
    local parts = {}
    for id, vcfg in pairs(game.C.VEHICLES) do
        local cnt = vehicle_counts[id:lower()] or 0
        table.insert(parts, string.format("%s%d", vcfg.icon, cnt))
    end
    table.insert(parts, string.format("😴%d", idle_count))
    self.accordion_stats.vehicles = table.concat(parts, " ")

    local client_count = 0
    for _, c in ipairs(game.entities.clients) do
        local client_is_in_downtown = game.maps.city:isPlotInDowntown(c.plot)
        if (is_downtown and client_is_in_downtown) or not is_downtown then
            client_count = client_count + 1
        end
    end
    self.accordion_stats.clients = string.format("%d (%.2f t/s)", client_count, self.trips_per_second)
end

function UIManager:_buildLayoutKey(game)
    local C = game.C
    return (#game.entities.trips.pending)
        .. "|" .. (#game.entities.vehicles)
        .. "|" .. (#game.entities.clients)
        .. "|" .. C.UI.SIDEBAR_WIDTH
        .. "|" .. (self.panel.active_tab_id or "")
end

function UIManager:_buildStatsKey(game)
    local is_dt = (game.camera.scale >= game.C.ZOOM.FOG_THRESHOLD) and "1" or "0"
    return (#game.entities.trips.pending) .. "|" .. (#game.entities.vehicles)
        .. "|" .. (#game.entities.clients) .. "|" .. is_dt
end

-- All layout positions are relative to y=0 (top of panel content area).
-- Panel:draw applies translate(0, content_y - scroll_y) before calling tab draw.
function UIManager:_doLayout(game)
    self.layout_cache = { trips = {}, upgrades = { buttons = {} }, vehicles = {}, clients = {}, buttons = {} }
    local C = game.C
    local p = C.UI.PADDING
    local w = C.UI.SIDEBAR_WIDTH - (p * 2)

    -- Trips tab (items stacked from y=0)
    for i, trip in ipairs(game.entities.trips.pending) do
        self.layout_cache.trips[i] = { trip = trip, x = p, y = (i - 1) * 50, w = w, h = 50 }
    end

    -- Upgrades tab
    local upgrade_y = 10
    for _, category in ipairs(game.state.Upgrades.categories) do
        self.layout_cache.upgrades[category.id] = { type = "header", text = category.name, x = p, y = upgrade_y, w = w }
        upgrade_y = upgrade_y + 25
        local icon_x = p + 15
        for _, sub_type in ipairs(category.sub_types) do
            table.insert(self.layout_cache.upgrades.buttons, {
                id    = sub_type.id,
                icon  = sub_type.icon,
                name  = sub_type.name,
                x     = icon_x,
                y     = upgrade_y,
                w     = 64,
                h     = 64,
                event = "ui_upgrade_button_clicked",
                data  = sub_type,
            })
            icon_x = icon_x + 64 + 15
        end
        upgrade_y = upgrade_y + 64 + 15
    end

    -- Vehicles tab
    self.layout_cache.buttons.hire_vehicles = {}
    local btn_y = 5
    for id, _ in pairs(game.C.VEHICLES) do
        local vid = id:lower()
        self.layout_cache.buttons.hire_vehicles["hire_" .. vid] = {
            x = p + 5, y = btn_y, w = w - 10, h = 30,
            vehicle_id = vid,
        }
        btn_y = btn_y + 35
    end
    local vehicle_list_y = btn_y + 5
    for i, vehicle in ipairs(game.entities.vehicles) do
        self.layout_cache.vehicles[i] = {
            vehicle = vehicle,
            x = p, y = vehicle_list_y + (i - 1) * 30, w = w, h = 30,
        }
    end

    -- Clients tab
    self.layout_cache.buttons.buy_client = { x = p + 5, y = 5, w = w - 10, h = 30 }
    for i, client in ipairs(game.entities.clients) do
        self.layout_cache.clients[i] = {
            client = client,
            x = p, y = 40 + (i - 1) * 20, w = w, h = 20,
        }
    end
end

return UIManager
