# Plan: WorldSandboxController God Object Refactor

## Context

`controllers/WorldSandboxController.lua` is 4,103 lines and owns 16 distinct responsibility domains: world noise orchestration, city placement, highway routing, city bounds/POI placement, district zoning, arterial road generation, street generation, WFC zone grid building, road network construction, city map assembly, world image rendering, city image rendering, game HUD image preparation, the sendToGame game bridge, camera/viewport management, and input handling.

The audit identified it as the single largest maintainability bottleneck. The goal is to break it into focused, MVC-compliant collaborators without the player or game noticing anything changed.

**Absolute constraint: zero observable behavioral change.** Same world output, same images, same `game.maps.*` shapes, same RNG sequence. This is a structural reorganization only — no logic changes, no data shape changes, no RNG substitutions.

---

## What Changes / What Stays

**Unchanged (do not touch):**
- `views/WorldSandboxView.lua` — reads `wsc.camera`, `wsc.world_image`, `wsc.city_image`, `wsc.view_mode`, `wsc.view_scope`, `wsc.status_text`; no changes needed
- `views/WorldSandboxSidebarManager.lua` — binds sliders to `wsc.params.*`, calls `wsc:generate()`, `wsc:place_cities()`, `wsc:build_highways()`, `wsc:regen_bounds()`, `wsc:sendToGame()`; no changes needed
- `main.lua` — calls `wsc:toggle()`, `wsc:isActive()`, routes all input to `wsc:handle_*`; no changes needed
- `services/WorldNoiseService.lua` — already extracted; untouched
- `models/Map.lua`, `lib/wfc.lua`, `utils/RoadSmoother.lua`, `data/*.lua` — untouched
- All `game.maps.*` and `game.hw_*` data shapes written by `sendToGame`

**Controller public API — must remain exactly:**
```
generate(), place_cities(), build_highways(), regen_bounds(), sendToGame()
toggle(), isActive(), open(), close()
handle_keypressed(), handle_mouse_wheel(), handle_mouse_down(),
handle_mouse_up(), handle_mouse_moved(), handle_textinput()
set_view(), enter_scope_pick(), set_scope_world()
self.params, self.camera, self.world_image, self.city_image,
self.view_mode, self.view_scope, self.status_text, self.sidebar_manager
```

---

## Portability Boundary

The world generation services must be extractable into a different project. Given a heightmap, parameters, and math functions, they produce a map — with **zero knowledge of Cosmic Courier**.

```
┌─────────────────────────────────────────────────────┐
│  PORTABLE WORLD GEN  (zero love.*, zero game refs)  │
│                                                     │
│  utils/WorldGenUtils.lua                            │
│  services/CityPlacementService.lua                  │
│  services/HighwayService.lua                        │
│  services/CityBoundsService.lua                     │
│  services/CityDistrictService.lua                   │
│  services/CityArterialService.lua                   │
│  services/CityStreetService.lua                     │
│  services/MapBuilderService.lua                     │
└─────────────────────────────────────────────────────┘
          │ returns plain Lua tables (map data)
          ▼
┌─────────────────────────┐    ┌──────────────────────┐
│  WorldImageService      │    │  GameBridgeService    │
│  (Love2D rendering)     │    │  (game integration)  │
│  love.* OK here         │    │  game.* OK here       │
└─────────────────────────┘    └──────────────────────┘
```

## MVC Role Assignment

| Layer | Files | Rule |
|---|---|---|
| Controller | `WorldSandboxController.lua` | Orchestration, camera, input, state storage. Calls services. Stores generated data on `self.*`. Injects `math_fns` into every service call. |
| **Portable** Services | `CityPlacementService`, `HighwayService`, `CityBoundsService`, `CityDistrictService`, `CityArterialService`, `CityStreetService`, `MapBuilderService` | Pure computation. **No `love.*` imports whatsoever. No game struct references.** Receive all math functions via `math_fns` parameter. Return plain Lua tables. |
| Rendering Service | `WorldImageService` | All `love.graphics.*` / `love.image.*` isolated here. Returns Love2D image objects. Not portable — Love2D dependency intentional. |
| Integration Service | `GameBridgeService` | The ONLY file that knows what a "game" is. FFI grid construction, `game.maps.*` population, entity reset. Not portable — game dependency intentional. |
| Utilities | `WorldGenUtils` | Shared pure helpers. Zero dependencies (no require at all). Portable. |

