-- data/dispatch_blocks.lua
-- Pure data: block definitions for the visual dispatch rule editor.
-- No functions, no requires. Add an entry here to add a new block type.
--
-- Categories:
--   hat      — trigger block; starts a rule (rounded top, tab bottom)
--   boolean  — condition/logic block; evaluates to true/false (hexagonal)
--   stack    — effect or action block; runs in sequence (puzzle-piece shape)
--   control  — C-block (if/then or if/then/else); contains sub-stacks
--
-- Structural fields:
--   must_be_first  = true    → can only be placed as the very first block in the stack
--   max_per_rule   = N       → at most N of this block per rule (checked across whole tree)
--   terminal       = true    → stack execution stops after this block
--   slot_accepts   = { ... } → what node kinds are accepted in each named slot
--
-- Semantic fields:
--   assertion      = { subject, property, op?, op_from_slot?, slot?, key_slot? }
--     op_from_slot: read the op from node.slots[op_from_slot]; ">"→"gt", "<"→"lt", "="→"eq"
--   constraint     = "name"
--   evaluator      = "name"
--   tooltip        = "string"   — shown in tooltip after 2s hover

local COUNTER_KEYS = { "A", "B", "C", "D", "E" }
local FLAG_KEYS    = { "X", "Y", "Z" }

-- ── Shared slot definitions ───────────────────────────────────────────────────
local SCOPE_SLOT    = { key = "scope",        type = "enum",         options = { "district", "city", "region", "continent", "world" }, default = "district" }
local VALUE_SLOT    = { key = "value",        type = "number",       default = 0,   step = 50,  min = 0 }
local SECONDS_SLOT  = { key = "seconds",      type = "number",       default = 10,  step = 5,   min = 0 }
local VEHICLE_SLOT  = { key = "vehicle_type", type = "vehicle_enum", default = "bike" }
local QUEUE_SLOT    = { key = "value",        type = "number",       default = 5,   step = 1,   min = 0 }
local MONEY_SLOT    = { key = "value",        type = "number",       default = 500, step = 100, min = 0 }
local COUNTER_SLOT  = { key = "key",          type = "enum",         options = COUNTER_KEYS, default = "A" }
local COUNT_VAL     = { key = "value",        type = "number",       default = 0,   step = 1,   min = 0 }
local FLAG_SLOT     = { key = "key",          type = "enum",         options = FLAG_KEYS,    default = "X" }
local AMOUNT_SLOT   = { key = "amount",       type = "number",       default = 1,   step = 1,   min = 1 }
local N_SLOT        = { key = "n",            type = "number",       default = 1,   step = 1,   min = 1 }

-- Reusable operator slots
local OP_CMP_SLOT   = { key = "op",  type = "enum", options = { ">", "<", "=" },   default = ">" }
local OP_DELTA_SLOT = { key = "op",  type = "enum", options = { "+=", "-=" },       default = "+=" }

