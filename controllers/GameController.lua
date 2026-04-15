-- controllers/GameController.lua
-- Main game controller that manages all game systems and updates

local FloatingTextSystem = require("services.FloatingTextSystem")

local GameController = {}
GameController.__index = GameController

function GameController:new(game)
    local instance = setmetatable({}, GameController)
    instance.game = game
    
    -- Initialize any controller-specific state
    instance.paused = false
    instance.time_scale = 1.0
    instance.last_update_time = love.timer.getTime()
    
    -- Performance tracking
    instance.performance_stats = {
        frame_count = 0,
        total_time = 0,
        avg_frame_time = 0,
        last_fps_update = 0
    }

    instance._gc_step_timer  = 0
    instance._gc_hard_timer  = 0
    instance._mem_warn_timer = 0

    game.error_service.logInfo("GameController", "Game controller initialized")

    return instance
end

function GameController:update(dt)
    -- Apply time scale (for debugging/pause functionality)
    local scaled_dt = dt * self.time_scale
    
    if self.paused then
        scaled_dt = 0
    end
    
    -- Update performance stats
    self:updatePerformanceStats(dt)
    
    -- Core game systems update
    self.game.error_service.withErrorHandling(function()
        self.game.state:update(scaled_dt, self.game)
    end, "Game State Update")

    self.game.error_service.withErrorHandling(function()
        FloatingTextSystem.update(scaled_dt, self.game)
    end, "Floating Text Update")
    
    self.game.error_service.withErrorHandling(function()
        self.game.time:update(scaled_dt, self.game)
    end, "Time System Update")
    
    
    self.game.error_service.withErrorHandling(function()
        self.game.entities:update(scaled_dt, self.game)
    end, "Entities Update")
    
    self.game.error_service.withErrorHandling(function()
        self.game.autodispatcher:update(scaled_dt, self.game)
    end, "Auto Dispatcher Update")
    
    self.game.error_service.withErrorHandling(function()
        self.game.event_spawner:update(scaled_dt, self.game)
    end, "Event Spawner Update")
    
    self.game.error_service.withErrorHandling(function()
        self.game.ui_manager:update(scaled_dt, self.game)
    end, "UI Manager Update")
    
    self.game.error_service.withErrorHandling(function()
        self.game.zoom_controls:update(self.game)
    end, "Zoom Controls Update")
    
    -- Update input controller (which includes debug menu)
    self.game.error_service.withErrorHandling(function()
        self.game.input_controller:update(scaled_dt)
    end, "Input Controller Update")
    
    -- Update camera if needed
    if self.game.camera and self.game.camera.update then
        self.game.error_service.withErrorHandling(function()
            self.game.camera:update(scaled_dt)
        end, "Camera Update")
    end
    
    -- Check for any critical errors that should pause the game
    self:stepGC(dt)
    self:checkCriticalErrors()
end

function GameController:updatePerformanceStats(dt)
    self.performance_stats.frame_count = self.performance_stats.frame_count + 1
    self.performance_stats.total_time = self.performance_stats.total_time + dt
    
    -- Update average frame time every second
    if self.performance_stats.total_time - self.performance_stats.last_fps_update >= 1.0 then
        self.performance_stats.avg_frame_time = self.performance_stats.total_time / self.performance_stats.frame_count
        self.performance_stats.last_fps_update = self.performance_stats.total_time
        
        -- Log performance if debug mode is enabled
        if self.game.debug_mode then
            local fps = 1.0 / self.performance_stats.avg_frame_time
            if fps < 30 then -- Log if FPS drops below 30
                self.game.error_service.logWarning("GameController", 
                    string.format("Low FPS detected: %.1f (%.3fms frame time)", fps, self.performance_stats.avg_frame_time * 1000))
            end
        end
        
        -- Reset counters
        self.performance_stats.frame_count = 0
        self.performance_stats.total_time = 0
    end
end

function GameController:stepGC(dt)
    self._gc_step_timer = self._gc_step_timer + dt
    self._gc_hard_timer = self._gc_hard_timer + dt

    -- Incremental GC step every 5 seconds to keep GC from falling behind
    if self._gc_step_timer >= 5 then
        self._gc_step_timer = 0
        collectgarbage("step", 1)
    end

    -- Full collection if above 512 MB, at most once every 30 seconds
    if self._gc_hard_timer >= 30 then
        self._gc_hard_timer = 0
        local mem_kb = collectgarbage("count")
        if mem_kb > 512 * 1024 then
            collectgarbage("collect")
        end
    end
