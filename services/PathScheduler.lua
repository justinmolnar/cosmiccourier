-- services/PathScheduler.lua
-- Spreads pathfinding calls across frames to prevent update-spike freezes.
-- State enter functions enqueue a closure; flush() runs at most N per frame.

local PathScheduler = {}

PathScheduler._queue = {}

-- How many A* calls to allow per frame. Tune upward if startup feels slow,
-- downward if you see frame spikes. Inter-city A* is heavier than local.
PathScheduler.budget = 24

function PathScheduler.request(vehicle, fn)
    vehicle._path_pending = true
    PathScheduler._queue[#PathScheduler._queue + 1] = {vehicle = vehicle, fn = fn}
end

function PathScheduler.flush()
    local q = PathScheduler._queue
    local n = math.min(PathScheduler.budget, #q)
    for i = 1, n do
        local item = q[i]
        -- Vehicle may have been reset/re-routed since request was made; skip if stale.
        if item.vehicle._path_pending then
            item.fn()
        end
    end
    -- Remove processed items (keep remaining at front)
    if n > 0 then
        for i = 1, #q - n do q[i] = q[i + n] end
        for i = #q - n + 1, #q do q[i] = nil end
    end
end

function PathScheduler.clear()
    PathScheduler._queue = {}
end

return PathScheduler
