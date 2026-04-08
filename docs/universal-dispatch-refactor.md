# Cosmic Courier — Universal Dispatch Block Refactor

> Created: 2026-04-07
> Source: codebase audit + original vision doc
> Scope: `data/dispatch_blocks.lua`, `services/DispatchEvaluators.lua`, `services/ReporterEvaluators.lua`, `services/DispatchRuleEngine.lua`, `views/tabs/DispatchTab.lua`

---

## The Goal

Move the dispatch system from a "kitchen sink" of hard-coded blocks to five composable primitives: **Get**, **Compare**, **Set**, **Find**, **Call**. After the final phase, adding a new game entity or property requires a single registry entry — not a new block ID, evaluator function, and engine `if` statement.

---

## Critical Rules

1. **No phase begins until the previous phase is complete and tested.**
2. **No feature work during a refactor phase.** Rules that worked before must work identically after.
3. **One logical change per commit.** Do not combine a rename with a behavior fix.
4. **If a refactor uncovers a real bug, fix the bug in a separate commit first.**
5. **Never delete old blocks — move them to the Legacy section.** When a primitive replaces a specific block, the old block is relocated to the `legacy` category in `dispatch_blocks.lua` and hidden from the main palette. It stays fully functional so existing rules keep working and the new primitive can be tested against it. Deletion happens only in Phase 6 after all primitives are verified.
6. **Legacy blocks are read-only.** Do not modify the evaluator logic of a legacy block once it is moved. If a bug is found in a legacy evaluator, fix it in the new primitive instead — the legacy version is your ground-truth baseline for comparison testing.
7. **Core primitives live in `data/dispatch_blocks.lua` under `category = "core"`. Legacy/prefab blocks live under `category = "legacy"`.** The palette in `DispatchTab.lua` filters out `legacy` by default but can show them via a toggle (e.g. a "Show Legacy" checkbox in the palette header).

---

## The Failure Mode to Avoid (Read This First)

Every phase in this refactor has one specific way to fail: **moving hardcoded values to a different location and calling it agnostic.**

Examples of this failure:
- Phase 2 puts 15 property names as a static enum inside the block def. The block still knows about `payout`, `money`, `count`. That is not agnostic. That is the same problem in a different file.
- Phase 3 puts a hardcoded list of operators in the block def. If the operator set is structural (`>`, `<`, `=`, `!=`, `>=`, `<=`) and does not change with game content, that is acceptable. If it were a list of game-specific comparison modes, it would not be.
- Phase 4 puts collection names (`vehicles`, `pending_trips`) as a static enum in the block def. The block still knows game entities exist. That is not agnostic.
- Phase 5 puts action names as a static enum in the Call block. The block still knows every action that exists. That is not agnostic.

**The test for agnosticism:** Could you add a new property, collection, sorter, or action to the game by editing only a single data registry file, with zero changes to any block definition, evaluator, or engine? If yes, it is agnostic. If no, it is not done.

A block def is allowed to contain: its ID, category, label, color, tooltip, and structural slot types (things that describe HOW it connects — not WHAT it connects to). It is never allowed to contain a list of game entities, properties, actions, or collections. Those lists live exclusively in registry files in `data/`.

---

## Current State

| Metric | Value |
|--------|-------|
| Evaluator functions (DispatchEvaluators.lua) | ~62 |
| Reporter evaluator functions (ReporterEvaluators.lua) | 15 data + 16 math/string = 31 |
| Specific comparison conditions (`cmp()` callers) | 15 |
| `cmp()` operator support | 6 of 6 (`>`, `<`, `=`, `!=`, `>=`, `<=`) |
| Hard-coded data reporters (non-math) | 12 |
| Smart-assignment actions with duplicated iteration loops | 4 |
| Collection types hard-coded inside the Engine | 3 (`for_each_vehicle`, `for_each_trip`, `find_trip`) |
| Estimated code quality | 7.0/10 |

---

## Phase 1 — Named Variable System

**Goal:** Replace hard-coded `counters`/`flags`/`text_vars` tables with a single string-keyed `vars` table.

