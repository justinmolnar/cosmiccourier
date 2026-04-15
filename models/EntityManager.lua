-- models/EntityManager.lua
local Client        = require("models.Client")
local PathScheduler = require("services.PathScheduler")

local Entities = {}
Entities.__index = Entities

function Entities:new()
    local instance = setmetatable({}, Entities)
    instance.depots         = {}
    instance.vehicles       = {}
    instance.clients        = {}
    instance.trips          = { pending = {} }
    instance.selected_vehicle = nil
    instance.selected_depot = nil

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
    local Depot = require("models.Depot")
    local start_plot = game.maps.city:getRandomDowntownBuildingPlot()
    if start_plot then
        local first_depot = Depot:new("downtown_1", start_plot, game)
        table.insert(self.depots, first_depot)
    end
    -- Starting client uses the default archetype from the registry (Downtown
    -- tier, general commerce). Every new save begins with this client; legacy
    -- saves without client data also end up here.
    local Archetypes = require("data.client_archetypes")
    self:addClient(game, self.depots[1], Archetypes.default_id)
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

function Entities:addClient(game, depot, archetype_id)
    local Archetypes = require("data.client_archetypes")
    archetype_id = archetype_id or Archetypes.default_id
    local archetype = Archetypes.by_id[archetype_id]
    if not archetype then
        print(string.format("EntityManager: unknown archetype_id '%s'", tostring(archetype_id)))
        return
    end

    -- Scope-tier guard (belt-and-braces; UI is the first gate).
    local LicenseService = require("services.LicenseService")
    if archetype.required_scope_tier > LicenseService.getCurrentTier(game) then
        print(string.format(
            "EntityManager: archetype '%s' requires tier %d; current tier %d — rejected.",
            archetype.id, archetype.required_scope_tier, LicenseService.getCurrentTier(game)))
        return
    end

    local cmap = (depot and depot.getCity) and depot:getCity(game) or game.maps.city
    if not cmap then return end
    local depot_district = depot and depot:getDistrict(game)

    -- Build a set of the archetype's preferred zones for O(1) membership test.
    local zone_set = {}
    for _, z in ipairs(archetype.spawn_zones or {}) do zone_set[z] = true end

    -- Placement order: (1) archetype zone + depot district; (2) archetype zone
    -- anywhere in the city; (3) any can_send plot (log the degraded fallback).
    local plot_local = cmap:getRandomBuildingPlotForZones(zone_set, depot_district, "can_send")
    if not plot_local then
        plot_local = cmap:getRandomBuildingPlotForZones(zone_set, nil, "can_send")
    end
    if not plot_local then
        plot_local = cmap:getRandomSendingPlot()
        if plot_local then
            print(string.format(
                "EntityManager: no '%s' archetype zone available in this city; using any can_send plot.",
                archetype.id))
        end
    end
    if not plot_local then return end

    local plot = (cmap.world_mn_x and game.maps.unified) and {
        x = (cmap.world_mn_x - 1) * 3 + plot_local.x,
        y = (cmap.world_mn_y - 1) * 3 + plot_local.y,
    } or plot_local
    local new_client = Client:new(plot, game, cmap, archetype_id)
    table.insert(self.clients, new_client)
end

function Entities:addVehicle(game, vehicleType, target_depot)
    local VehicleFactory = require("models.VehicleFactory")
    if not VehicleFactory.isValidVehicleType(vehicleType, game) then return end

    local vcfg_v = game.C.VEHICLES[vehicleType:upper()]
    local depot

    if vcfg_v and vcfg_v.transport_mode == "water" then
        -- Water-mode vehicles spawn at a dock entrance, not a road depot.
        local EntranceService = require("services.EntranceService")
        local dock = EntranceService.firstOfMode("water", game)
        if not dock then
            print("Cannot hire " .. vehicleType .. ": no dock placed yet.")
            return
        end
        depot = {
            plot = {x = dock.ux, y = dock.uy},
            assigned_vehicles = {},
            id = "dock_spawn",
        }
    else
        depot = target_depot or self.depots[1]
    end

    if not depot then return end

    local Vehicle = require("models.vehicles.Vehicle")
    local new_id = Vehicle.allocateId()
    local new_vehicle = VehicleFactory.createVehicle(vehicleType, new_id, depot, game)
    table.insert(self.vehicles, new_vehicle)
    table.insert(depot.assigned_vehicles, new_vehicle)

    local RE = require("services.DispatchRuleEngine")
    RE.fireEvent(game.state.dispatch_rules or {}, "vehicle_hired",
        { vehicle = new_vehicle, game = game })
