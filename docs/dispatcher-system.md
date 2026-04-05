# Dispatcher System

## Philosophy

The dispatcher is the heart of the game. It is the thing the player is actually building and tuning. Everything else — the world, the vehicles, the infrastructure — exists to give the dispatcher something to operate on.

The game is an idle at its core. The dispatcher runs continuously. The player does not manually orchestrate individual trips beyond the very earliest stages of the game, and even that is brief. The moment autodispatch unlocks, manual trip assignment is essentially gone. From that point forward the player's job is making the dispatcher smarter, not making individual decisions.

The gameplay loop is: the world runs, the player dips in, finds an inefficiency, writes a rule, watches the numbers change. The satisfaction is in discovery as much as the fix. An unlock reveals something that was already true about the network. The player investigates, forms a hypothesis, changes a rule, and watches the stats to confirm or disprove it. There is no single correct answer — two players on the same map can run completely different rule configurations and both be profitable.

The world runs whether you're watching or not. Missing a window costs a bit of money. A poorly configured rule wastes fuel for a few minutes. These are consequences, not crises. The game does not pause.

---

## The Early Game

The game starts with the player dispatching manually. A trip comes in, they click a bike, they click the trip. This is a tutorial by another name — the player learns what the dispatcher needs to know by doing it themselves first.

The first autodispatch unlock removes almost all of this immediately. The manual phase is short by design. What replaces it is watching the dispatcher do obviously dumb things and wanting to fix them. Trucks leaving at 2/10 capacity. A rush trip sitting idle while a batch threshold is never met. Bikes going to the wrong part of the city. These are visible inefficiencies that prompt the player to open the dispatcher and write their first rule.

The progression is about the quality of dispatcher decisions, not about removing manual work.

---

## Rule System

The dispatcher is a rule evaluation engine. When deciding how to handle a trip it:

1. Finds all eligible vehicles via capability matching
2. Evaluates the player's active ruleset in priority order
3. Rules filter candidates, reorder them, or delay dispatch entirely
4. If a clear candidate remains: assign
5. If rules say wait: trip stays pending, revisited next cycle

Rules are data objects — serializable, authored in the UI, evaluated at runtime. The engine has no opinions. It evaluates whatever ruleset the player has configured.

### Rule Types

**Filter rules** — eliminate vehicles from consideration
- Don't dispatch this vehicle until it reaches X% capacity
- Don't send any vehicle on trips shorter than X tiles
- Only use planes for critical service level trips

**Ranking rules** — reorder the candidate set
- Prefer the nearest vehicle to the pickup
- Prefer the vehicle with the most remaining capacity
- Prefer cheaper vehicles for small cargo sizes

**Threshold / batch rules** — control when a vehicle departs
- Don't dispatch truck until cargo queue reaches 60% capacity
- Override and depart if any trip in the queue has under 2 hours on its window
- Batch all trips to the same destination district before departing

**Priority rules** — suspend normal rules for urgent situations
- Critical service level trips bypass all threshold rules
- If a trip has missed its window, dispatch immediately regardless of capacity

**Infrastructure / routing rules** — affect pathfinding, not just vehicle selection
- Ban this road segment entirely
- For trips over 500 distance, prefer rail over highway
- Route all intercity cargo through hub depot Y

**Scheduling rules** — time-based triggers
- At 15:00 daily, begin routing all bikes back to depot
- At 16:00, dispatch all loaded trucks regardless of capacity
- Only operate this train line during peak hours

### Rule Data Model

A rule is a serializable object with conditions and an action:

```lua
{
  id         = "r_001",
  enabled    = true,
  priority   = 1,
  scope      = "depot:downtown_1",   -- global, depot, vehicle, route, or vehicle type
  label      = "Batch trucks to 60%",

  conditions = {
    { field = "vehicle.type",         op = "eq",  value = "truck" },
    { field = "vehicle.capacity_pct", op = "lt",  value = 60 },
  },

  action = {
    type            = "wait",
    until_field     = "vehicle.capacity_pct",
    until_op        = "gte",
    until_value     = 60,
    max_wait_seconds = 120,
  }
}
```

Rules have a scope — global, per-depot, per-vehicle-type, per-route. A rule scoped to a depot only fires for trips originating there. This is how the player configures different behaviour for different parts of their network without rules conflicting.

Conditions and actions are registered by game systems, not hardcoded in the engine. When the rail system exists, it registers `"route_via_rail"` as an available action. It appears in the rule editor automatically. If rail doesn't exist yet, the action isn't available. The engine vocabulary grows as the game world grows.

---

## Predictive Dispatch

The dispatcher is not purely reactive. At higher tiers it forecasts ahead.

A vehicle doesn't need to sit at the depot waiting for a batch threshold. It can be out working, and the dispatcher estimates "I'll have 60 capacity ready in approximately 3 minutes, and given current routes, vehicle 7 will be finishing its last drop in that area at that time — pre-route it toward the depot now so it arrives just in time to load."

This requires the dispatcher to model the network over time, not just its current state. ETAs already exist on vehicles — that's the foundation. The dispatcher needs to reason across the whole fleet simultaneously: where will everyone be in 5 minutes, what cargo will have accumulated, what's the optimal assembly.

