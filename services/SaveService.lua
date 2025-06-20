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
        "current_map_scale"
    },
    vehicle_data = {
        "type",
        "depot_plot"
        -- Note: vehicle positions and states are regenerated
    },
    regenerated_data = {
        "income_history",
        "trip_creation_history", 
        "floating_texts",
        "rush_hour",
        "entities" -- All vehicles, clients, trips regenerated
    }
}

function SaveService.saveGame(game_state, filename)
    filename = filename or "savegame.json"
    
    local save_data = {
        version = SAVE_SCHEMA.version,
        timestamp = os.time(),
        game_data = {}
    }
    
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
    
    -- Convert to JSON
    local json_string = SaveService._tableToJson(save_data)
    
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
    local save_data = SaveService._jsonToTable(json_string)
    if not save_data then
        print("SaveService: Failed to parse save file - invalid JSON")
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

function SaveService.applySaveData(game_state, save_data)
    if not save_data or not save_data.game_data then
        return false
    end
    
    local data = save_data.game_data
    
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
    
    -- Restore costs
    if data.costs then
        for vehicle_type, cost in pairs(data.costs) do
            game_state.costs[vehicle_type] = cost
        end
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
                    local save_data = SaveService._jsonToTable(json_string)
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

-- Private helper functions
function SaveService._validateSaveData(save_data)
    if type(save_data) ~= "table" then return false end
    if not save_data.version then return false end
    if not save_data.game_data then return false end
    if type(save_data.game_data) ~= "table" then return false end
    return true
end

function SaveService._tableToJson(tbl, indent)
    indent = indent or 0
    local indent_str = string.rep("  ", indent)
    
    if type(tbl) ~= "table" then
        if type(tbl) == "string" then
            return '"' .. tbl:gsub('"', '\\"') .. '"'
        elseif type(tbl) == "number" or type(tbl) == "boolean" then
            return tostring(tbl)
        else
            return "null"
        end
    end
    
    local result = "{\n"
    local first = true
    
    for key, value in pairs(tbl) do
        if not first then
            result = result .. ",\n"
        end
        first = false
        
        local key_str = type(key) == "string" and ('"' .. key .. '"') or tostring(key)
        result = result .. indent_str .. "  " .. key_str .. ": " .. SaveService._tableToJson(value, indent + 1)
    end
    
    result = result .. "\n" .. indent_str .. "}"
    return result
end

function SaveService._jsonToTable(json_str)
    -- Simple JSON parser - in a real implementation you'd use a proper JSON library
    -- This is a basic implementation for demonstration
    local success, result = pcall(function()
        -- Remove whitespace and comments
        local clean_json = json_str:gsub("%s+", " "):gsub("//.-\n", "")
        
        -- Very basic JSON parsing - this would need to be much more robust
        if clean_json:match("^%s*{") then
            return SaveService._parseJsonObject(clean_json)
        else
            return nil
        end
    end)
    
    if success then
        return result
    else
        print("SaveService: JSON parsing failed - " .. tostring(result))
        return nil
    end
end

function SaveService._parseJsonObject(json_str)
    -- This is a very simplified JSON parser
    -- In a production game, you would use a proper JSON library like dkjson or cjson
    local result = {}
    
    -- Remove outer braces
    local content = json_str:match("^%s*{(.+)}%s*$")
    if not content then return nil end
    
    -- Split by commas (this is overly simplified)
    for pair in content:gmatch('[^,]+') do
        local key, value = pair:match('%s*"([^"]+)"%s*:%s*(.+)%s*')
        if key and value then
            -- Parse value
            if value:match('^".*"$') then
                -- String value
                result[key] = value:match('^"(.*)"$')
            elseif value:match('^%d+%.?%d*$') then
                -- Number value
                result[key] = tonumber(value)
            elseif value == "true" then
                result[key] = true
            elseif value == "false" then
                result[key] = false
            elseif value:match('^%s*{') then
                -- Nested object (recursive)
                result[key] = SaveService._parseJsonObject(value)
            end
        end
    end
    
    return result
end

return SaveService