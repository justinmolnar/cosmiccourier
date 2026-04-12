-- data/unlock_registry.lua
-- Centralizes the key format for the unlock system.
-- Keys are "namespace:id" strings stored in game.state.unlocked.
--
-- Namespaces:
--   block        — block def ids (dispatch_blocks.lua)
--   prefab       — prefab ids (dispatch_prefabs.lua)
--   template     — rule template ids (rule_templates.lua)
--   action       — action ids for block_call (dispatch_actions.lua)
--   collection   — collection ids for find_match
--   sorter       — sorter ids for find_match
--   property     — "source.key" for rep_get_property
--   vehicle      — vehicle type ids
--   scope        — delivery scope levels
--   building     — building type ids
--   sort_metric  — sort_queue metric ids

local Registry = {}

--- Build a namespaced unlock key.
function Registry.key(namespace, id)
    return namespace .. ":" .. id
end

--- Map from slot key names to unlock namespaces.
--- Used by enum gating to know which namespace a slot's options belong to.
Registry.SLOT_NAMESPACE = {
    scope         = "scope",
    vehicle_type  = "vehicle",
    building_type = "building",
    metric        = "sort_metric",
}

return Registry
