# Cosmic Courier — Performance Plan

> Created: 2026-04-02
> Scope: Rendering, pathfinding, memory — all systems that cap vehicle count
> Goal: Support hundreds → thousands of simultaneous vehicles (idle game scale)
> Audit sources: Three parallel agent audits of GameView, pathfinder, vehicle update, and grid systems

---

## Critical Rules

1. **No phase begins until the previous phase is complete and tested.**
2. **Test with the F-key stress test (50 bikes + 50 trucks + 25 clients + 100 trips) after every phase.**
3. **No feature work during a performance phase.** The game must behave identically before and after.
4. **Measure before and after.** Note FPS with F-key test at start and end of each phase.
5. **Each phase is a single commit.** Do not combine two phases into one commit.
6. **If a phase uncovers a real bug, fix the bug in a separate commit first.**

---

## Current State

| Metric | Value |
|--------|-------|
| Map tile draw calls per frame (300×300 city) | ~90,000 |
| A* complexity | O(n²) — linear scan, no min-heap |
| Vehicle.path node removal | O(path_length) per node — `table.remove(t,1)` |
| Unified grid memory (1800×900) | ~50–200MB of Lua table structure |
| Path caching | None — identical routes recomputed every trip |
| LuaJIT GC heap practical cap | ~530MB on this machine |
| PathScheduler budget | 8 A* calls/frame |
| Tile type storage | String keys in Lua tables |

---

## Phase 1 — Map Canvas Caching + Viewport Culling

**Goal:** Eliminate the biggest single performance drain. The city tile grid calls `setColor()` + `rectangle()` for every tile on every frame. A 300×300 city produces ~90,000 draw calls/frame before a single vehicle is drawn. This is the primary cause of constant low FPS regardless of vehicle count.

### Tasks

| # | File | Change |
|---|------|--------|
| 1.1 | `models/Map.lua` | Add `Map:buildTileCanvas(C)` — renders entire tile grid to a `love.graphics.newCanvas()` once. Store as `self._tile_canvas`. Extract the tile color logic from `drawGrid()` into a pure `_getTileColor(tile)` local function so it can be called from both the canvas builder and any remaining fallback. |
| 1.2 | `models/Map.lua` | Modify `Map:drawGrid()` — if `self._tile_canvas` exists, draw it with a single `love.graphics.draw(self._tile_canvas, 0, 0)` and return. Otherwise fall through to the per-tile loop. The per-tile loop becomes the fallback for the first frame before the canvas is built. |
| 1.3 | `controllers/WorldSandboxController.lua` | After all city maps are set up in `sendToGame()`, call `map:buildTileCanvas(game.C)` for `game.maps.city` and each `city_N` map. Also call it for any map that has a `drawGrid` called on it. |
| 1.4 | `models/Map.lua` | Add viewport culling to the per-tile fallback loop in `drawGrid()`. Calculate visible tile range from camera bounds: `x0 = floor(cam_world_x0 / ts)`, `x1 = ceil(cam_world_x1 / ts)`, clamp to grid bounds. Only iterate visible rows/columns. |
| 1.5 | `views/GameView.lua` | Add viewport culling for vehicles. Before calling `v:draw(game)`, check if `v.px, v.py` is within the camera viewport (plus one tile margin). Skip invisible vehicles entirely — `shouldDrawAtCameraScale` already handles zoom scale but not position bounds. |

### Expected Outcome

Frame time for rendering drops from ~50ms to ~2–3ms. Pressing L multiple times stops causing frame stutters (those were rendering spikes, not pathfinding spikes). FPS with 100 vehicles should be consistently above 60.

### Testing

- Generate world → send to game → press F (stress test) → confirm smooth 60fps with no slideshow.
- Pan across the city at max zoom — confirm tiles render correctly from the canvas.
- Toggle biome/district overlay (I key, D key) — these should still work. The canvas may need to be invalidated and rebuilt when debug overlays that affect tile color are toggled. Add `self._tile_canvas = nil` to any toggle that changes tile appearance.
- Zoom all the way out to world view → zoom back in → canvas still present, no visual artifacts.

### AI Notes

