-- main.lua
-- The main entry point. Owns all game systems.

function love.load()
    local C = require("core.constants")

    -- The Game object holds all our systems.
    Game = {
        C = C, -- Add the constants table to our Game object
        EventBus = require("core.event_bus"),
        state = nil, -- state needs access to Game, so we initialize it after
        time = require("core.time"):new(),
        map = require("game.map"):new(C),
        entities = require("game.entities"):new(),
        autodispatcher = require("game.autodispatcher"):new(C),
        event_spawner = require("game.event_spawner"):new(C),
        pathfinder = require("lib.pathfinder"),
        fonts = {},
        debug_mode = false,
        ui = nil, -- Initialize UI module placeholder
    }
    
    -- State needs a reference to the Game object to subscribe to events
    Game.state = require("core.state"):new(C, Game)
    Game.ui = require("ui.ui"):new(C, Game) -- Create the UI module

    Game.map:generate()
    Game.entities:init(Game) -- Pass the Game object for dependency access
    
    local uiFont = love.graphics.newFont(C.UI.FONT_PATH_MAIN, C.UI.FONT_SIZE_UI)
    local emojiFont = love.graphics.newFont(C.UI.FONT_PATH_EMOJI, C.UI.FONT_SIZE_EMOJI)

    uiFont:setFallbacks(emojiFont)
    emojiFont:setFallbacks(uiFont)

    Game.fonts.ui = uiFont
    Game.fonts.emoji = emojiFont

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

function love.update(dt)
    -- Pass the Game object to all update functions that need it.
    Game.state:update(dt, Game) 
    Game.time:update(dt, Game)
    Game.entities:update(dt, Game)
    Game.autodispatcher:update(dt, Game)
    Game.event_spawner:update(dt, Game)
    Game.ui:update(dt, Game) -- This line was missing
end

function love.draw()
    local sidebar_w = Game.C.UI.SIDEBAR_WIDTH
    local screen_w, screen_h = love.graphics.getDimensions()

    -- === PASS 1: DRAW THE SIDEBAR ===
    love.graphics.setScissor(0, 0, sidebar_w, screen_h)
    
    love.graphics.setColor(Game.C.MAP.COLORS.UI_BG)
    love.graphics.rectangle("fill", 0, 0, sidebar_w, screen_h)
    
    Game.ui:draw(Game)
    
    love.graphics.setScissor() -- Disable scissor

    -- === PASS 2: DRAW THE GAME WORLD ===
    love.graphics.setScissor(sidebar_w, 0, screen_w - sidebar_w, screen_h)
    
    love.graphics.push()
    love.graphics.translate(sidebar_w, 0) -- Shift the coordinate system
    
    Game.map:draw()
    Game.entities:draw(Game)

    -- Draw the hover line and pins HERE, inside the map's scissor and coordinate system.
    if Game.ui.hovered_trip_index then
        -- FIX: Get trips from the correct module (entities, not state)
        local trip = Game.entities.trips.pending[Game.ui.hovered_trip_index]
        if trip and trip.legs[trip.current_leg] then
            -- FIX: Get start/end plots from the trip's leg structure
            local leg = trip.legs[trip.current_leg]
            local start_node = Game.map:findNearestRoadTile(leg.start_plot)
            local end_node = Game.map:findNearestRoadTile(leg.end_plot)
            
            if start_node and end_node then
                local path = Game.pathfinder.findPath(Game.map.grid, start_node, end_node)
                
                if path then
                    local pixel_path = {}
                    for _, node in ipairs(path) do
                        local px, py = Game.map:getPixelCoords(node.x, node.y)
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

    -- Draw the floating payout texts
    love.graphics.setFont(Game.fonts.ui)
    for _, ft in ipairs(Game.state.floating_texts) do
        love.graphics.setColor(1, 1, 0.8, ft.alpha) -- Set color with fade
        love.graphics.printf(ft.text, ft.x, ft.y, 150, "center")
    end
    
    love.graphics.pop()

    love.graphics.setScissor() -- Disable scissor
end

function love.mousepressed(x, y, button)
    if button == 1 then
        -- If the click is inside the sidebar...
        if x < Game.C.UI.SIDEBAR_WIDTH then
            Game.ui:handle_click(x, y, Game)
        else
            -- The click is in the game world, so we must translate the coordinate
            -- and then check for clicks on the event spawner first.
            local world_x = x - Game.C.UI.SIDEBAR_WIDTH
            local event_handled = Game.event_spawner:handle_click(world_x, y, Game)
            
            -- If the event icon wasn't clicked, then check for entities.
            if not event_handled then
                Game.entities:handle_click(world_x, y, Game)
            end
        end
    end
end