---

## New File Structure

```
utils/
  WorldGenUtils.lua              [NEW ~80 lines]

services/
  WorldNoiseService.lua          [EXISTS — unchanged]
  CityPlacementService.lua       [NEW ~200 lines]
  HighwayService.lua             [NEW ~220 lines]
  CityBoundsService.lua          [NEW ~290 lines]
  CityDistrictService.lua        [NEW ~280 lines]
  CityArterialService.lua        [NEW ~380 lines]
  CityStreetService.lua          [NEW ~110 lines]
  MapBuilderService.lua          [NEW ~700 lines]
  WorldImageService.lua          [NEW ~650 lines]
  GameBridgeService.lua          [NEW ~620 lines]

controllers/
  WorldSandboxController.lua     [MODIFIED: ~300 lines remaining]
```

Total code volume stays approximately the same (~4,100 lines), split across 10 new files.

---

## Service Interfaces

Each service is a module table with static functions. No constructor. Takes explicit data parameters. Returns results. Never captures `self` from the controller.

### `utils/WorldGenUtils.lua`
Shared helpers currently defined as local functions in the controller. Used by multiple services.
```lua
WorldGenUtils.bilinear2d(map, fy, fx, W, H) → number
-- subcell_elev_at receives noise_fn instead of calling love.math.noise directly:
WorldGenUtils.subcell_elev_at(gscx, gscy, heightmap, noise_fn) → number
WorldGenUtils.hpush(heap, f, i)
WorldGenUtils.hpop(heap) → {f, i}
```
**Source:** `bilinear2d` (line ~8), `subcell_elev_at` (line ~2881, uses `SC_DETAIL_FREQ/AMP`, `SC_MEDIUM_FREQ/AMP` constants defined at lines ~2876–2879), heap helpers inline in each Dijkstra/A* block.
**Love2D calls:** None. `subcell_elev_at` currently calls `love.math.noise` — replaced with injected `noise_fn` parameter. Constants `SC_DETAIL_FREQ` etc. move into this file as module-level locals.

---

### `services/CityPlacementService.lua`
```lua
CityPlacementService.placeCities(
    suitability_scores, continent_map, continents,
    region_map, regions_list, w, h, params, math_fns
) → city_locations   -- [{x, y, s, ...}]
```
**Source:** `place_cities()` lines ~2169–2322.
**Love2D removal:** `love.math.random()` → `math_fns.random()`. No other love.* calls.
**Controller injects:** `math_fns = { random = love.math.random, noise = love.math.noise }`
**Controller after:** `self.city_locations = CityPlacementService.placeCities(..., self.math_fns)`

---

### `services/HighwayService.lua`
```lua
HighwayService.buildHighways(
    city_locations, heightmap, biome_data, w, h, params, math_fns
) → highway_map   -- [cell_idx] = true
```
**Source:** `build_highways()` lines ~2323–2532.
**Love2D removal:** Any `love.math.*` calls replaced with `math_fns.*`. No game struct references.
**Controller after:** `self.highway_map = HighwayService.buildHighways(..., self.math_fns)`

---

### `services/CityBoundsService.lua`
```lua
CityBoundsService.genAllBounds(
    city_locations, heightmap, biome_data, region_map,
    continent_map, w, h, params, math_fns
) → {
    city_bounds_list,     -- [city_idx] = {[cell_idx] = true}
    city_pois_list,       -- [city_idx] = [{x, y, type, ...}]
    all_city_plots,       -- shared set
    border_cells,
    fringe_cells,
}
```
**Source:** `_gen_all_bounds()` + `_gen_bounds_for_city()` lines ~2535–2905.
**Love2D removal:** `love.math.noise()` → `math_fns.noise()`. No game struct references.
**Uses:** `WorldGenUtils.subcell_elev_at(gscx, gscy, hmap, math_fns.noise)`, `WorldGenUtils.hpush/hpop`

