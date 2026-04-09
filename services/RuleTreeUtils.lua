-- services/RuleTreeUtils.lua
-- Data model constructors, tree path operations, and migration utilities
-- for the Scratch-style dispatch rule editor.
--
-- Rule format:
--   rule.stack = array of stack-nodes
--   stack-node kinds: "hat" | "stack" | "control"
--   bool-node kinds:  "bool" (leaves and operators)
--
-- Tree path: ordered array of integer|string keys from rule.stack root to a node.
--   {2}              → rule.stack[2]
--   {2, "body", 1}   → rule.stack[2].body[1]
--   {2, "condition"} → rule.stack[2].condition  (the bool-node in that slot)

local RuleTreeUtils = {}

-- ── ID generation ─────────────────────────────────────────────────────────────

local function makeId()
    return string.format("rule_%d_%d",
        math.floor(love.timer.getTime() * 1000), love.math.random(1000, 9999))
end

-- ── Node constructors ─────────────────────────────────────────────────────────

-- Hat node: trigger block, always first in stack, no top notch.
function RuleTreeUtils.newHatNode(def_id, slots)
    return { kind = "hat", def_id = def_id, slots = slots or {} }
end

-- Stack node: effect or action block, flat execution.
function RuleTreeUtils.newStackNode(def_id, slots)
    return { kind = "stack", def_id = def_id, slots = slots or {} }
end

-- Control node: C-block (if/then or if/then/else).
-- condition: bool-node or nil (empty condition slot)
-- body:      array of stack-nodes (the "then" branch)
-- else_body: array of stack-nodes or nil (the "else" branch; nil = if-only)
function RuleTreeUtils.newControlNode(def_id, condition, body, else_body)
    return {
        kind      = "control",
        def_id    = def_id,
        condition = condition,
        body      = body or {},
        else_body = else_body,
    }
end

-- Find node: C-block that queries the world for a matching trip or vehicle,
-- then runs its body once with that entity in context.
-- slots:     sort_by, order, vehicle_type (for ctrl_find_vehicle)
-- condition: bool-node filter (nil = accept first)
-- body:      array of stack-nodes
function RuleTreeUtils.newFindNode(def_id, slots, body, condition)
    return {
        kind      = "find",
        def_id    = def_id,
        slots     = slots or {},
        condition = condition,
        body      = body or {},
    }
end

-- Loop node: C-block that iterates.
-- slots:     key/value table (e.g. { n=3 } or { vehicle_type="bike" })
-- body:      array of stack-nodes
-- condition: bool-node or nil (used by ctrl_repeat_until)
function RuleTreeUtils.newLoopNode(def_id, slots, body)
    return {
        kind      = "loop",
        def_id    = def_id,
        slots     = slots or {},
        body      = body or {},
        condition = nil,
    }
end

-- Leaf bool-node: a condition block that evaluates to true/false.
function RuleTreeUtils.newBoolLeaf(def_id, slots)
    return { kind = "bool", def_id = def_id, slots = slots or {} }
end

-- Binary bool operator: bool_and or bool_or.
function RuleTreeUtils.newBoolBinary(def_id, left, right)
    return { kind = "bool", def_id = def_id, left = left, right = right }
end

-- Unary bool operator: bool_not.
function RuleTreeUtils.newBoolNot(operand)
    return { kind = "bool", def_id = "bool_not", operand = operand }
end

-- New empty rule in tree format.
function RuleTreeUtils.newRule()
    return { id = makeId(), enabled = true, stack = {} }
end

-- Creates a new node instance based on its definition.
function RuleTreeUtils.newNode(def, game)
    local slots = RuleTreeUtils.defaultSlots(def, game)
    local id, cat = def.id, def.category
    if def.node_kind == "find" then return RuleTreeUtils.newFindNode(id, slots)
    elseif cat == "hat"        then return RuleTreeUtils.newHatNode(id, slots)
    elseif cat == "boolean"    then return RuleTreeUtils.newBoolLeaf(id, slots)
    elseif cat == "control"    then return RuleTreeUtils.newControlNode(id, nil, {}, nil)
    elseif cat == "loop"       then return RuleTreeUtils.newLoopNode(id, slots)
    elseif cat == "reporter"   then return { kind = "reporter", def_id = id, slots = slots }
    else return RuleTreeUtils.newStackNode(id, slots) end
end

-- ── Deep copy ─────────────────────────────────────────────────────────────────

function RuleTreeUtils.deepCopy(orig)
    if type(orig) ~= "table" then return orig end
    local copy = {}
    for k, v in pairs(orig) do
        copy[k] = RuleTreeUtils.deepCopy(v)
    end
    return copy
end

-- ── Path operations ───────────────────────────────────────────────────────────

-- Returns the node at path, or nil if path is invalid.
-- Integer key n  → current[n] (array index)
-- String  key s  → current[s] (field name: "body", "else_body", "condition", "left", "right", "operand")
function RuleTreeUtils.getNodeAtPath(stack, path)
    local cur = stack
    for _, key in ipairs(path) do
        if type(cur) ~= "table" then return nil end
        cur = cur[key]
        if cur == nil then return nil end
    end
    return cur
