# Cosmic Courier — Refactor Plan: Second Pass

> Created: 2026-04-01
> Source documents: `docs/audit-verification-report.md`
> Scope: Remaining MVC violations, global state abuse, and structural issues identified after the first refactor pass

---

## Critical Rules

1. **No phase begins until the previous phase is complete and tested.**
2. **No feature work during a refactor phase.** The game must behave identically before and after each phase.
3. **One logical change per commit.** Do not combine a rename with a behavior fix.
4. **If a refactor uncovers a real bug, fix the bug in a separate commit first.**
5. **Delete the old code.** Do not keep commented-out originals or backward-compat shims.

---

## Current State

| Metric | Value |
|--------|-------|
| Remaining MVC violations | 5 |
| Models/views with direct Game mutation | 3 |
| Business logic in view layer | 3 locations |
| If/elseif dispatch chains to replace | 2 |
| God functions remaining | 1 (`love.load` at 188 lines) |
| Duplicated calculations in view layer | 2 (cost formula in Modal) |

---

## Phase 1 — View Layer Cleanup

**Goal:** Remove all business logic from view files. After this phase, every view file does exactly one thing: render. No view computes costs, checks license eligibility, or calculates game state.

### Tasks

#### 1.1 — `ZoomControls.lua` — Metro license gating out of `draw()`

`views/components/ZoomControls.lua` lines 94–100 compute zoom-out eligibility directly in `draw()`:

```lua
local can_afford_license = game.state.money >= C.ZOOM.METRO_LICENSE_COST
local zoom_out_enabled = (current_scale == S.DOWNTOWN and
    (game.state.metro_license_unlocked or can_afford_license)) or ...
```

This is a business rule — the view should not know what a metro license costs or how affordability is determined.

- Create `services/ZoomService.lua`:
  - `ZoomService.canZoomOut(current_scale, game_state, constants)` — returns bool
  - `ZoomService.canZoomIn(current_scale, game_state, constants)` — returns bool
  - `ZoomService.getZoomBlockReason(current_scale, game_state, constants)` — returns string or nil (used by tooltip if present)
  - Uses `data/map_scales.lua` for hierarchy; does not reach into view layer
- Update `ZoomControls.draw()`:
  - Replace the inline affordability block with `ZoomService.canZoomOut(...)` and `ZoomService.canZoomIn(...)`
  - View reads a bool; it does not compute it

Note: Phase 4 of the first pass skipped `ZoomService` because `EventService` had already been simplified to one-line calls. That was correct. `ZoomService` is justified here because it absorbs logic from the **view** layer, not from `EventService`.

#### 1.2 — `Modal.lua` — Cost calculation out of `_drawTooltip()` and `handle_mouse_down()`

The upgrade cost formula appears in two places in `views/components/Modal.lua`:
- Line 250–251 in `_drawTooltip()`: `local cost = node_data.cost * (node_data.cost_multiplier ^ purchased_level)`
- Line 291 in `handle_mouse_down()`: same formula recalculated

`UpgradeModalViewModel` is already required at line 164 and used in `_drawTree()`. The ViewModel is the right home.

- Add `UpgradeModalViewModel.getNodeCost(node_data, purchased_level)` — returns the computed cost
- Update `Modal._drawTooltip()`: replace inline formula with `UpgradeModalViewModel.getNodeCost(...)`
- Update `Modal.handle_mouse_down()`: same replacement
- Verify: the cost displayed in the tooltip and the cost checked on click are now guaranteed to be identical (previously they could diverge if one was updated and the other was not)

#### 1.3 — `Modal.lua` — Prerequisite filtering in `update()`

`views/components/Modal.lua` lines 92–105 filter upgrade nodes by prerequisites inside the view's `update()` method. This is eligibility logic, not render logic.

- `UpgradeSystem` already exists and owns upgrade state. Add `UpgradeSystem:getDisplayableNodes(game_state)` — returns a filtered list of nodes the player can see given current prerequisites
- Update `Modal:update()`: replace inline prerequisite loop with a call to `UpgradeSystem:getDisplayableNodes(game.state)`
- Modal stores the result; its draw methods read from it. No eligibility logic remains in the view.

