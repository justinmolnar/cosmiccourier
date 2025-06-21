-- models/Client.lua
local Trip = require("models.Trip")

local Client = {}
Client.__index = Client

function Client:new(plot, game)
    local instance = setmetatable({}, Client)
    instance.plot = plot
    -- MODIFIED: Use game.maps.city to get pixel coordinates
    instance.px, instance.py = game.maps.city:getPixelCoords(plot.x, plot.y)
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
    -- MODIFIED: Get coordinates from the active map
    local active_map = game.maps[game.active_map_key]
    if active_map then
        self.px, self.py = active_map:getPixelCoords(self.plot.x, self.plot.y)
    end
end

return Client