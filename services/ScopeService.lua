-- services/ScopeService.lua
-- Centralized scope system. Single source of truth for what area the player
-- can operate in. All gameplay gating (pathfinding, interactions, trips)
-- goes through this service. Scope data lives in C.SCOPE (constants.lua).
local ScopeService = {}

--- Returns the current scope tier (integer 1-5), derived from owned licenses.
function ScopeService.getTier(game)
    if not game or not game.state then return 1 end
    return require("services.LicenseService").getCurrentTier(game)
end

--- Returns the current scope name ("district", "city", "region", "continent", "world").
function ScopeService.getCurrentScope(game)
    return game.C.SCOPE.NAMES[ScopeService.getTier(game)] or "world"
end

--- Returns the maximum allowed scope for trips and interactions.
function ScopeService.getMaxScope(game)
    return ScopeService.getCurrentScope(game)
end

--- Returns true if the given target scope is reachable at the current tier.
function ScopeService.canReach(game, target_scope)
    return (game.C.SCOPE.ORDER[target_scope] or 999) <= ScopeService.getTier(game)
end

--- Returns true if the given sub-cell (1-indexed) is inside the revealed scope area.
function ScopeService.isRevealed(game, gx, gy)
    local tier = ScopeService.getTier(game)
    if tier >= 5 then return true end
    local masks = game.scope_reveal_masks
    if not masks then return true end
    local mask = masks[tier]
    if not mask then return true end
    local mw = game.scope_mask_w
    local mh = game.scope_mask_h
    if not mw or not mh then return true end
    local mx, my = gx - 1, gy - 1
    if mx < 0 or my < 0 or mx >= mw or my >= mh then return false end
    local r = mask:getPixel(mx, my)
    return r > 0.5
end

return ScopeService
