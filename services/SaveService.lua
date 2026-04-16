-- services/SaveService.lua
-- Save v3.0: seed-replay. The world is NOT serialized — instead we persist
-- the inputs to worldgen (master RNG seed + wsc.params) and let `_initWorld`
-- regenerate the exact same terrain, cities, and highways at load time.
-- Entities, state, UI config, and dispatch rules serialize as plain data.
--
-- Load flow (orchestrated by main.lua):
--   1. Read + decode save.
--   2. Set love.math RNG seed from save.world.seed.
--   3. Copy save.world.params into Game.world_sandbox_controller.params.
--   4. Run `_initWorld` — worldgen produces byte-identical output.
--   5. SaveService.applyEntities(game, save) overrides the starter entities
--      that `wire()` created with the saved set.

local SaveService = {}

local SAVE_VERSION = "3.0"

-- JSON decode produces string keys for all object fields; Lua code reads
-- sparse integer-keyed tables directly. This walks decoded data and coerces
-- integer-ish string keys back to numbers.
local function coerceIntKeys(t, seen)
    if type(t) ~= "table" then return end
    seen = seen or {}
    if seen[t] then return end
    seen[t] = true
    local renames = {}
    for k, v in pairs(t) do
        if type(k) == "string" and k:match("^%-?%d+$") then
            renames[k] = tonumber(k)
        end
        coerceIntKeys(v, seen)
    end
    for strk, numk in pairs(renames) do
        t[numk] = t[strk]
        t[strk] = nil
    end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SAVE
-- ═══════════════════════════════════════════════════════════════════════════

-- Walk every location a live trip can live (pending, vehicle.cargo/queue,
-- building.cargo, depot.cargo, client.cargo) and dedupe by uid.
local function serializeTripsTable(game)
    local seen = {}
    local out  = {}
    local function add(trip)
        if trip and trip.uid and not seen[trip.uid] then
            seen[trip.uid] = true
            table.insert(out, trip:serialize())
        end
    end
    local E = game.entities
    if E.trips and E.trips.pending then
        for _, t in ipairs(E.trips.pending) do add(t) end
    end
    for _, v in ipairs(E.vehicles or {}) do
        for _, t in ipairs(v.trip_queue or {}) do add(t) end
        for _, t in ipairs(v.cargo      or {}) do add(t) end
    end
    for _, d in ipairs(E.depots or {}) do
        for _, t in ipairs(d.cargo or {}) do add(t) end
    end
    for _, c in ipairs(E.clients or {}) do
        for _, t in ipairs(c.cargo or {}) do add(t) end
    end
    for _, blist in pairs(game.buildings or {}) do
        for _, b in ipairs(blist) do
            for _, t in ipairs(b.cargo or {}) do add(t) end
        end
    end
    return out
end

local function serializePendingTripUids(pending)
    local out = {}
    for i, t in ipairs(pending or {}) do out[i] = t.uid end
    return out
end

-- Serialize each item in an entity list via its :serialize method.
local function serializeList(list)
    local out = {}
    for _, x in ipairs(list or {}) do table.insert(out, x:serialize()) end
    return out
end

function SaveService.saveGame(game, filename)
    filename = filename or "savegame.json"
    local gs = game.state

    -- Clear in-flight build states so they don't bleed through the snapshot.
    game.entities.build_depot_mode    = false
    game.entities.build_highway_mode  = false
    game.entities.highway_build_nodes = {}
    game._hw_ghost_cache              = nil

    local Vehicle = require("models.vehicles.Vehicle")
    local Trip    = require("models.Trip")
    local Client  = require("models.Client")
    local BuildingService = require("services.BuildingService")

    local wsc  = game.world_sandbox_controller
    local seed = gs._world_seed or { a = 0, b = 0 }

    -- `_world_start_idx` is set by WorldSandboxController:sendToGame when it
    -- picks/forces the starter city. It's the index into city_locations
    -- (NOT all_cities — all_cities always has the starter at [1]). Saving
    -- this lets the reload force the same starter through pickStartIdx.
    local start_idx = gs._world_start_idx

    local save = {
        version   = SAVE_VERSION,
        timestamp = os.time(),

        counters = {
            next_vehicle_id = Vehicle.getNextId(),
            next_trip_uid   = Trip.getNextUid(),
            next_client_id  = Client.getNextId(),
        },

        state = gs:serialize(),

        world = {
            seed      = { a = seed.a, b = seed.b },
            params    = wsc and wsc.params or {},
            start_idx = start_idx,
        },

        trips = serializeTripsTable(game),

        entities = {
            pending_trip_uids     = serializePendingTripUids(game.entities.trips.pending),
            pause_trip_generation = game.entities.pause_trip_generation or false,
            depots                = serializeList(game.entities.depots),
            clients               = serializeList(game.entities.clients),
            vehicles              = serializeList(game.entities.vehicles),
            buildings             = BuildingService.serializeAll(game),
        },
    }

    local json = require("lib.json")
    local ok, err = love.filesystem.write(filename, json.encode(save, true))
    if ok then
        print("SaveService: saved to " .. filename)
        return true
    else
        print("SaveService: save failed - " .. tostring(err))
        return false, err
    end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LOAD
-- ═══════════════════════════════════════════════════════════════════════════

function SaveService.loadGame(filename)
    filename = filename or "savegame.json"
    if not love.filesystem.getInfo(filename) then
        print("SaveService: no save file at " .. filename)
        return nil, "File not found"
    end
    local json_string, err = love.filesystem.read(filename)
    if not json_string then return nil, err end
    local json = require("lib.json")
    local data = json.decode(json_string)
    if type(data) ~= "table" or data.version ~= SAVE_VERSION then
        print("SaveService: save version mismatch (expected " .. SAVE_VERSION ..
              ", got " .. tostring(data and data.version) .. ") — ignoring save")
        return nil, "Version mismatch"
    end
    coerceIntKeys(data)
    return data
