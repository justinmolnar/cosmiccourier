# Cosmic Courier — MVP Refactor Plan

**Date:** 2026-04-13
**Goal:** Turn the current codebase into an actual game. Progression with meaning, dispatch rules that present real decisions, upgrades and fuel that matter, a starting state that feels considered rather than randomized. Scopes covered: Downtown → City → Region. Continent/World are out of scope. Boats remain in code but are not worked on.

Heavy UI and graphics work is required and is acknowledged as part of MVP. This document focuses on the systems-level refactor; polished UI surfaces are downstream of the changes here.

---

## Guiding Principles (Non-Negotiable)

These apply to every section below.

- **Five primitives frozen; everything else grows.** The 5 structural primitives (blocks) in `data/dispatch_blocks.lua` are frozen. They are turing-complete — any rule's logic can be composed from them. No new primitives.
  - **Hats are not primitives.** They are currently a bespoke layer on top. Adding new hats as cards require them (e.g., `when vehicle has traveled > X miles`) is expected and fine. Long-term they should probably be consolidated to use the primitives + enums, but that unification is **not MVP scope** — extend hats as needed now.
  - **Other dispatch data can grow freely**: new **actions** (`dispatch_actions.lua`), **properties** (`dispatch_properties.lua`), **sorters** (`dispatch_sorters.lua`), **collections** (`dispatch_collections.lua`), **prefabs** (`dispatch_prefabs.lua`), and **enum entries** (vehicle types, tags, etc.).
  - Rule of thumb: if a rule needs a new control-flow construct or new primitive behavior, reframe the rule. For anything else — new hat, new property, new sorter, new action verb, new enum value — add it.
- **License is a pure scope gate.** Buying a license raises `scope_tier` and does nothing else. It does not bundle packs, vehicles, or upgrades. It opens access to *optional* purchases that the player still chooses individually. Choose-your-own-adventure, not "here's everything."
- **Fuel is economics, not a tank.** Fuel is money-deducted-on-arrival. It exists so the player has to weigh load consolidation and vehicle right-sizing. No fuel levels, no refueling, no fuel stations. Ever.
- **"Dispatch" means the rule-card system specifically.** Not the broader trip/economy loop. If a feature runs in service code on trip events, that is the economy loop, not dispatch.
- **Tier 1 (Downtown) stays sparse.** Few or zero cards. Do not propose adding more.
- **Refactoring means deleting.** No legacy-fallback retention, no "just in case" dead code paths.

---

## 1. License Refactor

### Current state

Scope is raised by individual upgrades in the Expansion category of the upgrade tree (`data/upgrades.json`):

- `city_expansion` → `effect_type: set_flag`, `scope_tier = 2`
- `regional_network` → `scope_tier = 3`
- `continental_reach` → `scope_tier = 4` (out of scope for MVP)
- `global_operations` → `scope_tier = 5` (out of scope for MVP)

Player starts with `scope_tier = 1` (Downtown). Scope is the single source of truth for gating, read via `services/ScopeService.lua`. The scope-raising upgrades are just nodes in the Expansion tree UI — visually identical to "Cargo Trailer" or any other checkbox. That flatness is the problem: the single most significant progression decision in the game has no more weight than a 2% stat bump.

### Target state

Lift the scope-raise out of the upgrade tree entirely. Introduce a dedicated License UI surface. Mechanically unchanged — each license is still `set_flag scope_tier N` — but presented as a distinct phase-transition purchase.

MVP license set:
- **Downtown License** — held at game start. Not purchasable.
- **City License** — raises scope to 2. Gates the ~30+ minute early arc.
- **Region License** — raises scope to 3.

Continent/World licenses are not authored for MVP. Remove (or leave dormant and hidden) the `continental_reach` / `global_operations` upgrades.

### Work items

- Delete the scope-raising nodes from the Expansion upgrade tree in `data/upgrades.json`.
- Add a License-specific UI surface (dedicated screen or prominent HUD button). Behavior: show current license, show next-available license with its price, show a visual confirmation moment on purchase.
- Save/load support for the license state is already implicit (`scope_tier` is persisted in `SaveService` SAVE_SCHEMA). No schema change needed.
- Purge any UI references to the old Expansion-tree scope upgrades.

### Notes

