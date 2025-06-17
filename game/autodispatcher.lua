-- game/autodispatcher.lua
-- A system that automatically assigns trips to idle vehicles.

local AutoDispatcher = {}
AutoDispatcher.__index = AutoDispatcher

function AutoDispatcher:new(C)
    local instance = setmetatable({}, AutoDispatcher)
    instance.dispatch_timer = 0
    instance.dispatch_interval = C.GAMEPLAY.AUTODISPATCH_INTERVAL
    return instance
end

function AutoDispatcher:update(dt, game)
    -- Do nothing if the player hasn't unlocked this upgrade.
    if not game.state.upgrades.auto_dispatch_unlocked then
        return
    end

    self.dispatch_timer = self.dispatch_timer + dt
    if self.dispatch_timer >= self.dispatch_interval then
        self.dispatch_timer = self.dispatch_timer - self.dispatch_interval
        self:dispatch(game)
    end
end

function AutoDispatcher:dispatch(game)
    if #game.entities.trips.pending == 0 then return end

    -- For each pending trip, try to find a matching vehicle
    for i = #game.entities.trips.pending, 1, -1 do
        local trip_to_assign = game.entities.trips.pending[i]
        local required_type = trip_to_assign.legs[trip_to_assign.current_leg].vehicleType

        -- Find an available vehicle of the required type
        local found_vehicle = nil
        for _, vehicle in ipairs(game.entities.vehicles) do
            -- In the future, vehicle objects should have a .type property
            -- For now, we assume all vehicles are the required "bike" type
            if vehicle:isAvailable(game) then 
                found_vehicle = vehicle
                break -- Use the first one we find
            end
        end

        if found_vehicle then
            -- We found a match, assign the trip and remove it from the pending list
            found_vehicle:assignTrip(trip_to_assign, game)
            table.remove(game.entities.trips.pending, i)
        end
    end
end

return AutoDispatcher