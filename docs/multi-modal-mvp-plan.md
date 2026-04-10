# Cosmic Courier — Multi-Modal Transport MVP Plan

> Created: 2026-04-09
> Source documents: `docs/multi-modal-refactor.md`
> Scope: Pathfinding, Infrastructure, Dispatch, Vehicle/Building data, World gen water tiles
> Goal: End-to-end boat trip — depot → dock A → (shipline) → dock B → destination — using existing dispatch rules

---

## Critical Rules

1. **No phase begins until the previous phase is complete and tested.**
2. **No feature work during a feature phase.** If a phase is structural, the game must behave identically before and after.
3. **One logical change per commit.** Do not combine a rename with a behavior change.
4. **If a phase uncovers a real bug, fix it in a separate commit first.**
5. **Delete the old code.** No backward-compat shims, no commented-out originals.
6. **When a phase is complete: update this document with status, deviations, and line count change. Send the user test instructions. Do NOT commit until the user has tested and explicitly asked to commit.**

---

## Architecture Summary

Ships follow pre-computed **shiplines** — invisible trunk paths across water, generated once when two docks exist, cached in `game.trunks["water"]`. Ships do not pathfind the ocean in real time. The shipline generator uses a direction-aware A* (turn costs baked into node state) so paths curve gently. Water tile subtypes (`coastal_water`, `deep_water`, `open_ocean`) provide the cost gradient that makes routes hug coastlines.

The system is **completely mode-agnostic**: adding trains or planes later requires only a vehicle data file and a building data file. No core logic changes.

---

## Phase 1 — Water Tile Subtypes

**Goal:** World gen assigns water tiles a subtype based on proximity to land. No gameplay change — ships don't exist yet. This is the cost gradient that the shipline generator will consume in Phase 4.

### Tasks

| # | File | Change |
|---|------|--------|
| 1.1 | World gen terrain pass | After land/water assignment, flood-fill outward from all land tiles. Assign `coastal_water` (distance 1–2), `deep_water` (distance 3–5), `open_ocean` (distance 6+). Store as tile subtype in FFI grid. |
| 1.2 | `lib/pathfinder.lua` `_TILE_NAMES` | Add entries for `coastal_water`, `deep_water`, `open_ocean`. |
| 1.3 | `data/constants.lua` or tile palette | Register the three water subtypes with costs/colors so they're visible in debug tile view. |

### Expected Outcome

Water tiles near coastlines are tagged `coastal_water`, open ocean tagged `open_ocean`. Existing road vehicles ignore them (cost 9999 in their tables already). No visual change to the player unless debug tile view is open.

### Testing

- Open debug tile view; verify coastal cells read as `coastal_water`, open sea as `open_ocean`.
- Confirm existing road vehicle pathfinding is unchanged — run a cross-city delivery and verify no regression.

### AI Notes

The flood-fill runs once at map gen time, not at runtime. Cap distance at 6+ to keep `open_ocean` as a stable category. The three subtypes must use the same integer type system as existing tiles in the FFI grid.

---

**Status:** Complete — awaiting user test
**Line count change:** +68 / −4
**Deviation from plan:**
- Plan said "Register the three water subtypes with costs/colors so they're visible in debug tile view." Costs will come from vehicle JSON in Phase 5. Colors are registered now via three new C.MAP.COLORS entries (COASTAL_WATER, DEEP_WATER, OPEN_OCEAN) and tile_palette.json entries.
- Initial implementation used BFS shore-distance. Replaced with direct elevation classification: `h < deep_ocean_max` → open_ocean, midpoint → deep_water, `h < ocean_max` → coastal_water. The heightmap already encodes depth; BFS was redundant.
- Discovered a fourth inline _TILE_NAMES table in GameView.lua and a C.TILE table in constants.lua — both updated to stay in sync. The comment in constants.lua also had a stale file reference (WorldSandboxController) which was corrected to GameBridgeService.

---

## Phase 2 — Generalise Trunk Infrastructure

**Goal:** Replace the road-specific `game.hw_city_edges` with a mode-keyed `game.trunks[mode]` map. Road highways write to `game.trunks["road"]`. No other modes exist yet — this is a pure rename/restructure with identical behaviour.

### Tasks

