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
    
    -- All current vehicles are created on the "city" map.
    -- Future vehicles like trains could be created on the "region" map.
    local operational_map_key = "city"
    local vehicle = VehicleClass:new(id, depot_plot, game, vehicleType, VehicleClass.PROPERTIES, operational_map_key)
    
    -- IMPORTANT: Recalculate position for the current map scale
    vehicle:recalculatePixelPosition(game)
    
    print("VehicleFactory: Created " .. vehicleType .. " #" .. id .. " on map '" .. operational_map_key .. "'")
    
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