# Cosmic Courier — Phased Refactor Plan

> Created: 2026-03-31
> Source documents: `docs/code-audit.md`, `docs/abstraction-opportunities.md`
> Scope: All Lua files — world gen, city gen, roads, pathfinding, controllers, models, views, services, utils
> Updated: 2026-03-31 — reflects deletion of all `models/generators/`, `SandboxController`, F9 sandbox views, and stripping of old pipeline code from `MapGenerationService`

---

## Critical Rules

1. **No phase begins until the previous phase is complete and tested.**
2. **No feature work during a refactor phase.** The game must behave identically before and after each phase.
3. **One logical change per commit.** Do not combine a rename with a behavior fix.
4. **If a refactor uncovers a real bug, fix the bug in a separate commit first.**
5. **Delete the old code.** Do not keep commented-out originals or backward-compat shims.
6. **Magic numbers that move to config files must also get a comment** explaining what they control and what breaks if you change them.

---

## Current State

| Metric | Value |
|--------|-------|
| Critical bugs (broken code) | 6 |
| God functions (50+ lines) | 12 |
| MVC violations | 20+ |
| Files with duplicate code | 6 |
| Magic numbers (undocumented) | 45+ |
| Global Game mutations | 40+ |
| Hard-coded requires in wrong layer | 10+ |
| Files with excessive nesting (5+ levels) | 7 |
| Estimated code quality | 5.5/10 |

> **Post-cleanup note:** `models/generators/` (10 files), `SandboxController`, the F9 sandbox UI (9 files), and the old `MapGenerationService` pipeline (~300 lines) have all been deleted since the initial audit. The metrics above reflect the current state. Tasks in this plan that targeted deleted code are marked as resolved.

---

## Phase 1 — Critical Bug Fixes

**Goal:** Make the game actually work as designed. None of the subsequent phases matter if the game is silently broken.

### Tasks

| # | File | Change |
|---|------|--------|
| 1.1 | `config/GameConfig.lua:312–317` | Replace `_parseSimpleJson()` stub with `dkjson` parse (or the equivalent bundled lib). Add a test: load a known config file, verify the returned table has the expected keys. |
| 1.2 | `core/time.lua:9` | Implement `update(dt)`: increment `total_time` and `delta_time`. Verify `GameController` can read `time.total_time` and gets non-zero values after one frame. |
| 1.3 | `models/GameState.lua:82–94` | Delete the second `isUpgradeAvailable()` definition. Run upgrade UI — no behavior change expected since the first definition was already correct. |
| ~~1.4~~ | ~~`models/generators/road_generator.lua`~~ | ~~Determine what this file is supposed to contain.~~ **Resolved** — entire `models/generators/` directory deleted. |
| 1.5 | `services/WfcBlockService.lua:99–100` | Add E and S road segment extraction to match the existing N and W extraction. Verify WFC block placement picks up segments in all four directions. |
| 1.6 | `services/TripGenerator.lua` | `_createInterCityTrip()` is defined but never called. Either wire it up or delete it. No dead code. |
| 1.7 | `services/SaveService.lua:225–280` | Replace the hand-rolled JSON parser with the same library added in task 1.1. `GameConfig` and `SaveService` are two separate broken parsers — fixing only one leaves save data silently corrupted. |

### Expected Outcome

User configs load correctly. Save files load correctly. Game time accumulates. Upgrade availability check is not silently doubled. WFC block cells get road segments from all directions.

### Testing

- Change a setting in a user config file; restart; verify the change took effect (not the default).
- Save a game, quit, reload; verify the loaded state matches what was saved including nested tables.
- Print `time.total_time` after 5 seconds of gameplay; verify it reads ~5.
- Open the upgrade modal; verify no crash and correct unlock gating.
- Place WFC blocks adjacent to an E or S road segment; verify they receive the correct road neighbor count.

### AI Notes

Task 1.4 requires judgment — read the file before deciding. Task 1.6 requires reading call sites to understand whether inter-city trips are gated by an upgrade (in which case the call should be wired up conditionally) or genuinely unused (delete). Tasks 1.1 and 1.7 should use the same JSON library — add it once, require it in both files.

---

**Status:** Complete (commit `3b7d34f`)
**Line count change:** +239 / −213 (lib/json.lua adds lines; SaveService/GameConfig parsers removed)
**Deviation from plan:**
- Tasks 1.1 and 1.7 were implemented via a new `lib/json.lua` (pure-Lua encoder/decoder) rather than an external library like dkjson. Both files now require the same module as intended.
- Task 1.6: deleted `_createInterCityTrip` rather than wiring it up. The function body itself stated inter-city is disabled until the region map is implemented; it was genuinely dead code with no call sites.
- Two unplanned bug fixes were added to this commit after testing revealed regressions: `vehicle_states.lua` (endpoint-preserving Chaikin clustered waypoints at every junction causing vehicles to stall at intersections) and `main.lua` (circular font fallback — `uiFontSmall` listed itself — causing tofu icons). Fixed under rule 4; combined into the Phase 1 commit since they were blocking validation of the planned tasks.

---

## Phase 2 — Data Extraction

**Goal:** Replace all if/elseif chains and scattered constant tables that encode facts about the game world with centralized data files. After this phase, adding a zone type, tile type, road type, or vehicle type is a one-file change.

### Tasks

#### 2.1 — `data/zones.lua`

