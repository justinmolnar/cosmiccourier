-- services/SaveService.lua
local SaveService = {}

-- Define what parts of game state should be saved vs regenerated
local SAVE_SCHEMA = {
    version = "1.0",
    persistent_data = {
        "money",
        "trips_completed",
        "upgrades_purchased",
        "upgrades_discovered",
        "metro_license_unlocked",
        "current_map_scale",
        "licenses",
        "unlocked",
        "purchasable_vehicles"
    },
    vehicle_data = {
        "type",
        "depot_plot"
        -- Note: vehicle positions and states are regenerated
    },
    regenerated_data = {
        "income_history",
        "trip_creation_history",
        "rush_hour",
        -- Vehicles + pending-trip queue are regenerated on load.
        -- Depots and clients are persisted (see depots / clients below).
    }
}

-- Flatten a client's cargo (trip objects) to plain tables for JSON encoding.
-- Strips the source_client back-reference (it's the same client; re-attached
-- on load). Each leg is kept as-is — plots are plain tables already.
local function serializeCargoTrips(cargo)
    local out = {}
    for _, t in ipairs(cargo or {}) do
        local legs = {}
        for _, leg in ipairs(t.legs or {}) do
            table.insert(legs, {
                start_plot     = leg.start_plot,
                end_plot       = leg.end_plot,
                cargo_size     = leg.cargo_size,
                transport_mode = leg.transport_mode,
            })
        end
        table.insert(out, {
            scope       = t.scope,
            base_payout = t.base_payout,
            speed_bonus = t.speed_bonus,
            legs        = legs,
        })
    end
    return out
end

function SaveService.saveGame(game, filename)
    filename = filename or "savegame.json"
    
    local save_data = {
        version = SAVE_SCHEMA.version,
        timestamp = os.time(),
        game_data = {}
    }
    
    local game_state = game.state
    
    -- Save persistent state data
    for _, key in ipairs(SAVE_SCHEMA.persistent_data) do
        if game_state[key] ~= nil then
            save_data.game_data[key] = game_state[key]
        end
    end
    
    -- Save upgrade state
    save_data.game_data.upgrades = {
        purchased = game_state.upgrades_purchased,
        discovered = game_state.upgrades_discovered,
        current_values = game_state.upgrades
    }
    
    -- Save vehicle costs (these change as you buy more)
    save_data.game_data.costs = game_state.costs
    
    -- Save Depots
    local saved_depots = {}
    if game.entities and game.entities.depots then
        for _, d in ipairs(game.entities.depots) do
            table.insert(saved_depots, {
                id = d.id,
                plot = d.plot,
                analytics = d.analytics
            })
        end
    end
    save_data.game_data.depots = saved_depots

    -- Save Clients. Each client's live state is preserved so the game can
    -- resume at identical archetype timing and cargo on next load.
    local saved_clients = {}
    if game.entities and game.entities.clients then
        for _, c in ipairs(game.entities.clients) do
            table.insert(saved_clients, {
                archetype       = c.archetype,
                plot            = c.plot,
                trip_timer      = c.trip_timer,
                active          = c.active,
                freq_mult       = c.freq_mult,
                trips_generated = c.trips_generated,
                earnings        = c.earnings,
                cargo_trips     = serializeCargoTrips(c.cargo),
            })
        end
    end
    save_data.game_data.clients = saved_clients

    -- Convert to JSON
    local json = require("lib.json")
    local json_string = json.encode(save_data, true)
    
    -- Write to file
    local success, error_msg = love.filesystem.write(filename, json_string)
    
    if success then
        print("SaveService: Game saved to " .. filename)
        return true
    else
        print("SaveService: Failed to save game - " .. (error_msg or "unknown error"))
        return false, error_msg
    end
end

