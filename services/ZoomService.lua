-- services/ZoomService.lua
-- Encapsulates zoom eligibility rules.
-- ZoomControls draws based on these results; it does not compute them.

local ZoomService = {}

-- Returns true if the player is allowed to zoom out from current_scale.
-- Metro license gates the DOWNTOWN → CITY transition only.
function ZoomService.canZoomOut(current_scale, game_state, constants)
    local S = constants.MAP.SCALES
    if current_scale == S.DOWNTOWN then
        return game_state.metro_license_unlocked or game_state.money >= constants.ZOOM.METRO_LICENSE_COST
    end
    return current_scale == S.CITY or current_scale == S.REGION or current_scale == S.CONTINENT
end

-- Returns true if the player is allowed to zoom in from current_scale.
function ZoomService.canZoomIn(current_scale, game_state, constants)
    local S = constants.MAP.SCALES
    return current_scale == S.CITY or current_scale == S.REGION or
           current_scale == S.CONTINENT or current_scale == S.WORLD
end

-- Returns a human-readable reason string if zoom-out is blocked, or nil if allowed.
function ZoomService.getZoomBlockReason(current_scale, game_state, constants)
    local S = constants.MAP.SCALES
    if current_scale == S.DOWNTOWN and not game_state.metro_license_unlocked then
        return "Metropolitan Expansion License Required"
    end
    return nil
end

return ZoomService