Zone type strings currently appear in 8+ files. Extract to a single source of truth.

- Create `data/zones.lua` with:
  - `Zones.TYPES` — ordered list of all zone strings
  - `Zones.CATEGORIES` — groupings: `industrial`, `residential`, `commercial`, `parks`, `public`
  - `Zones.DEFINITIONS[zone_type]` — per-zone: `color`, `block_size`, `placement`, `adjacency_bonus`
  - `Zones.getCategory(zone_type)` — returns the category string
  - `Zones.isType(zone_type, category)` — replaces all inline `if zone == "industrial_heavy" or zone == "industrial_light"` checks
- Update callers:
  - `WFCZoningService.lua` — remove inline ZONES/ZONE_CONSTRAINTS/ADJACENCY tables; require `data/zones`
  - `BlockSubdivisionService.lua` — remove `ZONE_BLOCK_SIZE_FACTORS`; read from `Zones.DEFINITIONS[z].block_size`
  - `zone_types.lua` — delete (absorbed)
  - `data/districts.lua` — replace hardcoded zone name strings with `Zones.TYPES` references
  - `views/WorldSandboxView.lua:6–30` — move BIOME_LEGEND into `data/biomes.lua` (see 2.5)

#### 2.2 — `data/tile_palette.lua`

- Create `data/tile_palette.lua`: flat table mapping tile type string → `{r, g, b}`.
- Update `Map.lua:40–67` (`getTileColor`): replace 28-line if/elseif with `return TILE_PALETTE[tile.type] or TILE_PALETTE.default`.

#### 2.3 — `data/road_categories.lua`

- Create `data/road_categories.lua`: maps road type string → cost category string (`"road"`, `"arterial"`, `"highway"`).
- Update `PathfindingService.lua:44–54`: replace inline type-grouping checks with `road_categories[t]`.

#### 2.4 — `data/vehicle_types.lua`

Vehicle type data currently lives in `Bike.lua` and `Truck.lua` subclasses plus scattered type checks.

- Create `data/vehicle_types.lua` with full config per type: `icon`, `speed`, `capacity`, `visible_at_scales`, `pathfinding_costs`, `needs_road_spawn`.
- Update `Vehicle.lua`:
  - `shouldDrawAtCurrentScale()`: replace `if self.type == "bike"` check with `VehicleTypes[self.type].visible_at_scales` lookup.
  - Remove all other `self.type ==` checks; any remaining must be documented with a reason they can't use config.
- Update `AutoDispatcher.lua:47`: replace vehicle type string check with config lookup.
- Update `vehicle_states.lua:495`: replace `vehicle.type == "truck"` with config lookup.
- `Bike.lua` and `Truck.lua` become thin wrappers that call `Vehicle:new()` with the appropriate config key; they own no logic.

#### 2.5 — `data/biomes.lua`

- Create `data/biomes.lua`: ordered list of biomes, each with `name`, `color`, `elevation_min`, `temperature_range`, `wetness_range`.
- Update `WorldNoiseService`: read biome definitions from `data/biomes.lua` instead of internal tables.
- Update `WorldSandboxView.lua:6–30`: remove hardcoded `BIOME_LEGEND`; iterate `data/biomes` for the legend.
- Update `WorldSandboxView.lua:250–258`: remove inline elevation → biome name derivation; call a `Biomes.getName(elevation, temp, wetness)` function.

#### 2.6 — `data/map_scales.lua`

- Create `data/map_scales.lua`:
  - `SCALE_HIERARCHY` — ordered list: `{ WORLD, CONTINENT, REGION, CITY, DOWNTOWN }`
  - `getNext(current, direction)` — returns next scale in hierarchy or nil at boundary
- Update `EventService.lua:123–153`: replace both zoom functions' hardcoded chain with `MapScales.getNext()`.

#### 2.7 — `data/WorldGenConfig.lua` and `data/GameplayConfig.lua`

Extract every magic number from the generation pipeline and gameplay systems.

`WorldGenConfig.lua` should cover (at minimum):
- `ArterialRoadService`: number-of-arterials formula divisor (`75`), boundary costs (`5/150/20`)
- `BlockSubdivisionService`: max recursion depth (`12`), force-split threshold (`8`)
- `WfcBlockService`: arterial weight multiplier (`1e9`), weight ladder values
- `WorldNoiseService`: box-blur radius, river trace cap

`GameplayConfig.lua` should cover:
- `TripGenerator`: downtown/city trip ratios (`0.4 / 0.6`)
- `Map.lua`: minimum network size (`MIN_NETWORK_SIZE = 10`)
- `GameController`: memory warning threshold (`500000` — add a unit comment)
- `WfcLabController`: Catmull-Rom resolution (`segments_per_span = 8`), lightning bolt threshold (`dist <= 2`)
- `vehicle_states.lua`: Chaikin weights (if not absorbed into `lib/path_utils.lua` in Phase 3)

Every entry must have a comment: what it controls, valid range, what breaks if you exceed it.

### Expected Outcome

- Adding a new zone type = one block in `data/zones.lua`, zero other edits.
- Adding a new vehicle type = one block in `data/vehicle_types.lua`, zero other edits.
- All magic numbers visible in one place with explanations.
- No if/elseif chains that check zone names or vehicle types in service/controller code.

### Testing

