# Cosmic Courier — Full Codebase Audit

> Conducted: 2026-03-31
> Scope: All Lua files — world gen, city gen, roads, pathfinding, controllers, models, views, services, utils

---

## Table of Contents

1. [Critical Bugs](#1-critical-bugs)
2. [God Functions & God Files](#2-god-functions--god-files)
3. [Worst Duplication](#3-worst-duplication)
4. [MVC Violations](#4-mvc-violations)
5. [Global State Abuse](#5-global-state-abuse)
6. [Magic Numbers](#6-magic-numbers)
7. [World Gen Specific Issues](#7-world-gen-specific-issues)
8. [What's Actually Fine](#8-whats-actually-fine)
9. [Priority Repair List](#9-priority-repair-list)

---

## 1. Critical Bugs

Actual broken or incorrect code that needs fixing before anything else.

| # | File | Lines | Issue |
|---|------|-------|-------|
| 1 | `config/GameConfig.lua` | 312–317 | `_parseSimpleJson()` is a stub that always returns `nil` — user configs **never load**, game always uses defaults |
| 2 | `core/time.lua` | 9 | `update()` is **completely empty** — `GameController` reads `time.total_time` which is never populated |
| 3 | `models/GameState.lua` | 51–53 / 82–94 | `isUpgradeAvailable()` defined **twice** — second definition silently shadows the first |
| 4 | `models/generators/road_generator.lua` | all | File **contains highway_merger code** — wrong content entirely |
| 5 | `services/WfcBlockService.lua` | 99–100 | Road segment extraction only handles **N and W directions** — E and S are silently missing |
| 6 | `services/TripGenerator.lua` | — | `_createInterCityTrip()` is defined but **never called** — dead code |

---

## 2. God Functions & God Files

Functions or files doing far too much. Ordered by severity.

| File | Function | ~Lines | What it's doing |
|------|----------|--------|-----------------|
| `utils/RoadSmoother.lua` | *(whole file)* | 972 | Three separate algorithms (chain walk, RDP simplify, Chaikin smooth) fused into one file; 6+ nesting levels |
| `controllers/WorldSandboxController.lua` | `sendToGame()` | 330+ | Terrain generation, WFC solving, coordinate conversion, and district assignment all in one method |
| `controllers/WfcLabController.lua` | `keypressed()` | 230+ | 15+ distinct key handlers, each mutating 5+ Game globals, zero error handling |
| `views/GameView.lua` | `draw()` | 300+ | Five distinct render modes, camera transforms, and a dozen state reads fused into one function |
| `views/WorldSandboxView.lua` | `draw()` | 260 | Map rendering, city markers, POI markers, biome legend, and hover tooltip — one function |
| `services/WorldNoiseService.lua` | `generate()` | 413+ | Height generation, mountain overlay, edge masking, river tracing, lake filling, and biome assignment — all one function |
| `services/PathfindingService.lua` | `findVehiclePath()` | 224 | Two completely different pathfinding algorithms (road-node and sandbox) sharing a single function body |
| `controllers/SandboxController.lua` | `generate()` | 108 | Parameter validation, global constant mutation, service calls, flood fill, and downtown detection |
| `controllers/SandboxController.lua` | `regenerate_region()` | 110 | Repeats the same constant-mutation pattern as `generate()` |
| `models/vehicles/vehicle_states.lua` | `buildSmoothPath()` | 83 | Path smoothing with 6+ nested loops |
| `models/vehicles/Vehicle.lua` | `_resolveOffScreenState()` | 84 | 10-branch if-elseif state resolver in a while loop |
| `models/vehicles/Vehicle.lua` | `updateAbstracted()` | 80 | Mixed state transitions and movement logic |
| `views/WorldSandboxSidebarManager.lua` | `handle_mouse_down()` | 107 | 20+ sequential button checks, no dispatch pattern |
| `views/UIManager.lua` | `_doLayout()` | 68 | 100+ UI element positions, all hardcoded inline |
| `main.lua` | `love.load()` | 156 | Initializes 30+ systems in sequence with no modularity |
| `controllers/UIController.lua` | `handleMouseDown()` | 72 | 4 accordions × header + scroll + content checks, all sequential |

### world gen specifics

| File | Function | ~Lines | Issue |
|------|----------|--------|-------|
| `services/WFCZoningService.lua` | `_generateCoarseZones()` | 90 | Zone init, seed placement, growth, fill, and cleanup all in one pass |
| `services/ArterialRoadService.lua` | `_calculateArterialPaths()` | 81 | Cost grid creation, boundary finding, quadrant coverage, pathfinding, and smoothing — all inline |
| `services/BlockSubdivisionService.lua` | `_recursiveSplitBlock()` | 65 | Split decisions, direction logic, block creation, and recursion combined |
| `models/generators/districts.lua` | `ensureMinimumBoundaryRoads()` | 60+ | Horizontal and vertical sides handled in near-duplicate inline blocks |

---

## 3. Worst Duplication

### Street services — identical code copied 3 times

`GrowthStreetService`, `OrganicStreetService`, and `RadialStreetService` each define identical `write_road()` and `draw_line()` functions. That's ~45 lines of exact duplicates. A bug fix requires three edits. All three also independently do `Game.street_segments = {}` without `Game` being a declared parameter.

### Highway generators — near-identical files

`highway_ew.lua` and `highway_ns.lua` are ~95% the same. The entire `createFlowingPath()` algorithm is duplicated. The only meaningful difference is one line controlling curve axis preference. No shared base.

### Biome logic — three nearly-identical functions in WorldNoiseService

`biome_name_climate()`, `biome_color_climate()`, and `biome_color()` implement the same nested if-else tree three times. A change to biome definitions requires updating all three.

### Constant save/restore — copy-pasted twice in SandboxController

The exact same 8-line block that saves and restores `Game.C.MAP` constants appears in both `generate()` and `_buildFloodFill()`. Should be one helper method.

### Input dispatch — same 3-line branch in 6 event handlers

`main.lua` checks `world_sandbox → sandbox → input_controller` inside every single input handler (`keypressed`, `mousepressed`, `mousereleased`, `mousemoved`, `textinput`, `mousewheelmoved`).

### Debug overlay toggles — 8 copy-pasted key handlers

`InputController` has 8 structurally identical handlers for debug overlay keys (b, p, g, v, n, m, j, o). Should be a table and a loop.

### Other duplications noted

- `_createEmptyGrid()` exists in both `MapGenerationService` and `NewCityGenService`
- `_deepCopyParams()` in `MapGenerationService` is a generic deep-copy that should be a utility
- Road drawing (`_drawThickLineColored`) and spline generation appear in multiple services
- `downtown.lua` and `districts.lua` implement the same "cross road + perpendicular growth" algorithm independently
- `_findBestDistrictLocation()` and `_scoreDistrictLocation()` in `WFCZoningService` repeat the same if-else structure across all 13 zone types

---

## 4. MVC Violations

### Models mutating the Game global directly

- `Map.lua:143–175` — sets `Game.active_map_key`, mutates `Game.camera`, fires `Game.EventBus`
- `UpgradeSystem.lua:155` — `local game = Game` then directly modifies `game.C.VEHICLES.BIKE.speed` and iterates live vehicles
- All three street services — `Game.street_segments = {}` without `Game` being passed as a parameter
- `EntityManager.lua:97–115` — performs coordinate translation and game state mutation inside `handle_click()`
- `Client.lua:24` — directly inserts into `game.entities.trips.pending`

### Views doing business logic or mutating state

- `UIManager._calculatePerSecondStats()` — **mutates** `game.state.income_history` and `game.state.trip_creation_history` from inside a view
- `WorldSandboxView.draw()` — derives biome names from elevation thresholds inline in the render function
- `Modal.lua:92–105` — filters upgrade nodes by prerequisites and calculates costs in the view layer
- `ZoomControls.lua` — metro license gating logic embedded in `draw()`
- `EventSpawner.lua:54–66` — contains a `draw()` method (rendering logic in a model)

### Controllers doing model work

- `WfcLabController.keypressed()` — writes to `Game.lab_grid`, `Game.wfc_final_grid`, `Game.lab_zone_grid`, `Game.smooth_highway_overlay_paths`, and more on nearly every keypress
- `SandboxController.sendToGame()` — 65 lines of direct Game state mutation: replaces maps, resets vehicle state, drops and recreates clients
- `GameController:update()` — directly sets `self.game.debug_mode` (line 262)
- `InputController` — directly mutates `self.game.state.money` for cheat codes with no validation

### Config with side effects

- `GameConfig._onConfigChanged()` directly calls `love.window.setMode()` and `love.window.setFullscreen()` — config module should emit events, not call graphics APIs

---

## 5. Global State Abuse

The `Game` global is the dependency hub for every system. Nothing is injected; everything reaches out and grabs it. This makes every system impossible to test in isolation.

**Specific anti-patterns found:**

- `InputController` creates a **new `UIController` instance on every mouse click** (line 108) instead of reusing one
- `UIView.lua` calls `require()` inside `draw()` — every frame, every render
- `Camera.lua` creates a **new `CoordinateSystem` instance on every call** to `screenToWorld()`
- `WfcLabController.keypressed()` has zero error handling — any service failure leaves Game in a corrupted partial state with no recovery
- `SandboxController` and `WfcLabController` temporarily **mutate `Game.C.MAP` constants** during generation. If an exception fires mid-generation, the restore block never runs and constants stay corrupted for the rest of the session
- `ErrorService` uses module-level mutable state (`log_entries`, `error_counts`) — non-reentrant, impossible to reset between tests
- `AutoDispatcher` uses `goto continue` (line 49) and a debug-spam prevention flag (`debug_logged_running`) — both are workarounds for poor structure

---

## 6. Magic Numbers

No central config file for generation parameters. Numbers are scattered everywhere with no explanation of what they mean or what breaks if you change them.

**Worst clusters:**

| File | Examples | Count |
|------|----------|-------|
| `RoadSmoother.lua` | `-0.7`, `-0.5`, `100003` (hash seed) | 8+ |
| `controllers/WorldSandboxController.lua` | `DT_RADIUS=6`, `*3` sub-cell scale, `*1000` region key, `*100000` plot key | 7+ |
| `services/GrowthStreetService.lua` | `0.6`, `0.12`, `0.8`, `0.4`, `6` | 5+ |
| `models/generators/ringroad.lua` | `2.0`, `-0.7`, `0.1`, `0.15`, `avg_radius=100` | 5+ |
| `services/ArterialRoadService.lua` | `/75`, `*150`, `*1.0`, boundary costs `5/150/20` | 5+ |
| `models/generators/highway_ew.lua` / `ns.lua` | `100`, `1.5`, `40`, `0.7` | 4+ each |
| `services/WfcBlockService.lua` | `1e9`, `100`, `50`, `10`, `1` (weight ladder) | 4+ |
| All view files | Every pixel position, every RGB color, every accordion height | 25+ |

**Notable specific cases:**
- `GameController:127` and `GameConfig:127` — both use `500000` as a memory threshold. Is it bytes, KB, or MB? Neither says.
- `WfcBlockService` — `ARTERIAL_MULTIPLIER = 1e9` with no comment
- `BlockSubdivisionService` — recursive depth limit of `12` hardcoded, "force split for large blocks" at `8+` cells
- `ringroad.lua` — `calculateArcDistance()` uses `avg_radius = 100` hardcoded instead of the actual ring size

There is no `WorldGenConfig.lua` or equivalent. All generation tuning requires reading and editing source code.

---

## 7. World Gen Specific Issues

### WorldNoiseService

- `generate()` is 413+ lines combining noise, hydrology, and biome logic
- Three near-identical biome functions (`biome_name_climate`, `biome_color_climate`, `biome_color`) with the same 9-level if-else tree
- Box-blur pass is O(n² × r²) — slow for large maps
- River tracing loop has no iteration cap

### WFCZoningService

- Color data (a view concern) is baked into zone model definitions
- Adding a new zone type requires updating `ZONES`, `ZONE_CONSTRAINTS`, `ADJACENCY`, `_findBestDistrictLocation()`, and `_scoreDistrictLocation()` — all separately
- Magic cleanup passes: 2 blob-grow iterations, 5 cleanup passes, hardcoded

### ArterialRoadService

- First arterial hardcoded to pass through downtown (`if i == 1`)
- Second arterial hardcoded to pass through largest district (`if i == 2`)
- Cannot scale to 3+ arterials without a code change
- Fix: replace with a constraint configuration array

### BlockSubdivisionService

- Vertical and horizontal split logic are near-identical blocks — bug fixes must be made twice
- Stores results directly in `Game.street_segments` and `Game.street_intersections` instead of returning them
- `ZONE_BLOCK_SIZE_FACTORS` embeds 13 zone types inline with arbitrary divisors ranging 10–60

### PathfindingService

- `findVehiclePath()` handles two completely different map types in one 224-line body
- BFS snap logic repeated with slightly different criteria in two places
- `9999` used as "impassable" cost, `1000` as iteration cap — both magic

### lib/wfc.lua

- O(n) scan for minimum entropy cell on every iteration — should be a priority queue
- No way to distinguish "no solution found" from "contradiction"

---

## 8. What's Actually Fine

Not everything is a problem. These are clean and well-designed:

- `core/event_bus.lua` — minimal, correct pub/sub
- `conf.lua` — perfect
- `lib/wfc.lua` — small and readable (minor perf issue only)
- `views/components/Accordion.lua` — well-structured reusable component
- `views/components/Slider.lua` — clean
- `views/components/TextInput.lua` — clean
- `services/ErrorService.lua` — mostly solid, minor structural issues
- `models/VehicleFactory.lua` — simple factory, correct

---

## 9. Priority Repair List

### Fix immediately — broken code

1. `GameConfig._parseSimpleJson()` — replace with `dkjson` or equivalent; user configs are currently silently ignored
2. `core/time.lua` — implement `update()` and track `total_time`
3. `GameState.lua` — delete the duplicate `isUpgradeAvailable()` (lines 82–94)
4. `models/generators/road_generator.lua` — determine what this file is supposed to contain
5. `WfcBlockService.lua` — add E and S direction road segment extraction

### Fix for sanity — highest impact on maintainability

6. **Split `RoadSmoother.lua`** into three files: chain walker, RDP simplifier, Chaikin smoother
7. **Merge `highway_ew.lua` + `highway_ns.lua`** into one parameterized `HighwayGenerator.lua`
8. **Create `StreetServiceBase.lua`** — shared `write_road()`, `draw_line()`, and `street_segments` reset for all three street services
9. **Split `WorldNoiseService.generate()`** into separate phase functions: height, mountains, rivers, biomes
10. **Split `PathfindingService.findVehiclePath()`** into `findVehiclePathRoadNode()` and `findVehiclePathSandbox()`
11. **Fix `ArterialRoadService`** — replace `if i == 1 / if i == 2` with a constraint config array
12. **Extract biome logic** — replace three duplicate functions with one lookup-table-driven function
13. **Move `UIManager._calculatePerSecondStats()` to a service** — views must not mutate game state
14. **Stop mutating `Game.C.MAP` constants** in `SandboxController` — pass params explicitly or clone a config object
15. **Create `WorldGenConfig.lua`** — extract and document every magic number in the generation pipeline

### Fix for architecture — long-term health

16. Dependency injection instead of `Game` global hub everywhere
17. `InputController` — instantiate `UIController` once, not on every click
18. `UIView.lua` — move `require()` calls out of `draw()`
19. `WfcLabController.keypressed()` — key-to-handler table instead of 230-line if-else
20. `vehicle_states.lua` — split into per-state files or use table-driven dispatch
21. `Map.lua` — stop mutating `Game.active_map_key` and `Game.camera` from the model
22. `WFCZoningService` — data-driven zone definitions (single source of truth for colors, constraints, weights)
23. All sidebar input handlers — button registry with callbacks instead of sequential if chains

---

## Summary Statistics

| Category | Count |
|----------|-------|
| Critical bugs (broken code) | 6 |
| God functions (50+ lines) | 16 |
| MVC violations | 20+ |
| Files with duplicate code | 8 |
| Magic numbers (undocumented) | 60+ |
| Global Game mutations | 50+ |
| Hard-coded requires in wrong layer | 15+ |
| Files with excessive nesting (5+ levels) | 10 |

**Estimated overall code quality: 5/10**
Functional but fragile. Adding features requires touching many files. Debugging requires understanding the whole system at once. Testing is effectively impossible in the current structure.
