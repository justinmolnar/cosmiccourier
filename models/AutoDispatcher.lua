-- models/AutoDispatcher.lua with debug logging

local AutoDispatcher = {}
AutoDispatcher.__index = AutoDispatcher

function AutoDispatcher:new(C)
    local instance = setmetatable({}, AutoDispatcher)
    instance.dispatch_timer = 0
    instance.dispatch_interval = C.GAMEPLAY.AUTODISPATCH_INTERVAL
    instance.debug_logged_running = false
    instance.last_debug_time = 0
    return instance
end

function AutoDispatcher:update(dt, game)
    -- Debug: Check if upgrade is unlocked
    if not game.state.upgrades.auto_dispatch_unlocked then
        -- Only log this occasionally to avoid spam
        if math.floor(love.timer.getTime()) % 5 == 0 and self.last_debug_time ~= math.floor(love.timer.getTime()) then
            self.last_debug_time = math.floor(love.timer.getTime())
        end
        return
    end

    -- Debug: Log that we're running
    if not self.debug_logged_running then
        print("AutoDispatcher: Running! Upgrade is unlocked.")
        self.debug_logged_running = true
    end

    self.dispatch_timer = self.dispatch_timer + dt
    if self.dispatch_timer >= self.dispatch_interval then
        print(string.format("AutoDispatcher: Timer reached %.2f, dispatching...", self.dispatch_timer))
        self.dispatch_timer = self.dispatch_timer - self.dispatch_interval
        self:dispatch(game)
    end
end

function AutoDispatcher:dispatch(game)
    if #game.entities.trips.pending == 0 then return end

    print(string.format("AutoDispatcher: Trying to dispatch %d pending trips", #game.entities.trips.pending))

    -- For each pending trip, try to find a matching vehicle
    for i = #game.entities.trips.pending, 1, -1 do
        local trip_to_assign = game.entities.trips.pending[i]
        if not trip_to_assign.legs[trip_to_assign.current_leg] then 
            print(string.format("AutoDispatcher: Trip %d has no valid current leg", i))
            goto continue 
        end
        
        local required_type = trip_to_assign.legs[trip_to_assign.current_leg].vehicleType
        local current_leg = trip_to_assign.current_leg
        local total_legs = #trip_to_assign.legs
        
        print(string.format("AutoDispatcher: Trip %d needs %s for leg %d/%d (long_distance: %s)", 
              i, required_type, current_leg, total_legs, tostring(trip_to_assign.is_long_distance)))

        -- Find an available vehicle of the required type
        local found_vehicle = nil
        local available_vehicles = {}
        local total_vehicles_of_type = 0
        
        for _, vehicle in ipairs(game.entities.vehicles) do
            if vehicle.type == required_type then
                total_vehicles_of_type = total_vehicles_of_type + 1
                local is_available = vehicle:isAvailable(game)
                local capacity_info = string.format("(%d/%d)", #vehicle.trip_queue + #vehicle.cargo, game.state.upgrades.vehicle_capacity)
                table.insert(available_vehicles, string.format("%s %d %s (available: %s, state: %s)", 
                             vehicle.type, vehicle.id, capacity_info, tostring(is_available), vehicle.state.name))
                if is_available and not found_vehicle then 
                    found_vehicle = vehicle
                end
            end
        end
        
        print(string.format("AutoDispatcher: Found %d %s vehicles: %s", 
              total_vehicles_of_type, required_type, table.concat(available_vehicles, ", ")))

        if found_vehicle then
            print(string.format("AutoDispatcher: Assigning leg %d to %s %d", 
                  current_leg, found_vehicle.type, found_vehicle.id))
            found_vehicle:assignTrip(trip_to_assign, game)
            table.remove(game.entities.trips.pending, i)
        else
            print(string.format("AutoDispatcher: No available %s found for trip %d leg %d", required_type, i, current_leg))
        end
        
        ::continue::
    end
end

return AutoDispatcher