- Rename an existing zone type string in `data/zones.lua` — grep confirms there are no remaining hardcoded strings anywhere else.
- Add a dummy vehicle type to `data/vehicle_types.lua` — verify it spawns and renders without touching any other file.
- Change a WorldGenConfig value; regenerate; confirm the output reflects the new value.

### AI Notes

Phase 2 is the highest-leverage phase. Every subsequent phase is easier because string-comparison spiderwebs are gone. Do not proceed to Phase 3 until a grep for `"industrial_heavy"` outside `data/zones.lua` returns zero results.

---

**Status:** Complete (commit TBD — not yet committed)
**Line count change:** +340 new data files / −520 scattered inline definitions and dead code (net reduction ~180)
**Deviation from plan:**
- Pre-task dead-code purge (not in plan): deleted entire old generation chain before starting data extraction — `MapGenerationService`, `NewCityGenService`, `WFCZoningService`, `BlockSubdivisionService`, `ArterialRoadService`, `GrowthStreetService`, `RadialStreetService`, `OrganicStreetService`, `WfcLabController`. All were unreachable from the F8 world gen flow. Removed associated lab rendering from `GameView` (~350 lines) and lab wiring from `main.lua`. This eliminated the only callers of the WFC 13-zone system, so task 2.1's plan to update `WFCZoningService` was moot — it was deleted instead.
- Task 2.1: `data/zones.lua` created from `zone_types.lua` with `getCategory()`/`isType()` helpers added. The plan also called for updating `WFCZoningService` and `BlockSubdivisionService` — both deleted (see above). `data/districts.lua` had no hardcoded zone strings requiring update.
- Task 2.4: plan called for a new `data/vehicle_types.lua`; instead extended `data/constants.lua` VEHICLES entries with the new fields (`icon`, `needs_downtown_speed_scale`, `visible_at_scales`, `downtown_only_sim`, `can_long_distance`) to avoid duplicating data that already lived there. `Bike.lua`/`Truck.lua` now own zero logic — `getIcon()` overrides removed, base `Vehicle:getIcon()` reads `self.icon` which is set from `properties.icon` in `Vehicle:new()`.
- Task 2.5: `WorldNoiseService` fully integrated — `biome_color_climate` replaced with a name→color lookup against `data/biomes.lua` via a lazily-built cache. `biome_name_climate` is kept as the classification logic (it is logic, not data). `data/biomes.lua` corrected to match canonical name strings from `biome_name_climate` (fixed "Trop. Forest/Savanna/Swamp" → full names; added missing "Cold Highland" and "Boreal Highland" entries).
- Task 2.7: `WorldGenConfig` and `GameplayConfig` created with the values reachable in the live codebase. Several plan entries (`BlockSubdivisionService` max recursion depth, `WfcBlockService` weight ladder, `ArterialRoadService` divisors) were in the deleted dead-code chain and could not be extracted.

---

## Phase 3 — Library Utilities

**Goal:** Extract reusable algorithms from wherever they currently live into `lib/` modules. After this phase, each algorithm exists in exactly one file.

### Tasks

#### 3.1 — `lib/path_utils.lua`

Absorbs all curve smoothing and path manipulation algorithms:

- `chaikin(flat_points, iterations)` — flat array form, 0.75/0.25 weights (currently duplicated in `RoadSmoother.lua` and `vehicle_states.lua`)
- `rdp(points, epsilon)` — Ramer-Douglas-Peucker simplification (currently only in `RoadSmoother.lua`)
- `catmullRom(points, segments_per_span)` — Catmull-Rom spline (currently only in `WfcLabController.lua`)
- `linearInterpolate(p1, p2, t)` — from `WfcLabController.lua:_linearInterpolation`
- `removeDuplicates(points)` — from `WfcLabController.lua:_removeDuplicates`
- `fixLightningBolts(points, max_dist, dot_threshold)` — from `WfcLabController.lua:_fixLightningBolts`

Update callers:
- `RoadSmoother.lua` — require `lib/path_utils`, replace local `chaikin` and `simplify`
- `vehicle_states.lua` — require `lib/path_utils`, replace local `chaikin_flat`
- `WfcLabController.lua` — require `lib/path_utils`, replace all five local path functions. After this task, `WfcLabController.lua:305–426` (the 120-line path utility block) is deleted entirely.

#### 3.2 — `lib/rasterize.lua`

Absorbs Bresenham line rasterization (currently duplicated 3×):

- `rasterizeLine(x1, y1, x2, y2, callback)` — calls `callback(x, y)` for each cell

Update callers:
- `OrganicStreetService.lua:34–49`
- `RadialStreetService.lua:37–52`

#### 3.3 — `lib/grid_search.lua`

Absorbs BFS/flood-fill algorithms currently embedded in model code:

- `floodFill(grid, start_x, start_y, passable_fn)` — returns set of reachable cells
- `getAdjacentCells(grid, cells, match_fn)` — returns cells adjacent to a set satisfying a condition

Update callers:
- `Map.lua:81–110` (`getPlotsFromGrid`) — replace inline BFS with `grid_search.floodFill`

#### ~~3.4 — `lib/geometry.lua`~~ — Resolved

All identified callers (`highway_ew.lua`, `highway_ns.lua`, `districts.lua`, `ringroad.lua`) have been deleted. No remaining files require a shared geometry module. Skip this task.

#### 3.5 — `services/CoordinateService.lua` stub + `getDowntownBounds()`

