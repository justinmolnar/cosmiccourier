-- services/StatsService.lua
-- Computes per-second income and trip-creation stats from rolling history windows.
-- Prunes stale entries from state as a side effect.

local C = require("data.constants")

local StatsService = {}

local WINDOW = C.GAMEPLAY.STATS_WINDOW_SEC

function StatsService.computePerSecondStats(state)
    local now = love.timer.getTime()

    local total_income = 0
    for i = #state.income_history, 1, -1 do
        if now - state.income_history[i].time > WINDOW then
            table.remove(state.income_history, i)
        else
            total_income = total_income + state.income_history[i].amount
        end
    end

    local trip_count = 0
    for i = #state.trip_creation_history, 1, -1 do
        if now - state.trip_creation_history[i] > WINDOW then
            table.remove(state.trip_creation_history, i)
        else
            trip_count = trip_count + 1
        end
    end

    return {
        income_per_second = total_income / WINDOW,
        trips_per_second  = trip_count  / WINDOW,
    }
end

return StatsService
