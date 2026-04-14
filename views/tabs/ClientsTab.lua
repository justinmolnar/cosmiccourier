-- views/tabs/ClientsTab.lua
local ClientsTab = {}

local Archetypes     = require("data.client_archetypes")
local LicenseService = require("services.LicenseService")

-- Look up the license whose scope_tier matches a given tier number, so the
-- gating label can name the required license instead of a bare number.
local function licenseNameForTier(tier)
    for _, lic in ipairs(LicenseService.getAll()) do
        if lic.scope_tier == tier then return lic.display_name end
    end
    return string.format("tier %d", tier)
end

function ClientsTab.build(game, ui_manager)
    local comps = {}
    local state = game.state
    local current_tier = LicenseService.getCurrentTier(game)

    table.insert(comps, { type = "label", text = "Market", style = "heading", h = 28 })

    for _, archetype in ipairs(Archetypes.list) do
        local tier_ok   = current_tier >= archetype.required_scope_tier
        local can_afford = (state.money or 0) >= (archetype.market_cost or 0)
        local primary = string.format("%s Market for %s  ($%d)",
            archetype.icon or "", archetype.display_name, archetype.market_cost or 0)
        local secondary
        if not tier_ok then
            secondary = string.format("Requires %s", licenseNameForTier(archetype.required_scope_tier))
        else
            secondary = archetype.description or ""
        end
        table.insert(comps, {
            type     = "button",
            id       = "buy_client",
            data     = { archetype_id = archetype.id },
            disabled = not (tier_ok and can_afford),
            lines    = {
                { text = primary,   style = "body" },
                { text = secondary, style = "small" },
            },
        })
    end

    table.insert(comps, { type = "divider", h = 8 })
    table.insert(comps, { type = "label", text = "Active Clients", style = "heading", h = 28 })

    if #game.entities.clients == 0 then
        table.insert(comps, { type = "label", text = "No clients.", style = "muted", h = 24 })
    else
        for i, client in ipairs(game.entities.clients) do
            local archetype = Archetypes.by_id[client.archetype or ""]
            local icon = archetype and archetype.icon or ""
            local name = archetype and archetype.display_name or (client.archetype or "Client")
            table.insert(comps, {
                type  = "label",
                text  = string.format("  %s %s #%d", icon, name, i),
                h     = 22,
            })
        end
    end
    return comps
end

return ClientsTab