end

function GameController:checkCriticalErrors()
    -- MODIFIED: Check for the maps table instead of a single map
    if not self.game.maps or not self.game.entities or not self.game.state then
        self.game.error_service.logError("GameController", "Critical game components missing!")
        self:pauseGame()
        return
    end

    -- Check memory usage, rate-limited to once per 10 seconds
    self._mem_warn_timer = self._mem_warn_timer + (self.performance_stats.avg_frame_time or 0.016)
    if self._mem_warn_timer >= 10 then
        self._mem_warn_timer = 0
        local memory_usage = collectgarbage("count")
        if memory_usage > 700000 then -- 700MB threshold
            self.game.error_service.logWarning("GameController",
                string.format("High memory usage detected: %.1f MB", memory_usage / 1024))
        end
    end
end

function GameController:pauseGame()
    self.paused = true
    self.game.error_service.logInfo("GameController", "Game paused")
    
    -- Publish pause event
    self.game.EventBus:publish("game_paused", {})
end

function GameController:resumeGame()
    self.paused = false
    self.game.error_service.logInfo("GameController", "Game resumed")
    
    -- Publish resume event
    self.game.EventBus:publish("game_resumed", {})
end

function GameController:togglePause()
    if self.paused then
        self:resumeGame()
    else
        self:pauseGame()
    end
end

function GameController:isPaused()
    return self.paused
end

function GameController:setTimeScale(scale)
    if scale >= 0 and scale <= 10 then -- Reasonable bounds
        self.time_scale = scale
        self.game.error_service.logInfo("GameController", "Time scale set to: " .. tostring(scale))
        
        -- Publish time scale change event
        self.game.EventBus:publish("time_scale_changed", {scale = scale})
    else
        self.game.error_service.logWarning("GameController", "Invalid time scale: " .. tostring(scale))
    end
end

function GameController:getTimeScale()
    return self.time_scale
end

function GameController:getPerformanceStats()
    return {
        avg_frame_time = self.performance_stats.avg_frame_time,
        fps = self.performance_stats.avg_frame_time > 0 and (1.0 / self.performance_stats.avg_frame_time) or 0,
        memory_usage = collectgarbage("count") / 1024, -- MB
        paused = self.paused,
        time_scale = self.time_scale
    }
end

-- Emergency reset function for critical errors
function GameController:emergencyReset()
    self.game.error_service.logWarning("GameController", "Emergency reset initiated")
    
    self.game.error_service.withErrorHandling(function()
        -- Reset time scale and pause state
        self.time_scale = 1.0
        self.paused = false
        
        -- Force garbage collection
        collectgarbage("collect")
        
        if not self.game.entities then
            self.game.entities = require("models.EntityManager"):new()
            self.game.entities:init(self.game)
        end
        
        self.game.error_service.logInfo("GameController", "Emergency reset completed")
        
    end, "Emergency Reset")
end

-- Debug functionality
function GameController:toggleDebugMode()
    self.game.debug_mode = not self.game.debug_mode
    self.game.error_service.logInfo("GameController", "Debug mode: " .. tostring(self.game.debug_mode))
    
    -- Update config
    self.game.config.set("gameplay", "debug_mode_enabled", self.game.debug_mode)
    
    -- Publish debug mode change event
    self.game.EventBus:publish("debug_mode_changed", {enabled = self.game.debug_mode})
end

-- Get current game statistics
function GameController:getGameStats()
    local active_map = self.game.maps[self.game.active_map_key]
    local stats = {
        money = self.game.state.money,
        vehicles = #self.game.entities.vehicles,
        clients = #self.game.entities.clients,
        pending_trips = #self.game.entities.trips.pending,
        current_scale = self.game.state.current_map_scale,
        scale_name = active_map:getScaleName(),
        time_played = self.game.time.total_time or 0,
        rush_hour_active = self.game.state.rush_hour.active,
    }
    
    -- Add performance stats
    local perf_stats = self:getPerformanceStats()
    for k, v in pairs(perf_stats) do
        stats["perf_" .. k] = v
    end
    
    return stats
end

return GameController