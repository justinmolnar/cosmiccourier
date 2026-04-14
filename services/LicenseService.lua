-- services/LicenseService.lua
-- Single authority for operating licenses. A license is a pure scope gate:
-- it raises scope_tier on purchase and nothing else. No pack grants, no
-- vehicle unlocks, no upgrade side effects.
--
-- Source of truth: game.state.licenses (set of owned license ids).
-- Scope tier derives from the max tier across owned licenses.

local LicenseService = {}

local _cached
local function getData()
    if not _cached then _cached = require("data.licenses") end
    return _cached
end

--- Returns the licenses data table (all definitions, sorted by tier).
function LicenseService.getAll()
    return getData()
end

--- Returns the license definition for a given id, or nil.
function LicenseService.get(license_id)
    for _, lic in ipairs(getData()) do
        if lic.id == license_id then return lic end
    end
    return nil
end

--- True if the player currently owns the given license.
function LicenseService.isOwned(game, license_id)
    local licenses = game and game.state and game.state.licenses
    return licenses ~= nil and licenses[license_id] == true
end

--- Returns the current scope tier derived from owned licenses. Defaults to 1.
function LicenseService.getCurrentTier(game)
    local licenses = game and game.state and game.state.licenses
    if not licenses then return 1 end
    local best = 1
    for _, lic in ipairs(getData()) do
        if licenses[lic.id] and lic.scope_tier > best then
            best = lic.scope_tier
        end
    end
    return best
end

--- Returns the owned license definition at the current tier, or nil.
function LicenseService.getCurrent(game)
    local tier = LicenseService.getCurrentTier(game)
    for _, lic in ipairs(getData()) do
        if lic.scope_tier == tier and LicenseService.isOwned(game, lic.id) then
            return lic
        end
    end
    return nil
end

--- Returns the next purchasable license (scope_tier = current + 1), or nil
--- if the player is already at the highest available tier.
function LicenseService.getNextAvailable(game)
    local next_tier = LicenseService.getCurrentTier(game) + 1
    for _, lic in ipairs(getData()) do
        if lic.purchasable and lic.scope_tier == next_tier then
            return lic
        end
    end
    return nil
end

--- Returns (ok, reason). ok = true if the license can be purchased right now.
function LicenseService.canPurchase(game, license_id)
    local lic = LicenseService.get(license_id)
    if not lic then return false, "unknown_license" end
    if not lic.purchasable then return false, "not_purchasable" end
    if LicenseService.isOwned(game, license_id) then return false, "already_owned" end
    if lic.scope_tier ~= LicenseService.getCurrentTier(game) + 1 then
        return false, "wrong_tier"
    end
    if (game.state.money or 0) < (lic.cost or 0) then return false, "insufficient_funds" end
    return true
end

--- Purchase a license. Pure scope gate: deducts money, sets owned flag,
--- invalidates path cache, publishes license_purchased. No other effects.
--- Returns (ok, reason).
function LicenseService.purchase(game, license_id)
    local ok, reason = LicenseService.canPurchase(game, license_id)
    if not ok then return false, reason end

    local lic = LicenseService.get(license_id)
    game.state.money = game.state.money - (lic.cost or 0)
    game.state.licenses = game.state.licenses or {}
    game.state.licenses[license_id] = true

    require("services.PathCacheService").invalidate()

    if game.EventBus then
        game.EventBus:publish("license_purchased", { license = lic, game = game })
    end

    print(string.format("Purchased license: %s (tier %d)", lic.id, lic.scope_tier))
    return true
end

return LicenseService