return {

-- ═══════════════════════════════════════════════════════════════════════════
-- HAT — trigger block
-- ═══════════════════════════════════════════════════════════════════════════

    { id           = "trigger_trip",
      category     = "hat",
      color        = { 0.85, 0.65, 0.10 },
      label        = "when trip pending",
      tooltip      = "Trigger: fires when a new delivery trip enters the pending queue. Every rule must start with this block.",
      slots        = {},
      must_be_first = true,
      max_per_rule = 1 },

-- ═══════════════════════════════════════════════════════════════════════════
-- CONTROL — C-blocks
-- ═══════════════════════════════════════════════════════════════════════════

    { id           = "ctrl_if",
      category     = "control",
      color        = { 0.85, 0.65, 0.10 },
      label        = "if / then",
      tooltip      = "C-block: runs the inner blocks only when the condition is true. Drag a hexagonal condition block into the slot next to 'if'.",
      slots        = {},
      slot_accepts = { condition = "boolean", body = "stack" } },

    { id           = "ctrl_if_else",
      category     = "control",
      color        = { 0.85, 0.65, 0.10 },
      label        = "if / then / else",
      tooltip      = "C-block with else: runs the top section when condition is true; the bottom section when false.",
      slots        = {},
      slot_accepts = { condition = "boolean", body = "stack", else_body = "stack" } },

-- ═══════════════════════════════════════════════════════════════════════════
-- BOOLEAN — logic operators (tree nodes)
-- ═══════════════════════════════════════════════════════════════════════════

    { id           = "bool_and",
      category     = "boolean",
      color        = { 0.82, 0.78, 0.15 },
      label        = "and",
      tooltip      = "Logic AND: true only when both child conditions are true. Drop two condition blocks into the left and right slots.",
      slots        = {},
      slot_accepts = { left = "boolean", right = "boolean" } },

    { id           = "bool_or",
      category     = "boolean",
      color        = { 0.82, 0.78, 0.15 },
      label        = "or",
      tooltip      = "Logic OR: true when either child condition is true.",
      slots        = {},
      slot_accepts = { left = "boolean", right = "boolean" } },

    { id           = "bool_not",
      category     = "boolean",
      color        = { 0.88, 0.50, 0.18 },
      label        = "not",
      tooltip      = "Logic NOT: inverts a condition. True becomes false, false becomes true.",
      slots        = {},
      slot_accepts = { operand = "boolean" } },

-- ═══════════════════════════════════════════════════════════════════════════
-- BOOLEAN — conditions (trip)
-- ═══════════════════════════════════════════════════════════════════════════

    { id           = "cond_scope",
      category     = "boolean",
      color        = { 0.22, 0.68, 0.32 },
      label        = "scope is",
      tooltip      = "True when the trip's delivery scope matches the selected level (district / city / region / continent / world).",
      slots        = { SCOPE_SLOT },
      evaluator    = "scope_equals",
      scope_slot_key = "scope",
      assertion    = { subject = "trip", property = "scope", op = "eq",  slot = "scope" } },

    { id           = "cond_scope_not",
      category     = "boolean",
      color        = { 0.22, 0.68, 0.32 },
      label        = "scope is not",
      tooltip      = "True when the trip's scope does NOT match the selected level.",
      slots        = { SCOPE_SLOT },
      evaluator    = "scope_not_equals",
      assertion    = { subject = "trip", property = "scope", op = "neq", slot = "scope" } },

    { id           = "cond_payout",
      category     = "boolean",
      color        = { 0.22, 0.68, 0.32 },
      label        = "payout",
      tooltip      = "True when the trip's base payout compares to the value using the chosen operator (>, <, or =).",
      slots        = { OP_CMP_SLOT, VALUE_SLOT },
      evaluator    = "payout_compare",
      assertion    = { subject = "trip", property = "payout", op_from_slot = "op", slot = "value" } },

    { id           = "cond_wait",
      category     = "boolean",
      color        = { 0.22, 0.68, 0.32 },
      label        = "waited",
      tooltip      = "True when the trip has been waiting a number of seconds that satisfies the chosen comparison.",
      slots        = { OP_CMP_SLOT, SECONDS_SLOT },
      evaluator    = "wait_compare",
      assertion    = { subject = "trip", property = "wait", op_from_slot = "op", slot = "seconds" } },

    { id           = "cond_multi_leg",
      category     = "boolean",
      color        = { 0.22, 0.68, 0.32 },
      label        = "is multi-city",
      tooltip      = "True when the trip spans multiple cities and requires at least one vehicle transfer.",
      slots        = {},
      evaluator    = "is_multi_leg" },

-- ═══════════════════════════════════════════════════════════════════════════
-- BOOLEAN — conditions (vehicle availability)
-- ═══════════════════════════════════════════════════════════════════════════

    { id           = "cond_vehicle_idle",
      category     = "boolean",
      color        = { 0.28, 0.72, 0.58 },
      label        = "any idle",
      tooltip      = "True when at least one vehicle of the chosen type is idle and eligible for this trip.",
      slots        = { VEHICLE_SLOT },
      evaluator    = "vehicle_idle_any",
      assertion    = { subject = "fleet", property = "idle", op = "any",  key_slot = "vehicle_type" } },

    { id           = "cond_vehicle_none",
      category     = "boolean",
      color        = { 0.28, 0.72, 0.58 },
      label        = "no idle",
      tooltip      = "True when NO vehicles of the chosen type are idle and eligible for this trip.",
      slots        = { VEHICLE_SLOT },
      evaluator    = "vehicle_idle_none",
      assertion    = { subject = "fleet", property = "idle", op = "none", key_slot = "vehicle_type" } },

    { id           = "cond_idle_count",
      category     = "boolean",
      color        = { 0.28, 0.72, 0.58 },
      label        = "idle count",
      tooltip      = "True when the number of idle eligible vehicles of the chosen type satisfies the comparison against N.",
      slots        = { VEHICLE_SLOT, OP_CMP_SLOT, N_SLOT },
      evaluator    = "idle_count_compare",
      assertion    = { subject = "fleet", property = "idle", op_from_slot = "op", slot = "n", key_slot = "vehicle_type" } },

-- ═══════════════════════════════════════════════════════════════════════════
-- BOOLEAN — conditions (game state)
-- ═══════════════════════════════════════════════════════════════════════════

    { id           = "cond_queue",
      category     = "boolean",
      color        = { 0.35, 0.65, 0.72 },
      label        = "queue",
      tooltip      = "True when the number of unassigned pending trips satisfies the comparison against the value.",
      slots        = { OP_CMP_SLOT, QUEUE_SLOT },
      evaluator    = "queue_compare",
      assertion    = { subject = "game", property = "queue", op_from_slot = "op", slot = "value" } },

    { id           = "cond_money",
      category     = "boolean",
      color        = { 0.35, 0.65, 0.72 },
      label        = "money",
      tooltip      = "True when current cash satisfies the comparison against the value.",
      slots        = { OP_CMP_SLOT, MONEY_SLOT },
      evaluator    = "money_compare",
      assertion    = { subject = "game", property = "money", op_from_slot = "op", slot = "value" } },

    { id           = "cond_rush_hour",
      category     = "boolean",
      color        = { 0.35, 0.65, 0.72 },
      label        = "rush hour",
      tooltip      = "True during an active rush hour event (increased trip generation and payout).",
      slots        = {},
      evaluator    = "rush_hour_active",
      max_per_rule = 1 },

-- ═══════════════════════════════════════════════════════════════════════════
-- BOOLEAN — conditions (counters & flags)
-- ═══════════════════════════════════════════════════════════════════════════

    { id           = "cond_counter",
      category     = "boolean",
      color        = { 0.55, 0.38, 0.80 },
      label        = "counter",
      tooltip      = "True when the named counter (A-E) satisfies the comparison. Counters persist across ticks and rules.",
      slots        = { COUNTER_SLOT, OP_CMP_SLOT, COUNT_VAL },
      evaluator    = "counter_compare",
      assertion    = { subject = "counter", property = "value", op_from_slot = "op", slot = "value", key_slot = "key" } },

    { id           = "cond_flag_set",
      category     = "boolean",
      color        = { 0.55, 0.38, 0.80 },
      label        = "flag set",
      tooltip      = "True when the named flag (X, Y, Z) has been set. Flags are persistent boolean markers you control with 'set flag' / 'clear flag'.",
      slots        = { FLAG_SLOT },
      evaluator    = "flag_is_set",
      assertion    = { subject = "flag", property = "state", op = "set",   key_slot = "key" } },

    { id           = "cond_flag_clear",
      category     = "boolean",
      color        = { 0.55, 0.38, 0.80 },
      label        = "flag clear",
      tooltip      = "True when the named flag is NOT set.",
      slots        = { FLAG_SLOT },
      evaluator    = "flag_is_clear",
      assertion    = { subject = "flag", property = "state", op = "clear", key_slot = "key" } },

-- ═══════════════════════════════════════════════════════════════════════════
-- STACK — effects (side-effect blocks; do NOT claim the trip)
-- ═══════════════════════════════════════════════════════════════════════════

    { id           = "effect_counter_change",
      category     = "stack",
      color        = { 0.52, 0.28, 0.80 },
      label        = "counter",
      tooltip      = "Side-effect: adds or subtracts a fixed amount from the named counter. Does not claim the trip — execution continues.",
      slots        = { COUNTER_SLOT, OP_DELTA_SLOT, AMOUNT_SLOT },
      evaluator    = "counter_change" },

    { id           = "effect_counter_reset",
      category     = "stack",
      color        = { 0.52, 0.28, 0.80 },
      label        = "reset counter",
      tooltip      = "Side-effect: sets the named counter back to zero.",
      slots        = { COUNTER_SLOT },
      evaluator    = "counter_reset" },

    { id           = "effect_flag_set",
      category     = "stack",
      color        = { 0.52, 0.28, 0.80 },
      label        = "set flag",
      tooltip      = "Side-effect: marks the named flag as set. Use with 'flag set' conditions in other rules to coordinate behaviour.",
      slots        = { FLAG_SLOT },
      evaluator    = "flag_set" },

    { id           = "effect_flag_clear",
      category     = "stack",
      color        = { 0.52, 0.28, 0.80 },
      label        = "clear flag",
      tooltip      = "Side-effect: clears the named flag (sets it to false).",
      slots        = { FLAG_SLOT },
      evaluator    = "flag_clear" },

-- ═══════════════════════════════════════════════════════════════════════════
-- STACK — actions (terminal blocks)
-- ═══════════════════════════════════════════════════════════════════════════

    { id             = "action_assign_type",
      category       = "stack",
      color          = { 0.28, 0.45, 0.88 },
      label          = "assign to",
      tooltip        = "Action: assigns the trip to an idle vehicle of the chosen type. The rule stops if a vehicle is found.",
      slots          = { VEHICLE_SLOT },
      evaluator      = "assign_vehicle_type",
      vehicle_slot_key = "vehicle_type",
      constraint     = "vehicle_covers_trip_scope" },

    { id             = "action_assign_any",
      category       = "stack",
      color          = { 0.28, 0.45, 0.88 },
      label          = "assign to any",
      tooltip        = "Action: assigns the trip to any eligible idle vehicle regardless of type.",
      slots          = {},
      evaluator      = "assign_any" },

    { id             = "action_assign_nearest",
      category       = "stack",
      color          = { 0.28, 0.45, 0.88 },
      label          = "nearest",
      tooltip        = "Action: assigns the trip to the nearest eligible idle vehicle of the chosen type (by travel distance).",
      slots          = { VEHICLE_SLOT },
      evaluator      = "assign_nearest",
      vehicle_slot_key = "vehicle_type",
      constraint     = "vehicle_covers_trip_scope" },

    { id             = "action_cancel",
      category       = "stack",
      color          = { 0.62, 0.18, 0.18 },
      label          = "cancel trip",
      tooltip        = "Action: removes the trip from the queue without assigning it. Use to drop low-value or undesired trips.",
      slots          = {},
      evaluator      = "cancel_trip",
      terminal       = true,
      max_per_rule   = 1 },

    { id             = "action_skip",
      category       = "stack",
      color          = { 0.72, 0.22, 0.22 },
      label          = "skip (hold)",
      tooltip        = "Action: holds the trip in the pending queue for this tick without assigning it. It will be re-evaluated next tick.",
      slots          = {},
      evaluator      = "skip",
      terminal       = true,
      max_per_rule   = 1 },

}
