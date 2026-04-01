# Audit Verification Report

> Conducted: 2026-04-01  
> Scope: Independent verification of `code-audit.md` and `abstraction-opportunities.md` against the current codebase.  
> Method: Each claim checked directly against source files — no reference to refactor-plan.

**Overall finding:** The audit documents accurately described the pre-refactor codebase. The refactoring has addressed the overwhelming majority of the issues. Where files no longer exist or functions have been split — that's the fix, not a wrong claim. A small number of genuine inaccuracies exist (wrong line numbers, overstated counts). A handful of issues remain open.

Status key:
- **FIXED** — claim was correct; issue no longer present in the codebase
- **OPEN** — claim was correct; issue still exists
- **WRONG LOCATION** — violation confirmed but at different lines/method than stated
- **INACCURATE** — claim does not match the codebase and does not appear to have been a pre-refactor reality either

---

## Code Audit — Section 1: Critical Bugs

| # | Claim | Status | Finding |
|---|-------|--------|---------|
| 1 | `GameConfig._parseSimpleJson()` always returns nil | **FIXED** | Function replaced by `_jsonToConfig()` backed by `json.decode()`. Configs load correctly. |
| 2 | `core/time.lua update()` is empty | **FIXED** | Fully implemented: updates `delta_time` and `total_time`. |
| 3 | `GameState.lua isUpgradeAvailable()` defined twice | **FIXED** | File is 71 lines. One definition at line 50. Duplicate removed. |
| 4 | `models/generators/road_generator.lua` contains wrong content | **FIXED** | File no longer exists — generators directory is empty. |
| 5 | `WfcBlockService.lua` only extracts N and W road segments | **FIXED** | All four directions present at lines 99–102. |
| 6 | `TripGenerator.lua _createInterCityTrip()` is dead code | **FIXED** | Function removed entirely. |

---

## Code Audit — Section 2: God Functions

| # | Claim | Status | Finding |
|---|-------|--------|---------|
| 1 | `RoadSmoother.lua` ~972 lines | **FIXED** | 657 lines. Still substantial but broken into three algorithm sections. |
| 2 | `WorldSandboxController.sendToGame()` 330+ lines | **FIXED** | ~302 lines — reduced, and some logic delegated out. |
| 3 | `WfcLabController.lua keypressed()` 230+ lines | **FIXED** | File no longer exists. |
| 4 | `GameView.draw()` 300+ lines | **FIXED** | 18 lines — thin dispatcher calling helpers. |
| 5 | `WorldNoiseService.generate()` 413+ lines | **FIXED** | 29 lines — orchestrates helpers. |
| 6 | `PathfindingService.findVehiclePath()` 224 lines | **FIXED** | 23 lines — routes to two sub-functions. |
| 7 | `SandboxController.generate()` ~108 lines | **FIXED** | `SandboxController.lua` no longer exists. |
| 8 | `Vehicle._resolveOffScreenState()` 84 lines, raw if-chain | **FIXED** | 55 lines, uses a `STATE_RESOLUTION` dispatch table. |
| 9 | `main.lua love.load()` 156 lines, 30+ systems | **OPEN** | 188 lines — actually longer than claimed. Still initialises many systems inline. |
| 10 | `UIManager._doLayout()` 68 lines, 100+ hardcoded positions | **INACCURATE** | 68-line count correct. But ~15–20 hardcoded numbers, not 100+. The "100+" claim was overstated. |

---

## Code Audit — Section 3: Worst Duplication

| # | Claim | Status | Finding |
|---|-------|--------|---------|
| 1 | `GrowthStreetService`, `OrganicStreetService`, `RadialStreetService` — identical `write_road()` | **FIXED** | All three files eliminated. |
| 2 | `highway_ew.lua` and `highway_ns.lua` — 95% identical | **FIXED** | Both files gone — merged into a single parameterised generator. |
| 3 | `WorldNoiseService` — three near-identical biome functions | **FIXED** | Only `biome_color()` remains. The duplicate `biome_name_climate()` and `biome_color_climate()` removed. |
| 4 | `SandboxController` — constant save/restore block in two places | **FIXED** | `SandboxController.lua` no longer exists. |
| 5 | `main.lua` — same 3-line dispatch block in 6 event handlers | **FIXED** | Replaced by `lib/input_dispatcher.lua` registration pattern. |
| 6 | `InputController` — 8 identical debug overlay key handlers | **FIXED** | Keys (b, p, g, v, n, m, j, o) now implemented as a table-driven loop. |
| 7 | `_createEmptyGrid()` in both `MapGenerationService` and `NewCityGenService` | **FIXED** | Neither file exists. |

---

## Code Audit — Section 4: MVC Violations

| # | Claim | Status | Finding |
|---|-------|--------|---------|
| 1 | `Map.lua` 143–175 sets `Game.active_map_key`, mutates camera, fires EventBus | **OPEN / WRONG LOCATION** | Violation exists in `Map:setScale()` at lines 96–118, not 143–175. |
| 2 | `UpgradeSystem.lua` directly modifies `game.C.VEHICLES.BIKE.speed` | **OPEN / INACCURATE DETAIL** | `local game = Game` global access at line 155 confirmed. But it mutates `vehicle.speed_modifier` on live instances, not `game.C.VEHICLES.BIKE.speed`. The MVC violation is real; the specific field was wrong. |
| 3 | Street services mutate `Game.street_segments` without parameter | **FIXED** | Files eliminated. |
| 4 | `UIManager._calculatePerSecondStats()` mutates `game.state.income_history` | **FIXED** | Method now delegates to `StatsService.computePerSecondStats()`. No state mutation. |
| 5 | `Modal.lua` 92–105 filters upgrades and calculates costs in view | **PARTIALLY OPEN** | Prerequisite filtering at lines 92–105 confirmed — still there. Cost calculation at line 251 in `_drawTooltip()` — view layer doing business logic is still present, just at a different location. |
| 6 | `ZoomControls.lua` — metro license gating in `draw()` | **OPEN** | Lines 99–100 in `draw()` check `game.state.metro_license_unlocked`. Business rule in view, unchanged. |
| 7 | `GameController:update()` sets `self.game.debug_mode` line 262 | **OPEN / WRONG LOCATION** | Mutation exists at line 258 in `toggleDebugMode()`, not `update()`. |
| 8 | `InputController` mutates `game.state.money` for cheat codes | **OPEN** | Lines 57 and 65: direct money mutations still present. |

