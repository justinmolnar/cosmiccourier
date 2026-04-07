-- models/AutoDispatcher.lua
local AutoDispatcher = {}
AutoDispatcher.__index = AutoDispatcher

function AutoDispatcher:new(C)
    local instance = setmetatable({}, AutoDispatcher)
    instance.dispatch_timer    = 0
    instance.dispatch_interval = C.GAMEPLAY.AUTODISPATCH_INTERVAL
    return instance
end

function AutoDispatcher:update(dt, game)
    -- Always tick wait_time so rules based on how long a trip has been pending work
    -- even before auto-dispatch is unlocked.
    for _, trip in ipairs(game.entities.trips.pending) do
        trip.wait_time = (trip.wait_time or 0) + dt
    end

    if not game.state.upgrades.auto_dispatch_unlocked then return end

    self.dispatch_timer = self.dispatch_timer + dt
    if self.dispatch_timer >= self.dispatch_interval then
        self.dispatch_timer = self.dispatch_timer - self.dispatch_interval
        self:dispatch(game)
    end
end

function AutoDispatcher:dispatch(game)
    if #game.entities.trips.pending == 0 then return end

    local RE = require("services.DispatchRuleEngine")
    local claimed, _, cancelled = RE.evaluate(game.state.dispatch_rules or {}, game)

    for i = #game.entities.trips.pending, 1, -1 do
        local trip = game.entities.trips.pending[i]
        if claimed[trip] or cancelled[trip] then
            table.remove(game.entities.trips.pending, i)
        end
    end
end

return AutoDispatcher