| # | File | Change |
|---|------|--------|
| 2.1 | `services/InfrastructureService.lua` | Rename all writes from `game.hw_city_edges` to `game.trunks["road"]`. Rename `hw_attachment_nodes` to `game.trunk_hubs["road"]`. Rename `hw_city_sc_bounds` to `game.trunk_sc_bounds["road"]`. |
| 2.2 | `services/GameBridgeService.lua` | Update all reads/writes to use `game.trunks["road"]`, `game.trunk_hubs["road"]`, `game.trunk_sc_bounds["road"]`. |
| 2.3 | `services/PathfindingService.lua` | Replace all `game.hw_city_edges` references with `game.trunks[vehicle.transport_mode]`. Replace `game.hw_attachment_nodes` with `game.trunk_hubs[vehicle.transport_mode]`. Replace `game.hw_city_sc_bounds` with `game.trunk_sc_bounds[vehicle.transport_mode]`. |
| 2.4 | `services/PathCacheService.lua` | Add `mode` as the outermost key: `cache[mode][ux1][uy1][ux2][uy2]`. Update all get/put call sites to pass the vehicle's transport mode. |
| 2.5 | Grep sweep | Confirm zero remaining references to `hw_city_edges`, `hw_attachment_nodes`, `hw_city_sc_bounds` anywhere in the codebase. |

### Expected Outcome

Game behaviour is identical. Highways still work. The data structure is now mode-keyed and ready for water trunks to be slotted in without any further structural changes.

### Testing

- Run a full cross-city truck delivery. Verify it completes normally.
- Verify highway rendering (if any debug overlay exists) is unchanged.
- Run the grep sweep from task 2.5 and confirm zero hits.

### AI Notes

This phase is a pure rename. If anything breaks it is a wiring error, not a logic error. Do not change any pathfinding logic during this phase.

---

**Status:** Not started
**Line count change:** —
**Deviation from plan:** —

---

## Phase 3 — Direction-Aware Pathfinder

**Goal:** Add an optional `turn_costs` parameter to `Pathfinder.findPath`. When nil, behaviour is exactly identical to today. When provided, node state expands to `(x, y, dir)` and turning adds cost. This will be used by the shipline generator in Phase 4.

### Tasks

| # | File | Change |
|---|------|--------|
| 3.1 | `lib/pathfinder.lua` | Add optional `turn_costs` param to `findPath(grid, startNode, endNode, costs, map, turn_costs)`. When provided: node key includes direction (4 directions = 4× state space). Entering a neighbor from a different direction than arrived adds `turn_costs.turn_90` (perpendicular) or `turn_costs.turn_180` (reversal) to the move cost. When nil: existing code path runs unchanged. |
| 3.2 | `lib/pathfinder.lua` | Update `nodeKey` to encode direction when turn mode is active: `x + y*65536 + dir*65536*65536`. |
| 3.3 | All existing `Pathfinder.findPath` call sites | Confirm none pass a 6th argument — no changes needed, nil is the default. |

### Expected Outcome

All existing pathfinding unchanged. A new caller can pass `{turn_90 = 8, turn_180 = 999}` and receive a path that avoids sharp turns. Higher `turn_90` = gentler curves in the result.

### Testing

- Run a full cross-city delivery. Verify no regression.
- Write a minimal test: call `findPath` on a small water grid with `turn_costs` and verify the returned path has no 180° reversals and prefers gradual curves over shortcuts with sharp turns.

### AI Notes

Direction is encoded as an integer: 0=North, 1=East, 2=South, 3=West. The start node has no incoming direction — all four initial directions are seeded with cost 0. A 180° penalty must be high enough to make reversals essentially impossible for ships (999 is a reasonable default — higher than any realistic path length).

---

**Status:** Not started
**Line count change:** —
**Deviation from plan:** —

---

## Phase 4 — Building Registry & Dock Placement

**Goal:** A data-driven building registry loaded from `data/buildings/`. Placement validation reads rules by name from a small validator registry. When a dock is placed and a second dock already exists, shipline generation triggers automatically and writes to `game.trunks["water"]`. This is the first appearance of ships in the data — no ship vehicle yet, just the infrastructure.

### Tasks

| # | File | Change |
|---|------|--------|
| 4.1 | `data/buildings/dock.json` | Create: `id`, `display_name`, `serves` (`"water"`), `is_transfer_hub` (`true`), `placement_rule` (`"adjacent_to_water"`). |
| 4.2 | `data/constants.lua` | Auto-load all files in `data/buildings/` into `C.BUILDINGS[id]` on startup, same pattern as `C.VEHICLES`. |
| 4.3 | `services/BuildingService.lua` | **New file.** Placement validator registry: `validators["adjacent_to_water"] = function(tile, map) ... end`. `BuildingService.canPlace(building_cfg, tile, map)` runs the rule. `BuildingService.place(building_cfg, tile, city, game)` stamps the building, registers it in `game.buildings[city]`, and triggers trunk generation if `is_transfer_hub` and a second hub of the same `serves` type exists in any other city. |
| 4.4 | `services/BuildingService.lua` | Shipline generator: A* across the unified map using water subtype costs from the ship vehicle config (loaded from `C.VEHICLES.SHIP.pathfinding_costs`), with `turn_costs = {turn_90=8, turn_180=999}`. Result cached in `game.trunks["water"][city_a][city_b]`. Dock tile coords become entries in `game.trunk_hubs["water"][city]`. |
| 4.5 | UI / build tool | Wire dock placement into the existing build UI. Player can select dock from a building palette and click a water-adjacent city tile. `BuildingService.canPlace` gates the click. |

