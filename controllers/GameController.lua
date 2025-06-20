-- controllers/GameController.lua
local GameController = {}
GameController.__index = GameController

function GameController:new(game_instance)
    local instance = setmetatable({}, GameController)
    instance.Game = game_instance
    return instance
end

function GameController:update(dt)
    local Game = self.Game

    -- Only update the game world if no modal is active
    if not Game.ui_manager.modal_manager:isActive() then
        Game.state:update(dt, Game) 
        Game.time:update(dt, Game)
        Game.map:update(dt, Game)
        Game.entities:update(dt, Game)
        Game.autodispatcher:update(dt, Game)
        Game.event_spawner:update(dt, Game)
        Game.zoom_controls:update(Game)
    end
    -- The UI Manager (and its modal manager) updates regardless
    Game.ui_manager:update(dt, Game)
end

return GameController