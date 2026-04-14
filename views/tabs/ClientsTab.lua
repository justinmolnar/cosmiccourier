-- views/tabs/ClientsTab.lua
-- Two grids: buyable archetypes (market) + active clients.
-- No detail panels — selected client is indicated by row highlight + map ring.
local ClientsTab = {}

function ClientsTab.build(game, ui_manager)
    return {
        { type = "label", text = "Market",         style = "heading", h = 28 },
        { type = "datagrid", source = require("data.datagrids.client_market") },
        { type = "divider", h = 10 },
        { type = "label", text = "Active Clients", style = "heading", h = 28 },
        { type = "datagrid", source = require("data.datagrids.clients") },
    }
end

return ClientsTab
