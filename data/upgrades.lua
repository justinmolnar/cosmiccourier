-- data/upgrades.lua
-- Pure data structure for game upgrades - no business logic

local json = require("lib.json")

local raw     = love.filesystem.read("data/upgrades.json")
local Upgrades = json.decode(raw)

-- Create a flat map for easy lookup by ID
local AllUpgrades = {}
for _, category in ipairs(Upgrades.categories) do
    for _, sub_type in ipairs(category.sub_types) do
        for _, upgrade in ipairs(sub_type.tree) do
            AllUpgrades[upgrade.id] = upgrade
        end
    end
end

Upgrades.AllUpgrades = AllUpgrades
return Upgrades
