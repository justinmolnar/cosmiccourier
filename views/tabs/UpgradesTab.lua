-- views/tabs/UpgradesTab.lua
local UpgradesTab = {}

local ICON_ROW_H = 96   -- must match ComponentRenderer ICON_SIZE(64) + label + padding

function UpgradesTab.build(game, ui_manager)
    local ScopeService = require("services.ScopeService")
    local tier = ScopeService.getTier(game)
    local comps = {}
    for _, category in ipairs(game.state.Upgrades.categories) do
        local items = {}
        for _, sub_type in ipairs(category.sub_types) do
            if not sub_type.required_scope or tier >= sub_type.required_scope then
                table.insert(items, {
                    id   = "open_upgrade",
                    data = sub_type,
                    icon = sub_type.icon,
                    name = sub_type.name,
                })
            end
        end
        if #items > 0 then
            table.insert(comps, { type = "label", text = category.name, style = "heading", h = 28 })
            table.insert(comps, { type = "icon_row", items = items, h = ICON_ROW_H })
            table.insert(comps, { type = "spacer", h = 8 })
        end
    end
    return comps
end

return UpgradesTab
