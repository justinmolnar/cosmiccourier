# Cosmic Courier — Codebase Overview

> Generated 2026-04-03. Covers all 74 Lua source files.

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Language | Lua |
| Engine | LÖVE2D (love2d.org) |
| Graphics | LÖVE2D + custom GLSL shaders |
| Procedural gen | Wave Function Collapse, FBM Perlin noise |
| Pathfinding | A* + Hierarchical A* (HPA*) |
| Data | JSON (config, save games) |
| Fonts | Arial TTF + NotoEmoji TTF |

---

## Directory Structure

```
cosmic-courier/
├── main.lua                    # Entry point & initialization
├── conf.lua                    # LÖVE2D window/module config
│
├── config/
│   └── GameConfig.lua          # User preferences (saved to disk)
│
├── core/
│   ├── event_bus.lua           # Pub/sub event system
│   ├── camera.lua              # Camera transform & viewport
│   └── time.lua                # Game time tracking
│
├── data/
│   ├── constants.lua           # All immutable game constants
│   ├── GameplayConfig.lua      # Gameplay tuning knobs
│   ├── WorldGenConfig.lua      # World generation tuning
│   ├── biomes.lua / .json      # Biome definitions
│   ├── zones.lua               # Zone definitions
│   ├── districts.json          # District configurations
│   ├── tile_palette.lua / .json
│   ├── road_categories.lua / .json
│   ├── upgrades.lua / .json    # Upgrade tree data
│   ├── biome_zone_mults.json
│   └── map_scales.lua          # Zoom level definitions
│
├── models/
│   ├── GameState.lua           # Central game state (money, upgrades, etc.)
│   ├── Map.lua                 # Grid management & tile queries
│   ├── EntityManager.lua       # Vehicles, clients, trips registry
│   ├── Trip.lua                # Single delivery trip
│   ├── Client.lua              # Client entity (generates trips)
│   ├── VehicleFactory.lua      # Creates vehicle instances
│   ├── UpgradeSystem.lua       # Upgrade tree & purchase logic
│   ├── AutoDispatcher.lua      # Auto-assigns trips to idle vehicles
│   ├── EventSpawner.lua        # Rush hour & game events
│   └── vehicles/
│       ├── Vehicle.lua         # Base vehicle class
│       ├── Bike.lua            # Bike subclass (downtown only)
│       ├── Truck.lua           # Truck subclass (long distance)
│       └── vehicle_states.lua  # State machine states
│
├── controllers/
│   ├── GameController.lua      # Main update loop coordinator
│   ├── InputController.lua     # Keyboard/mouse → game actions
│   ├── UIController.lua        # Sidebar UI interactions
│   └── WorldSandboxController.lua  # World generation pipeline
│
├── services/
│   ├── PathfindingService.lua  # A* + HPA* route computation
│   ├── PathCacheService.lua    # Path memoization
│   ├── PathScheduler.lua       # Path request queueing
│   ├── PathSmoothingService.lua # Chaikin + RDP curve smoothing
│   ├── CoordinateService.lua   # Single source for coord transforms
│   ├── WorldNoiseService.lua   # FBM/Perlin noise + biome gen
│   ├── TripGenerator.lua       # Trip creation logic
│   ├── TripEligibilityService.lua # Trip/vehicle compatibility
│   ├── VehicleUpgradeService.lua  # Applies upgrade effects
│   ├── AutoDispatcher.lua      # Auto-dispatch logic
│   ├── SaveService.lua         # Serialize/deserialize game state
│   ├── EventService.lua        # EventBus subscription setup
│   ├── ErrorService.lua        # Error logging & crash handling
│   ├── StatsService.lua        # Statistics tracking
│   ├── FloatingTextSystem.lua  # Floating money/damage text
│   └── ChainWalker.lua         # Road chain connection algorithms
│
├── views/
│   ├── GameView.lua            # Main world viewport renderer
│   ├── UIView.lua              # Sidebar panels renderer
│   ├── WorldSandboxView.lua    # World gen preview renderer
│   ├── WorldSandboxSidebarView.lua
│   ├── WorldSandboxSidebarManager.lua
│   ├── UIManager.lua           # Coordinates all UI systems
│   ├── modal_manager.lua       # Modal dialog system
│   ├── UpgradeModalViewModel.lua
│   └── components/
│       ├── Accordion.lua       # Collapsible panel
│       ├── Modal.lua           # Modal dialog
│       ├── Slider.lua
│       ├── TextInput.lua
│       ├── ZoomControls.lua
│       ├── TripsPanelView.lua
│       ├── VehiclesPanelView.lua
│       ├── UpgradesPanelView.lua
│       └── ClientsPanelView.lua
│
├── lib/
│   ├── pathfinder.lua          # Core A* algorithm
│   ├── wfc.lua                 # Wave Function Collapse
│   ├── grid_search.lua         # BFS / flood-fill
│   ├── input_dispatcher.lua    # Priority input routing
│   ├── path_utils.lua          # RDP + Chaikin helpers
│   ├── utils.lua               # deepCopy, misc utilities
│   └── json.lua                # JSON encode/decode
│
├── utils/
│   ├── DrawingUtils.lua
│   └── RoadSmoother.lua
│
├── shaders/                    # GLSL shaders (saturation, alpha effects)
├── assets/fonts/               # Arial.ttf, NotoEmoji.ttf
└── docs/                       # Documentation
```

