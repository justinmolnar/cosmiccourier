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
    -- This dispatcher tries to assign one trip to any available vehicle.
    for _, vehicle in ipairs(game.state.vehicles) do
        if #game.state.trips.pending == 0 then return end -- No more trips to assign

        if vehicle:isAvailable(game) then
            local trip_to_assign = table.remove(game.state.trips.pending, 1)
            vehicle:assignTrip(trip_to_assign, game)
        end
    end
end

return AutoDispatcher