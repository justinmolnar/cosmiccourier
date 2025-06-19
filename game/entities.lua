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

    -- This is a placeholder. The 'game' object isn't available right at this moment.
    -- We will set up the real subscription in main.lua's love.load function.
    instance.event_bus_listener_setup = function(game)
        game.EventBus:subscribe("map_scale_changed", function()
            print("Map scale changed! Recalculating all entity positions...")
            
            -- Recalculate for vehicles
            for _, vehicle in ipairs(instance.vehicles) do
                if vehicle.recalculatePixelPosition then
                    vehicle:recalculatePixelPosition(game)
                end
            end
    
            -- Recalculate for clients
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

    -- Create the first Bike's depot
    self.depot_plot = game.map:getRandomBuildingPlot()
    self:addVehicle(game, "bike")  -- ADD "bike" parameter
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
    -- *** ADD THIS NEW BLOCK TO DRAW THE DEPOT ***
    if self.depot_plot then
        local depot_gx, depot_gy -- Grid X and Grid Y
        
        if game.map:getCurrentScale() == game.C.MAP.SCALES.DOWNTOWN then
            -- In downtown view, use the plot's local coordinates
            depot_gx = self.depot_plot.x
            depot_gy = self.depot_plot.y
        else
            -- In city view, calculate the position using the stored offset
            depot_gx = game.map.downtown_offset.x + self.depot_plot.x
            depot_gy = game.map.downtown_offset.y + self.depot_plot.y
        end

        -- Get the final pixel coordinates and draw the depot icon
        local depot_px, depot_py = game.map:getPixelCoords(depot_gx, depot_gy)
        love.graphics.setFont(game.fonts.emoji)
        love.graphics.setColor(0, 0, 0)
        love.graphics.print("🏠", depot_px - 14, depot_py - 14)
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