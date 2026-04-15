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
    local RE    = require("services.DispatchRuleEngine")
    local rules = game.state.dispatch_rules or {}

    -- Clear broadcast queue before this dispatch cycle
    game.state.broadcast_queue = {}

    -- Fire polling hats (money/queue/counter/flag thresholds, all-busy/idle)
    RE.evaluatePoll(rules, game)

    if #game.entities.trips.pending > 0 then
        local claimed, _, cancelled = RE.evaluate(rules, game)

        for i = #game.entities.trips.pending, 1, -1 do
            local trip = game.entities.trips.pending[i]
            if claimed[trip] or cancelled[trip] then
                table.remove(game.entities.trips.pending, i)
                -- Cancelled trips are destroyed, so they also leave the source
                -- client's inventory. Claimed trips stay — DoPickup clears them.
                if cancelled[trip] then
                    local sc = trip.source_client
                    if sc and sc.cargo then
                        for j = #sc.cargo, 1, -1 do
                            if sc.cargo[j] == trip then table.remove(sc.cargo, j); break end
                        end
                    end
                end
            end
        end
    end

    -- Fire broadcast-hat rules for each unique message sent this cycle
    local bq   = game.state.broadcast_queue
    local seen = {}
    for _, name in ipairs(bq) do
        if not seen[name] then
            seen[name] = true
            RE.fireEvent(rules, "broadcast", { game = game, broadcast_name = name })
        end
    end
    game.state.broadcast_queue = {}
end

return AutoDispatcher