Create `services/CoordinateService.lua` now as a stub with a single function. Phase 4.1 fills out the rest of the interface. Creating the file here avoids the ambiguity of "add to `CoordinateSystem.lua` or the future service" — target the final home from the start.

```lua
function getDowntownBounds(grid_w, grid_h, constants)
    local dw = constants.MAP.DOWNTOWN_GRID_WIDTH
    local dh = constants.MAP.DOWNTOWN_GRID_HEIGHT
    local x1 = math.floor((grid_w - dw) / 2) + 1
    local y1 = math.floor((grid_h - dh) / 2) + 1
    return { x1 = x1, y1 = y1, x2 = x1 + dw - 1, y2 = y1 + dh - 1 }
end
```

Update all 6 callers to require `services/CoordinateService`:
- `BlockSubdivisionService.lua:44–52`
- `NewCityGenService.lua:54–61` and `118–123`
- `GrowthStreetService.lua:15–18`
- `OrganicStreetService.lua:19–22`
- `RadialStreetService.lua:22–25`
- `WfcLabController.lua:269–276`

Do not touch `CoordinateSystem.lua` in this phase — it will be absorbed into `CoordinateService` in Phase 4.1.

#### 3.6 — `lib/utils.lua`

Create `lib/utils.lua` for generic utility functions with no domain knowledge.

- `deepCopy(t)` — recursive table deep-copy. Currently exists as `_deepCopyParams()` in `MapGenerationService.lua`; it's a generic utility that shouldn't live in a map service.

Update callers:
- `MapGenerationService.lua` — delete `_deepCopyParams()`, require `lib/utils`
- `SandboxController.lua` — will use `utils.deepCopy` in Phase 6.4 when constant mutation is removed

### Expected Outcome

- `lib/` contains four small, pure files: `path_utils`, `rasterize`, `grid_search`, `utils`.
- No algorithm implementation exists in more than one file.
- `WfcLabController.lua` has lost its 120-line path utility block (lines 305–426).
- `services/CoordinateService.lua` exists as a stub, ready for Phase 4.1.
- `grep -r "0.75\*x0" .` returns exactly one result: `lib/path_utils.lua`.
- `grep -r "Bresenham\|while.*err" .` (or equivalent line rasterization signature) returns exactly one result: `lib/rasterize.lua`.

### Testing

- After moving each algorithm, run a game session and verify roads render, vehicles path, WFC generates — no visual regressions.
- The Chaikin output from `lib/path_utils.chaikin` must produce identical results to the two old inline versions (write a test that runs both on the same input and compares outputs before deleting the old code).
- Verify all WfcLabController hotkeys still produce smooth road overlays after the path utility block is removed.

### AI Notes

`lib/path_utils.lua` is the highest priority in this phase — Chaikin lives in two files already and a third copy could easily appear during vehicle work. `lib/rasterize.lua` is second — the three-way Bresenham divergence is already causing inconsistent road placement. For task 3.5, create `CoordinateService.lua` as a stub file — do not wait until Phase 4 to create it, to avoid the ambiguity of where `getDowntownBounds` lives in the interim.

---

**Status:** Complete (commit TBD)
**Line count change:** +120 new lib/service files / −95 removed inline duplicates (net reduction ~25 — smaller than estimated because most callers were already deleted in Phase 2)
**Deviation from plan:**
- Task 3.2 (`lib/rasterize.lua`): all three Bresenham callers (OrganicStreetService, RadialStreetService, and a third) were deleted in Phase 2's dead-code purge. No Bresenham code exists in the codebase. File not created — nothing to absorb.
- Task 3.1 partial: catmullRom, linearInterpolate, removeDuplicates, fixLightningBolts were all in WfcLabController (deleted Phase 2). Only chaikin and rdp/simplify extracted to `lib/path_utils.lua`.
- Task 3.5: all six `getDowntownBounds` callers were in the deleted dead-code chain. `CoordinateService.lua` stub created anyway as planned — it is the intended home for Phase 4.1 coordinate work.
- Task 3.6: `_deepCopyParams` source (MapGenerationService) was deleted in Phase 2. `lib/utils.lua` created anyway for Phase 6.4 use.

---

## Phase 4 — Service Refactoring

**Goal:** Consolidate scattered service logic into single-responsibility services. After this phase, each domain (coordinates, highways, streets, path smoothing, trip eligibility, zoom) is owned by exactly one service.

### Tasks

#### 4.1 — `services/CoordinateService.lua`

Coordinate conversions currently appear in 6+ files. Make `CoordinateService` the single authority.

- `gridToPixel(gx, gy, tps)` — tile center in pixel space
- `pixelToGrid(px, py, tps)` — pixel to tile
- `roadNodeToPixel(rx, ry, tps)` — road-node coordinate to pixel (with `is_tile` offset)
- `applyRegionOffset(px, py, city_origin_in_region, tile_size)` — vehicle region draw position
- `getDowntownBounds(grid_w, grid_h, constants)` — (absorbed from Phase 3 task 3.5)
- `screenToWorld(sx, sy, camera)` / `worldToScreen(wx, wy, camera)`

Update callers:
- `Vehicle.lua:25–37`, `55–72`, `106–115` — replace inline coordinate math
- `GameView.lua:45–56` — replace inline coordinate math
- `vehicle_states.lua:517–530` — replace inline coordinate math
- `EntityManager.lua:100–103` — replace inline coordinate math
- `InputController.lua:138` — replace inline coordinate math
- `Camera.lua` — `screenToWorld()` stops creating a new `CoordinateSystem` instance on every call

