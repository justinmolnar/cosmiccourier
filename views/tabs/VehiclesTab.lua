-- views/tabs/VehiclesTab.lua
-- Tab content is two datagrids: a buy/hire market, and the active fleet.
-- No "Selected Vehicle" detail panel — row highlight + map ring is the
-- selection signal; right-click a fleet row for actions.
local VehiclesTab = {}

function VehiclesTab.build(game, ui_manager)
    return {
        { type = "label", text = "Hire Vehicles",   style = "heading", h = 28 },
        { type = "datagrid", source = require("data.datagrids.vehicle_market") },
        { type = "divider", h = 10 },
        { type = "label", text = "Active Vehicles", style = "heading", h = 28 },
        { type = "datagrid", source = require("data.datagrids.vehicles") },
    }
end

return VehiclesTab
