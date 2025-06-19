-- game/vehicle.lua (The new base vehicle file)
local Vehicle = {}
Vehicle.__index = Vehicle

function Vehicle:new(id, depot_plot, game)
    local instance = setmetatable({}, Vehicle)

    -- Require the state machine definition file
    local States = require("game.vehicle_states")
    
    instance.id = id
    instance.depot_plot = depot_plot
    instance.px, instance.py = game.map:getPixelCoords(depot_plot.x, depot_plot.y)
    
    instance.trip_queue = {} -- Trips assigned, but not yet picked up
    instance.cargo = {}      -- Trips picked up and currently being delivered
    instance.path = {}
    
    -- This is our new reliable grid-based position tracker
    instance.grid_anchor = {x = depot_plot.x, y = depot_plot.y}
    
    -- Initialize the state machine
    instance.state = nil
    instance:changeState(States.Idle, game)

    return instance
end

function Vehicle:recalculatePixelPosition(game)
    local new_gx, new_gy
    if game.map:getCurrentScale() == game.C.MAP.SCALES.DOWNTOWN then
        -- We are zoomed in, use the anchor directly
        new_gx = self.grid_anchor.x
        new_gy = self.grid_anchor.y
    else
        -- We are zoomed out, we need to apply the downtown offset
        new_gx = game.map.downtown_offset.x + self.grid_anchor.x
        new_gy = game.map.downtown_offset.y + self.grid_anchor.y
    end

    local new_px, new_py = game.map:getPixelCoords(new_gx, new_gy)
    self.px = new_px
    self.py = new_py
    
    print(string.format("Bike %d position recalculated to (%d, %d)", self.id, self.px, self.py))
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

    print("Queuing trip for bike " .. self.id)
    table.insert(self.trip_queue, trip)
end

function Vehicle:update(dt, game)
    -- The vehicle's update function is now extremely simple.
    -- It just calls the update method of whatever state it's currently in.
    -- The state itself is now responsible for movement and state changes.
    if self.state and self.state.update then
        self.state:update(dt, self, game)
    end
end

function Vehicle:isAvailable(game)
    local total_load = #self.trip_queue + #self.cargo
    return total_load < game.state.upgrades.vehicle_capacity
end


-- The generic draw function. Specific vehicle types can override this.
function Vehicle:draw(game)
    if self == game.entities.selected_vehicle then
        love.graphics.setColor(1, 1, 0) -- Yellow circle for selected
        love.graphics.circle("line", self.px, self.py, 16)
    end

    -- Default drawing if a subclass doesn't provide its own
    love.graphics.setColor(1,0,1) -- Magenta square as placeholder
    love.graphics.rectangle("fill", self.px - 8, self.py - 8, 16, 16)
    love.graphics.setColor(1,1,1)

    -- Draw debug info
    if game.debug_mode then
        local C = game.C
        local debug_x = self.px + 20
        local debug_y = self.py - 20
        local line_h = 15
        local state_name = self.state and self.state.name or "N/A"
        local path_count = self.path and #self.path or 0
        local target_text = "None"
        if self.path and self.path[1] then
            target_text = string.format("(%d, %d)", self.path[1].x, self.path[1].y)
        end
        local debug_lines = {
            string.format("ID: %d | State: %s", self.id, state_name),
            string.format("Path Nodes: %d", path_count),
            string.format("Target: %s", target_text),
            string.format("Cargo: %d | Queue: %d", #self.cargo, #self.trip_queue),
            string.format("Pos: %d, %d", math.floor(self.px), math.floor(self.py))
        }
        love.graphics.setColor(0, 0, 0, 0.7)
        love.graphics.rectangle("fill", debug_x - 5, debug_y - 5, 200, #debug_lines * line_h + 10)
        love.graphics.setColor(0, 1, 0)
        for i, line in ipairs(debug_lines) do
            love.graphics.print(line, debug_x, debug_y + (i-1) * line_h)
        end
        love.graphics.setColor(1, 1, 1)
        if self.path and #self.path > 0 then
            local pixel_path = {}
            table.insert(pixel_path, self.px)
            table.insert(pixel_path, self.py)
            for _, node in ipairs(self.path) do
                local px, py = game.map:getPixelCoords(node.x, node.y)
                table.insert(pixel_path, px)
                table.insert(pixel_path, py)
            end
            love.graphics.setColor(1, 0, 1, 0.8)
            love.graphics.setLineWidth(2)
            love.graphics.line(pixel_path)
            for i = 3, #pixel_path, 2 do
                love.graphics.circle("fill", pixel_path[i], pixel_path[i+1], 3)
            end
            love.graphics.setLineWidth(1)
            love.graphics.setColor(1,1,1)
        end
    end
end

return Vehicle