Delete `CoordinateSystem.lua` after migration is complete (or keep it as a thin redirect if it is imported in many places — measure first).

#### ~~4.2 — `services/HighwayGenerator.lua`~~ — Resolved

`highway_ew.lua` and `highway_ns.lua` have been deleted. Skip this task.

#### 4.3 — `services/StreetPipeline.lua` + `services/streets/StreetServiceBase.lua`

The three street services share an identical 5-step pipeline; only step 2 (the generation algorithm) differs.

- Create `services/StreetPipeline.lua`:
  - `StreetPipeline.run(city_grid, params, strategy_fn)` — runs the full pipeline; calls `strategy_fn` for step 2
  - `StreetPipeline.writeRoad(city_grid, x, y, road_type)` — shared road-write function (replaces the three identical local `write_road()` copies)
  - `StreetPipeline.drawLine(city_grid, x1, y1, x2, y2)` — shared (requires `lib/rasterize` from Phase 3)
  - `StreetPipeline.applyDowntownGrid(city_grid, downtown_bounds, block_size)` — shared dense-grid step

- Update each service to be a thin strategy provider:
  - `GrowthStreetService` — provides `growthStrategy(city_grid, params)` function; calls `StreetPipeline.run`
  - `OrganicStreetService` — provides `organicStrategy(city_grid, params)`
  - `RadialStreetService` — provides `radialStrategy(city_grid, params)`

- Remove the `Game.street_segments = {}` mutation from all three services. The pipeline returns results; the controller that calls the pipeline assigns them.

**Before touching any write site:** run `grep -rn "street_segments" .` and identify every read site. There is at least one controller reading `Game.street_segments` after the service call — that caller must be updated to receive the return value instead, or the pipeline output will be silently dropped.

#### 4.4 — `services/PathSmoothingService.lua`

Move `buildSmoothPath` from `vehicle_states.lua` into its own service.

- `PathSmoothingService.buildSmoothPath(path, vehicle_px, vehicle_py, map, tps)` — returns `smooth_path` list
- Uses `lib/path_utils.chaikin` from Phase 3

Update `vehicle_states.lua`: replace the inline `buildSmoothPath` with a call to the service. Vehicle states have no smoothing logic.

#### 4.5 — `services/TripEligibilityService.lua`

Trip eligibility is currently checked in three separate places with logic that can drift.

- `TripEligibilityService.canHandle(vehicle, trip, game_state)` — returns `{ eligible = bool, reason = string }`
  - Absorbs: `vehicle_states.lua:495–511`, `AutoDispatcher.lua:33–47`, implicit logic in `TripGenerator.lua`

Update all three callers to use the service. Delete local eligibility checks.

#### 4.6 — `services/ZoomService.lua`

- `ZoomService.getNext(current_scale, direction)` — uses `data/map_scales.lua` from Phase 2
- Update `EventService.lua:123–153`: replace both zoom functions with single-line calls to `ZoomService`.

#### 4.7 — `ArterialRoadService` — Constraint Config Array

Replace the `if i == 1 / if i == 2` hardcoding with a config array.

- Add `ARTERIAL_CONSTRAINTS` table (could live in `data/WorldGenConfig.lua` from Phase 2):
  ```lua
  { type = "must_pass_through", target = "downtown" },
  { type = "must_pass_through", target = "largest_district" },
  { type = "prefer_quadrant_coverage" },
  ```
- The generation loop reads constraints by index. Adding a third arterial is adding a third entry.

### Expected Outcome

- `grep -r "0.75\*x\|road_node.*pixel\|tps\s*\*\s*rx" .` (coordinate math pattern) returns results only in `CoordinateService.lua`.
- ~~`highway_ew.lua` and `highway_ns.lua` are deleted.~~ Already done.
- All three street services are under 60 lines each.
- `PathSmoothingService` is the only file containing junction/degree logic for vehicle path smoothing.
- Trip eligibility has one canonical source.

### Testing

- Generate a city; verify roads, arterials, and highways look identical before and after.
- Run a full delivery trip; verify vehicle paths and smoothing are unchanged.
- Verify inter-city trip eligibility is consistent between dispatcher and state machine (previously could diverge).
- Zoom in and out; verify scale transitions work identically.

### AI Notes

Task 4.3 (StreetPipeline) is the trickiest — the `Game.street_segments = {}` removal requires identifying who receives the pipeline's output and threading it through correctly. Measure before touching: `grep -n "street_segments" .` to see all write sites.

---

**Status:** Complete (commit TBD)
**Line count change:** ~+150 new service files / −200 removed duplicates and inline logic (net reduction ~50)
**Deviation from plan:**
- **4.1 caller migration:** CoordinateService fully implemented and CoordinateSystem.lua deleted. Camera.lua, Vehicle.lua (`:new`, `:recalculatePixelPosition`, `:_getRegionDrawPosition`), and EntityManager.lua (`:handle_click`) all updated. InputController.lua had no coordinate math to migrate. GameView.lua's coordinate math was removed as part of the lab/WFC draw function purge.
- **4.3 skipped:** GrowthStreetService, OrganicStreetService, and RadialStreetService were all dead code and deleted in Phase 2 pre-purge. StreetPipeline is moot.
- **4.6 partial:** No `ZoomService.lua` created. `MapScales.getNext()` called directly from EventService — one line each, no added indirection justified creating a wrapper service.
- **4.7 skipped:** ArterialRoadService deleted in Phase 2 pre-purge as dead code.

