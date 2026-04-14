-- models/Client.lua
local Trip = require("models.Trip")
local TripGenerator = require("services.TripGenerator")
local Archetypes    = require("data.client_archetypes")

local Client = {}
Client.__index = Client

function Client:new(plot, game, city_map, archetype_id)
    local instance = setmetatable({}, Client)
    instance.plot     = plot  -- unified sub-cell coords
    instance.city_map = city_map or (game.maps and game.maps.city)
    local umap = game.maps and game.maps.unified
    if umap then
        instance.px, instance.py = umap:getPixelCoords(plot.x, plot.y)
    else
        instance.px, instance.py = game.maps.city:getPixelCoords(plot.x, plot.y)
    end
    instance.archetype       = archetype_id
    instance.trip_timer      = TripGenerator.calculateNextTripTime(game, archetype_id)
    instance.active          = true   -- when false, no new trips are generated
    instance.freq_mult       = 1.0    -- multiplies the inter-trip interval (>1 = less frequent)
    instance.trips_generated = 0
    instance.earnings        = 0

    instance.cargo           = {}
    return instance
end

-- Per-archetype base capacity plus the matching upgrade stat. New trips are
-- blocked once the client's cargo hits this number.
function Client:getEffectiveCapacity(game)
    local a = Archetypes.by_id[self.archetype] or Archetypes.by_id[Archetypes.default_id]
    local base  = a and a.capacity or 1
    local bonus = game.state.upgrades[self.archetype .. "_capacity_bonus"] or 0
    return base + bonus
end

function Client:update(dt, game)
    if game.entities.pause_trip_generation then return end
    if not self.active then return end
    self.trip_timer = self.trip_timer - dt
    if self.trip_timer <= 0 then
        local base_time = TripGenerator.calculateNextTripTime(game, self.archetype)
        self.trip_timer = base_time * math.max(0.1, self.freq_mult or 1.0)

        -- Cargo-full clients silently skip generation this cycle.
        if #self.cargo >= self:getEffectiveCapacity(game) then return end

        local new_trip = TripGenerator.generateTrip(self.plot, game, self.city_map, self.archetype)
        if new_trip then
            new_trip.source_client = self
            self.trips_generated   = (self.trips_generated or 0) + 1
            table.insert(self.cargo, new_trip)
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