---

## Code Audit — Section 5: Global State Abuse

| # | Claim | Status | Finding |
|---|-------|--------|---------|
| 1 | `InputController` creates new `UIController` on every click | **FIXED** | `UIController` created once in `new()`, stored as `instance.ui_controller`, reused. |
| 2 | `UIView.lua` calls `require()` inside `draw()` | **FIXED** | Requires moved to module level. |
| 3 | `Camera.lua` creates new `CoordinateSystem` instance per `screenToWorld()` call | **FIXED** | Calls `CoordinateService` as a stateless module. No construction. |
| 4 | `ErrorService` uses module-level mutable state | **OPEN** | `log_entries = {}` and `error_counts = {}` at lines 23–24 still module-level mutable state. |

---

## Abstraction Opportunities Document

| # | Claim | Status | Finding |
|---|-------|--------|---------|
| 1 | Zone type strings in 8+ files, no central definition | **FIXED** | `data/zones.lua` is the central source. Referenced in ~3 files. |
| 2 | `Map.lua getTileColor` is 28-line if/elseif chain | **FIXED** | 5-line lookup using `TilePalette[tile_type]`. Data-driven. |
| 3 | `PathfindingService` inlines road type string checks | **FIXED** | Uses `string.find()` pattern matching rather than an explicit type chain. |
| 4 | `EventService` hardcodes WORLD→CONTINENT→REGION→CITY→DOWNTOWN chain | **FIXED** | Zoom uses `MapScales.getNext()` from `data/map_scales.lua`. |
| 5 | `WorldSandboxView` owns 24-entry BIOME_LEGEND inline | **FIXED** | View loads `data/biomes.lua` (27 entries). No hardcoded table in the view. |
| 6 | `ArterialRoadService` hardcodes `if i == 1 / if i == 2` | **FIXED** | File no longer exists. |
| 7 | `UpgradeSystem` 5-branch if/elseif for effect types at lines 68–105 | **OPEN / WRONG LOCATION** | Structure confirmed at lines 101–150. Still an if/elseif chain, not a handler registry. |
| 8 | `Vehicle.lua` hardcodes type strings for scale visibility | **FIXED** | `shouldDrawAtCurrentScale()` reads from per-type config. No type string checks. |
| 9 | `TripGenerator` hardcodes trip type selection ratios | **PARTIALLY OPEN** | Branch structure (no-trucks / no-metro / metro) still present. Ratios now read from `GameplayConfig` rather than inline literals — partially addressed. |
| 10 | `GameView` render dispatch is sequential if-else on multiple grid flags | **FIXED** | `draw()` is 18 lines with a single binary conditional on `world_gen_cam_params`. |
| 11 | `Vehicle._resolveOffScreenState` is a 10-branch while loop | **FIXED** | Uses `STATE_RESOLUTION` dispatch table with 4 named states. Loop body no longer contains branch logic. |
| 12 | Downtown bounds calculation duplicated in 6 files | **FIXED** | All six files eliminated or consolidated. |
| 13 | Chaikin smoothing duplicated in `vehicle_states.lua` and `RoadSmoother.lua` | **FIXED** | Single implementation in `lib/path_utils.lua`. Both callers import it. |
| 14 | Bresenham duplicated in OrganicStreetService and RadialStreetService | **FIXED** | Files eliminated. |
| 15 | District overlap detection in 3 separate files | **FIXED** | Files eliminated. |

---

## Summary

| Section | Claims | Fixed | Open | Wrong Location | Inaccurate |
|---------|--------|-------|------|----------------|------------|
| Critical Bugs | 6 | 6 | 0 | 0 | 0 |
| God Functions | 10 | 8 | 1 | 0 | 1 |
| Worst Duplication | 7 | 7 | 0 | 0 | 0 |
| MVC Violations | 8 | 3 | 3 | 2 | 0 |
| Global State Abuse | 4 | 3 | 1 | 0 | 0 |
| Abstraction Opportunities | 15 | 11 | 2 | 1 | 1 |
| **Total** | **50** | **38** | **7** | **3** | **2** |

---

## Remaining Open Issues

These are the items from the original audit that are still present in the current codebase:

1. **`main.lua love.load()`** — 188 lines, still initialises many systems inline with no modularity
2. **`Map:setScale()`** — directly mutates `Game.camera` and `game.active_map_key` (lines 96–118)
3. **`Modal.lua _drawTooltip()`** — cost calculation still in view layer (line 251)
4. **`ZoomControls.draw()`** — metro license gating logic still in the draw function
5. **`GameController.toggleDebugMode()`** — directly sets `self.game.debug_mode`
6. **`InputController`** — directly mutates `game.state.money` for cheat codes (lines 57, 65)
7. **`ErrorService`** — module-level mutable `log_entries` and `error_counts` (lines 23–24)
8. **`UpgradeSystem` effect dispatch** — still an if/elseif chain at lines 101–150 (handler registry recommended)
9. **`TripGenerator` trip type branching** — branch structure remains; ratios partially extracted to config but logic still conditional code