---

### `services/CityDistrictService.lua`
```lua
CityDistrictService.genAllDistricts(
    city_locations, city_pois_list, city_bounds_list,
    heightmap, w, h, params, math_fns
) → city_district_maps,   -- [city_idx] = {[sub_cell_idx] = poi_idx}
    city_district_colors,  -- [city_idx] = {[sub_cell_idx] = {r,g,b}}
    city_district_types    -- [city_idx] = {[poi_idx] = district_type}
```
**Source:** `_gen_all_districts()` + `_gen_districts_for_city()` lines ~2906–3174.
**Love2D removal:** All `love.math.*` → `math_fns.*`. No game struct references.
**Uses:** `WorldGenUtils.subcell_elev_at(..., math_fns.noise)`, `WorldGenUtils.hpush/hpop`

---

### `services/CityArterialService.lua`
```lua
CityArterialService.genAllArterials(
    city_locations, city_pois_list, city_bounds_list,
    city_district_maps, highway_map, heightmap, biome_data, w, h, params, math_fns
) → city_arterial_maps   -- [city_idx] = {[sub_cell_idx] = true}
```
**Source:** `_gen_all_arterials()` + `_gen_arterials_for_city()` lines ~3175–3528.
**Love2D removal:** `love.math.noise()` → `math_fns.noise()`. No game struct references.
**Uses:** `WorldGenUtils.subcell_elev_at(..., math_fns.noise)`, `WorldGenUtils.hpush/hpop`
**Controller after:** `self.city_arterial_maps = CityArterialService.genAllArterials(..., self.math_fns)`
**Note:** Most complex service (~380 lines). Extract last among the generation services.

---

### `services/CityStreetService.lua`
```lua
CityStreetService.genAllStreets(
    city_locations, city_pois_list, city_bounds_list,
    city_district_maps, w, h, params
) → city_street_maps   -- [cell_key] = street_type, keyed per city
```
**Source:** `_gen_all_streets()` + `_gen_streets_for_city()` lines ~3541–3629.
**Love2D removal:** None needed (deterministic geometry, no love.* calls).
**Controller after:** `self.city_street_maps = CityStreetService.genAllStreets(...)`

---

### `services/MapBuilderService.lua`
```lua
MapBuilderService.buildCityMap(
    city_idx, mn_x, mx_x, mn_y, mx_y, art_sci, all_claimed,
    pois, district_map, arterial_map, street_map,
    highway_map, heightmap, biome_data, params, math_fns
) → Map instance,
    zone_grid,      -- WFC result (needed by WorldImageService)
    zone_offsets    -- needed by WorldImageService
```
**Source:** `_buildCityGrid()` + `_buildZoneGrid()` + `_fixIslandConnectivity()` + `_buildRoadNetwork()` + `_buildCityMap()` — lines ~209–881 and ~1049–1235.
**Love2D removal:** `love.math.random()` in WFC zone weighting → `math_fns.random()`. No game struct references.
**Controller after:** `map, zone_grid, zone_offsets = MapBuilderService.buildCityMap(..., self.math_fns)`
**Note:** Contains the WFC call (`lib.wfc`). Returns zone_grid alongside Map so WorldImageService can render the city correctly. This is the largest and most complex service.

---

