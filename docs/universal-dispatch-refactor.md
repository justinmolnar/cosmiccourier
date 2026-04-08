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
| Smart-assignment actions with duplicated iteration loops | 0 (Replaced by Find in Phase 4) |
| Collection types hard-coded inside the Engine | 2 (`for_each_vehicle`, `for_each_trip`) |
| Estimated code quality | 8.0/10 |

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

**Status:** Complete

**Work completed:**
- Canonicalized `bool_compare` evaluator in `DispatchEvaluators.lua`.
- Added `bool_compare` block definition to `data/dispatch_blocks.lua` with full operator support.
- Fixed `cmp()` helper in `services/DispatchEvaluators.lua` to support all 6 operators (added `>=` and `<=` support).
- Moved 15 specific comparison conditions (including `cond_payout`, `cond_wait`, `cond_money`, etc.) to the `legacy` category in `data/dispatch_blocks.lua`.

**Deviation from plan:** None.

---

## Phase 4 — The "Find" Block

**Goal:** Replace the 4 smart-assignment actions and 3 hard-coded collection iterators in the Engine with a single composable `Find(Collection, Filter, Sorter) → Variable` block. After this phase, "find the fastest eligible bike" is not a hard-coded action — it is a Find block configured by the user.

**Status:** Complete

**Work completed:**
- Created `data/dispatch_collections.lua` and `data/dispatch_sorters.lua` registries as the single source of truth for iteration and scoring.
- Implemented `find_match` evaluator in `services/DispatchEvaluators.lua` which uses the registries to filter and sort items.
- Updated `services/DispatchRuleEngine.lua` to use a generic `find` node handler, removing ~60 lines of hard-coded `ctrl_find_trip` logic.
- Added the `find_match` block definition to `data/dispatch_blocks.lua`.
- Moved 4 smart-assignment actions (`assign_nearest`, `assign_fastest`, `assign_most_capacity`, `assign_least_recent`) to the `legacy` category.
- Moved `ctrl_find_trip` and `ctrl_find_vehicle` to the `legacy` category.

**Deviation from plan:**
- Skipped the extraction of the shared `collectEligible` helper as the generic `find_match` implementation rendered it redundant before it was needed for refactoring.
- Used `category = "find"` for the new block instead of `category = "core"` to maintain consistency with other functional categories.

---

## Phase 5 — Action Registry (The "Call" Block)

**Goal:** Move all ~62 action/effect evaluators from `DispatchEvaluators.lua` into a formal registry so the Engine is a data-driven loop with no domain knowledge. After this phase, adding a new world-impacting action requires one entry in `data/dispatch_actions.lua` — not an evaluator function, block definition, and Engine `if` statement.

**Status:** Not started

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
