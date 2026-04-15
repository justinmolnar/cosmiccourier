-- config/GameConfig.lua
local GameConfig = {}

-- Default configuration values
local DEFAULT_CONFIG = {
    -- Graphics settings
    graphics = {
        vsync = true,
        fullscreen = true,
        window_width = 1920,
        window_height = 1080,
        camera_smoothing = true,
        particle_effects = true,
        screen_shake = true
    },
    
    -- Audio settings
    audio = {
        master_volume = 1.0,
        sound_effects_volume = 0.8,
        music_volume = 0.6,
        mute_when_minimized = true
    },
    
    -- Input settings
    input = {
        mouse_sensitivity = 1.0,
        scroll_speed = 1.0,
        double_click_time = 0.3,
        drag_threshold = 5
    },
    
    -- UI settings
    ui = {
        show_tooltips = true,
        tooltip_delay = 0.5,
        show_fps = false,
        sidebar_auto_collapse = false,
        animation_speed = 1.0
    },
    
    -- Gameplay settings
    gameplay = {
        auto_pause_on_focus_loss = true,
        speed_multiplier = 1.0,
        difficulty_mode = "normal", -- easy, normal, hard
        tutorial_enabled = true,
        debug_mode_enabled = false
    },
    
    -- Developer settings
    developer = {
        console_enabled = false,
        debug_pathfinding = false,
        debug_rendering = false,
        profiling_enabled = false,
        log_level = "info" -- debug, info, warning, error
    }
}

-- Current configuration (starts as copy of default)
local current_config = {}

-- Registered change listeners: fn(section, key, old_value, new_value)
local change_listeners = {}

function GameConfig.onChanged(fn)
    table.insert(change_listeners, fn)
end

function GameConfig.initialize()
    -- Start with default config
    current_config = GameConfig._deepCopy(DEFAULT_CONFIG)

    -- Register the default love.window handler for graphics changes
    GameConfig.registerDefaultWindowHandler()

    -- Try to load user config
    GameConfig.loadUserConfig()

    -- Apply any command line overrides
    GameConfig._applyCommandLineArgs()

    print("GameConfig: Configuration initialized")
end

function GameConfig.get(section, key)
    if section and key then
        return current_config[section] and current_config[section][key]
    elseif section then
        return current_config[section]
    else
        return current_config
    end
end

function GameConfig.set(section, key, value)
    if not current_config[section] then
        current_config[section] = {}
    end
    
    local old_value = current_config[section][key]
    current_config[section][key] = value
    
    -- Trigger any necessary updates
    GameConfig._onConfigChanged(section, key, old_value, value)
    
    print("GameConfig: Set " .. section .. "." .. key .. " = " .. tostring(value))
end

function GameConfig.reset(section)
    if section then
        current_config[section] = GameConfig._deepCopy(DEFAULT_CONFIG[section])
        print("GameConfig: Reset section " .. section)
    else
        current_config = GameConfig._deepCopy(DEFAULT_CONFIG)
        print("GameConfig: Reset all configuration")
    end
end

function GameConfig.saveUserConfig()
    local config_data = {
        version = "1.0",
        timestamp = os.time(),
        config = current_config
    }
    
    local json_string = GameConfig._configToJson(config_data)
    local success, error_msg = love.filesystem.write("config.json", json_string)
    
    if success then
        print("GameConfig: User configuration saved")
        return true
    else
        print("GameConfig: Failed to save configuration - " .. (error_msg or "unknown error"))
        return false
    end
end

function GameConfig.loadUserConfig()
    local config_file = love.filesystem.getInfo("config.json")
    if not config_file then
        print("GameConfig: No user config file found, using defaults")
        return false
    end
    
    local json_string, error_msg = love.filesystem.read("config.json")
    if not json_string then
        print("GameConfig: Failed to read config file - " .. (error_msg or "unknown error"))
        return false
    end
    
    local config_data = GameConfig._jsonToConfig(json_string)
    if not config_data or not config_data.config then
        print("GameConfig: Invalid config file format")
        return false
    end
    
    -- Merge loaded config with defaults (in case new settings were added)
    current_config = GameConfig._mergeConfigs(DEFAULT_CONFIG, config_data.config)
    
    print("GameConfig: User configuration loaded")
    return true
