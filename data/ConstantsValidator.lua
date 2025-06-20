-- data/ConstantsValidator.lua
local ConstantsValidator = {}

function ConstantsValidator.validate(constants)
    local errors = {}
    
    -- Validate UI constants
    ConstantsValidator._validateUI(constants, errors)
    
    -- Validate MAP constants
    ConstantsValidator._validateMap(constants, errors)
    
    -- Validate GAMEPLAY constants
    ConstantsValidator._validateGameplay(constants, errors)
    
    -- Validate ZOOM constants
    ConstantsValidator._validateZoom(constants, errors)
    
    -- Validate COSTS constants
    ConstantsValidator._validateCosts(constants, errors)
    
    -- Validate EVENTS constants
    ConstantsValidator._validateEvents(constants, errors)
    
    -- Validate EFFECTS constants
    ConstantsValidator._validateEffects(constants, errors)
    
    if #errors > 0 then
        local error_message = "Constants validation failed:\n" .. table.concat(errors, "\n")
        error(error_message)
    end
    
    print("ConstantsValidator: All constants validated successfully")
    return true
end

function ConstantsValidator._validateUI(constants, errors)
    local ui = constants.UI
    if not ui then
        table.insert(errors, "Missing UI constants table")
        return
    end
    
    ConstantsValidator._validateNumber(ui, "SIDEBAR_WIDTH", errors, 100, 500)
    ConstantsValidator._validateString(ui, "FONT_PATH_MAIN", errors)
    ConstantsValidator._validateString(ui, "FONT_PATH_EMOJI", errors)
    ConstantsValidator._validateNumber(ui, "FONT_SIZE_UI", errors, 8, 32)
    ConstantsValidator._validateNumber(ui, "FONT_SIZE_UI_SMALL", errors, 6, 24)
    ConstantsValidator._validateNumber(ui, "FONT_SIZE_EMOJI", errors, 12, 48)
    ConstantsValidator._validateNumber(ui, "PADDING", errors, 0, 50)
    ConstantsValidator._validateNumber(ui, "VEHICLE_CLICK_RADIUS", errors, 1, 50)
end

function ConstantsValidator._validateMap(constants, errors)
    local map = constants.MAP
    if not map then
        table.insert(errors, "Missing MAP constants table")
        return
    end
    
    ConstantsValidator._validateNumber(map, "DOWNTOWN_GRID_WIDTH", errors, 10, 200)
    ConstantsValidator._validateNumber(map, "DOWNTOWN_GRID_HEIGHT", errors, 10, 200)
    ConstantsValidator._validateNumber(map, "CITY_GRID_WIDTH", errors, 50, 1000)
    ConstantsValidator._validateNumber(map, "CITY_GRID_HEIGHT", errors, 50, 1000)
    ConstantsValidator._validateNumber(map, "TILE_SIZE", errors, 1, 32)
    ConstantsValidator._validateNumber(map, "NUM_SECONDARY_ROADS", errors, 10, 500)
    
    -- Validate colors
    if map.COLORS then
        for color_name, color_value in pairs(map.COLORS) do
            if type(color_value) == "table" and #color_value >= 3 then
                for i = 1, 3 do
                    if type(color_value[i]) ~= "number" or color_value[i] < 0 or color_value[i] > 1 then
                        table.insert(errors, "Invalid color value for MAP.COLORS." .. color_name .. "[" .. i .. "]")
                    end
                end
            else
                table.insert(errors, "Invalid color format for MAP.COLORS." .. color_name)
            end
        end
    end
    
    -- Validate scales
    if map.SCALES then
        for scale_name, scale_value in pairs(map.SCALES) do
            if type(scale_value) ~= "number" or scale_value < 1 or scale_value > 10 then
                table.insert(errors, "Invalid scale value for MAP.SCALES." .. scale_name)
            end
        end
    end
end