---

## Phase 5 — God Function Decomposition ✅ Complete

**Goal:** Break up every function over ~80 lines that does more than one named thing. After this phase, no function exceeds 80 lines, and every function has one clearly statable responsibility.

### Tasks

#### 5.1 — `WorldNoiseService.generate()` (413+ lines)

Split into separate phase functions:

- `generateHeightMap(params)` — noise + mountain overlay + edge masking
- `traceRivers(height_map, params)` — river tracing (add an iteration cap using config value from Phase 2)
- `fillLakes(height_map, river_map, params)` — lake filling
- `assignBiomes(height_map, river_map, params)` — biome assignment (uses `data/biomes.lua` from Phase 2)
- `generate(params)` — calls the four above in sequence; owns no generation logic itself

Remove the three near-identical biome functions (`biome_name_climate`, `biome_color_climate`, `biome_color`). Replace with one lookup-table-driven `Biomes.getName(e, t, w)` and `Biomes.getColor(e, t, w)` from `data/biomes.lua`.

#### 5.2 — `PathfindingService.findVehiclePath()` (224 lines)

Split into two clearly typed functions:

- `findVehiclePathRoadNode(vehicle, destination, map, game)` — A* on road-node graph
- `findVehiclePathSandbox(vehicle, destination, map, game)` — BFS on tile grid

`findVehiclePath()` becomes a 10-line router that checks `map.road_v_rxs` and delegates.

Move the BFS snap logic (repeated twice with slightly different criteria) into a shared `_snapToNearestRoadNode(pos, map)` helper.

Replace magic numbers `9999` (impassable cost) and `1000` (iteration cap) with named constants from `data/WorldGenConfig.lua`.

#### 5.3 — `RoadSmoother.lua` (972 lines) — Split into Three Files

The file currently fuses three algorithms:

- `services/ChainWalker.lua` — walks `zone_seg_v/h` adjacency graph, stops at degree≠2 nodes, produces raw chains
- `lib/path_utils.lua` — already receives `chaikin` and `rdp` from Phase 3 (task 3.1)
- `services/RoadSmoother.lua` — thin coordinator: calls `ChainWalker`, pipes through `path_utils.rdp` then `path_utils.chaikin`, returns smooth paths

The existing `RoadSmoother.lua` entry point (`buildStreetPathsLike`) stays callable — callers do not change.

#### 5.4 — `controllers/WorldSandboxController.sendToGame()` (330+ lines)

Extract the four distinct responsibilities into separate methods:

- `_generateTerrain(params)` — noise + WFC orchestration
- `_convertCoordinates(raw_data, target_map)` — coordinate conversion to city grid
- `_assignDistricts(city_grid, zone_data)` — district assignment
- `sendToGame(params)` — calls the four in order; orchestration only

Each extracted method should be under 80 lines.

#### 5.5 — `views/GameView.lua draw()` (300+ lines)

Implement the render mode registry described in `abstraction-opportunities.md §5`:

- Create a `RENDER_MODES` table with `{ condition, renderer }` entries for: lab grid, WFC final grid, world gen, region scale, city/downtown scales.
- `draw()` iterates the table and delegates to the matched renderer.
- Each renderer function is under 60 lines.

#### 5.6 — `Vehicle._resolveOffScreenState()` — State Dispatch Table

Replace the 10-branch while loop with a dispatch table:

```lua
local STATE_RESOLUTION = {
    ["Idle"]        = function(v, g) ... end,
    ["To Pickup"]   = function(v, g) ... end,
    ["To Dropoff"]  = function(v, g) ... end,
    ["Returning"]   = function(v, g) ... end,
    -- etc.
}
```

The loop body becomes: look up handler, call it, break if travel state reached.

#### ~~5.7 — `SandboxController.generate()` and `regenerate_region()`~~ — Resolved

`SandboxController` has been deleted. Skip this task.

### Expected Outcome

- No function in the codebase exceeds ~80 lines.
- `WorldNoiseService` has a clear 4-phase generate pipeline.
- `PathfindingService` has two named, typed pathfinding functions.
- `RoadSmoother.lua` is under 100 lines.
- `GameView.draw()` is under 30 lines.

### Testing

- Regenerate the world several times; verify visually identical output.
- Run A* on the road-node map and the sandbox map; verify paths are equivalent to pre-refactor.
- Off-screen vehicle simulation (abstracted mode) must resolve states identically; test by sending a vehicle on a long trip, switching to region view, and verifying it completes without hanging.

### Deviations

