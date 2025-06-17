-- game/entities.lua
local Client = require("game.client")
local Vehicle = require("game.vehicle")

local Entities = {}
Entities.__index = Entities

function Entities:new()
    local instance = setmetatable({}, Entities)
    instance.depot_plot = nil -- Store the main depot location
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
        table.insert(game.state.clients, new_client)
        print("New client added.")
    end
end

function Entities:addVehicle(game)
    if self.depot_plot then
        local new_id = #game.state.vehicles + 1
        local new_vehicle = Vehicle:new(new_id, self.depot_plot, game)
        table.insert(game.state.vehicles, new_vehicle)
        print("New vehicle #" .. new_id .. " purchased.")
    end
end

function Entities:update(dt, game)
    for _, client in ipairs(game.state.clients) do
        client:update(dt, game)
    end
    for _, vehicle in ipairs(game.state.vehicles) do
        vehicle:update(dt, game)
    end
end

function Entities:draw(game)
    for _, client in ipairs(game.state.clients) do
        -- FIX: Pass the 'game' object to the draw function, just like with vehicles.
        client:draw(game)
    end
    for _, vehicle in ipairs(game.state.vehicles) do
        vehicle:draw(game)
    end
end

-- This now ONLY handles clicks on game objects, not UI.
function Entities:handle_click(x, y, game)
    -- Check if the click landed on any vehicle
    for _, vehicle in ipairs(game.state.vehicles) do
        local dist_sq = (x - vehicle.px)^2 + (y - vehicle.py)^2
        if dist_sq < 100 then -- Clicked within 10 pixels
            game.state.selected_vehicle = vehicle
            print("Selected bike " .. vehicle.id)
            return true -- Click was handled by selecting a vehicle
        end
    end

    -- If the code reaches here, the click was in the game world but not on a vehicle.
    -- This is the correct place to deselect.
    game.state.selected_vehicle = nil
    return false -- No entity handled the click
end


return Entities