### `services/WorldImageService.lua` *(Love2D rendering — love.* permitted)*
```lua
WorldImageService.buildWorldImage(
    heightmap, colormap, biome_colormap, suitability_colormap,
    continent_colormap, region_colormap, city_locations,
    view_mode, w, h, params
) → love.Image

WorldImageService.buildWorldImageHiRes(
    heightmap, biome_data, w, h, params, scale
) → love.Image

WorldImageService.buildCityImage(
    city_map, city_idx, zone_grid, zone_offsets, pois,
    district_map, district_colors, arterial_map, street_map,
    heightmap, biome_data, w, h, params, render_mode
) → love.Image

WorldImageService.buildGameImages(
    city_maps, zone_grids, zone_offsets, city_idxs,
    pois_list, district_maps, district_colors,
    arterial_maps, street_maps, heightmap, biome_data, w, h, params
) → { city_images, camera_params }
```
**Source:** `_buildImage()` + `_buildImageHiRes()` (lines ~1894–2052), `_buildCityImage()` (lines ~3739–3929), `_buildGameImages()` (lines ~885–1039).
**Note:** Only service that may call `love.graphics.*`, `love.image.*`, `love.math.noise()`.

---

### `services/GameBridgeService.lua`
```lua
GameBridgeService.sendToGame(
    game, city_maps, game_images, camera_params,
    city_locations, highway_map, city_bounds_list, city_pois_list,
    continent_map, continents, region_map, regions_list,
    river_paths, w, h, params
) → nil   (mutates game)
```
**Source:** `sendToGame()` lines ~1237–1825 (excluding the per-city _buildCityMap and _buildGameImages calls, which move to MapBuilderService and WorldImageService).
**Uses:** `ffi`, `models.Map`, `services.PathCacheService`, `utils.RoadSmoother`.
**Note:** This is the critical bridge. A bug here breaks the entire game load. Extract last. Verify by completing a full session.

---

## Slim Controller (After Refactor)

```lua
-- controllers/WorldSandboxController.lua (~300 lines)
-- Responsibilities: params storage, self.* data storage, camera, input, orchestration

function WSC:new(game)       -- init self.params, self.camera, sidebar, all self.* fields
function WSC:generate()      -- WorldNoiseService → self.heightmap, biome_data, etc.
                             -- WorldImageService.buildWorldImage → self.world_image
function WSC:place_cities()  -- CityPlacementService → self.city_locations
function WSC:build_highways()-- HighwayService → self.highway_map
function WSC:regen_bounds()  -- CityBoundsService → self.city_bounds_list, pois_list
                             -- CityDistrictService → self.city_district_maps
                             -- CityArterialService → self.city_arterial_maps
                             -- CityStreetService → self.city_street_maps
                             -- WorldImageService.buildWorldImage → self.world_image (rebuild)
function WSC:sendToGame()    -- per city: MapBuilderService.buildCityMap
                             -- WorldImageService.buildGameImages
                             -- GameBridgeService.sendToGame
-- Camera / viewport: set_view, enter_scope_pick, set_scope_world,
--   _fitToArea, _selectContinent, _selectRegion, _selectCity,
--   _selectDowntown, _centerCamera
-- Input: handle_keypressed, handle_mouse_*, handle_textinput
```

---

## Extraction Phase Order

Four batches. Do all extractions in a batch together, then test. Never start the next batch until the current one passes all tests.

### Batch A — Utilities + Stateless Generation (LOW risk)
1. Create `utils/WorldGenUtils.lua` — move `bilinear2d`, `subcell_elev_at`, heap helpers; update controller `require`
2. Extract `CityPlacementService` — controller calls service, stores result on `self.city_locations`
3. Extract `HighwayService` — controller calls service, stores result on `self.highway_map`

**Test after Batch A:** F8 opens → Generate → Place Cities → Build Highways all produce correct output.

---

### Batch B — City Spatial Generation (MEDIUM risk)
4. Extract `CityBoundsService` — controller calls service, stores `self.city_bounds_list`, `self.city_pois_list`
5. Extract `CityDistrictService` — controller calls service, stores `self.city_district_maps`, `self.city_district_colors`, `self.city_district_types`
6. Extract `CityStreetService` — controller calls service, stores `self.city_street_maps`

**Test after Batch B:** Regen Bounds → select a city → all district colors, street overlays render correctly.

---

