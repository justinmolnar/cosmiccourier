-- views/UpgradeModalViewModel.lua
-- Computes per-node display state for the upgrade tech-tree modal.
-- Separates "what to show" from "how to draw it" in Modal:_drawTree.

local UpgradeModalViewModel = {}

-- Returns the cost to purchase the next level of a node.
-- Single source of truth for the cost formula used by drawTree, drawTooltip, and handle_mouse_down.
function UpgradeModalViewModel.getNodeCost(node_data, purchased_level)
    return node_data.cost * (node_data.cost_multiplier ^ purchased_level)
end

-- Returns a table keyed by node id with display fields:
--   is_visible, is_maxed, is_purchased, is_available, can_afford, purchased, cost
function UpgradeModalViewModel.buildDisplayState(tree_data, visible_nodes, game_state)
    local nodes = {}
    for _, node_data in ipairs(tree_data.tree) do
        local purchased = game_state.upgrades_purchased[node_data.id] or 0
        local cost = UpgradeModalViewModel.getNodeCost(node_data, purchased)
        nodes[node_data.id] = {
            is_visible   = visible_nodes[node_data.id] == true,
            is_maxed     = purchased >= node_data.max_level,
            is_purchased = purchased > 0,
            is_available = game_state:isUpgradeAvailable(node_data.id),
            can_afford   = game_state.money >= cost,
            purchased    = purchased,
            cost         = cost,
        }
    end
    return nodes
end

return UpgradeModalViewModel
