-- game/client.lua
local Trip = require("game.trip")

local Client = {}
Client.__index = Client

function Client:new(plot, game)
    local instance = setmetatable({}, Client)
    instance.plot = plot
    instance.px, instance.py = game.map:getPixelCoords(plot.x, plot.y)
    instance.trip_timer = love.math.random(5, 10) -- Time until next trip
    return instance
end

function Client:update(dt, game)
    local C_GAMEPLAY = game.C.GAMEPLAY
    local C_EVENTS = game.C.EVENTS

    self.trip_timer = self.trip_timer - dt
    if self.trip_timer <= 0 then
        if game.state.rush_hour.active then
            self.trip_timer = love.math.random(C_EVENTS.FRENZY_TRIP_MIN_SEC, C_EVENTS.FRENZY_TRIP_MAX_SEC)
        else
            self.trip_timer = love.math.random(C_GAMEPLAY.TRIP_GENERATION_MIN_SEC, C_GAMEPLAY.TRIP_GENERATION_MAX_SEC)
        end
        
        if #game.state.trips.pending < C_GAMEPLAY.MAX_PENDING_TRIPS then
            local end_plot = game.map:getRandomBuildingPlot()
            if end_plot then
                -- Create a new trip with a base payout and a starting speed bonus
                local new_trip = Trip:new(C_GAMEPLAY.BASE_TRIP_PAYOUT, C_GAMEPLAY.INITIAL_SPEED_BONUS)
                new_trip.start_plot = self.plot
                new_trip.end_plot = end_plot

                table.insert(game.state.trips.pending, new_trip)
                if not game.state.rush_hour.active then
                    print("New trip generated!")
                end
            end
        end
    end
end

function Client:draw(game)
    love.graphics.setFont(game.fonts.emoji)
    love.graphics.setColor(0, 0, 0) -- Black
    love.graphics.print("🏢", self.px - 14, self.py - 14) -- Adjust offset for new size
    love.graphics.setFont(game.fonts.ui) -- Switch back to default UI font
end

return Client