---

## Architecture

The project follows a classic game engine separation of concerns:

```
Input → Controllers → Services → Models → Views → Renderer
                          ↓
                      EventBus (cross-cutting pub/sub)
```

### High-Level Data Flow

```
love.update(dt)
  └── GameController:update(dt)
        ├── GameState:update(dt)
        ├── EntityManager:update(dt)   ← vehicles, clients
        ├── AutoDispatcher:update(dt)
        ├── EventSpawner:update(dt)
        └── UIManager:update(dt)

love.draw()
  ├── [sandbox mode] WorldSandboxView:draw()
  └── [game mode]
        ├── GameView:draw()        ← world viewport
        ├── UIView:draw()          ← sidebar
        ├── ZoomControls:draw()
        └── ModalManager:draw()
```

---

## Initialization Order (`main.lua`)

| # | Function | What It Does |
|---|----------|--------------|
| 1 | `_initCore()` | Seed RNG, ErrorService, constants, window |
| 2 | `_buildGame()` | Global `Game` table, Map instances, pathfinder, camera |
| 3 | `_loadSave()` | Deserialize `savegame.json` or `lastsave.json` into GameState |
| 4 | `_initSystems()` | UIManager, Accordion panels, controllers, views |
| 5 | `_initInputDispatcher()` | Priority input routing (sandbox > game) |
| 6 | `_loadFonts()` | Arial + NotoEmoji with fallbacks |
| 7 | `_initWorld()` | World generation pipeline |
| 8 | `_initAutoSave()` | 5-minute auto-save interval |

---

## Major Systems

### Map

`Map.lua` manages grid-based tile data. Two map instances exist simultaneously:

- **`Game.maps.city`** — Downtown + surrounding area (~200×200 cells)
- **`Game.maps.region`** — Larger regional view (~1024×768 cells)

Tile types: `grass`, `road`, `downtown_road`, `arterial`, `highway`, `water`, `mountain`, `river`, `plot`, `downtown_plot`

Coordinate spaces are managed exclusively through `CoordinateService.lua`:
- **Grid coords** — 1-indexed `(gx, gy)`
- **Pixel coords** — world space in pixels: `(gx - 0.5) * tile_size`
- **Screen coords** — display space after camera transform
- **Region coords** — large-scale world cell coords

### Vehicles

Class hierarchy using Lua metatables (`Vehicle` → `Bike` / `Truck`):

| Property | Bike | Truck |
|----------|------|-------|
| Cost | 150 | 1200 |
| Speed | 80 | 60 |
| Range | Downtown only | All scales |
| Preferred roads | downtown_road | arterial / highway |
| Path cost (arterial) | 20 | 5 |

**Vehicle state machine** (`vehicle_states.lua`): `Idle → EnRoute → Loading → InTransit → Idle`

Vehicle position is dual: `grid_anchor` (discrete tile) + `px, py` (continuous pixel, used for smooth rendering).

### Pathfinding

Three layers:

1. **`lib/pathfinder.lua`** — Core A* on a grid. Supports corner nodes (intersections) and tile nodes (arterial/highway centers). Manhattan distance heuristic.
2. **`services/PathfindingService.lua`** — Wraps A* with snap-to-road, vehicle cost tables, zone-based graph, and HPA* for inter-city routing.
3. **`services/PathCacheService.lua`** — Memoizes computed paths keyed on `"x1,y1,x2,y2"`.
4. **`services/PathSmoothingService.lua`** — Post-processes raw paths with RDP simplification then Chaikin curve smoothing.

Movement costs are vehicle-dependent; impassable tiles get `IMPASSABLE_COST = 9999`.

### Trips

```
Client:update()
  └── trip_timer fires → TripGenerator.generateTrip()
        ├── 40% chance: downtown trip (Bike)
        └── 60% chance: city trip (Truck)
  └── Trip added to EntityManager.trips.pending

Player (or AutoDispatcher) assigns trip to vehicle
  └── TripEligibilityService checks vehicle type + capacity
  └── Vehicle:assignTrip(trip) → state = EnRoute
  └── PathfindingService.computePath() → vehicle moves along path
  └── On delivery: money added, "package_delivered" event emitted
```

`Trip` supports multi-leg deliveries (bike pickup → truck long-haul). Bonus pay decays in real time; `freeze()`/`thaw()` pause decay during assignment.

### World Generation

Triggered via `WorldSandboxController` (F8 to open sandbox):

