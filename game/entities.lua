-- game/entities.lua
local Client = require("game.client")
local Vehicle = require("game.vehicle")

local Entities = {}
Entities.__index = Entities

function Entities:new()
    local instance = setmetatable({}, Entities)
    instance.depot_plot = nil 
    
    instance.vehicles = {}
    instance.clients = {}
    instance.trips = { pending = {} }
    instance.selected_vehicle = nil

    instance.event_bus_listener_setup = function(game)
        game.EventBus:subscribe("map_scale_changed", function()
            print("Map scale changed! Recalculating all entity positions...")
            
            -- FIX: This logic was correct but wasn't being triggered properly before.
            -- This ensures ALL entities update their screen position when the camera moves.
            for _, vehicle in ipairs(instance.vehicles) do
                if vehicle.recalculatePixelPosition then
                    vehicle:recalculatePixelPosition(game)
                end
            end
    
            for _, client in ipairs(instance.clients) do
                if client.recalculatePixelPosition then
                    client:recalculatePixelPosition(game)
                end
            end
        end)
    end

    return instance
end

function Entities:init(game)
    -- Create the first Client
    self:addClient(game)

    -- FIX: The depot should start in a random DOWNTOWN building plot.
    self.depot_plot = game.map:getRandomDowntownBuildingPlot()
    self:addVehicle(game, "bike")
end

function Entities:addClient(game)
    -- FIX: Clients should only be generated in downtown building plots.
    local client_plot = game.map:getRandomDowntownBuildingPlot()
    if client_plot then
        local new_client = Client:new(client_plot, game)
        table.insert(self.clients, new_client)
        print("New client added.")
    end
end

function Entities:addVehicle(game, vehicleType)
    if not vehicleType then
        print("ERROR: addVehicle called without a vehicleType.")
        return
    end

    if self.depot_plot then
        -- The require path is now more dynamic based on vehicleType
        local VehicleClass = require("game." .. vehicleType)
        if not VehicleClass then
            print("ERROR: Could not find vehicle class for type: " .. vehicleType)
            return
        end

        local new_id = #self.vehicles + 1
        -- Pass the vehicleType to the constructor
        local new_vehicle = VehicleClass:new(new_id, self.depot_plot, game, vehicleType)
        table.insert(self.vehicles, new_vehicle)
        print("New " .. vehicleType .. " #" .. new_id .. " purchased.")
    end
end

function Entities:update(dt, game)
    local C_GAMEPLAY = game.C.GAMEPLAY
    
    -- Only decay bonuses for trips that are NOT in transit
    -- Pending trips (waiting for pickup)
    for _, trip in ipairs(self.trips.pending) do
        if not trip.is_in_transit then
            trip.speed_bonus = math.max(0, trip.speed_bonus - (dt * C_GAMEPLAY.BONUS_DECAY_RATE))
            trip.last_update_time = love.timer.getTime()
        end
    end
    
    -- Future: Hub inventories would also be checked here
    -- for _, hub in ipairs(self.hubs) do
    --     for _, trip in ipairs(hub.inventory) do
    --         if not trip.is_in_transit then
    --             trip.speed_bonus = math.max(0, trip.speed_bonus - (dt * C_GAMEPLAY.BONUS_DECAY_RATE))
    --             trip.last_update_time = love.timer.getTime()
    --         end
    --     end
    -- end

    -- Update clients
    for _, client in ipairs(self.clients) do
        client:update(dt, game)
    end
    
    -- Update vehicles
    for _, vehicle in ipairs(self.vehicles) do
        vehicle:update(dt, game)
    end
end

function Entities:draw(game)
    if self.depot_plot then
        local depot_px, depot_py = game.map:getPixelCoords(self.depot_plot.x, self.depot_plot.y)
        love.graphics.setFont(game.fonts.emoji)
        love.graphics.setColor(0, 0, 0)

        -- FIX: Apply a counter-scale to keep the icon size consistent
        love.graphics.push()
        love.graphics.translate(depot_px, depot_py)
        love.graphics.scale(1 / game.camera.scale, 1 / game.camera.scale)
        love.graphics.print("🏠", -14, -14) -- Center the emoji
        love.graphics.pop()
    end

    for _, client in ipairs(self.clients) do
        client:draw(game)
    end
    for _, vehicle in ipairs(self.vehicles) do
        vehicle:draw(game)
    end
end

function Entities:handle_click(x, y, game)
    -- Check if the click landed on any vehicle
    for _, vehicle in ipairs(self.vehicles) do
        local dist_sq = (x - vehicle.px)^2 + (y - vehicle.py)^2
        if dist_sq < 100 then -- Clicked within 10 pixels
            self.selected_vehicle = vehicle
            print("Selected bike " .. vehicle.id)
            return true -- Click was handled by selecting a vehicle
        end
    end

    -- If the code reaches here, the click was in the game world but not on a vehicle.
    -- This is the correct place to deselect.
    self.selected_vehicle = nil
    return false -- No entity handled the click
end


return Entities