### Expected Outcome

- `ZoomControls.lua` contains no references to `metro_license_cost`, `money`, or affordability
- `Modal.lua` contains no cost formula and no prerequisite loop
- `grep -n "cost_multiplier\^" views/` returns zero results

### Testing

- Open the upgrade modal at various unlock states; verify visible nodes and costs are unchanged
- Reach exactly the metro license cost in money; verify zoom-out button enables at the boundary
- Verify zoom-out is disabled when broke and re-enables when money crosses the threshold

### AI Notes

Task 1.1: `ZoomService.canZoomOut` must handle the edge case where the player is at DOWNTOWN scale with no license and cannot afford one — this is the "locked" state that should show the license purchase prompt. Make sure the reason string captures this.

Task 1.2: check `handle_mouse_down` in Modal carefully — if it also fires a purchase action, the cost it uses to check affordability must match the displayed cost exactly. Two separate formula copies are the bug here.

---

**Status:** Complete
**Deviation from plan:** None.
**Notes:**
- `UpgradeModalViewModel.buildDisplayState` also contained the cost formula inline; updated it to call `getNodeCost` for internal consistency, making the ViewModel fully self-consistent.
- The module-level `require("views.UpgradeModalViewModel")` in Modal replaces the lazy `require` that was inside `_drawTree` — same module, now loaded once at startup instead of on every draw call.

---

## Phase 2 — Model Decoupling

**Goal:** Models stop mutating things they don't own. After this phase, `Map` does not touch `Game.camera`, and `UpgradeSystem` does not reach into the global `Game` variable.

### Tasks

#### 2.1 — `Map:setScale()` — Camera mutation out of the model

`models/Map.lua` lines 96–118 (`setScale`) directly mutates `game.camera.x`, `game.camera.y`, `game.camera.scale`, and `game.active_map_key`. The `game` object is passed in as a parameter (not a global), but the model is still doing the camera's job.

- `setScale()` should own only: updating `game.state.current_map_scale` and publishing the `"map_scale_changed"` event (it already does both)
- Remove the three camera-mutation lines (105–107) and the `game.active_map_key` assignment (line 99) from `setScale()`
- The `"map_scale_changed"` event already fires — add `active_map_key` and the target camera position as payload fields on the event
- Update `EventService` (or `GameController`) to subscribe to `"map_scale_changed"` and apply the camera repositioning there

**Before touching this:** grep for every subscriber to `"map_scale_changed"` to understand the full handler chain. Confirm there is exactly one place that should apply the camera update after this change.

#### 2.2 — `UpgradeSystem` — Inject Game instead of accessing global

`models/UpgradeSystem.lua` line 155: `local game = Game` — direct global access inside `applyStatToGameValues()`. This makes `UpgradeSystem` impossible to test in isolation.

- `UpgradeSystem:new(game)` — store `game` as `self.game` at construction time
- Find every call site that constructs `UpgradeSystem`; pass the game instance in
- Replace the `local game = Game` line with `local game = self.game`
- No behavior change — the same game reference, now injected

#### 2.3 — `UpgradeSystem` — Vehicle speed mutation out of the model

`models/UpgradeSystem.lua` lines 152–198 (`applyStatToGameValues`) iterates live vehicles and mutates `vehicle.speed_modifier` directly. A model should not iterate and patch the game's entity list.

- Create `services/VehicleUpgradeService.lua`:
  - `VehicleUpgradeService.applySpeedModifier(vehicles, vehicle_type, value)` — iterates the vehicle list and sets the modifier
  - This is the only place in the codebase allowed to do this iteration
- Update `UpgradeSystem.applyStatToGameValues()`:
  - Remove the two vehicle-iteration blocks (lines 161–177)
  - Replace with `VehicleUpgradeService.applySpeedModifier(self.game.entities.vehicles, "bike", stat_value)` etc.
