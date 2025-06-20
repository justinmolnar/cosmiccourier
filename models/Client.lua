-- models/Client.lua
local Trip = require("models.Trip")

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
    local TripGenerator = require("services.TripGenerator")
    
    self.trip_timer = self.trip_timer - dt
    if self.trip_timer <= 0 then
        self.trip_timer = TripGenerator.calculateNextTripTime(game)
        
        local new_trip = TripGenerator.generateTrip(self.plot, game)
        if new_trip then
            table.insert(game.entities.trips.pending, new_trip)
            game.EventBus:publish("trip_created")
        end
    end
end

-- REMOVED THE DRAW FUNCTION FROM HERE

function Client:recalculatePixelPosition(game)
    self.px, self.py = game.map:getPixelCoords(self.plot.x, self.plot.y)
end

return Client