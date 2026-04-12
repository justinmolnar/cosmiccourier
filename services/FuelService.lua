-- services/FuelService.lua
-- Computes and consumes fuel costs for vehicle journeys.
-- Fuel cost = raw_path_cost * vehicle.fuel_rate
-- Deducted from game.state.money when a vehicle completes a path.

local PathfindingService = require("services.PathfindingService")

local FuelService = {}

--- Compute fuel cost for a path and store it on the vehicle.
--- Called when a path is assigned (in PathScheduler callbacks).
function FuelService.computeAndStore(vehicle, path, game)
    if not path or #path == 0 or (vehicle.fuel_rate or 0) == 0 then
        vehicle.path_fuel_cost = 0
        return
    end
    local raw_cost = PathfindingService.computePathCost(vehicle, path, game)
    vehicle.path_fuel_cost = raw_cost * vehicle.fuel_rate
end

--- Consume the stored fuel cost: deduct from money and publish event.
--- Called when a vehicle finishes traveling a path (arrives at destination).
--- Idempotent -- zeroes the stored cost after consumption.
function FuelService.consume(vehicle, game)
    local amount = vehicle.path_fuel_cost or 0
    if amount <= 0 then return 0 end

    game.state.money = game.state.money - amount
    vehicle.path_fuel_cost = 0

    game.EventBus:publish("fuel_consumed", {
        amount  = amount,
        vehicle = vehicle,
        x       = vehicle.px,
        y       = vehicle.py,
    })

    return amount
end

return FuelService
