-- data/datagrids/client_market.lua
-- Buy-an-archetype market grid. Shared by ClientsTab (primary seller) and
-- potentially DepotTab (if depot-scoped purchasing returns). Row click
-- publishes the existing ui_buy_client_clicked event.

local Archetypes     = require("data.client_archetypes")
local LicenseService = require("services.LicenseService")

local function licenseNameForTier(tier)
    for _, lic in ipairs(LicenseService.getAll()) do
        if lic.scope_tier == tier then return lic.display_name end
    end
    return string.format("tier %d", tier)
end

local function isAffordable(item, game)
    local tier_ok    = LicenseService.getCurrentTier(game) >= (item.required_scope_tier or 0)
    local money_ok   = (game.state.money or 0) >= (item.market_cost or 0)
    return tier_ok and money_ok, tier_ok, money_ok
end

local columns = {
    {
        id = "icon", label = " ", width = 26, min_width = 20, align = "center",
        draw = function(x, y, w, h, item, game)
            love.graphics.setFont(game.fonts.ui)
            local affordable, tier_ok = isAffordable(item, game)
            love.graphics.setColor(affordable and 1 or 0.5, affordable and 1 or 0.5, affordable and 1 or 0.5)
            love.graphics.printf(item.icon or "?", x, y + 2, w, "center")
        end,
    },
    {
        id = "name", label = "Archetype", width = 110, min_width = 60,
        draw = function(x, y, w, h, item, game)
            local affordable, tier_ok = isAffordable(item, game)
            love.graphics.setFont(game.fonts.ui_small)
            if not tier_ok then
                love.graphics.setColor(0.55, 0.55, 0.55)
            elseif not affordable then
                love.graphics.setColor(0.9, 0.6, 0.3)
            else
                love.graphics.setColor(1, 1, 1)
            end
            love.graphics.printf(item.display_name or item.id,
                x + 4, y + 4, w - 8, "left")
        end,
        sort_key = function(item) return item.display_name or item.id end,
    },
    {
        id = "tier", label = "Req", width = 85, min_width = 40,
        format = function(item, game)
            local tier = item.required_scope_tier or 0
            if tier == 0 then return "—" end
            return licenseNameForTier(tier)
        end,
        sort_key = function(item) return item.required_scope_tier or 0 end,
    },
    {
        id = "cost", label = "Cost", width = 60, min_width = 40, align = "right",
        format   = function(item) return string.format("$%d", item.market_cost or 0) end,
        sort_key = function(item) return item.market_cost or 0 end,
    },
    {
        id = "capacity", label = "Cap", width = 40, min_width = 30, align = "right",
        format   = function(item) return tostring(item.capacity or "?") end,
        sort_key = function(item) return item.capacity or 0 end,
    },
    {
        id = "cargo", label = "Cargo", width = 55, min_width = 40, align = "right",
        format = function(item)
            local r = item.cargo_size_range
            if not r then return "—" end
            if r[1] == r[2] then return tostring(r[1]) end
            return string.format("%d–%d", r[1], r[2])
        end,
        sort_key = function(item) return item.cargo_size_range and item.cargo_size_range[1] or 0 end,
    },
    {
        id = "payout", label = "× $", width = 50, min_width = 30, align = "right",
        format   = function(item) return string.format("%.2f", item.payout_multiplier or 1) end,
        sort_key = function(item) return item.payout_multiplier or 0 end,
    },
    {
        id = "spawn", label = "Spawn", width = 60, min_width = 40, align = "right",
        visible_default = false,
        format = function(item)
            local r = item.base_spawn_seconds
            if not r then return "—" end
            return string.format("%d–%ds", r[1], r[2])
        end,
        sort_key = function(item) return item.base_spawn_seconds and item.base_spawn_seconds[1] or 0 end,
    },
}

return {
    id            = "client_market",
    items_fn      = function(game) return Archetypes.list end,
    row_id        = function(item) return item.id end,
    on_row_click  = function(item, game)
        local affordable = isAffordable(item, game)
        if not affordable then return end
        game.EventBus:publish("ui_buy_client_clicked", { archetype_id = item.id })
    end,
    empty_message = "No archetypes available.",
    default_sort  = { column = "tier", direction = "asc" },
    columns       = columns,
}
