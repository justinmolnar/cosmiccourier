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

-- Mirrors Depot:getCity — finds the city_map containing this client's plot.
function Client:getCity(game)
    if not self.plot then return nil end
    local px, py = self.plot.x, self.plot.y
    for _, cmap in ipairs(game.maps and game.maps.all_cities or {}) do
        local ox = (cmap.world_mn_x - 1) * 3
        local oy = (cmap.world_mn_y - 1) * 3
        local lx = px - ox
        local ly = py - oy
        if lx >= 1 and ly >= 1
        and cmap.grid and lx <= #(cmap.grid[1] or {}) and ly <= #cmap.grid then
            return cmap
        end
    end
    return nil
end

function Client:getDistrict(game)
    local city_map = self:getCity(game)
    if not city_map or not city_map.district_map or not city_map.district_types then return nil end
    local sub_w = (game.world_w or 0) * 3
    if sub_w == 0 then return nil end
    local sci = (self.plot.y - 1) * sub_w + self.plot.x
    local poi_idx = city_map.district_map[sci]
    if poi_idx then return city_map.district_types[poi_idx] end
    return nil
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