- **5.1**: Kept phases as `generateHeightMap`, `traceRiversAndLakes`, `assignBiomesAndSuitability`, `detectContinentsAndRegions` rather than the originally named functions. River + lake tracing are one pass (inseparable). No `data/biomes.lua` extracted — biome logic lives in the phase functions; the plan's biome separation would have required a larger data reorganization outside Phase 5 scope.
- **5.2**: Implemented as planned. `_snapToColumn` and `_snapToNearestTraversable` are the shared snap helpers (not `_snapToNearestRoadNode` as named in the plan — name adjusted to reflect actual usage).
- **5.3**: `ChainWalker.lua` placed in `services/` (not a new split file in `utils/`). `walkRoad` was dead code — removed rather than ported. `DIRS8` and `ROAD_TYPES` remain local to both files as needed.
- **5.4**: `sendToGame` was ~1035 lines (not 330+ as estimated). Extracted into `_buildZoneGrid`, `_buildRoadNetwork`, `_buildGameImages` using a shared `ctx` table. `sendToGame` reduced to ~304 lines. The 3 helpers range from 100-350 lines each (road network is large due to island connectivity BFS). The plan's names (`_generateTerrain`, `_convertCoordinates`, `_assignDistricts`) did not cleanly map to the actual logical boundaries.
- **5.5**: Extracted `_drawFloatingTexts`, `_drawTileGridFallback`, `_drawWorldGenMode` from `draw()`. Did not implement a `RENDER_MODES` registry table — the if/else between world-gen and fallback is simple enough that a dispatch table adds indirection without clarity benefit. `draw()` is 20 lines.
- **5.6**: Implemented as planned.

### AI Notes

Task 5.3 (RoadSmoother split) has the highest risk — the chain walker is deeply coupled to the `zone_seg_v/h` data structures. Read the full file before splitting. Preserve the existing `buildStreetPathsLike` signature so that downstream callers (`vehicle_states`, map renderers) do not need to change.

---

**Status:** Not started
**Line count change:** ~−500 (same logic, better organized; no new files beyond what's already planned)
**Deviation from plan:** —

---

## Phase 6 — MVC Cleanup

**Goal:** Models do not mutate global state. Views do not run business logic. Controllers do not own game data.

### Tasks

#### 6.1 — `UIManager._calculatePerSecondStats()` → Service

This view function mutates `game.state.income_history` and `game.state.trip_creation_history`.

- Create `services/StatsService.lua` with `calculatePerSecondStats(game_state)` — returns a stats table, mutates nothing
- `UIManager` calls `StatsService.calculatePerSecondStats(game.state)` and reads the returned table for display
- `UIManager` never writes to `game.state`

#### 6.2 — `Map.lua` — Stop Mutating Game Global

`Map.lua:143–175` sets `Game.active_map_key`, mutates `Game.camera`, fires `Game.EventBus`.

- `Map.lua` must not read or write the `Game` global. Pass `game` as a parameter or use events.
- `Map:setActive(game)` — emits an event; `GameController` handles the event and updates `game.active_map_key` and `game.camera`.

#### 6.3 — `UpgradeSystem.lua` — Stop Direct Vehicle Mutation

`UpgradeSystem.lua:155` directly modifies `game.C.VEHICLES.BIKE.speed` and iterates live vehicles.

- Upgrade application emits an `upgrade_applied` event with the effect data.
- `GameController` (or a new `UpgradeEffectHandler`) listens and applies the effect to vehicle properties.
- `UpgradeSystem` owns upgrade state and eligibility only — not vehicle mutation.

**Design decision required before starting this task:** The current code mutates `game.C.VEHICLES.BIKE.speed` — a constant — at runtime, so that all future vehicle instantiation inherits the upgraded speed. If you move the mutation to an event handler that does the same thing, you've changed who mutates the constant but not the underlying problem. The cleaner fix is to give each vehicle instance its own `speed_modifier` multiplier, so upgrades emit an event that updates `vehicle.speed_modifier` on all live vehicles, and new vehicles initialize their modifier from the upgrade state. Decide on this approach before writing any code in this task — retrofitting it later is harder.

#### ~~6.4 — `SandboxController` — Stop Mutating `Game.C.MAP` Constants~~ — Resolved

`SandboxController` has been deleted. Verify that no other callers of `NewCityGenService` or `MapGenerationService` still temporarily mutate `Game.C.MAP` — if `WorldSandboxController` does this, address it here instead.

#### 6.5 — `EventSpawner.lua` — Remove `draw()` Method

`EventSpawner.lua:54–66` contains a `draw()` method in a model. Move rendering to a view or to `GameView`. `EventSpawner` emits events; it does not draw.

#### 6.6 — `GameConfig._onConfigChanged()` — Emit Events Instead of Calling Graphics APIs

`GameConfig._onConfigChanged()` directly calls `love.window.setMode()` and `love.window.setFullscreen()`.

- `_onConfigChanged()` emits `config_changed` event with the changed key and value.
- A `DisplayController` (or `GameController`) listens and calls the LÖVE APIs.
- Config module has no dependency on `love.window`.

#### 6.7 — `Modal.lua` — Compute Display State Outside Draw

`Modal.lua:170–206` determines node color, border, and visibility inline during draw.

- Create `UpgradeModalViewModel.buildDisplayState(upgrade_tree, game_state)` — returns a display table
- `_drawTree()` reads the display table and renders it; no game state access during draw

#### 6.8 — `InputController` — Instantiate `UIController` Once

`InputController` creates a new `UIController` instance on every mouse click (line 108). Instantiate once in `InputController:new()` and reuse.

### Expected Outcome

- Models contain no `love.*` calls and no writes to the global `Game`.
- Views contain no `game.state.x = y` assignments.
- `GameConfig` has no LÖVE dependency.
- No global constants are mutated during generation.

### Testing

- Trigger an upgrade; verify vehicle speed changes correctly via the event path.
- Trigger a config change (fullscreen toggle); verify it still works after `_onConfigChanged` no longer calls graphics APIs directly.
- Induce a generation error mid-way (temporarily); verify `Game.C.MAP` values are unchanged afterward.

---

**Status:** Not started
**Line count change:** ~+80 new handler/service code / −120 misplaced logic (net reduction ~40)
**Deviation from plan:** —

---

## Phase 7 — Architecture Improvements

**Goal:** Eliminate the remaining global-hub anti-patterns. After this phase, systems declare their dependencies explicitly and can be understood in isolation.

### Tasks

#### 7.1 — `lib/input_dispatcher.lua` — Replace 6 Copy-Pasted Blocks in `main.lua`

The controller-priority dispatch pattern appears in every input handler in `main.lua`:

- Create `lib/input_dispatcher.lua` with:
  - `InputDispatcher:register(controller, priority)` — adds to ordered list
  - `InputDispatcher:dispatch(event_name, ...)` — tries each controller in priority order, stops on first that handles it
- `main.lua` registers controllers once in `love.load()`.
- Each handler becomes one line: `input_dispatcher:dispatch("keypressed", key, scancode, isrepeat)`.

#### 7.2 — `WfcLabController.keypressed()` — Key-to-Handler Table

Replace the 230-line if-else chain with a handler table:

```lua
local KEY_HANDLERS = {
    ["r"] = function(self) ... end,
    ["g"] = function(self) ... end,
    -- etc.
}

function WfcLabController:keypressed(key)
    local handler = KEY_HANDLERS[key]
    if handler then handler(self) end
end
```

Wrap each handler in a pcall or error boundary — currently any service failure leaves `Game` in a corrupted partial state.

#### 7.3 — `InputController` — Debug Toggle Table

8 structurally identical debug overlay key handlers (b, p, g, v, n, m, j, o). Replace with:

```lua
local DEBUG_TOGGLES = {
    b = "show_build_zones",
    p = "show_pathfinding",
    g = "show_grid",
    -- etc.
}
```

The handler loops the table. Adding a new debug toggle is one line.

#### 7.4 — `UIView.lua` — Move `require()` Out of `draw()`

`UIView.lua` calls `require()` inside `draw()` — every frame, every render. Move all requires to the module top level.

#### 7.5 — `FloatingTextSystem` — Extract from `GameState`

`GameState.lua:40–49` updates floating text position and alpha inside the state model.

- Create `services/FloatingTextSystem.lua`:
  - `FloatingTextSystem.emit(text, x, y)` — called by game events
  - `FloatingTextSystem.update(dt)` — advances all active texts
  - `FloatingTextSystem.draw()` — renders them
- `GameState` holds no floating text logic.

#### 7.6 — `_createEmptyGrid()` Deduplication

`_createEmptyGrid()` exists in both `MapGenerationService` and `NewCityGenService`. Move to `lib/grid_search.lua` (Phase 3 adds this file) and delete both local copies.

#### 7.7 — `ErrorService` — Non-Reentrant State Fix

`ErrorService` uses module-level mutable state (`log_entries`, `error_counts`). This makes it impossible to reset between test runs.

- Expose `ErrorService.reset()` for test use.
- Consider making `ErrorService` instantiable so multiple isolated services can have separate error logs.

### Expected Outcome

- `main.lua` input handlers are one line each.
- `WfcLabController.keypressed()` is under 20 lines.
- No `require()` inside any `draw()` or `update()` function.
- Floating text is a self-contained system.
- `ErrorService` is resettable.

### Testing

- Every key in `WfcLabController` must still work after the table refactor.
- All debug overlays must toggle correctly after the table refactor.
- Profile: verify `require()` is no longer called during a frame's draw phase (use LÖVE's `love.timer.getDelta()` + require hook or a simple counter).