end

-- Called by main.lua BEFORE `_initWorld`. Primes the RNG and wsc.params so
-- the worldgen that runs next produces the same world as the save.
function SaveService.primeWorld(game, save)
    if not save or not save.world then return end
    local seed = save.world.seed or {}
    if seed.a and seed.b then
        love.math.setRandomSeed(seed.a, seed.b)
    end
    -- Stash the seed on state so the next save can serialize it unchanged.
    game.state._world_seed = { a = seed.a, b = seed.b }

    local wsc = game.world_sandbox_controller
    -- Force the same starter city on reload. Without this, the next
    -- pickStartIdx() inside sendToGame rolls the RNG and can land on a
    -- different city than the save — fog reveals the wrong place while the
    -- saved entities sit hidden in the real starter.
    if wsc and save.world.start_idx then
        wsc._forced_start_idx = save.world.start_idx
    end
    if wsc and save.world.params then
        wsc.params = wsc.params or {}
        for k, v in pairs(save.world.params) do
            wsc.params[k] = v
        end
    end
end

-- Called by main.lua AFTER `_initWorld`. The world now exists; we overwrite
-- the default starter entities that `wire()` created with the saved set.
function SaveService.applyEntities(game, save)
    if not save or save.version ~= SAVE_VERSION then return false end
    local gs = game.state

    local Vehicle = require("models.vehicles.Vehicle")
    local Trip    = require("models.Trip")
    local Client  = require("models.Client")
    local Depot   = require("models.Depot")
    local BuildingService = require("services.BuildingService")

    -- Counters first (so any :new inside restore doesn't collide).
    local ctr = save.counters or {}
    if ctr.next_vehicle_id then Vehicle.setNextId(ctr.next_vehicle_id) end
    if ctr.next_trip_uid   then Trip.setNextUid(ctr.next_trip_uid)     end
    if ctr.next_client_id  then Client.setNextId(ctr.next_client_id)   end

    gs:applySerialized(save.state or {})

    -- Trips (uid-keyed table).
    local trips_by_uid = {}
    for _, td in ipairs(save.trips or {}) do
        local t = Trip.fromSerialized(td)
        trips_by_uid[t.uid] = t
    end

    -- Depots (before vehicles — vehicles reference depots by id).
    game.entities.depots = {}
    local depots_by_id = {}
    for _, dd in ipairs(save.entities.depots or {}) do
        local d = Depot.fromSerialized(dd, game, trips_by_uid)
        table.insert(game.entities.depots, d)
        depots_by_id[d.id] = d
    end

    -- Clients.
    game.entities.clients = {}
    local clients_by_id = {}
    for _, cd in ipairs(save.entities.clients or {}) do
        local c = Client.fromSerialized(cd, game, trips_by_uid)
        table.insert(game.entities.clients, c)
        clients_by_id[c.id] = c
    end
    -- Trips in pending / depot / building cargo still need source_client back-refs.
    for _, td in ipairs(save.trips or {}) do
        local trip = trips_by_uid[td.uid]
        if trip and td.source_client_id then
            trip.source_client = clients_by_id[td.source_client_id] or trip.source_client
        end
    end

    -- Vehicles.
    game.entities.vehicles = {}
    for _, vd in ipairs(save.entities.vehicles or {}) do
        local v = Vehicle.fromSerialized(vd, game, depots_by_id, trips_by_uid)
        if v then
            table.insert(game.entities.vehicles, v)
            if v.depot and v.depot.assigned_vehicles then
                table.insert(v.depot.assigned_vehicles, v)
            end
        end
    end

    -- Pending trips.
    game.entities.trips = game.entities.trips or { pending = {} }
    game.entities.trips.pending = {}
    for _, uid in ipairs(save.entities.pending_trip_uids or {}) do
        local t = trips_by_uid[uid]
        if t then table.insert(game.entities.trips.pending, t) end
    end

    -- Buildings.
    BuildingService.restoreAll(game, save.entities.buildings or {}, trips_by_uid)

    -- Misc entity flags.
    game.entities.pause_trip_generation = save.entities.pause_trip_generation or false

    -- Re-assert counters (each :new during restore bumped them).
    if ctr.next_vehicle_id then Vehicle.setNextId(ctr.next_vehicle_id) end
    if ctr.next_trip_uid   then Trip.setNextUid(ctr.next_trip_uid)     end
    if ctr.next_client_id  then Client.setNextId(ctr.next_client_id)   end

    print("SaveService: applied entities from save v" .. tostring(save.version))
    return true
end

-- ═══════════════════════════════════════════════════════════════════════════
-- DELETE / HELPERS
-- ═══════════════════════════════════════════════════════════════════════════

function SaveService.deleteSave(filename)
    filename = filename or "savegame.json"
    local ok = love.filesystem.remove(filename)
    if ok then print("SaveService: deleted " .. filename) end
    return ok
end

function SaveService.getSaveFiles()
    local out = {}
    for _, fn in ipairs(love.filesystem.getDirectoryItems("")) do
        if fn:match("%.json$") then
            local info = love.filesystem.getInfo(fn)
            if info and info.type == "file" then
                local s = love.filesystem.read(fn)
                if s then
                    local json = require("lib.json")
                    local d = json.decode(s)
                    if d and d.version == SAVE_VERSION then
                        table.insert(out, {
                            filename = fn, timestamp = d.timestamp or 0, version = d.version,
                        })
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.timestamp > b.timestamp end)
    return out
end

return SaveService
