-- views/tabs/DepotTab.lua
local DepotTab = {}

function DepotTab.build(game, ui_manager)
    local comps = {}
    local depot = ui_manager.panel.depot_view

    if not depot then
        table.insert(comps, { type = "label", text = "No Depot Selected", style = "muted", h = 24 })
        local is_build_mode = game.entities.build_depot_mode
        table.insert(comps, {
            type  = "button",
            id    = "toggle_build_depot_mode",
            data  = {},
            lines = {
                { text = is_build_mode and "Cancel Build Mode" or "🏗️ Build New Depot ($500)", style = "body" },
            },
        })
        return comps
    end

    local city_map = depot:getCity(game)
    local district = depot:getDistrict(game) or "Unknown District"

    table.insert(comps, { type = "label", text = "Depot Details", style = "heading", h = 28 })
    
    table.insert(comps, {
        type  = "button",
        id    = "none",
        data  = {},
        lines = {
            { text = "🏢 " .. (depot.id or "Local Depot"), style = "body" },
            { text = string.format("  District: %s", string.upper(district)), style = "small" },
        },
    })
    table.insert(comps, { type = "divider", h = 10 })

    table.insert(comps, { type = "label", text = "Analytics", style = "heading", h = 24 })
    
    local stats = depot.analytics or { trips_completed = 0, income_generated = 0 }
    local assigned_count = depot.assigned_vehicles and #depot.assigned_vehicles or 0

    table.insert(comps, { type = "label", text = string.format("Vehicles Assigned: %d", assigned_count), style = "body", h = 20 })
    table.insert(comps, { type = "label", text = string.format("Trips Completed: %d", stats.trips_completed), style = "body", h = 20 })
    table.insert(comps, { type = "label", text = string.format("Income Generated: $%d", stats.income_generated), style = "body", h = 20 })
    
    table.insert(comps, { type = "divider", h = 10 })
    
    table.insert(comps, { type = "label", text = "Actions", style = "heading", h = 24 })

    local sorted = {}
    for id, vcfg in pairs(game.C.VEHICLES) do
        table.insert(sorted, { id = id, vcfg = vcfg })
    end
    table.sort(sorted, function(a, b) return a.vcfg.base_cost < b.vcfg.base_cost end)

    local depot_district = depot:getDistrict(game)

    for _, entry in ipairs(sorted) do
        local vid  = entry.id:lower()
        local vcfg = entry.vcfg
        local cost = game.state.costs[vid] or vcfg.base_cost
        local can_afford = game.state.money >= cost

        -- Check required_depot_district (e.g. bikes need a downtown depot)
        local district_ok = true
        local district_reason = nil
        if vcfg.required_depot_district then
            if depot_district ~= vcfg.required_depot_district then
                district_ok = false
                district_reason = "Requires " .. vcfg.required_depot_district .. " depot"
            end
        end

        local disabled = not can_afford or not district_ok
        local label = string.format("%s Hire %s ($%d)", vcfg.icon, vcfg.display_name, cost)
        local lines = { { text = label, style = "body" } }
        if district_reason then
            table.insert(lines, { text = district_reason, style = "small" })
        end

        table.insert(comps, {
            type     = "button",
            id       = "hire_vehicle_at_depot",
            disabled = disabled,
            data     = { vehicle_id = vid, depot = depot },
            lines    = lines,
        })
    end

    table.insert(comps, { type = "divider", h = 10 })
    local market_cost = 100
    table.insert(comps, {
        type     = "button",
        id       = "market_for_clients",
        disabled = game.state.money < market_cost,
        data     = { depot = depot },
        lines    = {
            { text = "📢 Market for Clients ($" .. market_cost .. ")", style = "body" },
            { text = "Attract a new client to this district", style = "small" },
        },
    })

    return comps
end

return DepotTab