1. **Heightmap** — `WorldNoiseService` stacks FBM layers: continental shape, terrain variation, ridged mountains, coastline detail.
2. **Biomes** — Elevation + moisture (second Perlin octave) → biome category.
3. **City placement** — Score terrain suitability; place cities at local maxima.
4. **Highways** — A* between city pairs on heightmap graph; mark highway cells.
5. **City street grids** — WFC (`lib/wfc.lua`) collapses zone constraints per city.
6. **Districts** — Zone segments built from WFC output, stored in `city_district_maps`.
7. **Send to game** — `sendToGame()` populates `Game.maps`, spawns entities.

World grid: 600×300 cells. Output stored in `WorldSandboxController` state tables (`heightmap`, `colormap`, `city_locations`, `city_zone_grids`, etc.).

### Rendering

**GameView** renders layers back-to-front:
1. Base grid tiles (grass, roads, plots)
2. City canvas overlays (zoom-driven alpha + saturation shader)
3. Arterial roads
4. Zone/district colored regions
5. Vehicles (icon-based; culled below `ENTITY_THRESHOLD` zoom)
6. Clients
7. Debug overlays (F3, B, P, G, V, N, etc.)

Zoom thresholds drive LOD transitions:

| Constant | Scale | Effect |
|----------|-------|--------|
| `CITY_IMAGE_THRESHOLD` | 1.5 | City canvas images appear |
| `ENTITY_THRESHOLD` | 4.0 | Vehicles become visible |
| `ZONE_THRESHOLD` | 6.0 | District colors visible |
| `BIKE_THRESHOLD` | 8.0 | Bikes visible |
| `FOG_THRESHOLD` | 8.0 | Fog overlay |

**UIView** renders a 280px sidebar with scissor-clipped Accordion panels: Stats, Trips, Vehicles, Upgrades, Clients.

### Upgrades

`UpgradeSystem.lua` loads the tree from `data/upgrades.json`. Purchasing an upgrade:
- Checks cost + prerequisites
- Deducts money from `GameState`
- Applies effect (speed multiplier, unlock auto-dispatch, extend frenzy duration, etc.)
- Emits event for UI refresh

### Event Bus

All cross-system communication goes through `core/event_bus.lua`:

```lua
game.EventBus:publish("package_delivered", trip, payout)
game.EventBus:subscribe("package_delivered", function(trip, payout) ... end)
```

Key events: `map_scale_changed`, `package_delivered`, `trip_created`, `ui_assign_trip_clicked`, `ui_buy_vehicle_clicked`, `ui_purchase_upgrade_clicked`.

---

## Code Patterns & Conventions

### OOP via metatables

```lua
local MyClass = {}
MyClass.__index = MyClass

function MyClass:new(...)
    return setmetatable({}, MyClass)
end

function MyClass:method() end

return MyClass
```

Inheritance: `setmetatable(Child, {__index = Parent})`.

### Stateless services

Services expose only static functions — no instance required:

```lua
local PathfindingService = {}
function PathfindingService.computePath(map, vehicle, start, goal) ... end
return PathfindingService
```

### UI components

All UI components share the same interface:

```lua
Component:update(dt, game)
Component:draw(game)
Component:handle_mouse_down(x, y, button)
Component:handle_mouse_up(x, y, button)
Component:handle_scroll(x, y, dy)
```

### Configuration tiers

| Layer | File | Purpose |
|-------|------|---------|
| Constants | `data/constants.lua` | Immutable game balance, read-only at runtime |
| Gameplay config | `data/GameplayConfig.lua` | Tunable gameplay parameters |
| User config | `config/GameConfig.lua` | Saved preferences (fullscreen, etc.) |

### Error handling

```lua
Game.error_service.withErrorHandling(function()
    -- risky code
end, "Context Label")
```

Also: `logInfo()`, `logWarning()`, `logError()`.

---

## Notable File Sizes

| File | Lines |
|------|-------|
| `WorldSandboxController.lua` | 3,934 |
| `GameView.lua` | 1,541 |
| `WorldNoiseService.lua` | 1,049 |
| `Map.lua` | 451 |
| `PathfindingService.lua` | 354 |
| `main.lua` | 251 |
| `UpgradeSystem.lua` | 235 |
| `EntityManager.lua` | 132 |

`WorldSandboxController.lua` is by far the heaviest file and the main candidate for splitting.

---

## Input Routing

`lib/input_dispatcher.lua` routes all LÖVE2D input callbacks with priority:

- **F8** always toggles the world sandbox
- **Sandbox active** → `WorldSandboxController` handles input
- **Game active** → `InputController` handles input; `UIController` handles sidebar clicks

Key bindings (game mode):
- `ESC` — quit
- `F3` — debug overlay
- `TAB` — toggle debug mode
- `S` — toggle smooth vehicle movement
- `B/P/G/V/N` — individual debug layer toggles
- Middle-mouse drag — pan camera
- Scroll wheel — zoom

---

## Save System

`SaveService.lua` serializes `GameState` to `savegame.json` (manual save) and `lastsave.json` (auto-save, every 5 minutes). On load, `_loadSave()` tries `savegame.json` first, then `lastsave.json`.