- License cost needs to be meaningfully higher than incidental purchases — it is the single largest money sink in its phase. Actual values assigned in the tuning pass.
- Because license is a pure gate, **nothing downstream needs refactoring to accommodate it**. `required_scope` on individual purchases (cars, packs, etc.) already does the right thing.

---

## 2. Card Authoring — Populate Tier 2 and Tier 3 Packs

### Current state

- `data/rule_templates.lua` contains ~16 implemented templates.
- `docs/rule-pack-catalog.md` describes ~100 rule concepts across 21 sections — aspirational, not shipped.
- `data/rule_packs.lua` defines 7 pack queries (tier 1 starter, tier 2 assignment/routing, tier 3 hub/vehicle, tier 4 economy/queue).
- Tier 1 pack (`starter_pack`, `count=2`, `max_complexity=1`) currently matches 2 starter-tagged templates — trivially all of them. Adequate for MVP.
- Tier 2 packs match what exists tagged `assignment` / `routing`. Thin.
- Tier 3 packs (`hub`, `vehicle`) are even thinner.

### Target state

Enough authored templates at each tier that pack openings feel like real selection (some variety, some replayability), not "here are all 2 cards that exist." Specifically:

- **Tier 1 (Downtown):** stays sparse. Status quo. No authoring work.
- **Tier 2 (City):** author enough to make the `assignment_pack` and `routing_pack` queries produce meaningfully varied results across multiple openings. Target 8–12 templates total across the tier-2 tag pool.
- **Tier 3 (Region):** author enough for `hub_routing_pack` and `vehicle_pack`. Target 6–10 templates.

Pack queries in `rule_packs.lua` may need adjustment if the current two-pack-per-tier split (e.g., `assignment_pack` + `routing_pack` both at scope 2) fragments authoring. Unified tier packs are an option; keep the plumbing in `PackService` as-is either way.

### Work items

- Triage `docs/rule-pack-catalog.md` against the existing primitives. For each catalog entry classify it as: composable-from-existing-primitives (implementable), needs-new-data (implementable — add hats/actions/properties/sorters/collections/enums as needed), or needs-new-primitive (drop, per principle — should be rare since the 5 are turing-complete).
- For each implementable tier-2 and tier-3 entry, author it as a `build()` function in `data/rule_templates.lua` with appropriate `tags`, `complexity`, `rarity`. Add any required properties, sorters, actions, or enum values to their respective `dispatch_*.lua` files.
- Update `docs/rule-pack-catalog.md` to mark which entries are now shipped vs still aspirational vs dropped.
- Verify `PackService.openPack` random selection still produces good variety after authoring.

### Notes

- Card authoring is the largest chunk of MVP content work.
- The catalog's `(FUTURE)` tags on rail/plane rules can be permanently dropped — those systems aren't in MVP scope.

---

## 3. Fuel-Aware Dispatch Cards

### Current state

- `services/FuelService.lua` deducts `path_cost × vehicle.fuel_rate` from `state.money` on every trip arrival.
- Each vehicle has a `fuel_rate` field (bike 0.01, car 0.05, truck 0.10 per current data).
- No dispatch rule cards reason about fuel. Zero templates in `rule_templates.lua` reference fuel cost, payout-vs-cost ratios, or vehicle right-sizing.
- The player has no information channel telling them that trips have a cost side — fuel is silent.

### Target state

Dispatch cards that surface the fuel/payout trade-off as a gameplay puzzle. The player can author rules that skip unprofitable trips, prefer fuel-efficient vehicles, or defer assignment to consolidate loads.

Representative cards (all composable from existing blocks):

- **Skip unprofitable trip** — if projected fuel cost > payout × threshold, skip.
- **Prefer fuel-efficient assignment** — sort candidate vehicles by `fuel_rate` ascending, not just by distance.
- **Wait for batch** — if vehicle capacity ≥ N, defer assignment until at least M pending packages share the destination region.
- **Net-profit filter** — only assign if `payout - (path_cost × fuel_rate) ≥ minimum_margin`.
- **Right-size by capacity** — choose smallest vehicle whose capacity covers the package count, not the fastest.

### Work items

