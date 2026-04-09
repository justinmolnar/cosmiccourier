# Architectural Audit Report — April 8, 2026

## Executive Summary

The Cosmic Courier codebase entered April 2026 with two major God Objects and a pattern of MVC leakage across both the rendering and game-state layers. Both God Objects have since been resolved: `WorldSandboxController.lua` (4,103 lines) and `DispatchTab.lua` (~2,794 lines) were each refactored into focused, single-responsibility services. This report covers the pre-refactor issues and the post-refactor state of both.

---

## 1. Pre-Refactor Issues (State at Start of Day)

### 1.1 God Objects

| File | Lines | Problem |
|---|---|---|
| `controllers/WorldSandboxController.lua` | ~4,103 | Owned 16 distinct responsibilities: terrain noise, city placement, highway routing, city bounds/POI placement, district zoning, arterial road generation, street generation, WFC zone-grid building, road network construction, city map assembly, world image rendering, city image rendering, HUD image preparation, game bridge, camera/viewport, input handling |
| `views/tabs/DispatchTab.lua` | ~2,794 | View component performing heavy logic lifting — block dimension measurement, palette filtering/grouping, tree path utilities — that belongs in a Service layer |

### 1.2 Non-Agnostic Rendering (MVC Leakage)

- **`models/vehicles/Vehicle.lua`**: Contains direct `love.graphics` calls inside a model.
- **`models/Map.lua`**: Contains direct `love.graphics` calls inside a model.
- **Impact**: Game logic cannot run headless (server/unit tests) without loading the full Love2D graphics module.

### 1.3 Global State Coupling

The `Game` global object is used as a blackboard. Views, Models, and Controllers all read and write it freely.
- **Violation**: `views/GameView.lua` directly modifies state on the `Game` object.
- **Impact**: State changes are hard to trace; components cannot be tested in isolation.

### 1.4 Scattered love.* Imports in Generation Code

`love.math.noise`, `love.math.random`, and `love.graphics.*` were called directly inside world-generation functions that had no business depending on Love2D. This made the generation logic impossible to test or reuse outside of a running Love2D process.

---

## 2. WorldSandboxController Refactor (Completed April 8, 2026)

### 2.1 Goal

Extract all domain logic from `WorldSandboxController.lua` into focused, single-responsibility services. Zero observable behavioral change — same world output, same images, same `game.maps.*` shapes, same RNG sequence.

### 2.2 Portability Boundary Enforced

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
         │ returns plain Lua tables
         ▼
