-- data/dispatch_blocks.lua
-- Pure data: block definitions for the visual dispatch rule editor.
-- No functions, no requires. Add an entry here to add a new block type.
--
-- Categories:
--   trigger    — hat block; starts a rule
--   condition  — boolean test against the trip or game state
--   logic      — AND / OR / NOT connectors
--   effect     — side-effect actions (counters, flags); do NOT claim the trip
--   action     — terminal actions; claim, skip, or cancel the trip
--
-- Validation fields (all optional):
--   must_be_first          = true   → can only be placed as the very first block
--   max_per_rule           = N      → at most N of this block per rule
--   valid_after_categories = {…}    → last block's category MUST be in this list
--   requires_category_before= {…}   → at least one block of each listed category must exist before
--   terminal               = true   → nothing can follow this block
--   scope_slot_key         = "key"  → marks this block as setting a scope condition (capability check)
--   vehicle_slot_key       = "key"  → marks this block as assigning a vehicle type (capability check)

-- Counter keys available to the player (persistent across ticks, saved with game)
local COUNTER_KEYS = { "A", "B", "C", "D", "E" }
-- Flag keys available to the player
local FLAG_KEYS    = { "X", "Y", "Z" }

-- Shared slot definitions reused across many blocks
local SCOPE_SLOT   = { key = "scope",   type = "enum",   options = { "district", "city", "region", "continent", "world" }, default = "district" }
local VALUE_SLOT   = { key = "value",   type = "number", default = 0, step = 50, min = 0 }
local SECONDS_SLOT = { key = "seconds", type = "number", default = 10, step = 5, min = 0 }
local VEHICLE_SLOT = { key = "vehicle_type", type = "vehicle_enum", default = "bike" }
local QUEUE_SLOT   = { key = "value",   type = "number", default = 5,  step = 1,  min = 0 }
local MONEY_SLOT   = { key = "value",   type = "number", default = 500, step = 100, min = 0 }
local COUNTER_SLOT = { key = "key",     type = "enum",   options = COUNTER_KEYS, default = "A" }
local COUNT_VAL    = { key = "value",   type = "number", default = 0, step = 1, min = 0 }
local FLAG_SLOT    = { key = "key",     type = "enum",   options = FLAG_KEYS,    default = "X" }
local AMOUNT_SLOT  = { key = "amount",  type = "number", default = 1, step = 1, min = 1 }
local N_SLOT       = { key = "n",       type = "number", default = 1, step = 1, min = 1 }

-- Validation shorthand
local AFTER_COND_OR_LOGIC   = { "trigger", "condition", "logic" }
local AFTER_TRIG_COND       = { "trigger", "condition" }
local AFTER_ANY_NONTERMINAL = { "trigger", "condition", "effect" }
local NEEDS_TRIGGER         = { "trigger" }

