-- views/tabs/VehiclesTab.lua
local VehiclesTab = {}

function VehiclesTab.build(game, ui_manager)
    local comps = {}
    local state = game.state

    -- Selected vehicle detail panel
    local sel = game.entities.selected_vehicle
    if sel then
        table.insert(comps, { type = "label", text = "Selected Vehicle", style = "heading", h = 28 })
        local cap_used = #sel.cargo + #sel.trip_queue
        local cap_max  = state.upgrades.vehicle_capacity
        table.insert(comps, {
            type  = "button",
            id    = "deselect_vehicle",
            data  = {},
            lines = {
                { text = string.format("%s %s #%d", sel:getIcon(), sel.type, sel.id), style = "body" },
                { text = string.format("  %s  |  cap %d/%d", sel.state.name, cap_used, cap_max), style = "small" },
            },
        })
        if cap_used > 0 then
            table.insert(comps, {
                type  = "button",
                id    = "unassign_vehicle",
                data  = { vehicle = sel },
                lines = {
                    { text = "Return trip to queue", style = "body" },
                },
            })
        end
        table.insert(comps, { type = "divider", h = 10 })
    end

    -- Hire section
    table.insert(comps, { type = "label", text = "Hire Vehicles", style = "heading", h = 28 })

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
    local hc = ui_manager.hovered_component
    if hc and hc.id == "select_vehicle" and hc.data and hc.data.vehicle then
        hovered_vid = hc.data.vehicle.id
    end

    if #game.entities.vehicles == 0 then
        table.insert(comps, { type = "label", text = "No vehicles hired.", style = "muted", h = 24 })
    else
        for _, v in ipairs(game.entities.vehicles) do
            local cap_used = #v.cargo + #v.trip_queue
            local cap_max  = state.upgrades.vehicle_capacity
            local is_sel   = (game.entities.selected_vehicle == v)
            local sel_mark = is_sel and "▶ " or ""
            table.insert(comps, {
                type    = "button",
                id      = "select_vehicle",
                data    = { vehicle = v },
                hovered = (v.id == hovered_vid),
                lines   = {
                    { text = string.format("%s%s %s #%d", sel_mark, v:getIcon(), v.type, v.id), style = "body" },
                    { text = string.format("  %s  |  cap %d/%d", v.state.name, cap_used, cap_max), style = "small" },
                },
            })
        end
    end

    return comps
end

return VehiclesTab
