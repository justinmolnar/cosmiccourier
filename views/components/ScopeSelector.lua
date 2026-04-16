-- views/components/ScopeSelector.lua
-- Helpers for the scope_selector ComponentRenderer type. The component itself
-- (header bar render + hit detection) lives in ComponentRenderer; this module
-- exposes the dropdown / context-menu items used to change selection.

local ScopeSelectionService = require("services.ScopeSelectionService")

local ScopeSelector = {}

-- Build ContextMenu items for the city list. UIController calls this from
-- the scope_select_open hit dispatch and feeds the result into
-- ui_manager:showContextMenu.
function ScopeSelector.buildCityMenuItems(game)
    local items = {}
    local current = ScopeSelectionService.getSelectedCityIdx(game)
    for _, entry in ipairs(ScopeSelectionService.getSelectableCities(game)) do
        local cmap = entry.city_map
        local name = cmap.name or cmap.id or ("City " .. tostring(entry.idx))
        local is_current = (entry.idx == current)
        items[#items + 1] = {
            label  = is_current and ("✓ " .. name) or ("   " .. name),
            action = function()
                ScopeSelectionService.setSelectedCity(game, entry.idx)
            end,
        }
    end
    return items
end

-- Pretty name for the currently-selected city, for the scope_selector label.
function ScopeSelector.selectedCityName(game)
    local cmap = ScopeSelectionService.getSelectedCity(game)
    if not cmap then return "—" end
    return cmap.name or cmap.id or "City"
end

return ScopeSelector
