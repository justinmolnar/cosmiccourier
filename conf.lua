-- conf.lua
-- This file is executed first by LÖVE to set up the game window and modules.

function love.conf(t)
    t.window.title = "Logistics Idler"
    t.window.width = 1280
    t.window.height = 720
    
    t.console = true -- ADD THIS LINE to enable the console window

    -- We don't need the physics module for this game, so we can disable it
    -- to save a little memory.
    t.modules.physics = false
end