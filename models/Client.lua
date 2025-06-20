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
    local C_GAMEPLAY = game.C.GAMEPLAY
    local C_EVENTS = game.C.EVENTS
    local upgrades = game.state.upgrades

    self.trip_timer = self.trip_timer - dt
    if self.trip_timer <= 0 then
        local min_time = C_GAMEPLAY.TRIP_GENERATION_MIN_SEC * upgrades.trip_gen_min_mult
        local max_time = C_GAMEPLAY.TRIP_GENERATION_MAX_SEC * upgrades.trip_gen_max_mult
        self.trip_timer = love.math.random(min_time, max_time)
        
        if #game.entities.trips.pending < upgrades.max_pending_trips then
            local base_payout = C_GAMEPLAY.BASE_TRIP_PAYOUT
            local speed_bonus = C_GAMEPLAY.INITIAL_SPEED_BONUS
            
            local trucks_exist = false
            for _, v in ipairs(game.entities.vehicles) do
                if v.type == "truck" then
                    trucks_exist = true
                    break
                end
            end

            if trucks_exist and love.math.random() < 0.3 then
                local city_plot = game.map:getRandomCityBuildingPlot()
                if city_plot then
                    base_payout = base_payout * C_GAMEPLAY.CITY_TRIP_PAYOUT_MULTIPLIER
                    speed_bonus = speed_bonus * C_GAMEPLAY.CITY_TRIP_BONUS_MULTIPLIER
                    local new_trip = Trip:new(base_payout, speed_bonus)
                    new_trip:addLeg(self.plot, game.entities.depot_plot, "bike")
                    new_trip:addLeg(game.entities.depot_plot, city_plot, "truck")
                    table.insert(game.entities.trips.pending, new_trip)
                    game.EventBus:publish("trip_created")
                    print("New multi-leg (bike->truck) trip generated!")
                end
            else
                local end_plot = game.map:getRandomDowntownBuildingPlot()
                if end_plot then
                    local new_trip = Trip:new(base_payout, speed_bonus)
                    new_trip:addLeg(self.plot, end_plot, "bike")
                    table.insert(game.entities.trips.pending, new_trip)
                    game.EventBus:publish("trip_created")
                end
            end
        end
    end
end

-- REMOVED THE DRAW FUNCTION FROM HERE

function Client:recalculatePixelPosition(game)
    self.px, self.py = game.map:getPixelCoords(self.plot.x, self.plot.y)
end

return Client