- Identify what each fuel-aware card needs from the dispatch data layer. Expected additions:
  - **Properties** (`dispatch_properties.lua`): `vehicle.fuel_rate`, `trip.projected_fuel_cost`, `trip.net_profit` (payout − projected fuel cost), etc.
  - **Sorters** (`dispatch_sorters.lua`): `by_fuel_rate_asc`, `by_net_profit_desc`, etc.
  - **Actions** (`dispatch_actions.lua`): if any new verb is cleaner than composing from existing ones — otherwise reuse.
  - **Hats** if a new trigger condition is needed (e.g., `when fleet fuel spend > threshold`).
  - No new primitives.
- Author the cards into `data/rule_templates.lua` with appropriate tier tags.
- Ensure the new properties are computable at rule-evaluation time (projected fuel cost for an assignment candidate requires a path-cost estimate against a candidate vehicle; wire that in wherever candidates are evaluated).

### Notes

- Fuel cards live primarily at tier 2 (City) and tier 3 (Region). At tier 1 fuel matters little because only bikes operate and bike fuel_rate is trivial.
- Per the guiding principle, do not propose cards referencing "fuel remaining," "refuel," or "fuel stations."

---

## 4. Upgrades Review

### Current state

- `data/upgrades.json` contains 60+ upgrades across Vehicles, Clients, Operations, Expansion.
- Several upgrades are stubs or placeholders. Known example: `truck_speed_1` cost = 1. Others likely similar.
- `vehicle_capacity` upgrade is **player-wide** (adds to `state.upgrades.vehicle_capacity`) — a bike capacity upgrade also buffs trucks. This collapses the differentiation between vehicle types that the game otherwise tries to establish.
- Upgrades have not been meaningfully reviewed in ~12 months. Many may not fit the current game design; some may no longer even be reachable.
- Dispatch pack upgrades (`assignment_pack`, `routing_dispatch`, etc.) live in their own sub-tree. These stay as separate purchases (per License principle), but their costs and prerequisites need review alongside the economy pass.

### Target state

A curated, tuned upgrade tree where:

- Every upgrade has a real, defensible cost.
- Every upgrade has a reason to exist (player choice between meaningful alternatives).
- Capacity and other per-vehicle-type stats are actually per-vehicle-type.
- The tree is not cluttered with irrelevant or dead-end nodes.

### Work items

- Read every upgrade in `upgrades.json`. For each: keep, cut, or fix.
- Fix placeholder costs (e.g., `truck_speed_1 = 1`).
- Refactor `vehicle_capacity` from player-wide to per-vehicle-type. Split into `bike_capacity`, `car_capacity`, `truck_capacity` (matching the speed pattern). Update `UpgradeSystem.lua` effect handling and `VehiclesTab.lua` display. Remove legacy player-wide references.
- Remove upgrades that don't fit the MVP design (including the now-defunct scope-raising Expansion nodes per §1).
- Verify prerequisites are coherent — no orphaned or unreachable nodes.

### Notes

- This is a judgement-heavy pass. The output is as much a design document as a code change.
- Individual pack upgrades stay — they are part of the "choose your own adventure" after a license.

---

## 5. Fuel in Upgrades

### Current state

- `fuel_rate` is a per-vehicle-type constant loaded from vehicle config in `models/vehicles/Vehicle.lua`.
- No upgrades modify fuel_rate. No fuel-related upgrade paths exist anywhere in `upgrades.json`.

### Target state

Fuel-efficiency upgrades as a real purchasable axis in the Vehicles category. Parallels the existing speed and capacity paths. Gives the player an answer to "my fuel costs are too high" besides "run fewer trips."

Representative upgrades:

- **Fuel-efficient engine** (per vehicle type) — reduces `fuel_rate` by some %. Multiple tiers.
- **Route optimization** (global or per type) — reduces effective `path_cost` by some %. (Optional — overlaps with the dispatch-card "prefer short paths" axis; decide during implementation.)

### Work items

- Add fuel-efficiency upgrade nodes per vehicle type in `data/upgrades.json` (bike, car, truck). Ship is out of scope.
- `UpgradeSystem.lua` needs to handle an effect that multiplies `fuel_rate` downward. `multiply_stat` likely works if the target is the per-type fuel_rate field; verify routing.
- Ensure live vehicles pick up the reduced `fuel_rate` the same way they pick up speed changes.

### Notes

- Fuel upgrades should not trivialize fuel cost. Tuning target: upgrades reduce the fuel-vs-payout tension but don't eliminate it. Player still cares about right-sizing even fully upgraded.