function SaveService.loadGame(filename)
    filename = filename or "savegame.json"
    
    -- Check if file exists
    local file_info = love.filesystem.getInfo(filename)
    if not file_info then
        print("SaveService: No save file found at " .. filename)
        return nil, "File not found"
    end
    
    -- Read file
    local json_string, error_msg = love.filesystem.read(filename)
    if not json_string then
        print("SaveService: Failed to read save file - " .. (error_msg or "unknown error"))
        return nil, error_msg
    end
    
    -- Parse JSON
    local json = require("lib.json")
    local save_data, err = json.decode(json_string)
    if not save_data then
        print("SaveService: Failed to parse save file - " .. (err or "invalid JSON"))
        return nil, "Invalid JSON"
    end
    
    -- Validate save data
    if not SaveService._validateSaveData(save_data) then
        print("SaveService: Save file is invalid or corrupted")
        return nil, "Invalid save data"
    end
    
    print("SaveService: Game loaded from " .. filename)
    return save_data
end

function SaveService.applySaveData(game, save_data)
    if not save_data or not save_data.game_data then
        return false
    end
    
    local data = save_data.game_data
    local game_state = game.state
    
    -- Restore persistent data
    for _, key in ipairs(SAVE_SCHEMA.persistent_data) do
        if data[key] ~= nil then
            game_state[key] = data[key]
        end
    end
    
    -- Restore upgrade state
    if data.upgrades then
        if data.upgrades.purchased then
            game_state.upgrades_purchased = data.upgrades.purchased
        end
        if data.upgrades.discovered then
            game_state.upgrades_discovered = data.upgrades.discovered
        end
        if data.upgrades.current_values then
            -- Merge saved upgrade values with defaults
            for key, value in pairs(data.upgrades.current_values) do
                game_state.upgrades[key] = value
            end
        end
    end

    -- Migration: legacy clients-upgrade purchased entries -> drop.
    -- The downtown_clients / city_clients sub-trees were replaced by the
    -- per-archetype sub-trees. Their node ids and dead-code stat fields
    -- are retired. This migration clears them from an older save so the
    -- UpgradesTab renders cleanly and stats don't leak.
    do
        local LEGACY_UPGRADE_IDS = {
            "logistics_optimization", "client_relations",
            "downtown_payouts_1", "downtown_bonus_1", "corporate_sponsorship",
            "bulk_contracts", "efficient_routing",
            "city_payouts_1", "interchange_planning", "regional_depots",
        }
        local LEGACY_STAT_FIELDS = {
            "downtown_payout_bonus", "downtown_speed_bonus",
            "city_payout_bonus", "depot_transition_speed",
            "multi_trip_chance", "multi_trip_amount",
            "regional_depots_unlocked",
        }
        local dropped = {}
        if game_state.upgrades_purchased then
            for _, id in ipairs(LEGACY_UPGRADE_IDS) do
                if game_state.upgrades_purchased[id] ~= nil then
                    game_state.upgrades_purchased[id] = nil
                    table.insert(dropped, id)
                end
            end
        end
        if game_state.upgrades then
            for _, key in ipairs(LEGACY_STAT_FIELDS) do
                game_state.upgrades[key] = nil
            end
        end
        if #dropped > 0 then
            print("SaveService: dropped legacy clients-upgrade entries: "
                .. table.concat(dropped, ", "))
        end
    end

    -- Migration: legacy player-wide vehicle_capacity -> per-vehicle-type fields.
    -- Idempotent: re-runs see nil and skip.
    if game_state.upgrades and game_state.upgrades.vehicle_capacity ~= nil then
        local legacy = game_state.upgrades.vehicle_capacity
        local live = game_state.upgrades
        live.bike_capacity  = live.bike_capacity  or legacy
        live.car_capacity   = live.car_capacity   or legacy
        live.truck_capacity = live.truck_capacity or legacy
        live.vehicle_capacity = nil
        print("SaveService: migrated legacy vehicle_capacity -> per-type capacities")
    end

    -- Migration: legacy scope_tier -> owned license set.
    -- Derives licenses from old scope field; continent/world tiers drop to region.
    if game_state.licenses == nil then
        game_state.licenses = { downtown_license = true }
    end
    local legacy_tier = data.scope_tier
        or (data.upgrades and data.upgrades.current_values and data.upgrades.current_values.scope_tier)
    if legacy_tier then
        if legacy_tier >= 2 then game_state.licenses.city_license = true end
        if legacy_tier >= 3 then game_state.licenses.region_license = true end
        print(string.format("SaveService: migrated legacy scope_tier=%d to licenses", legacy_tier))
    end
    -- Clean legacy scope fields so subsequent saves don't re-persist them.
    game_state.scope_tier = nil
    if game_state.upgrades then game_state.upgrades.scope_tier = nil end
    
    -- Restore costs
    if data.costs then
        for vehicle_type, cost in pairs(data.costs) do
            game_state.costs[vehicle_type] = cost
        end
    end
    
    -- Restore Depots
    if data.depots and game.entities then
        game.entities.depots = {}
        local Depot = require("models.Depot")
        for _, d_data in ipairs(data.depots) do
            local new_depot = Depot:new(d_data.id, d_data.plot, game)
            if d_data.analytics then
                new_depot.analytics = d_data.analytics
            end
            table.insert(game.entities.depots, new_depot)
        end
    end

    -- Restore Clients. If the save has a clients array, it is the source
    -- of truth — replace any default clients spawned by EntityManager:init.
    -- Legacy saves without client data keep the default starting client.
    if data.clients and game.entities then
        local Client     = require("models.Client")
        local Trip       = require("models.Trip")
        local Archetypes = require("data.client_archetypes")
        game.entities.clients = {}
        game.entities.trips   = game.entities.trips or { pending = {} }
        game.entities.trips.pending = {}

        for _, c_data in ipairs(data.clients) do
            local archetype_id = c_data.archetype or Archetypes.default_id
            local cmap = game.maps and game.maps.city
            local new_client = Client:new(c_data.plot, game, cmap, archetype_id)
            new_client.trip_timer      = c_data.trip_timer      or new_client.trip_timer
            new_client.active          = (c_data.active ~= nil) and c_data.active or true
            new_client.freq_mult       = c_data.freq_mult       or 1.0
            new_client.trips_generated = c_data.trips_generated or 0
            new_client.earnings        = c_data.earnings        or 0

            for _, t_data in ipairs(c_data.cargo_trips or {}) do
                local trip = Trip:new(t_data.base_payout or 0, t_data.speed_bonus or 0)
                trip.scope = t_data.scope
                for _, leg in ipairs(t_data.legs or {}) do
                    trip:addLeg(leg.start_plot, leg.end_plot,
                                leg.cargo_size, leg.transport_mode)
                end
                trip.source_client = new_client
                table.insert(new_client.cargo, trip)
                table.insert(game.entities.trips.pending, trip)
            end

            table.insert(game.entities.clients, new_client)
        end
    else
        -- Legacy save: the default-spawned starting client stays in place.
        -- Defensive: ensure it has an archetype string.
        if game.entities and game.entities.clients then
            local Archetypes = require("data.client_archetypes")
            for _, c in ipairs(game.entities.clients) do
                if not c.archetype then c.archetype = Archetypes.default_id end
            end
        end
        print("SaveService: legacy save detected, default starting client in place")
    end

    print("SaveService: Save data applied to game state")
    return true
