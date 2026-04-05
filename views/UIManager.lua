-- views/UIManager.lua
local UIManager = {}
UIManager.__index = UIManager

local CR = require("views.ComponentRenderer")

local PANEL_Y    = 120    -- pixels below top of sidebar where panel begins
local ICON_ROW_H = 96     -- must match ComponentRenderer ICON_SIZE(64) + label + padding

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
        build = function(g) return instance:_buildTripsTab(g) end })
    instance.panel:registerTab({ id = "vehicles", label = "Vehicles", icon = "🚗", priority = 2,
        build = function(g) return instance:_buildVehiclesTab(g) end })
    instance.panel:registerTab({ id = "upgrades", label = "Upgrades", icon = "⬆️", priority = 3,
        build = function(g) return instance:_buildUpgradesTab(g) end })
    instance.panel:registerTab({ id = "clients",  label = "Clients",  icon = "🏢", priority = 4,
        build = function(g) return instance:_buildClientsTab(g) end })

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
                -- Backward compat for GameView trip-path preview
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

-- ─── Tab builders ────────────────────────────────────────────────────────────

function UIManager:_buildTripsTab(game)
    local comps   = {}
    local pending = game.entities.trips.pending

    local hovered_idx = nil
    local hc = self.hovered_component
    if hc and hc.id == "assign_trip" and hc.data then
        hovered_idx = hc.data.index
    end

    if #pending == 0 then
        table.insert(comps, { type = "label", text = "No pending trips.", style = "muted", h = 30 })
        return comps
    end

    local mode_text = { road = "road", rail = "rail", water = "water", air = "air" }
    local status_text = { done = "done", transit = "moving", waiting = "waiting", pending = "queued" }

    for i, trip in ipairs(pending) do
        local current_bonus = math.floor(trip:getCurrentBonus())
        local lines = {
            { text = string.format("Trip %d:  $%d base  +  $%d bonus", i, trip.base_payout, current_bonus),
              style = "body" },
        }
        for leg_idx, leg in ipairs(trip.legs) do
            local mode = mode_text[leg.transport_mode] or leg.transport_mode or "road"
            local status
            if leg_idx < trip.current_leg then
                status = "done"
            elseif leg_idx == trip.current_leg then
                status = trip.is_in_transit and "moving" or "waiting"
            else
                status = "queued"
            end
            table.insert(lines, {
                text  = string.format("  leg %d  [%s]  %s", leg_idx, mode, status),
                style = "small",
            })
        end
        table.insert(comps, {
            type    = "button",
            id      = "assign_trip",
            data    = { index = i },
            hovered = (i == hovered_idx),
            lines   = lines,
        })
    end
    return comps
end

function UIManager:_buildVehiclesTab(game)
    local comps = {}
    local state = game.state

    -- Hire section
    table.insert(comps, { type = "label", text = "Hire Vehicles", style = "heading", h = 28 })

    -- Sort by base_cost for stable ordering
    local sorted = {}
    for id, vcfg in pairs(game.C.VEHICLES) do
        table.insert(sorted, { id = id, vcfg = vcfg })
    end
    table.sort(sorted, function(a, b) return a.vcfg.base_cost < b.vcfg.base_cost end)

    for _, entry in ipairs(sorted) do
        local vid  = entry.id:lower()
        local vcfg = entry.vcfg
        local cost = state.costs[vid] or vcfg.base_cost
        table.insert(comps, {
            type  = "button",
            id    = "hire_vehicle",
            data  = { vehicle_id = vid },
            lines = {
                { text = string.format("%s Hire %s  ($%d)", vcfg.icon, vcfg.display_name, cost), style = "body" },
            },
        })
    end

    -- Active vehicle list
    table.insert(comps, { type = "divider", h = 10 })
    table.insert(comps, { type = "label", text = "Active Vehicles", style = "heading", h = 28 })

    local hovered_vid = nil
    local hc = self.hovered_component
    if hc and hc.id == "select_vehicle" and hc.data and hc.data.vehicle then
        hovered_vid = hc.data.vehicle.id
    end

    if #game.entities.vehicles == 0 then
        table.insert(comps, { type = "label", text = "No vehicles hired.", style = "muted", h = 24 })
    else
        for _, v in ipairs(game.entities.vehicles) do
            local cap_used = #v.cargo + #v.trip_queue
            local cap_max  = state.upgrades.vehicle_capacity
            local sel      = (game.entities.selected_vehicle == v) and "▶ " or ""
            table.insert(comps, {
                type    = "button",
                id      = "select_vehicle",
                data    = { vehicle = v },
                hovered = (v.id == hovered_vid),
                lines   = {
                    { text = string.format("%s%s %s #%d", sel, v:getIcon(), v.type, v.id), style = "body" },
                    { text = string.format("  %s  |  cap %d/%d", v.state.name, cap_used, cap_max), style = "small" },
                },
            })
        end
    end

    return comps
end

function UIManager:_buildUpgradesTab(game)
    local comps = {}
    for _, category in ipairs(game.state.Upgrades.categories) do
        table.insert(comps, { type = "label", text = category.name, style = "heading", h = 28 })
        local items = {}
        for _, sub_type in ipairs(category.sub_types) do
            table.insert(items, {
                id   = "open_upgrade",
                data = sub_type,
                icon = sub_type.icon,
                name = sub_type.name,
            })
        end
        if #items > 0 then
            table.insert(comps, { type = "icon_row", items = items, h = ICON_ROW_H })
        end
        table.insert(comps, { type = "spacer", h = 8 })
    end
    return comps
end

function UIManager:_buildClientsTab(game)
    local comps = {}
    local state = game.state
    local cost  = state.costs.client or 500

    table.insert(comps, {
        type  = "button",
        id    = "buy_client",
        data  = {},
        lines = {
            { text = string.format("Market for New Client  ($%d)", cost), style = "body" },
        },
    })
    table.insert(comps, { type = "divider", h = 8 })
    table.insert(comps, { type = "label", text = "Active Clients", style = "heading", h = 28 })

    if #game.entities.clients == 0 then
        table.insert(comps, { type = "label", text = "No clients.", style = "muted", h = 24 })
    else
        for i = 1, #game.entities.clients do
            table.insert(comps, { type = "label", text = string.format("Client #%d", i), h = 22 })
        end
    end
    return comps
end

return UIManager