### Status: Implemented

Shipped bundled inside commit `dc65f30` ("Phases 1-2: data hygiene + license refactor"). Not called out in the commit message, which is why it read as unaddressed.

- `data/upgrades.json` — 9 nodes under per-vehicle-type sub-trees:
  - Bike: `bike_fuel_1` ($3k) → `bike_fuel_2` ($15k, prereq `bike_fuel_1`) → `bike_fuel_3` ($60k, prereq `bike_fuel_2`)
  - Car:  `car_fuel_1` ($5k) → `car_fuel_2` → `car_fuel_3` (prereq chain; `required_scope: 2`)
  - Truck: `truck_fuel_1` ($12k) → `truck_fuel_2` → `truck_fuel_3` (prereq chain; `required_scope: 3`)
  - Each: `effect_type: "multiply_stat"`, `effect_target: "{type}_fuel_rate"`, `effect_value: 0.9` (−10%/level). Fully upgraded: 0.729× base.
- `models/UpgradeSystem.lua:148` — existing `multiply_stat` handler routes `{type}_fuel_rate` into `state.upgrades[target]` multiplicatively. No new handler needed.
- `models/vehicles/Vehicle.lua:97-103` — `getEffectiveFuelRate(game)` returns `base_fuel_rate × (state.upgrades[type.."_fuel_rate"] or 1.0)`. Lazy-read (no per-instance caching).
- `services/FuelService.lua:13` — `computeAndStore` consumes via the getter, not a raw field read.
- `data/vehicles/{bike,car,truck}.json` — base `fuel_rate` values: 0.01 / 0.05 / 0.10.
- Ship is deliberately out of scope per principles; no ship fuel upgrade exists.
- "Route optimization" upgrades (the optional half of the target-state notes) are NOT implemented. That was flagged as "decide during implementation" and was not adopted.

### Deviations

- No global `fuel_rate` upgrade; all nodes are strictly per-vehicle-type (matches the MVP principle that per-type trees replace player-wide stats).
- `max_level: 1` per node with a prerequisite chain, rather than a single multi-level node. Outcome is equivalent (three discrete purchases) but represented as three separate upgrades.

---

## 6. Starting City Picker

### Current state

`controllers/WorldSandboxController.lua` line ~396 picks the starting city uniformly at random from all generated cities: `local start_idx = love.math.random(1, #self.city_locations)`.

World gen produces ~32 cities across ~20 regions (configurable). Each city has a `bounds` set of cell indices (from `CityBoundsService`). No explicit population — cell count is the implicit size proxy, and that is fine.

### Target state

Deterministic-ish selection rule: the starting city is the **smallest city in a region that contains at least 2 cities**. If multiple regions qualify, pick among them by whatever criterion (random among eligible regions is fine, or prefer some region-level property if it emerges as useful).

This gives the player a credible small home base with at least one neighbor city — laying the groundwork for the City-license expansion arc to feel natural.

### Work items

- In `WorldSandboxController.lua` around the current random-pick site, replace with:
  1. Group cities by `region_map[ci]`.
  2. Filter to regions with ≥ 2 cities.
  3. Among qualifying regions, pick one (random is acceptable).
  4. Within that region, pick the city with the smallest `#bounds`.
- Handle the edge case where no region has ≥ 2 cities (unlikely with 32 cities / 20 regions, but possible) — fall back to the smallest city overall, or regenerate world. Pick whichever is simpler.

### Notes

- ~15 lines of change. Lowest-risk item in the refactor.

### Status: Implemented

Selection logic shipped inside commit `dc65f30` ("Phases 1-2: data hygiene + license refactor"); architecture cleanup (data-driven constants, fallback removal, success logging) shipped in the Phase 6 cleanup pass.

- `controllers/WorldSandboxController.lua` — `pickStartIdx()` groups cities by `region_map[ci]`, filters to regions with ≥`STARTING_CITY_MIN_REGION_SIZE` cities, picks a random qualifying region, and returns the smallest city in that region (by `boundsCount`).
- Regen-on-failure: if no qualifying region exists, `self:generate()` + `self:place_cities()` are re-run up to `STARTING_CITY_MAX_REGEN_ATTEMPTS` times. Exhausting the cap hard-errors (the Region license tier is unplayable without a neighbor city, so fallback is not an option).
- `data/constants.lua` — `C.WORLD_GEN.STARTING_CITY_MIN_REGION_SIZE` (2) and `C.WORLD_GEN.STARTING_CITY_MAX_REGEN_ATTEMPTS` (10). No magic numbers in the picker.
- Success log: `WorldSandboxController: starting city idx=N region=R bounds=K` prints once per successful pick.

