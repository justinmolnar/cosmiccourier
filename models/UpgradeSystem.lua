-- models/UpgradeSystem.lua
local UpgradeSystem = {}
UpgradeSystem.__index = UpgradeSystem

function UpgradeSystem:new(game_state, constants)
    local instance = setmetatable({}, UpgradeSystem)
    instance.state = game_state
    instance.C = constants
    instance.upgrades_data = require("data.upgrades")
    return instance
end

function UpgradeSystem:isUpgradeAvailable(upgradeId)
    local upgrade = self.upgrades_data.AllUpgrades[upgradeId]
    if not upgrade then return false end

    -- Check if all prerequisite upgrades have been purchased to at least level 1
    for _, prereqId in ipairs(upgrade.prerequisites) do
        if (self.state.upgrades_purchased[prereqId] or 0) < 1 then
            return false -- A prerequisite is not met
        end
    end
    
    return true -- All prerequisites are met
end

function UpgradeSystem:getUpgradeCost(upgradeId)
    local upgrade = self.upgrades_data.AllUpgrades[upgradeId]
    if not upgrade then return nil end
    
    local current_level = self.state.upgrades_purchased[upgradeId] or 0
    return upgrade.cost * (upgrade.cost_multiplier ^ current_level)
end

function UpgradeSystem:canAffordUpgrade(upgradeId)
    local cost = self:getUpgradeCost(upgradeId)
    return cost and self.state.money >= cost
end

function UpgradeSystem:isUpgradeMaxed(upgradeId)
    local upgrade = self.upgrades_data.AllUpgrades[upgradeId]
    if not upgrade then return true end
    
    local current_level = self.state.upgrades_purchased[upgradeId] or 0
    return current_level >= upgrade.max_level
end

function UpgradeSystem:purchaseUpgrade(upgradeId)
    local upgrade = self.upgrades_data.AllUpgrades[upgradeId]
    if not upgrade then
        print("ERROR: Unknown upgrade ID: " .. tostring(upgradeId))
        return false
    end
    
    if not self:isUpgradeAvailable(upgradeId) then
        print("ERROR: Upgrade not available: " .. upgradeId)
        return false
    end
    
    if self:isUpgradeMaxed(upgradeId) then
        print("ERROR: Upgrade already maxed: " .. upgradeId)
        return false
    end
    
    local cost = self:getUpgradeCost(upgradeId)
    if not self:canAffordUpgrade(upgradeId) then
        print("ERROR: Cannot afford upgrade: " .. upgradeId .. " (cost: " .. cost .. ")")
        return false
    end
    
    -- Purchase the upgrade
    self.state.money = self.state.money - cost
    local current_level = self.state.upgrades_purchased[upgradeId] or 0
    self.state.upgrades_purchased[upgradeId] = current_level + 1
    
    -- Apply the upgrade effect
    self:applyUpgradeEffect(upgradeId)
    
    print("Purchased upgrade: " .. upgradeId .. " (level " .. (current_level + 1) .. ")")
    return true
end

function UpgradeSystem:applyUpgradeEffect(upgradeId)
    local upgrade = self.upgrades_data.AllUpgrades[upgradeId]
    if not upgrade then 
        print("ERROR: No upgrade data found for " .. tostring(upgradeId))
        return 
    end
    
    -- Handle data-driven effects
    if upgrade.effect_type then
        self:applyDataDrivenEffect(upgrade)
    -- Handle function-based effects (legacy)
    elseif upgrade.effect then
        upgrade.effect(self.state, self.C)
    else
        print("WARNING: Upgrade " .. upgradeId .. " has no effect defined")
    end
end