**Status:** Complete (commit `e293b90`)

**Work completed:**
- Unified `GameState.vars` (deleted `counters`, `flags`, `text_vars`).
- Implemented `TextInput` component for the UI.
- Dynamic block width expansion as custom names are typed.
- All evaluators updated to call `getVar()`/`setVar()`.

**Deviation from plan:** None.

---

## Phase 2 — The "Get" Reporter Block

**Goal:** Create a generic `Get(Source, Property)` reporter that replaces the 12 hard-coded data reporters in `ReporterEvaluators.lua`. After this phase, adding a new inspectable property to any entity requires one entry in a registry — not a new reporter block and evaluator.

**Status:** Complete

**Work completed:**
- Created `data/dispatch_properties.lua` registry as the single source of truth.
- Implemented `rep_get_property` as a pure, registry-driven pass-through (removed all hardcoded logic and context checks).
- Updated `DispatchTab.lua` with **cascading visibility**: Property slot only appears after Source is selected.
- Made `Get` block **variadic**: additional parameter slots are rendered dynamically based on the registry's `params` field.
- Created reusable `views/components/Dropdown.lua` for all enum-type slots.
- Implemented placeholder rendering (`<source>`, `<property>`) so new blocks start in a clean state.
- Moved 12 legacy reporters to `legacy` category in `dispatch_blocks.lua`.

**Deviation from plan:**
- Extended the plan to support **variadic parameters** to avoid "magic numbers" in the block structure.
- Replaced "click-to-cycle" UI with a **Dropdown component**.

---

## Phase 3 — The "Compare" Block

**Goal:** Replace 15 specific comparison conditions with one `Compare(Left, Op, Right)` block. The seed already exists as `reporter_compare` (`DispatchEvaluators.lua:470`) — Phase 3 makes it canonical and deletes everything it supersedes.

**Status:** Not started

### Tasks

#### 3.1 — Fix `cmp()` in `DispatchEvaluators.lua:29`

(Completed as part of Phase 2 preparation)

#### 3.2 — Canonicalize `reporter_compare` as `bool_compare`

Rename the evaluator `reporter_compare` (line 470) to `bool_compare`. Update its block definition in `dispatch_blocks.lua` to expose all 6 operators in the `op` enum (`>`, `<`, `>=`, `<=`, `=`, `!=`). The left and right slots already accept reporter nodes — no logic changes needed.

```lua
local function bool_compare(block, ctx)
    local lv = tonumber(evalSlot(block.slots.left,  ctx)) or 0
    local rv = tonumber(evalSlot(block.slots.right, ctx)) or 0
    return cmp(lv, block.slots.op or ">", rv)
end
```

#### 3.3 — Delete the 15 specific comparison conditions

After Phase 2, every left-hand side these blocks hard-code is now a `rep_get_property` call. They are redundant.

**Move to `legacy` category in `dispatch_blocks.lua`** (evaluator functions stay untouched):
- `payout_compare` (line 48) — `cmp(trip.base_payout, op, value)`
- `wait_compare` (line 52) — `cmp(trip.wait_time, op, seconds)`
- `leg_count` (line 60) — `cmp(#trip.legs, op, value)`
- `cargo_size` (line 64) — `cmp(leg.cargo_size, op, value)`
- `trip_bonus` (line 69) — `cmp(trip.speed_bonus, op, value)`
- `idle_count_compare` (line 98) — `cmp(idle_count, op, n)`
- `fleet_util` (line 112) — `cmp(fleet_pct, op, value)`
- `queue_compare` (line 128) — `cmp(#pending, op, value)`
- `money_compare` (line 132) — `cmp(money, op, value)`
- `counter_compare` (line 148) — `cmp(var, op, value)`
- `this_vehicle_speed` (line 591) — `cmp(vehicle.speed, op, value)`
- `this_vehicle_trips` (line 596) — `cmp(vehicle.trips, op, value)`
- `depot_vehicle_count` (line 816) — `cmp(#depot.vehicles, op, value)`
- `client_count` (line 866) — `cmp(#clients, op, value)`
- `active_client_count` (line 871) — `cmp(active_count, op, value)`

