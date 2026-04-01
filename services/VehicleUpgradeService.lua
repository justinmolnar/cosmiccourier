-- services/VehicleUpgradeService.lua
-- Applies upgrade stat changes to live vehicle instances.
-- UpgradeSystem delegates here; nothing else should iterate vehicles for upgrade purposes.

local VehicleUpgradeService = {}

-- Sets speed_modifier on every live vehicle of the given type.
-- New vehicles pick up the value from game_state.upgrades at spawn time.
function VehicleUpgradeService.applySpeedModifier(vehicles, vehicle_type, value)
    for _, vehicle in ipairs(vehicles) do
        if vehicle.type == vehicle_type then
            vehicle.speed_modifier = value
        end
    end
end

return VehicleUpgradeService
