-- models/UpgradeSystem.lua
local VehicleUpgradeService = require("services.VehicleUpgradeService")

local UpgradeSystem = {}
UpgradeSystem.__index = UpgradeSystem

function UpgradeSystem:new(game_state, constants, game)
    local instance = setmetatable({}, UpgradeSystem)
    instance.state = game_state
    instance.C = constants
    instance.game = game
    instance.upgrades_data = require("data.upgrades")
    return instance
end

-- Returns a table keyed by node id whose value is true for every node
-- the player can currently see (purchased or all prerequisites met).
function UpgradeSystem:getDisplayableNodes(tree_data)
    local visible = {}
    for _, node_data in ipairs(tree_data.tree) do
        local is_purchased = (self.state.upgrades_purchased[node_data.id] or 0) > 0
        local prereqs_met = true
        for _, prereq_id in ipairs(node_data.prerequisites) do
            if (self.state.upgrades_purchased[prereq_id] or 0) == 0 then
                prereqs_met = false
                break
            end
        end
        if is_purchased or prereqs_met then
            visible[node_data.id] = true
        end
    end
    return visible
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

local EFFECT_HANDLERS = {
    set_flag = function(system, upgrade)
        system.state.upgrades[upgrade.effect_target] = upgrade.effect_value
        print(string.format("Set flag: upgrades.%s = %s", upgrade.effect_target, tostring(upgrade.effect_value)))
    end,

    add_stat = function(system, upgrade)
        local current = system.state.upgrades[upgrade.effect_target] or 0
        system.state.upgrades[upgrade.effect_target] = current + upgrade.effect_value
        print(string.format("Added stat: upgrades.%s = %s (was %s)", upgrade.effect_target, system.state.upgrades[upgrade.effect_target], current))
        system:applyStatToGameValues(upgrade.effect_target, system.state.upgrades[upgrade.effect_target])
    end,

    multiply_stat = function(system, upgrade)
        local current = system.state.upgrades[upgrade.effect_target] or 1
        system.state.upgrades[upgrade.effect_target] = current * upgrade.effect_value
        print(string.format("Multiplied stat: upgrades.%s = %s (was %s)", upgrade.effect_target, system.state.upgrades[upgrade.effect_target], current))
        system:applyStatToGameValues(upgrade.effect_target, system.state.upgrades[upgrade.effect_target])
    end,

    multiply_stats = function(system, upgrade)
        local targets = upgrade.effect_targets or {upgrade.effect_target}
        for _, stat_target in ipairs(targets) do
            local current = system.state.upgrades[stat_target] or 1
            system.state.upgrades[stat_target] = current * upgrade.effect_value
            print(string.format("Multiplied stat: upgrades.%s = %s (was %s)", stat_target, system.state.upgrades[stat_target], current))
            system:applyStatToGameValues(stat_target, system.state.upgrades[stat_target])
        end
    end,

    special = function(system, upgrade)
        system:applySpecialEffect(upgrade)
    end,

    grant_pack = function(system, upgrade)
        local PackService  = require("services.PackService")
        local all_templates = require("data.rule_templates")
        local all_packs     = require("data.rule_packs")

        -- Also set the flag if specified (e.g. auto_dispatch_unlocked)
        if upgrade.effect_target and upgrade.effect_value then
            system.state.upgrades[upgrade.effect_target] = upgrade.effect_value
        end

        local pack_id = upgrade.grant_pack_id
        local pack_def = PackService.findPack(pack_id, all_packs)
        if not pack_def then
            print("ERROR: Unknown pack id: " .. tostring(pack_id))
            return
        end

        local result = PackService.openPack(pack_def, all_templates, system.state)
        print(string.format("Opened pack '%s': %d templates, %d new unlocks",
            pack_def.name, #result.templates, #result.new_keys))

        -- Publish event for UI pickup
        if system.game and system.game.EventBus then
            system.game.EventBus:publish("pack_opened", {
                pack   = pack_def,
                result = result,
            })
        end
    end,
}

function UpgradeSystem:applyDataDrivenEffect(upgrade)
    print(string.format("Applying effect: %s -> %s = %s", upgrade.effect_type, upgrade.effect_target, tostring(upgrade.effect_value)))
    local handler = EFFECT_HANDLERS[upgrade.effect_type]
    if not handler then
        print("ERROR: Unknown effect_type: " .. tostring(upgrade.effect_type))
        return
    end
    handler(self, upgrade)
end

function UpgradeSystem:applyStatToGameValues(stat_name, stat_value)
    local game = self.game
    if not game then
        print("ERROR: Cannot access game instance for upgrade application")
        return
    end

    -- Check if stat_name matches {vehicle_id}_{stat} pattern for any known vehicle.
    -- e.g. "bike_speed" → push speed_modifier to all live bikes.
    if game.C and game.C.VEHICLES then
        for vid, _ in pairs(game.C.VEHICLES) do
            local prefix = vid:lower() .. "_"
            if stat_name:sub(1, #prefix) == prefix then
                local stat_part = stat_name:sub(#prefix + 1)
                if stat_part == "speed" then
                    VehicleUpgradeService.applySpeedModifier(game.entities.vehicles, vid:lower(), stat_value)
                end
                -- capacity upgrades are read live via getEffectiveCapacity — no push needed
                return
            end
        end
    end

    -- Non-vehicle stats are stored in game.state.upgrades and read live — no push needed.
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