Only the `category` field changes. Existing rules using any of these blocks continue to evaluate normally. They are hidden from the main palette but visible via the "Show Legacy" toggle.

**Do not delete:**
- `scope_equals` / `scope_not_equals` — string equality checks, evaluate to booleans without a numeric value. Move to Prefab section as `Compare(Get(trip, scope), =, "district")` wrappers for UX convenience.
- `is_multi_leg` — becomes a Prefab for `Compare(Get(trip, leg_count), >, 1)`.
- `rush_hour_active`, `upgrade_purchased` — boolean state checks, not comparisons; keep.
- `vehicle_idle_any`, `vehicle_idle_none` — collection checks, addressed in Phase 4.
- `random_chance`, `always_true`, `always_false`, `counter_mod` — special logic blocks, keep.
- `flag_is_set`, `flag_is_clear` — keep until `rep_get_var` (Phase 2.4) is stable enough to replace them as Prefabs.
- `text_var_eq`, `text_var_contains` — string comparisons; `bool_compare` is numeric only. Keep `text_var_eq`; consider `text_var_contains` as a permanent special block.
- `this_vehicle_type`, `this_vehicle_idle`, `depot_open` — boolean state checks, keep.

#### 3.4 — Update the UI in `DispatchTab.lua`

The existing `reporter_compare` block likely renders with two reporter drop-zones and an operator dropdown. After the rename and 6-operator expansion:
- Ensure the operator slot renders as a 6-option enum widget.
- Ensure left/right slots accept any `reporter` category block (including the new `rep_get_property`).
- Update palette entry labels and tooltip.

### Expected Outcome

- `grep -rn "payout_compare\|money_compare\|queue_compare\|counter_compare\|fleet_util" services/` returns zero results.
- `cmp("5", ">=", "5")` returns true. `cmp("5", "!=", "4")` returns true. (Write a test before deleting old code.)
- A rule comparing `Get(trip, payout) > 500` evaluates identically to what the old `payout_compare` block did.
- The palette has one comparison block instead of fifteen.

### Testing

- Before deleting any old comparison block, verify `bool_compare` produces identical results on the same input: run both the old evaluator and `bool_compare` on the same ctx and assert equal.
- Test all 6 operators: verify `>=` and `<=` pass the boundary case (`5 >= 5` = true, `5 <= 5` = true); verify `!=` (`5 != 4` = true, `5 != 5` = false).
- Rebuild a representative rule set using only `bool_compare + rep_get_property`. Run a full game session; verify dispatch behavior is identical.
- Verify that `scope_equals`, `rush_hour_active`, `random_chance` still evaluate correctly — they were not deleted.

### AI Notes

Do task 3.1 (the `cmp()` bug fix) as a standalone commit before writing any of the new block logic. The missing operators are a silent bug affecting any existing rule that uses `>=` or `<=` — fixing it first ensures the baseline is correct before the migration. Do not combine the bug fix with any other change.

---

## Phase 4 — The "Find" Block

**Goal:** Replace the 4 smart-assignment actions and 3 hard-coded collection iterators in the Engine with a single composable `Find(Collection, Filter, Sorter) → Variable` block. After this phase, "find the fastest eligible bike" is not a hard-coded action — it is a Find block configured by the user.

### Tasks

#### 4.1 — Audit duplication in smart-assignment actions

The four actions `assign_nearest` (line 319), `assign_fastest` (line 419), `assign_most_capacity` (line 434), and `assign_least_recent` (line 451) share an identical skeleton:

```lua
local want = (block.slots.vehicle_type or ""):lower()
local eligible = {}
for _, v in ipairs(ctx.game.entities.vehicles) do
    if (v.type or ""):lower() == want
       and TripEligibility.canAssign(v, ctx.trip, ctx.game) then
        eligible[#eligible+1] = v
    end
end
if #eligible == 0 then return false end
table.sort(eligible, <comparator>)
eligible[1]:assignTrip(ctx.trip, ctx.game)
return "claimed"
```

