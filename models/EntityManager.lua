-- models/EntityManager.lua
local Client = require("models.Client")

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
            
            print(string.format("DEBUG: Found %d vehicles to recalculate", #game.entities.vehicles))
            for i, vehicle in ipairs(game.entities.vehicles) do
                print(string.format("DEBUG: Recalculating vehicle %d (type: %s)", vehicle.id, vehicle.type))
                if vehicle.recalculatePixelPosition then
                    vehicle:recalculatePixelPosition(game)
                else
                    print(string.format("ERROR: Vehicle %d has no recalculatePixelPosition method!", vehicle.id))
                end
            end

            for _, client in ipairs(game.entities.clients) do
                if client.recalculatePixelPosition then
                    client:recalculatePixelPosition(game)
                end
            end
        end)
    end

    return instance
end

function Entities:init(game)
    -- MODIFIED: Use game.maps.city to find the depot plot
    self.depot_plot = game.maps.city:getRandomDowntownBuildingPlot()
    self:addClient(game)
    self:addVehicle(game, "bike")
end

function Entities:addClient(game)
    -- MODIFIED: Use game.maps.city to find a plot for the client
    local client_plot = game.maps.city:getRandomDowntownBuildingPlot()
    if client_plot then
        local new_client = Client:new(client_plot, game)
        table.insert(self.clients, new_client)
        print("New client added.")
    end
end

function Entities:addVehicle(game, vehicleType)
    local VehicleFactory = require("models.VehicleFactory")
    
    if not VehicleFactory.isValidVehicleType(vehicleType) then
        print("ERROR: Invalid vehicle type: " .. tostring(vehicleType))
        return
    end

    if not self.depot_plot then
        print("ERROR: No depot plot available for vehicle creation")
        return
    end

    local new_id = #self.vehicles + 1
    local new_vehicle = VehicleFactory.createVehicle(vehicleType, new_id, self.depot_plot, game)
    table.insert(self.vehicles, new_vehicle)
end

function Entities:update(dt, game)
    local C_GAMEPLAY = game.C.GAMEPLAY
    
    for _, trip in ipairs(self.trips.pending) do
        if not trip.is_in_transit then
            trip.speed_bonus = math.max(0, trip.speed_bonus - (dt * C_GAMEPLAY.BONUS_DECAY_RATE))
            trip.last_update_time = love.timer.getTime()
        end
    end

    for _, client in ipairs(self.clients) do
        client:update(dt, game)
    end
    
    for _, vehicle in ipairs(self.vehicles) do
        vehicle:update(dt, game)
    end
end

-- REMOVED THE DRAW FUNCTION FROM HERE

function Entities:handle_click(x, y, game)
    for _, vehicle in ipairs(self.vehicles) do
        local dist_sq = (x - vehicle.px)^2 + (y - vehicle.py)^2
        -- FIX: Use the click radius from the correct location in constants
        if dist_sq < game.C.UI.VEHICLE_CLICK_RADIUS * game.C.UI.VEHICLE_CLICK_RADIUS then
            self.selected_vehicle = vehicle
            print("Selected " .. vehicle.type .. " " .. vehicle.id)
            return true
        end
    end

    self.selected_vehicle = nil
    return false
end

return Entities