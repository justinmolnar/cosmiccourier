# Vehicle Abstraction — Phased Action Plan

> Created: 2026-04-05
> Source documents: `docs/vehicle-abstraction-refactor.md`, `docs/dispatcher-system.md`
> Goal: A single JSON file per vehicle is the only thing that needs to change to add or modify a vehicle. No logic file has any knowledge of what vehicle types exist.

---

## Critical Rules

1. **No phase begins until the previous phase is complete and tested.**
2. **The game must behave identically before and after each phase.** Bikes and trucks work exactly as before throughout. Only the source of truth changes.
3. **Delete the old code.** No backward-compat shims, no commented-out originals.
4. **No new vehicle types until Phase 6 is complete.** The refactor is not done until the proof-of-concept vehicle works with zero logic changes.
5. **One phase, one commit.**

---

## Definition of Done

Drop a new file `data/vehicles/car.json`. Start the game. The car appears in the hire UI with correct stats, can be hired, is dispatched to eligible trips, renders correctly, and upgrades correctly. No other file was touched.

---

## Phase 1 — Vehicle JSON Definitions

**Goal:** Move all vehicle data out of `data/constants.lua` into individual JSON files. No behavior change — constants.lua still populates `game.C.VEHICLES`, just from loaded files instead of hardcoded tables.

### Tasks

| # | File | Change |
|---|------|--------|
| 1.1 | `data/vehicles/bike.json` | Create. Contains: id, display_name, icon, dot_color, base_speed, base_capacity, base_cost, cost_multiplier, max_range, transport_mode, pathfinding_costs, rendering (render_zoom_key, abstract_zoom_key, needs_speed_scale), upgrades array |
| 1.2 | `data/vehicles/truck.json` | Create. Same schema. max_range: null (unlimited) |
| 1.3 | `data/constants.lua` | Replace the hardcoded VEHICLES block with a loader that reads all files in `data/vehicles/`, parses each JSON, and populates `game.C.VEHICLES[def.id:upper()]` with the result. The key format stays uppercase to match existing `vehicle.type_upper` lookups |
| 1.4 | `data/constants.lua` | Resolve `render_zoom_key` and `abstract_zoom_key` strings to actual constants at load time (e.g. `"BIKE_THRESHOLD"` → `game.C.ZOOM.BIKE_THRESHOLD`) so callsites read a number not a string |

### Schema Reference

```json
{
  "id": "bike",
  "display_name": "Bicycle",
  "icon": "🚲",
  "dot_color": [0.3, 0.88, 0.35],
  "base_speed": 80,
  "base_capacity": 1,
  "base_cost": 150,
  "cost_multiplier": 1.15,
  "max_range": 300,
  "transport_mode": "road",
  "pathfinding_costs": {
    "downtown_road": 5,
    "road": 10,
    "arterial": 20,
    "highway": 50,
    "water": 9999,
    "mountain": 9999
  },
  "rendering": {
    "render_zoom_key": "BIKE_THRESHOLD",
    "abstract_zoom_key": "BIKE_THRESHOLD",
    "needs_speed_scale": true
  },
  "upgrades": []
}
```

### Expected Outcome

`game.C.VEHICLES.BIKE` and `game.C.VEHICLES.TRUCK` contain identical data to what they did before. Everything else is untouched.

### Testing

- Print `game.C.VEHICLES.BIKE.base_speed` at startup — should be 80
- Print `game.C.VEHICLES.TRUCK.pathfinding_costs.highway` — should be 1
- Hire a bike, hire a truck — both work, correct costs shown
- No crashes, no behavioral changes

---

## Phase 2 — VehicleFactory + Vehicle Base Class

**Goal:** Delete `Bike.lua` and `Truck.lua`. VehicleFactory creates all vehicles generically from the loaded definition. Vehicle.lua has no type-specific branches.

### Tasks

