# Terraforming & Infrastructure

## Core Concept

Infrastructure is a graph of edges with costs and traversal requirements. The routing system doesn't know what kind of infrastructure it's using — it sees edge costs. A rail line between two cities is just a trunk edge costing 88. Two highway segments costing 116 each total 232. The router picks the cheaper option. The fact that one is rail and one is asphalt is irrelevant to the routing decision.

A trip that routes through a rail edge gets a leg with `transport_mode: "rail"`. The dispatcher finds a rail vehicle. The trip itself has no knowledge of trains — it just followed the cheapest path through the infrastructure graph.

This extends naturally to any future mode: canal routes, air corridors, pneumatic tubes. They're all just edges with costs and mode tags.

---

## The Infrastructure Graph

Currently the "trunk" is implicitly traced from highway tiles in `ffi_grid`. That needs to become an explicit infrastructure graph that can contain non-tile edges.

```
node: a point in the world (subcell coords or a named station)
edge: connection between two nodes
  - cost: pathfinding weight
  - transport_mode: "road" | "rail" | "water" | "air"
  - traversal_time: estimated seconds (for ETA)
  - bidirectional: bool
  - infrastructure_id: reference to the built object that created this edge
```

The pathfinder traverses this graph the same way it currently traverses highway tiles. The graph just becomes richer over time as infrastructure is built.

**Mode transitions** happen at special nodes — stations, docks, airports. At a transition node, the pathfinder can switch from one mode graph to another, incurring a transfer cost. This is how multi-modal trips work: road → station → rail → station → road. Each segment becomes a separate leg. The trip doesn't know; it just followed the cheapest path.

---

## Tile-Based vs Graph-Based Infrastructure

Two kinds of infrastructure exist:

**Tile-based** (written into ffi_grid): roads, highways, tunnels. These are physical terrain modifications. The pathfinder reads tile costs from the grid directly. Building a highway through a mountain replaces mountain tiles with highway tiles in ffi_grid and updates tile_nodes accordingly.

**Graph-based** (explicit edges): rail lines, ferry routes, air corridors. These don't exist as tiles — they're point-to-point connections added directly to the infrastructure graph. A rail line has two endpoint stations (nodes) and an edge between them. The ffi_grid doesn't change.

The pathfinder already handles both: it traverses tile-centre nodes for highways and corner nodes for street networks. The infrastructure graph extends this with explicit long-range edges.

---

## World Mutation

Currently the world is written once at generation and never touched. Making it mutable requires a single atomic mutation function that keeps all derived data structures in sync.

### What needs updating per infrastructure type

**Road / Highway segment:**
- `ffi_grid` cells: tile type updated (e.g. mountain → highway)
- `tile_nodes[y][x]`: entry added for new traversable tiles
- `road_nodes`: updated if new corner nodes become reachable
- Path cache: flush entries whose bounding box overlaps affected cells
- World highway paths: rebuild (new highway changes trunk routing options)
- City overlay canvas: dirty flag on tiles covering the affected region
- Road smooth paths: rebuild segments adjacent to modified tiles

**Tunnel:**
Same as highway segment. The tunnel is just a sequence of cells whose type changes from mountain/water to a traversable type. Visually distinct but mechanically identical to a highway from the pathfinder's perspective.

**Rail line:**
- Infrastructure graph: add edge between two station nodes
- Station nodes: register as mode-transition points in the graph
- Path cache: flush inter-city entries (new trunk option may exist)
- World highway paths: rebuild to include rail edges in trunk routing
- Rendering: add rail line to world render layer

**Dock / Airport:**
- Infrastructure graph: add mode-transition node at the dock/airport location
- Connect to local road network (nearest road node)
- Add water/air edges to/from other docks/airports if route exists
- Path cache: flush affected entries
- Rendering: place dock/airport sprite at location

### The mutation function

```lua
function World:buildInfrastructure(spec, game)
  -- spec describes what is being built and where
  -- Returns: success bool, error string if failed

  -- 1. Validate placement (terrain requirements, cost, etc.)
  -- 2. Deduct player cost
  -- 3. Apply tile changes to ffi_grid (if tile-based)
  -- 4. Update tile_nodes / road_nodes (if tile-based)
  -- 5. Add graph edges (if graph-based)
  -- 6. Register station/transition nodes (if applicable)
  -- 7. Flush path cache (selective or full)
  -- 8. Mark render artifacts dirty
  -- 9. Optionally trigger vehicle reroute event
end
```

All infrastructure types go through this one function. The spec describes the type and parameters. No infrastructure-specific code outside of this function.

---

## Vehicle Rerouting

