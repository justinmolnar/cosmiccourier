-- views/tabs/DepotTab.lua
-- No "Selected Depot" detail panel. Grid of all depots with analytics columns.
-- When one is selected, a hire-vehicle grid appears below; its purchase target
-- is the selected depot (vehicle_market datasource reads selected_depot).
local DepotTab = {}

function DepotTab.build(game, ui_manager)
    local comps = {
        { type = "label", text = "Depots", style = "heading", h = 28 },
        { type = "datagrid", source = require("data.datagrids.depots") },
    }

    -- Build-new-depot affordance — entrypoint for placing a fresh depot.
    local is_build_mode = game.entities.build_depot_mode
    table.insert(comps, { type = "divider", h = 8 })
    table.insert(comps, {
        type  = "button",
        id    = "toggle_build_depot_mode",
        data  = {},
        lines = {
            { text = is_build_mode and "Cancel Build Mode" or "🏗️ Build New Depot ($500)", style = "body" },
        },
    })

    if game.entities.selected_depot then
        table.insert(comps, { type = "divider", h = 10 })
        table.insert(comps, { type = "label", text = "Hire at Selected Depot", style = "heading", h = 28 })
        table.insert(comps, { type = "datagrid", source = require("data.datagrids.vehicle_market") })
    end

    return comps
end

return DepotTab