- The upgrade model no longer knows about vehicle internals

### Expected Outcome

- `Map.lua` contains no assignments to `game.camera.*` or `game.active_map_key`
- `UpgradeSystem.lua` contains no reference to the global `Game`
- `UpgradeSystem.lua` contains no `for _, vehicle in ipairs(...)` loops
- Camera repositioning on scale change works identically to before

### Testing

- Zoom in/out through all five scale levels; verify camera repositioning is identical to pre-refactor
- Purchase a speed upgrade; verify bike and truck speeds change correctly in-game
- Verify UpgradeSystem can be constructed with any game-shaped table (isolation check)

### AI Notes

Task 2.1: the camera target position logic currently inside `setScale()` may need to be preserved as a pure function that returns `{x, y, scale}` — emit that as event payload rather than deleting the calculation. The calculation moves, not disappears.

Task 2.3: `applyStatToGameValues` handles multiple stat types beyond speed (capacity, trip gen rates, frenzy duration). Only the vehicle-iteration stats move to `VehicleUpgradeService`. The others (`max_pending_trips`, `frenzy_duration`, etc.) stay in `UpgradeSystem` for now.

---

**Status:** Complete
**Deviation from plan:** None.
**Notes:**
- `Map:update()` also publishes `map_scale_changed` on transition complete with no payload. The new EventService subscriber nil-guards on `data` so transition-complete fires are correctly ignored by the camera handler.
- `game.active_map_key` is always `"city"` across the entire codebase — the assignment in `setScale()` was redundant. Moved to the event subscriber as planned; behaviour is identical.

---

## Phase 3 — Dispatch Table Refactoring

**Goal:** Replace if/elseif chains that dispatch on type strings with handler registries. After this phase, adding a new upgrade effect type or a new trip type is a one-table-entry change.

### Tasks

#### 3.1 — `UpgradeSystem` — Effect dispatch → handler registry

`models/UpgradeSystem.lua` lines 101–150 (`applyDataDrivenEffect`) has a 5-branch if/elseif chain:

```lua
if effect_type == "set_flag" then ...
elseif effect_type == "add_stat" then ...
elseif effect_type == "multiply_stat" then ...
elseif effect_type == "multiply_stats" then ...
elseif effect_type == "special" then ...
```

Replace with a handler registry:

```lua
local EFFECT_HANDLERS = {
    set_flag       = function(effect, state) ... end,
    add_stat       = function(effect, state) ... end,
    multiply_stat  = function(effect, state) ... end,
    multiply_stats = function(effect, state) ... end,
    special        = function(effect, state) ... end,
}

function UpgradeSystem:applyDataDrivenEffect(effect, state)
    local handler = EFFECT_HANDLERS[effect.type]
    if not handler then
        ErrorService.warn("Unknown effect type: " .. tostring(effect.type))
        return
    end
    handler(effect, state)
end
```

Adding a new effect type is adding one entry to `EFFECT_HANDLERS`. The dispatch function body never changes again.

#### 3.2 — `TripGenerator` — Trip type selection → availability registry

`services/TripGenerator.lua` lines 30–49 use nested conditionals to select trip type:

```lua
if not trucks_exist then
    -- downtown only
elseif not metro_unlocked then
    -- random downtown/city
else
    -- same random downtown/city (metro branch identical to previous)
```

The metro branch is currently identical to the non-metro branch — inter-city was disabled. This is dead branching that will need to be activated when inter-city trips are implemented.

Replace with an availability-based selection:

```lua
local function getAvailableTripTypes(game_state)
    if not game_state.trucks_unlocked then
        return { { type = "downtown", weight = 1.0 } }
    end
    return {
        { type = "downtown", weight = GameplayConfig.DOWNTOWN_TRIP_CHANCE },
        { type = "city",     weight = 1.0 - GameplayConfig.DOWNTOWN_TRIP_CHANCE },
    }
    -- inter-city entry added here when region map is implemented
end
```