The only difference is the comparator. Extract a shared `collectEligible(ctx, vehicle_type)` helper before Phase 4.2. This is an internal refactor, not a visible change — do it in a separate commit.

#### 4.2 — `data/dispatch_collections.lua`

Define the collection types the Find block can iterate:

```lua
return {
    { id = "vehicles",      label = "Vehicles",       ctx_key = "vehicles",
      read  = function(ctx, slots) return ctx.game.entities.vehicles end,
      needs = {} },
    { id = "pending_trips", label = "Pending Trips",  ctx_key = "trips",
      read  = function(ctx, slots) return ctx.game.entities.trips.pending end,
      needs = {} },
}
```

#### 4.3 — `data/dispatch_sorters.lua`

Define the sorter metrics the Find block can use:

```lua
return {
    -- Vehicle sorters
    { id = "nearest",      label = "Nearest",         for_type = "vehicles",
      score = function(item, ctx) local ax = item.grid_anchor and item.grid_anchor.x or 0; ... return d2 end,
      order = "asc" },
    { id = "fastest",      label = "Fastest",         for_type = "vehicles",
      score = function(item, ctx) return item:getSpeed() end,        order = "desc" },
    { id = "most_capacity",label = "Most Capacity",   for_type = "vehicles",
      score = function(item, ctx) return item:getEffectiveCapacity(ctx.game) end, order = "desc" },
    { id = "least_recent", label = "Least Recently Used", for_type = "vehicles",
      score = function(item, ctx) return item.last_trip_end_time or 0 end, order = "asc" },
    -- Trip sorters
    { id = "highest_payout",label = "Highest Payout", for_type = "pending_trips",
      score = function(item, ctx) return item.base_payout or 0 end,  order = "desc" },
    { id = "longest_wait", label = "Longest Wait",    for_type = "pending_trips",
      score = function(item, ctx) return item.wait_time or 0 end,    order = "desc" },
}
```

#### 4.4 — `find_match` evaluator in `DispatchEvaluators.lua`

```lua
local function find_match(block, ctx)
    local Collections = require("data.dispatch_collections")
    local Sorters     = require("data.dispatch_sorters")

    local col_id  = block.slots.collection or "vehicles"
    local sort_id = block.slots.sorter     or "nearest"
    local out_key = block.slots.output_var or "found"

    local col  = Collections[col_id]
    local sort = Sorters[sort_id]
    if not col or not sort then return false end

    local items = col.read(ctx, block.slots)

    -- Apply filter (the block's nested boolean condition)
    local filtered = {}
    for _, item in ipairs(items) do
        local inner_ctx = { game = ctx.game, trip = ctx.trip, vehicle = item }
        if not block.condition or evalBoolNode(block.condition, inner_ctx) then
            filtered[#filtered+1] = item
        end
    end

    if #filtered == 0 then return false end

    -- Sort and pick best
    table.sort(filtered, function(a, b)
        local sa = sort.score(a, ctx)
        local sb = sort.score(b, ctx)
        return sort.order == "asc" and sa < sb or sa > sb
    end)

    setVar(ctx.game, out_key, filtered[1])
    return false
end
```

#### 4.5 — Add `find` node kind to `RuleTreeUtils.lua` and Engine

The Find block needs a nested boolean condition slot (like `ctrl_if`). Add `newFindNode(def_id, slots, condition)` constructor to `RuleTreeUtils.lua` (one already exists — verify it matches the schema above).

In `DispatchRuleEngine.lua`, the `elseif node.kind == "find"` branch (line 168) currently contains hard-coded logic for `ctrl_find_trip`. Replace this branch with a call to `find_match` via the standard evaluator lookup:

```lua
elseif node.kind == "find" then
    local def = getDefs()[node.def_id]
    local fn  = def and def.evaluator and getEvaluators()[def.evaluator]
    if fn then fn(node, ctx) end
```

This removes ~60 lines of hard-coded trip-sort logic from the Engine (lines 168–230).

#### 4.6 — Add Find block definition to `dispatch_blocks.lua`

