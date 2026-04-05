# Cosmic Courier — Code Issues Audit

> Deep audit focused on anti-patterns, MVC violations, god functions, and coupling problems.

---

## 1. God Functions / Monolithic Code — HIGH

### `WorldSandboxController:sendToGame()` — ~467 lines
**File:** `controllers/WorldSandboxController.lua:1212–1678`

Single function handles world generation, city building, map creation, player initialization, vehicle setup, and unified map construction. Impossible to test individual stages, and any subsystem change touches this function. Should be split into at minimum: `_buildMaps()`, `_initPlayer()`, `_buildUnifiedGrid()`, `_spawnEntities()`.

### `WorldSandboxController:_buildZoneGrid()` — ~258 lines
**File:** `controllers/WorldSandboxController.lua:183–440`

WFC sampling, district type selection, zone segment creation, boundary fixing, and node generation all tangled together in one method.

### `WorldSandboxController:_buildRoadNetwork()` — ~278 lines
**File:** `controllers/WorldSandboxController.lua:579–856`

Road vertex grid creation, highway intersection extraction, boundary street painting, and FFI grid construction — four separate concerns in one function.

### `WorldSandboxController:build_highways()` — ~208 lines
**File:** `controllers/WorldSandboxController.lua:2095–2296`

A* pathfinding logic buried inside highway generation. The pathfinding should delegate to PathfindingService; the MST city connection logic should be its own function.

### `GameView.lua` — 1,541 lines
**File:** `views/GameView.lua`

Six distinct visualization modes jammed into one file:
- `_drawWorldGenMode()` (~line 497)
- `_drawDeliveryDebug()` (~line 882)
- `_drawDistrictOverlay()` (~line 1001)
- `_drawBiomeOverlay()` (~line 1165)
- `_drawUnifiedGridOverlay()` (~line 1287)

Debug overlays especially should be a separate module.

---

## 2. MVC Violations — HIGH

### Models mutating shared game state directly
- **`models/Client.lua:20–32`** — `Client:update()` directly pushes into `game.entities.trips.pending` and publishes events. A model should not write to the entity registry; that belongs in a controller or service.
- **`models/vehicles/Vehicle.lua:106–109`** — `Vehicle:assignTrip()` manipulates its own `trip_queue` directly rather than going through a service interface.

### Controllers mutating state that belongs to services
- **`controllers/InputController.lua:199–208`** — Directly sets `game.state.upgrades.auto_dispatch_unlocked = true` and modifies `game.state.money`. These mutations belong in `UpgradeSystem` or a dedicated service.

### Views reading raw internal state
- **`views/GameView.lua:800–849`** — Accesses `umap.ffi_grid`, `umap._w`, `cmap.world_mn_x`, `cmap._road_smooth_paths_v8` directly. Views should go through a map interface, not reach into implementation fields.
- **`views/UIManager.lua:70`** — Directly accesses `game.state.Upgrades.categories` (also note the capitalisation inconsistency vs `game.state.upgrades` elsewhere).

### Upgrade system reaching into entities
- **`models/UpgradeSystem.lua:177–203`** — `applyStatToGameValues()` directly modifies vehicle objects by calling `VehicleUpgradeService.applySpeedModifier(game.entities.vehicles, ...)`. An upgrade purchase should publish an event; vehicles should react to it. The upgrade system should not hold a reference to the vehicle list.

---

## 3. State Management Problems — HIGH

### Global `Game` table with no ownership
**File:** `main.lua:38–69`

The monolithic `Game` table has 20+ direct fields. There is no clear owner for `Game.camera`, `Game.game_controller`, `Game.entities`, etc. It acts as a service locator / global singleton, which makes dependency tracking impossible.

### Multiple mutation paths to the same state

| State | Modified in |
|-------|-------------|
| `game.state.money` | `InputController`, `UpgradeSystem`, `EventService` |
| `game.state.upgrades.*` | `UpgradeSystem`, `InputController`, `Vehicle:new` |
| `game.entities.trips.pending` | `Client:update()`, `AutoDispatcher`, various services |

Any of these can change the same value with no ordering guarantees.

### World state split between `WorldSandboxController` and `main`
- `WorldSandboxController` holds 60+ instance fields for the generated world
- `main.lua:45–49` holds `maps.city`, `maps.region`, `maps.unified`, `active_map_key`
- `GameController` reads `game.maps[game.active_map_key]`

There is no single authoritative owner for world state.

### Vehicle lifecycle uses mixed paradigms
**File:** `models/vehicles/Vehicle.lua:50–51, 194–200`

The vehicle has a state machine *and* manual flags (`current_path_eta`, simulation mode flags, etc.). These two mechanisms can disagree about what state the vehicle is actually in.

---

## 4. Duplicate Logic — MEDIUM

### Bounding box calculation repeated 3+ times
**File:** `controllers/WorldSandboxController.lua:1236–1241, 1286–1292, 2286–2292`

The same `min/max cx, cy from cell index` pattern is copy-pasted each time a bounding box needs computing. Should be a utility function.

### Road-type checking duplicated
- **`models/Map.lua:32–36`** — `isRoad()` checks 4 tile types
- **`services/PathfindingService.lua`** — Multiple locations independently check tile names

Adding a new road type requires edits in both files.

### Tile type encoding defined twice
- **`controllers/WorldSandboxController.lua:8–11`** — `TILE_INT` table
- **`services/PathfindingService.lua:9–12`** — `_TILE_NAMES` table

Same data, two representations. They will drift.