`generateTrip()` calls `getAvailableTripTypes()`, does a weighted random pick, then calls the appropriate `_create*Trip()` function. The branching logic is data; the selection mechanism is code. These are separated.

### Expected Outcome

- `applyDataDrivenEffect` body is 5–8 lines: lookup, nil-check, call
- Adding a new upgrade effect = one entry in `EFFECT_HANDLERS`, zero other edits
- `generateTrip()` has no nested if-blocks — only a weighted selection from the availability list
- Adding inter-city trips = one entry in the `getAvailableTripTypes` return table

### Testing

- Purchase every upgrade type; verify effects apply correctly
- Run the game for several minutes and verify the downtown/city trip ratio is consistent with `GameplayConfig.DOWNTOWN_TRIP_CHANCE`
- Add a dummy `test_effect` entry to `EFFECT_HANDLERS` that logs a message; verify it fires when a test upgrade with that type is applied

---

**Status:** Complete
**Deviation from plan:** None.
**Notes:**
- EFFECT_HANDLERS entries take `(system, upgrade)` rather than the plan's sketch of `(effect, state)` — handlers call instance methods (`system:applyStatToGameValues`, `system:applySpecialEffect`) so `self` must be passed. The dispatch function calls `handler(self, upgrade)`.
- `getAvailableTripTypes` takes `trucks_exist` bool (computed in `generateTrip`) rather than full `game_state` — the only state it needs is whether trucks are present. Keeps the function pure and easy to test.
- The metro_unlocked branch was identical to the non-metro branch; collapsed into one case as planned. The commented intercity entry marks the insertion point for when region map is implemented.

---

## Phase 4 — `love.load()` Decomposition

**Goal:** `main.lua:love.load()` is 188 lines initialising 11 distinct categories of systems in sequence. After this phase, `love.load()` is a short orchestrator whose body reads as a table of contents.

### Tasks

#### 4.1 — Extract bootstrap phases from `love.load()`

Current `love.load()` categories and the functions they map to:

| Lines | Category | Extract to |
|-------|----------|------------|
| 2–34 | Error, config, constants, graphics setup | `_initCore()` |
| 42–72 | Game global object construction (20+ properties) | `_buildGameObject()` → returns Game table |
| 74–84 | Save system — load save file and apply | `_loadSave(Game)` |
| 86–98 | UI, controllers, views, world sandbox wiring | `_initSystems(Game)` |
| 101–146 | Input dispatcher registration | `_initInputDispatcher(Game)` |
| 150–168 | Font loading with fallbacks | `_loadFonts(Game)` |
| 171–180 | World auto-generation | `_initWorld(Game)` |
| 182–185 | Auto-save timer setup | `_initAutoSave(Game)` |

After extraction, `love.load()` becomes:

```lua
function love.load()
    local Game = _initCore()
    _buildGameObject(Game)
    _loadSave(Game)
    _initSystems(Game)
    _initInputDispatcher(Game)
    _loadFonts(Game)
    _initWorld(Game)
    _initAutoSave(Game)
end
```

Each extracted function lives in `main.lua` as a local function above `love.load()`. Do not create a new file — this is internal decomposition, not a new module.

**Exception:** `_buildGameObject` may warrant becoming `core/game_factory.lua` if the Game table construction is complex enough to benefit from its own require chain. Measure the function length after extraction and decide.

#### 4.2 — Validate the input dispatcher block

Lines 101–146 currently register closures for every LÖVE input event. While this is correct (and was cleaned up from the old copy-paste pattern), the block is still 46 lines. Review whether the `InputDispatcher` registration can be tightened — specifically, whether the event name → method name mapping can be expressed as a table rather than 6 explicit function definitions.

This is a cleanup task only — do not change behavior.

### Expected Outcome

- `love.load()` body is under 20 lines
- Each sub-function has a single statable responsibility
- `grep -n "love.load" main.lua` returns a body that reads as a table of contents

### Testing

- Cold start the game; verify it loads identically to pre-refactor
- Load a save file; verify state is restored correctly
- Verify world auto-generation still fires and the world renders

---

**Status:** —
