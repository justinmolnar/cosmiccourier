function love.load()
    local C = require("core.constants")

    Game = {
        C = C,
        EventBus = require("core.event_bus"),
        state = nil,
        time = require("core.time"):new(),
        map = require("game.map"):new(C),
        entities = require("game.entities"):new(),
        autodispatcher = require("game.autodispatcher"):new(C),
        event_spawner = require("game.event_spawner"):new(C),
        pathfinder = require("lib.pathfinder"),
        fonts = {},
        debug_mode = false,
        ui = nil,
        zoom_controls = nil,
    }
    
    Game.map.scale_grids = {}

    Game.state = require("core.state"):new(C, Game)
    Game.ui = require("ui.ui"):new(C, Game)
    Game.zoom_controls = require("ui.zoom_controls"):new(C)

    -- Set up the event listener for entities AFTER the event bus is created
    Game.entities.event_bus_listener_setup(Game)

    Game.map:generate()
    Game.entities:init(Game)
    
    local uiFont = love.graphics.newFont(C.UI.FONT_PATH_MAIN, C.UI.FONT_SIZE_UI)
    local uiFontSmall = love.graphics.newFont(C.UI.FONT_PATH_MAIN, C.UI.FONT_SIZE_UI_SMALL)
    local emojiFont = love.graphics.newFont(C.UI.FONT_PATH_EMOJI, C.UI.FONT_SIZE_EMOJI)
    local emojiFontUI = love.graphics.newFont(C.UI.FONT_PATH_EMOJI, C.UI.FONT_SIZE_EMOJI_UI)

    uiFont:setFallbacks(emojiFontUI, emojiFont)
    uiFontSmall:setFallbacks(emojiFontUI, emojiFont)
    emojiFont:setFallbacks(uiFont, uiFontSmall)
    emojiFontUI:setFallbacks(uiFont, uiFontSmall)

    Game.fonts.ui = uiFont
    Game.fonts.ui_small = uiFontSmall
    Game.fonts.emoji = emojiFont
    Game.fonts.emoji_ui = emojiFontUI

    love.graphics.setFont(Game.fonts.ui)
end

function love.keypressed(key)
    if key == "`" then
        Game.debug_mode = not Game.debug_mode
        print("Debug mode set to: " .. tostring(Game.debug_mode))
    elseif key == "-" then
        Game.state.money = Game.state.money - 10000
        print("DEBUG: Removed 10,000 money.")
    elseif key == "=" then
        Game.state.money = Game.state.money + 10000
        print("DEBUG: Added 10,000 money.")
    end
end

function love.mousewheelmoved(x, y)
    Game.ui:handle_scroll(y)
end

function love.update(dt)
    Game.state:update(dt, Game) 
    Game.time:update(dt, Game)
    Game.map:update(dt, Game) -- Pass the Game object here
    Game.entities:update(dt, Game)
    Game.autodispatcher:update(dt, Game)
    Game.event_spawner:update(dt, Game)
    Game.ui:update(dt, Game)
    Game.zoom_controls:update(Game)
end

function love.draw()
    local sidebar_w = Game.C.UI.SIDEBAR_WIDTH
    local screen_w, screen_h = love.graphics.getDimensions()

    -- === PASS 1: DRAW THE SIDEBAR ===
    love.graphics.setScissor(0, 0, sidebar_w, screen_h)
    love.graphics.setColor(Game.C.MAP.COLORS.UI_BG)
    love.graphics.rectangle("fill", 0, 0, sidebar_w, screen_h)
    Game.ui:draw(Game)
    love.graphics.setScissor()

    -- === PASS 2: DRAW THE GAME WORLD ===
    love.graphics.setScissor(sidebar_w, 0, screen_w - sidebar_w, screen_h)
    love.graphics.push()
    love.graphics.translate(sidebar_w, 0)
    Game.map:draw()
    Game.entities:draw(Game)
    Game.event_spawner:draw(Game)

    -- THIS IS THE COMPLETELY REWRITTEN AND CORRECTED PATH PREVIEW LOGIC
    if Game.ui.hovered_trip_index then
        local trip = Game.entities.trips.pending[Game.ui.hovered_trip_index]
        if trip and trip.legs[trip.current_leg] then
            local leg = trip.legs[trip.current_leg]
            
            local path_grid, start_node, end_node
            
            -- Determine the correct grid and find nodes based on the vehicle required for the leg
            if leg.vehicleType == "bike" then
                path_grid = Game.map.scale_grids[Game.C.MAP.SCALES.DOWNTOWN]
                start_node = Game.map:findNearestDowntownRoadTile(leg.start_plot)
                end_node = Game.map:findNearestDowntownRoadTile(leg.end_plot)
            else -- Assumes truck or other city-scale vehicles
                path_grid = Game.map.scale_grids[Game.C.MAP.SCALES.CITY]
                start_node = Game.map:findNearestRoadTile(leg.start_plot) -- uses current grid, which is what we want for city vehicles
                end_node = Game.map:findNearestRoadTile(leg.end_plot)
            end

            if start_node and end_node and path_grid then
                -- This call is now guaranteed to have the correct grid and the required costs table
                local path = Game.pathfinder.findPath(path_grid, start_node, end_node, Game.C.GAMEPLAY.PATHFINDING_COSTS)
                
                if path then
                    local pixel_path = {}
                    for _, node in ipairs(path) do
                        -- Get pixel coordinates relative to the *correct* grid for the leg
                        local px, py
                        if leg.vehicleType == "bike" then
                            px, py = Game.map:getDowntownPixelCoords(node.x, node.y)
                        else
                             px, py = Game.map:getPixelCoords(node.x, node.y)
                        end
                        table.insert(pixel_path, px)
                        table.insert(pixel_path, py)
                    end
                    
                    local hover_color = Game.C.MAP.COLORS.HOVER
                    love.graphics.setColor(hover_color[1], hover_color[2], hover_color[3], 0.7)
                    love.graphics.setLineWidth(3)
                    love.graphics.line(pixel_path)
                    love.graphics.setLineWidth(1)
                    
                    love.graphics.setColor(hover_color)
                    love.graphics.circle("fill", pixel_path[1], pixel_path[2], 5)
                    love.graphics.circle("fill", pixel_path[#pixel_path-1], pixel_path[#pixel_path], 5)
                end
            end
        end
    end

    love.graphics.setFont(Game.fonts.ui)
    for _, ft in ipairs(Game.state.floating_texts) do
        love.graphics.setColor(1, 1, 0.8, ft.alpha)
        love.graphics.printf(ft.text, ft.x, ft.y, 150, "center")
    end
    
    love.graphics.pop()
    love.graphics.setScissor()

    -- === PASS 3: DRAW ZOOM CONTROLS (outside scissor) ===
    Game.zoom_controls:draw(Game)
end

function love.mousepressed(x, y, button)
    if Game.ui:handle_mouse_down(x, y, button) then
        return
    end

    if button == 1 then
        -- Check zoom controls first (they're outside the scissor area)
        if Game.zoom_controls:handle_click(x, y, Game) then
            return
        end
        
        if x < Game.C.UI.SIDEBAR_WIDTH then
            Game.ui:handle_click(x, y, Game)
        else
            local world_x = x - Game.C.UI.SIDEBAR_WIDTH
            local event_handled = Game.event_spawner:handle_click(world_x, y, Game)
            
            if not event_handled then
                Game.entities:handle_click(world_x, y, Game)
            end
        end
    end
end

function love.mousereleased(x, y, button)
    Game.ui:handle_mouse_up(x, y, button)
end