end

function Entities:removeVehicle(vehicle, game)
    -- Unassign trips back to pending queue
    if vehicle.unassign then vehicle:unassign(game) end

    -- Remove from depot's assigned list
    if vehicle.depot then
        local av = vehicle.depot.assigned_vehicles
        for i = #av, 1, -1 do
            if av[i] == vehicle then table.remove(av, i); break end
        end
    end

    -- Remove from global vehicle list
    for i = #self.vehicles, 1, -1 do
        if self.vehicles[i] == vehicle then table.remove(self.vehicles, i); break end
    end

    local RE = require("services.DispatchRuleEngine")
    RE.fireEvent(game.state.dispatch_rules or {}, "vehicle_dismissed",
        { vehicle = vehicle, game = game })
end

function Entities:update(dt, game)
    local C_GAMEPLAY = game.C.GAMEPLAY
    local decay = dt * C_GAMEPLAY.BONUS_DECAY_RATE

    PathScheduler.flush()

    -- Decay speed bonuses on pending (non-transit) trips, and expire
    -- Rush trips past their deadline. Pending + expired → remove + publish;
    -- in-transit + expired → flag payout_forfeited (consumed at delivery).
    local now = love.timer.getTime()
    for i = #self.trips.pending, 1, -1 do
        local trip = self.trips.pending[i]
        if trip.is_rush and trip.deadline and now > trip.deadline then
            table.remove(self.trips.pending, i)
            if trip.source_client and trip.source_client.cargo then
                local c = trip.source_client.cargo
                for j = #c, 1, -1 do
                    if c[j] == trip then table.remove(c, j); break end
                end
            end
            game.EventBus:publish("rush_trip_expired", { trip = trip })
        elseif not trip.is_in_transit then
            local b = trip.speed_bonus - decay
            trip.speed_bonus = b < 0 and 0 or b
        end
    end
    -- Trips committed to a vehicle (queued or being carried) missed deadline:
    -- set the forfeit flag (consumed at delivery). Vehicle still completes the
    -- route; payout is zeroed at arrival.
    local function maybeForfeit(trip)
        if trip.is_rush and trip.deadline
           and not trip.payout_forfeited
           and now > trip.deadline then
            trip.payout_forfeited = true
            game.EventBus:publish("rush_trip_expired", { trip = trip, in_transit = true })
        end
    end
    for _, vehicle in ipairs(self.vehicles) do
        for _, trip in ipairs(vehicle.trip_queue or {}) do maybeForfeit(trip) end
        for _, trip in ipairs(vehicle.cargo or {})       do maybeForfeit(trip) end
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
    local active_map = game.maps[game.active_map_key]
    local uts = active_map.tile_pixel_size or game.C.MAP.TILE_SIZE
    
    -- Check depots first — depot.plot is always in unified sub-cell coords
    local umap = game.maps.unified
    local u_uts = umap and umap.tile_pixel_size or game.C.MAP.TILE_SIZE
    local depot_click_r = 20 / game.camera.scale  -- 20 screen-px hit area
    for _, depot in ipairs(self.depots) do
        if depot.plot then
            local dpx = (depot.plot.x - 0.5) * u_uts
            local dpy = (depot.plot.y - 0.5) * u_uts
            if (x - dpx)^2 + (y - dpy)^2 < depot_click_r^2 then
                self.selected_depot = depot
                self.selected_vehicle = nil
                return true
            end
        end
    end

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
        self.selected_depot = nil
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