end

-- Returns the parent table and the final key for a path.
-- Needed for mutation without full copy.
local function resolveParent(stack, path)
    if #path == 0 then return nil, nil end
    local parent = stack
    for i = 1, #path - 1 do
        if type(parent) ~= "table" then return nil, nil end
        parent = parent[path[i]]
    end
    return parent, path[#path]
end

-- Deep copies the stack, removes the node at path, and returns:
--   (removed_node_copy, new_stack)
-- For integer keys: table.remove (shifts the array).
-- For string  keys: sets the field to nil (empties the slot).
function RuleTreeUtils.removeNodeAtPath(stack, path)
    local new_stack = RuleTreeUtils.deepCopy(stack)
    local parent, last_key = resolveParent(new_stack, path)
    if not parent then return nil, new_stack end

    local removed = RuleTreeUtils.deepCopy(parent[last_key])

    if type(last_key) == "number" then
        table.remove(parent, last_key)
    else
        parent[last_key] = nil
    end

    return removed, new_stack
end

-- Deep copies the stack and inserts node at the specified location.
-- Returns new_stack.
--
-- parent_path: path to the parent array or control node
-- slot:        integer (insert before that index in array parent) OR
--              string  (set named field on control/bool node)
-- node:        the node to insert
--
-- Examples:
--   insertNodeAtPath(stack, {}, 2, node)           → insert at rule.stack[2]
--   insertNodeAtPath(stack, {2,"body"}, 1, node)   → insert at rule.stack[2].body[1]
--   insertNodeAtPath(stack, {2}, "condition", node) → set rule.stack[2].condition = node
function RuleTreeUtils.insertNodeAtPath(stack, parent_path, slot, node)
    local new_stack = RuleTreeUtils.deepCopy(stack)
    local node_copy = RuleTreeUtils.deepCopy(node)

    local parent
    if #parent_path == 0 then
        parent = new_stack
    else
        parent = RuleTreeUtils.getNodeAtPath(new_stack, parent_path)
    end

    if not parent then return new_stack end

    if type(slot) == "number" then
        table.insert(parent, slot, node_copy)
    else
        parent[slot] = node_copy
    end

    return new_stack
end

-- ── Slot defaults ─────────────────────────────────────────────────────────────

-- Build default slot values for a block def (mirrors old RuleEngine.newBlockInst logic).
-- Needs game for vehicle_enum defaults.
function RuleTreeUtils.defaultSlots(def, game)
    local slots = {}
    for _, sd in ipairs(def.slots or {}) do
        if sd.type == "vehicle_enum" then
            -- Only provide a default for vehicle_enum if it's NOT the Get block, 
            -- or keep it nil so it cascades.
            if def.id ~= "rep_get_property" then
                local first = nil
                for id in pairs(game and game.C and game.C.VEHICLES or {}) do
                    local low = id:lower()
                    if not first or low < first then first = low end
                end
                slots[sd.key] = first or sd.default or ""
            end
        else
            slots[sd.key] = sd.default
        end
    end
    return slots
end

-- ── Prefabs ───────────────────────────────────────────────────────────────────

-- Returns the full prefab registry.
function RuleTreeUtils.getPrefabs()
    return require("data.dispatch_prefabs")
end

-- Instantiate a prefab with the given params, returning a deep copy of its tree.
-- params: key→value table matching the prefab's params list.
function RuleTreeUtils.instantiatePrefab(prefab, params)
    local node = prefab.build(params or {})
    return RuleTreeUtils.deepCopy(node)
end

-- ── Migration: old flat format → new tree format ──────────────────────────────
-- Converts rule.blocks (flat array) to rule.stack (tree).
-- Preserves evaluation semantics exactly (left-associative AND/OR/NOT).

function RuleTreeUtils.migrateRule(old_rule)
    if not old_rule.blocks then return old_rule end  -- already migrated

    local new_rule = {
        id      = old_rule.id,
        enabled = old_rule.enabled,
        stack   = {},
    }

    -- Separate blocks by category
    local trigger_block = nil
    local cond_blocks   = {}  -- {block, kind} where kind = "cond"|"logic"|"negate"
    local action_blocks = {}  -- stack nodes (effects + actions)

    for _, block in ipairs(old_rule.blocks) do
        -- Look up old category via block def id patterns
        local id = block.def_id or ""
        if id == "trigger_trip" then
            trigger_block = block
        elseif id == "logic_and" then
            cond_blocks[#cond_blocks + 1] = { kind = "logic", op = "and" }
        elseif id == "logic_or" then
            cond_blocks[#cond_blocks + 1] = { kind = "logic", op = "or" }
        elseif id == "logic_not" then
            cond_blocks[#cond_blocks + 1] = { kind = "negate" }
        elseif id:sub(1,5) == "cond_" then
            cond_blocks[#cond_blocks + 1] = { kind = "cond", block = block }
        else
            -- effect or action → stack node
            action_blocks[#action_blocks + 1] = {
                kind   = "stack",
                def_id = block.def_id,
                slots  = block.slots or {},
            }
        end
    end

    -- Hat node
    if trigger_block then
        new_rule.stack[#new_rule.stack + 1] = RuleTreeUtils.newHatNode(
            trigger_block.def_id, trigger_block.slots)
    end

    -- Build bool tree from flat cond_blocks using old pending_op semantics.
    -- Strategy: build left-associative tree.
    -- e.g. A and B or C  →  OR(AND(A, B), C)
    local bool_tree = nil
    local pending_op    = "and"
    local pending_negate = false

    local function applyNegate(node)
        if pending_negate then
            pending_negate = false
            return RuleTreeUtils.newBoolNot(node)
        end
        return node
    end

    local function combine(left, right, op)
        if left == nil then return right end
        if op == "or" then
            return RuleTreeUtils.newBoolBinary("bool_or", left, right)
        else
            return RuleTreeUtils.newBoolBinary("bool_and", left, right)
        end
    end

    for _, entry in ipairs(cond_blocks) do
        if entry.kind == "negate" then
            pending_negate = not pending_negate
        elseif entry.kind == "logic" then
            pending_op = entry.op
        elseif entry.kind == "cond" then
            local leaf = RuleTreeUtils.newBoolLeaf(entry.block.def_id, entry.block.slots)
            leaf = applyNegate(leaf)
            bool_tree  = combine(bool_tree, leaf, pending_op)
            pending_op = "and"
        end
    end

    -- Wrap in ctrl_if if conditions exist, else put actions directly in stack
    if bool_tree then
        new_rule.stack[#new_rule.stack + 1] = RuleTreeUtils.newControlNode(
            "ctrl_if", bool_tree, action_blocks)
    else
        for _, node in ipairs(action_blocks) do
            new_rule.stack[#new_rule.stack + 1] = node
        end
    end

    return new_rule
end

-- Migrate a list of rules in place. Detects old format by presence of .blocks field.
function RuleTreeUtils.migrateRules(rules)
    for i, rule in ipairs(rules) do
        if rule.blocks then
            rules[i] = RuleTreeUtils.migrateRule(rule)
        end
    end
end

-- ── Tree traversal helpers ────────────────────────────────────────────────────

-- Call fn(node, path) for every node in the tree (depth-first).
-- path is the tree path to reach that node.
function RuleTreeUtils.walkTree(stack, fn, _path)
    local path = _path or {}
    for i, node in ipairs(stack) do
        local node_path = {}
        for _, k in ipairs(path) do node_path[#node_path+1] = k end
        node_path[#node_path+1] = i
        fn(node, node_path)
        if node.kind == "control" then
            -- Walk body
            local body_path = {}
            for _, k in ipairs(node_path) do body_path[#body_path+1] = k end
            body_path[#body_path+1] = "body"
            RuleTreeUtils.walkTree(node.body or {}, fn, body_path)
            -- Walk else_body
            if node.else_body then
                local else_path = {}
                for _, k in ipairs(node_path) do else_path[#else_path+1] = k end
                else_path[#else_path+1] = "else_body"
                RuleTreeUtils.walkTree(node.else_body, fn, else_path)
            end
        elseif node.kind == "loop" or node.kind == "find" then
            -- Walk body
            local body_path = {}
            for _, k in ipairs(node_path) do body_path[#body_path+1] = k end
            body_path[#body_path+1] = "body"
            RuleTreeUtils.walkTree(node.body or {}, fn, body_path)
        end
    end
end

-- Call fn(bool_node, path) for every bool-node in the tree.
function RuleTreeUtils.walkBoolTree(node, fn, path)
    if not node then return end
    fn(node, path)
    if node.def_id == "bool_and" or node.def_id == "bool_or" then
        local left_path  = {}; for _,k in ipairs(path) do left_path[#left_path+1]=k end; left_path[#left_path+1]="left"
        local right_path = {}; for _,k in ipairs(path) do right_path[#right_path+1]=k end; right_path[#right_path+1]="right"
        RuleTreeUtils.walkBoolTree(node.left,  fn, left_path)
        RuleTreeUtils.walkBoolTree(node.right, fn, right_path)
    elseif node.def_id == "bool_not" then
        local op_path = {}; for _,k in ipairs(path) do op_path[#op_path+1]=k end; op_path[#op_path+1]="operand"
        RuleTreeUtils.walkBoolTree(node.operand, fn, op_path)
    end
end

-- ── Path helpers ──────────────────────────────────────────────────────────────

-- Returns true if two tree paths (arrays of keys) are equal.
function RuleTreeUtils.pathsEqual(a, b)
    if not a or not b or #a ~= #b then return false end
    for i = 1, #a do if a[i] ~= b[i] then return false end end
    return true
end

-- Returns a new path with key appended.
function RuleTreeUtils.appendPath(base, key)
    local p = {}
    for _, k in ipairs(base or {}) do p[#p+1] = k end
    p[#p+1] = key
    return p
end

return RuleTreeUtils
