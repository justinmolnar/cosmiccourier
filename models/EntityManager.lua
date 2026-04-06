-- models/EntityManager.lua
local Client        = require("models.Client")
local PathScheduler = require("services.PathScheduler")

local Entities = {}
Entities.__index = Entities

function Entities:new()
    local instance = setmetatable({}, Entities)
    instance.depot_plot     = nil
    instance.vehicles       = {}
    instance.clients        = {}
    instance.trips          = { pending = {} }
    instance.selected_vehicle = nil

    instance.event_bus_listener_setup = function(game)
        game.EventBus:subscribe("map_scale_changed", function()
            for _, vehicle in ipairs(game.entities.vehicles) do
                if vehicle.recalculatePixelPosition then
                    vehicle:recalculatePixelPosition(game)
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
    self.depot_plot = game.maps.city:getRandomDowntownBuildingPlot()
    self:addClient(game)
    -- Start with the cheapest available vehicle type.
    local starter_id, starter_cost = nil, math.huge
    for id, vcfg in pairs(game.C.VEHICLES) do
        if vcfg.base_cost < starter_cost then
            starter_id   = id:lower()
            starter_cost = vcfg.base_cost
        end
    end
    if starter_id then self:addVehicle(game, starter_id) end
end

function Entities:addClient(game)
    local cmap = game.maps.city
    local plot_local = cmap:getRandomDowntownBuildingPlot()
    if plot_local then
        local plot = (cmap.world_mn_x and game.maps.unified) and {
            x = (cmap.world_mn_x - 1) * 3 + plot_local.x,
            y = (cmap.world_mn_y - 1) * 3 + plot_local.y,
        } or plot_local
        local new_client = Client:new(plot, game)
        table.insert(self.clients, new_client)
    end
end

function Entities:addVehicle(game, vehicleType)
    local VehicleFactory = require("models.VehicleFactory")
    if not VehicleFactory.isValidVehicleType(vehicleType, game) then return end
    if not self.depot_plot then return end
    local new_id = #self.vehicles + 1
    local new_vehicle = VehicleFactory.createVehicle(vehicleType, new_id, self.depot_plot, game)
    table.insert(self.vehicles, new_vehicle)
end

function Entities:update(dt, game)
    local C_GAMEPLAY = game.C.GAMEPLAY
    local decay = dt * C_GAMEPLAY.BONUS_DECAY_RATE

    PathScheduler.flush()

    -- Decay speed bonuses on pending (non-transit) trips.
    for _, trip in ipairs(self.trips.pending) do
        if not trip.is_in_transit then
            local b = trip.speed_bonus - decay
            trip.speed_bonus = b < 0 and 0 or b
        end
    end

    for _, client in ipairs(self.clients) do
        client:update(dt, game)
    end

    -- Cache viewport bounds once per frame so shouldUseAbstractedSimulation can
    -- cull off-screen vehicles with 4 cheap comparisons instead of per-vehicle camera math.
    local cs     = game.camera.scale
    local cx, cy = game.camera.x, game.camera.y
    local sw     = love.graphics.getWidth()
    local sh     = love.graphics.getHeight()
    local sidebar = game.C.UI.SIDEBAR_WIDTH
    local half_w  = (sw - sidebar) * 0.5 / cs
    local half_h  = sh * 0.5 / cs
    if not game._vp then game._vp = {} end
    local vp = game._vp
    vp.left  = cx - half_w;  vp.right = cx + half_w
    vp.top   = cy - half_h;  vp.bot   = cy + half_h

    for _, vehicle in ipairs(self.vehicles) do
        vehicle:update(dt, game)
    end
end

function Entities:handle_click(x, y, game)
    local click_r    = game.C.UI.VEHICLE_CLICK_RADIUS / game.camera.scale
    local radius_sq  = click_r * click_r
    local candidates = {}
    for _, vehicle in ipairs(self.vehicles) do
        local dist_sq = (x - vehicle.px)^2 + (y - vehicle.py)^2
        if dist_sq < radius_sq then
            candidates[#candidates + 1] = vehicle
        end
    end

    if #candidates == 0 then
        self.selected_vehicle = nil
        return false
    end

    local pick = candidates[1]
    for i, v in ipairs(candidates) do
        if v == self.selected_vehicle then
            pick = candidates[(i % #candidates) + 1]
            break
        end
    end
    self.selected_vehicle = pick
    return true
end

return Entities
