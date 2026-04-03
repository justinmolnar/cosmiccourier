-- models/AutoDispatcher.lua
local TripEligibilityService = require("services.TripEligibilityService")
local AutoDispatcher = {}
AutoDispatcher.__index = AutoDispatcher

function AutoDispatcher:new(C)
    local instance = setmetatable({}, AutoDispatcher)
    instance.dispatch_timer = 0
    instance.dispatch_interval = C.GAMEPLAY.AUTODISPATCH_INTERVAL
    return instance
end

function AutoDispatcher:update(dt, game)
    if not game.state.upgrades.auto_dispatch_unlocked then return end
    self.dispatch_timer = self.dispatch_timer + dt
    if self.dispatch_timer >= self.dispatch_interval then
        self.dispatch_timer = self.dispatch_timer - self.dispatch_interval
        self:dispatch(game)
    end
end

function AutoDispatcher:dispatch(game)
    if #game.entities.trips.pending == 0 then return end

    local by_type = {}
    for _, vehicle in ipairs(game.entities.vehicles) do
        local t = vehicle.type
        if not by_type[t] then by_type[t] = {} end
        by_type[t][#by_type[t]+1] = vehicle
    end

    for i = #game.entities.trips.pending, 1, -1 do
        local trip = game.entities.trips.pending[i]
        local leg  = trip.legs[trip.current_leg]
        if not leg then goto continue end

        local found_vehicle = nil
        for _, vehicle in ipairs(by_type[leg.vehicleType] or {}) do
            if TripEligibilityService.canAssign(vehicle, trip, game) then
                found_vehicle = vehicle
                break
            end
        end

        if found_vehicle then
            found_vehicle:assignTrip(trip, game)
            table.remove(game.entities.trips.pending, i)
        end

        ::continue::
    end
end

return AutoDispatcher
