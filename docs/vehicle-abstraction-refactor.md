# Vehicle Abstraction Refactor

## Goal

The codebase currently has no concept of a generic vehicle — it knows about bikes and trucks specifically, in dozens of places. Adding any new vehicle type requires patching logic files throughout the codebase. This refactor eliminates that entirely.

**The target state:** the game engine has zero knowledge of what vehicle types exist. It only knows that vehicles have properties, trips have requirements, and the dispatcher matches them. A new vehicle is a new JSON file and nothing else.

---

## The Core Problem

Two failure modes currently:

**Type-name coupling** — code checks `v.type == "bike"` or `leg.vehicleType == "truck"` to make decisions. Every new vehicle requires finding and patching all of these.

**Implicit capability flags** — `can_long_distance`, `downtown_only_sim` encode what vehicles can do but are named after current concepts. A car, boat, or plane immediately breaks the mental model of these flags.

---

## Vehicle Definition Schema

Vehicles live in `data/vehicles/` — one JSON file per type. The engine loads all files in that directory at startup. Nothing else in the codebase knows what files exist.

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

  "upgrades": [
    {
      "id": "bike_bag",
      "display_name": "Cargo Bag",
      "description": "Increases carrying capacity.",
      "levels": [
        { "cost": 200, "capacity": 2 },
        { "cost": 500, "capacity": 3 }
      ]
    },
    {
      "id": "bike_speed",
      "display_name": "Lightweight Frame",
      "description": "Increases base speed.",
      "levels": [
        { "cost": 300, "speed_multiplier": 1.2 },
        { "cost": 700, "speed_multiplier": 1.5 }
      ]
    }
  ]
}
```

```json
{
  "id": "truck",
  "display_name": "Truck",
  "icon": "🚚",
  "dot_color": [1.0, 0.55, 0.1],

  "base_speed": 60,
  "base_capacity": 10,
  "base_cost": 1200,
  "cost_multiplier": 1.0,

  "max_range": null,
  "transport_mode": "road",

  "pathfinding_costs": {
    "downtown_road": 15,
    "road": 10,
    "arterial": 5,
    "highway": 1,
    "water": 9999,
    "mountain": 9999
  },

  "rendering": {
    "render_zoom_key": "ENTITY_THRESHOLD",
    "abstract_zoom_key": "ENTITY_THRESHOLD",
    "needs_speed_scale": false
  },

  "upgrades": [...]
}
```

`max_range: null` means unlimited. `max_range: 300` means the vehicle cannot be dispatched to a leg whose total distance exceeds 300 tiles from its depot.

When the fuel system is added, `max_range` becomes derived at runtime from `fuel_capacity / fuel_per_tile` rather than being a static value. The eligibility check doesn't change.

---

## Trip Leg Schema

Legs no longer name a vehicle type. They describe what the journey requires. The dispatcher finds vehicles that satisfy those requirements.

```lua
leg = {
  origin_subcell  = { x, y },   -- unified grid coords
  dest_subcell    = { x, y },
  origin_city     = "city_1",
  dest_city       = "city_2",
  inter_city      = true,        -- derived: origin_city ~= dest_city
  distance        = 840,         -- estimated tile distance, set at leg creation
  cargo_size      = 3,           -- size of this package
  transport_mode  = "road",      -- what infrastructure this leg uses
  trunk_path      = { ... },     -- pre-computed city-to-city trunk nodes, nil if same city
}
```

`cargo_size` replaces all current capacity logic. A package is a size. A vehicle has a capacity. A vehicle can carry the package if `capacity >= cargo_size`.

`distance` is computed when the leg is created (approximate trunk-route distance). This allows the dispatcher to filter by range without pathfinding every candidate vehicle.

---

## Eligibility Matching

`TripEligibilityService` becomes three comparisons:

```lua
function canAssign(vehicle, leg, game)
  local vcfg = game.C.VEHICLES[vehicle.type]

  -- 1. Can it carry this package?
  if vehicle:getEffectiveCapacity(game) < leg.cargo_size then
    return false
  end

  -- 2. Is the leg within this vehicle's operational range?
  if vcfg.max_range ~= nil and leg.distance > vcfg.max_range then
    return false
  end

  -- 3. Does the transport mode match?
  if vcfg.transport_mode ~= leg.transport_mode then
    return false
  end

  return vehicle:isAvailable(game)
