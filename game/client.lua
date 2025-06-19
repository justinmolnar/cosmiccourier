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
    local upgrades = game.state.upgrades

    self.trip_timer = self.trip_timer - dt
    if self.trip_timer <= 0 then
        -- Reset timer using new upgradeable multipliers
        local min_time = C_GAMEPLAY.TRIP_GENERATION_MIN_SEC * upgrades.trip_gen_min_mult
        local max_time = C_GAMEPLAY.TRIP_GENERATION_MAX_SEC * upgrades.trip_gen_max_mult
        self.trip_timer = love.math.random(min_time, max_time)
        
        -- Use new upgradeable max pending trips value
        if #game.entities.trips.pending < upgrades.max_pending_trips then
            local trips_to_generate = 1
            -- Check if we should generate a bulk order
            if love.math.random() < upgrades.multi_trip_chance then
                trips_to_generate = upgrades.multi_trip_amount
                print("Bulk order generated!")
            end

            for i = 1, trips_to_generate do
                -- Check the cap again inside the loop in case we fill it up
                if #game.entities.trips.pending >= upgrades.max_pending_trips then break end
                
                -- *** FIX: Call the new function to get a guaranteed downtown plot ***
                local end_plot = game.map:getRandomDowntownBuildingPlot()
                
                if end_plot then
                    local new_trip = Trip:new(C_GAMEPLAY.BASE_TRIP_PAYOUT, C_GAMEPLAY.INITIAL_SPEED_BONUS)
                    table.insert(new_trip.legs, {
                        start_plot = self.plot,
                        end_plot = end_plot,
                        vehicleType = "bike" 
                    })
                    table.insert(game.entities.trips.pending, new_trip)
                end
            end
            
            if not game.state.rush_hour.active and trips_to_generate == 1 then
                print("New trip generated!")
            end
        end
    end
end

function Client:draw(game)
    if game.map:getCurrentScale() ~= game.C.MAP.SCALES.DOWNTOWN then
        return
    end

    love.graphics.setFont(game.fonts.emoji)
    love.graphics.setColor(0, 0, 0) -- Black
    love.graphics.print("🏢", self.px - 14, self.py - 14) -- Adjust offset for new size
    love.graphics.setFont(game.fonts.ui) -- Switch back to default UI font
end

function Client:recalculatePixelPosition(game)
    -- Clients, like bikes, exist only in the downtown grid.
    -- We can use the same specialized function to get their correct pixel coordinates.
    self.px, self.py = game.map:getDowntownPixelCoords(self.plot.x, self.plot.y)
end

return Client