function ConstantsValidator._validateGameplay(constants, errors)
    local gameplay = constants.GAMEPLAY
    if not gameplay then
        table.insert(errors, "Missing GAMEPLAY constants table")
        return
    end
    
    ConstantsValidator._validateNumber(gameplay, "INITIAL_MONEY", errors, 0, 10000)
    ConstantsValidator._validateNumber(gameplay, "BASE_TRIP_PAYOUT", errors, 1, 1000)
    ConstantsValidator._validateNumber(gameplay, "INITIAL_SPEED_BONUS", errors, 0, 1000)
    ConstantsValidator._validateNumber(gameplay, "TRIP_GENERATION_MIN_SEC", errors, 1, 60)
    ConstantsValidator._validateNumber(gameplay, "TRIP_GENERATION_MAX_SEC", errors, 5, 120)
    ConstantsValidator._validateNumber(gameplay, "MAX_PENDING_TRIPS", errors, 1, 100)
    ConstantsValidator._validateNumber(gameplay, "BASE_TILE_SIZE", errors, 8, 32)
end

function ConstantsValidator._validateZoom(constants, errors)
    local zoom = constants.ZOOM
    if not zoom then
        table.insert(errors, "Missing ZOOM constants table")
        return
    end
    
    ConstantsValidator._validateNumber(zoom, "BUTTONS_APPEAR_THRESHOLD", errors, 1000, 1000000)
    ConstantsValidator._validateNumber(zoom, "METRO_LICENSE_COST", errors, 1000, 1000000)
    ConstantsValidator._validateNumber(zoom, "ZOOM_BUTTON_SIZE", errors, 15, 100)
    ConstantsValidator._validateNumber(zoom, "TRANSITION_DURATION", errors, 0.1, 5.0)
end

function ConstantsValidator._validateCosts(constants, errors)
    local costs = constants.COSTS
    if not costs then
        table.insert(errors, "Missing COSTS constants table")
        return
    end
    
    ConstantsValidator._validateNumber(costs, "CLIENT", errors, 100, 10000)
    ConstantsValidator._validateNumber(costs, "AUTO_DISPATCH", errors, 100, 10000)
    ConstantsValidator._validateNumber(costs, "CLIENT_MULT", errors, 1.0, 5.0)
end

function ConstantsValidator._validateEvents(constants, errors)
    local events = constants.EVENTS
    if not events then
        table.insert(errors, "Missing EVENTS constants table")
        return
    end
    
    ConstantsValidator._validateNumber(events, "SPAWN_MIN_SEC", errors, 10, 300)
    ConstantsValidator._validateNumber(events, "SPAWN_MAX_SEC", errors, 30, 600)
    ConstantsValidator._validateNumber(events, "LIFESPAN_SEC", errors, 5, 60)
    ConstantsValidator._validateNumber(events, "INITIAL_DURATION_SEC", errors, 5, 60)
end

function ConstantsValidator._validateEffects(constants, errors)
    local effects = constants.EFFECTS
    if not effects then
        table.insert(errors, "Missing EFFECTS constants table")
        return
    end
    
    ConstantsValidator._validateNumber(effects, "PAYOUT_TEXT_LIFESPAN_SEC", errors, 0.5, 10)
    ConstantsValidator._validateNumber(effects, "PAYOUT_TEXT_FLOAT_SPEED", errors, -100, 0)
end

-- Helper validation functions
function ConstantsValidator._validateNumber(table, key, errors, min_val, max_val)
    local value = table[key]
    if value == nil then
        table.insert(errors, "Missing required number: " .. key)
    elseif type(value) ~= "number" then
        table.insert(errors, "Expected number for " .. key .. ", got " .. type(value))
    elseif min_val and value < min_val then
        table.insert(errors, key .. " must be at least " .. min_val .. ", got " .. value)
    elseif max_val and value > max_val then
        table.insert(errors, key .. " must be at most " .. max_val .. ", got " .. value)
    end
end

function ConstantsValidator._validateString(table, key, errors)
    local value = table[key]
    if value == nil then
        table.insert(errors, "Missing required string: " .. key)
    elseif type(value) ~= "string" then
        table.insert(errors, "Expected string for " .. key .. ", got " .. type(value))
    elseif value == "" then
        table.insert(errors, key .. " cannot be empty string")
    end
end

function ConstantsValidator._validateTable(table, key, errors)
    local value = table[key]
    if value == nil then
        table.insert(errors, "Missing required table: " .. key)
    elseif type(value) ~= "table" then
        table.insert(errors, "Expected table for " .. key .. ", got " .. type(value))
    end
end

return ConstantsValidator