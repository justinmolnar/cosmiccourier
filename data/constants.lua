local C = {
    UI = {
        SIDEBAR_WIDTH       = math.floor(love.graphics.getWidth() * 0.33),
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
    DOWNTOWN_GRID_WIDTH  = 64, -- Changed from 64
    DOWNTOWN_GRID_HEIGHT = 64, -- Changed from 45
    
    -- City scale (much larger area)
    CITY_GRID_WIDTH      = 200, -- Changed from 372
    CITY_GRID_HEIGHT     = 200, -- Changed from 270

    -- Region scale (NEW)
    REGION_GRID_WIDTH    = 1024,
    REGION_GRID_HEIGHT   = 768,
    
    TILE_SIZE            = 2,
    NUM_SECONDARY_ROADS  = 100,
    
        COLORS = {
        GRASS           = {0.2, 0.6, 0.25},
        ROAD            = {0.2, 0.2, 0.2},
        ARTERIAL        = {0.45, 0.38, 0.28},
        PLOT            = {0.7, 0.7, 0.7},
        UI_BG           = {0.1, 0.1, 0.15},
        HOVER           = {1, 1, 0},
        DOWNTOWN_PLOT   = {0.85, 0.85, 0.8},
        DOWNTOWN_ROAD   = {0.3, 0.3, 0.35},
        WATER           = {0.2, 0.3, 0.8},
        COASTAL_WATER   = {0.28, 0.48, 0.88},
        DEEP_WATER      = {0.12, 0.22, 0.65},
        OPEN_OCEAN      = {0.05, 0.10, 0.42},
        MOUNTAIN        = {0.5, 0.45, 0.4},
        DEBUG_NODE      = {0, 1, 0},
    },

    SCALES = {
            DOWNTOWN  = 1,
            CITY      = 2,
            REGION    = 3,
            CONTINENT = 4,
            WORLD     = 5,
        },

    SCALE_NAMES = {
            [1] = "Downtown Core",
            [2] = "Metropolitan Area",
            [3] = "Regional View",
            [4] = "Continental View",
            [5] = "World View",
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
        VEHICLE_STUCK_TIMER     = 15,
    },

    ZOOM = {
        -- Kept for save-data compatibility (not used at runtime):
        METRO_LICENSE_COST       = 50000,
        ZOOM_BUTTON_SIZE         = 30,
        ZOOM_BUTTON_MARGIN       = 10,
        TRANSITION_DURATION      = 0.8,

        -- Continuous zoom range:
        MIN_SCALE                = 1.0,
        MAX_SCALE                = 400.0,
        SCROLL_FACTOR            = 1.15,

        -- Detail-level thresholds (camera.scale values):
        ARTERIAL_THRESHOLD       = 3.0,
        ZONE_THRESHOLD           = 6.0,
        ENTITY_THRESHOLD         = 4.0,
        BIKE_THRESHOLD           = 8.0,
        FOG_THRESHOLD            = 8.0,
        CITY_IMAGE_THRESHOLD     = 1.5,
        DOWNTOWN_IMG_THRESHOLD   = 20.0,
    },

    -- VEHICLES and BUILDINGS are populated after C is fully defined (loaders below).
    VEHICLES  = {},
    BUILDINGS = {},

    MAP_GEN = {
        -- Component Toggles (EXISTING)
        GENERATE_DOWNTOWN = true,
        GENERATE_DISTRICTS = true,
        GENERATE_HIGHWAYS = true,
        GENERATE_RINGROAD = true,
        GENERATE_CONNECTIONS = true,
        
        -- Highway Generation
        HIGHWAY_MERGE_DISTANCE = 50,
        HIGHWAY_MERGE_STRENGTH = 0.8,
        HIGHWAY_PARALLEL_MERGE_DISTANCE = 80,
        HIGHWAY_CURVE_DISTANCE = 50,
        HIGHWAY_STEP_SIZE = 30,
        HIGHWAY_BUFFER = 35,
        NUM_NS_HIGHWAYS = 2,
        NUM_EW_HIGHWAYS = 2,
        
        -- Ring Road Generation
        RING_MIN_ANGLE = 45, -- degrees
        RING_MIN_ARC_DISTANCE = 30,
        RING_EDGE_THRESHOLD = 0.1, -- percentage of map
        RING_CENTER_DISTANCE_THRESHOLD = 0.15, -- percentage of map
        
        -- District Generation
        NUM_DISTRICTS = 10,
        DISTRICT_MIN_SIZE = 40,
        DISTRICT_MAX_SIZE = 80,
        DISTRICT_PLACEMENT_ATTEMPTS = 500,
        DOWNTOWN_ROADS = 40,
        DISTRICT_ROADS_MIN = 15,
        DISTRICT_ROADS_MAX = 30,
        
        -- Connecting Roads
        WALKER_CONNECTION_DISTANCE = 25,
        WALKER_SPLIT_CHANCE = 0.05,
        WALKER_TURN_CHANCE = 0.15,
        WALKER_MAX_ACTIVE = 3,
        WALKER_DEATH_RULES_ENABLED = true,
        
        -- Path Smoothing
        SMOOTHING_MAX_ANGLE = 126, -- degrees
        SMOOTHING_ENABLED = true,
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

    -- Integer tile type constants for the FFI unified grid.
    -- Must match the TILE_INT table in GameBridgeService and
    -- the _TILE_NAMES tables in PathfindingService, lib/pathfinder, and GameView.
    TILE = {
        GRASS         = 0,
        ROAD          = 1,
        DOWNTOWN_ROAD = 2,
        ARTERIAL      = 3,
        HIGHWAY       = 4,
        WATER         = 5,
        MOUNTAIN      = 6,
        RIVER         = 7,
        PLOT          = 8,
        DOWNTOWN_PLOT = 9,
        COASTAL_WATER = 10,
        DEEP_WATER    = 11,
        OPEN_OCEAN    = 12,
    },
}

-- Load vehicle definitions from data/vehicles/*.json
do
    local json = require("lib.json")
    local Z    = C.ZOOM
    local files = love.filesystem.getDirectoryItems("data/vehicles")
    for _, filename in ipairs(files) do
        if filename:match("%.json$") then
            local contents = love.filesystem.read("data/vehicles/" .. filename)
            if contents then
                local def = json.decode(contents)
                local key = def.id:upper()
                -- Resolve zoom key strings → actual threshold numbers
                local rk = def.rendering and def.rendering.render_zoom_key
                local ak = def.rendering and def.rendering.abstract_zoom_key
                def.rendering.render_zoom_threshold  = (rk and Z[rk]) or Z.ENTITY_THRESHOLD
                def.rendering.abstract_zoom_threshold = (ak and Z[ak]) or Z.ENTITY_THRESHOLD
                -- Backward-compat aliases so existing callsites keep working through the refactor
                def.speed                     = def.base_speed
                def.cost                      = def.base_cost
                def.needs_downtown_speed_scale = def.rendering.needs_speed_scale
                def.downtown_only_sim          = (def.rendering.render_zoom_threshold >= (Z.BIKE_THRESHOLD or 8.0))
                def.can_long_distance          = (def.max_range == nil)
                C.VEHICLES[key] = def
            end
        end
    end
end

-- Load building definitions from data/buildings/*.json
do
    local json  = require("lib.json")
    local files = love.filesystem.getDirectoryItems("data/buildings")
    for _, filename in ipairs(files or {}) do
        if filename:match("%.json$") then
            local contents = love.filesystem.read("data/buildings/" .. filename)
            if contents then
                local def = json.decode(contents)
                C.BUILDINGS[def.id] = def
            end
        end
    end
end

return C