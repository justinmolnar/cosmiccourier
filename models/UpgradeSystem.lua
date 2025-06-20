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
    if upgrade and upgrade.effect then
        upgrade.effect(self.state, self.C)
    end
end

function UpgradeSystem:getUpgradeCategories()
    return self.upgrades_data.categories
end

function UpgradeSystem:getAllUpgrades()
    return self.upgrades_data.AllUpgrades
end

return UpgradeSystem