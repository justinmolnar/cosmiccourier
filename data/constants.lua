local C = {
    UI = {
        SIDEBAR_WIDTH       = 280,
        FONT_PATH_MAIN      = "assets/fonts/arial.ttf",
        FONT_PATH_EMOJI     = "assets/fonts/NotoEmoji.ttf",
        FONT_SIZE_UI        = 16,
        FONT_SIZE_UI_SMALL  = 12,
        FONT_SIZE_EMOJI     = 28,
        FONT_SIZE_EMOJI_UI  = 32,
        
        PADDING             = 10,
        STATS_Y_START       = 10,
        STATS_Y_STEP        = 20,
        DIVIDER_Y           = 80,
        TRIP_LIST_Y_START   = 90,
        TRIP_LIST_Y_STEP    = 20,
        BUTTONS_Y_START     = 300,
        BUTTONS_Y_STEP      = 40,
        BUTTON_HEIGHT       = 30,
        VEHICLE_CLICK_RADIUS = 20, -- Increased from 10
    },

    MAP = {
    -- Downtown scale
    DOWNTOWN_GRID_WIDTH  = 64,
    DOWNTOWN_GRID_HEIGHT = 45,
    
    -- City scale (much larger area)
    CITY_GRID_WIDTH      = 372,
    CITY_GRID_HEIGHT     = 270,

    -- Region scale (NEW)
    REGION_GRID_WIDTH    = 1024,
    REGION_GRID_HEIGHT   = 768,
    
    TILE_SIZE            = 2,
    NUM_SECONDARY_ROADS  = 100, -- Increased from 40 to make downtown denser
    
        COLORS = {
        GRASS           = {0.2, 0.6, 0.25},
        ROAD            = {0.2, 0.2, 0.2},
        PLOT            = {0.7, 0.7, 0.7},
        UI_BG           = {0.1, 0.1, 0.15},
        HOVER           = {1, 1, 0},
        DOWNTOWN_PLOT   = {0.85, 0.85, 0.8},
        DOWNTOWN_ROAD   = {0.3, 0.3, 0.35},
        -- ADD THESE LINES
        WATER           = {0.2, 0.3, 0.8},
        MOUNTAIN        = {0.5, 0.45, 0.4},
        DEBUG_NODE      = {0, 1, 0},
    },

    SCALES = {
            DOWNTOWN = 1,
            CITY = 2,
            REGION = 3,
            PLANET = 4,
        },

    SCALE_NAMES = {
            [1] = "Downtown Core",
            [2] = "Metropolitan Area", 
            [3] = "Regional Network",
            [4] = "Planetary Grid",
        },
},

    GAMEPLAY = {
        INITIAL_MONEY           = 150,
        -- REMOVED: INITIAL_BIKE_SPEED and INITIAL_TRUCK_SPEED (now in vehicle properties)
        BASE_TRIP_PAYOUT        = 50,
        CITY_TRIP_PAYOUT_MULTIPLIER = 20,
        INITIAL_SPEED_BONUS     = 100,
        CITY_TRIP_BONUS_MULTIPLIER = 10,
        TRIP_GENERATION_MIN_SEC = 10,
        TRIP_GENERATION_MAX_SEC = 20,
        MAX_PENDING_TRIPS       = 10,
        AUTODISPATCH_INTERVAL   = 1,
        BONUS_DECAY_RATE        = 1.0,
        MIN_DELTA_CALCULATION   = 0.1,
        CURRENT_MAP_SCALE       = 1,
        -- REMOVED: VEHICLE_CLICK_RADIUS (moved to UI)
        BASE_TILE_SIZE          = 16,
    },

    ZOOM = {
        BUTTONS_APPEAR_THRESHOLD = 25000,
        PRICE_REVEAL_THRESHOLD   = 45000,
        METRO_LICENSE_COST       = 50000,
        ZOOM_BUTTON_SIZE         = 30,
        ZOOM_BUTTON_MARGIN       = 10,
        TRANSITION_DURATION      = 0.8,
        ZOOM_SCALE_FACTOR        = 3.0,
    },

    COSTS = {
        -- REMOVED: BIKE and TRUCK (now handled in GameState with proper values)
        SPEED           = 75,
        CLIENT          = 500,
        AUTO_DISPATCH   = 1000,
        CAPACITY        = 2500,
        FRENZY_DURATION = 5000,

        -- REMOVED: BIKE_MULT and TRUCK_MULT (moved to GameState)
        SPEED_MULT      = 1.5,
        CLIENT_MULT     = 1.2,
        CAPACITY_MULT   = 1.5,
        FRENZY_DURATION_MULT = 1.5,

        SPEED_UPGRADE_MULT = 1.2,
    },

    EVENTS = {
        SPAWN_MIN_SEC           = 60,
        SPAWN_MAX_SEC           = 120,
        LIFESPAN_SEC            = 15,
        INITIAL_DURATION_SEC    = 15,
        DURATION_UPGRADE_AMOUNT = 5,
        FRENZY_TRIP_MIN_SEC     = 1,
        FRENZY_TRIP_MAX_SEC     = 3,
    },

    EFFECTS = {
        PAYOUT_TEXT_LIFESPAN_SEC = 3,
        PAYOUT_TEXT_FLOAT_SPEED  = -20,
    },
}

return C