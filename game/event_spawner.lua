-- game/event_spawner.lua
-- Manages the spawning and clicking of the "Rush Hour" clickable icon.

local EventSpawner = {}
EventSpawner.__index = EventSpawner

function EventSpawner:new(C)
    local instance = setmetatable({}, EventSpawner)
    instance.C = C.EVENTS
    instance.spawn_timer = love.math.random(instance.C.SPAWN_MIN_SEC, instance.C.SPAWN_MAX_SEC)
    instance.clickable = nil
    return instance
end

function EventSpawner:update(dt, game)
    -- If a clickable is already active, count down its lifespan.
    if self.clickable then
        self.clickable.timer = self.clickable.timer - dt
        if self.clickable.timer <= 0 then
            self.clickable = nil -- It disappeared before being clicked.
        end
        return -- Don't count down to the next spawn while one is on screen.
    end

    -- If no clickable is active, count down to the next one.
    self.spawn_timer = self.spawn_timer - dt
    if self.spawn_timer <= 0 then
        -- Time to spawn a new one!
        local map_w = game.C.MAP.GRID_WIDTH * game.C.MAP.TILE_SIZE
        local map_h = game.C.MAP.GRID_HEIGHT * game.C.MAP.TILE_SIZE
        self.clickable = {
            x = love.math.random(50, map_w - 50),
            y = love.math.random(50, map_h - 50),
            timer = self.C.LIFESPAN_SEC,
            radius = 30,
        }
        -- Reset the timer for the *next* spawn.
        self.spawn_timer = love.math.random(self.C.SPAWN_MIN_SEC, self.C.SPAWN_MAX_SEC)
    end
end

function EventSpawner:draw(game)
    if self.clickable then
        love.graphics.setFont(game.fonts.emoji)
        love.graphics.setColor(1, 1, 1)
        -- Pulse effect to draw attention
        local scale = 1 + math.sin(love.timer.getTime() * 5) * 0.1
        love.graphics.push()
        love.graphics.translate(self.clickable.x, self.clickable.y)
        love.graphics.scale(scale, scale)
        love.graphics.print("☎️", -14, -14) -- Center the emoji
        love.graphics.pop()
    end
end

function EventSpawner:handle_click(x, y, game)
    if not self.clickable then return false end

    local c = self.clickable
    local dist_sq = (x - c.x)^2 + (y - c.y)^2

    if dist_sq < c.radius * c.radius then
        print("Rush Hour activated!")
        game.state.rush_hour.active = true
        game.state.rush_hour.timer = game.state.upgrades.frenzy_duration
        self.clickable = nil -- Remove the icon once clicked.
        return true
    end

    return false
end

return EventSpawner