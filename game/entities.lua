-- game/entities.lua
local Client = require("game.client")
local Vehicle = require("game.vehicle")

local Entities = {}
Entities.__index = Entities

function Entities:new()
    local instance = setmetatable({}, Entities)
    instance.depot_plot = nil -- Store the main depot location
    
    -- Entities now owns all the game objects
    instance.vehicles = {}
    instance.clients = {}
    instance.trips = { pending = {} }
    instance.selected_vehicle = nil

    return instance
end

function Entities:init(game)
    -- Create the first Client
    self:addClient(game)

    -- Create the first Bike's depot
    self.depot_plot = game.map:getRandomBuildingPlot()
    self:addVehicle(game)
end

function Entities:addClient(game)
    local client_plot = game.map:getRandomBuildingPlot()
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
        local VehicleClass = require("game." .. vehicleType)
        if not VehicleClass then
            print("ERROR: Could not find vehicle class for type: " .. vehicleType)
            return
        end

        local new_id = #self.vehicles + 1
        local new_vehicle = VehicleClass:new(new_id, self.depot_plot, game)
        table.insert(self.vehicles, new_vehicle)
        print("New " .. vehicleType .. " #" .. new_id .. " purchased.")
    end
end

function Entities:update(dt, game)
    -- Tick down the speed bonus for ALL active trips
    -- 1. Pending trips
    for _, trip in ipairs(self.trips.pending) do
        trip.speed_bonus = math.max(0, trip.speed_bonus - dt)
    end
    -- 2. Trips assigned to vehicles (in queue or cargo)
    for _, vehicle in ipairs(self.vehicles) do
        for _, trip in ipairs(vehicle.trip_queue) do
            trip.speed_bonus = math.max(0, trip.speed_bonus - dt)
        end
        for _, trip in ipairs(vehicle.cargo) do
            trip.speed_bonus = math.max(0, trip.speed_bonus - dt)
        end
    end

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
    for _, client in ipairs(self.clients) do
        -- FIX: Pass the 'game' object to the draw function, just like with vehicles.
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