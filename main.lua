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
        -- MODIFIED: From 'map' to 'maps' to hold multiple map instances
        maps = {
            city = require("models.Map"):new(C),
            region = require("models.Map"):new(C) -- Add a map for the region view
        },
        active_map_key = "city", -- The key of the map currently being viewed/simulated
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
        ui_view = nil
    }
    
    -- Try to load saved game
    local SaveService = require("services.SaveService")
    local save_data = SaveService.loadGame()
    
    Game.state = require("models.GameState"):new(C, Game)
    
    -- Apply save data if available
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

    -- MODIFIED: Generate the REGION map on startup now
    ErrorService.withErrorHandling(function()
        Game.maps.region:generateRegion()
    end, "Region Map Generation")
    
    Game.entities:init(Game)
    
    -- Font loading with error handling
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
    
    -- MODIFIED: Set the initial scale on the city map
    Game.maps.city:setScale(C.MAP.SCALES.DOWNTOWN)
    
    -- Set up auto-save timer
    local auto_save_interval = GameConfig.get("ui", "auto_save_interval")
    if auto_save_interval > 0 then
        Game.auto_save_timer = auto_save_interval
    end
    
    ErrorService.logInfo("Main", "Game initialization completed successfully")
end

function love.update(dt)
    Game.game_controller:update(dt)
    
    -- Handle auto-save
    if Game.auto_save_timer then
        Game.auto_save_timer = Game.auto_save_timer - dt
        if Game.auto_save_timer <= 0 then
            local SaveService = require("services.SaveService")
            Game.error_service.withErrorHandling(function()
                SaveService.saveGame(Game.state, "autosave.json")
            end, "Auto Save")
            
            -- Reset timer
            Game.auto_save_timer = Game.config.get("ui", "auto_save_interval")
        end
    end
end

function love.draw()
    Game.ui_view:draw()
    Game.game_view:draw()

    -- NEW: Draw the Lab Grid on top of the game world, but under the UI
    if Game.debug_lab_grid then
        Game.game_view:drawLabGrid()
    end

    Game.zoom_controls:draw(Game)
    Game.ui_manager.modal_manager:draw(Game)
    
    -- Draw debug menu on top of everything
    if Game.input_controller:isDebugMenuVisible() then
        Game.input_controller:getDebugMenuView():draw()
    end
end

function love.keypressed(key)
    Game.input_controller:keypressed(key)
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
    
    -- Save game state
    local SaveService = require("services.SaveService")
    Game.error_service.withErrorHandling(function()
        SaveService.saveGame(Game.state, "lastsave.json")
        Game.error_service.logInfo("Main", "Game state saved on exit")
    end, "Exit Save")
    
    -- Save configuration
    Game.error_service.withErrorHandling(function()
        Game.config.saveUserConfig()
    end, "Config Save")
    
    -- Save error logs
    Game.error_service.saveLogsToFile()
    
    Game.error_service.logInfo("Main", "Shutdown complete")
    return false -- Allow quit
end