| # | File | Change |
|---|------|--------|
| 2.1 | `models/VehicleFactory.lua` | Remove the VEHICLE_TYPES registry. Replace `createVehicle(type, ...)` with a generic loader: look up `game.C.VEHICLES[type:upper()]`, assert it exists, call `Vehicle:new()` with the definition. `isValidVehicleType()` checks `game.C.VEHICLES[type:upper()] ~= nil` |
| 2.2 | `models/vehicles/Vehicle.lua` | Remove the `if vt == "BIKE" / elseif vt == "TRUCK"` speed_modifier branch. Replace with `vcfg.base_speed` and initial `speed_modifier = 1.0` (upgrades apply on top). Remove any remaining type-specific branches |
| 2.3 | `models/vehicles/Vehicle.lua` | `shouldDrawAtCameraScale()` — replace `vcfg.downtown_only_sim` check with `cs >= vcfg.rendering.render_zoom_threshold` (resolved number from Phase 1.4) |
| 2.4 | `models/vehicles/Vehicle.lua` | `shouldUseAbstractedSimulation()` — replace `vcfg.downtown_only_sim` check with `cs < vcfg.rendering.abstract_zoom_threshold` |
| 2.5 | `models/vehicles/vehicle_states.lua` | `moveAlongPath()` — replace `vcfg.needs_downtown_speed_scale` with `vcfg.rendering.needs_speed_scale` |
| 2.6 | `models/vehicles/Bike.lua` | Delete |
| 2.7 | `models/vehicles/Truck.lua` | Delete |

### Expected Outcome

VehicleFactory creates bikes and trucks from JSON definitions. No subclass files. Vehicle.lua has no mention of "bike" or "truck". Behavior is identical.

### Testing

- Hire bikes and trucks — both spawn correctly
- Bikes respect zoom abstraction threshold, trucks render at all scales
- Speed and movement identical to before
- No crashes on vehicle creation

---

## Phase 3 — Trip Leg Requirements

**Goal:** Trip legs describe what they need, not which vehicle type should fulfill them. The string "bike" and "truck" are removed from all trip objects.

### Tasks

| # | File | Change |
|---|------|--------|
| 3.1 | `models/Trip.lua` | Add fields to leg: `cargo_size` (number), `distance` (tiles, estimated at creation), `transport_mode` (string, default "road"), `service_level` (string, default "standard"). Remove `vehicleType` field |
| 3.2 | `services/TripGenerator.lua` | Remove all hardcoded "bike" and "truck" assignments on legs. Replace with requirement fields based on trip geometry: downtown-only short trips get small cargo_size; inter-city trips get larger cargo_size; distance estimated from origin/dest subcell coords. No vehicle type names anywhere |
| 3.3 | `services/TripEligibilityService.lua` | Replace type-string match with three capability checks: `vehicle:getEffectiveCapacity(game) >= leg.cargo_size`, `vcfg.max_range == nil or leg.distance <= vcfg.max_range`, `vcfg.transport_mode == leg.transport_mode` |
| 3.4 | `models/AutoDispatcher.lua` | Remove the `by_type` vehicle partitioning. Dispatch iterates all vehicles and calls the updated `TripEligibilityService.canAssign()`. The type-indexed optimization is no longer needed since eligibility is now computed not looked up |

### Cargo Size Reference (starting values)

| Trip type | cargo_size | Rationale |
|-----------|-----------|-----------|
| Downtown short | 1 | Bike-sized, small parcel |
| Downtown standard | 2–3 | Small but needs more capacity |
| Inner-city | 4–6 | Car or truck territory |
| Inter-city | 7–10 | Truck minimum |

These numbers are tunable. The point is the size emerges from trip geometry, not from a hardcoded vehicle name.

### Expected Outcome

Trips carry no vehicle type names. The dispatcher assigns vehicles based on capability matching. Bikes still get downtown trips because their capacity and range match. Trucks still get inter-city trips because only they have sufficient range and cargo_size capacity. Behavior is identical, mechanism is generic.

