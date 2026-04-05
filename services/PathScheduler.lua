-- services/PathScheduler.lua
-- Spreads pathfinding calls across frames to prevent update-spike freezes.
-- State enter functions enqueue a closure; flush() runs until the per-frame
-- time budget is consumed.  Cache hits (cheap) drain many per ms; full A*
-- (expensive) naturally self-limits without a hard count cap.

local PathScheduler = {}

PathScheduler._queue = {}
PathScheduler._head  = 1   -- index of next item to process (avoids O(n) array drain)

-- Wall-clock ms to spend on pathfinding per frame.  Raise for faster vehicle
-- response; lower if other update work needs more headroom.
PathScheduler.budget_ms = 2.0

function PathScheduler.request(vehicle, fn)
    vehicle._path_pending = true
    PathScheduler._queue[#PathScheduler._queue + 1] = {vehicle = vehicle, fn = fn}
end

function PathScheduler.flush()
    local q    = PathScheduler._queue
    local head = PathScheduler._head
    local tail = #q
    if head > tail then return end

    local deadline = love.timer.getTime() + PathScheduler.budget_ms * 0.001
    local i = head
    while i <= tail do
        local item = q[i]
        -- Vehicle may have been reset/re-routed since request was made; skip if stale.
        if item.vehicle._path_pending then
            item.fn()
        end
        i = i + 1
        if love.timer.getTime() >= deadline then break end
    end

    -- Advance head to the first unprocessed item.
    PathScheduler._head = i

    -- Compact the array once a meaningful prefix has been consumed to keep
    -- memory from growing unboundedly on high-volume queues.
    local new_head = PathScheduler._head
    if new_head > 64 then
        local new_len = tail - new_head + 1
        if new_len > 0 then
            for j = 1, new_len do q[j] = q[new_head + j - 1] end
            for j = new_len + 1, tail do q[j] = nil end
        else
            for j = 1, tail do q[j] = nil end
        end
        PathScheduler._head = 1
    end
end

function PathScheduler.clear()
    PathScheduler._queue = {}
    PathScheduler._head  = 1
end

return PathScheduler
