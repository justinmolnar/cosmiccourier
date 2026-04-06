-- models/VehicleFactory.lua
local Vehicle = require("models.vehicles.Vehicle")
local VehicleFactory = {}

function VehicleFactory.createVehicle(vehicleType, id, depot, game)
    assert(vehicleType, "VehicleFactory: vehicleType required")
    local vcfg = game.C.VEHICLES[vehicleType:upper()]
    assert(vcfg, "VehicleFactory: unknown vehicle type '" .. tostring(vehicleType) .. "'")
    local vehicle = Vehicle:new(id, depot, game, vehicleType)
    vehicle:recalculatePixelPosition(game)
    return vehicle
end

function VehicleFactory.isValidVehicleType(vehicleType, game)
    return game.C.VEHICLES[vehicleType:upper()] ~= nil
end

return VehicleFactory
