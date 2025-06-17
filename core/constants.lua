-- core/constants.lua
-- A central file for all game constants and configuration values.

local C = {
    UI = {
        SIDEBAR_WIDTH       = 280,
        FONT_PATH_MAIN      = "assets/fonts/arial.ttf",
        FONT_PATH_EMOJI     = "assets/fonts/NotoEmoji.ttf",
        FONT_SIZE_UI        = 16,
        FONT_SIZE_EMOJI     = 28,
        
        -- Layout numbers for the sidebar
        PADDING             = 10,
        STATS_Y_START       = 10,
        STATS_Y_STEP        = 20,
        DIVIDER_Y           = 80,
        TRIP_LIST_Y_START   = 90,
        TRIP_LIST_Y_STEP    = 20,
        BUTTONS_Y_START     = 300,
        BUTTONS_Y_STEP      = 40,
        BUTTON_HEIGHT       = 30,
    },

    MAP = {
        GRID_WIDTH          = 62,
        GRID_HEIGHT         = 45,
        TILE_SIZE           = 16,
        NUM_SECONDARY_ROADS = 40,
        
        COLORS = {
            GRASS   = {0.2, 0.6, 0.25},
            ROAD    = {0.2, 0.2, 0.2},
            PLOT    = {0.7, 0.7, 0.7},
            UI_BG   = {0.1, 0.1, 0.15},
            HOVER   = {1, 1, 0},
        }
    },

    GAMEPLAY = {
        INITIAL_MONEY           = 100,
        INITIAL_BIKE_SPEED      = 80,
        BASE_TRIP_PAYOUT        = 50,  -- Renamed from TRIP_PAYOUT
        INITIAL_SPEED_BONUS     = 100, -- The starting value of the speed bonus for each trip
        TRIP_GENERATION_MIN_SEC = 10,
        TRIP_GENERATION_MAX_SEC = 20,
        MAX_PENDING_TRIPS       = 10,
        AUTODISPATCH_INTERVAL   = 1, -- in seconds
    },

    COSTS = {
        -- Initial costs
        BIKE            = 150,
        SPEED           = 75,
        CLIENT          = 500,
        AUTO_DISPATCH   = 1000,
        CAPACITY        = 2500,
        FRENZY_DURATION = 5000,

        -- Cost increase multipliers
        BIKE_MULT       = 1.15,
        SPEED_MULT      = 1.5,
        CLIENT_MULT     = 1.2,
        CAPACITY_MULT   = 1.5,
        FRENZY_DURATION_MULT = 1.5,

        -- Upgrade multipliers
        SPEED_UPGRADE_MULT = 1.2,
    },

    EVENTS = {
        SPAWN_MIN_SEC           = 60,  -- Minimum time in seconds before a new clickable appears
        SPAWN_MAX_SEC           = 120, -- Maximum time
        LIFESPAN_SEC            = 15,  -- How long the clickable stays on screen before disappearing
        INITIAL_DURATION_SEC    = 15,  -- How long the frenzy effect lasts initially
        DURATION_UPGRADE_AMOUNT = 5,   -- How many seconds each upgrade adds
        FRENZY_TRIP_MIN_SEC     = 1,   -- The faster trip generation rate
        FRENZY_TRIP_MAX_SEC     = 3,
    },

    EFFECTS = {
        PAYOUT_TEXT_LIFESPAN_SEC = 3,   -- How long the text stays on screen
        PAYOUT_TEXT_FLOAT_SPEED  = -20, -- How fast the text floats upwards (negative is up)
    },
}

return C