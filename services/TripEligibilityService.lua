-- services/TripEligibilityService.lua
-- Single authority for trip assignment eligibility.

local TripEligibilityService = {}

-- Returns true if vehicle can be assigned the given trip right now.
function TripEligibilityService.canAssign(vehicle, trip, game)
    local leg = trip.legs[trip.current_leg]
    if not leg then return false end

    local vcfg = game.C.VEHICLES[vehicle.type_upper]
    if not vcfg then return false end

    -- 1. Cargo capacity
    if vehicle:getEffectiveCapacity(game) < (leg.cargo_size or 1) then
        return false
    end

    -- 2. Transport mode
    if vcfg.transport_mode ~= (leg.transport_mode or "road") then
        return false
    end

    return vehicle:isAvailable(game)
end

return TripEligibilityService