### Testing

- Generate 20+ trips, inspect their legs — no vehicleType field, cargo_size and distance present
- Bikes are assigned to small downtown trips, trucks to inter-city trips
- AutoDispatcher correctly skips vehicles that don't meet requirements
- No crashes, trip completion rates similar to before

---

## Phase 4 — Upgrade System

**Goal:** Vehicle upgrades are defined in the vehicle JSON. UpgradeSystem reads them generically. No hardcoded stat names like `bike_speed` or `truck_speed`.

### Tasks

| # | File | Change |
|---|------|--------|
| 4.1 | `data/vehicles/bike.json` | Populate the upgrades array with the bike's current upgrade tree (speed levels, capacity levels) using a generic schema |
| 4.2 | `data/vehicles/truck.json` | Same for truck |
| 4.3 | `models/UpgradeSystem.lua` | Remove `if stat_name == "bike_speed" / elseif stat_name == "truck_speed"` branches. Replace with a loop over `game.C.VEHICLES` — for each definition, apply the upgrade effect to all vehicles of that type using the stat name pattern `{vehicle_id}_{stat}`. Or read the effect directly from the upgrade definition |
| 4.4 | `services/VehicleUpgradeService.lua` | Verify it already works generically (it takes a vehicle_type string and a value — no changes needed if the caller is fixed) |
| 4.5 | `models/vehicles/Vehicle.lua` | `getEffectiveCapacity(game)` reads base_capacity from vcfg and applies any capacity upgrades from game state generically |
| 4.6 | `data/upgrades.json` | Remove vehicle upgrade entries. This file is now only for non-vehicle upgrades: dispatcher unlocks, depot expansions, client improvements, analytics unlocks, etc. |

### Upgrade Schema (in vehicle JSON)

```json
"upgrades": [
  {
    "id": "bike_speed_1",
    "display_name": "Lightweight Frame",
    "description": "Increases speed by 20%.",
    "cost": 300,
    "stat": "speed_multiplier",
    "value": 1.2,
    "prerequisite": null
  },
  {
    "id": "bike_bag_1",
    "display_name": "Cargo Bag",
    "description": "Carry one additional parcel.",
    "cost": 200,
    "stat": "capacity",
    "value": 2,
    "prerequisite": null
  }
]
```

### Expected Outcome

Upgrading bike speed and truck capacity works identically. UpgradeSystem has no vehicle-specific logic. Adding a vehicle with upgrades in its JSON makes those upgrades available automatically.

### Testing

- Purchase a bike speed upgrade — bike moves faster
- Purchase a truck capacity upgrade — truck accepts more trips
- UpgradeSystem logs no errors on unknown stat names
- upgrades.json no longer contains vehicle entries

---

## Phase 5 — UI

**Goal:** All vehicle UI is generated from loaded definitions. No hardcoded hire buttons, no hardcoded vehicle type names in any view or controller.

### Tasks

| # | File | Change |
|---|------|--------|
| 5.1 | `views/UIManager.lua` | Hire button layout: replace hardcoded `hire_bike` / `hire_truck` buttons with a loop over `game.C.VEHICLES`. Generate one button entry per definition, keyed by vehicle id |
| 5.2 | `views/components/VehiclesPanelView.lua` | Replace hardcoded "Hire New Bike" / "Hire New Truck" sections with a loop over `game.C.VEHICLES`. Each definition renders its own hire button using `vcfg.display_name`, `vcfg.icon`, and current cost from game state |
| 5.3 | `controllers/UIController.lua` | Replace type-specific button checks with a generic handler: iterate `game.C.VEHICLES`, check if the click hit that vehicle's hire button, publish `"ui_buy_vehicle_clicked"` with the vehicle id |
| 5.4 | `services/EventService.lua` | Vehicle purchase cost scaling: replace `if vehicleType == "bike" / elseif vehicleType == "truck"` with `vcfg.cost_multiplier` from the definition. `state.costs[vehicleType]` is initialized from `vcfg.base_cost` at world load for any definition that exists |
| 5.5 | `views/components/TripsPanelView.lua` | Trip leg icon: replace `(leg.vehicleType == "bike") and "🚲" or "🚚"` ternary. Trips no longer have vehicleType — display transport_mode icon or service_level badge instead |
| 5.6 | `views/GameView.lua` | Dot color in debug_dot_vehicles mode: replace type checks with `vcfg.dot_color`. Selected vehicle highlight stays as-is (not type-dependent) |

