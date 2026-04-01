# Cosmic Courier — Abstraction & Componentization Audit

> Conducted: 2026-03-31
> Focus: Logic that is embedded inline in code but should be extracted into separate, reusable, code-agnostic modules. The calling code should not know HOW something works — only that it does.

---

## Table of Contents

1. [Data That Should Be Data](#1-data-that-should-be-data)
2. [Inline Algorithms That Should Be Modules](#2-inline-algorithms-that-should-be-modules)
3. [Business Rules Embedded in Logic Code](#3-business-rules-embedded-in-logic-code)
4. [Copy-Pasted Patterns](#4-copy-pasted-patterns)
5. [State Machines Written as If-Else](#5-state-machines-written-as-if-else)
6. [Strategy Patterns Waiting to Happen](#6-strategy-patterns-waiting-to-happen)
7. [Coordinate Math Scattered Everywhere](#7-coordinate-math-scattered-everywhere)
8. [Rendering Logic Mixed with Data Logic](#8-rendering-logic-mixed-with-data-logic)
9. [Hardcoded Thresholds That Are Tuning Parameters](#9-hardcoded-thresholds-that-are-tuning-parameters)
10. [Proposed New Modules](#10-proposed-new-modules)
11. [Priority Order](#11-priority-order)

---

## 1. Data That Should Be Data

These are if/elseif chains or scattered constants that encode facts about the world. The code should just look them up.

---

### Zone Types — No Single Source of Truth

Zone type strings appear in at least **8 separate files** with no central definition. Every consumer re-defines or re-checks them independently.

| Where | What it does |
|-------|-------------|
| `WFCZoningService.lua:7–21` | ZONES table (colors, weights) |
| `WFCZoningService.lua:24–55` | ZONE_CONSTRAINTS + ADJACENCY tables |
| `BlockSubdivisionService.lua:6–23` | ZONE_BLOCK_SIZE_FACTORS (13 entries, arbitrary divisors) |
| `WFCZoningService.lua:218, 226, 234, 242, 294, 300, 304, 308` | Inline `if zone == "industrial_heavy" or zone == "industrial_light" or zone == "warehouse"` repeated 6+ times |
| `WFCZoningService.lua:288–321` | Zone-specific distance preferences in scoring function |
| `zone_types.lua` | Separate definitions that duplicate the above |
| `data/districts.lua` | District zone names hardcoded again |
| `views/WorldSandboxView.lua:6–30` | BIOME_LEGEND table with 24 hardcoded RGB values |

**What this should be:** A single `data/zones.lua` with:
```lua
Zones.TYPES = { "downtown", "commercial", "residential_north", ... }

Zones.CATEGORIES = {
    industrial = { "industrial_heavy", "industrial_light", "warehouse" },
    residential = { "residential_north", "residential_south" },
    commercial = { "commercial", "entertainment", "tech" },
    parks = { "park_central", "park_nature" },
    public = { "university", "medical" },
}

Zones.DEFINITIONS = {
    commercial = {
        color = { 0.9, 0.7, 0.3 },
        block_size = { min = 4, max = 8 },
        placement = { ideal_dist_from_downtown = 0.3, edge_preference = false },
        adjacency_bonus = { ... },
    },
    -- etc
}

function Zones.getCategory(zone_type) ... end
function Zones.isType(zone_type, category) ... end
```

Then `WFCZoningService`, `BlockSubdivisionService`, views, and everything else read from this one place. Adding a zone means one file edit.

---

### Tile Colors — 13-Way If-Else in Map.lua

`Map.lua:40–67` (`getTileColor`) is a 28-line if/elseif chain mapping tile type strings to RGB tuples. There's also a downtown variant embedded inside the same chain.

**What this should be:**
```lua
-- data/tile_palette.lua
return {
    road         = { 0.55, 0.55, 0.58 },
    downtown_road = { 0.65, 0.65, 0.70 },
    highway      = { 0.85, 0.75, 0.30 },
    grass        = { 0.35, 0.55, 0.25 },
    -- etc
}
```

`Map.lua` becomes one line: `return TILE_PALETTE[tile.type] or TILE_PALETTE.default`.

---

### Road Type Categories — Pathfinding Cost Lookup Scattered

`PathfindingService.lua:44–54` checks road type strings inline to determine which cost category to use:
```lua
if t == "highway" or t == "highway_ring" or t == "highway_ns" or t == "highway_ew" then
```

This grouping is a game design decision baked into pathfinding code.

**What this should be:**
```lua
-- data/road_categories.lua
return {
    arterial     = "arterial",
    highway      = "highway",
    highway_ring = "highway",
    highway_ns   = "highway",
    highway_ew   = "highway",
    road         = "road",
    downtown_road = "road",
}
```

Adding a new road type means one line in the data file, not a search through pathfinding logic.

---

### Scale Zoom Hierarchy — Embedded in Event Handlers

`EventService.lua:123–153` contains two mirrored functions for zoom in and zoom out, each with a hardcoded WORLD → CONTINENT → REGION → CITY → DOWNTOWN chain. The scale progression is a design fact, not event logic.

**What this should be:**
```lua
-- data/map_scales.lua
local SCALE_HIERARCHY = { S.WORLD, S.CONTINENT, S.REGION, S.CITY, S.DOWNTOWN }

function getNextScale(current, direction) ... end
function getPrevScale(current) ... end
```

`EventService` just calls `MapScales.getNext(current, "in")` — it doesn't know the hierarchy.

---

### Biome Legend — View File Owns Biome Definitions

`WorldSandboxView.lua:6–30` defines a 24-entry BIOME_LEGEND table with hardcoded names and RGB values. The world gen and the view define biomes independently — if one changes, the other silently goes out of sync.

**What this should be:** `data/biomes.lua` loaded by both `WorldNoiseService` and the view. The view just iterates whatever biomes are defined; it doesn't own the list.

---

## 2. Inline Algorithms That Should Be Modules

These are algorithmic chunks of 20+ lines doing a named, reusable thing — sitting inline inside a larger function.

---

### Downtown Bounds Calculation — In At Least 6 Files

The same formula appears across:
- `BlockSubdivisionService.lua:44–52`
- `NewCityGenService.lua:54–61` and `118–123`
- `GrowthStreetService.lua:15–18`
- `OrganicStreetService.lua:19–22`
- `RadialStreetService.lua:22–25`
- `WfcLabController.lua:269–276`

All computing the same thing:
```lua
local dt_x1 = math.floor((width - downtown_w) / 2) + 1
local dt_y1 = math.floor((height - downtown_h) / 2) + 1
local dt_x2 = dt_x1 + downtown_w - 1
local dt_y2 = dt_y1 + downtown_h - 1
```

**What this should be:**
```lua
-- In MapUtils or CoordinateSystem
function getDowntownBounds(grid_w, grid_h, constants)
    local dw = constants.MAP.DOWNTOWN_GRID_WIDTH
    local dh = constants.MAP.DOWNTOWN_GRID_HEIGHT
    local x1 = math.floor((grid_w - dw) / 2) + 1
    local y1 = math.floor((grid_h - dh) / 2) + 1
    return { x1 = x1, y1 = y1, x2 = x1 + dw - 1, y2 = y1 + dh - 1 }
end
```

If the centering formula ever changes, it changes in one place.

---

### Chaikin Curve Smoothing — In Two Files

`vehicle_states.lua:8–19` (`chaikin_flat`) and `RoadSmoother.lua:47–56` (`chaikin`) both implement the same curve-smoothing algorithm with identical 0.75/0.25 weights.

**What this should be:** `lib/path_utils.lua` with `chaikin(points, iterations)`. Both callers import it.

---

### Bresenham Line Rasterization — In Three Files

`OrganicStreetService.lua:34–49` and `RadialStreetService.lua:37–52` contain identical 15-line Bresenham implementations. A third variant appears in `connecting_roads.lua:263–286`.

**What this should be:**
```lua
-- lib/rasterize.lua
function rasterizeLine(x1, y1, x2, y2, callback)
    -- Bresenham; calls callback(x, y) for each cell
end
```

All three callers pass their own `write_road` as the callback. One algorithm to maintain.

---

### BFS Road Network Detection — Inline in Map.lua

`Map.lua:81–110` (`getPlotsFromGrid`) implements a 30-line BFS to find connected road networks, then finds adjacent plots. This is a graph algorithm embedded in a model.

**What this should be:**
```lua
-- lib/grid_search.lua
function floodFill(grid, start_x, start_y, passable_fn) ... end
function getAdjacentCells(grid, cells, match_fn) ... end
```

`Map.lua` describes what it wants, not how to search for it.

---

### Walker-Based Path Generation — Inline in connecting_roads.lua

`connecting_roads.lua:60–139` implements a random walker with 4 death conditions, direction bias, momentum, and center-pull physics, all written as straight procedural code inside the generator.

**What this should be:** A `WalkerAgent` module with `create()`, `step(walker, grid)`, `isDead(walker)`. The generator creates walkers and calls step, but doesn't contain the physics.

---

### Ring Road Angle Filtering — Three Interleaved Functions

`ringroad.lua:34–100` has `filterSharpAnglesAggressive()`, `filterSharpAnglesLenient()`, and `wouldCreateBacktrack()` — three geometric functions with shared thresholds, all mixed into the ring generation file.

**What this should be:**
```lua
-- lib/path_filter.lua
function filterByAngle(nodes, min_angle_deg) ... end
function removeBacktracks(nodes, threshold) ... end
```

Ring generation calls these with its chosen parameters. The geometry lives elsewhere.

---

### Smooth Path Builder — Inline in vehicle_states.lua

`vehicle_states.lua:22–95` (`buildSmoothPath`) is an 73-line function that does road-node degree checking, tile-vs-junction distinction, and Chaikin smoothing — all inside the vehicle state module.

**What this should be:** `services/PathSmoothingService.lua` with `buildSmoothPath(path, map, tps)`. Vehicle states call it and get back waypoints. They have no idea how smoothing works.

---

## 3. Business Rules Embedded in Logic Code

These are "if this vehicle type, do this" or "if this zone, use that threshold" conditions that encode game design decisions inside algorithms.

---

### Trip Type Selection — Rules Buried in TripGenerator

`TripGenerator.lua:29–47` contains the rule system for which trip types are available:
- No trucks → downtown only
- Trucks but no metro → 40% downtown, 60% city
- Metro unlocked → still 40/60 (inter-city disabled)

These are game balance decisions written as if/else conditions inside the generator.

**What this should be:**
```lua
-- data/trip_rules.lua
return {
    no_trucks    = { weights = { downtown = 1.0, city = 0.0, intercity = 0.0 } },
    trucks       = { weights = { downtown = 0.4, city = 0.6, intercity = 0.0 } },
    metro        = { weights = { downtown = 0.3, city = 0.5, intercity = 0.2 } },
}
```

`TripGenerator` reads the state, looks up the rule, picks a weighted type. Rebalancing is a data edit.

---

### Vehicle Visibility by Scale — Hardcoded Per-Type in Vehicle.lua

`Vehicle.lua:263–272` checks `self.type == "bike"` and `self.type == "truck"` to decide which map scales each vehicle appears at. This is a display rule, not vehicle behavior.

**What this should be:** Part of each vehicle's properties config:
```lua
bike  = { visible_at_scales = { S.DOWNTOWN, S.CITY } }
truck = { visible_at_scales = { S.DOWNTOWN, S.CITY, S.REGION } }
```

`Vehicle:shouldDrawAtScale(scale)` just checks its own config. No type string checks.

---

### Trip Eligibility — Scattered Across Three Files

Whether a vehicle can handle a trip is checked in:
- `vehicle_states.lua:495–511` — long-distance + truck + metro license check
- `AutoDispatcher.lua:33–47` — vehicle type vs trip required type
- `TripGenerator.lua` — implicit in trip creation logic

**What this should be:**
```lua
-- services/TripEligibilityService.lua
function canVehicleHandleTrip(vehicle, trip, game_state)
    -- returns { eligible = bool, reason = string }
end
```

All three callers use this one function. The rules live in one place.

---

### Arterial Constraint Logic — Hardcoded First/Second Arterial

`ArterialRoadService.lua:46–53`:
```lua
if i == 1 then
    -- force through downtown
elseif i == 2 then
    -- force through largest district
end
```

The constraint rules for each arterial are embedded in the counting loop. You cannot add a third arterial without editing this if-else.

**What this should be:**
```lua
local ARTERIAL_CONSTRAINTS = {
    { type = "must_pass_through", target = "downtown" },
    { type = "must_pass_through", target = "largest_district" },
    { type = "prefer_quadrant_coverage" },
}
```

The loop reads constraints from the table — it doesn't know which arterial is "special."

---

### Upgrade Effect Dispatch — If-Else Chain in UpgradeSystem

`UpgradeSystem.lua:68–105` (`applyDataDrivenEffect`) has a 5-branch if/elseif for effect types (`set_flag`, `add_stat`, `multiply_stat`, `multiply_stats`, `special`), then `applyStatToGameValues` adds another 50-line function for stat-specific logic.

**What this should be:**
```lua
local effect_handlers = {
    set_flag      = function(effect, state) ... end,
    add_stat      = function(effect, state) ... end,
    multiply_stat = function(effect, state) ... end,
    special       = function(effect, state) ... end,
}

function applyEffect(effect, state)
    local handler = effect_handlers[effect.type]
    if handler then handler(effect, state) end
end
```

Adding a new effect type is adding one entry to the table.

---

## 4. Copy-Pasted Patterns

Blocks of 5+ lines appearing more than once in slightly different form — meaning the same bug needs to be fixed in multiple places.

---

### `write_road()` — Copied Into 3 Street Services

Identical function in `GrowthStreetService`, `OrganicStreetService`, `RadialStreetService`. Also each independently does `Game.street_segments = {}` without `Game` being a function parameter.

**Fix:** `services/streets/StreetServiceBase.lua` with shared helpers. Each service inherits or imports.

---

### Highway `createFlowingPath()` — Two Near-Identical Files

`highway_ew.lua:50–99` and `highway_ns.lua:24–72` are the same algorithm. The only difference: one biases horizontal movement, one biases vertical. Same for `calculateCurveAroundDistrict()` in both files.

**Fix:**
```lua
-- models/generators/HighwayGenerator.lua
function createFlowingPath(start, goal, districts, params)
    -- params.axis = "horizontal" or "vertical"
end
```

Both `highway_ew` and `highway_ns` are thin wrappers that set the axis and call the shared function.

---

### Downtown Dense Grid — Same Pattern in 3 Street Services

All three street services apply the same nested loop to lay a grid of roads over downtown:
```lua
for dy = dt_y1, dt_y2, dt_block do
    for dx = dt_x1, dt_x2 do write_road(dx, dy) end
end
```

**Fix:** A single `applyDowntownGrid(city_grid, downtown_bounds, block_size)` function called by all three.

---

### Input Dispatch Pattern — Repeated in 6 Event Handlers in main.lua

```lua
if Game.world_sandbox_controller and Game.world_sandbox_controller:isActive() then
    Game.world_sandbox_controller:handle_mouse_down(x, y, button)
    return
end
if Game.sandbox_controller and Game.sandbox_controller:isActive() then
    ...
end
```

Appears in `keypressed`, `mousepressed`, `mousereleased`, `mousemoved`, `textinput`, `mousewheelmoved`.

**Fix:** A single `InputDispatcher` that holds an ordered list of controllers and tries each. `main.lua` registers controllers once; each handler is one line.

---

### Constant Save/Restore Around Generation — Twice in SandboxController

The same 8-line block that saves and restores `Game.C.MAP` appears in both `generate()` and `_buildFloodFill()`. If an exception fires, the restore never runs.

**Fix:** One helper function, or better — stop mutating global constants entirely. Pass a params copy to generation functions.

---

### District Overlap Detection — Three Separate Implementations

- `highway_ew.lua:107–115` (`findConflictingDistrict`)
- `highway_ns.lua:61–69` (same function)
- `districts.lua:67–86` (`doDistrictsOverlap`)

All check distance-based overlap with slightly different buffer values (35 vs 15 vs 5), causing inconsistent collision behavior.

**Fix:** `lib/geometry.lua` with `circlesOverlap(cx1, cy1, cx2, cy2, buffer)` and `pointInDistrict(px, py, district, buffer)`. One implementation, explicit buffer per callsite.

---

## 5. State Machines Written as If-Else

---

### Vehicle State Resolution — 10-Branch While Loop

`Vehicle.lua:133–216` (`_resolveOffScreenState`) resolves vehicle state with a while loop containing 10 if/elseif branches checking state name strings (`"To Pickup"`, `"To Dropoff"`, `"Returning"`, etc.), each with its own transition logic.

**What this should be:** A state dispatch table:
```lua
local STATE_RESOLUTION = {
    ["Idle"]              = function(v, g) ... end,
    ["To Pickup"]         = function(v, g) ... end,
    ["To Dropoff"]        = function(v, g) ... end,
    ["Returning"]         = function(v, g) ... end,
}

-- Resolution loop becomes:
local handler = STATE_RESOLUTION[vehicle.state.name]
if handler then handler(vehicle, game) end
```

Adding a state means adding one table entry. The loop body never changes.

---

### Scale-Based Render Dispatch — Nested If-Else in GameView

`GameView.lua:119–159` selects what to render based on `game.lab_grid`, `game.wfc_final_grid`, `game.world_gen_cam_params`, and scale. All conditions are checked sequentially.

**What this should be:** A render mode registry:
```lua
local RENDER_MODES = {
    { condition = function(g) return g.lab_grid ~= nil end,    renderer = LabGridRenderer },
    { condition = function(g) return g.wfc_final_grid ~= nil end, renderer = WFCGridRenderer },
    { condition = function(g) return g.world_gen_cam_params end, renderer = WorldGenRenderer },
}
```

`GameView.draw()` iterates the list and delegates. It has no knowledge of what each renderer does.

---

### Zoom State — Mirrored If-Else in EventService

`EventService.lua:123–153` — two functions for zoom in and zoom out each contain a mirrored chain of scale comparisons. They're the same logic in opposite directions.

**Fix:** `ZoomService.getNextScale(current, "in")` / `getNextScale(current, "out")` — already noted in section 1, but the state machine angle is: EventService should not encode the scale sequence.

---

## 6. Strategy Patterns Waiting to Happen

Places where near-identical code paths differ only by a type string or one parameter — a clear signal that the difference should be injected as data, not branched as code.

---

### Vehicle Types — Subclasses That Should Be Configs

`Bike.lua` and `Truck.lua` subclass `Vehicle.lua`, each overriding `getIcon()` and providing different properties. Truck also has special initialization to find a road. Type string checks appear throughout:
- `Vehicle.lua:263` — `if self.type == "bike"`
- `AutoDispatcher.lua:47` — vehicle type checks
- `vehicle_states.lua:495` — `vehicle.type == "truck"`

**What this should be:** No subclasses. A single `Vehicle` class with a config object per type:
```lua
-- data/vehicle_types.lua
return {
    bike = {
        icon = "🚲",
        speed = 1.0,
        capacity = 1,
        visible_at_scales = { S.DOWNTOWN, S.CITY },
        pathfinding_costs = { road = 1, arterial = 0.8, highway = 5 },
        needs_road_spawn = false,
    },
    truck = {
        icon = "🚛",
        speed = 0.6,
        capacity = 3,
        visible_at_scales = { S.DOWNTOWN, S.CITY, S.REGION },
        pathfinding_costs = { road = 1.2, arterial = 0.9, highway = 0.7 },
        needs_road_spawn = true,
    },
}
```

Adding a new vehicle type is adding an entry to this file.

---

### Street Generation Algorithms — 3 Services, Same Structure

`GrowthStreetService`, `OrganicStreetService`, and `RadialStreetService` all:
1. Compute downtown bounds
2. Apply a generation algorithm
3. Apply a dense grid over downtown
4. Prune connectivity
5. Set `Game.street_segments = {}`

The structure is identical. Only step 2 differs.

**What this should be:** One `StreetGenerator` that runs the pipeline, accepting a `strategy` function for step 2:
```lua
StreetGenerator.generate(city_grid, params, strategy_fn)
```

`GrowthStreetService` provides the growth strategy function. `OrganicStreetService` provides the organic one. The pipeline is not duplicated.

---

### Highway Generators — Two Files, One Direction Parameter

`highway_ew.lua` and `highway_ns.lua` differ by one word. The entire existence of two files is because the axis is hardcoded.

**Fix:** One `HighwayGenerator.lua` with a `direction = "ew" | "ns"` parameter. Delete one of the files entirely.

---

## 7. Coordinate Math Scattered Everywhere

Three different coordinate systems exist (road-node, tile/grid, screen/pixel), and conversions between them are computed ad-hoc inline throughout the codebase. `CoordinateSystem.lua` exists but is incomplete and inconsistently used.

| Conversion | Found in |
|-----------|---------|
| Grid → Pixel | `Vehicle.lua:25–37`, `GameView.lua:45–56`, `vehicle_states.lua:517–530` |
| Pixel → Grid | `EntityManager.lua:100–103`, `InputController.lua:138` |
| Road-node → Pixel | `Vehicle.lua:55–72`, `pathfinder.lua:35–80` |
| Downtown → Global | `SandboxController.lua:579–590`, `NewCityGenService.lua:118–123` |
| Region offset | `Vehicle.lua:106–115`, `vehicle_states.lua:517–530` |

**What this should be:** `CoordinateSystem.lua` made complete and authoritative:
```lua
CoordSys.gridToPixel(gx, gy)          -- tile center in pixel space
CoordSys.pixelToGrid(px, py)          -- pixel to tile
CoordSys.roadNodeToPixel(rx, ry, tps) -- road-node coordinate to pixel
CoordSys.applyRegionOffset(px, py, city_origin, tile_size)
CoordSys.getDowntownBounds(grid_w, grid_h)
CoordSys.screenToWorld(sx, sy, camera)
CoordSys.worldToScreen(wx, wy, camera)
```

Nothing else does coordinate math. Everything else calls these functions.

---

## 8. Rendering Logic Mixed with Data Logic

---

### Camera Mutation During Draw

`GameView.lua:58–90` (`_drawEntitiesOnCityImage`) sets up a virtual camera by **mutating** `Game.camera` during the draw call, then restores it after. This is state mutation inside a rendering function.

**What this should be:** A `CameraTransform` value object:
```lua
local transform = CameraTransform.createVirtual(base_cam, target_bounds)
-- Pass transform to draw calls; never mutate global camera
```

---

### Biome Name Derived from Elevation in View

`WorldSandboxView.lua:250–258` derives biome names by checking elevation thresholds inline during the hover tooltip render. This is game logic in the render path.

**What this should be:** `WorldNoiseService` (or a biome module) exposes `getBiomeName(elevation, temperature, wetness)`. The view calls it and displays the result.

---

### Upgrade Node Styling — Business Logic in `_drawTree()`

`Modal.lua:170–206` determines each node's color, border, and visibility based on `purchased_level`, `can_afford`, `prereqs_met` inline during drawing.

**What this should be:**
```lua
-- Called before draw, returns a display state object
function getUpgradeDisplayState(node, game_state)
    return {
        color = ...,
        border = ...,
        is_visible = ...,
        status_text = ...,
    }
end
```

`_drawTree()` just reads the display state and renders it.

---

### FloatingText — Update Logic in GameState

`GameState.lua:40–49` updates floating text Y position and alpha inside the state model's update function.

**What this should be:** A `FloatingTextSystem` that owns both update and draw, with `FloatingTextSystem.emit(text, x, y)` called by game events. `GameState` holds no floating text logic.

---

## 9. Hardcoded Thresholds That Are Tuning Parameters

These are numbers embedded in conditional logic that represent tunable game balance or generation quality decisions. They should live in a config, not the code.

The most important ones to extract:

| Value | File | Meaning |
|-------|------|---------|
| `0.4 / 0.6` | `TripGenerator.lua:34,42` | Downtown vs city trip ratio |
| `if i == 1` / `if i == 2` | `ArterialRoadService.lua:46–53` | Which arterials get special treatment |
| `math.max(2, math.floor((w+h)/75))` | `ArterialRoadService.lua:15` | Number of arterials formula |
| `12` | `BlockSubdivisionService.lua:286` | Max recursive subdivision depth |
| `8` | `BlockSubdivisionService.lua:292` | "Large block" force-split threshold |
| `MIN_NETWORK_SIZE = 10` | `Map.lua:80` | Min road cells to be a valid network |
| `> 200` | `connecting_roads.lua:103` | Walker max steps |
| `avg_radius = 100` | `ringroad.lua` | Hardcoded ring size for arc calculation |
| `1e9` | `WfcBlockService.lua:58` | Arterial multiplier for WFC weights |
| `0.75 / 0.25` | `vehicle_states.lua:9` | Chaikin algorithm weights |
| `segments_per_span = 8` | `WfcLabController.lua:317` | Catmull-Rom resolution |
| `dist1 <= 2 / dist2 <= 2` | `WfcLabController.lua:411–414` | Lightning bolt detection threshold |
| `500000` | `GameController.lua:127` | Memory warning threshold (bytes? KB?) |

**What this should be:** A `data/WorldGenConfig.lua` and a `data/GameplayConfig.lua`. Numbers live there with comments explaining what they do and what happens if you change them.

---

## 10. Proposed New Modules

Modules that don't exist yet but would absorb the scattered logic above.

| Module | Absorbs |
|--------|---------|
| `data/zones.lua` | Zone types, categories, colors, block sizes, adjacency, placement preferences — single source of truth |
| `data/tile_palette.lua` | All tile type → color mappings |
| `data/road_categories.lua` | Road type → cost category mapping |
| `data/vehicle_types.lua` | Vehicle definitions replacing Bike.lua / Truck.lua subclasses |
| `data/trip_rules.lua` | Trip type selection weights by game state |
| `data/WorldGenConfig.lua` | All generation magic numbers, documented |
| `data/GameplayConfig.lua` | All gameplay magic numbers |
| `lib/path_utils.lua` | Chaikin, RDP simplification, Catmull-Rom (currently split across 3+ files) |
| `lib/rasterize.lua` | Bresenham line (currently duplicated 3x) |
| `lib/grid_search.lua` | BFS/DFS flood fill, network detection (currently inline in Map.lua) |
| `lib/geometry.lua` | Overlap detection, angle calculation, dot product, distance (currently duplicated across highway generators and ringroad) |
| `lib/input_dispatcher.lua` | Controller dispatch replacing 6 copy-pasted blocks in main.lua |
| `services/CoordinateService.lua` | All coordinate conversions, completing and replacing CoordinateSystem.lua |
| `services/PathSmoothingService.lua` | buildSmoothPath, vehicle waypoint construction |
| `services/TripEligibilityService.lua` | canVehicleHandleTrip, replacing 3 scattered eligibility checks |
| `services/ZoomService.lua` | Scale hierarchy traversal |
| `services/StreetPipeline.lua` | Common pipeline for all 3 street services |
| `services/HighwayGenerator.lua` | Merging highway_ew + highway_ns with axis param |

---

## 11. Priority Order

Ordered by: how many files the scattered logic currently infects × how much pain it causes when you want to add something new.

### Do First — Highest Leverage

1. **`data/zones.lua`** — zone type strings are in 8+ files; every new zone is a multi-file change
2. **`CoordinateService.lua`** — coordinate math in 6+ files; off-by-one bugs are invisible until runtime
3. **`getDowntownBounds()` utility** — same formula in 6 files; fixing a centering bug means 6 edits
4. **`HighwayGenerator.lua`** — merge ew/ns; two files maintaining the same algorithm is untenable
5. **`StreetPipeline.lua` + `lib/rasterize.lua`** — 3 services with identical scaffolding and Bresenham

### Do Next — Unblocks Extensibility

6. **`data/vehicle_types.lua`** — adding a vehicle type currently requires a new subclass and edits across 4 files
7. **`data/trip_rules.lua`** — trip balance is invisible; changing ratios requires reading generator code
8. **Trip eligibility into one service** — 3 separate checks that can drift out of sync
9. **`lib/path_utils.lua`** — Chaikin in two places; RDP in one; Catmull-Rom in another
10. **Upgrade effect handler registry** — adding an effect type requires editing a switch statement

### Do Eventually — Cleanliness

11. `data/tile_palette.lua` — Map.lua's color chain is ugly but not dangerous
12. `data/road_categories.lua` — pathfinding cost lookup is small and localized
13. Render mode registry in GameView — it works, just hard to read
14. State dispatch table for vehicles — the if-else works but limits testability
15. `FloatingTextSystem` — currently mixed into GameState update
16. Camera transform value object — mutation-during-draw is risky but hasn't broken yet
17. `lib/geometry.lua` — overlap detection inconsistency is real but low-frequency