┌──────────────────────────┐   ┌─────────────────────────┐
│  WorldImageService       │   │  GameBridgeService       │
│  (Love2D rendering)      │   │  (game integration)     │
│  love.* permitted        │   │  game.* permitted        │
└──────────────────────────┘   └─────────────────────────┘
```

**Math injection pattern** — `love.math.noise` and `love.math.random` are bound once in the controller:
```lua
self.math_fns = { noise = love.math.noise, random = love.math.random }
```
and passed explicitly to every portable service. Same function pointers → bit-for-bit identical RNG and noise output.

### 2.3 Services Created

| Service | Lines | Responsibility |
|---|---|---|
| `utils/WorldGenUtils.lua` | ~80 | Shared pure helpers: `bilinear2d`, `subcell_elev_at`, heap push/pop |
| `services/CityPlacementService.lua` | ~170 | City scoring, candidate filtering, placement |
| `services/HighwayService.lua` | ~220 | A\* highway routing between city pairs |
| `services/CityBoundsService.lua` | ~290 | City footprint flood-fill, POI placement, border/fringe cells |
| `services/CityDistrictService.lua` | ~280 | Voronoi district assignment, district color generation |
| `services/CityArterialService.lua` | ~380 | Arterial road pathfinding through city subcell grid |
| `services/CityStreetService.lua` | ~110 | Zone-boundary street generation |
| `services/MapBuilderService.lua` | ~700 | WFC zone-grid, road network, Map assembly |
| `services/WorldImageService.lua` | ~307 | All Love2D image rendering (world, hi-res, city) |
| `services/GameBridgeService.lua` | ~382 | FFI unified grid, attachment nodes, city edges, vehicle/depot reset |
| `services/WorldNoiseService.lua` | existed | Terrain noise (already extracted previously) |

### 2.4 Controller Before / After

| Metric | Before | After |
|---|---|---|
| Lines | ~4,103 | 870 |
| Reduction | — | 79% |
| Methods | ~80 | 26 |
| Responsibilities | 16 | 4 (orchestration, camera, input, state storage) |
| love.* in generation | Yes (noise/random scattered) | No — all injected via math_fns |
| Game refs in generation | Yes | No — isolated to GameBridgeService |

### 2.5 Controller Public API (Unchanged)

The following surface was preserved exactly — the sidebar, main loop, and view all continue to work without modification:

```
generate(), place_cities(), build_highways(), regen_bounds(), sendToGame()
toggle(), isActive(), open(), close()
handle_keypressed(), handle_mouse_wheel(), handle_mouse_down(),
handle_mouse_up(), handle_mouse_moved(), handle_textinput()
set_view(), enter_scope_pick(), set_scope_world()
self.params, self.camera, self.world_image, self.city_image,
self.view_mode, self.view_scope, self.status_text, self.sidebar_manager
```

### 2.6 Regressions Found and Fixed During Refactor

| Issue | Root Cause | Fix |
|---|---|---|
| Initial downtown zoom broken on launch | `_centerCamera()` was removed with scope system but still called in `generate()` | Restored simple implementation in controller |
| Vertical camera drift / no clamp | `handle_mouse_moved` had no Y boundary | Added `math.max(0, math.min(world_h * ts, camera.y))` |
| `_gen_all_districts` nil call crash | Method lived inside dead-code block B6 (lines 2224–2504) and was deleted with it | Added back as a thin delegate before dead code deletion |
| Dead scope buttons in sidebar | Five `btn_scope_*` buttons were remnants of removed UI | Removed all declarations, layout, draw calls, and click handlers from `WorldSandboxSidebarManager.lua` |

### 2.7 Commits

| Commit | Batch | Description |
|---|---|---|
| (pre-session) | A | WorldGenUtils, CityPlacementService, HighwayService |
| (pre-session) | B | CityBoundsService, CityDistrictService, CityStreetService |
| (pre-session) | C | CityArterialService, MapBuilderService, WorldImageService |
| `fcaf5a2` | D | GameBridgeService, dead-code deletion, sidebar cleanup, camera fixes |

---

## 3. DispatchTab Refactor (Completed April 9, 2026)

### 3.1 Goal

Extract all non-view logic from `DispatchTab.lua` into focused, single-responsibility services. Zero observable behavioral change — same block layout, same palette filtering, same drag-drop, same rule evaluation. Structural reorganization only.

### 3.2 Services Created / Modified

| File | Status | Responsibility |
|---|---|---|
| `services/RuleTreeUtils.lua` | Modified | +`pathsEqual`, +`appendPath` (2 pure path helpers extracted from DispatchTab locals) |
| `services/DispatchValidator.lua` | Modified | +`getSlotVisibility` (cascading slot visibility for `rep_get_property`) |
| `services/DispatchPaletteService.lua` | Created (~80 lines) | `filter(all, filter)` — tag+search filtering; `group(visible)` — category grouping sorted by hue |
| `services/DispatchLayoutService.lua` | Created (~290 lines) | All block dimension measurement: `measureNode`, `measureStack`, `boolNodeW`, `boolNodeSize`, `stackNaturalW`, `controlNaturalW`, `loopNaturalW`, `inlineRepW`, `pillWidth` |

### 3.3 Portability Boundary Enforced

All four extracted services have zero `love.*` calls and zero `game.*` references. `DispatchLayoutService` takes an explicit `ctx = { font, slot_input, panel_w }` assembled once per draw entry in DispatchTab — same values as before, now explicit rather than closed-over.

### 3.4 DispatchTab Before / After

| Metric | Before | After |
|---|---|---|
| Lines | ~2,794 | ~2,520 |
| Reduction | — | ~10% |
| Non-view logic in view | Measurement, palette, paths, visibility | None — all extracted |
| love.* in services | N/A | No |
| Top-level requires | Scattered inside functions | Consolidated at module top |

> Note: Line count reduction is modest (~10%) because DispatchTab retains all rendering and event handling, which is the bulk of the file. The structural win is the removal of all non-view logic, not raw line count.

### 3.5 DispatchTab Public API (Unchanged)

```
getState(), build()
getRuleDropIndex(), updateDropTarget(), updateHover()
drawDragGhost(), drawTooltip()
handleTextInput(), handleKeyPressed()
commitFocus(), clearFocus()
toggleFilterTag(), blurPaletteSearch()
handleSearchInput(), handleSearchKey()
cycleSlot(), cycleRepInnerSlot()
```

### 3.6 Prefab Palette Improvements (Delivered with Batch B)

- Added a "★ Prefabs" toggle pill to the palette filter header; prefabs are hidden by default and shown on toggle
- Tag filters and search text now apply to prefabs (previously the prefab section was unaffected by filters)
- Hover tooltips on prefab tiles now read the `tip` field (previously no tooltip was shown)

### 3.7 Commits

| Commit | Batch | Description |
|---|---|---|
| (Batch A) | A | `pathsEqual`/`appendPath` → RuleTreeUtils; `getSlotVisibility` → DispatchValidator; top-level requires consolidated |
| (Batch B) | B | `DispatchPaletteService` created; prefab toggle, tag filter wiring, hover tooltips |
| (Batch C) | C | `DispatchLayoutService` created; measurement functions extracted; wrapper shim in DispatchTab |
| (Batch D) | D | Dead locals removed; inline requires eliminated |

---

## 4. Remaining Issues (Post-Refactor State)

### 4.1 MVC Leakage in Models (Unchanged)

`models/vehicles/Vehicle.lua` and `models/Map.lua` still contain direct `love.graphics` calls. These have not degraded since the March audit but remain a barrier to headless testing.

**Recommended action**: Move rendering calls into a `VehicleRenderer` and `MapRenderer` in `views/`.

### 4.2 Global State Coupling (Unchanged)

`views/GameView.lua` still writes directly to the `Game` global. The pattern is contained but has not been formalized.

**Recommended action**: Enforce that all `Game` state mutations route through a controller method.

---

## 5. Metrics Summary

| Metric | March 2026 | April 8 (pre-refactor) | April 8 (post-WSC refactor) | April 9 (post-DT refactor) | Trend |
|---|---|---|---|---|---|
| Largest file | `RoadSmoother.lua` (972 lines) | `WorldSandboxController.lua` (4,103 lines) | `DispatchTab.lua` (~2,794 lines) | `DispatchTab.lua` (~2,520 lines) | Improved |
| WorldSandboxController lines | — | 4,103 | 870 | 870 | ✅ -79% |
| DispatchTab lines | — | ~2,794 | ~2,794 | ~2,520 | ✅ -10% |
| Dedicated generation services | 1 | 1 | 11 | 11 | ✅ |
| Dispatch services | 3 | 3 | 3 | 7 | ✅ |
| love.* in portable gen code | — | Yes | No | No | ✅ |
| Non-view logic in DispatchTab | — | Yes | Yes | No | ✅ |
| God Objects remaining | — | 2 | 1 (DispatchTab) | 0 | ✅ |
| MVC violations (models) | 20+ | 30+ | 30+ | 30+ | Unchanged |

---

## 6. Recommended Next Actions (Priority Order)

1. **Decouple Vehicle/Map Rendering** — Move `love.graphics` calls into `VehicleRenderer` / `MapRenderer` in `views/`. Removes the last barrier to headless model testing.
2. **Formalize Game global writes** — Prevent Views from writing to the `Game` object directly; route all `Game` state mutations through a controller method.
3. **Data-driven dispatcher** — Refactor dispatcher to use a property registry rather than hardcoded string checks, enabling automatic discovery of new block/vehicle properties.
