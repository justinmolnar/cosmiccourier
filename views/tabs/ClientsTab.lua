-- views/tabs/ClientsTab.lua
local ClientsTab = {}

function ClientsTab.build(game, ui_manager)
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

return ClientsTab
