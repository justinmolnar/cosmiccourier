-- game/event_spawner.lua
-- Manages the spawning and clicking of the "Rush Hour" clickable icon.

local EventSpawner = {}
EventSpawner.__index = EventSpawner

function EventSpawner:new(C)
    local instance = setmetatable({}, EventSpawner)
    instance.C = C.EVENTS
    instance.spawn_timer = love.math.random(C.EVENTS.SPAWN_MIN_SEC, C.EVENTS.SPAWN_MAX_SEC)
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
        -- Always reset the timer so we don't busy-retry if conditions aren't met.
        self.spawn_timer = love.math.random(self.C.SPAWN_MIN_SEC, self.C.SPAWN_MAX_SEC)

        local active_map = game.maps[game.active_map_key]
        if not active_map then return end

        local current_grid = active_map.grid
        if not current_grid or #current_grid == 0 then return end

        local grid_w = current_grid[1] and #current_grid[1] or 0
        local grid_h = #current_grid
        local tile_size = active_map.tile_pixel_size or active_map:getCurrentTileSize()
        if grid_w == 0 or tile_size == 0 then return end

        -- cam.x/y are in absolute world-pixel space (TILE_SIZE units per grid cell).
        -- Entity positions are in local sub-cell space, relative to the city origin.
        -- Subtract the city origin to get the camera centre in local sub-cell space.
        local ts = game.C.MAP.TILE_SIZE
        local city_origin_x = ((game.world_gen_city_mn_x or 1) - 1) * ts
        local city_origin_y = ((game.world_gen_city_mn_y or 1) - 1) * ts

        local cam = game.camera
        local screen_w, screen_h = love.graphics.getDimensions()
        local vw = screen_w - (game.C.UI.SIDEBAR_WIDTH or 0)
        local half_vw = vw / (2 * cam.scale)
        local half_vh = screen_h / (2 * cam.scale)

        local center_x = cam.x - city_origin_x
        local center_y = cam.y - city_origin_y

        local gx_min = math.max(1,      math.floor((center_x - half_vw) / tile_size) + 1)
        local gx_max = math.min(grid_w, math.floor((center_x + half_vw) / tile_size) + 1)
        local gy_min = math.max(1,      math.floor((center_y - half_vh) / tile_size) + 1)
        local gy_max = math.min(grid_h, math.floor((center_y + half_vh) / tile_size) + 1)

        if gx_min > gx_max or gy_min > gy_max then return end

        local gx = love.math.random(gx_min, gx_max)
        local gy = love.math.random(gy_min, gy_max)

        self.clickable = {
            x = (gx - 0.5) * tile_size,
            y = (gy - 0.5) * tile_size,
            timer = self.C.LIFESPAN_SEC,
            radius = 30,
        }
    end
end

function EventSpawner:handle_click(x, y, game)
    if not self.clickable then return false end

    local c = self.clickable
    -- x,y are in absolute world space (from screenToWorld); ec coords are local sub-cell space.
    -- Convert to the same space by adding the city origin offset.
    local ts = game.C.MAP.TILE_SIZE
    local cx = c.x + ((game.world_gen_city_mn_x or 1) - 1) * ts
    local cy = c.y + ((game.world_gen_city_mn_y or 1) - 1) * ts
    local dist_sq = (x - cx)^2 + (y - cy)^2

    if dist_sq < c.radius * c.radius then
        game.state.rush_hour.active = true
        game.state.rush_hour.timer = game.state.upgrades.frenzy_duration
        self.clickable = nil -- Remove the icon once clicked.
        return true
    end

    return false
end

return EventSpawner