### AI Notes

Task 7.2 requires adding error handling around every handler body — this is the most important part. The current state of `WfcLabController` where any service failure corrupts `Game` is a genuine reliability bug, not just a style issue.

---

**Status:** Not started
**Line count change:** ~+50 / −150 (net reduction ~100)
**Deviation from plan:** —

---

## Summary

| Phase | Goal | New Files | Files Deleted | Net Line Δ |
|-------|------|-----------|---------------|------------|
| 1 — Bug Fixes | Game actually works | 0 | 1–2 | −120 |
| 2 — Data Extraction | One source of truth for game facts | 9 | 2 | −150 |
| 3 — Lib Utilities | Each algorithm in exactly one place | 5 | 0 | −180 |
| 4 — Service Refactoring | Each domain owned by one service | 4 | 0 | −150 |
| 5 — God Functions | No function over ~80 lines | 2 | 0 | −400 |
| 6 — MVC Cleanup | Models/views/controllers in their lanes | 2 | 0 | −40 |
| 7 — Architecture | Systems declare their dependencies | 2 | 0 | −100 |
| **Total** | | **24** | **3–4** | **~−1140** |

> The original audit also included ~1,200 lines of now-deleted code (generators, SandboxController, old pipeline) that doesn't appear here since it no longer needs refactoring.

Estimated code quality after all phases: **8/10**
- All critical bugs fixed
- Every algorithm in one place
- Adding a zone, vehicle type, or road type is a one-file change
- No global constant mutation
- Views contain no business logic
- Functions are small enough to read in one screen