end

function SaveService.getSaveFiles()
    local save_files = {}
    local files = love.filesystem.getDirectoryItems("")
    
    for _, filename in ipairs(files) do
        if filename:match("%.json$") then
            local file_info = love.filesystem.getInfo(filename)
            if file_info and file_info.type == "file" then
                -- Try to parse as save file
                local json_string = love.filesystem.read(filename)
                if json_string then
                    local json = require("lib.json")
                    local save_data = json.decode(json_string)
                    if save_data and save_data.version and save_data.game_data then
                        table.insert(save_files, {
                            filename = filename,
                            timestamp = save_data.timestamp or 0,
                            version = save_data.version
                        })
                    end
                end
            end
        end
    end
    
    -- Sort by timestamp (newest first)
    table.sort(save_files, function(a, b) return a.timestamp > b.timestamp end)
    
    return save_files
end

function SaveService.deleteSave(filename)
    local success = love.filesystem.remove(filename)
    if success then
        print("SaveService: Deleted save file " .. filename)
    else
        print("SaveService: Failed to delete save file " .. filename)
    end
    return success
end

-- Private helper functions (JSON encoding/decoding handled by lib/json)
function SaveService._validateSaveData(save_data)
    if type(save_data) ~= "table" then return false end
    if not save_data.version then return false end
    if not save_data.game_data then return false end
    if type(save_data.game_data) ~= "table" then return false end
    return true
end

return SaveService