-- models/VehicleFactory.lua
local VehicleFactory = {}

-- Registry of available vehicle types
local VEHICLE_TYPES = {
    bike = "models.vehicles.Bike",
    truck = "models.vehicles.Truck"
}

function VehicleFactory.createVehicle(vehicleType, id, depot_plot, game)
    if not vehicleType then
        error("VehicleFactory: vehicleType is required")
    end
    
    local module_path = VEHICLE_TYPES[vehicleType]
    if not module_path then
        error("VehicleFactory: Unknown vehicle type '" .. vehicleType .. "'")
    end
    
    local VehicleClass = require(module_path)
    if not VehicleClass then
        error("VehicleFactory: Could not load vehicle class for type '" .. vehicleType .. "'")
    end
    
    local vehicle = VehicleClass:new(id, depot_plot, game)
    
    -- IMPORTANT: Recalculate position for the current map scale
    vehicle:recalculatePixelPosition(game)
    
    print("VehicleFactory: Created " .. vehicleType .. " #" .. id)
    
    return vehicle
end

function VehicleFactory.isValidVehicleType(vehicleType)
    return VEHICLE_TYPES[vehicleType] ~= nil
end

function VehicleFactory.getAvailableTypes()
    local types = {}
    for vehicleType, _ in pairs(VEHICLE_TYPES) do
        table.insert(types, vehicleType)
    end
    return types
end

return VehicleFactory