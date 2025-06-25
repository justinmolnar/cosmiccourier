function love.load()
    -- Initialize error handling first
    local ErrorService = require("services.ErrorService")
    ErrorService.initialize({
        log_level = 2, -- INFO level
        log_to_file = true,
        show_error_popups = true
    })
    
    -- Initialize configuration system
    local GameConfig = require("config.GameConfig")
    GameConfig.initialize()
    
    -- Load and validate constants
    local C = require("data.constants")
    local ConstantsValidator = require("data.ConstantsValidator")
    
    ErrorService.withErrorHandling(function()
        ConstantsValidator.validate(C)
    end, "Constants Validation")
    
    -- Apply graphics configuration
    love.window.setMode(
        GameConfig.get("graphics", "window_width"),
        GameConfig.get("graphics", "window_height"),
        {
            fullscreen = GameConfig.get("graphics", "fullscreen"),
            vsync = GameConfig.get("graphics", "vsync")
        }
    )
    
    local GameController = require("controllers.GameController")
    local InputController = require("controllers.InputController")
    local GameView = require("views.GameView")
    local UIView = require("views.UIView")
    local UIManager = require("views.UIManager")

    Game = {
        C = C,
        config = GameConfig,
        error_service = ErrorService,
        EventBus = require("core.event_bus"),
        state = nil,
        time = require("core.time"):new(),
        maps = {
            city = require("models.Map"):new(C),
            region = require("models.Map"):new(C)
        },
        active_map_key = "city",
        entities = require("models.EntityManager"):new(),
        autodispatcher = require("models.AutoDispatcher"):new(C),
        event_spawner = require("models.EventSpawner"):new(C),
        pathfinder = require("lib.pathfinder"),
        fonts = {},
        debug_mode = GameConfig.get("gameplay", "debug_mode_enabled"),
        ui_manager = nil,
        zoom_controls = nil,
        camera = require("core.camera"):new(0, 0, 1),
        game_controller = nil,
        input_controller = nil,
        game_view = nil,
        ui_view = nil,
        show_districts = true,
        -- NEW: Storing paths from R and Y keys separately
        arterial_control_paths = {},
        smooth_highway_overlay_paths = {}
    }
    
    local SaveService = require("services.SaveService")
    local save_data = SaveService.loadGame()
    
    Game.state = require("models.GameState"):new(C, Game)
    
    if save_data then
        ErrorService.withErrorHandling(function()
            SaveService.applySaveData(Game.state, save_data)
            ErrorService.logInfo("Main", "Save game loaded successfully")
        end, "Save Game Loading")
    end
    
    Game.ui_manager = UIManager:new(C, Game)
    Game.zoom_controls = require("views.components.ZoomControls"):new(C)

    Game.entities.event_bus_listener_setup(Game)

    Game.game_controller = GameController:new(Game)
    Game.input_controller = InputController:new(Game)
    Game.game_view = GameView:new(Game)
    Game.ui_view = UIView:new(Game)

    ErrorService.withErrorHandling(function()
        Game.maps.region:generateRegion()
    end, "Region Map Generation")
    
    Game.entities:init(Game)
    
    ErrorService.withErrorHandling(function()
        local uiFont = love.graphics.newFont(C.UI.FONT_PATH_MAIN, C.UI.FONT_SIZE_UI)
        local uiFontSmall = love.graphics.newFont(C.UI.FONT_PATH_MAIN, C.UI.FONT_SIZE_UI_SMALL)
        local emojiFont = love.graphics.newFont(C.UI.FONT_PATH_EMOJI, C.UI.FONT_SIZE_EMOJI)
        local emojiFontUI = love.graphics.newFont(C.UI.FONT_PATH_EMOJI, C.UI.FONT_SIZE_EMOJI_UI)
        local uiIconFont = love.graphics.newFont(C.UI.FONT_PATH_EMOJI, C.UI.FONT_SIZE_UI)

        uiFont:setFallbacks(uiIconFont)
        uiFontSmall:setFallbacks(uiIconFont)
        emojiFont:setFallbacks(uiFont, uiFontSmall)
        emojiFontUI:setFallbacks(uiFont, uiFontSmall)

        Game.fonts.ui = uiFont
        Game.fonts.ui_small = uiFontSmall
        Game.fonts.emoji = emojiFont
        Game.fonts.emoji_ui = emojiFontUI

        love.graphics.setFont(Game.fonts.ui)
    end, "Font Loading")
    
    Game.maps.city:setScale(C.MAP.SCALES.DOWNTOWN)
    
    local auto_save_interval = GameConfig.get("ui", "auto_save_interval")
    if auto_save_interval > 0 then
        Game.auto_save_timer = auto_save_interval
    end
    
    ErrorService.logInfo("Main", "Game initialization completed successfully")
end