### Expected Outcome

All vehicle UI renders identically for bikes and trucks. No view or controller file contains the strings "bike" or "truck" in any logic branch.

### Testing

- Both hire buttons appear with correct names, icons, and costs
- Hiring works for both types
- Cost scales correctly on repeated hire
- TripsPanelView shows correct icons for trip legs
- Dot mode renders bikes green and trucks orange as before

---

## Phase 6 — Proof of Concept: Add a Car

**Goal:** Prove the system works. Add a car with zero changes to any logic file.

### Tasks

| # | File | Change |
|---|------|--------|
| 6.1 | `data/vehicles/car.json` | Create. Faster than a truck, lower capacity (3), highway-capable, no range limit, road transport mode, entity-threshold zoom |
| 6.2 | — | Nothing else |

```json
{
  "id": "car",
  "display_name": "Car",
  "icon": "🚗",
  "dot_color": [0.4, 0.6, 1.0],
  "base_speed": 120,
  "base_capacity": 3,
  "base_cost": 600,
  "cost_multiplier": 1.2,
  "max_range": null,
  "transport_mode": "road",
  "pathfinding_costs": {
    "downtown_road": 10,
    "road": 5,
    "arterial": 2,
    "highway": 1,
    "water": 9999,
    "mountain": 9999
  },
  "rendering": {
    "render_zoom_key": "ENTITY_THRESHOLD",
    "abstract_zoom_key": "ENTITY_THRESHOLD",
    "needs_speed_scale": false
  },
  "upgrades": []
}
```

### Expected Outcome

The car appears in the hire UI. It can be hired. The dispatcher assigns it to trips with cargo_size <= 3. It renders as a blue dot. It pathfinds preferring highways. Nothing else changed.

### Testing

- Car hire button appears without touching any logic file
- Hire a car — it spawns at the depot
- Dispatch a size-2 trip — car is eligible and gets assigned
- Dispatch a size-8 trip — car is not eligible, truck handles it
- Car renders correctly in dot mode and emoji mode

---

## Files Deleted by End of Phase 5

- `models/vehicles/Bike.lua`
- `models/vehicles/Truck.lua`
- Vehicle entries in `data/upgrades.json`
- VEHICLES block in `data/constants.lua`

## Files With "bike" or "truck" Removed From Logic

- `models/VehicleFactory.lua`
- `models/vehicles/Vehicle.lua`
- `models/vehicles/vehicle_states.lua`
- `services/TripEligibilityService.lua`
- `services/TripGenerator.lua`
- `models/AutoDispatcher.lua`
- `models/UpgradeSystem.lua`
- `services/EventService.lua`
- `views/UIManager.lua`
- `views/components/VehiclesPanelView.lua`
- `views/components/TripsPanelView.lua`
- `controllers/UIController.lua`
- `views/GameView.lua`

## Files Untouched

- `lib/pathfinder.lua`
- `services/PathScheduler.lua`
- `services/PathCacheService.lua`
- `services/PathfindingService.lua`
- `models/vehicles/vehicle_states.lua` (beyond the needs_speed_scale rename in Phase 2)
- `models/EntityManager.lua`
- `controllers/GameController.lua`
- All map and world generation files
