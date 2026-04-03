local function _initCore()
    love.math.setRandomSeed(os.time(), math.floor(os.clock() * 1000000))

    local ErrorService = require("services.ErrorService")
    ErrorService.initialize({
        log_level = 2,
        log_to_file = true,
        show_error_popups = true
    })

    local GameConfig = require("config.GameConfig")
    GameConfig.initialize()

    local C = require("data.constants")
    local ConstantsValidator = require("data.ConstantsValidator")
    ErrorService.withErrorHandling(function()
        ConstantsValidator.validate(C)
    end, "Constants Validation")

    local is_fullscreen = GameConfig.get("graphics", "fullscreen")
    love.window.setMode(
        is_fullscreen and 0 or GameConfig.get("graphics", "window_width"),
        is_fullscreen and 0 or GameConfig.get("graphics", "window_height"),
        {
            fullscreen = is_fullscreen,
            fullscreentype = "desktop",
            vsync = GameConfig.get("graphics", "vsync")
        }
    )

    return C
end

local function _buildGame(C)
    local ErrorService = require("services.ErrorService")
    local GameConfig   = require("config.GameConfig")

    Game = {
        C = C,
        config = GameConfig,
        error_service = ErrorService,
        EventBus = require("core.event_bus"),
        state = nil,
        time = require("core.time"):new(),
        maps = {
            city   = require("models.Map"):new(C),
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
        -- Default overlays: hide road grid, show arterial smooth + J street overlay
        debug_hide_roads = true,
        debug_smooth_roads = true,
        debug_smooth_roads_like = true,
        debug_smooth_vehicle_movement = false,
    }

    return Game
end

local function _loadSave(Game)
    local SaveService = require("services.SaveService")
    local save_data = SaveService.loadGame()

    Game.state = require("models.GameState"):new(Game.C, Game)

    if save_data then
        Game.error_service.withErrorHandling(function()
            SaveService.applySaveData(Game.state, save_data)
            Game.error_service.logInfo("Main", "Save game loaded successfully")
        end, "Save Game Loading")
    end
end

local function _initSystems(Game)
    local UIManager = require("views.UIManager")

    Game.ui_manager    = UIManager:new(Game.C, Game)
    Game.zoom_controls = require("views.components.ZoomControls"):new(Game.C)

    Game.entities.event_bus_listener_setup(Game)

    Game.game_controller = require("controllers.GameController"):new(Game)
    Game.input_controller = require("controllers.InputController"):new(Game)
    Game.game_view = require("views.GameView"):new(Game)
    Game.ui_view   = require("views.UIView"):new(Game)

    Game.world_sandbox_controller    = require("controllers.WorldSandboxController"):new(Game)
    Game.world_sandbox_view          = require("views.WorldSandboxView"):new(Game)
    Game.world_sandbox_sidebar_view  = require("views.WorldSandboxSidebarView"):new(Game)
end

local function _initInputDispatcher(Game)
    local InputDispatcher = require("lib.input_dispatcher")
    Game.input_dispatcher = InputDispatcher:new()
    local wsc = Game.world_sandbox_controller
    local ic  = Game.input_controller

    -- keypressed has special routing: f8 toggles sandbox, sandbox gets priority, fallback to ic
    Game.input_dispatcher:on("keypressed",
        function(k) return k == "f8" end,
        function()  wsc:toggle() end)
    Game.input_dispatcher:on("keypressed",
        function()  return wsc:isActive() end,
        function(k) wsc:handle_keypressed(k) end)
    Game.input_dispatcher:on("keypressed", nil,
        function(k) ic:keypressed(k) end)

    -- All other events: sandbox gets priority when active, fallback to input_controller
    local routes = {
        { "mousewheelmoved",  function(x,y)       wsc:handle_mouse_wheel(x,y)          end, function(x,y)       ic:mousewheelmoved(x,y)    end },
        { "mousepressed",     function(x,y,b)     wsc:handle_mouse_down(x,y,b)         end, function(x,y,b)     ic:mousepressed(x,y,b)     end },
        { "mousereleased",    function(x,y,b)     wsc:handle_mouse_up(x,y,b)           end, function(x,y,b)     ic:mousereleased(x,y,b)    end },
        { "mousemoved",       function(x,y,dx,dy) wsc:handle_mouse_moved(x,y,dx,dy)    end, function(x,y,dx,dy) ic:mousemoved(x,y,dx,dy)   end },
        { "textinput",        function(t)         wsc:handle_textinput(t)              end, function(t)         ic:textinput(t)            end },
    }
    for _, r in ipairs(routes) do
        Game.input_dispatcher:on(r[1], function() return wsc:isActive() end, r[2])
        Game.input_dispatcher:on(r[1], nil, r[3])
    end

    Game.entities:init(Game)
end

local function _loadFonts(Game)
    Game.error_service.withErrorHandling(function()
        local C = Game.C
        local uiFont     = love.graphics.newFont(C.UI.FONT_PATH_MAIN,  C.UI.FONT_SIZE_UI)
        local uiFontSmall = love.graphics.newFont(C.UI.FONT_PATH_MAIN, C.UI.FONT_SIZE_UI_SMALL)
        local emojiFont   = love.graphics.newFont(C.UI.FONT_PATH_EMOJI, C.UI.FONT_SIZE_EMOJI)
        local emojiFontUI = love.graphics.newFont(C.UI.FONT_PATH_EMOJI, C.UI.FONT_SIZE_EMOJI_UI)
        local uiIconFont  = love.graphics.newFont(C.UI.FONT_PATH_EMOJI, C.UI.FONT_SIZE_UI)

        uiFont:setFallbacks(uiIconFont)
        uiFontSmall:setFallbacks(uiIconFont)
        emojiFont:setFallbacks(uiFont, uiFontSmall)
        emojiFontUI:setFallbacks(uiFont, uiFontSmall)

        Game.fonts.ui       = uiFont
        Game.fonts.ui_small = uiFontSmall
        Game.fonts.emoji    = emojiFont
        Game.fonts.emoji_ui = emojiFontUI

        love.graphics.setFont(Game.fonts.ui)
    end, "Font Loading")
end

local function _initWorld(Game)
    Game.error_service.withErrorHandling(function()
        local wsc = Game.world_sandbox_controller
        wsc.params.seed_x = love.math.random() * 1000
        wsc.params.seed_y = love.math.random() * 1000
        wsc:generate()
        wsc:place_cities()
        wsc:build_highways()
        wsc:regen_bounds()
        wsc:sendToGame()
    end, "World Auto-Generation")
end

local function _initAutoSave(Game)
    local auto_save_interval = Game.config.get("ui", "auto_save_interval")
    if auto_save_interval > 0 then
        Game.auto_save_timer = auto_save_interval
    end
end

-- =============================================================================

function love.load()
    local C = _initCore()
    local Game = _buildGame(C)
    collectgarbage("setpause", 300)
    collectgarbage("setstepmul", 400)
    _loadSave(Game)
    _initSystems(Game)
    _initInputDispatcher(Game)
    _loadFonts(Game)
    _initWorld(Game)
    _initAutoSave(Game)
    Game.error_service.logInfo("Main", "Game initialization completed successfully")
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
    if Game.world_sandbox_controller:isActive() then
        Game.world_sandbox_sidebar_view:draw()
        Game.world_sandbox_view:draw()
        return
    end

    Game.ui_view:draw()
    Game.game_view:draw()

    Game.zoom_controls:draw(Game)
    Game.ui_manager.modal_manager:draw(Game)
end

function love.keypressed(key)          Game.input_dispatcher:dispatch("keypressed", key) end
function love.wheelmoved(x, y)         Game.input_dispatcher:dispatch("mousewheelmoved", x, y) end
function love.mousepressed(x, y, b)    Game.input_dispatcher:dispatch("mousepressed", x, y, b) end
function love.mousereleased(x, y, b)   Game.input_dispatcher:dispatch("mousereleased", x, y, b) end
function love.mousemoved(x, y, dx, dy) Game.input_dispatcher:dispatch("mousemoved", x, y, dx, dy) end
function love.textinput(text)          Game.input_dispatcher:dispatch("textinput", text) end

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