```lua
{
    id        = "find_match",
    category  = "find",
    label     = "Find",
    node_kind = "find",
    evaluator = "find_match",
    slots = {
        { name = "collection",  kind = "enum", options = "collections" },
        { name = "sorter",      kind = "enum", options = "dynamic" },   -- filtered by collection
        { name = "output_var",  kind = "text", default = "found" },
    },
    has_condition = true,   -- renders nested boolean filter slot
    tooltip = "Find the best matching item in a collection and store it in a variable.",
},
```

#### 4.7 — Delete the 4 smart-assignment actions

After `find_match` is working, the four smart-assignment evaluators are redundant. They become Prefab blocks (pre-configured Find + assign_ctx combos) in the Prefab section.

**Move to `legacy` category in `dispatch_blocks.lua`** (evaluator functions stay untouched):
- `assign_nearest` (line 319)
- `assign_fastest` (line 419)
- `assign_most_capacity` (line 434)
- `assign_least_recent` (line 451)

### Expected Outcome

- `grep -rn "assign_nearest\|assign_fastest\|assign_most_capacity\|assign_least_recent" services/` returns zero results.
- The Engine's `elseif node.kind == "find"` branch is ≤5 lines.
- "Find nearest bike" is a Find block configured with `collection=vehicles`, `sorter=nearest`, `filter=vehicle_type=bike` — no code change required.
- Adding a new sorter metric is one entry in `data/dispatch_sorters.lua`.

### Testing

- Rebuild a rule equivalent to `assign_nearest(bike)` using `find_match` + `assign_ctx`. Verify it claims the same trip as the old hard-coded block on identical game state.
- Test `find_match` when no items pass the filter: verify it returns `false`, does not crash, and does not mutate `output_var`.
- Test `ctrl_for_each_vehicle` and `ctrl_for_each_trip` still work (they are not deleted in this phase).
- Run a complete dispatch cycle across 10 trips; verify no change in assignment outcomes vs. pre-phase baseline.

### AI Notes

Task 4.5 requires care: the Engine's existing `find` branch already handles `ctrl_find_trip` with custom sort logic. Read lines 168–230 of `DispatchRuleEngine.lua` in full before writing the replacement. The goal is to make the branch call the evaluator via the registry — not to inline new logic. If `ctrl_find_trip` is used by any existing saved rules, add it to the Prefab section before deleting the hard-coded Engine branch.

---

**Status:** Not started
**Line count change (estimated):** +120 (two registry files + evaluator) / −200 (4 action bodies + hard-coded Engine branch) = net −80

---

## Phase 5 — Action Registry (The "Call" Block)

**Goal:** Move all ~62 action/effect evaluators from `DispatchEvaluators.lua` into a formal registry so the Engine is a data-driven loop with no domain knowledge. After this phase, adding a new world-impacting action requires one entry in `data/dispatch_actions.lua` — not an evaluator function, block definition, and Engine `if` statement.

### Tasks

#### 5.1 — Audit what "domain knowledge" the Engine currently holds

Read `DispatchRuleEngine.lua` from top to bottom and list every place it contains logic specific to a block category or type (not generic tree traversal). Expected findings from the current codebase:
- The `for_each_vehicle` / `for_each_trip` loop bodies (lines ~137–164): these embed vehicle-type filtering and snapshot logic inline.
- The `find` branch (will be cleared by Phase 4.5).
- Any direct reads of `ctx.game.entities.*` outside of evaluator calls.

Document the list before writing any code. This audit is the deliverable for task 5.1.

#### 5.2 — `data/dispatch_actions.lua`

Create a formal action registry. Each entry declares its ID, evaluator function reference, parameter schema, and category tags.

```lua
-- data/dispatch_actions.lua
local E = require("services.DispatchEvaluators")

return {
    { id = "add_money",       fn = E.add_money,       params = { { name="amount", kind="reporter" } }, tags = {"economy"} },
    { id = "subtract_money",  fn = E.subtract_money,  params = { { name="amount", kind="reporter" } }, tags = {"economy"} },
    { id = "set_payout",      fn = E.set_payout,      params = { { name="value",  kind="reporter" } }, tags = {"trip"} },
    { id = "play_sound",      fn = E.play_sound,      params = { { name="sound",  kind="enum", options="sounds" } }, tags = {"audio"} },
    -- ... all ~62 entries
}
```

