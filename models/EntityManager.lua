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
    self:addClient(game)
    self.depot_plot = game.map:getRandomDowntownBuildingPlot()
    self:addVehicle(game, "bike")
end

function Entities:addClient(game)
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
        local VehicleClass = require("models.vehicles." .. vehicleType)
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
        if dist_sq < game.C.GAMEPLAY.VEHICLE_CLICK_RADIUS * game.C.GAMEPLAY.VEHICLE_CLICK_RADIUS then
            self.selected_vehicle = vehicle
            print("Selected " .. vehicle.type .. " " .. vehicle.id)
            return true
        end
    end

    self.selected_vehicle = nil
    return false
end

return Entities