### Deviations

- Spec permitted "fall back to smallest city overall, or regenerate world — whichever is simpler." Regen-only was chosen; fallback is architecturally forbidden (a world with no ≥2-city region breaks Region scope progression).
- Two pre-existing silent "just in case" branches (nil-bounds remap to city 1; degenerate-bbox coerce to 30×30) were deleted during cleanup. They now hard-error instead — matches the "Refactoring means deleting" MVP principle.

---

## 7. Onboarding Plumbing

### Current state

- Fresh save: `scope_tier = 1`, `auto_dispatch_unlocked = false`, ~$150, one bike.
- Default active tab is **Dispatch** (registered with priority 1 in `UIManager.lua`). The Dispatch tab on a fresh save shows a gate message: *"Purchase the Auto-Dispatcher upgrade to unlock dispatch rules"* (`DispatchTab.lua:1918-1921`).
- Trip assignment without dispatch: `AutoDispatcher` returns early when `auto_dispatch_unlocked = false`. The player must manually assign — click a vehicle in Vehicles tab, click a trip in Trips tab. This works but is not signposted.
- No tutorial, no onboarding prompts, no nudges.

### Target state

A fresh player lands on a playable screen and has a legible path to their first action.

- Default active tab is **not** a gated screen. Likely Trips or Vehicles, whichever reads best. Or a new landing/HUD surface if UI scope expands.
- The Dispatch tab, while locked, should either be hidden outright or clearly labeled as not-yet-unlocked with minimal visual weight.
- Manual click-vehicle-then-click-trip assignment is the core minute-one interaction. It should be discoverable — at minimum through tab ordering and labeling; ideally with a first-time hint.
- Heavy graphical polish is explicitly deferred. This section is about the minimum needed to make a fresh save playable without confusion.

### Work items

- Change default tab registration priority so a playable tab (Trips) is default-active on a fresh save.
- Hide the Dispatch tab when `auto_dispatch_unlocked = false`, or render it as clearly gated without occupying the default slot.
- (Optional, stretch) Add a first-time-hint overlay on Trips/Vehicles indicating manual-assign flow.

### Notes

- This is the smallest item in the refactor mechanically but potentially the highest impact on whether a new player "gets" the game.

### Status: Implemented

Shipped in Phase 7 cleanup pass.

- `views/Panel.lua` — `registerTab` now accepts an optional `visible_when = function(game) -> bool` predicate. `Panel:_visibleTabs(game)` filters the tab bar + click routing; `Panel:_resolveActiveTab(game)` reassigns `active_tab_id` to the first visible tab if the current active is hidden. Framework stays agnostic — no tab ids, no game-state knowledge inside Panel.
- `views/UIManager.lua` — tab priorities reordered so a playable tab lands first on fresh save:
  - `trips` (1), `vehicles` (2), `dispatch` (3), `upgrades` (4), `clients` (5), `depot` (6), `infrastructure` (7).
  - Dispatch carries `visible_when = function(g) return g.state.upgrades.auto_dispatch_unlocked == true end`.
- `views/tabs/DispatchTab.lua` — the `auto_dispatch_unlocked` gate branch (former L1918–1923) is deleted. Build fn now assumes unlock, since the tab is hidden otherwise.
- `controllers/UIController.lua` — `panel:handleMouseDown` now receives `Game` so the click router can consult the same visibility filter.
- Re-show on unlock is automatic: the per-frame `Panel:draw` polling (`views/Panel.lua:210-211` pattern) picks up the new predicate result immediately.

### Deviations

- First-time-hint overlay (stretch in the spec) was not implemented — no scaffolding existed and a fresh save is already playable without it.
- No `data/tabs.lua` registry refactor. The imperative registration block is small and refactoring it was scope creep.
- The `visible_when` field was added as a generic framework capability; its only current consumer is Dispatch. Future scope-gated tabs (Depot/Clients) can opt in without further Panel changes.

---

## 8. Economy Tuning Pass

### Current state

