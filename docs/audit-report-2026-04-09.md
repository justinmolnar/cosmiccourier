# Architectural Audit Report — April 9, 2026

## Executive Summary
The April 8 audit flagged `WorldSandboxController.lua` (~3,750 lines) as the single largest maintainability bottleneck. That refactor is now complete. The controller has been reduced from 4,103 lines to **870 lines** — a 79% reduction — with all domain logic extracted into focused, testable service files. The remaining open issues are `DispatchTab.lua` and MVC leakage in models.

---

## 1. Resolved Since April 8

### 1.1 WorldSandboxController God Object — RESOLVED ✅
**Before:** 4,103 lines. Single file owned terrain generation, city placement, highway routing, district/arterial/street generation, WFC zone grid, road network construction, city map assembly, world/city/HUD image rendering, game bridge (FFI grid, vehicle reset, world hierarchy), camera/viewport, and input handling.

**After:** 870 lines. Pure orchestration, camera, and input. All domain logic extracted into:

| Service | Lines | Responsibility |
|---|---|---|
| `utils/WorldGenUtils.lua` | ~80 | Shared pure helpers (bilinear, subcell elevation, heap) |
| `services/WorldNoiseService.lua` | existing | Terrain noise, heightmap, biome, moisture, rivers |
| `services/CityPlacementService.lua` | ~200 | City seed placement + suitability scoring |
| `services/HighwayService.lua` | ~220 | A* highway routing between cities |
| `services/CityBoundsService.lua` | ~290 | Dijkstra city footprint flood-fill + POI placement |
| `services/CityDistrictService.lua` | ~280 | Sub-cell district flood-fill + WFC type assignment |
| `services/CityArterialService.lua` | ~380 | Direction-aware 8-dir Dijkstra arterial roads |
| `services/CityStreetService.lua` | ~110 | Zone-boundary street grid generation |
| `services/MapBuilderService.lua` | ~700 | WFC zone grid + road network + Map assembly |
| `services/WorldImageService.lua` | ~310 | Love2D rendering: world image, hi-res, city image |
| `services/GameBridgeService.lua` | ~382 | FFI unified grid, vehicle/depot reset, world hierarchy |

**Portability boundary enforced:** All generation services (`CityPlacement*` through `MapBuilder*`) have zero `love.*` imports and zero game struct references. They receive math functions via `math_fns = { noise = love.math.noise, random = love.math.random }` injection, preserving bit-identical RNG output. `WorldImageService` and `GameBridgeService` are intentionally non-portable.

---

## 2. Remaining Issues

### 2.1 DispatchTab God View (~2,420 lines)
`views/tabs/DispatchTab.lua` remains a View component performing heavy logic: dispatch rule evaluation, filtering, and block execution that belongs in services or models. This is now the largest single-file maintainability risk in the codebase.

### 2.2 Non-Agnostic Rendering (MVC Leakage)
`models/vehicles/Vehicle.lua` and `models/Map.lua` still contain direct `love.graphics` calls, preventing headless execution of game logic.

### 2.3 Global State Coupling
`views/GameView.lua` and other views still write directly to the `Game` global object rather than routing mutations through controller methods.

---

## 3. Metrics

| Metric | April 8, 2026 | April 9, 2026 | Trend |
|--------|---------------|---------------|-------|
| `WorldSandboxController.lua` | ~3,750 lines | **870 lines** | ✅ Resolved |
| `views/tabs/DispatchTab.lua` | ~2,420 lines | ~2,420 lines | 🚩 Open |
| Portable world-gen services | 0 | **11** | ✅ Improved |
| God Functions in controller | 25+ | 0 | ✅ Resolved |
| MVC violations (controller) | High | None | ✅ Resolved |
| MVC violations (models/views) | 30+ | 30+ | 🚩 Unchanged |

---

## 4. Recommended Next Actions

1. **Fragment DispatchTab**: Extract dispatch rule evaluation and filtering into `services/DispatchRuleService.lua`; the tab should only render and delegate.
2. **Decouple Vehicle/Map Rendering**: Move `love.graphics` calls out of `Vehicle.lua` and `Map.lua` into dedicated renderer classes in `views/`.
3. **Formalize Controller Layer**: Prevent views from writing to the `Game` global; route all state mutations through controller methods.