function UpgradeSystem:applyDataDrivenEffect(upgrade)
    local effect_type = upgrade.effect_type
    local target = upgrade.effect_target
    local value = upgrade.effect_value
    
    print(string.format("Applying effect: %s -> %s = %s", effect_type, target, tostring(value)))
    
    if effect_type == "set_flag" then
        -- Set a boolean flag in upgrades
        self.state.upgrades[target] = value
        print(string.format("Set flag: upgrades.%s = %s", target, tostring(value)))
        
    elseif effect_type == "add_stat" then
        -- Add to a numeric stat
        local current = self.state.upgrades[target] or 0
        self.state.upgrades[target] = current + value
        print(string.format("Added stat: upgrades.%s = %s (was %s)", target, self.state.upgrades[target], current))
        
        -- Apply the stat change to actual game values
        self:applyStatToGameValues(target, self.state.upgrades[target])
        
    elseif effect_type == "multiply_stat" then
        -- Multiply a numeric stat
        local current = self.state.upgrades[target] or 1
        self.state.upgrades[target] = current * value
        print(string.format("Multiplied stat: upgrades.%s = %s (was %s)", target, self.state.upgrades[target], current))
        
        -- Apply the stat change to actual game values
        self:applyStatToGameValues(target, self.state.upgrades[target])
        
    elseif effect_type == "multiply_stats" then
        -- Multiply multiple stats (targets should be an array)
        local targets = upgrade.effect_targets or {target}
        for _, stat_target in ipairs(targets) do
            local current = self.state.upgrades[stat_target] or 1
            self.state.upgrades[stat_target] = current * value
            print(string.format("Multiplied stat: upgrades.%s = %s (was %s)", stat_target, self.state.upgrades[stat_target], current))
            
            -- Apply the stat change to actual game values
            self:applyStatToGameValues(stat_target, self.state.upgrades[stat_target])
        end
        
    elseif effect_type == "special" then
        -- Handle special effects that need custom logic
        self:applySpecialEffect(upgrade)
        
    else
        print("ERROR: Unknown effect_type: " .. tostring(effect_type))
    end
end

function UpgradeSystem:applyStatToGameValues(stat_name, stat_value)
    -- This function applies upgrade stats to the actual values used by the game
    -- Get game reference from global (since it's stored as Game in main.lua)
    local game = Game
    if not game then
        print("ERROR: Cannot access game instance for upgrade application")
        return
    end
    
    if stat_name == "bike_speed" then
        -- Apply bike speed multiplier to all existing bikes
        local Bike = require("models.vehicles.Bike")
        local base_speed = 80 -- Base bike speed from PROPERTIES
        local new_speed = base_speed * stat_value
        
        -- Update the class properties (affects new bikes)
        Bike.PROPERTIES.speed = new_speed
        
        -- Update existing bikes
        for _, vehicle in ipairs(game.entities.vehicles) do
            if vehicle.type == "bike" then
                vehicle.properties.speed = new_speed
                print(string.format("Updated bike %d speed to %d", vehicle.id, new_speed))
            end
        end
        
    elseif stat_name == "truck_speed" then
        -- Apply truck speed multiplier
        local Truck = require("models.vehicles.Truck")
        local base_speed = 60 -- Base truck speed
        local new_speed = base_speed * stat_value
        
        Truck.PROPERTIES.speed = new_speed
        
        for _, vehicle in ipairs(game.entities.vehicles) do
            if vehicle.type == "truck" then
                vehicle.properties.speed = new_speed
                print(string.format("Updated truck %d speed to %d", vehicle.id, new_speed))
            end
        end
        
    elseif stat_name == "vehicle_capacity" then
        -- This one is already used correctly by the game
        -- No additional changes needed
        
    elseif stat_name == "max_pending_trips" then
        -- This one is already used correctly
        -- No additional changes needed
        
    elseif stat_name == "frenzy_duration" then
        -- This one is already used correctly
        -- No additional changes needed
        
    elseif stat_name == "trip_gen_min_mult" or stat_name == "trip_gen_max_mult" then
        -- These are already used correctly by TripGenerator
        -- No additional changes needed
        
    else
        print(string.format("INFO: Stat %s doesn't need special application", stat_name))
    end
end

function UpgradeSystem:applySpecialEffect(upgrade)
    local target = upgrade.effect_target
    local value = upgrade.effect_value
    
    -- Handle special cases that don't fit the standard patterns
    if target == "bike_cost_reduction" or target == "bike_upgrade_discount" then
        -- These might need to modify the costs table or other special handling
        self.state.upgrades[target] = (self.state.upgrades[target] or 0) + value
        print(string.format("Applied special effect: %s = %s", target, self.state.upgrades[target]))
        
    elseif target == "truck_capacity" then
        -- Truck-specific capacity bonus
        self.state.upgrades[target] = (self.state.upgrades[target] or 0) + value
        print(string.format("Applied truck capacity: %s", self.state.upgrades[target]))
        
    else
        -- Default: just set the value
        self.state.upgrades[target] = value
        print(string.format("Applied special effect: %s = %s", target, tostring(value)))
    end
end

function UpgradeSystem:getUpgradeCategories()
    return self.upgrades_data.categories
end

function UpgradeSystem:getAllUpgrades()
    return self.upgrades_data.AllUpgrades
end

return UpgradeSystem