- Starting money: $150 (`data/constants.lua`).
- Base trip payout: $50, with a city-trip multiplier of 20.
- Trip generation every 10–20 seconds.
- Many upgrade costs are nominal or placeholder.
- License costs (to the extent licenses-as-upgrades exist today) not tuned for MVP license framing.

### Target state

Numbers that produce the intended pacing:

- A 30+ minute arc from game start to affordability of the City license.
- Meaningful trade-offs at each purchase decision (a license versus several smaller upgrades; a new vehicle versus efficiency improvements on current ones).
- Fuel cost that matters but doesn't dominate.

### Work items

- Tuning is inherently iterative. It happens as part of implementing §§1–5, not as a standalone step.
- Set initial values, play, adjust. Keep all constants centralized in `data/constants.lua` and the relevant JSON/Lua data files — no magic numbers scattered in service code.

### Notes

- Tuning is the whole point, not a gating question. Every number in the game is currently meaningless until this pass runs.

### Status: Implemented

Phase 8 is inherently two-layered:

**Architectural compliance** — done in this pass. Audit confirmed (and this commit closed the remaining gap) that no gameplay-relevant magic numbers live in logic code. Every tunable has a single source of truth in a data file.

**Numeric tuning** — this pass produced math-driven first-pass values for the provably-broken axis (fuel upgrades) and fixed a starter-archetype trap. Final values emerge from playtest iteration, which is user-driven and out of single-commit scope.

Work shipped in this pass:

- `services/StatsService.lua` — `WINDOW = 15` moved to `C.GAMEPLAY.STATS_WINDOW_SEC`. No gameplay-relevant literal remains in any service, controller, or model.
- `data/constants.lua` — deleted orphan entries with zero runtime readers: `CITY_TRIP_PAYOUT_MULTIPLIER`, `CITY_TRIP_BONUS_MULTIPLIER`, `TRIP_GENERATION_MIN_SEC`, `TRIP_GENERATION_MAX_SEC`, `MIN_DELTA_CALCULATION` from `GAMEPLAY`; `DURATION_UPGRADE_AMOUNT`, `FRENZY_TRIP_MIN_SEC`, `FRENZY_TRIP_MAX_SEC` from `EVENTS`. The entire `COSTS` table was deleted — every entry was a relic from the pre-JSON upgrade era (real upgrade costs live in `data/upgrades.json`, license costs in `data/licenses.lua`, market costs per archetype).
- `data/ConstantsValidator.lua` — validator entries for deleted constants removed; `_validateCosts` deleted.
- `data/upgrades.json` — fuel-upgrade costs rescaled to plausible break-even ranges (break-even ≈ 300 trips of savings at the relevant tier):
  - Bike: `3000 / 15000 / 60000` → `150 / 750 / 3000`
  - Car:  `5000 / 25000 / 100000` → `800 / 4000 / 16000`
  - Truck: `12000 / 50000 / 200000` → `2000 / 10000 / 40000`
- `data/client_archetypes.lua` — default starter archetype changed from `retail` (cargo 2–5, exceeds bike capacity) to `restaurant` (cargo 1–2, fits). The former trapped a fresh save with a client whose trips the starting bike physically couldn't assign.

### Deviations

- The iterative playtest loop is out of scope for this commit. Playtest sessions edit data files directly; no plan needed.
- `CITY_TRIP_PAYOUT_MULTIPLIER = 20` was suspected of double-counting with per-archetype `payout_multiplier` — grep confirmed it had no runtime reader at all, so it was deleted outright rather than documented-and-kept. The archetype multiplier is now the sole city-scope economy knob.
- The spec's "30+ minute arc to City license" was left untested numerically. The `city_license` cost ($5000) was retained; re-tune after playtest. The starter-archetype fix was the blocker for the arc even being possible.
- Fuel-upgrade break-even analysis used estimated trip fuel cost per vehicle ($2.50 bike, $25 car, $50 truck) derived from the pathfinding cost tables, not runtime measurements. Playtest may surface the need for further adjustment.

### Tuning Surface

Every gameplay knob lives in one of these files. Tuning edits go here, not in code.

