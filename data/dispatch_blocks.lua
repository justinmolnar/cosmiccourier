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

    { id           = "cond_multi_leg",
      category     = "boolean",
      tags         = { "trip" },
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

-- ═══════════════════════════════════════════════════════════════════════════
-- BOOLEAN — conditions (game state)
-- ═══════════════════════════════════════════════════════════════════════════

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

-- ═══════════════════════════════════════════════════════════════════════════
-- STACK — effects (side-effect blocks; do NOT claim the trip)
-- ═══════════════════════════════════════════════════════════════════════════

-- ── Trip mutation ─────────────────────────────────────────────────────────

-- ── Economy ───────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════════════
-- STACK — queue manipulation (non-terminal; reorder/bulk-cancel pending)
-- ═══════════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════════
-- LEGACY — hidden from main palette
-- ═══════════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════════
-- STACK — flow control
-- ═══════════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════════
-- STACK — actions (terminal blocks)
-- ═══════════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════════
-- STACK — per-vehicle actions (require a vehicle event hat)
-- ═══════════════════════════════════════════════════════════════════════════

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
    --   trip:    payout  wait_time  bonus  leg_count  scope  cargo_size  next_mode
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
      loop_handler = "ctrl_repeat_n",
      slots        = { { key="n", type="number", default=3, step=1, min=1 } } },

    { id           = "ctrl_repeat_until",
      category     = "loop",
      tags         = { "logic" },
      color        = { 0.20, 0.55, 0.75 },
      label        = "repeat until",
      tooltip      = "Repeats the inner stack until the condition becomes true (safety cap: 100 iterations). Drop a condition block into the slot.",
      loop_handler = "ctrl_repeat_until",
      slots        = {} },

    { id           = "ctrl_for_each_vehicle",
      category     = "loop",
      tags         = { "logic", "vehicle" },
      color        = { 0.20, 0.55, 0.75 },
      label        = "for each vehicle",
      tooltip      = "Runs the inner stack once for each vehicle of the chosen type. Use 'this vehicle' blocks inside to act on each vehicle.",
      loop_handler = "ctrl_for_each_vehicle",
      slots        = { VEHICLE_SLOT } },

    { id           = "ctrl_for_each_trip",
      category     = "loop",
      tags         = { "logic", "trip" },
      color        = { 0.20, 0.55, 0.75 },
      label        = "for each pending trip",
      tooltip      = "Runs the inner stack once for each trip in the pending queue. Trip blocks inside act on the iterated trip.",
      loop_handler = "ctrl_for_each_trip",
      slots        = {} },

-- ═══════════════════════════════════════════════════════════════════════════
-- STACK — Visual / Looks (require vehicle context)
-- ═══════════════════════════════════════════════════════════════════════════

    -- ── Sound ─────────────────────────────────────────────────────────────────

    -- ── UI Notifications ──────────────────────────────────────────────────────

    -- ── Depot management ──────────────────────────────────────────────────────

    { id           = "cond_depot_open",
      category     = "boolean",
      tags         = { "depot" },
      color        = { 0.55, 0.38, 0.18 },
      label        = "depot is open",
      tooltip      = "True when the primary depot is open.",
      slots        = {},
      evaluator    = "depot_open" },

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

    { id           = "block_call",
      category     = "stack",
      tags         = { "logic" },
      color        = { 0.50, 0.50, 0.50 },
      label        = "Call",
      tooltip      = "Generic action caller. Pick an action from the list.",
      evaluator    = "block_call",
      slots        = {
          { key="action", type="enum", options = "dynamic" },
      } },

    { id           = "action_call",
      category     = "stack",
      tags         = { "logic" },
      color        = { 0.55, 0.20, 0.55 },
      label        = "call",
      tooltip      = "Calls a procedure defined with 'define'. Shares the current trip/vehicle context.",
      slots        = { { key="name", type="string", default="my block" } },
      evaluator    = "action_call" },

    -- ── Building cargo ─────────────────────────────────────────────────────────

    { id           = "hat_trip_deposited",
      category     = "hat",
      event_type   = "trip_deposited",
      tags         = { "trigger", "building" },
      color        = { 0.55, 0.38, 0.18 },
      label        = "when trip deposited at building",
      tooltip      = "Fires when a trip arrives at any building (dock, depot, client). Sets ctx.trip and ctx.building.",
      must_be_first = true, max_per_rule = 1 },

    -- ── Client management ─────────────────────────────────────────────────────

    -- ── Utility / exotic ──────────────────────────────────────────────────────

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

}