The canvas must be built on the Love2D main thread (GPU operations can't be called from coroutines). `sendToGame()` is called from a coroutine — verify whether canvas creation can happen there or needs to be deferred to the first `love.draw()` call. If it must be deferred, set a `map._needs_canvas_build = true` flag in sendToGame and build in the draw path on the first frame.

The canvas size is `grid_width * tile_pixel_size` × `grid_height * tile_pixel_size`. For a 600×300 city sub-cell grid at `ts/3 ≈ 5px` tiles, that's 3000×1500 pixels — within Love2D's canvas limits. If tile_pixel_size is very small, the canvas may be tiny enough that aliasing is visible at high zoom; test both zoom extremes.

---

## Phase 2 — A* Algorithm: Binary Min-Heap

**Goal:** Replace the O(n²) A* open-set linear scan with a binary min-heap. The current implementation in `lib/pathfinder.lua` (lines ~150–155) scans all open-set nodes to find the minimum fScore each iteration. On the 1800×900 unified grid, long inter-city paths can explore 10,000–50,000 nodes, producing ~250M comparisons per single A* call.

### Tasks

| # | File | Change |
|---|------|--------|
| 2.1 | `lib/pathfinder.lua` | Replace the `while next(openSet)` loop and its inner `for _, node in pairs(openSet)` linear scan with a binary min-heap. Use the lazy-deletion pattern: allow duplicate heap entries for the same node; when popping, skip nodes already in `closedSet`. This avoids implementing decrease-key while giving identical results. |
| 2.2 | `lib/pathfinder.lua` | Add three local functions scoped to `findPath`: `heap_push(h, f, node)`, `heap_pop(h)`, and the closed-set skip check. The heap is a 1-indexed Lua array; push sifts up, pop swaps root with last element and sifts down. |
| 2.3 | `services/PathScheduler.lua` | Raise `PathScheduler.budget` from `8` to `24`. With a heap, each A* call is 5–10x faster; the old budget was chosen to limit frame time per call, not per call count. Test higher values if 24 still causes spikes. |

#### Heap implementation detail

```
heap_push(h, f, node):
    append {f=f, node=node} to h
    sift up: while i > 1 and h[parent].f > h[i].f, swap and move up

heap_pop(h):
    save h[1]
    move h[#h] to h[1], nil h[#h]
    sift down: while smallest child < current, swap and move down
    return saved root

In main loop:
    openHeap = {}        -- min-heap
    inOpen   = {}        -- nodeKey → best gScore seen (for duplicate suppression)
    closedSet = {}       -- nodeKey → true

    seed: push start node with fScore
    loop:
        entry = heap_pop(openHeap)
        if closedSet[entry.key]: continue  (lazy deletion)
        closedSet[entry.key] = true
        if is_end: reconstruct and return
        for each neighbor:
            if closedSet[neighbor]: skip
            tentative_g = gScore[current] + cost(neighbor)
            if not inOpen[nKey] or tentative_g < inOpen[nKey]:
                update gScore, fScore, cameFrom
                inOpen[nKey] = tentative_g
                heap_push(openHeap, fScore[nKey], neighbor)
```

### Expected Outcome

A* calls on the unified grid complete in <1ms for typical city-local trips and <5ms for long inter-city trips. Pressing L (inter-city trip) produces no perceptible stutter even at budget=24. PathScheduler drains the F-test's 100-vehicle queue in ~4 frames instead of ~13.

### Testing

- Press L rapidly 10 times → no lag spike at all.
- Press F → monitor for first 5 seconds → smooth framerate throughout startup.
- Verify vehicles reach correct destinations (algorithm correctness unchanged).
- Verify inter-city truck paths are geometrically correct (not wildly wrong routes).

### AI Notes

Read `lib/pathfinder.lua` in full before editing. The existing code uses specific variable names for `openSet`, `gScore`, `fScore`, `cameFrom` — preserve these names where they persist (cameFrom is still needed for path reconstruction). The `nodeKey` function format may matter — check if it generates strings or numbers; strings are fine, but consistent with the existing code.

The lazy-deletion heap can produce slightly more memory allocation than a proper decrease-key heap because duplicate entries accumulate. For the path lengths involved (<10,000 nodes explored typically), this is negligible. Profile if inter-city paths cause memory spikes.

---

## Phase 3 — Vehicle Path Index + Path Cache

**Goal:** Eliminate two remaining per-frame costs: O(n) array shifts from `table.remove(vehicle.path, 1)` calls, and redundant A* recomputation for routes that vehicles travel repeatedly.

### Tasks

#### 3a — Path index pointer

| # | File | Change |
|---|------|--------|
| 3.1 | `models/vehicles/Vehicle.lua` | Add `instance.path_i = 1` to `Vehicle:new()`. Reset `self.path_i = 1` in `Vehicle:recalculatePixelPosition()` is NOT needed — only reset when `vehicle.path` itself is replaced. |
| 3.2 | `models/vehicles/vehicle_states.lua` | In all state `:enter()` functions that set `vehicle.path = {}`, also set `vehicle.path_i = 1`. In PathScheduler closures that assign `vehicle.path = result`, set `vehicle.path_i = 1`. |
| 3.3 | `models/vehicles/vehicle_states.lua` | In `moveAlongPath()` fallback section (lines ~73–91): replace `vehicle.path[1]` with `vehicle.path[vehicle.path_i]`, and replace `table.remove(vehicle.path, 1)` with `vehicle.path_i = vehicle.path_i + 1`. |
| 3.4 | `models/vehicles/vehicle_states.lua` | In `moveAlongPath()` grid_anchor update section (lines ~60–68): replace `vehicle.path[1]` with `vehicle.path[vehicle.path_i]`, and replace `table.remove(vehicle.path, 1)` with `vehicle.path_i = vehicle.path_i + 1`. |
| 3.5 | `models/vehicles/vehicle_states.lua` | Replace all `#vehicle.path == 0` and `not vehicle.path or #vehicle.path == 0` checks with `(not vehicle.path) or ((vehicle.path_i or 1) > #vehicle.path)`. |
| 3.6 | `controllers/WorldSandboxController.lua` | In the vehicle reset block (line ~1513 area), add `v.path_i = 1` alongside the existing `v.smooth_path_i = nil`. |

#### 3b — Path result cache

| # | File | Change |
|---|------|--------|
| 3.7 | `services/PathCacheService.lua` | **New file.** LRU cache keyed by `"sx,sy>ex,ey"` string. Max 800 entries. `get(sx,sy,ex,ey)` returns cached path or nil. `put(sx,sy,ex,ey,path)` stores result, evicting oldest entry if at cap. `invalidate()` clears cache entirely (call on world regeneration). |
| 3.8 | `services/PathfindingService.lua` | In `findVehiclePathSandbox()`, before calling A*: check `PathCacheService.get(start.x, start.y, end_plot.x, end_plot.y)`. If hit, return it. After A* completes, call `PathCacheService.put(...)` with the result. |
| 3.9 | `controllers/WorldSandboxController.lua` | In `sendToGame()`, after world setup: call `require("services.PathCacheService").invalidate()` to clear any stale paths from a previous generation. |

### Expected Outcome

GC pressure from path array manipulation is eliminated. Bikes making repeat runs between the same buildings skip A* entirely on the second trip. After 2–3 minutes of F-test gameplay, A* call rate visible in PathScheduler queue should drop noticeably (add a temporary `print` counter if you want to verify).

### Testing

- 1000+ frame run with F-test → no GC-pause stutter (the periodic freezes every few seconds should be gone or greatly reduced).
- Vehicles reach correct destinations: path_i approach is functionally identical to table.remove — verify with a few manual trips.
- After `sendToGame()`, force a new inter-city trip → path is recomputed (cache correctly invalidated).
- Deliberately re-run the same route (use L key twice to same destination) → second trip should not show PathScheduler queue grow (cache hit).

### AI Notes

The cache stores path table references. Vehicles must not mutate the path array they receive — with the `path_i` approach from 3a they only read from it, so this is safe. If any code path still calls `table.remove(vehicle.path, ...)`, the cache will be silently corrupted; audit thoroughly.

Cache key collision is impossible with `"sx,sy>ex,ey"` format as long as coordinates fit in Lua's default number-to-string conversion. Coordinates are integers, so this is guaranteed.

---

## Phase 4 — FFI Unified Grid

**Goal:** Replace the 1.62M-slot Lua table grid with a LuaJIT FFI C struct array. This pushes the unified grid outside the GC heap entirely, drops memory from ~50–200MB to ~6.4MB, improves A* cache locality (adjacent tiles are adjacent in memory), and provides the data structure needed for future tile properties (elevation, mountain terrain, water, tunnel flags) without memory explosion.

### Tasks

| # | File | Change |
|---|------|--------|
| 4.1 | `data/constants.lua` | Add `C.TILE` table with integer constants: `GRASS=0, ROAD=1, DOWNTOWN_ROAD=2, ARTERIAL=3, HIGHWAY=4, WATER=5, MOUNTAIN=6`. Add `C.TILE_COSTS` table mapping each integer to pathfinding cost (replaces string-based cost lookups). |
| 4.2 | `controllers/WorldSandboxController.lua` | At top of file, add `local ffi = require("ffi")` and `ffi.cdef[[ typedef struct { uint8_t type; uint8_t elevation; uint8_t flags; uint8_t reserved; } CosmicTile; ]]`. |
| 4.3 | `controllers/WorldSandboxController.lua` | In `sendToGame()`, replace the `ugrid[y][x] = GRASS/HIGHWAY/...` construction with `ffi.new("CosmicTile[?]", uw * uh)`. Stamp highway cells and city grids using 1D index `(y-1)*uw + (x-1)`. Store as `game.maps.unified.ffi_grid`. Keep the Lua `ugrid` table temporarily (see 4.6). |
| 4.4 | `services/PathfindingService.lua` | In `findVehiclePathSandbox()`, if `ffi_grid` is available, read tile type as `ffi_grid[(y-1)*uw + (x-1)].type` (integer) and look up cost via `C.TILE_COSTS[type_int]`. Fall back to the string-based Lua grid if `ffi_grid` is nil (handles sandbox/test maps without FFI grid). |
| 4.5 | `models/vehicles/Vehicle.lua` | Add `Vehicle:getMovementCostForInt(tile_type_int)` that looks up `game.C.TILE_COSTS[tile_type_int]` instead of `self.properties.pathfinding_costs[tileType_string]`. Call this in the FFI pathfinding path. Keep the string-based method for non-FFI maps. |
| 4.6 | `controllers/WorldSandboxController.lua` | After verifying all pathfinding, rendering, and debug code uses the FFI grid (or the fallback shim), remove the Lua `ugrid` table to free the memory. The `umap.grid` field can remain nil or a small metadata stub. |
| 4.7 | `models/Map.lua` | Update `umap:isRoad(t)` to accept an integer type: `return t == T.ROAD or t == T.DOWNTOWN_ROAD or ...`. Keep the string version working for city maps that still use Lua grid tiles. |

### Expected Outcome

Task Manager shows Love2D memory drops ~100–150MB after world generation. LuaJIT GC heap pressure is dramatically reduced. No more 530MB cap issues during normal gameplay. A* on the unified grid is faster due to sequential memory access patterns.

### Testing

- Generate world → send to game → check Task Manager memory before and after vs Phase 3 baseline.
- Press F → all vehicles navigate correctly (FFI pathfinding correctness check).
- Inter-city trip (L key) → truck routes correctly through highway cells.
- Enable biome/district overlays → they still work (overlays may still read Lua grid for rendering; ensure they have a fallback or are updated to read FFI data).
- World regeneration → memory returns to pre-send baseline (FFI array is GC'd when game.maps.unified is replaced).

### AI Notes

`ffi.cdef` must only be called once per unique struct definition across the entire program lifetime. If `ffi.cdef` is called again with the same name, LuaJIT will throw an error on reload. Guard with a module-level flag or use `pcall`. In practice, Love2D reloads the entire Lua state on F5 restart, so this is only an issue if `sendToGame()` is called multiple times in one session (it can be — the user presses F9 to regenerate).

Safe guard pattern:
```lua
if not _CosmicTileDefined then
    ffi.cdef[[ typedef struct { uint8_t type; uint8_t elevation; uint8_t flags; uint8_t reserved; } CosmicTile; ]]
    _CosmicTileDefined = true
end
```

The `umap:findNearestRoadTile()` BFS currently reads `self.grid[cy][cx].type` as a string. Update to read from `ffi_grid` with integer comparison once 4.3 is in place.

---

## Phase 5 — Quick Wins and Tuning

**Goal:** Collect the remaining performance improvements that are each small in scope but collectively meaningful.

### Tasks

| # | File | Change |
|---|------|--------|
| 5.1 | `main.lua` | Add GC tuning immediately after `_buildGame()`: `collectgarbage("setpause", 300)` and `collectgarbage("setstepmul", 400)`. These reduce GC pause frequency at the cost of slightly higher peak memory. Two lines, immediate effect. |
| 5.2 | `controllers/InputController.lua` | Fix the S-key smooth vehicle movement toggle. When toggled ON: (1) call `require("services.PathSmoothingService").buildSnapLookup(game)` to ensure the snap lookup exists, then (2) iterate all vehicles and call `buildSmoothPath(v, game)` for any vehicle with `v.path and #v.path > 0`. Currently vehicles mid-path when S is pressed never get smooth paths until their next trip. |
| 5.3 | `models/AutoDispatcher.lua` | Type-index vehicles at dispatch time. Before the trip loop, build `local by_type = {}` partitioning all vehicles by `v.type`. In the inner loop, iterate `by_type[leg.vehicleType]` instead of all vehicles. Cuts inner loop by ~50% when fleet is split bikes/trucks. |
| 5.4 | `services/PathSmoothingService.lua` | Fix `buildSmoothPath` to handle the case where `game.maps.unified._snap_lookup` is nil — call `buildSnapLookup` internally rather than silently failing. This is a correctness fix that also makes the S-toggle work reliably. |

### Expected Outcome

GC pauses (periodic 100–200ms freezes that happen even with idle vehicles) are reduced or eliminated. S key enables smooth movement for all currently-moving vehicles immediately. AutoDispatcher is measurably faster at scale (1000+ vehicles). Memory behavior is more predictable.

### Testing

- Start game, do nothing for 60 seconds, monitor for GC stutter — should be gone or greatly reduced.
- Press S mid-simulation → vehicles currently on paths begin following smooth curves immediately (not only on next trip).
- Press F → dispatch 100 vehicles → measure time to assign all trips (should be slightly faster than before 5.3).

### AI Notes

Task 5.1 (GC tuning) should go in before 5.2, 5.3, 5.4 since it affects the baseline. The `setpause=300` means "start a GC cycle when heap grows to 300% of live data after last cycle" (default 200%). Higher = less frequent GC, more memory headroom. Don't go above 500 without profiling actual peak usage.

---

## Phase 6 — Future / When Needed

These are not planned for immediate implementation. Document them here so the architecture decisions in Phases 1–5 don't foreclose them.

### Hierarchical Pathfinding (HPA*)

When thousands of vehicles are active, even O(n log n) A* on 1.62M cells will be too slow for the required call rate. HPA* builds an abstract graph of region-to-region connections (city boundary nodes, highway junction nodes) and plans paths at two levels: which abstract edges to traverse, then detailed local A* within each region. The unified grid and FFI tile array from Phase 4 are the correct foundation for this.

### SpriteBatch for Vehicles

Once vehicles have pixel-art sprites instead of emoji, use `love.graphics.newSpriteBatch()` to draw all vehicles in 1–2 draw calls regardless of count. Currently emoji renders via `love.graphics.print()` which can't be batched. The Phase 1 viewport culling is the prerequisite (culled vehicles still need to be excluded from the SpriteBatch).

### Spatial Partitioning

`EntityManager:handle_click()` is O(vehicles). A tile-aligned spatial hash (grid cell → vehicle list) reduces click detection to O(1) and enables proximity queries for future mechanics (depot queuing, vehicle bunching, passenger boarding animations).

### Dedicated Render Thread

Love2D 12.x introduces a separate render thread option. If rendering and update are decoupled, the canvas approach from Phase 1 can be rendered on the GPU thread while the CPU thread runs simulation. This is architecture-level and requires Love2D version upgrade.
