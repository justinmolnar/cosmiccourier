-- services/ErrorService.lua
local ErrorService = {}

-- Error levels
local ERROR_LEVELS = {
    DEBUG = 1,
    INFO = 2,
    WARNING = 3,
    ERROR = 4,
    FATAL = 5
}

-- Current configuration
local config = {
    log_level = ERROR_LEVELS.INFO,
    log_to_file = true,
    log_to_console = true,
    max_log_entries = 1000,
    show_error_popups = true
}

-- Log storage
local log_entries = {}
local error_counts = {}

function ErrorService.initialize(user_config)
    if user_config then
        for key, value in pairs(user_config) do
            config[key] = value
        end
    end
    
    -- Set up error handler
    local old_error_handler = love.errorhandler
    love.errorhandler = function(msg)
        ErrorService.logError("FATAL", "Love2D Error", msg, debug.traceback())
        return old_error_handler(msg)
    end
    
    ErrorService.logInfo("ErrorService", "Error handling system initialized")
end

function ErrorService.logDebug(category, message, details)
    ErrorService._log(ERROR_LEVELS.DEBUG, category, message, details)
end

function ErrorService.logInfo(category, message, details)
    ErrorService._log(ERROR_LEVELS.INFO, category, message, details)
end

function ErrorService.logWarning(category, message, details)
    ErrorService._log(ERROR_LEVELS.WARNING, category, message, details)
end

function ErrorService.logError(category, message, details, stack_trace)
    ErrorService._log(ERROR_LEVELS.ERROR, category, message, details, stack_trace)
    
    -- Track error frequency
    local error_key = category .. ":" .. message
    error_counts[error_key] = (error_counts[error_key] or 0) + 1
    
    -- Show popup for critical errors if enabled
    if config.show_error_popups and error_counts[error_key] <= 3 then
        ErrorService._showErrorPopup(category, message, details)
    end
end

function ErrorService.logFatal(category, message, details, stack_trace)
    ErrorService._log(ERROR_LEVELS.FATAL, category, message, details, stack_trace)
    
    -- For fatal errors, always show popup and save logs immediately
    ErrorService._showErrorPopup(category, message, details)
    ErrorService.saveLogsToFile()
    
    -- Consider terminating the game or entering safe mode
    print("FATAL ERROR: " .. category .. " - " .. message)
end

function ErrorService.handleLuaError(err, category)
    category = category or "Lua Runtime"
    local stack_trace = debug.traceback()
    ErrorService.logError(category, tostring(err), nil, stack_trace)
    return err
end

function ErrorService.withErrorHandling(func, category, ...)
    category = category or "Unknown"
    
    local success, result = pcall(func, ...)
    
    if not success then
        ErrorService.handleLuaError(result, category)
        return nil, result
    end
    
    return result
end

function ErrorService.assert(condition, category, message, details)
    if not condition then
        ErrorService.logError(category or "Assertion", message or "Assertion failed", details, debug.traceback())
        error(message or "Assertion failed")
    end
    return condition
end

function ErrorService.getRecentLogs(level_filter, max_entries)
    max_entries = max_entries or 50
    local filtered_logs = {}
    
    for i = #log_entries, 1, -1 do
        local entry = log_entries[i]
        if not level_filter or entry.level >= level_filter then
            table.insert(filtered_logs, entry)
            if #filtered_logs >= max_entries then
                break
            end
        end
    end
    
    return filtered_logs
end