When infrastructure is built, existing vehicles don't need to immediately reroute. The lazy approach works well:

- Flush the path cache
- Vehicles finish their current path unaffected
- Next time a vehicle needs a path, it pathfinds fresh and discovers the new infrastructure
- Vehicles in `Stuck` state pick it up on their next retry automatically

Optionally: publish a `"infrastructure_built"` event. Vehicles that are currently idle or returning to depot could subscribe and trigger a fresh dispatch cycle, allowing them to take advantage of new routes sooner.

---

## What's Currently Mutable

| Structure | Type | Mutable? | Notes |
|-----------|------|----------|-------|
| `ffi_grid` | C array (FFI) | Yes | Physically writable, just never written post-init |
| `tile_nodes[y][x]` | Lua table | Yes | Standard table modification |
| `road_nodes[y][x]` | Lua table | Yes | Standard table modification |
| `zone_seg_v/h` | Lua table | Yes | Street network edges |
| `world_highway_paths` | Lua table | Yes | Pre-computed but rebuildable |
| `map.road_v_rxs` etc. | Lua table | Yes | Arterial crossing data |
| City overlay canvases | LÖVE Canvas | Yes | Already have dirty flags |
| Road smooth paths | Lua table | Yes | Rebuilt from road network |
| HPA* attachment nodes | Lua table | Yes | Pre-computed, need rebuild on change |
| `highway_map` | Lua table | Yes | Needs to stay in sync with ffi_grid |

The main risk is `ffi_grid` and `highway_map` diverging. Currently `highway_map` is a separate boolean grid used by `_buildWorldHighwayPaths` for rendering. Any tile mutation must update both atomically.

---

## Rendering Considerations

### Tile-based changes
The city overlay canvas system already has dirty flags. When tiles change, mark the relevant canvas regions dirty. They rebuild on next draw. This already works — it just needs to be called from the mutation function.

For tunnels: tunnel portals and the tunnel line itself need a distinct visual. Options:
- A new tile type (`tunnel`) with its own render style in the canvas system
- An overlay drawn on top of the terrain canvas at tunnel cell positions

### Graph-based infrastructure (rail, water routes, air)
These don't map to tiles. They need a dedicated render layer similar to how `_buildWorldHighwayPaths` traces the highway network. Each infrastructure type gets a trace function that draws its path on the world layer.

Rail: draw tracks between station nodes along the edge path
Ferry/boat: draw a dashed water route line
Air: draw a thin arc between airports (or skip — air routes may be invisible)

These should be canvased at appropriate zoom levels, consistent with how road overlays work.

### New tile types needed
- `tunnel` — mountain/water tile the player has bored through
- `rail` — rail tile (if rail uses tiles rather than graph edges)
- `dock` — coastal tile converted to a dock
- Possibly: `airport` as a special plot type rather than a tile

---

## Building UI Considerations

Player-facing construction would need:
- A "build mode" that shows valid placement positions for the selected infrastructure type
- Cost display and terrain validity checking before placement
- Drag-to-draw for linear infrastructure (roads, rails, tunnels)
- Click-to-place for point infrastructure (docks, airports, stations)

This is a separate UI system, not designed here. The mutation API above is the contract that UI calls into.

---

## What Needs Refactoring First

Before terraforming works cleanly, these pieces should be in place:

1. **Vehicle abstraction refactor** (see vehicle-abstraction-refactor.md) — transport_mode on vehicles and legs must exist so the pathfinder can generate mode-appropriate legs when routing through mixed infrastructure

2. **Infrastructure graph as explicit data structure** — currently the trunk is implicit in highway tile traversal. It needs to become a queryable graph that can hold non-tile edges

3. **`highway_map` / `ffi_grid` sync** — currently two separate representations of the same data. Should be derived from one source of truth

4. **Canvas dirty region API** — currently canvas invalidation is coarse (whole canvas). Should support dirty regions so only affected tiles rebuild, not the entire city overlay

5. **World mutation function** — the atomic update function described above, called by all infrastructure placement code

---

## Implementation Order

1. Extract infrastructure graph from implicit tile traversal into explicit data structure
2. Sync `highway_map` and `ffi_grid` into one source of truth
3. Implement `World:buildInfrastructure(spec)` for tile-based roads/highways
4. Wire canvas dirty regions to the mutation function
5. Test: player builds a road segment, pathfinder uses it, canvas updates
6. Add tunnel support (mountain tile replacement)
7. Add graph-based edges (rail, water) once vehicle abstraction is complete
8. Add mode-transition nodes (stations, docks, airports)
9. Multi-modal leg generation in TripGenerator
