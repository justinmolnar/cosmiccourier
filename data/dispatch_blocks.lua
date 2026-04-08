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
local VAR_SLOT      = { key = "key",          type = "string",       default = "my_var" }
local COUNT_VAL     = { key = "value",        type = "number",       default = 0,   step = 1,   min = 0 }
local AMOUNT_SLOT   = { key = "amount",       type = "number",       default = 1,   step = 1,   min = 1 }
local N_SLOT        = { key = "n",            type = "number",       default = 1,   step = 1,   min = 1 }

-- Reusable operator slots
local OP_CMP_SLOT   = { key = "op",  type = "enum", options = { ">", "<", ">=", "<=", "!=", "=" },   default = ">" }
local OP_DELTA_SLOT = { key = "op",  type = "enum", options = { "+=", "-=" },       default = "+=" }
local TEXT_VAR_SLOT = { key = "key", type = "string",       default = "my_var" }

-- Reporter input slots (accept literal number or reporter node)
local REP_A = { key = "a", type = "number", default = 0, step = 1, min = nil }
local REP_B = { key = "b", type = "number", default = 0, step = 1, min = nil }

return {

-- ═══════════════════════════════════════════════════════════════════════════
-- HAT — trigger block
-- ═══════════════════════════════════════════════════════════════════════════

    { id           = "trigger_trip",
      category     = "hat",
      tags         = { "trigger", "trip" },
      color        = { 0.85, 0.65, 0.10 },
      label        = "when trip pending",
      tooltip      = "Trigger: fires when a new delivery trip enters the pending queue. Every rule must start with this block.",
      slots        = {},
      must_be_first = true,
      max_per_rule = 1 },

-- ── Vehicle lifecycle event hats ───────────────────────────────────────────

    { id           = "hat_vehicle_hired",
      category     = "hat",
      event_type   = "vehicle_hired",
      tags         = { "trigger", "vehicle" },
      color        = { 0.20, 0.65, 0.45 },
      label        = "when vehicle hired",
      tooltip      = "Fires once when a vehicle of the chosen type is added to your fleet.",
      slots        = { VEHICLE_SLOT },
      must_be_first = true, max_per_rule = 1 },

    { id           = "hat_vehicle_idle",
      category     = "hat",
      event_type   = "vehicle_idle",
      tags         = { "trigger", "vehicle" },
      color        = { 0.20, 0.65, 0.45 },
      label        = "when vehicle becomes idle",
      tooltip      = "Fires when a vehicle finishes returning to depot and becomes idle.",
      slots        = { VEHICLE_SLOT },
      must_be_first = true, max_per_rule = 1 },

    { id           = "hat_vehicle_trip_complete",
      category     = "hat",
      event_type   = "vehicle_trip_complete",
      tags         = { "trigger", "vehicle" },
      color        = { 0.20, 0.65, 0.45 },
      label        = "when vehicle completes trip",
      tooltip      = "Fires when a vehicle makes a final delivery on a trip.",
      slots        = { VEHICLE_SLOT },
      must_be_first = true, max_per_rule = 1 },

    { id           = "hat_vehicle_pickup",
      category     = "hat",
      event_type   = "vehicle_pickup",
      tags         = { "trigger", "vehicle" },
      color        = { 0.20, 0.65, 0.45 },
      label        = "when vehicle picks up cargo",
      tooltip      = "Fires when a vehicle picks up cargo and begins transit.",
      slots        = { VEHICLE_SLOT },
      must_be_first = true, max_per_rule = 1 },

    { id           = "hat_vehicle_returns_depot",
      category     = "hat",
      event_type   = "vehicle_returns_depot",
      tags         = { "trigger", "vehicle" },
      color        = { 0.20, 0.65, 0.45 },
      label        = "when vehicle returns to depot",
      tooltip      = "Fires when a vehicle arrives back at its depot after its last delivery.",
      slots        = { VEHICLE_SLOT },
      must_be_first = true, max_per_rule = 1 },

    { id           = "hat_hotkey",
      category     = "hat",
      event_type   = "hotkey",
      tags         = { "trigger", "logic" },
      color        = { 0.70, 0.42, 0.18 },
      label        = "when hotkey pressed",
      tooltip      = "Fires when the player presses the chosen key. Works regardless of dispatch unlock.",
      slots        = { { key="key", type="key_enum", default="1" } },
      must_be_first = true, max_per_rule = 1 },

    { id           = "hat_vehicle_dismissed",
      category     = "hat",
      event_type   = "vehicle_dismissed",
      tags         = { "trigger", "vehicle" },
      color        = { 0.20, 0.65, 0.45 },
      label        = "when vehicle dismissed",
      tooltip      = "Fires when a vehicle of the chosen type is removed from your fleet.",
      slots        = { VEHICLE_SLOT },
      must_be_first = true, max_per_rule = 1 },

    { id           = "hat_vehicle_idle_for",
      category     = "hat",
      event_type   = "poll",
      hat_evaluator = "hat_vehicle_idle_for",
      tags         = { "trigger", "vehicle" },
      color        = { 0.20, 0.65, 0.45 },
      label        = "when vehicle idle for",
      tooltip      = "Fires (each dispatch tick) while any matching vehicle has been idle for at least N seconds. ctx.vehicle is set to that vehicle.",
      slots        = { VEHICLE_SLOT,
                       { key="seconds", type="number", default=10, step=5, min=1 } },
      must_be_first = true, max_per_rule = 1 },

-- ── Rush hour event hats ───────────────────────────────────────────────────

    { id           = "hat_rush_hour_start",
      category     = "hat",
      event_type   = "rush_hour_start",
      tags         = { "trigger", "game" },
      color        = { 0.85, 0.40, 0.20 },
      label        = "when rush hour starts",
      tooltip      = "Fires once when a rush hour event begins.",
      slots        = {},
      must_be_first = true, max_per_rule = 1 },

    { id           = "hat_rush_hour_end",
      category     = "hat",
      event_type   = "rush_hour_end",
      tags         = { "trigger", "game" },
      color        = { 0.85, 0.40, 0.20 },
      label        = "when rush hour ends",
      tooltip      = "Fires once when a rush hour event ends.",
      slots        = {},
      must_be_first = true, max_per_rule = 1 },

-- ── Polling hats (fire each dispatch tick while condition holds) ───────────

    { id           = "hat_money_below",
      category     = "hat",
      event_type   = "poll",
      hat_evaluator = "hat_money_below",
      tags         = { "trigger", "game" },
      color        = { 0.35, 0.65, 0.72 },
      label        = "while money below",
      tooltip      = "Fires each dispatch tick while your money is below the threshold.",
      slots        = { MONEY_SLOT },
      must_be_first = true, max_per_rule = 1 },

    { id           = "hat_money_above",
      category     = "hat",
      event_type   = "poll",
      hat_evaluator = "hat_money_above",
      tags         = { "trigger", "game" },
      color        = { 0.35, 0.65, 0.72 },
      label        = "while money above",
      tooltip      = "Fires each dispatch tick while your money is above the threshold.",
      slots        = { MONEY_SLOT },
      must_be_first = true, max_per_rule = 1 },

    { id           = "hat_queue_reaches",
      category     = "hat",
      event_type   = "poll",
      hat_evaluator = "hat_queue_reaches",
      tags         = { "trigger", "game" },
      color        = { 0.35, 0.65, 0.72 },
      label        = "while queue at least",
      tooltip      = "Fires each dispatch tick while the pending queue has at least N trips.",
      slots        = { N_SLOT },
      must_be_first = true, max_per_rule = 1 },

    { id           = "hat_queue_empties",
      category     = "hat",
      event_type   = "poll",
      hat_evaluator = "hat_queue_empties",
      tags         = { "trigger", "game" },
      color        = { 0.35, 0.65, 0.72 },
      label        = "while queue empty",
      tooltip      = "Fires each dispatch tick while there are no pending trips.",
      slots        = {},
      must_be_first = true, max_per_rule = 1 },

    { id           = "hat_all_busy",
      category     = "hat",
      event_type   = "poll",
      hat_evaluator = "hat_all_busy",
      tags         = { "trigger", "vehicle" },
      color        = { 0.20, 0.65, 0.45 },
      label        = "while all busy",
      tooltip      = "Fires each dispatch tick while no vehicles of the chosen type are idle.",
      slots        = { VEHICLE_SLOT },
      must_be_first = true, max_per_rule = 1 },

    { id           = "hat_all_idle",
      category     = "hat",
      event_type   = "poll",
      hat_evaluator = "hat_all_idle",
      tags         = { "trigger", "vehicle" },
      color        = { 0.20, 0.65, 0.45 },
      label        = "while all idle",
      tooltip      = "Fires each dispatch tick while all vehicles of the chosen type are idle.",
      slots        = { VEHICLE_SLOT },
      must_be_first = true, max_per_rule = 1 },

    { id           = "hat_counter_reaches",
      category     = "hat",
      event_type   = "poll",
      hat_evaluator = "hat_counter_reaches",
      tags         = { "trigger", "counter" },
      color        = { 0.55, 0.38, 0.80 },
      label        = "while counter at least",
      tooltip      = "Fires each dispatch tick while the named counter is at or above the value.",
      slots        = { VAR_SLOT, COUNT_VAL },
      must_be_first = true, max_per_rule = 1 },

    { id           = "hat_counter_drops",
      category     = "hat",
      event_type   = "poll",
      hat_evaluator = "hat_counter_drops",
      tags         = { "trigger", "counter" },
      color        = { 0.55, 0.38, 0.80 },
      label        = "while counter below",
      tooltip      = "Fires each dispatch tick while the named counter is below the value.",
      slots        = { VAR_SLOT, COUNT_VAL },
      must_be_first = true, max_per_rule = 1 },

    { id           = "hat_flag_set",
      category     = "hat",
      event_type   = "poll",
      hat_evaluator = "hat_flag_set_poll",
      tags         = { "trigger", "counter" },
      color        = { 0.55, 0.38, 0.80 },
      label        = "while flag set",
      tooltip      = "Fires each dispatch tick while the named flag is set.",
      slots        = { VAR_SLOT },
      must_be_first = true, max_per_rule = 1 },

    { id           = "hat_flag_cleared",
      category     = "hat",
      event_type   = "poll",
      hat_evaluator = "hat_flag_cleared_poll",
      tags         = { "trigger", "counter" },
      color        = { 0.55, 0.38, 0.80 },
      label        = "while flag clear",
      tooltip      = "Fires each dispatch tick while the named flag is clear.",
      slots        = { VAR_SLOT },
      must_be_first = true, max_per_rule = 1 },

-- ═══════════════════════════════════════════════════════════════════════════
-- CONTROL — C-blocks
-- ═══════════════════════════════════════════════════════════════════════════

    { id           = "ctrl_if",
      category     = "control",
      tags         = { "logic" },
      color        = { 0.85, 0.65, 0.10 },
      label        = "if / then",
      tooltip      = "C-block: runs the inner blocks only when the condition is true. Drag a hexagonal condition block into the slot next to 'if'.",
      slots        = {},
      slot_accepts = { condition = "boolean", body = "stack" } },

    { id           = "ctrl_if_else",
      category     = "control",
      tags         = { "logic" },
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
      tags         = { "logic" },
      color        = { 0.82, 0.78, 0.15 },
      label        = "and",
      tooltip      = "Logic AND: true only when both child conditions are true. Drop two condition blocks into the left and right slots.",
      slots        = {},
      slot_accepts = { left = "boolean", right = "boolean" } },

    { id           = "bool_or",
      category     = "boolean",
      tags         = { "logic" },
      color        = { 0.82, 0.78, 0.15 },
      label        = "or",
      tooltip      = "Logic OR: true when either child condition is true.",
      slots        = {},
      slot_accepts = { left = "boolean", right = "boolean" } },

    { id           = "bool_not",
      category     = "boolean",
      tags         = { "logic" },
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
      tags         = { "trip" },
      color        = { 0.22, 0.68, 0.32 },
      label        = "scope is",
      tooltip      = "True when the trip's delivery scope matches the selected level (district / city / region / continent / world).",
      slots        = { SCOPE_SLOT },
      evaluator    = "scope_equals",
      scope_slot_key = "scope",
      assertion    = { subject = "trip", property = "scope", op = "eq",  slot = "scope" } },

    { id           = "cond_scope_not",
      category     = "boolean",
      tags         = { "trip" },
      color        = { 0.22, 0.68, 0.32 },
      label        = "scope is not",
      tooltip      = "True when the trip's scope does NOT match the selected level.",
      slots        = { SCOPE_SLOT },
      evaluator    = "scope_not_equals",
      assertion    = { subject = "trip", property = "scope", op = "neq", slot = "scope" } },

    { id           = "cond_payout",
      category     = "boolean",
      tags         = { "trip" },
      color        = { 0.22, 0.68, 0.32 },
      label        = "payout",
      tooltip      = "True when the trip's base payout compares to the value using the chosen operator (>, <, or =).",
      slots        = { OP_CMP_SLOT, VALUE_SLOT },
      evaluator    = "payout_compare",
      assertion    = { subject = "trip", property = "payout", op_from_slot = "op", slot = "value" } },

    { id           = "cond_wait",
      category     = "boolean",
      tags         = { "trip" },
      color        = { 0.22, 0.68, 0.32 },
      label        = "waited",
      tooltip      = "True when the trip has been waiting a number of seconds that satisfies the chosen comparison.",
      slots        = { OP_CMP_SLOT, SECONDS_SLOT },
      evaluator    = "wait_compare",
      assertion    = { subject = "trip", property = "wait", op_from_slot = "op", slot = "seconds" } },

    { id           = "cond_multi_leg",
      category     = "boolean",
      tags         = { "trip" },
      color        = { 0.22, 0.68, 0.32 },
      label        = "is multi-city",
      tooltip      = "True when the trip spans multiple cities and requires at least one vehicle transfer.",
      slots        = {},
      evaluator    = "is_multi_leg" },

    { id           = "cond_leg_count",
      category     = "boolean",
      tags         = { "trip" },
      color        = { 0.22, 0.68, 0.32 },
      label        = "leg count",
      tooltip      = "True when the number of legs in this trip satisfies the comparison.",
      slots        = { OP_CMP_SLOT, { key="value", type="number", default=1, step=1, min=1 } },
      evaluator    = "leg_count",
      assertion    = { subject="trip", property="leg_count", op_from_slot="op", slot="value" } },

    { id           = "cond_cargo_size",
      category     = "boolean",
      tags         = { "trip" },
      color        = { 0.22, 0.68, 0.32 },
      label        = "cargo size",
      tooltip      = "True when the cargo size of the current leg satisfies the comparison.",
      slots        = { OP_CMP_SLOT, { key="value", type="number", default=1, step=1, min=0 } },
      evaluator    = "cargo_size" },

    { id           = "cond_trip_bonus",
      category     = "boolean",
      tags         = { "trip" },
      color        = { 0.22, 0.68, 0.32 },
      label        = "trip bonus",
      tooltip      = "True when the current speed bonus on this trip satisfies the comparison. Bonus decreases while in transit.",
      slots        = { OP_CMP_SLOT, { key="value", type="number", default=50, step=10, min=0 } },
      evaluator    = "trip_bonus" },

-- ═══════════════════════════════════════════════════════════════════════════
-- BOOLEAN — conditions (vehicle availability)
-- ═══════════════════════════════════════════════════════════════════════════

    { id           = "cond_vehicle_idle",
      category     = "boolean",
      tags         = { "vehicle", "game" },
      color        = { 0.28, 0.72, 0.58 },
      label        = "any idle",
      tooltip      = "True when at least one vehicle of the chosen type is idle and eligible for this trip.",
      slots        = { VEHICLE_SLOT },
      evaluator    = "vehicle_idle_any",
      assertion    = { subject = "fleet", property = "idle", op = "any",  key_slot = "vehicle_type" } },

    { id           = "cond_vehicle_none",
      category     = "boolean",
      tags         = { "vehicle", "game" },
      color        = { 0.28, 0.72, 0.58 },
      label        = "no idle",
      tooltip      = "True when NO vehicles of the chosen type are idle and eligible for this trip.",
      slots        = { VEHICLE_SLOT },
      evaluator    = "vehicle_idle_none",
      assertion    = { subject = "fleet", property = "idle", op = "none", key_slot = "vehicle_type" } },

    { id           = "cond_idle_count",
      category     = "boolean",
      tags         = { "vehicle", "game" },
      color        = { 0.28, 0.72, 0.58 },
      label        = "idle count",
      tooltip      = "True when the number of idle eligible vehicles of the chosen type satisfies the comparison against N.",
      slots        = { VEHICLE_SLOT, OP_CMP_SLOT, N_SLOT },
      evaluator    = "idle_count_compare",
      assertion    = { subject = "fleet", property = "idle", op_from_slot = "op", slot = "n", key_slot = "vehicle_type" } },

    { id           = "cond_fleet_util",
      category     = "boolean",
      tags         = { "vehicle", "game" },
      color        = { 0.28, 0.72, 0.58 },
      label        = "fleet util %",
      tooltip      = "True when the percentage of non-idle vehicles (fleet utilisation) satisfies the comparison.",
      slots        = { OP_CMP_SLOT, { key="value", type="number", default=50, step=5, min=0 } },
      evaluator    = "fleet_util" },

-- ═══════════════════════════════════════════════════════════════════════════
-- BOOLEAN — conditions (game state)
-- ═══════════════════════════════════════════════════════════════════════════

    { id           = "cond_queue",
      category     = "boolean",
      tags         = { "game", "trip" },
      color        = { 0.35, 0.65, 0.72 },
      label        = "queue",
      tooltip      = "True when the number of unassigned pending trips satisfies the comparison against the value.",
      slots        = { OP_CMP_SLOT, QUEUE_SLOT },
      evaluator    = "queue_compare",
      assertion    = { subject = "game", property = "queue", op_from_slot = "op", slot = "value" } },

    { id           = "cond_money",
      category     = "boolean",
      tags         = { "game" },
      color        = { 0.35, 0.65, 0.72 },
      label        = "money",
      tooltip      = "True when current cash satisfies the comparison against the value.",
      slots        = { OP_CMP_SLOT, MONEY_SLOT },
      evaluator    = "money_compare",
      assertion    = { subject = "game", property = "money", op_from_slot = "op", slot = "value" } },

    { id           = "cond_rush_hour",
      category     = "boolean",
      tags         = { "game" },
      color        = { 0.35, 0.65, 0.72 },
      label        = "rush hour",
      tooltip      = "True during an active rush hour event (increased trip generation and payout).",
      slots        = {},
      evaluator    = "rush_hour_active",
      max_per_rule = 1 },

    { id           = "cond_upgrade_purchased",
      category     = "boolean",
      tags         = { "game" },
      color        = { 0.35, 0.65, 0.72 },
      label        = "upgrade purchased",
      tooltip      = "True when the specified upgrade has been purchased. Cycle the slot to pick from your purchased upgrades.",
      slots        = { { key="name", type="upgrade_enum", default="auto_dispatch" } },
      evaluator    = "upgrade_purchased" },

-- ═══════════════════════════════════════════════════════════════════════════
-- BOOLEAN — conditions (logic / utility)
-- ═══════════════════════════════════════════════════════════════════════════

    { id           = "cond_random_chance",
      category     = "boolean",
      tags         = { "logic" },
      color        = { 0.82, 0.78, 0.15 },
      label        = "random chance",
      tooltip      = "True with the given probability each time the rule fires. 50 = 50% chance.",
      slots        = { { key="pct", type="number", default=50, step=5, min=1 } },
      evaluator    = "random_chance" },

    { id           = "cond_always_true",
      category     = "boolean",
      tags         = { "logic" },
      color        = { 0.82, 0.78, 0.15 },
      label        = "always true",
      tooltip      = "Always evaluates to true. Useful as a placeholder or to disable else-branches during testing.",
      slots        = {},
      evaluator    = "always_true" },

    { id           = "cond_always_false",
      category     = "boolean",
      tags         = { "logic" },
      color        = { 0.82, 0.78, 0.15 },
      label        = "always false",
      tooltip      = "Always evaluates to false. Useful to disable a branch without deleting it.",
      slots        = {},
      evaluator    = "always_false" },

-- ═══════════════════════════════════════════════════════════════════════════
-- BOOLEAN — conditions (counters & flags)
-- ═══════════════════════════════════════════════════════════════════════════

    { id           = "cond_counter",
      category     = "boolean",
      tags         = { "counter" },
      color        = { 0.55, 0.38, 0.80 },
      label        = "counter",
      tooltip      = "True when the named counter (A-E) satisfies the comparison. Counters persist across ticks and rules.",
      slots        = { VAR_SLOT, OP_CMP_SLOT, COUNT_VAL },
      evaluator    = "counter_compare",
      assertion    = { subject = "counter", property = "value", op_from_slot = "op", slot = "value", key_slot = "key" } },

    { id           = "cond_flag_set",
      category     = "boolean",
      tags         = { "counter", "logic" },
      color        = { 0.55, 0.38, 0.80 },
      label        = "flag set",
      tooltip      = "True when the named flag (X, Y, Z) has been set. Flags are persistent boolean markers you control with 'set flag' / 'clear flag'.",
      slots        = { VAR_SLOT },
      evaluator    = "flag_is_set",
      assertion    = { subject = "flag", property = "state", op = "set",   key_slot = "key" } },

    { id           = "cond_flag_clear",
      category     = "boolean",
      tags         = { "counter", "logic" },
      color        = { 0.55, 0.38, 0.80 },
      label        = "flag clear",
      tooltip      = "True when the named flag is NOT set.",
      slots        = { VAR_SLOT },
      evaluator    = "flag_is_clear",
      assertion    = { subject = "flag", property = "state", op = "clear", key_slot = "key" } },

    { id           = "cond_counter_mod",
      category     = "boolean",
      tags         = { "counter", "logic" },
      color        = { 0.55, 0.38, 0.80 },
      label        = "counter mod",
      tooltip      = "True when counter[A] mod M equals R. Use to trigger every Nth event (e.g. counter A mod 5 = 0 fires every 5 increments).",
      slots        = { VAR_SLOT, { key="m", type="number", default=2, step=1, min=1 }, { key="r", type="number", default=0, step=1, min=0 } },
      evaluator    = "counter_mod" },

-- ═══════════════════════════════════════════════════════════════════════════
-- BOOLEAN — conditions (per-vehicle context; require a vehicle event hat)
-- ═══════════════════════════════════════════════════════════════════════════

    { id           = "cond_this_vehicle_type",
      category     = "boolean",
      tags         = { "vehicle" },
      color        = { 0.28, 0.72, 0.58 },
      label        = "this vehicle is type",
      tooltip      = "True when the vehicle that fired this rule matches the chosen type.",
      slots        = { VEHICLE_SLOT },
      evaluator    = "this_vehicle_type" },

    { id           = "cond_this_vehicle_idle",
      category     = "boolean",
      tags         = { "vehicle" },
      color        = { 0.28, 0.72, 0.58 },
      label        = "this vehicle is idle",
      tooltip      = "True when the vehicle that fired this rule is currently idle at its depot.",
      slots        = {},
      evaluator    = "this_vehicle_idle" },

    { id           = "cond_this_vehicle_speed",
      category     = "boolean",
      tags         = { "vehicle" },
      color        = { 0.28, 0.72, 0.58 },
      label        = "this vehicle speed",
      tooltip      = "True when this vehicle's effective speed satisfies the comparison.",
      slots        = { OP_CMP_SLOT, { key="value", type="number", default=80, step=10, min=0 } },
      evaluator    = "this_vehicle_speed" },

    { id           = "cond_this_vehicle_trips",
      category     = "boolean",
      tags         = { "vehicle" },
      color        = { 0.28, 0.72, 0.58 },
      label        = "this vehicle trips completed",
      tooltip      = "True when this vehicle's total trips completed satisfies the comparison.",
      slots        = { OP_CMP_SLOT, { key="value", type="number", default=10, step=1, min=0 } },
      evaluator    = "this_vehicle_trips" },

-- ═══════════════════════════════════════════════════════════════════════════
-- STACK — effects (side-effect blocks; do NOT claim the trip)
-- ═══════════════════════════════════════════════════════════════════════════

-- ── Trip mutation ─────────────────────────────────────────────────────────

    { id           = "effect_set_payout",
      category     = "stack",
      tags         = { "trip" },
      color        = { 0.28, 0.45, 0.88 },
      label        = "set payout to",
      tooltip      = "Side-effect: overrides this trip's base payout to the given value.",
      slots        = { { key="value", type="number", default=100, step=50, min=0 } },
      evaluator    = "set_payout" },

    { id           = "effect_add_bonus",
      category     = "stack",
      tags         = { "trip" },
      color        = { 0.28, 0.45, 0.88 },
      label        = "add bonus",
      tooltip      = "Side-effect: adds to this trip's speed bonus (the extra payout for fast delivery).",
      slots        = { { key="value", type="number", default=50, step=10, min=0 } },
      evaluator    = "add_bonus" },

-- ── Economy ───────────────────────────────────────────────────────────────

    { id           = "effect_add_money",
      category     = "stack",
      tags         = { "game" },
      color        = { 0.85, 0.40, 0.20 },
      label        = "add money",
      tooltip      = "Side-effect: adds money directly to your balance.",
      slots        = { { key="amount", type="number", default=100, step=100, min=0 } },
      evaluator    = "add_money" },

    { id           = "effect_subtract_money",
      category     = "stack",
      tags         = { "game" },
      color        = { 0.85, 0.40, 0.20 },
      label        = "subtract money",
      tooltip      = "Side-effect: removes money from your balance (minimum 0).",
      slots        = { { key="amount", type="number", default=100, step=100, min=0 } },
      evaluator    = "subtract_money" },

    { id           = "effect_trigger_rush_hour",
      category     = "stack",
      tags         = { "game" },
      color        = { 0.85, 0.40, 0.20 },
      label        = "trigger rush hour",
      tooltip      = "Side-effect: starts a rush hour event lasting N seconds.",
      slots        = { { key="seconds", type="number", default=30, step=5, min=5 } },
      evaluator    = "trigger_rush_hour" },

    { id           = "effect_end_rush_hour",
      category     = "stack",
      tags         = { "game" },
      color        = { 0.85, 0.40, 0.20 },
      label        = "end rush hour",
      tooltip      = "Side-effect: immediately ends any active rush hour.",
      slots        = {},
      evaluator    = "end_rush_hour" },

    { id           = "effect_pause_trip_gen",
      category     = "stack",
      tags         = { "game" },
      color        = { 0.85, 0.40, 0.20 },
      label        = "pause trip gen",
      tooltip      = "Side-effect: stops new trips from being generated until resumed.",
      slots        = {},
      evaluator    = "pause_trip_gen" },

    { id           = "effect_resume_trip_gen",
      category     = "stack",
      tags         = { "game" },
      color        = { 0.85, 0.40, 0.20 },
      label        = "resume trip gen",
      tooltip      = "Side-effect: re-enables trip generation if it was paused.",
      slots        = {},
      evaluator    = "resume_trip_gen" },

    { id           = "effect_set_trip_gen_rate",
      category     = "stack",
      tags         = { "game" },
      color        = { 0.85, 0.40, 0.20 },
      label        = "set trip gen rate",
      tooltip      = "Side-effect: sets the trip generation multiplier. 100 = normal rate, 200 = double, 50 = half.",
      slots        = { { key="pct", type="number", default=100, step=10, min=10 } },
      evaluator    = "set_trip_gen_rate" },

    { id           = "effect_counter_change",
      category     = "stack",
      tags         = { "counter" },
      color        = { 0.52, 0.28, 0.80 },
      label        = "counter",
      tooltip      = "Side-effect: adds or subtracts a fixed amount from the named counter. Does not claim the trip — execution continues.",
      slots        = { VAR_SLOT, OP_DELTA_SLOT, AMOUNT_SLOT },
      evaluator    = "counter_change" },

    { id           = "effect_counter_reset",
      category     = "stack",
      tags         = { "counter" },
      color        = { 0.52, 0.28, 0.80 },
      label        = "reset counter",
      tooltip      = "Side-effect: sets the named counter back to zero.",
      slots        = { VAR_SLOT },
      evaluator    = "counter_reset" },

    { id           = "effect_flag_set",
      category     = "stack",
      tags         = { "counter" },
      color        = { 0.52, 0.28, 0.80 },
      label        = "set flag",
      tooltip      = "Side-effect: marks the named flag as set. Use with 'flag set' conditions in other rules to coordinate behaviour.",
      slots        = { VAR_SLOT },
      evaluator    = "flag_set" },

    { id           = "effect_flag_clear",
      category     = "stack",
      tags         = { "counter" },
      color        = { 0.52, 0.28, 0.80 },
      label        = "clear flag",
      tooltip      = "Side-effect: clears the named flag (sets it to false).",
      slots        = { VAR_SLOT },
      evaluator    = "flag_clear" },

    { id           = "effect_set_counter",
      category     = "stack",
      tags         = { "counter" },
      color        = { 0.52, 0.28, 0.80 },
      label        = "set counter",
      tooltip      = "Side-effect: sets a counter to an absolute value (unlike 'counter +=/-=' which adds/subtracts).",
      slots        = { VAR_SLOT, { key="value", type="number", default=0, step=1, min=0 } },
      evaluator    = "set_counter" },

    { id           = "effect_reset_all_counters",
      category     = "stack",
      tags         = { "counter" },
      color        = { 0.52, 0.28, 0.80 },
      label        = "reset all counters",
      tooltip      = "Side-effect: sets all counters (A through E) back to zero at once.",
      slots        = {},
      evaluator    = "reset_all_counters" },

    { id           = "effect_toggle_flag",
      category     = "stack",
      tags         = { "counter" },
      color        = { 0.52, 0.28, 0.80 },
      label        = "toggle flag",
      tooltip      = "Side-effect: flips a flag — set becomes clear, clear becomes set.",
      slots        = { VAR_SLOT },
      evaluator    = "toggle_flag" },

    { id           = "effect_swap_counters",
      category     = "stack",
      tags         = { "counter" },
      color        = { 0.52, 0.28, 0.80 },
      label        = "swap counters",
      tooltip      = "Side-effect: exchanges the values of two counters.",
      slots        = { { key="a", type="enum", options={ "A","B","C","D","E" }, default="A" },
                       { key="b", type="enum", options={ "A","B","C","D","E" }, default="B" } },
      evaluator    = "swap_counters" },

-- ═══════════════════════════════════════════════════════════════════════════
-- STACK — queue manipulation (non-terminal; reorder/bulk-cancel pending)
-- ═══════════════════════════════════════════════════════════════════════════

    { id           = "action_prioritize",
      category     = "stack",
      tags         = { "trip" },
      color        = { 0.28, 0.45, 0.88 },
      label        = "prioritize trip",
      tooltip      = "Moves this trip to the front of the pending queue so it is evaluated first next tick.",
      slots        = {},
      evaluator    = "prioritize_trip" },

    { id           = "action_deprioritize",
      category     = "stack",
      tags         = { "trip" },
      color        = { 0.28, 0.45, 0.88 },
      label        = "deprioritize trip",
      tooltip      = "Moves this trip to the back of the pending queue so it is evaluated last.",
      slots        = {},
      evaluator    = "deprioritize_trip" },

    { id           = "action_sort_queue",
      category     = "stack",
      tags         = { "trip", "game" },
      color        = { 0.28, 0.45, 0.88 },
      label        = "sort queue by",
      tooltip      = "Sorts the entire pending trip queue by the chosen field. payout=highest first, wait=longest waiting first, scope=smallest first, cargo=largest first.",
      slots        = { { key="field", type="enum", options={"payout","wait","scope","cargo"}, default="payout" } },
      evaluator    = "sort_queue" },

    { id           = "action_cancel_all_scope",
      category     = "stack",
      tags         = { "trip", "game" },
      color        = { 0.62, 0.18, 0.18 },
      label        = "cancel all scope",
      tooltip      = "Cancels every pending trip with the matching scope (including this one if it matches). Useful for bulk purge on overload.",
      slots        = { SCOPE_SLOT },
      evaluator    = "cancel_all_scope",
      terminal     = true },

    { id           = "action_cancel_all_wait",
      category     = "stack",
      tags         = { "trip", "game" },
      color        = { 0.62, 0.18, 0.18 },
      label        = "cancel all waited",
      tooltip      = "Cancels every pending trip whose wait time satisfies the comparison (e.g. waited > 120s). Clears stale trips automatically.",
      slots        = { OP_CMP_SLOT, SECONDS_SLOT },
      evaluator    = "cancel_all_wait",
      terminal     = true },

-- ═══════════════════════════════════════════════════════════════════════════
-- LEGACY — hidden from main palette
-- ═══════════════════════════════════════════════════════════════════════════

    { id             = "action_assign_fastest",
      category       = "legacy",
      tags           = { "trip", "vehicle" },
      color          = { 0.28, 0.45, 0.88 },
      label          = "assign fastest",
      tooltip        = "Action: assigns the trip to the fastest eligible vehicle of the chosen type (highest speed stat).",
      slots          = { VEHICLE_SLOT },
      evaluator      = "assign_fastest",
      vehicle_slot_key = "vehicle_type",
      constraint     = "vehicle_covers_trip_scope" },

    { id             = "action_assign_most_capacity",
      category       = "legacy",
      tags           = { "trip", "vehicle" },
      color          = { 0.28, 0.45, 0.88 },
      label          = "assign most capacity",
      tooltip        = "Action: assigns the trip to the eligible vehicle with the most remaining cargo capacity.",
      slots          = { VEHICLE_SLOT },
      evaluator      = "assign_most_capacity",
      vehicle_slot_key = "vehicle_type",
      constraint     = "vehicle_covers_trip_scope" },

    { id             = "action_assign_least_recent",
      category       = "legacy",
      tags           = { "trip", "vehicle" },
      color          = { 0.28, 0.45, 0.88 },
      label          = "assign least recent",
      tooltip        = "Action: assigns the trip to the eligible vehicle that has been idle the longest (round-robin fairness).",
      slots          = { VEHICLE_SLOT },
      evaluator      = "assign_least_recent",
      vehicle_slot_key = "vehicle_type",
      constraint     = "vehicle_covers_trip_scope" },

    { id             = "action_assign_nearest",
      category       = "legacy",
      tags           = { "trip", "vehicle" },
      color          = { 0.28, 0.45, 0.88 },
      label          = "nearest",
      tooltip        = "Action: assigns the trip to the nearest eligible idle vehicle of the chosen type (by travel distance).",
      slots          = { VEHICLE_SLOT },
      evaluator      = "assign_nearest",
      vehicle_slot_key = "vehicle_type",
      constraint     = "vehicle_covers_trip_scope" },

-- ═══════════════════════════════════════════════════════════════════════════
-- STACK — flow control
-- ═══════════════════════════════════════════════════════════════════════════

    { id           = "action_stop_rule",
      category     = "stack",
      tags         = { "logic" },
      color        = { 0.40, 0.40, 0.45 },
      label        = "stop this rule",
      tooltip      = "Stops executing this rule immediately. The trip is not claimed or skipped — the next rule will still fire.",
      slots        = {},
      evaluator    = "stop_rule" },

    { id           = "action_stop_all",
      category     = "stack",
      tags         = { "logic" },
      color        = { 0.40, 0.40, 0.45 },
      label        = "stop all rules",
      tooltip      = "Stops all rule evaluation for this trip this tick. No further rules will fire. The trip stays pending.",
      slots        = {},
      evaluator    = "stop_all" },

-- ═══════════════════════════════════════════════════════════════════════════
-- STACK — actions (terminal blocks)
-- ═══════════════════════════════════════════════════════════════════════════

    { id             = "action_assign_type",
      category       = "stack",
      tags           = { "trip", "vehicle" },
      color          = { 0.28, 0.45, 0.88 },
      label          = "assign to",
      tooltip        = "Action: assigns the trip to an idle vehicle of the chosen type. The rule stops if a vehicle is found.",
      slots          = { VEHICLE_SLOT },
      evaluator      = "assign_vehicle_type",
      vehicle_slot_key = "vehicle_type",
      constraint     = "vehicle_covers_trip_scope" },

    { id             = "action_assign_any",
      category       = "stack",
      tags           = { "trip", "vehicle" },
      color          = { 0.28, 0.45, 0.88 },
      label          = "assign to any",
      tooltip        = "Action: assigns the trip to any eligible idle vehicle regardless of type.",
      slots          = {},
      evaluator      = "assign_any" },

    { id             = "action_assign_nearest",
      category       = "stack",
      tags           = { "trip", "vehicle" },
      color          = { 0.28, 0.45, 0.88 },
      label          = "nearest",
      tooltip        = "Action: assigns the trip to the nearest eligible idle vehicle of the chosen type (by travel distance).",
      slots          = { VEHICLE_SLOT },
      evaluator      = "assign_nearest",
      vehicle_slot_key = "vehicle_type",
      constraint     = "vehicle_covers_trip_scope" },

    { id             = "action_cancel",
      category       = "stack",
      tags           = { "trip" },
      color          = { 0.62, 0.18, 0.18 },
      label          = "cancel trip",
      tooltip        = "Action: removes the trip from the queue without assigning it. Use to drop low-value or undesired trips.",
      slots          = {},
      evaluator      = "cancel_trip",
      terminal       = true,
      max_per_rule   = 1 },

    { id             = "action_skip",
      category       = "stack",
      tags           = { "trip" },
      color          = { 0.72, 0.22, 0.22 },
      label          = "skip (hold)",
      tooltip        = "Action: holds the trip in the pending queue for this tick without assigning it. It will be re-evaluated next tick.",
      slots          = {},
      evaluator      = "skip",
      terminal       = true,
      max_per_rule   = 1 },

-- ═══════════════════════════════════════════════════════════════════════════
-- STACK — per-vehicle actions (require a vehicle event hat)
-- ═══════════════════════════════════════════════════════════════════════════

    { id           = "action_unassign_vehicle",
      category     = "stack",
      tags         = { "vehicle", "trip" },
      color        = { 0.28, 0.45, 0.88 },
      label        = "unassign this vehicle",
      tooltip      = "Returns all of this vehicle's queued trips back to the pending queue.",
      slots        = {},
      evaluator    = "unassign_vehicle" },

    { id           = "action_send_to_depot",
      category     = "stack",
      tags         = { "vehicle" },
      color        = { 0.28, 0.45, 0.88 },
      label        = "send to depot",
      tooltip      = "Orders this vehicle to return to its assigned depot immediately.",
      slots        = {},
      evaluator    = "send_to_depot" },

    { id           = "action_set_speed_mult",
      category     = "stack",
      tags         = { "vehicle" },
      color        = { 0.28, 0.45, 0.88 },
      label        = "set speed multiplier",
      tooltip      = "Sets this vehicle's speed modifier. 100 = normal, 200 = double, 50 = half.",
      slots        = { { key="value", type="number", default=100, step=10, min=10 } },
      evaluator    = "set_speed_mult" },

    { id           = "action_fire_vehicle",
      category     = "stack",
      tags         = { "vehicle" },
      color        = { 0.28, 0.45, 0.88 },
      label        = "fire this vehicle",
      tooltip      = "Removes this vehicle from the fleet, returning any assigned trips to the queue.",
      slots        = {},
      evaluator    = "fire_vehicle" },

-- ═══════════════════════════════════════════════════════════════════════════
-- BOOLEAN — conditions (text variables)
-- ═══════════════════════════════════════════════════════════════════════════

    { id           = "cond_text_var_eq",
      category     = "boolean",
      tags         = { "logic" },
      color        = { 0.82, 0.78, 0.15 },
      label        = "text var =",
      tooltip      = "True when the named text variable exactly matches the given string.",
      slots        = { { key="key",   type="text_var_enum", default="A" },
                       { key="value", type="string",        default="" } },
      evaluator    = "text_var_eq" },

    { id           = "cond_text_var_contains",
      category     = "boolean",
      tags         = { "logic" },
      color        = { 0.82, 0.78, 0.15 },
      label        = "text var contains",
      tooltip      = "True when the named text variable contains the given substring.",
      slots        = { { key="key",   type="text_var_enum", default="A" },
                       { key="value", type="string",        default="" } },
      evaluator    = "text_var_contains" },

-- ═══════════════════════════════════════════════════════════════════════════
-- STACK — effects (text variables)
-- ═══════════════════════════════════════════════════════════════════════════

    { id           = "effect_set_text_var",
      category     = "stack",
      tags         = { "logic" },
      color        = { 0.82, 0.78, 0.15 },
      label        = "set text var",
      tooltip      = "Sets the named text variable to the given string (overwrites previous value).",
      slots        = { { key="key",   type="text_var_enum", default="A" },
                       { key="value", type="string",        default="" } },
      evaluator    = "set_text_var" },

    { id           = "effect_append_text_var",
      category     = "stack",
      tags         = { "logic" },
      color        = { 0.82, 0.78, 0.15 },
      label        = "append to text var",
      tooltip      = "Appends the given string to the end of the named text variable.",
      slots        = { { key="key",   type="text_var_enum", default="A" },
                       { key="value", type="string",        default="" } },
      evaluator    = "append_text_var" },

    { id           = "effect_clear_text_var",
      category     = "stack",
      tags         = { "logic" },
      color        = { 0.82, 0.78, 0.15 },
      label        = "clear text var",
      tooltip      = "Clears the named text variable back to an empty string.",
      slots        = { { key="key", type="text_var_enum", default="A" } },
      evaluator    = "clear_text_var" },

-- ═══════════════════════════════════════════════════════════════════════════
-- BROADCAST — hat + effect
-- ═══════════════════════════════════════════════════════════════════════════

    { id           = "hat_broadcast_received",
      category     = "hat",
      event_type   = "broadcast",
      tags         = { "trigger", "logic" },
      color        = { 0.50, 0.30, 0.75 },
      label        = "when broadcast received",
      tooltip      = "Fires when another rule broadcasts the matching message name this tick.",
      slots        = { { key="name", type="string", default="event" } },
      must_be_first = true, max_per_rule = 1 },

    { id           = "effect_broadcast",
      category     = "stack",
      tags         = { "logic" },
      color        = { 0.50, 0.30, 0.75 },
      label        = "broadcast",
      tooltip      = "Sends a named message. Rules with 'when broadcast received' listening for this name will fire after all other rules this tick.",
      slots        = { { key="name", type="string", default="event" } },
      evaluator    = "broadcast_message" },

-- ═══════════════════════════════════════════════════════════════════════════
-- BOOLEAN — reporter comparison
-- ═══════════════════════════════════════════════════════════════════════════

    { id           = "bool_compare",
      category     = "boolean",
      tags         = { "logic" },
      color        = { 0.82, 0.78, 0.15 },
      label        = "Compare",
      tooltip      = "True when the left reporter value compares to the right reporter value. Drop reporter blocks (like 'Get') into the left/right slots.",
      evaluator    = "bool_compare",
      slots        = {
          { key="left",  type="reporter", default=0 },
          { key="op",    type="enum", options={ ">", "<", ">=", "<=", "!=", "=" }, default=">" },
          { key="right", type="reporter", default=0 },
      } },
-- ═══════════════════════════════════════════════════════════════════════════
-- REPORTER — core primitives (Phase 2)
-- ═══════════════════════════════════════════════════════════════════════════

    -- All property keys available for rep_get_property, grouped by source:
    --   trip:    payout  wait_time  bonus  leg_count  scope  cargo_size
    --   vehicle: speed   trips_completed  type
    --   game:    money   queue_count  trips_completed  rh_timer
    --   fleet:   count   idle_count  utilization

    { id           = "rep_get_property",
      category     = "reporter",
      tags         = { "trip", "vehicle", "game", "logic" },
      color        = { 0.30, 0.72, 0.62 },
      label        = "Get",
      tooltip      = "Returns a property from any entity. Pick a source, then pick a property. Some properties may require additional parameters.",
      evaluator    = "rep_get_property",
      slots        = {
          { key="source",       type="enum", options = "dynamic" },
          { key="property",     type="enum", options = "dynamic" },
      } },

    { id           = "rep_get_var",
      category     = "reporter",
      tags         = { "counter", "logic" },
      color        = { 0.55, 0.38, 0.80 },
      label        = "Var",
      tooltip      = "Returns the value of a named variable. Works with numeric counters, boolean flags, and text vars. Replaces the legacy counter/flag/text-var reporters.",
      evaluator    = "rep_get_var",
      slots        = {
          { key="key", type="string", default="my_var" },
      } },

-- ═══════════════════════════════════════════════════════════════════════════
-- REPORTER — legacy (replaced by rep_get_property / rep_get_var)
-- These blocks are hidden from the main palette. Toggle "Show Legacy" to see them.
-- Evaluator functions are unchanged — existing rules continue to work.
-- ═══════════════════════════════════════════════════════════════════════════

    { id           = "rep_money",
      category     = "legacy",
      tags         = { "game" },
      color        = { 0.30, 0.72, 0.62 },
      label        = "money",
      tooltip      = "LEGACY — use Get(game, money) instead. Returns your current money balance.",
      slots        = {},
      evaluator    = "rep_money" },

    { id           = "rep_queue_count",
      category     = "legacy",
      tags         = { "game" },
      color        = { 0.30, 0.72, 0.62 },
      label        = "queue size",
      tooltip      = "LEGACY — use Get(game, queue_count) instead. Returns the number of pending trips.",
      slots        = {},
      evaluator    = "rep_queue_count" },

    { id           = "rep_trips_completed",
      category     = "legacy",
      tags         = { "game" },
      color        = { 0.30, 0.72, 0.62 },
      label        = "trips completed",
      tooltip      = "LEGACY — use Get(game, trips_completed) instead. Returns total trips delivered.",
      slots        = {},
      evaluator    = "rep_trips_completed" },

    { id           = "rep_rush_hour_remaining",
      category     = "legacy",
      tags         = { "game" },
      color        = { 0.85, 0.40, 0.20 },
      label        = "rush hour remaining",
      tooltip      = "LEGACY — use Get(game, rh_timer) instead. Returns remaining rush hour seconds.",
      slots        = {},
      evaluator    = "rep_rush_hour_remaining" },

    { id           = "rep_counter",
      category     = "legacy",
      tags         = { "counter" },
      color        = { 0.55, 0.38, 0.80 },
      label        = "counter",
      tooltip      = "LEGACY — use Var instead. Returns the value of the named counter.",
      slots        = { VAR_SLOT },
      evaluator    = "rep_counter" },

    { id           = "rep_flag",
      category     = "legacy",
      tags         = { "counter" },
      color        = { 0.55, 0.38, 0.80 },
      label        = "flag as number",
      tooltip      = "LEGACY — use Var instead. Returns 1 if the named flag is set, 0 if clear.",
      slots        = { VAR_SLOT },
      evaluator    = "rep_flag" },

    { id           = "rep_text_var",
      category     = "legacy",
      tags         = { "logic" },
      color        = { 0.82, 0.78, 0.15 },
      label        = "text var",
      tooltip      = "LEGACY — use Var instead. Returns the current value of the named text variable.",
      slots        = { TEXT_VAR_SLOT },
      evaluator    = "rep_text_var" },

    { id           = "rep_vehicle_count",
      category     = "legacy",
      tags         = { "vehicle" },
      color        = { 0.20, 0.65, 0.45 },
      label        = "vehicle count",
      tooltip      = "LEGACY — use Get(fleet, count) instead. Returns total vehicles of chosen type.",
      slots        = { VEHICLE_SLOT },
      evaluator    = "rep_vehicle_count" },

    { id           = "rep_idle_count",
      category     = "legacy",
      tags         = { "vehicle" },
      color        = { 0.20, 0.65, 0.45 },
      label        = "idle count",
      tooltip      = "LEGACY — use Get(fleet, idle_count) instead. Returns idle vehicles of chosen type.",
      slots        = { VEHICLE_SLOT },
      evaluator    = "rep_idle_count" },

    { id           = "rep_trip_payout",
      category     = "legacy",
      tags         = { "trip" },
      color        = { 0.22, 0.68, 0.32 },
      label        = "trip payout",
      tooltip      = "LEGACY — use Get(trip, payout) instead. Returns the base payout of the current trip.",
      slots        = {},
      evaluator    = "rep_trip_payout" },

    { id           = "rep_trip_wait",
      category     = "legacy",
      tags         = { "trip" },
      color        = { 0.22, 0.68, 0.32 },
      label        = "trip wait time",
      tooltip      = "LEGACY — use Get(trip, wait_time) instead. Returns how long the trip has waited.",
      slots        = {},
      evaluator    = "rep_trip_wait" },

    { id           = "rep_trip_bonus",
      category     = "legacy",
      tags         = { "trip" },
      color        = { 0.22, 0.68, 0.32 },
      label        = "trip bonus",
      tooltip      = "LEGACY — use Get(trip, bonus) instead. Returns the current speed bonus on this trip.",
      slots        = {},
      evaluator    = "rep_trip_bonus" },

    { id           = "rep_trip_leg_count",
      category     = "legacy",
      tags         = { "trip" },
      color        = { 0.22, 0.68, 0.32 },
      label        = "trip legs",
      tooltip      = "LEGACY — use Get(trip, leg_count) instead. Returns the number of legs in this trip.",
      slots        = {},
      evaluator    = "rep_trip_leg_count" },

    { id           = "rep_this_vehicle_speed",
      category     = "legacy",
      tags         = { "vehicle" },
      color        = { 0.20, 0.65, 0.45 },
      label        = "this vehicle speed",
      tooltip      = "LEGACY — use Get(vehicle, speed) instead. Returns this vehicle's effective speed.",
      slots        = {},
      evaluator    = "rep_this_vehicle_speed" },

    { id           = "rep_this_vehicle_trips",
      category     = "legacy",
      tags         = { "vehicle" },
      color        = { 0.20, 0.65, 0.45 },
      label        = "this vehicle trips",
      tooltip      = "LEGACY — use Get(vehicle, trips_completed) instead. Returns trips completed by this vehicle.",
      slots        = {},
      evaluator    = "rep_this_vehicle_trips" },

-- ═══════════════════════════════════════════════════════════════════════════
-- REPORTER — math operators
-- ═══════════════════════════════════════════════════════════════════════════

    { id="rep_add", category="reporter", tags={"logic"}, color={0.42,0.55,0.90},
      label="+", tooltip="Returns a + b.", slots={REP_A, REP_B}, evaluator="rep_add" },

    { id="rep_sub", category="reporter", tags={"logic"}, color={0.42,0.55,0.90},
      label="-", tooltip="Returns a - b.", slots={REP_A, REP_B}, evaluator="rep_sub" },

    { id="rep_mul", category="reporter", tags={"logic"}, color={0.42,0.55,0.90},
      label="×", tooltip="Returns a × b.", slots={REP_A, REP_B}, evaluator="rep_mul" },

    { id="rep_div", category="reporter", tags={"logic"}, color={0.42,0.55,0.90},
      label="÷", tooltip="Returns a ÷ b (0 if b is zero).", slots={REP_A, REP_B}, evaluator="rep_div" },

    { id="rep_mod", category="reporter", tags={"logic"}, color={0.42,0.55,0.90},
      label="mod", tooltip="Returns a mod b.", slots={REP_A, REP_B}, evaluator="rep_mod" },

    { id="rep_round", category="reporter", tags={"logic"}, color={0.42,0.55,0.90},
      label="round", tooltip="Returns a rounded to the nearest integer.",
      slots={ { key="a", type="number", default=0, step=1 } }, evaluator="rep_round" },

    { id="rep_abs", category="reporter", tags={"logic"}, color={0.42,0.55,0.90},
      label="abs", tooltip="Returns the absolute value of a.",
      slots={ { key="a", type="number", default=0, step=1 } }, evaluator="rep_abs" },

    { id="rep_min", category="reporter", tags={"logic"}, color={0.42,0.55,0.90},
      label="min", tooltip="Returns the smaller of a and b.", slots={REP_A, REP_B}, evaluator="rep_min" },

    { id="rep_max", category="reporter", tags={"logic"}, color={0.42,0.55,0.90},
      label="max", tooltip="Returns the larger of a and b.", slots={REP_A, REP_B}, evaluator="rep_max" },

    { id="rep_random", category="reporter", tags={"logic"}, color={0.42,0.55,0.90},
      label="random between",
      tooltip="Returns a random integer between a and b (inclusive).",
      slots={ { key="a", type="number", default=1, step=1, min=1 },
              { key="b", type="number", default=10, step=1, min=1 } },
      evaluator="rep_random" },

-- ═══════════════════════════════════════════════════════════════════════════
-- REPORTER — string operators
-- ═══════════════════════════════════════════════════════════════════════════

    { id="rep_join", category="reporter", tags={"logic"}, color={0.65,0.42,0.88},
      label="join", tooltip="Joins two strings together.",
      slots={ { key="a", type="string", default="" }, { key="b", type="string", default="" } },
      evaluator="rep_join" },

    { id="rep_length", category="reporter", tags={"logic"}, color={0.65,0.42,0.88},
      label="length of",
      tooltip="Returns the character count of a string.",
      slots={ { key="a", type="string", default="" } }, evaluator="rep_length" },

    { id="rep_num_to_text", category="reporter", tags={"logic"}, color={0.65,0.42,0.88},
      label="number to text",
      tooltip="Converts a number to its text representation.",
      slots={ { key="a", type="number", default=0, step=1 } }, evaluator="rep_num_to_text" },

    { id="rep_text_to_num", category="reporter", tags={"logic"}, color={0.65,0.42,0.88},
      label="text to number",
      tooltip="Parses a string as a number (0 if not parseable).",
      slots={ { key="a", type="string", default="" } }, evaluator="rep_text_to_num" },

    { id="rep_upper", category="reporter", tags={"logic"}, color={0.65,0.42,0.88},
      label="uppercase",
      tooltip="Converts a string to all uppercase letters.",
      slots={ { key="a", type="string", default="" } }, evaluator="rep_upper" },

    { id="rep_lower", category="reporter", tags={"logic"}, color={0.65,0.42,0.88},
      label="lowercase",
      tooltip="Converts a string to all lowercase letters.",
      slots={ { key="a", type="string", default="" } }, evaluator="rep_lower" },

-- ═══════════════════════════════════════════════════════════════════════════
-- LOOP — C-block loops (category = "loop")
-- ═══════════════════════════════════════════════════════════════════════════

    { id           = "ctrl_repeat_n",
      category     = "loop",
      tags         = { "logic" },
      color        = { 0.20, 0.55, 0.75 },
      label        = "repeat",
      tooltip      = "Runs the inner stack N times (maximum 100). Use 'break' to exit early.",
      slots        = { { key="n", type="number", default=3, step=1, min=1 } } },

    { id           = "ctrl_repeat_until",
      category     = "loop",
      tags         = { "logic" },
      color        = { 0.20, 0.55, 0.75 },
      label        = "repeat until",
      tooltip      = "Repeats the inner stack until the condition becomes true (safety cap: 100 iterations). Drop a condition block into the slot.",
      slots        = {} },

    { id           = "ctrl_for_each_vehicle",
      category     = "loop",
      tags         = { "logic", "vehicle" },
      color        = { 0.20, 0.55, 0.75 },
      label        = "for each vehicle",
      tooltip      = "Runs the inner stack once for each vehicle of the chosen type. Use 'this vehicle' blocks inside to act on each vehicle.",
      slots        = { VEHICLE_SLOT } },

    { id           = "ctrl_for_each_trip",
      category     = "loop",
      tags         = { "logic", "trip" },
      color        = { 0.20, 0.55, 0.75 },
      label        = "for each pending trip",
      tooltip      = "Runs the inner stack once for each trip in the pending queue. Trip blocks inside act on the iterated trip.",
      slots        = {} },

    { id           = "action_break",
      category     = "stack",
      tags         = { "logic" },
      color        = { 0.40, 0.40, 0.45 },
      label        = "break",
      tooltip      = "Exits the current repeat/for-each loop immediately. Has no effect outside a loop.",
      slots        = {},
      evaluator    = "action_break" },

    { id           = "action_continue",
      category     = "stack",
      tags         = { "logic" },
      color        = { 0.40, 0.40, 0.45 },
      label        = "continue",
      tooltip      = "Skips the remaining blocks in this loop iteration and moves to the next. Has no effect outside a loop.",
      slots        = {},
      evaluator    = "action_continue" },

-- ═══════════════════════════════════════════════════════════════════════════
-- STACK — Visual / Looks (require vehicle context)
-- ═══════════════════════════════════════════════════════════════════════════

    { id           = "action_set_vehicle_color",
      category     = "stack",
      tags         = { "vehicle" },
      color        = { 0.65, 0.30, 0.75 },
      label        = "set vehicle color",
      tooltip      = "Draws a tinted disc behind the vehicle icon to make it visually distinct. Values are 0–1 RGB.",
      slots        = { { key="r", type="number", default=1.0, step=0.1, min=0 },
                       { key="g", type="number", default=0.5, step=0.1, min=0 },
                       { key="b", type="number", default=0.1, step=0.1, min=0 } },
      evaluator    = "set_vehicle_color" },

    { id           = "action_reset_vehicle_color",
      category     = "stack",
      tags         = { "vehicle" },
      color        = { 0.65, 0.30, 0.75 },
      label        = "reset vehicle color",
      tooltip      = "Removes the custom color override, restoring the vehicle to its default appearance.",
      slots        = {},
      evaluator    = "reset_vehicle_color" },

    { id           = "action_set_vehicle_icon",
      category     = "stack",
      tags         = { "vehicle" },
      color        = { 0.65, 0.30, 0.75 },
      label        = "set vehicle icon",
      tooltip      = "Overrides the emoji icon displayed for this vehicle.",
      slots        = { { key="icon", type="string", default="🚀" } },
      evaluator    = "set_vehicle_icon" },

    { id           = "action_show_speech_bubble",
      category     = "stack",
      tags         = { "vehicle" },
      color        = { 0.65, 0.30, 0.75 },
      label        = "show speech bubble",
      tooltip      = "Displays a text bubble above this vehicle for the given number of seconds.",
      slots        = { { key="text",    type="string", default="Hello!" },
                       { key="seconds", type="number", default=3, step=1, min=1 } },
      evaluator    = "show_speech_bubble" },

    { id           = "action_flash_vehicle",
      category     = "stack",
      tags         = { "vehicle" },
      color        = { 0.65, 0.30, 0.75 },
      label        = "flash vehicle",
      tooltip      = "Briefly flashes the vehicle yellow for the given number of seconds.",
      slots        = { { key="seconds", type="number", default=1, step=0.5, min=0.5 } },
      evaluator    = "flash_vehicle" },

    { id           = "action_show_label",
      category     = "stack",
      tags         = { "vehicle" },
      color        = { 0.65, 0.30, 0.75 },
      label        = "show label",
      tooltip      = "Shows a persistent text label above this vehicle until 'hide label' is called.",
      slots        = { { key="text", type="string", default="VIP" } },
      evaluator    = "show_vehicle_label" },

    { id           = "action_hide_label",
      category     = "stack",
      tags         = { "vehicle" },
      color        = { 0.65, 0.30, 0.75 },
      label        = "hide label",
      tooltip      = "Removes the persistent label from this vehicle.",
      slots        = {},
      evaluator    = "hide_vehicle_label" },

    { id           = "action_show_vehicle",
      category     = "stack",
      tags         = { "vehicle" },
      color        = { 0.65, 0.30, 0.75 },
      label        = "show vehicle",
      tooltip      = "Makes this vehicle visible on the map (reverses 'hide vehicle').",
      slots        = {},
      evaluator    = "show_vehicle" },

    { id           = "action_hide_vehicle",
      category     = "stack",
      tags         = { "vehicle" },
      color        = { 0.65, 0.30, 0.75 },
      label        = "hide vehicle",
      tooltip      = "Hides this vehicle from the map. It continues to move and deliver — it is just invisible.",
      slots        = {},
      evaluator    = "hide_vehicle" },

    { id           = "action_zoom_to_vehicle",
      category     = "stack",
      tags         = { "vehicle" },
      color        = { 0.65, 0.30, 0.75 },
      label        = "pan camera to vehicle",
      tooltip      = "Pans the camera so this vehicle is centred on screen.",
      slots        = {},
      evaluator    = "zoom_to_vehicle" },

    { id           = "action_pan_to_depot",
      category     = "stack",
      tags         = { "vehicle" },
      color        = { 0.65, 0.30, 0.75 },
      label        = "pan camera to depot",
      tooltip      = "Pans the camera to this vehicle's home depot.",
      slots        = {},
      evaluator    = "pan_to_depot" },

    { id           = "action_set_zoom",
      category     = "stack",
      tags         = { "game" },
      color        = { 0.65, 0.30, 0.75 },
      label        = "set zoom",
      tooltip      = "Sets the camera zoom scale directly. Higher = more zoomed in.",
      slots        = { { key="scale", type="number", default=2, step=0.5, min=0.1 } },
      evaluator    = "set_zoom" },

    { id           = "action_shake_screen",
      category     = "stack",
      tags         = { "game" },
      color        = { 0.65, 0.30, 0.75 },
      label        = "shake screen",
      tooltip      = "Shakes the screen for the given duration with the given intensity (pixels).",
      slots        = { { key="seconds",   type="number", default=0.5, step=0.25, min=0.1 },
                       { key="magnitude", type="number", default=8,   step=2,    min=1   } },
      evaluator    = "shake_screen" },

    -- ── Sound ─────────────────────────────────────────────────────────────────

    { id           = "action_play_sound",
      category     = "stack",
      tags         = { "sound" },
      color        = { 0.75, 0.30, 0.65 },
      label        = "play sound",
      tooltip      = "Plays one of the built-in programmatic sounds.",
      slots        = { { key="sound", type="sound_enum", default="beep" } },
      evaluator    = "play_sound" },

    { id           = "action_stop_all_sounds",
      category     = "stack",
      tags         = { "sound" },
      color        = { 0.75, 0.30, 0.65 },
      label        = "stop all sounds",
      tooltip      = "Stops all currently playing sounds.",
      slots        = {},
      evaluator    = "stop_all_sounds" },

    { id           = "action_set_volume",
      category     = "stack",
      tags         = { "sound" },
      color        = { 0.75, 0.30, 0.65 },
      label        = "set volume",
      tooltip      = "Sets master volume (0–100).",
      slots        = { { key="value", type="number", default=80, step=10, min=0, max=100 } },
      evaluator    = "set_volume" },

    -- ── UI Notifications ──────────────────────────────────────────────────────

    { id           = "action_show_toast",
      category     = "stack",
      tags         = { "ui" },
      color        = { 0.25, 0.65, 0.85 },
      label        = "show toast",
      tooltip      = "Pushes a coloured message into the information feed.",
      slots        = { { key="text",  type="string", default="Hello!" },
                       { key="color", type="enum",   default="yellow",
                         options = { "yellow", "green", "blue", "red", "white" } } },
      evaluator    = "show_toast" },

    { id           = "action_show_alert",
      category     = "stack",
      tags         = { "ui" },
      color        = { 0.25, 0.65, 0.85 },
      label        = "show alert",
      tooltip      = "Pushes a red warning message into the information feed.",
      slots        = { { key="text", type="string", default="Alert!" } },
      evaluator    = "show_alert" },

    { id           = "action_add_to_log",
      category     = "stack",
      tags         = { "ui" },
      color        = { 0.25, 0.65, 0.85 },
      label        = "add to log",
      tooltip      = "Appends a quiet grey entry to the information feed.",
      slots        = { { key="text", type="string", default="..." } },
      evaluator    = "add_to_log" },

    -- ── Depot management ──────────────────────────────────────────────────────

    { id           = "cond_depot_open",
      category     = "boolean",
      tags         = { "depot" },
      color        = { 0.55, 0.38, 0.18 },
      label        = "depot is open",
      tooltip      = "True when the primary depot is open.",
      slots        = {},
      evaluator    = "depot_open" },

    { id           = "cond_depot_vehicle_count",
      category     = "boolean",
      tags         = { "depot", "vehicle" },
      color        = { 0.55, 0.38, 0.18 },
      label        = "depot vehicle count",
      tooltip      = "Compare the number of vehicles assigned to the primary depot.",
      slots        = { { key="op",    type="enum",   default=">",
                         options = { ">", "<", "=" } },
                       { key="value", type="number", default=2, step=1, min=0 } },
      assertion    = { subject="depot", property="vehicle_count", op_from_slot="op", slot="value" },
      evaluator    = "depot_vehicle_count" },

    { id           = "action_open_depot",
      category     = "stack",
      tags         = { "depot" },
      color        = { 0.55, 0.38, 0.18 },
      label        = "open depot",
      tooltip      = "Marks the primary depot as open.",
      slots        = {},
      evaluator    = "open_depot" },

    { id           = "action_close_depot",
      category     = "stack",
      tags         = { "depot" },
      color        = { 0.55, 0.38, 0.18 },
      label        = "close depot",
      tooltip      = "Marks the primary depot as closed.",
      slots        = {},
      evaluator    = "close_depot" },

    { id           = "action_rename_depot",
      category     = "stack",
      tags         = { "depot" },
      color        = { 0.55, 0.38, 0.18 },
      label        = "rename depot to",
      tooltip      = "Sets the display name of the primary depot.",
      slots        = { { key="name", type="string", default="HQ" } },
      evaluator    = "rename_depot" },

    { id           = "action_set_depot_capacity",
      category     = "stack",
      tags         = { "depot" },
      color        = { 0.55, 0.38, 0.18 },
      label        = "set depot capacity",
      tooltip      = "Sets the maximum vehicles for the primary depot (0 = unlimited).",
      slots        = { { key="value", type="number", default=5, step=1, min=0 } },
      evaluator    = "set_depot_capacity" },

    { id           = "action_send_vehicles_to_depot",
      category     = "stack",
      tags         = { "depot", "vehicle" },
      color        = { 0.55, 0.38, 0.18 },
      label        = "send to depot",
      tooltip      = "Sends all vehicles of the given type back to the depot.",
      slots        = { { key="vehicle_type", type="vehicle_enum", default="" } },
      evaluator    = "send_vehicles_to_depot" },

    -- ── Custom blocks / procedures ────────────────────────────────────────────

    { id           = "hat_define",
      category     = "hat",
      tags         = { "logic" },
      color        = { 0.55, 0.20, 0.55 },
      label        = "define",
      tooltip      = "Marks this rule as a reusable procedure. Give it a name and call it with 'call'.",
      must_be_first = true,
      slots        = { { key="name", type="string", default="my block" } },
      evaluator    = nil },

    { id           = "action_call",
      category     = "stack",
      tags         = { "logic" },
      color        = { 0.55, 0.20, 0.55 },
      label        = "call",
      tooltip      = "Calls a procedure defined with 'define'. Shares the current trip/vehicle context.",
      slots        = { { key="name", type="string", default="my block" } },
      evaluator    = "action_call" },

    -- ── Client management ─────────────────────────────────────────────────────

    { id           = "cond_client_count",
      category     = "boolean",
      tags         = { "client" },
      color        = { 0.30, 0.60, 0.50 },
      label        = "client count",
      tooltip      = "Compare the total number of clients.",
      slots        = { { key="op",    type="enum",   default=">", options={"<",">","="} },
                       { key="value", type="number", default=1, step=1, min=0 } },
      assertion    = { subject="client", property="count", op_from_slot="op", slot="value" },
      evaluator    = "client_count" },

    { id           = "cond_active_client_count",
      category     = "boolean",
      tags         = { "client" },
      color        = { 0.30, 0.60, 0.50 },
      label        = "active client count",
      tooltip      = "Compare the number of clients currently generating trips.",
      slots        = { { key="op",    type="enum",   default=">", options={"<",">","="} },
                       { key="value", type="number", default=1, step=1, min=0 } },
      evaluator    = "active_client_count" },

    { id           = "action_pause_all_clients",
      category     = "stack",
      tags         = { "client" },
      color        = { 0.30, 0.60, 0.50 },
      label        = "pause all clients",
      tooltip      = "Stops all clients from generating new trips.",
      slots        = {},
      evaluator    = "pause_all_clients" },

    { id           = "action_resume_all_clients",
      category     = "stack",
      tags         = { "client" },
      color        = { 0.30, 0.60, 0.50 },
      label        = "resume all clients",
      tooltip      = "Allows all clients to generate new trips again.",
      slots        = {},
      evaluator    = "resume_all_clients" },

    { id           = "action_set_client_freq",
      category     = "stack",
      tags         = { "client" },
      color        = { 0.30, 0.60, 0.50 },
      label        = "set client frequency",
      tooltip      = "Sets how fast all clients generate trips. 100% = normal. 200% = half as fast.",
      slots        = { { key="pct", type="number", default=100, step=25, min=10, max=500 } },
      evaluator    = "set_client_freq" },

    { id           = "action_add_client",
      category     = "stack",
      tags         = { "client" },
      color        = { 0.30, 0.60, 0.50 },
      label        = "add client",
      tooltip      = "Adds a new client to the city.",
      slots        = {},
      evaluator    = "add_client" },

    { id           = "action_remove_client",
      category     = "stack",
      tags         = { "client" },
      color        = { 0.30, 0.60, 0.50 },
      label        = "remove client",
      tooltip      = "Removes the most recently added client (minimum 1 client remains).",
      slots        = {},
      evaluator    = "remove_client" },

    -- ── Utility / exotic ──────────────────────────────────────────────────────

    { id           = "action_comment",
      category     = "stack",
      tags         = { "logic" },
      color        = { 0.50, 0.50, 0.50 },
      label        = "//",
      tooltip      = "A comment block — does nothing. Use the text slot to annotate your rules.",
      slots        = { { key="text", type="string", default="note" } },
      evaluator    = "action_comment" },

    { id           = "action_set_rule_name",
      category     = "stack",
      tags         = { "logic" },
      color        = { 0.50, 0.50, 0.50 },
      label        = "name this rule",
      tooltip      = "Sets a display name for this rule (shown in the rule list header).",
      slots        = { { key="name", type="string", default="My Rule" } },
      evaluator    = "set_rule_name" },

    { id           = "action_benchmark",
      category     = "stack",
      tags         = { "logic" },
      color        = { 0.50, 0.50, 0.50 },
      label        = "benchmark",
      tooltip      = "Logs the current game time to the info feed. Useful for timing rules.",
      slots        = {},
      evaluator    = "benchmark" },

    { id           = "hat_every_n_seconds",
      category     = "hat",
      tags         = { "trigger", "logic" },
      color        = { 0.82, 0.60, 0.18 },
      label        = "every",
      tooltip      = "Fires this rule repeatedly, every N seconds.",
      event_type   = "poll",
      hat_evaluator = "hat_every_n_seconds",
      slots        = { { key="seconds", type="number", default=5, step=1, min=1 } } },

    { id           = "hat_after_n_seconds",
      category     = "hat",
      tags         = { "trigger", "logic" },
      color        = { 0.82, 0.60, 0.18 },
      label        = "after",
      tooltip      = "Fires this rule exactly once, N seconds after the game starts.",
      event_type   = "poll",
      hat_evaluator = "hat_after_n_seconds",
      slots        = { { key="seconds", type="number", default=10, step=5, min=1 } } },

-- ═══════════════════════════════════════════════════════════════════════════
-- FIND — core primitives (Phase 4)
-- ═══════════════════════════════════════════════════════════════════════════

    { id           = "find_match",
      category     = "find",
      node_kind    = "find",
      tags         = { "logic", "query" },
      color        = { 0.20, 0.55, 0.75 },
      label        = "Find",
      tooltip      = "Finds the best matching item in a collection and stores it in a variable. Use 'where' to filter and 'sorter' to rank.",
      evaluator    = "find_match",
      has_condition = true,
      slots        = {
          { key="collection", type="enum", options="dynamic" },
          { key="sorter",     type="enum", options="dynamic" },
          { key="variable",   type="string" },
      } },

-- ═══════════════════════════════════════════════════════════════════════════
-- LEGACY — hidden from main palette
-- ═══════════════════════════════════════════════════════════════════════════

    { id           = "ctrl_find_trip",
      category     = "legacy",
      node_kind    = "find",
      tags         = { "trip", "logic" },
      color        = { 0.25, 0.55, 0.75 },
      label        = "find trip",
      tooltip      = "Queries pending trips matching the condition, sorted by the chosen field. Runs the body once with ctx.trip set to the first match.",
      slots        = { { key="sort_by", type="enum", default="wait",
                         options={"wait","payout","scope","none"} },
                       { key="order",   type="enum", default="desc",
                         options={"desc","asc"} } } },

    { id           = "ctrl_find_vehicle",
      category     = "legacy",
      node_kind    = "find",
      tags         = { "vehicle", "logic" },
      color        = { 0.25, 0.55, 0.75 },
      label        = "find vehicle",
      tooltip      = "Queries idle vehicles of the chosen type matching the condition. Runs the body once with ctx.vehicle set to the first match.",
      slots        = { VEHICLE_SLOT,
                       { key="sort_by", type="enum", default="speed",
                         options={"speed","capacity","idle_time","none"} } } },

    { id           = "action_assign_ctx",
      category     = "stack",
      tags         = { "trip", "vehicle", "logic" },
      color        = { 0.85, 0.50, 0.15 },
      label        = "assign trip to vehicle",
      tooltip      = "Assigns ctx.trip to ctx.vehicle. Use inside nested 'find trip' + 'find vehicle' blocks.",
      slots        = {},
      evaluator    = "assign_ctx" },

}
