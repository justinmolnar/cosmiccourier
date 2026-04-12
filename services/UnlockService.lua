-- services/UnlockService.lua
-- Stateless query/mutation for the unlock system.
-- All functions take game state (with state.unlocked table) as a parameter.

local Registry = require("data.unlock_registry")

local UnlockService = {}

--- Check if a key is unlocked.
function UnlockService.isUnlocked(key, state)
    return state.unlocked[key] == true
end

--- Unlock a single key.
function UnlockService.unlock(key, state)
    state.unlocked[key] = true
end

--- Unlock a list of keys.
function UnlockService.unlockMany(keys, state)
    for _, key in ipairs(keys) do
        state.unlocked[key] = true
    end
end

--- Return all unlocked ids for a given namespace.
--- e.g. getUnlocked("action", state) → { "assign_ctx", "cancel_trip" }
function UnlockService.getUnlocked(namespace, state)
    local prefix = namespace .. ":"
    local len    = #prefix
    local result = {}
    for key in pairs(state.unlocked) do
        if key:sub(1, len) == prefix then
            result[#result + 1] = key:sub(len + 1)
        end
    end
    return result
end

--- Filter an options array to only include unlocked ids.
--- Returns a new array containing only options where "namespace:option" is unlocked.
function UnlockService.filterOptions(namespace, options, state)
    local result = {}
    for _, opt in ipairs(options) do
        if state.unlocked[Registry.key(namespace, opt)] then
            result[#result + 1] = opt
        end
    end
    return result
end

-- ── Node tree walker ─────────────────────────────────────────────────────────
-- Walks a dispatch rule node tree and extracts all referenced unlock keys.
-- Returns them as a flat set (keys = true).

local function collectFromNode(node, keys)
    if not node or type(node) ~= "table" then return end

    -- Block def_id
    if node.def_id then
        keys["block:" .. node.def_id] = true
    end

    -- Slot values
    local slots = node.slots
    if slots then
        if slots.action   then keys["action:" .. slots.action] = true end
        if slots.collection then keys["collection:" .. slots.collection] = true end
        if slots.sorter    then keys["sorter:" .. slots.sorter] = true end
        if slots.vehicle_type and slots.vehicle_type ~= "any" then
            keys["vehicle:" .. slots.vehicle_type] = true
        end
        if slots.scope     then keys["scope:" .. slots.scope] = true end
        if slots.building_type then keys["building:" .. slots.building_type] = true end
        if slots.metric    then keys["sort_metric:" .. slots.metric] = true end

        -- rep_get_property: source + property
        if node.def_id == "rep_get_property" then
            if slots.source then
                keys["property_source:" .. slots.source] = true
                if slots.property then
                    keys["property:" .. slots.source .. "." .. slots.property] = true
                end
            end
        end

        -- Recurse into reporter slot values (wrapped as { kind="reporter", node={...} })
        for _, v in pairs(slots) do
            if type(v) == "table" then
                if v.kind == "reporter" and v.node then
                    collectFromNode(v.node, keys)
                elseif v.def_id then
                    collectFromNode(v, keys)
                end
            end
        end
    end

    -- Recurse into children
    if node.condition then collectFromNode(node.condition, keys) end
    if node.body then
        for _, child in ipairs(node.body) do collectFromNode(child, keys) end
    end
    if node.else_body then
        for _, child in ipairs(node.else_body) do collectFromNode(child, keys) end
    end
    -- Bool tree children
    if node.left    then collectFromNode(node.left, keys) end
    if node.right and type(node.right) == "table" then collectFromNode(node.right, keys) end
    if node.operand then collectFromNode(node.operand, keys) end
end

--- Walk a stack (array of nodes) and return all derived unlock keys as a set.
function UnlockService.deriveKeys(stack)
    local keys = {}
    for _, node in ipairs(stack or {}) do
        collectFromNode(node, keys)
    end
    return keys
end

--- Unlock everything referenced by a node tree (block defs, actions, enums, etc.)
function UnlockService.unlockFromNodeTree(stack, state)
    local keys = UnlockService.deriveKeys(stack)
    for key in pairs(keys) do
        state.unlocked[key] = true
    end
end

return UnlockService