The `params` schema is used by `DispatchTab.lua` to render the slot widgets, replacing the per-block slot definitions currently in `dispatch_blocks.lua`.

#### 5.3 — Slim `DispatchEvaluators.lua` to pure functions

Remove all block-definition concerns from `DispatchEvaluators.lua`. The file should export only the function table. All slot-rendering metadata moves to the registry in 5.2.

The file header changes from "keyed by the `evaluator` field in dispatch_blocks.lua" to "pure functions — called only through data/dispatch_actions.lua".

#### 5.4 — Loop extraction from `DispatchRuleEngine.lua`

After Phase 4.5, the only remaining hard-coded blocks in the Engine are the `for_each_vehicle` and `for_each_trip` loop bodies (lines ~137–164). These are iterators, not domain logic — but the vehicle-type filtering and snapshot logic is still inline.

Move the snapshot + filter logic into the `find_match` evaluator path (or a shared `collectItems(collection_id, filter, ctx)` helper used by both loops and Find). The Engine's loop branch becomes:

```lua
elseif node.kind == "loop" then
    local def = getDefs()[node.def_id]
    local fn  = def and def.loop_handler and getEvaluators()[def.loop_handler]
    if fn then return fn(node, ctx, evalStack) end
```

Each loop type registers a `loop_handler` in `dispatch_blocks.lua` pointing to an evaluator function. The Engine has no knowledge of what it iterates.

#### 5.5 — `block_call` block definition

Add a `Call(ActionName, Params)` block to `dispatch_blocks.lua`. This is the user-facing generic action block. It presents a dropdown of all actions from `data/dispatch_actions.lua` and renders their param slots dynamically.

```lua
{
    id        = "block_call",
    category  = "stack",
    label     = "Call",
    evaluator = "block_call_eval",
    slots = {
        { name = "action", kind = "enum", options = "dispatch_actions" },
        { name = "params", kind = "dynamic" },  -- populated by selected action's params schema
    },
    tooltip = "Execute a registered action.",
},
```

The `block_call_eval` evaluator looks up the action by ID and calls its `fn`:

```lua
local function block_call_eval(block, ctx)
    local Actions = require("data.dispatch_actions")
    local id = block.slots.action or ""
    for _, a in ipairs(Actions) do
        if a.id == id then return a.fn(block, ctx) end
    end
    return false
end
```

#### 5.6 — Verify `DispatchRuleEngine.lua` is ≤80 lines

After Phases 4 and 5, the Engine should contain only:
- Block definition loading (~15 lines)
- `evalReporter` (~5 lines)
- `evalBoolNode` (~15 lines)
- `evalStack` loop (~25 lines) with generic branches: `control`, `loop`, `find`, `stack`
- Public API: `evaluate`, `evaluatePoll`, `fireEvent`, `newRule`, `newBlockInst`, `getDefById`

If it exceeds 80 lines after cleanup, identify and extract the remaining inline logic before closing the phase.

### Expected Outcome

- `DispatchRuleEngine.lua` is ≤80 lines with zero domain knowledge — no references to `trip`, `vehicle`, `money`, or any game entity.
- Adding a new action = one entry in `data/dispatch_actions.lua`. Zero other file edits.
- `grep -rn "ctx.game.state.money\|ctx.game.entities" services/DispatchRuleEngine.lua` returns zero results.

### Testing

- Run the full evaluator test suite against the registry-backed path. Every existing action must produce identical output.
- Verify `block_call_eval` for an unknown action ID returns `false` without crashing.
- Add a dummy action to `data/dispatch_actions.lua`. Verify it appears in the Call block dropdown and executes without touching any other file.
- Load a saved game with existing rules. Verify all rules evaluate and dispatch trips as before.

### AI Notes