return {

-- ═══════════════════════════════════════════════════════════════════════════
-- TRIGGERS
-- ═══════════════════════════════════════════════════════════════════════════

    { id            = "trigger_trip",
      category      = "trigger",
      color         = { 0.85, 0.65, 0.10 },
      label         = "when trip pending",
      slots         = {},
      must_be_first = true,
      max_per_rule  = 1 },

-- ═══════════════════════════════════════════════════════════════════════════
-- CONDITIONS — Trip
-- ═══════════════════════════════════════════════════════════════════════════

    { id                       = "cond_scope",
      category                 = "condition",
      color                    = { 0.22, 0.68, 0.32 },
      label                    = "scope is",
      slots                    = { SCOPE_SLOT },
      evaluator                = "scope_equals",
      requires_category_before = NEEDS_TRIGGER,
      valid_after_categories   = AFTER_COND_OR_LOGIC,
      scope_slot_key           = "scope",
      assertion                = { subject = "trip", property = "scope", op = "eq",  slot = "scope" } },

    { id                       = "cond_scope_not",
      category                 = "condition",
      color                    = { 0.22, 0.68, 0.32 },
      label                    = "scope is not",
      slots                    = { SCOPE_SLOT },
      evaluator                = "scope_not_equals",
      requires_category_before = NEEDS_TRIGGER,
      valid_after_categories   = AFTER_COND_OR_LOGIC,
      assertion                = { subject = "trip", property = "scope", op = "neq", slot = "scope" } },

    { id                       = "cond_payout_gt",
      category                 = "condition",
      color                    = { 0.22, 0.68, 0.32 },
      label                    = "payout >",
      slots                    = { VALUE_SLOT },
      evaluator                = "payout_gt",
      requires_category_before = NEEDS_TRIGGER,
      valid_after_categories   = AFTER_COND_OR_LOGIC,
      assertion                = { subject = "trip", property = "payout", op = "gt", slot = "value" } },

    { id                       = "cond_payout_lt",
      category                 = "condition",
      color                    = { 0.22, 0.68, 0.32 },
      label                    = "payout <",
      slots                    = { VALUE_SLOT },
      evaluator                = "payout_lt",
      requires_category_before = NEEDS_TRIGGER,
      valid_after_categories   = AFTER_COND_OR_LOGIC,
      assertion                = { subject = "trip", property = "payout", op = "lt", slot = "value" } },

    { id                       = "cond_payout_between",
      category                 = "condition",
      color                    = { 0.22, 0.68, 0.32 },
      label                    = "payout",
      slots                    = { { key = "min", type = "number", default = 100, step = 50, min = 0 },
                                   { key = "max", type = "number", default = 500, step = 50, min = 0 } },
      evaluator                = "payout_between",
      requires_category_before = NEEDS_TRIGGER,
      valid_after_categories   = AFTER_COND_OR_LOGIC },

    { id                       = "cond_wait_gt",
      category                 = "condition",
      color                    = { 0.22, 0.68, 0.32 },
      label                    = "waited >",
      slots                    = { SECONDS_SLOT },
      evaluator                = "wait_gt",
      requires_category_before = NEEDS_TRIGGER,
      valid_after_categories   = AFTER_COND_OR_LOGIC,
      assertion                = { subject = "trip", property = "wait", op = "gt", slot = "seconds" } },

    { id                       = "cond_wait_lt",
      category                 = "condition",
      color                    = { 0.22, 0.68, 0.32 },
      label                    = "waited <",
      slots                    = { SECONDS_SLOT },
      evaluator                = "wait_lt",
      requires_category_before = NEEDS_TRIGGER,
      valid_after_categories   = AFTER_COND_OR_LOGIC,
      assertion                = { subject = "trip", property = "wait", op = "lt", slot = "seconds" } },

    { id                       = "cond_multi_leg",
      category                 = "condition",
      color                    = { 0.22, 0.68, 0.32 },
      label                    = "is multi-city",
      slots                    = {},
      evaluator                = "is_multi_leg",
      requires_category_before = NEEDS_TRIGGER,
      valid_after_categories   = AFTER_COND_OR_LOGIC },

-- ═══════════════════════════════════════════════════════════════════════════
-- CONDITIONS — Vehicle availability
-- ═══════════════════════════════════════════════════════════════════════════

    { id                       = "cond_vehicle_idle",
      category                 = "condition",
      color                    = { 0.28, 0.72, 0.58 },
      label                    = "any idle",
      slots                    = { VEHICLE_SLOT },
      evaluator                = "vehicle_idle_any",
      requires_category_before = NEEDS_TRIGGER,
      valid_after_categories   = AFTER_COND_OR_LOGIC,
      assertion                = { subject = "fleet", property = "idle", op = "any",  key_slot = "vehicle_type" } },

    { id                       = "cond_vehicle_none",
      category                 = "condition",
      color                    = { 0.28, 0.72, 0.58 },
      label                    = "no idle",
      slots                    = { VEHICLE_SLOT },
      evaluator                = "vehicle_idle_none",
      requires_category_before = NEEDS_TRIGGER,
      valid_after_categories   = AFTER_COND_OR_LOGIC,
      assertion                = { subject = "fleet", property = "idle", op = "none", key_slot = "vehicle_type" } },

    { id                       = "cond_idle_count_gt",
      category                 = "condition",
      color                    = { 0.28, 0.72, 0.58 },
      label                    = "idle count >",
      slots                    = { VEHICLE_SLOT, N_SLOT },
      evaluator                = "vehicle_idle_count_gt",
      requires_category_before = NEEDS_TRIGGER,
      valid_after_categories   = AFTER_COND_OR_LOGIC,
      assertion                = { subject = "fleet", property = "idle", op = "gt", slot = "n", key_slot = "vehicle_type" } },

-- ═══════════════════════════════════════════════════════════════════════════
-- CONDITIONS — Game state
-- ═══════════════════════════════════════════════════════════════════════════

    { id                       = "cond_queue_gt",
      category                 = "condition",
      color                    = { 0.35, 0.65, 0.72 },
      label                    = "queue >",
      slots                    = { QUEUE_SLOT },
      evaluator                = "queue_gt",
      requires_category_before = NEEDS_TRIGGER,
      valid_after_categories   = AFTER_COND_OR_LOGIC,
      assertion                = { subject = "game", property = "queue", op = "gt", slot = "value" } },

    { id                       = "cond_queue_lt",
      category                 = "condition",
      color                    = { 0.35, 0.65, 0.72 },
      label                    = "queue <",
      slots                    = { QUEUE_SLOT },
      evaluator                = "queue_lt",
      requires_category_before = NEEDS_TRIGGER,
      valid_after_categories   = AFTER_COND_OR_LOGIC,
      assertion                = { subject = "game", property = "queue", op = "lt", slot = "value" } },

    { id                       = "cond_money_gt",
      category                 = "condition",
      color                    = { 0.35, 0.65, 0.72 },
      label                    = "money >",
      slots                    = { MONEY_SLOT },
      evaluator                = "money_gt",
      requires_category_before = NEEDS_TRIGGER,
      valid_after_categories   = AFTER_COND_OR_LOGIC,
      assertion                = { subject = "game", property = "money", op = "gt", slot = "value" } },

    { id                       = "cond_money_lt",
      category                 = "condition",
      color                    = { 0.35, 0.65, 0.72 },
      label                    = "money <",
      slots                    = { MONEY_SLOT },
      evaluator                = "money_lt",
      requires_category_before = NEEDS_TRIGGER,
      valid_after_categories   = AFTER_COND_OR_LOGIC,
      assertion                = { subject = "game", property = "money", op = "lt", slot = "value" } },

    { id                       = "cond_rush_hour",
      category                 = "condition",
      color                    = { 0.35, 0.65, 0.72 },
      label                    = "rush hour",
      slots                    = {},
      evaluator                = "rush_hour_active",
      requires_category_before = NEEDS_TRIGGER,
      valid_after_categories   = AFTER_COND_OR_LOGIC,
      max_per_rule             = 1 },

-- ═══════════════════════════════════════════════════════════════════════════
-- CONDITIONS — Counters & Flags
-- ═══════════════════════════════════════════════════════════════════════════

    { id                       = "cond_counter_gt",
      category                 = "condition",
      color                    = { 0.55, 0.38, 0.80 },
      label                    = "counter >",
      slots                    = { COUNTER_SLOT, COUNT_VAL },
      evaluator                = "counter_gt",
      requires_category_before = NEEDS_TRIGGER,
      valid_after_categories   = AFTER_COND_OR_LOGIC,
      assertion                = { subject = "counter", property = "value", op = "gt", slot = "value", key_slot = "key" } },

    { id                       = "cond_counter_lt",
      category                 = "condition",
      color                    = { 0.55, 0.38, 0.80 },
      label                    = "counter <",
      slots                    = { COUNTER_SLOT, COUNT_VAL },
      evaluator                = "counter_lt",
      requires_category_before = NEEDS_TRIGGER,
      valid_after_categories   = AFTER_COND_OR_LOGIC,
      assertion                = { subject = "counter", property = "value", op = "lt", slot = "value", key_slot = "key" } },

    { id                       = "cond_counter_eq",
      category                 = "condition",
      color                    = { 0.55, 0.38, 0.80 },
      label                    = "counter =",
      slots                    = { COUNTER_SLOT, COUNT_VAL },
      evaluator                = "counter_eq",
      requires_category_before = NEEDS_TRIGGER,
      valid_after_categories   = AFTER_COND_OR_LOGIC,
      assertion                = { subject = "counter", property = "value", op = "eq", slot = "value", key_slot = "key" } },

    { id                       = "cond_flag_set",
      category                 = "condition",
      color                    = { 0.55, 0.38, 0.80 },
      label                    = "flag set",
      slots                    = { FLAG_SLOT },
      evaluator                = "flag_is_set",
      requires_category_before = NEEDS_TRIGGER,
      valid_after_categories   = AFTER_COND_OR_LOGIC,
      assertion                = { subject = "flag", property = "state", op = "set",   key_slot = "key" } },

    { id                       = "cond_flag_clear",
      category                 = "condition",
      color                    = { 0.55, 0.38, 0.80 },
      label                    = "flag clear",
      slots                    = { FLAG_SLOT },
      evaluator                = "flag_is_clear",
      requires_category_before = NEEDS_TRIGGER,
      valid_after_categories   = AFTER_COND_OR_LOGIC,
      assertion                = { subject = "flag", property = "state", op = "clear", key_slot = "key" } },

-- ═══════════════════════════════════════════════════════════════════════════
-- LOGIC connectors
-- ═══════════════════════════════════════════════════════════════════════════

    { id                       = "logic_and",
      category                 = "logic",
      color                    = { 0.82, 0.78, 0.15 },
      label                    = "and",
      op                       = "and",
      slots                    = {},
      requires_category_before = NEEDS_TRIGGER,
      valid_after_categories   = { "trigger", "condition" } },

    { id                       = "logic_or",
      category                 = "logic",
      color                    = { 0.82, 0.78, 0.15 },
      label                    = "or",
      op                       = "or",
      slots                    = {},
      requires_category_before = NEEDS_TRIGGER,
      valid_after_categories   = { "trigger", "condition" } },

    -- Prefix negation: flips the result of the immediately following condition.
    { id                       = "logic_not",
      category                 = "logic",
      color                    = { 0.88, 0.50, 0.18 },
      label                    = "not",
      negate                   = true,
      slots                    = {},
      requires_category_before = NEEDS_TRIGGER,
      valid_after_categories   = AFTER_COND_OR_LOGIC },

-- ═══════════════════════════════════════════════════════════════════════════
-- EFFECTS — side-effect blocks (counters & flags)
-- These do NOT claim or skip the trip; they run and the rule continues
-- to the next block. Chain them before a terminal action.
-- ═══════════════════════════════════════════════════════════════════════════

    { id                       = "effect_counter_add",
      category                 = "effect",
      color                    = { 0.52, 0.28, 0.80 },
      label                    = "counter +=",
      slots                    = { COUNTER_SLOT, AMOUNT_SLOT },
      evaluator                = "counter_add",
      requires_category_before = NEEDS_TRIGGER,
      valid_after_categories   = AFTER_ANY_NONTERMINAL },

    { id                       = "effect_counter_sub",
      category                 = "effect",
      color                    = { 0.52, 0.28, 0.80 },
      label                    = "counter -=",
      slots                    = { COUNTER_SLOT, AMOUNT_SLOT },
      evaluator                = "counter_sub",
      requires_category_before = NEEDS_TRIGGER,
      valid_after_categories   = AFTER_ANY_NONTERMINAL },

    { id                       = "effect_counter_reset",
      category                 = "effect",
      color                    = { 0.52, 0.28, 0.80 },
      label                    = "reset counter",
      slots                    = { COUNTER_SLOT },
      evaluator                = "counter_reset",
      requires_category_before = NEEDS_TRIGGER,
      valid_after_categories   = AFTER_ANY_NONTERMINAL },

    { id                       = "effect_flag_set",
      category                 = "effect",
      color                    = { 0.52, 0.28, 0.80 },
      label                    = "set flag",
      slots                    = { FLAG_SLOT },
      evaluator                = "flag_set",
      requires_category_before = NEEDS_TRIGGER,
      valid_after_categories   = AFTER_ANY_NONTERMINAL },

    { id                       = "effect_flag_clear",
      category                 = "effect",
      color                    = { 0.52, 0.28, 0.80 },
      label                    = "clear flag",
      slots                    = { FLAG_SLOT },
      evaluator                = "flag_clear",
      requires_category_before = NEEDS_TRIGGER,
      valid_after_categories   = AFTER_ANY_NONTERMINAL },

-- ═══════════════════════════════════════════════════════════════════════════
-- ACTIONS — terminal blocks
-- ═══════════════════════════════════════════════════════════════════════════

    { id                       = "action_assign_type",
      category                 = "action",
      color                    = { 0.28, 0.45, 0.88 },
      label                    = "assign to",
      slots                    = { VEHICLE_SLOT },
      evaluator                = "assign_vehicle_type",
      requires_category_before = NEEDS_TRIGGER,
      valid_after_categories   = AFTER_ANY_NONTERMINAL,
      vehicle_slot_key         = "vehicle_type",
      constraint               = "vehicle_covers_trip_scope" },

    { id                       = "action_assign_any",
      category                 = "action",
      color                    = { 0.28, 0.45, 0.88 },
      label                    = "assign to any",
      slots                    = {},
      evaluator                = "assign_any",
      requires_category_before = NEEDS_TRIGGER,
      valid_after_categories   = AFTER_ANY_NONTERMINAL },

    { id                       = "action_assign_nearest",
      category                 = "action",
      color                    = { 0.28, 0.45, 0.88 },
      label                    = "nearest",
      slots                    = { VEHICLE_SLOT },
      evaluator                = "assign_nearest",
      requires_category_before = NEEDS_TRIGGER,
      valid_after_categories   = AFTER_ANY_NONTERMINAL,
      vehicle_slot_key         = "vehicle_type",
      constraint               = "vehicle_covers_trip_scope" },

    { id                       = "action_cancel",
      category                 = "action",
      color                    = { 0.62, 0.18, 0.18 },
      label                    = "cancel trip",
      slots                    = {},
      evaluator                = "cancel_trip",
      requires_category_before = NEEDS_TRIGGER,
      valid_after_categories   = AFTER_ANY_NONTERMINAL,
      terminal                 = true,
      max_per_rule             = 1 },

    { id                       = "action_skip",
      category                 = "action",
      color                    = { 0.72, 0.22, 0.22 },
      label                    = "skip (hold)",
      slots                    = {},
      evaluator                = "skip",
      requires_category_before = NEEDS_TRIGGER,
      valid_after_categories   = AFTER_ANY_NONTERMINAL,
      terminal                 = true,
      max_per_rule             = 1 },

}
