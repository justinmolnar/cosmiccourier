-- models/vehicles/Vehicle.lua
local Vehicle = {}
Vehicle.__index = Vehicle

function Vehicle:new(id, depot_plot, game, vehicleType, properties)
    -- THIS IS THE FIX: By requiring the states file here, we avoid the
    -- circular dependency that happens during the initial game load.
    local States = require("models.vehicles.vehicle_states")
    
    local instance = setmetatable({}, Vehicle)
    
    instance.id = id
    instance.type = vehicleType or "vehicle"
    instance.properties = properties or {}
    instance.depot_plot = depot_plot
    instance.px, instance.py = game.map:getPixelCoords(depot_plot.x, depot_plot.y)
    
    instance.trip_queue = {} -- Trips assigned, but not yet picked up
    instance.cargo = {}      -- Trips picked up and currently being delivered
    instance.path = {}
    
    instance.grid_anchor = {x = depot_plot.x, y = depot_plot.y}
    
    instance.state = nil
    instance:changeState(States.Idle, game)

    return instance
end

function Vehicle:recalculatePixelPosition(game)
    self.px, self.py = game.map:getPixelCoords(self.grid_anchor.x, self.grid_anchor.y)
end

function Vehicle:changeState(newState, game)
    if self.state and self.state.exit then
        self.state:exit(self, game)
    end
    self.state = newState
    if self.state and self.state.enter then
        self.state:enter(self, game)
    end
end

function Vehicle:assignTrip(trip, game)
    if not self:isAvailable(game) then return end

    print("Queuing trip for " .. self.type .. " " .. self.id)
    table.insert(self.trip_queue, trip)
end

function Vehicle:update(dt, game)
    if self.state and self.state.update then
        self.state:update(dt, self, game)
    end
end

function Vehicle:isAvailable(game)
    local total_load = #self.trip_queue + #self.cargo
    return total_load < game.state.upgrades.vehicle_capacity
end

function Vehicle:drawDebug(game)
    local C = game.C
    local line_h = 15
    local state_name = self.state and self.state.name or "N/A"
    local path_count = self.path and #self.path or 0
    local target_text = "None"
    if self.path and self.path[1] then
        target_text = string.format("(%d, %d)", self.path[1].x, self.path[1].y)
    end
    local debug_lines = {
        string.format("ID: %d | Type: %s", self.id, self.type),
        string.format("State: %s", state_name),
        string.format("Path Nodes: %d", path_count),
        string.format("Target: %s", target_text),
        string.format("Cargo: %d | Queue: %d", #self.cargo, #self.trip_queue),
        string.format("Pos: %d, %d", math.floor(self.px), math.floor(self.py))
    }

    love.graphics.push()
    love.graphics.translate(self.px + 20, self.py - 20)
    love.graphics.scale(1 / game.camera.scale, 1 / game.camera.scale)
    
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", -5, -5, 200, #debug_lines * line_h + 10)
    love.graphics.setColor(0, 1, 0)
    for i, line in ipairs(debug_lines) do
        love.graphics.print(line, 0, (i-1) * line_h)
    end
    
    love.graphics.pop()
    love.graphics.setColor(1, 1, 1)

    if self.path and #self.path > 0 then
        -- This path drawing logic can remain as is.
    end
end

function Vehicle:draw(game)
    local should_draw = false
    local current_scale = game.map:getCurrentScale()
    
    -- This generic draw logic can be simplified or specialized in subclasses
    if current_scale == game.C.MAP.SCALES.DOWNTOWN or current_scale == game.C.MAP.SCALES.CITY then
        should_draw = true
    end

    if not should_draw then
        return
    end

    if self == game.entities.selected_vehicle then
        love.graphics.setColor(1, 1, 0)
        local radius = 16 / game.camera.scale
        love.graphics.setLineWidth(2 / game.camera.scale)
        love.graphics.circle("line", self.px, self.py, radius)
        love.graphics.setLineWidth(1)
    end

    if game.debug_mode then
        self:drawDebug(game)
    end
end

return Vehicle