Phase 5 is the highest-risk phase because it restructures how evaluators are loaded. The existing `evaluator` field in `dispatch_blocks.lua` already provides the data-driven lookup — Phase 5 formalizes and extends that pattern. Start with task 5.1 (the audit) and do not write code until you have a complete list of what the Engine currently knows. The engine's current line count is ~439 lines; the 80-line target is aggressive but achievable once Phases 4 and 5 are both done.

---

**Status:** Not started
**Line count change (estimated):** +80 (`data/dispatch_actions.lua`) / −360 (Engine body reduction + evaluator reorganization) = net −280

---

## Phase 6 — Legacy Cleanup

**Goal:** Delete every block that has been in the `legacy` category since Phases 2–5 and has been confirmed redundant by real gameplay testing. This phase only happens when you are confident the primitives cover every use case the old blocks handled.

### Prerequisites (all must be true before any deletion)

- At least one complete gameplay session has been played using only core primitive blocks in the dispatch rules — no legacy blocks in use.
- Every legacy block has a documented equivalent expressed in core primitives (see table below).
- `RuleTreeUtils.migrateRule()` has entries for every legacy block ID being deleted, so any saved rules automatically upgrade on load.

### Legacy Block → Primitive Equivalent Table

Populate this table during Phases 2–5 as each block is moved to legacy:

| Legacy Block ID | Primitive Equivalent |
|---|---|
| `rep_trip_payout` | `Get(trip, payout)` |
| `rep_money` | `Get(game, money)` |
| `rep_vehicle_count` | `Get(fleet, count)` |
| `payout_compare` | `Compare(Get(trip, payout), >, value)` |
| `money_compare` | `Compare(Get(game, money), >, value)` |
| `counter_compare" | `Compare(Get(variable, key), >, value)` |
| `assign_nearest` | `Find(vehicles, nearest) + assign_ctx` |
| `assign_fastest` | `Find(vehicles, fastest) + assign_ctx` |
| *(fill in as phases complete)* | |

### Tasks

#### 6.1 — Write migration entries in `RuleTreeUtils.lua`

For each legacy block being deleted, add an entry to `migrateRule()` that transforms the old node into its primitive equivalent. Run the migration against a snapshot of real saved rules before deleting anything.

#### 6.2 — Delete legacy evaluator functions from `DispatchEvaluators.lua` and `ReporterEvaluators.lua`

Delete the functions, not just the block definitions. Run the evaluator test suite after each deletion batch — do not delete all functions in one commit.

#### 6.3 — Delete legacy block definitions from `dispatch_blocks.lua`

Remove all entries with `category = "legacy"`. Remove the "Show Legacy" palette toggle from `DispatchTab.lua`.

#### 6.4 — Verify `DispatchEvaluators.lua` line count

Target: under 200 lines. Everything over that threshold is either a legitimate unique action (not replaceable by a primitive) or a missed cleanup item.

### Expected Outcome

- `grep -rn "category.*legacy" data/dispatch_blocks.lua` returns zero results.
- `DispatchEvaluators.lua` is under 200 lines.
- All saved rules load and evaluate without errors via the migration path.

### Testing

- Load a save file that was created before Phase 2 (or a snapshot taken before any migration). Verify `migrateRule()` upgrades all rules silently and they behave identically.
- Run a full gameplay session; verify no crash or behavioral regression.

---

**Status:** Not started — prerequisite: Phases 2–5 complete and verified

---

## Technical Design Principles

These apply to all phases:

- **Validation via assertions:** The `assertion` table in `dispatch_blocks.lua` must be updated whenever a new source/property combination is added to the registry. If a user tries to get `speed` from a `game` source, the validator catches it before evaluation.
- **Legacy blocks are a safety net, not a crutch.** They exist so you can test new primitives against known-good behavior. If you find yourself building new rules with legacy blocks after Phase 2, stop — that is a signal the primitive is missing something.
- **No hard-coding:** After Phase 5, the only code that knows about specific game entities is in `data/` registry files and the thin `read`/`score`/`fn` lambdas they contain.
- **Migration is mandatory before deletion.** `RuleTreeUtils.lua` already has `migrateRule()`. Every block ID removed in Phase 6 needs a migration entry added first.