- **`data/constants.lua`** `GAMEPLAY` — `INITIAL_MONEY`, `BASE_TRIP_PAYOUT`, `INITIAL_SPEED_BONUS`, `BONUS_DECAY_RATE`, `MAX_PENDING_TRIPS`, `AUTODISPATCH_INTERVAL`, `VEHICLE_STUCK_TIMER`, `STATS_WINDOW_SEC`.
- **`data/constants.lua`** `EVENTS` — rush-hour `SPAWN_MIN_SEC`, `SPAWN_MAX_SEC`, `LIFESPAN_SEC`, `INITIAL_DURATION_SEC`.
- **`data/constants.lua`** `EFFECTS` — `PAYOUT_TEXT_LIFESPAN_SEC`, `PAYOUT_TEXT_FLOAT_SPEED`.
- **`data/licenses.lua`** — `cost` per license (`city_license`, `region_license`).
- **`data/upgrades.json`** — every upgrade's `cost`, `cost_multiplier`, `max_level`, `effect_value`.
- **`data/client_archetypes.lua`** — per archetype: `base_spawn_seconds`, `payout_multiplier`, `market_cost`, `cargo_size_range`, `dest_scope_weights`, `required_scope_tier`. Also `default_id` for the fresh-save starter.
- **`data/vehicles/{bike,car,truck,ship}.json`** — `base_speed`, `base_capacity`, `base_cost`, `cost_multiplier`, `fuel_rate`, `pathfinding_costs`.
- **`data/rule_packs.lua`** — pack `count`, `max_complexity`, `tags`, `scope_tier` (no inline costs; grants reference pack ids in `upgrades.json`).

---

## 9. Client Archetypes, Trip Generation, Cargo

### Current state

- **Clients are uniform.** `models/Client.lua` is a single generic class: `plot`, `trip_timer`, `freq_mult`, `capacity`, `cargo[]`. No archetype, no typing.
- **Client placement** is zone-tied — `services/EntityManager.lua:54-68` picks a random plot in a `can_send` zone (commercial/industrial/etc.) via the zone config in `data/zones.lua`. Infrastructure for archetype-aware placement already exists; the differentiation is just not expressed yet.
- **Trip generation** (`services/TripGenerator.lua:20-48`) is hardcoded: `scope = "district"`, cargo-size = 1, destination = any same-district `can_receive` plot with a city-wide fallback. `DebugTripFactory` has scope-aware destination logic (district/city/region/continent/world with payout multipliers 1x/1.5x/3x/5x/8x) that production never calls.
- **Cargo** is just a size number. No cargo types, no vehicle-type requirements beyond capacity. `TripEligibilityService.canAssign` checks `vehicle.capacity >= trip cargo_size` and that's it. This is correct; keep it.
- **Deadlines**: none. Trips have a `speed_bonus` that decays with wait time, but no hard deadline or critical-trip tier.
- **Client acquisition**: "Market for Clients" button spawns a new generic client for a fixed cost. No archetype choice, no progression.
- **Client upgrades**: a `Clients` upgrade category exists in `data/upgrades.json` but applies to all clients uniformly.

### Target state

**Client archetypes** — differentiated configs (not subclasses) for the kinds of businesses the player works with. MVP set: 3-5 archetypes. Representative shape:

| Archetype | Spawn zone | Cargo size range | Destination scope distribution | Scope tier required |
|-----------|-----------|------------------|-------------------------------|---------------------|
| Lawyer    | commercial / office | 1-3  | ~all local (district)        | 1 (Downtown)        |
| Restaurant| mixed / retail      | 1-2  | all local, short radius      | 1 (Downtown)        |
| Retail    | commercial          | 2-5  | mostly local, some cross-district | 1 (Downtown)   |
| Warehouse | industrial          | 10-100 | mix of district / city / region | 2 (City)        |
| Factory   | industrial          | 50-200 | cross-city / region          | 3 (Region)          |

Each archetype has its own config record with:
- Spawn zone(s) the client can occupy.
- Cargo size range `{min, max}`.
- Destination scope distribution (weighted table: how often a generated trip is district / city / region).
- Base spawn frequency (seconds between trips).
- Payout multiplier.
- Required scope tier to even appear as a purchasable client.

**Per-archetype upgrade trees** — each archetype gets its own upgrade tree in the `Clients` upgrade category, parallel to how vehicles have per-type trees (bike / car / truck). Specializing in lawyers = upgrading the Lawyer tree. Representative per-archetype upgrades: faster spawn rate, higher payout multiplier, larger cargo size bias, better deadline odds. No generic "all clients" upgrade — if a property is shared, it's still set per archetype.

