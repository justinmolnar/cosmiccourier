-- services/ScopeSelectionService.lua
-- Tiny state manager over the currently-focused city for the City tab.
-- Stored as game.state.ui.selected_city_id (1-based index into
-- game.maps.all_cities). Defaults to the city containing the first depot.

local ScopeSelectionService = {}

local function _ensureUiTable(game)
    if not game.state then return nil end
    game.state.ui = game.state.ui or {}
    return game.state.ui
end

-- Default selection: the city containing entities.depots[1] (the player's
-- starter depot). Falls back to city index 1 if that lookup fails.
local function _defaultCityIdx(game)
    local depot = game.entities and game.entities.depots and game.entities.depots[1]
    if depot and depot.getCity then
        local cmap = depot:getCity(game)
        if cmap then
            for i, m in ipairs(game.maps.all_cities or {}) do
                if m == cmap then return i end
            end
        end
    end
    return 1
end

-- ─── Public API ─────────────────────────────────────────────────────────────

function ScopeSelectionService.getSelectedCityIdx(game)
    local ui = _ensureUiTable(game)
    if ui and ui.selected_city_id then return ui.selected_city_id end
    return _defaultCityIdx(game)
end

function ScopeSelectionService.getSelectedCity(game)
    local idx = ScopeSelectionService.getSelectedCityIdx(game)
    local all = game.maps and game.maps.all_cities or {}
    return all[idx]
end

function ScopeSelectionService.setSelectedCity(game, city_idx)
    local ui = _ensureUiTable(game)
    if not ui then return end
    ui.selected_city_id = city_idx
end

-- List of cities the player can pick between. At tier 1 the player operates
-- in a single city; at tier 2+ the list expands to any city the player has
-- a depot in. Returns { { idx, city_map }, ... } in all_cities order.
function ScopeSelectionService.getSelectableCities(game)
    local all = game.maps and game.maps.all_cities or {}
    local LicenseService = require("services.LicenseService")
    local tier = LicenseService.getCurrentTier(game)

    local operated = {}
    for _, d in ipairs(game.entities and game.entities.depots or {}) do
        if d.getCity then
            local cmap = d:getCity(game)
            if cmap then operated[cmap] = true end
        end
    end

    local out = {}
    for i, cmap in ipairs(all) do
        -- Tier 1 → only the starter city (the one containing your depot).
        -- Tier 2+ → every city you operate in.
        if tier >= 2 and operated[cmap] then
            out[#out + 1] = { idx = i, city_map = cmap }
        elseif tier < 2 and operated[cmap] then
            out[#out + 1] = { idx = i, city_map = cmap }
            break
        end
    end
    -- Always include the selected city even if the player doesn't operate there
    -- (click-to-inspect on the map should still work on neighbor cities).
    local sel = ScopeSelectionService.getSelectedCityIdx(game)
    local already_in = false
    for _, e in ipairs(out) do if e.idx == sel then already_in = true; break end end
    if not already_in and all[sel] then
        out[#out + 1] = { idx = sel, city_map = all[sel] }
    end
    return out
end

return ScopeSelectionService