end
```

No type names. No flags. A bike naturally can't do an inter-city leg because the inter-city leg's distance exceeds the bike's max_range. A bike naturally can't carry a size-10 package because its capacity is 1. No special cases needed.

---

## Trip Generation

`TripGenerator` knows about geography, not about vehicles. It creates legs by examining origin and destination:

- Are they in the same city? Set `inter_city = false`, estimate distance within city.
- Different cities? Set `inter_city = true`, estimate distance via trunk path, store trunk nodes.
- Compute `cargo_size` based on whatever game logic determines package weight.
- Set `transport_mode = "road"` (until other modes exist).

TripGenerator never writes a vehicle type onto a leg. The dispatcher figures out what can fulfill it.

---

## Operational Range and Zone Behavior

There are no hardcoded zones in vehicle definitions. Zone-like behavior emerges from the combination of depot location and max_range.

A bike with `max_range: 300` and a downtown depot effectively stays downtown — 300 tiles doesn't reach the city edge. If you later place a bike depot in a suburban district, bikes work that district instead. The constraint is spatial, not named.

Larger vehicles with `max_range: null` can be dispatched anywhere. A regional vehicle might have `max_range: 5000` — enough for same-region trips but not cross-continent.

---

## Trains (Special Case)

Trains are not dispatch vehicles in the standard sense. A train doesn't get assigned to a trip — a trip gets routed through a train. The train is closer to infrastructure (like a highway) with a schedule than a vehicle you hire.

Train legs are a different leg type generated when the routing system knows two rail stations are connected. The train fulfills the leg as a scheduled service, not a dispatched unit. This should be designed separately and not inherit the road vehicle dispatch model.

---

## What Gets Deleted

- `models/vehicles/Bike.lua` — no subclasses needed
- `models/vehicles/Truck.lua` — no subclasses needed
- `data/constants.lua` VEHICLES block — replaced by loaded JSON definitions
- `can_long_distance`, `downtown_only_sim` flags — replaced by `max_range` and capacity
- Every `v.type == "bike"` / `v.type == "truck"` check in logic files
- Hardcoded hire buttons in `VehiclesPanelView`, `UIController`
- Hardcoded vehicle stat names (`bike_speed`, `truck_speed`) in UpgradeSystem
- `upgrades.json` vehicle sections — upgrades move into vehicle JSON files
- Hardcoded icon/color ternaries in `TripsPanelView`, `GameView`

`upgrades.json` is kept for non-vehicle upgrades: dispatcher improvements, client-related unlocks, depot expansions, etc.

---

## What Changes

| File | Change |
|------|--------|
| `data/vehicles/*.json` | Created — one per vehicle type |
| `data/constants.lua` | Load all vehicle JSONs at init into `game.C.VEHICLES` |
| `models/VehicleFactory.lua` | Generic loader; no VEHICLE_TYPES registry |
| `models/vehicles/Vehicle.lua` | All type-specific branches removed; reads from vcfg |
| `services/TripEligibilityService.lua` | Three-comparison match: capacity, range, mode |
| `services/TripGenerator.lua` | Assigns geometry/size requirements, no type names |
| `models/UpgradeSystem.lua` | Iterates vehicle definitions generically |
| `services/EventService.lua` | Cost scaling reads `vcfg.cost_multiplier` |
| `views/UIManager.lua` | Iterates `game.C.VEHICLES` for button layout |
| `views/components/VehiclesPanelView.lua` | Loop over definitions |
| `controllers/UIController.lua` | Generic hire handler |
| `views/components/TripsPanelView.lua` | `vcfg.icon` instead of ternary |
| `views/GameView.lua` | `vcfg.dot_color` instead of type checks |
| `models/vehicles/vehicle_states.lua` | Already generic — no changes |
| `models/AutoDispatcher.lua` | Already generic — no changes |
| `lib/pathfinder.lua` | No changes |
| `services/PathScheduler.lua` | No changes |

---

## Dispatcher Evolution

The current dispatcher is minimal — first available vehicle of matching type. Under this system, multiple vehicles may be eligible for a leg. The dispatcher can then rank by:

- Nearest to pickup
- Fastest (speed × remaining range)
- Least loaded
- Cheapest operating cost (future)

This ranking logic is entirely separate from eligibility and can be iterated on independently without touching vehicle definitions.

---

## Implementation Order

1. Define the vehicle JSON schema and write `bike.json`, `truck.json`
2. Update `VehicleFactory` to load generically from the directory
3. Update `Vehicle.lua` — remove all type branches, read from vcfg
4. Update `TripEligibilityService` — new three-comparison match
5. Update `TripGenerator` — assign requirements, not type names
6. Update `UpgradeSystem` — iterate vehicle definitions
7. Update UI — iterate definitions for buttons, icons, colors
8. Delete `Bike.lua`, `Truck.lua`, remove constants VEHICLES block