### Batch C — Arterials + Rendering + Map Assembly (HIGH risk)
7. Extract `CityArterialService` — controller calls service, stores `self.city_arterial_maps`
8. Extract `WorldImageService` — controller calls for world image, city image, game images; stores Love2D images on `self`
9. Extract `MapBuilderService` — controller calls per-city map build in `sendToGame`; receives `Map`, `zone_grid`, `zone_offsets` back

**Test after Batch C:** sendToGame → game loads → city map is correct → camera transitions (world → continent → region → city → downtown) all work.

---

### Batch D — Game Bridge + Final Cleanup (HIGH risk)
10. Extract `GameBridgeService` — move FFI grid construction, `game.maps.*` population, entity reset out of controller
11. Controller cleanup — delete all extracted code from controller, verify ~300 lines remain, all `self.*` data fields still present

**Test after Batch D:** Full regression (see Verification Sequence below). Determinism check with fixed seed.

---

## Critical Implementation Rules

1. **One batch per commit.** All three extractions in a batch go in one commit, after tests pass.
2. **No logic changes inside a phase.** Copy functions verbatim, adjust only parameter passing (`self.x` → explicit `x`). Fix behavior separately if a bug surfaces.
3. **Make all dependencies explicit.** A service function must receive every piece of data it needs as a parameter. No captures of controller state via closures. No globals.
4. **Inject math functions — never call love.* in portable services.** Controller sets `self.math_fns = { noise = love.math.noise, random = love.math.random }` in `new()` and passes it to every service call. Services call `math_fns.noise(...)` / `math_fns.random(...)` — same function pointers means bit-for-bit identical RNG stream and noise values. Agnosticism means no `love.*` imports anywhere in portable services.
5. **Return zone_grid alongside Map.** `MapBuilderService.buildCityMap` must return the WFC zone_grid and zone_offsets alongside the Map instance — WorldImageService needs them for city rendering. Store all three on `self` in the controller.
6. **sendToGame is last.** It depends on outputs from every other service. Extract it only after all other services are verified.
7. **Verify game.maps.* shapes are identical** after Phase 10 by comparing a deterministic seed's output before and after (same seed_x/seed_y in params).

---

## Key File Paths

| File | Status | Note |
|---|---|---|
| `controllers/WorldSandboxController.lua` | Modify | Shrinks from 4103 → ~300 lines |
| `utils/WorldGenUtils.lua` | Create | Pure helpers, no require |
| `services/CityPlacementService.lua` | Create | Source: lines ~2169–2322 |
| `services/HighwayService.lua` | Create | Source: lines ~2323–2532 |
| `services/CityBoundsService.lua` | Create | Source: lines ~2535–2905 |
| `services/CityDistrictService.lua` | Create | Source: lines ~2906–3174 |
| `services/CityArterialService.lua` | Create | Source: lines ~3175–3528 |
| `services/CityStreetService.lua` | Create | Source: lines ~3541–3629 |
| `services/MapBuilderService.lua` | Create | Source: lines ~209–881, 1049–1235 |
| `services/WorldImageService.lua` | Create | Source: lines ~885–1039, 1894–2052, 3739–3929 |
| `services/GameBridgeService.lua` | Create | Source: lines ~1237–1825 (partial) |
| `views/WorldSandboxView.lua` | No change | |
| `views/WorldSandboxSidebarManager.lua` | No change | |
| `main.lua` | No change | |
| `services/WorldNoiseService.lua` | No change | |

---

## Verification Sequence (After Each Phase AND At Completion)

1. F8 opens sandbox, sidebar renders with all sliders
2. "Generate" → world image appears, no error
3. "Place Cities" → cities appear as dots on world image
4. "Build Highways" → highway lines appear
5. "Regen Bounds" → district colors, arterials, streets visible on city select
6. "Send to Game" → game world loads, depot and player spawn correctly
7. Vehicles navigate road network without pathfinding errors
8. A trip can be created and dispatched
9. Camera transitions work: world → continent → region → city → downtown
10. **Determinism check:** Run with seed_x=100, seed_y=200 before and after Phase 10. City count, locations, and road layout must be identical.