This is a high-tier unlock. Early dispatchers are purely reactive. Predictive dispatch is a late-game capability that transforms how the network operates.

---

## Scheduling

At a certain tier, the player can define fixed schedules that the whole network coordinates around.

- 6 bikes collect inner-city trips from 08:00 to 15:00
- At 15:00 they all return to the depot
- Trucks arrive at 16:00, load everything accumulated, depart to other cities or trunk infrastructure
- Bikes are back out by 17:00 for the evening run

A schedule is a set of rules with time conditions. The underlying rule engine doesn't change — time is just another condition field. But the player experience shifts from "configure responses to events" to "design a daily rhythm for the whole network."

Schedules interact with predictive dispatch — the dispatcher knows the 16:00 departure is coming and starts pre-positioning vehicles accordingly at 15:30.

---

## Service Levels and Delivery Windows

Trips have a service level set at order time. This is not something a trip escalates into — it is a property of the trip from birth. A critical trip is a different product the client ordered, paying a premium for it.

Delivery windows replace the current speed bonus decay model:

- A trip has a window (hours or days depending on distance and service level)
- Deliver within the window: full payout plus bonus
- Miss the window: base payout only, or for rush trips, base payout begins decaying
- Hard deadline missed entirely: potential penalty

Example windows:
- Inner-city regular: 4-8 hours
- Inner-city rush: 1 hour
- Intercity regular: 2-3 days
- Intercity rush: 12 hours
- Intercontinental regular: 1-2 weeks
- Intercontinental rush: 3 days

The dispatcher is fundamentally managing these windows across the whole network. The most important rule the player writes early is probably something like "if a trip has under 2 hours on its window, bypass capacity thresholds and dispatch immediately."

---

## Information as Progression

The player does not have perfect information from the start. Information unlocks are as meaningful as capability unlocks.

Early game: you know how many vehicles are assigned to a depot and roughly what they're doing. That's it. An attentive player can still click through individual vehicles and notice patterns manually — they get rewarded for that attention before the unlock exists.

Later unlocks surface what was always true:

| Unlock | What becomes visible |
|--------|---------------------|
| Basic analytics | On-time rate per depot |
| Financial breakdown | Profit/loss broken down by fuel, missed windows, capacity waste |
| Rule analytics | How often each rule fires, estimated value of each rule |
| Fleet overview | Per-vehicle efficiency, idle time, average capacity utilization |
| Network flow | Cargo volume moving between depots and trunk infrastructure |
| Forecasting | Projected capacity, predicted bottlenecks |

Rule analytics are particularly important — a rule that never fires is dead weight or misconfigured. The dispatcher UI shows next to each rule how often it fired in the last hour and the estimated financial impact. Rules become legible objects with measurable outcomes, not black boxes.

The moment an analytics unlock hits, the player sees something they've been vaguely aware of for a while confirmed in numbers. "Wtf, these trains lose money — they're burning fuel waiting at the station because this city doesn't generate enough trips to fill them. Switch to trucks, 300% profit increase." That discovery is the active gameplay inside an idle game.

---

## Seeded Runs and Speedruns

Because the world is fully deterministic from a seed, there is a mathematically optimal ruleset for any given seed. Finding it is a legitimate challenge.

The speedrun target is a win condition — likely delivering a specific package to a specific far destination (another continent, eventually another planet). Everything the player builds is in service of that one delivery. The win condition is itself a logistics problem: trace the route, identify what infrastructure is missing, build toward it.

After the win, play continues. The win is the speedrun endpoint. Beyond it the player is optimizing the network for its own sake.

Seeded runs allow direct comparison between players. Two runners on the same seed with different dispatcher configurations produce measurably different outcomes. Since the ruleset is serializable JSON, sharing a configuration is sharing a file. Communities naturally form around optimal configurations for known seeds.

---

## What Exists Now

| Component | State |
|-----------|-------|
| `AutoDispatcher.lua` | Exists — greedy, timer-based, no rules. This becomes the Tier 0 behavior |
| `TripEligibilityService.lua` | Exists — type string match only. Needs capability refactor |
| Vehicle `trip_queue` | Exists — supports multiple assigned trips already |
| Vehicle state machine | Exists — needs a Staging state for batch dispatch |
| Trip objects | Exist — need service_level, delivery_window, age fields. Speed bonus decay model to be replaced |
| Rule data model | Does not exist |
| Rule evaluation engine | Does not exist |
| Staging / pre-positioning | Does not exist |
| Scheduling | Does not exist |
| Predictive dispatch | Does not exist |
| Analytics / stats | Does not exist |
| Path cost overrides (route banning) | Does not exist |
| Dispatcher UI | Does not exist |

---

## Implementation Order

1. Vehicle abstraction refactor — trip legs need capability requirements before the dispatcher can reason about them generically
2. Replace speed bonus decay with delivery windows and service levels on trips
3. Build rule data model and basic evaluation engine (filter + ranking rules)
4. Add Staging state to vehicle state machine for batch dispatch
5. Wire rule unlocks to the progression system
6. Add path cost override API for route banning and infrastructure preference
7. Build dispatcher UI — rule editor, scoping, enable/disable
8. Add per-depot and per-fleet analytics
9. Add scheduling (time-condition rules)
10. Add predictive dispatch as late-game capability
