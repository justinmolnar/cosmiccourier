# Architectural Audit Report - April 9, 2026

## Executive Summary
The `cosmic-courier` codebase exhibits several architectural anti-patterns common in evolving game projects. While functional, the system suffers from significant "God Object" inflation, MVC boundary leakage, and tight coupling between procedural generation logic and data structures.

---

## 1. God Objects (High Risk)
These files have grown too large (500+ to 2000+ lines) and handle too many unrelated responsibilities.

| File | Primary Responsibility | Violations |
| :--- | :--- | :--- |
| `views/GameView.lua` | Main World Rendering | Contains ~2000 lines. Handles camera math, shader management, world-highway path building, and complex geometric logic that should be in services. |
| `services/WorldNoiseService.lua` | Terrain Generation | Contains ~1000 lines. Mixes pure noise math with biome color logic and river routing. |
| `services/MapBuilderService.lua` | City Assembly | Contains ~800 lines. Orchestrates WFC, road networking, and district assignment in monolithic functions. |
| `services/InfrastructureService.lua` | World Mutation | Manages tile-level mutations, cost calculations, and HPA* hierarchy sync. |
| `models/Map.lua` | World State | Handles grid storage, flood fills for plots, and scale transitions. |

---

## 2. MVC Violations
The separation between Model, View, and Controller is frequently breached, leading to fragile code.

### Model/Service -> View Leakage
*   **`models/EntityManager.lua`**: Directly calls `love.graphics.getWidth()` and `getHeight()` to calculate viewport culling.
*   **`models/EventSpawner.lua`**: Calls `love.graphics.getDimensions()` and `love.math.random()` for world-space logic.
*   **`services/WorldNoiseService.lua`**: Uses `love.math.noise` and `love.graphics` constants/colors.

### View -> Logic Leakage
*   **`views/GameView.lua`**: Implements `_buildWorldHighwayPaths`, which is complex graph traversal logic that belongs in a Service.
*   **`views/UIManager.lua`**: Manages "Income Per Second" and "Trips Per Second" calculations (`_calculatePerSecondStats`), which are business logic.

---

## 3. Logic & Data Coupling
Data structures are often "blind" to their own schema, requiring logic files to have deep knowledge of internal table shapes.

*   **Biome Definitions**: `services/InfrastructureService.lua` has a hardcoded `TERRAIN_COST` table that maps strings from `data/biomes.lua`. If a biome name changes in the data, the service breaks silently.
*   **State Bloat**: `models/GameState.lua` initializes everything from upgrade definitions to dispatch rules and event setups. It acts as a central hub that every system must touch.
*   **Coordinate Conversions**: Logic for converting between Screen, World, Grid, and Sub-cell coordinates is duplicated across `CoordinateService.lua`, `GameView.lua`, and `Map.lua`.

---

## 4. Redundancy & Over-engineering
*   **Stats Tracking**: Multiple systems (UIManager, GameController, StatsService) track or calculate frame-based delta values independently.
*   **Road Smoothing**: There is overlap between `utils/RoadSmoother.lua` and the inline path smoothing in `views/GameView.lua`.

---

## 5. Strategic Recommendations

1.  **Decompose `GameView.lua`**: Extract the `_buildWorldHighwayPaths` and geometric projection logic into `services/WorldImageService.lua` or a dedicated `WorldGeometryService`.
2.  **Cleanse Models of Rendering**: Pass viewport bounds *into* the `EntityManager:update` from the Controller rather than having the Model query `love.graphics`.
3.  **Unify Coordinate Authority**: Force all systems to use `services/CoordinateService.lua` for any conversion, removing inline math from views and models.
4.  **Data-Driven Services**: Move `TERRAIN_COST` and similar mapping tables into `data/` JSON or Lua configuration files so logic doesn't need to be modified for balance changes.
5.  **Extract Stats Logic**: Move all "Per Second" and "History" calculations into `services/StatsService.lua`, making `UIManager` a pure consumer of pre-calculated strings or values.
