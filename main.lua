function love.load()
    local C = require("data.constants")
    local GameController = require("controllers.GameController")
    local InputController = require("controllers.InputController")
    local GameView = require("views.GameView")
    local UIView = require("views.UIView")
    local UIManager = require("views.UIManager")

    Game = {
        C = C,
        EventBus = require("core.event_bus"),
        state = nil,
        time = require("core.time"):new(),
        map = require("models.Map"):new(C),
        entities = require("models.EntityManager"):new(),
        autodispatcher = require("models.AutoDispatcher"):new(C),
        event_spawner = require("models.EventSpawner"):new(C),
        pathfinder = require("lib.pathfinder"),
        fonts = {},
        debug_mode = false,
        ui_manager = nil,
        zoom_controls = nil,
        camera = require("core.camera"):new(0, 0, 1),
        game_controller = nil,
        input_controller = nil,
        game_view = nil,
        ui_view = nil
    }
    
    Game.state = require("models.GameState"):new(C, Game)
    Game.ui_manager = UIManager:new(C, Game)
    -- CORRECTED: The path now correctly points to the 'ZoomControls' component's new location.
    Game.zoom_controls = require("views.components.ZoomControls"):new(C)

    Game.entities.event_bus_listener_setup(Game)

    Game.game_controller = GameController:new(Game)
    Game.input_controller = InputController:new(Game)
    Game.game_view = GameView:new(Game)
    Game.ui_view = UIView:new(Game)

    Game.map:generate()
    Game.entities:init(Game)
    
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
    Game.map:setScale(C.MAP.SCALES.DOWNTOWN)
end

function love.update(dt)
    Game.game_controller:update(dt)
end

function love.draw()
    Game.ui_view:draw()
    Game.game_view:draw()
    Game.zoom_controls:draw(Game)
    Game.ui_manager.modal_manager:draw(Game)
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