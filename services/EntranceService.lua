-- services/EntranceService.lua
-- Lifetime management for entrances: the mode-agnostic connection points
-- between a city's internal network and inter-city trunks.
--
-- Entrances live in two indexes:
--   game.entrances[id]              — flat lookup by id
--   game.entrances_by_city[city][]  — per-city list (ordered registration)
--
-- Both indexes are kept in sync by this service. Nothing else should write
-- to them directly.

local Entrance = require("models.Entrance")

local EntranceService = {}

-- Ensure the two game-level indexes exist. Cheap to call idempotently.
local function _ensureTables(game)
    if not game.entrances         then game.entrances         = {} end
    if not game.entrances_by_city then game.entrances_by_city = {} end
end

-- Register a new entrance. Returns the entrance table. If an entrance with
-- the same id already exists, returns the existing one (no duplicate).
function EntranceService.register(mode, city_idx, ux, uy, building_ref, game)
    _ensureTables(game)
    local id = Entrance.makeId(mode, city_idx, ux, uy)
    local existing = game.entrances[id]
    if existing then return existing end

    local e = Entrance.new(mode, city_idx, ux, uy, building_ref)
    game.entrances[id] = e
    if not game.entrances_by_city[city_idx] then
        game.entrances_by_city[city_idx] = {}
    end
    table.insert(game.entrances_by_city[city_idx], e)
    return e
end

function EntranceService.getById(id, game)
    return game.entrances and game.entrances[id] or nil
end

function EntranceService.getForCity(city_idx, game)
    return (game.entrances_by_city and game.entrances_by_city[city_idx]) or {}
end

function EntranceService.getForCityAndMode(city_idx, mode, game)
    local out = {}
    for _, e in ipairs(EntranceService.getForCity(city_idx, game)) do
        if e.mode == mode then out[#out + 1] = e end
    end
    return out
end

-- Nearest entrance (by squared Euclidean distance) in a city, filtered to a
-- specific mode. Returns the entrance table, or nil if none exists.
function EntranceService.nearest(city_idx, px, py, mode, game)
    local best, best_d2 = nil, math.huge
    for _, e in ipairs(EntranceService.getForCity(city_idx, game)) do
        if e.mode == mode then
            local d2 = (e.ux - px) * (e.ux - px) + (e.uy - py) * (e.uy - py)
            if d2 < best_d2 then best_d2 = d2; best = e end
        end
    end
    return best
end

-- Remove all entrances of a given mode across all cities. Used before a
-- full road-network rebuild so stale attachment nodes don't linger.
function EntranceService.clearMode(mode, game)
    if not game.entrances then return end
    for id, e in pairs(game.entrances) do
        if e.mode == mode then
            game.entrances[id] = nil
        end
    end
    if game.entrances_by_city then
        for ci, list in pairs(game.entrances_by_city) do
            for i = #list, 1, -1 do
                if list[i].mode == mode then table.remove(list, i) end
            end
            if #list == 0 then game.entrances_by_city[ci] = nil end
        end
    end
end

-- Iterate all entrances (flat). Used by graph rebuild.
function EntranceService.all(game)
    local out = {}
    if game.entrances then
        for _, e in pairs(game.entrances) do out[#out + 1] = e end
    end
    return out
end

-- Does at least one entrance of this mode exist anywhere?
-- Used by UI to gate actions like "hire a ship requires a dock".
function EntranceService.anyOfMode(mode, game)
    if not game.entrances then return false end
    for _, e in pairs(game.entrances) do
        if e.mode == mode then return true end
    end
    return false
end

-- First entrance of a mode (stable order not guaranteed). Used as a
-- fallback spawn point for water vehicles when a specific city isn't known.
function EntranceService.firstOfMode(mode, game)
    if not game.entrances_by_city then return nil end
    -- Iterate in ascending city_idx order for deterministic selection.
    local cities = {}
    for ci in pairs(game.entrances_by_city) do cities[#cities + 1] = ci end
    table.sort(cities)
    for _, ci in ipairs(cities) do
        for _, e in ipairs(game.entrances_by_city[ci]) do
            if e.mode == mode then return e end
        end
    end
    return nil
end

return EntranceService