end

function GameConfig.getAvailableOptions(section)
    local options = {}
    
    if section == "graphics" then
        options.resolution = {
            {1280, 720}, {1920, 1080}, {2560, 1440}, {3840, 2160}
        }
        options.vsync = {true, false}
        options.fullscreen = {true, false}
    elseif section == "gameplay" then
        options.difficulty_mode = {"easy", "normal", "hard", "nightmare"}
        options.speed_multiplier = {0.5, 0.75, 1.0, 1.25, 1.5, 2.0}
    elseif section == "audio" then
        options.volume_levels = {0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0}
    end
    
    return options
end

function GameConfig.validateValue(section, key, value)
    local section_data = DEFAULT_CONFIG[section]
    if not section_data then return false end
    
    local default_value = section_data[key]
    if default_value == nil then return false end
    
    -- Type checking
    if type(value) ~= type(default_value) then return false end
    
    -- Range checking for specific values
    if section == "audio" and key:match("volume") then
        return value >= 0.0 and value <= 1.0
    elseif section == "gameplay" and key == "speed_multiplier" then
        return value >= 0.1 and value <= 10.0
    elseif section == "graphics" and (key == "window_width" or key == "window_height") then
        return value >= 640 and value <= 7680
    end
    
    return true
end

-- Private helper functions
function GameConfig._deepCopy(original)
    local copy = {}
    for key, value in pairs(original) do
        if type(value) == "table" then
            copy[key] = GameConfig._deepCopy(value)
        else
            copy[key] = value
        end
    end
    return copy
end

function GameConfig._mergeConfigs(default, user)
    local merged = GameConfig._deepCopy(default)
    
    for section, section_data in pairs(user) do
        if type(section_data) == "table" and merged[section] then
            for key, value in pairs(section_data) do
                if merged[section][key] ~= nil then
                    merged[section][key] = value
                end
            end
        end
    end
    
    return merged
end

function GameConfig._onConfigChanged(section, key, old_value, new_value)
    for _, fn in ipairs(change_listeners) do
        fn(section, key, old_value, new_value)
    end
end

-- Default window handler — registers love.window calls as a listener.
-- Called once at startup so callers can replace it if desired.
function GameConfig.registerDefaultWindowHandler()
    GameConfig.onChanged(function(section, key, old_value, new_value)
        if section == "graphics" then
            if key == "window_width" or key == "window_height" then
                love.window.setMode(
                    current_config.graphics.window_width,
                    current_config.graphics.window_height,
                    {fullscreen = current_config.graphics.fullscreen}
                )
            elseif key == "fullscreen" then
                love.window.setFullscreen(new_value)
            elseif key == "vsync" then
                love.window.setVSync(new_value and 1 or 0)
            end
        elseif section == "audio" then
            if key:match("volume") then
                print("GameConfig: Audio volume changed - " .. key .. " = " .. new_value)
            end
        end
    end)
end

function GameConfig._applyCommandLineArgs()
    local args = love.arg.parseGameArguments(arg or {})
    
    for _, argument in ipairs(args) do
        if argument == "--debug" then
            GameConfig.set("developer", "console_enabled", true)
            GameConfig.set("developer", "debug_rendering", true)
        elseif argument == "--fullscreen" then
            GameConfig.set("graphics", "fullscreen", true)
        elseif argument == "--windowed" then
            GameConfig.set("graphics", "fullscreen", false)
        elseif argument:match("--resolution=") then
            local resolution = argument:match("--resolution=(.+)")
            local width, height = resolution:match("(%d+)x(%d+)")
            if width and height then
                GameConfig.set("graphics", "window_width", tonumber(width))
                GameConfig.set("graphics", "window_height", tonumber(height))
            end
        end
    end
end

function GameConfig._configToJson(config_table)
    local json = require("lib.json")
    return json.encode(config_table, true)
end

function GameConfig._jsonToConfig(json_string)
    local json = require("lib.json")
    local result, err = json.decode(json_string)
    if err then
        print("GameConfig: JSON parse error - " .. tostring(err))
        return nil
    end
    return result
end

return GameConfig