function love.update(dt)
    Game.game_controller:update(dt)
    
    if Game.auto_save_timer then
        Game.auto_save_timer = Game.auto_save_timer - dt
        if Game.auto_save_timer <= 0 then
            local SaveService = require("services.SaveService")
            Game.error_service.withErrorHandling(function()
                SaveService.saveGame(Game.state, "autosave.json")
            end, "Auto Save")
            
            Game.auto_save_timer = Game.config.get("ui", "auto_save_interval")
        end
    end
end

function love.draw()
    Game.ui_view:draw()
    Game.game_view:draw()

    if Game.debug_lab_grid then
        Game.game_view:drawLabGrid()
    end

    Game.zoom_controls:draw(Game)
    Game.ui_manager.modal_manager:draw(Game)
    
    if Game.input_controller:isDebugMenuVisible() then
        Game.input_controller:getDebugMenuView():draw()
    end
end

function love.keypressed(key)
    Game.input_controller:keypressed(key)
    
    -- WFC Testing Controls
    if key == "w" or key == "e" then
        print("=== Testing WFC Grid Generation ===")
        local NewCityGenService = require("services.NewCityGenService")
        local wfc_params = {
            width = (key == "w") and 32 or 64,
            height = (key == "w") and 24 or 48,
            use_wfc_for_zones = true,
        }
        local result = NewCityGenService.generateDetailedCity(wfc_params)
        if result and result.city_grid then
            Game.lab_grid = result.city_grid
            Game.lab_zone_grid = result.zone_grid
            print("WFC SUCCESS!")
        else
            print("WFC FAILED!")
        end
    end
    
    -- Arterial road generation test
    if key == "r" then
        print("=== Generating and SAVING Arterial Roads ===")
        if Game.lab_grid and Game.lab_zone_grid then
            local NewCityGenService = require("services.NewCityGenService")
            local arterial_params = { num_arterials = 4, min_edge_distance = 15 }
            
            -- This function now returns the paths it generated
            local success, generated_paths = NewCityGenService.generateArterialsOnly(Game.lab_grid, Game.lab_zone_grid, arterial_params)
            
            if success then
                -- Save the control points for the 'Y' key to use
                Game.arterial_control_paths = generated_paths
                print("Arterial road generation SUCCESS! Saved " .. #Game.arterial_control_paths .. " paths.")
            else
                print("Arterial road generation FAILED!")
            end
        else
            print("ERROR: No lab grid available. Press 'W' or 'E' first.")
        end
    end

    -- Smooth overlay visualization key
    if key == "y" then
        print("=== Visualizing Smoothed Overlay from 'R' key data ===")
        if not Game.arterial_control_paths or #Game.arterial_control_paths == 0 then
            print("ERROR: No arterial paths found. Press 'R' to generate them first.")
            return
        end

        local MapGenerationService = require("services.MapGenerationService")
        Game.smooth_highway_overlay_paths = {} -- Clear previous overlay

        for _, control_points in ipairs(Game.arterial_control_paths) do
            -- The spline function gracefully handles paths with too few points
            local spline_path = MapGenerationService._generateSplinePoints(control_points, 10)
            if #spline_path > 1 then
                table.insert(Game.smooth_highway_overlay_paths, spline_path)
            end
        end
        print("Generated " .. #Game.smooth_highway_overlay_paths .. " smooth overlays from saved arterial paths.")
    end
    
    -- Clear test
    if key == "c" then
        Game.lab_grid = nil
        Game.lab_zone_grid = nil
        Game.arterial_control_paths = {} -- Clear saved R-key paths
        Game.smooth_highway_overlay_paths = {} -- Clear Y-key overlay
        print("=== Cleared lab grid and all overlays ===")
    end
    
    if key == "t" then
        Game.show_districts = not Game.show_districts
        print("=== Toggled district visibility to: " .. tostring(Game.show_districts) .. " ===")
    end
    
    if key == "h" then
        print("=== WFC Test Controls ===")
        print("W/E - Generate WFC city grid") 
        print("R - Generate grid-based arterials (and save their paths)")
        print("Y - Draw smooth overlay of the roads generated by 'R'")
        print("C - Clear lab grid and all overlays")
        print("T - Toggle district zone visibility")
        print("H - Show this help")
    end
end

function love.mousewheelmoved(x, y)
    Game.input_controller:mousewheelmoved(x, y)
end

function love.mousepressed(x, y, button)
    Game.input_controller:mousepressed(x, y, button)
end

function love.mousereleased(x, y, button)
    Game.input_controller:mousereleased(x, y, button)
end

function love.textinput(text)
    Game.input_controller:textinput(text)
end

function love.quit()
    Game.error_service.logInfo("Main", "Game shutting down...")
    
    local SaveService = require("services.SaveService")
    Game.error_service.withErrorHandling(function()
        SaveService.saveGame(Game.state, "lastsave.json")
        Game.error_service.logInfo("Main", "Game state saved on exit")
    end, "Exit Save")
    
    Game.error_service.withErrorHandling(function()
        Game.config.saveUserConfig()
    end, "Config Save")
    
    Game.error_service.saveLogsToFile()
    
    Game.error_service.logInfo("Main", "Shutdown complete")
    return false
end