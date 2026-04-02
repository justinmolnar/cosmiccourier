-- models/Client.lua
local Trip = require("models.Trip")

local Client = {}
Client.__index = Client

function Client:new(plot, game)
    local instance = setmetatable({}, Client)
    instance.plot = plot  -- unified sub-cell coords
    local umap = game.maps and game.maps.unified
    if umap then
        instance.px, instance.py = umap:getPixelCoords(plot.x, plot.y)
    else
        instance.px, instance.py = game.maps.city:getPixelCoords(plot.x, plot.y)
    end
    instance.trip_timer = love.math.random(5, 10)
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
    local umap = game.maps and game.maps.unified
    if umap then
        self.px, self.py = umap:getPixelCoords(self.plot.x, self.plot.y)
    end
end

return Client