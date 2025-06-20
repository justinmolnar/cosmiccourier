-- controllers/GameController.lua
-- Main game controller that manages all game systems and updates

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
        self.game.time:update(scaled_dt, self.game)
    end, "Time System Update")
    
    self.game.error_service.withErrorHandling(function()
        self.game.map:update(scaled_dt)
    end, "Map Update")
    
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

function GameController:checkCriticalErrors()
    -- Check for critical game state issues
    if not self.game.map or not self.game.entities or not self.game.state then
        self.game.error_service.logError("GameController", "Critical game components missing!")
        self:pauseGame()
        return
    end
    
    -- Check memory usage (if it gets too high, log a warning)
    local memory_usage = collectgarbage("count")
    if memory_usage > 500000 then -- 500MB threshold
        self.game.error_service.logWarning("GameController", 
            string.format("High memory usage detected: %.1f MB", memory_usage / 1024))
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
        
        -- Reinitialize critical systems if needed
        if not self.game.map then
            self.game.map = require("models.Map"):new(self.game.C)
            self.game.map:generate()
        end
        
        if not self.game.entities then
            self.game.entities = require("models.EntityManager"):new()
            self.game.entities:init(self.game)
        end
        
        self.game.error_service.logInfo("GameController", "Emergency reset completed")
        
    end, "Emergency Reset")
end

-- Save game state
function GameController:saveGame(filename)
    self.game.error_service.withErrorHandling(function()
        local SaveService = require("services.SaveService")
        SaveService.saveGame(self.game.state, filename or "quicksave.json")
        self.game.error_service.logInfo("GameController", "Game saved: " .. (filename or "quicksave.json"))
        
        -- Publish save event
        self.game.EventBus:publish("game_saved", {filename = filename})
        
    end, "Save Game")
end

-- Load game state
function GameController:loadGame(filename)
    self.game.error_service.withErrorHandling(function()
        local SaveService = require("services.SaveService")
        local save_data = SaveService.loadGame(filename or "quicksave.json")
        
        if save_data then
            SaveService.applySaveData(self.game.state, save_data)
            self.game.error_service.logInfo("GameController", "Game loaded: " .. (filename or "quicksave.json"))
            
            -- Publish load event
            self.game.EventBus:publish("game_loaded", {filename = filename})
        else
            self.game.error_service.logWarning("GameController", "Failed to load game: " .. (filename or "quicksave.json"))
        end
        
    end, "Load Game")
end

-- Quick save/load functionality
function GameController:quickSave()
    self:saveGame("quicksave.json")
end

function GameController:quickLoad()
    self:loadGame("quicksave.json")
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
    local stats = {
        money = self.game.state.money,
        vehicles = #self.game.entities.vehicles,
        clients = #self.game.entities.clients,
        pending_trips = #self.game.entities.trips.pending,
        current_scale = self.game.map:getCurrentScale(),
        scale_name = self.game.map:getScaleName(),
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

-- Clean shutdown
function GameController:shutdown()
    self.game.error_service.logInfo("GameController", "Game controller shutting down...")
    
    -- Save current state
    self:saveGame("autosave.json")
    
    -- Clean up any resources
    self.game.error_service.withErrorHandling(function()
        -- Force final garbage collection
        collectgarbage("collect")
        
        self.game.error_service.logInfo("GameController", "Game controller shutdown complete")
    end, "Controller Shutdown")
end

return GameController