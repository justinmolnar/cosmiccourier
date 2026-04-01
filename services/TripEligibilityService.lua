-- services/TripEligibilityService.lua
-- Single authority for trip assignment eligibility.
-- Prevents AutoDispatcher and EventService from diverging on what constitutes
-- a valid assignment.

local TripEligibilityService = {}

-- Returns true if vehicle can be assigned the given trip right now.
function TripEligibilityService.canAssign(vehicle, trip, game)
    if not trip.legs[trip.current_leg] then return false end
    local required_type = trip.legs[trip.current_leg].vehicleType
    return vehicle.type == required_type and vehicle:isAvailable(game)
end

return TripEligibilityService