### Zone segment lookup repeated
**File:** `services/PathfindingService.lua:78–82, 134–138`

The zone segment lookup/check pattern appears in both the snap function and the cost function. Should be extracted.

---

## 5. Anti-Patterns — MEDIUM

### Magic numbers scattered through generation code
**File:** `controllers/WorldSandboxController.lua`

| Location | Value | Meaning |
|----------|-------|---------|
| ~line 1047 | `local DT_RADIUS = 6` | Downtown radius — local constant, not config |
| ~line 1167 | `local r = 18` | Unnamed radius |
| ~lines 2932–2939 | 6 numeric literals | Arterial turn costs and multipliers |
| ~lines 2642–2645 | `SC_DETAIL_FREQ=0.55` etc. | Noise parameters hardcoded in function |

### Massive if/elseif chains
- **`views/GameView.lua:824–841`** — 18-line nested if on tile types with duplicated branch bodies. Should be a dispatch/lookup table.
- **`models/UpgradeSystem.lua:177–203`** — 18-line if/elseif in `applyStatToGameValues()` matching stat name strings. Should be a config-driven map of `statName → applyFn`.

### Vehicle state machine uses magic strings
**File:** `models/vehicles/vehicle_states.lua:140`

State names like `"To Pickup"` are raw strings used as dispatch keys in `STATE_RESOLUTION[name]`. A single typo silently does nothing. Should be constants or an enum table.

### Debug flag explosion
**File:** `main.lua:63–69`

Four separate top-level boolean debug flags (`debug_hide_roads`, `debug_smooth_roads`, `debug_smooth_roads_like`, `debug_smooth_vehicle_movement`) instead of a single debug state object. Hard to audit what debug state the game is in.

### Deeply nested control flow
**File:** `services/PathfindingService.lua:176–267`

HPA* hierarchical routing nests 3+ levels deep for city hops, tier selection, and path segments. The tier logic should be extracted to its own function.

### 126 raw `print()` calls across 29 files

`ErrorService` exists for logging but is used inconsistently. Some errors go to `error_service.logError()`, some to `print("ERROR: ...")`, some fail silently with a bare `return false`. There is no consistent error propagation strategy.

---

## 6. Coupling Issues — MEDIUM

### `WorldSandboxController` constructor initialises 60+ fields
**File:** `controllers/WorldSandboxController.lua:16–149`

UI slider parameters, generation algorithm internals, and visual state are all initialised in the same constructor block. Generation parameters should be a separate config object so they can be changed without touching the controller.

### `GameState` ↔ `UpgradeSystem` circular dependency
**File:** `models/GameState.lua:41`

`GameState` creates `UpgradeSystem` in its constructor. `UpgradeSystem` then references back to `GameState` to read/write money and upgrade values. Neither can be tested independently.

### Zoom thresholds defined in multiple files

| File | Constant |
|------|----------|
| `models/vehicles/Vehicle.lua:88–92` | `BIKE_THRESHOLD`, `ENTITY_THRESHOLD` |
| `views/GameView.lua:27–29` | Several overlay thresholds |
| `views/GameView.lua:64` | `OVERLAY_VECTOR_THRESHOLD = 5.0` |

These should all live in `data/constants.lua`.

---

## 7. Inconsistencies — MEDIUM

### Coordinate system implicit conversions
- `WorldSandboxController` — world cells (1–600)
- `Map` — sub-cells (1–1800, 3× scale)
- `PathfindingService` — converts between both silently
- `Vehicle.lua:38` — multiplies by `tile_pixel_size` to get `px`

No coordinate type is documented. Silent conversion in multiple places is the main source of off-by-one bugs.

### Inconsistent event payload schema
Some events carry structured data (`map_scale_changed` passes `{ camera, active_map_key }`), others carry nothing (`trip_created`). There is no defined schema for event payloads.

### Three near-identical plot-selection methods on Map
`Map:getRandomBuildingPlot()`, `Map:getRandomDowntownBuildingPlot()`, `Map:getRandomCityBuildingPlot()` — same operation with slightly different filters. Should be one method with a filter parameter.

### Capitalisation inconsistency
`game.state.Upgrades.categories` (capital U, in UIManager) vs `game.state.upgrades.*` (lowercase) everywhere else. At least one of these is a bug.

---

## 8. Dead Code / Artifacts — LOW

### Orphaned "REMOVED" comments
- `models/EntityManager.lua:101` — `-- REMOVED THE DRAW FUNCTION FROM HERE`
- `models/Client.lua:35` — same comment
- `models/vehicles/Bike.lua:18` — similar comment

These are left-over debugging breadcrumbs; just delete them.

### Commented-out code blocks
**File:** `models/vehicles/Vehicle.lua:170–175`

An entire if-block commented out. If it's not needed, delete it; if it is, un-comment and fix it.

---

## Priority Order

| Priority | Issue | Why |
|----------|-------|-----|
| 1 | `sendToGame()` god function | Blocks all world-gen work; everything touches it |
| 2 | State mutation ownership | Multiple paths to same state = silent bugs |
| 3 | `TILE_INT` / `_TILE_NAMES` duplication | Will cause tile-type bugs as map grows |
| 4 | MVC: Client/Vehicle writing to shared state | Models should not own the entity registry |
| 5 | Magic numbers in WorldSandboxController | Makes tuning generation fragile |
| 6 | GameState ↔ UpgradeSystem circular dep | Prevents unit testing either |
| 7 | Zoom thresholds scattered | Minor but causes visual inconsistencies |
| 8 | 126 print() calls | Noise in logs, inconsistent with ErrorService |