function ErrorService.getErrorStatistics()
    local stats = {
        total_entries = #log_entries,
        by_level = {
            debug = 0,
            info = 0,
            warning = 0,
            error = 0,
            fatal = 0
        },
        by_category = {},
        most_frequent_errors = {}
    }
    
    -- Count by level
    for _, entry in ipairs(log_entries) do
        if entry.level == ERROR_LEVELS.DEBUG then stats.by_level.debug = stats.by_level.debug + 1
        elseif entry.level == ERROR_LEVELS.INFO then stats.by_level.info = stats.by_level.info + 1
        elseif entry.level == ERROR_LEVELS.WARNING then stats.by_level.warning = stats.by_level.warning + 1
        elseif entry.level == ERROR_LEVELS.ERROR then stats.by_level.error = stats.by_level.error + 1
        elseif entry.level == ERROR_LEVELS.FATAL then stats.by_level.fatal = stats.by_level.fatal + 1
        end
        
        -- Count by category
        stats.by_category[entry.category] = (stats.by_category[entry.category] or 0) + 1
    end
    
    -- Get most frequent errors
    local error_list = {}
    for error_key, count in pairs(error_counts) do
        table.insert(error_list, {error = error_key, count = count})
    end
    table.sort(error_list, function(a, b) return a.count > b.count end)
    
    for i = 1, math.min(10, #error_list) do
        table.insert(stats.most_frequent_errors, error_list[i])
    end
    
    return stats
end

function ErrorService.saveLogsToFile(filename)
    if not config.log_to_file then return false end
    
    filename = filename or ("error_log_" .. os.date("%Y%m%d_%H%M%S") .. ".txt")
    
    local log_content = {}
    table.insert(log_content, "Error Log - Generated: " .. os.date("%Y-%m-%d %H:%M:%S"))
    table.insert(log_content, "Game Version: " .. (love.getVersion and love.getVersion() or "Unknown"))
    table.insert(log_content, "System: " .. love.system.getOS())
    table.insert(log_content, "----------------------------------------")
    
    for _, entry in ipairs(log_entries) do
        local level_name = ErrorService._getLevelName(entry.level)
        local timestamp = os.date("%H:%M:%S", entry.timestamp)
        
        local line = string.format("[%s] %s - %s: %s", 
            timestamp, level_name, entry.category, entry.message)
        
        if entry.details then
            line = line .. " | Details: " .. tostring(entry.details)
        end
        
        if entry.stack_trace then
            line = line .. "\nStack Trace:\n" .. entry.stack_trace
        end
        
        table.insert(log_content, line)
    end
    
    local success, error_msg = love.filesystem.write(filename, table.concat(log_content, "\n"))
    
    if success then
        ErrorService.logInfo("ErrorService", "Logs saved to " .. filename)
        return true
    else
        print("Failed to save logs: " .. (error_msg or "unknown error"))
        return false
    end
end

function ErrorService.clearLogs()
    log_entries = {}
    error_counts = {}
    ErrorService.logInfo("ErrorService", "Log history cleared")
end

function ErrorService.setLogLevel(level)
    if type(level) == "string" then
        level = ERROR_LEVELS[level:upper()]
    end
    
    if level and level >= ERROR_LEVELS.DEBUG and level <= ERROR_LEVELS.FATAL then
        config.log_level = level
        ErrorService.logInfo("ErrorService", "Log level set to " .. ErrorService._getLevelName(level))
    else
        ErrorService.logWarning("ErrorService", "Invalid log level: " .. tostring(level))
    end
end

-- Private functions
function ErrorService._log(level, category, message, details, stack_trace)
    if level < config.log_level then return end
    
    local entry = {
        timestamp = os.time(),
        level = level,
        category = category or "Unknown",
        message = message or "No message",
        details = details,
        stack_trace = stack_trace
    }
    
    table.insert(log_entries, entry)
    
    -- Limit log size
    if #log_entries > config.max_log_entries then
        table.remove(log_entries, 1)
    end
    
    -- Console output
    if config.log_to_console then
        local level_name = ErrorService._getLevelName(level)
        local output = string.format("[%s] %s: %s", level_name, category, message)
        
        if level >= ERROR_LEVELS.ERROR then
            print("ERROR: " .. output)
            if details then print("  Details: " .. tostring(details)) end
            if stack_trace then print("  " .. stack_trace) end
        elseif level >= ERROR_LEVELS.WARNING then
            print("WARNING: " .. output)
        else
            print(output)
        end
    end
end

function ErrorService._getLevelName(level)
    for name, value in pairs(ERROR_LEVELS) do
        if value == level then return name end
    end
    return "UNKNOWN"
end

function ErrorService._showErrorPopup(category, message, details)
    -- In a real game, this would show a proper error dialog
    -- For now, just ensure it's logged to console
    print("ERROR POPUP: " .. category .. " - " .. message)
    if details then
        print("Details: " .. tostring(details))
    end
end

return ErrorService