### Expected Outcome

Player can place docks in coastal cities. When two docks exist, a shipline is silently computed and cached. No ship vehicle yet — the trunk exists but nothing rides it. Debug overlay (if available) can confirm `game.trunks["water"]` is populated.

### Testing

- Place a dock in a coastal city. Verify placement is rejected on non-water-adjacent tiles.
- Place a second dock in a different coastal city. Print `game.trunks["water"]` and verify a path exists between them.
- Place a third dock; verify shiplines are computed from it to all existing docks.
- Verify road vehicle pathfinding is completely unaffected.

### AI Notes

`BuildingService` is the only new file. It is a pure service — no rendering, no game state mutations beyond `game.trunks` and `game.buildings`. The build UI wiring is minimal: dock is just another item in the palette that calls `BuildingService.place` on click. Rendering of the dock building itself (a tile icon or marker) is out of scope for this phase unless trivially simple.

---

**Status:** Not started
**Line count change:** —
**Deviation from plan:** —

---

## Phase 5 — Ship Vehicle & Trunk Traversal

**Goal:** `ship.json` is added. Ships can be dispatched, pathfind to dock A via road (as pedestrians to the port), ride the shipline trunk to dock B, and await pickup. The vehicle state machine reuses the existing trunk traversal states.

### Tasks

| # | File | Change |
|---|------|--------|
| 5.1 | `data/vehicles/ship.json` | Create: `transport_mode: "water"`, `pathfinding_costs` for the three water subtypes (coastal=2, deep=5, open_ocean=10) and all land types at 9999, `anchor_to_road: false`, speed, capacity, icon. |
| 5.2 | `services/PathfindingService.lua` | HPA* trunk lookup now uses `game.trunks[vehicle.transport_mode]`. For `"water"` mode, attachment nodes are dock tile positions from `game.trunk_hubs["water"]`. Tier 1 / Tier 4 local legs do not apply to ships — ships board/exit trunks directly at dock tiles. |
| 5.3 | `models/vehicles/vehicle_states.lua` | Confirm `ToTrunk` / `OnTrunk` / `ExitingTrunk` states (or their current highway equivalents) work for water mode. The trunk path from Phase 4 is a coordinate sequence — `OnTrunk` just walks it. No changes expected if state names are already generic; rename if they are still highway-specific. |
| 5.4 | `services/TripEligibilityService.lua` | Verify `transport_mode` matching already handles `"water"` — no changes expected. Confirm by inspection. |
| 5.5 | Depot spawning | Ships spawn at dock tile rather than a road depot. `Depot.lua` or spawn logic needs to accept a dock as a valid spawn point for water-mode vehicles. |

### Expected Outcome

A ship vehicle can be dispatched. It pathfinds from its dock spawn, rides the shipline to the destination dock, and completes the trunk leg. A truck can then be dispatched to complete the final road leg. The full 3-leg trip works end-to-end using existing dispatch rules.

### Testing

- Dispatch a ship between two docked cities. Verify it follows the shipline path (no erratic movement, smooth curves from Phase 3 turn costs).
- Verify the ship does not attempt to cross land.
- Set up a 3-leg dispatch rule: truck to dock A → ship dock A to dock B → truck from dock B to destination. Deliver a package end-to-end and verify payout.
- Verify road trucks are completely unaffected.

### AI Notes

The "local leg" for ships is zero — ships board the trunk directly at the dock. If PathfindingService expects a Tier 1 local path before the trunk, add a mode check: if `transport_mode == "water"` (or more generally, if the start node IS a trunk hub), skip Tier 1 and enter the trunk directly. Keep this check data-driven if possible: `building_cfg.boards_trunk_directly = true`.

---

**Status:** Not started
**Line count change:** —
**Deviation from plan:** —

---

## End State

| Capability | Delivered |
|------------|-----------|
| Water tile subtypes in world gen | Phase 1 |
| Mode-keyed `game.trunks[mode]` | Phase 2 |
| Direction-aware pathfinder for gentle shipline curves | Phase 3 |
| Dock placement with auto-shipline generation | Phase 4 |
| Ship vehicle riding shiplines, 3-leg dispatch | Phase 5 |

**Adding trains after this:** create `train.json` + `station.json` (placement rule: `on_rail`). Zero core changes.