**Two-tier deadline system** — no per-archetype deadline profile. Instead:
- **Regular trips** (default) — existing speed_bonus decay, no hard deadline.
- **Rush / Critical trips** (unlockable) — much higher bonus, tight hard deadline; if not delivered in time the trip expires and pays zero (or penalizes). Whether a trip spawns as Rush is a per-archetype probability, tuned per archetype's upgrade tree. Unlock is its own scope-gated purchase (could be a card, an upgrade, or part of an archetype tree — decide during implementation).

**Out-of-scope trips eat silently.** When an archetype rolls a destination scope the player can't service under their current license, the trip is not created. The client's `trip_timer` resets; nothing goes to the pending queue; no notification. The hidden cost of running a mismatched archetype is felt as reduced effective trip rate. This replaces the previous open question — no unreachable-trip clutter, no forced fallback to local scope.

**Client acquisition** respects archetype scope gating. Downtown license = access to Lawyer / Restaurant / Retail clients at the market. City license = adds Warehouse. Region = adds Factory.

### New data / structures

- `data/client_archetypes.lua` — archetype config registry.
- `models/Client.lua` — add `archetype` field; all runtime behavior reads from the archetype config.
- `data/upgrades.json` — replace the generic `Clients` tree with per-archetype sub-trees (following the pattern of the per-vehicle-type trees).
- `models/Trip.lua` — add `deadline` field (nil for Regular, seconds-from-now for Rush). **Do not touch leg infrastructure** — legs stay alive, dispatch rules use them.
- `services/TripGenerator.lua` — read the client's archetype, roll cargo size + destination scope from the archetype config, bail (silently) if scope exceeds player license.
- Enum values for archetype ids can be added where needed (enums are free to grow).

### Work items

- Define the initial archetype set (3-5) in `data/client_archetypes.lua` with real config values.
- Replace `TripGenerator.generateTrip` logic to be archetype-driven; integrate scope-based destination picking from `DebugTripFactory` into production flow.
- Extend `Client:new` to accept/store an archetype id; default zone-based placement uses archetype-preferred zones.
- Rework `data/upgrades.json` `Clients` category into per-archetype sub-trees.
- Update `ClientsTab` / `DepotTab` market UIs to show archetype options (respecting scope gating) — UI polish is §7-scope, but wiring the archetype choice is here.
- Add `trip.deadline` handling: expiration check in trip update loop, UI surface on the Trips tab, payout zeroing on expiry.

### Notes

- No cargo-type enum, no vehicle-type requirements. Capacity is the only fit check.
- No archetype-specific deadline profiles. Deadlines are a two-tier system (regular / rush), with Rush probability driven by archetype upgrades.
- Eating out-of-scope trips silently is intentional — keeps the pending queue clean and makes archetype/license matchup a real strategic choice.

---

## Out of Scope (Explicitly)

To prevent scope creep, these are **not** MVP:

- Continent and World scopes.
- Boats, ships, any water transport gameplay. Ship code stays dormant.
- Planes, trains, any new vehicle mode.
- Fuel tanks, refueling, fuel stations, fuel-level conditions.
- New dispatch block types.
- Heavy graphical polish beyond minimum onboarding legibility.
- Depot analytics feature completion (data captured but unused — leave alone).

---

## Execution Order

No hard ordering dependency between most sections, but a sensible flow:

1. **Starting city picker (§6)** — small, isolated, low risk. Ship first.
2. **Upgrades review (§4)** and **Fuel in upgrades (§5)** — do together, they both live in the same data file and touch the same handler code.
3. **License refactor (§1)** — depends on §4 cleanup for the final shape of the Expansion tree.
4. **Client archetypes (§9)** — reshapes trip generation and the Clients upgrade tree. Do after §1 since archetype scope-gating depends on the license system being real, and before §2/§3 so new cards can reference archetype properties if useful.
5. **Card authoring (§2)** and **Fuel-aware dispatch cards (§3)** — largest content load, can run in parallel with each other.
6. **Onboarding plumbing (§7)** — final pass, can't fully tune until the systems above settle.
7. **Economy tuning (§8)** — continuous across all above.

No section should be committed without testing and a deviation-review check-in.
