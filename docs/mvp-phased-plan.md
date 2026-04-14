# Cosmic Courier — MVP Phased Action Plan

> Created: 2026-04-13
> Source document: `docs/mvp-refactor.md`
> Scope: License system, upgrades, fuel, clients, trip generation, dispatch card authoring, onboarding, economy tuning
> Goal: A playable MVP with real progression from Downtown → City → Region, differentiated clients, fuel-aware dispatch decisions, and tuned economic pacing.

---

## Critical Rules

1. **No phase begins until the previous phase is complete and tested.**
2. **No feature work during a structural phase.** If a phase is a rename / consolidation, the game must behave identically before and after.
3. **One logical change per commit.** Do not combine a rename with a behavior change.
4. **If a phase uncovers a real bug, fix it in a separate commit first.**
5. **Delete the old code.** No backward-compat shims, no commented-out originals, no "in case we need it later" flags.
6. **When a phase is complete: update this document with status, deviations, and line count change. Send the user test instructions. Do NOT commit until the user has tested and explicitly asked to commit.**

---

## Non-Negotiable Design Principles

These apply to every phase. They override any implementer instinct that contradicts them.

- **Five primitives frozen.** The 5 structural primitives in `data/dispatch_blocks.lua` are turing-complete and will not grow. No new primitive blocks, ever.
- **Hats / actions / properties / sorters / collections / enums can grow.** These are not primitives. Add entries to the corresponding `data/dispatch_*.lua` files as new cards require them.
- **License is a pure scope gate.** A license raises `scope_tier` and does nothing else. It does NOT bundle card packs, vehicle unlocks, or upgrades. Downstream purchases stay as separate player choices gated by `required_scope`.
- **Fuel is economics, not a tank.** Fuel is a per-trip money deduction that forces load-consolidation decisions. No fuel levels, no refueling, no fuel stations. Ever.
- **Cargo is a capacity number.** No cargo types, no vehicle-type requirements. If a vehicle's capacity is ≥ trip's cargo_size, it can carry it.
- **Tier 1 (Downtown) card pool stays sparse.** Do not propose adding cards here unless explicitly asked.
- **Refactoring means deleting.** Old code comes out when new code goes in.

---

## Architecture Summary

The MVP refactor resolves five structural problems simultaneously:

1. **Progression is meaningless** — scope-raise is buried in the Expansion upgrade tree and feels like a checkbox. Fix: extract into a dedicated **License** system with its own UI surface. Mechanically unchanged (just `set_flag scope_tier N`), but presented as a phase transition.
2. **Clients are uniform** — every client is a generic trip generator. Fix: introduce **Client archetypes** (Lawyer, Restaurant, Warehouse, etc.) differentiated by spawn zone, cargo size range, destination scope distribution, and per-archetype upgrade trees. Archetypes themselves are scope-gated, so they participate in the license progression.
3. **Cards are thin** — 16 templates for a game that claims a rich dispatch system. Fix: **author tier-2 and tier-3 packs** with real content, driven by catalog triage. Tier 1 stays sparse.
4. **Fuel is invisible** — it's deducted silently, no dispatch rule can reason about it. Fix: expose fuel as **dispatch data** (properties, sorters) and author **fuel-aware cards** that turn "car with 1 vs truck with 5" into a real puzzle.
5. **Onboarding is broken** — default tab is the gated Dispatch tab. Fix: default to a playable tab, hide the gate, let manual click-assignment carry the 30+ minute arc to the first City license.

Underneath all of this is a **tuning pass** — most numeric constants in the game today are placeholders. Tuning is the final phase.

---

## Phase 1 — Data Hygiene

**Goal:** Ship the low-risk data-file changes in one pass: starting city picker, upgrades audit (cuts, cost fixes, per-vehicle-type capacity split), and per-vehicle-type fuel-efficiency upgrade nodes. All three are data-centric with localized consumer changes.

### Tasks

| # | File | Change |
|---|------|--------|
| **Starting city** | | |
| 1.1 | `controllers/WorldSandboxController.lua` (~line 396) | Replace random city pick with: group cities by `region_map[ci]`, filter to regions with ≥ 2 cities, pick one qualifying region, choose the city with smallest `#bounds`. Fall back to smallest overall if no region has ≥ 2 cities; log the fallback. |
| **Upgrades audit** | | |
| 1.2 | `data/upgrades.json` | Read every upgrade. Cut ones outside MVP scope. Fix placeholder costs (known example: `truck_speed_1 = 1`). Walk every `cost` for similar placeholders. Keep dispatch pack upgrades' structure for now — Phase 2 restructures that tree when licenses move in. |
| 1.3 | `data/upgrades.json` | Split player-wide `vehicle_capacity` into `bike_capacity`, `car_capacity`, `truck_capacity`, each in its vehicle's sub-tree. Cascade split through shared children (cargo_racks, bike_trailer, etc.). |
| 1.4 | `models/UpgradeSystem.lua` | Route `add_stat` / `multiply_stat` capacity effects to the per-vehicle-type field. |
| 1.5 | `models/vehicles/Vehicle.lua` | `getEffectiveCapacity(game)` reads the per-vehicle-type upgrade stat. |
| 1.6 | `views/tabs/VehiclesTab.lua` | Capacity display reads per-vehicle-type field. Remove legacy read. |
| 1.7 | `data/upgrades.json` | Verify every `prerequisites` list resolves to an existing id. No orphans. |
| 1.8 | Grep sweep | Confirm zero references to `state.upgrades.vehicle_capacity` remain. |
| **Fuel efficiency** | | |
| 1.9 | `data/upgrades.json` | Add fuel-efficiency node(s) to each vehicle sub-tree (bike, car, truck). Multi-level. Effect multiplies `fuel_rate` downward. No ship nodes — out of MVP. |
| 1.10 | `models/UpgradeSystem.lua` | Ensure `multiply_stat` accepts per-vehicle-type `fuel_rate` as a target. |
| 1.11 | `models/vehicles/Vehicle.lua` | `getEffectiveFuelRate(game)` = base `fuel_rate` × per-type upgrade stat. |
| 1.12 | `services/FuelService.lua` | Replace direct `vehicle.fuel_rate` reads with `vehicle:getEffectiveFuelRate(game)`. |
| **Save migration** | | |
| 1.13 | `services/SaveService.lua` | One-time migration in `applySaveData`: legacy `state.upgrades.vehicle_capacity` value copies to all three per-type fields; legacy field deleted after migration. |

### Expected Outcome

- New saves spawn in a credible starting city.
- Upgrade tree is coherent; costs are real; capacity upgrades differentiate by vehicle type.
- Fuel efficiency is a real purchasable axis; upgrading truck fuel efficiency does not affect bikes.
- Legacy saves load cleanly with the capacity migration.

### Testing

- Generate 5 worlds, verify the starting city is the smallest in a ≥2-city region each time.
- New save: buy `bike_capacity_1`, spawn a truck, verify truck capacity is unchanged.
- Note baseline truck trip fuel cost, buy truck fuel-efficiency upgrade, re-run, verify the drop is ~ the expected fraction. Verify bikes and cars are unaffected.
- Load an older save: verify capacity-equivalent, no data loss.
- Grep confirms zero references to the legacy player-wide capacity field.
- Regression: a full cross-city delivery works normally with a non-upgraded vehicle.

### AI Notes

- Tuning target for fuel efficiency: reduces tension, doesn't eliminate it. A fully-upgraded player should still care about vehicle right-sizing.
- Do not touch `vehicle.transport_mode` — that's pathfinding.
- Scope-raising Expansion upgrades (`city_expansion`, `regional_network`, etc.) are NOT touched here — Phase 2 handles them.

---

**Status:** Not started
**Line count change:** —
**Deviation from plan:** —

---

## Phase 2 — License Refactor

**Goal:** Extract the scope-raising upgrades into a dedicated License system with its own UI surface. Mechanically identical to the current scope-raising upgrades (still `set_flag scope_tier N`), but presented as a phase transition rather than a tree checkbox.

### Tasks

| # | File | Change |
|---|------|--------|
| 2.1 | `data/upgrades.json` | Delete `city_expansion`, `regional_network` from the Expansion sub-tree. Delete `continental_reach` and `global_operations` (out of MVP). |
| 2.2 | `data/licenses.lua` | **New file.** Three entries: `downtown_license` (held at start, not purchasable), `city_license`, `region_license`. Each: `id`, `display_name`, `cost`, `scope_tier`, `description`. |
| 2.3 | `models/GameState.lua` | `state.licenses = { downtown = true }` default on new save. |
| 2.4 | `services/LicenseService.lua` | **New file.** `getCurrentLicense`, `canPurchase`, `purchase`. Purchase deducts money, sets the flag, derives `scope_tier` from license set, publishes `license_purchased`. |
| 2.5 | `services/ScopeService.lua` | Make license set the source of truth; `scope_tier` derives via `LicenseService.getCurrentScope(game)`. |
| 2.6 | `services/EventService.lua` | Subscribe to `license_purchased` for UI refresh / confirmation. No side effects that bundle packs/vehicles/upgrades. |
| 2.7 | `services/SaveService.lua` | Persist `state.licenses`. Migration: old saves with `scope_tier >= 2` get `city_license = true`; `>= 3` gets `region_license = true`. Clear the old scope_tier field after derivation. |
| 2.8 | UI — **new License surface** | Prominent HUD button or dedicated screen (NOT a tab node, NOT a tree node). Shows current license + next-available license's cost + purchase affordance. Confirmation prompt on purchase. |
| 2.9 | `views/tabs/UpgradesTab.lua` | Remove rendering for the deleted Expansion scope-raising nodes. |
| 2.10 | Grep sweep | Zero references to `city_expansion` / `regional_network` / `continental_reach` / `global_operations` remain. |

### Expected Outcome

Player sees a clearly distinct License purchase moment. Mechanically `scope_tier` rises exactly as before. Downstream scope-gated purchases still gate correctly.

### Testing

- New save: `state.licenses.downtown = true`, scope = 1, no City/Region.
- Buy City license via the new UI: money deducted, scope at 2, scope-2-gated items appear as purchasable.
- Buy Region license: scope 3, region-2-gated items appear.
- Load an older save with `scope_tier = 3`: both `city_license` and `region_license` present after migration.
- Grep confirms no old upgrade ids.

### AI Notes

- License UI is a brand-new surface. Don't shoehorn into the existing upgrade tree rendering.
- License purchase is the ONLY thing that happens in the transaction. Do not grant packs / vehicles / upgrades — the memory `project_license_is_pure_gate.md` is load-bearing.
- Pick one source of truth between `state.licenses` and `scope_tier`; derive the other. Recommendation: licenses are source-of-truth.

---

**Status:** Not started
**Line count change:** —
**Deviation from plan:** —

---

## Phase 3 — Client Archetypes: Data & Generation

**Goal:** Introduce client archetypes driving spawn zone, cargo size, destination scope, and spawn frequency. Out-of-scope trips eat silently. Per-archetype upgrade trees come in Phase 4 — this phase only adds the data layer and trip-generation changes.

### Tasks

| # | File | Change |
|---|------|--------|
| 3.1 | `data/client_archetypes.lua` | **New file.** Each entry: `id`, `display_name`, `spawn_zones` (list), `cargo_size_range = {min, max}`, `dest_scope_weights = { district = N, city = M, region = K }`, `base_spawn_seconds = {min, max}`, `payout_multiplier`, `required_scope_tier`, `market_cost`. MVP set: Lawyer, Restaurant, Retail, Warehouse, Factory. |
| 3.2 | `models/Client.lua` | Add `archetype` field. Constructor accepts archetype id. Runtime behavior reads the archetype config. Default for any un-archetyped client is `"retail"`. |
| 3.3 | `services/EntityManager.lua` | `addClient(game, depot, archetype_id)` picks a placement plot matching the archetype's allowed zones (via the existing `can_send` filtering restricted to archetype zones). Fall back to any `can_send` plot if no archetype-preferred plot exists. |
| 3.4 | `services/TripGenerator.lua` | Replace hardcoded `scope = "district"` / `cargo_size = 1` with archetype-driven rolls. Cargo: uniform in range. Destination scope: weighted pick. Destination plot: integrate `DebugTripFactory`'s scope-aware destination selection into production. |
| 3.5 | `services/TripGenerator.lua` | **Out-of-scope eating.** If rolled destination scope > player's current tier, return nil. Client's `trip_timer` resets via normal flow. No fallback, no queue entry, no notification. |
| 3.6 | `services/EventService.lua` | Verify subscribers handle nil-trip result cleanly. |
| 3.7 | `services/SaveService.lua` | Persist `client.archetype`. Migration: legacy clients get `"retail"`. |
| 3.8 | `EntityManager:init()` | Starting client gets a Downtown-tier archetype (pick and document — e.g., `"retail"`). |

### Expected Outcome

Clients spawn in zones appropriate to their archetype. Trip cargo sizes and destination scopes vary by archetype. Mismatched archetypes (e.g. Warehouse under Downtown license) silently burn trip-generation cycles.

### Testing

- Spawn a Lawyer with Downtown license, observe ~10 trips: cargo 1-3, all same-district.
- Buy City license, spawn a Warehouse, observe ~10 trips: cargo 10-100, mix of scopes.
- Temporarily allow a Warehouse under Downtown (via debug), observe many generation cycles with no trips appearing.
- Load an older save: all clients present with `"retail"` archetype, trips still generate.

### AI Notes

- `DebugTripFactory`'s scope-aware destination pools are the integration target. Do not reimplement; extract or call from production path.
- Do not add cargo type enum. Do not add vehicle-type requirements.
- Save migration runs once on load.

---

**Status:** Not started
**Line count change:** —
**Deviation from plan:** —

---

## Phase 4 — Client Archetypes: Per-Archetype Upgrade Trees + Market Gating

**Goal:** Replace the generic Clients upgrade category with per-archetype sub-trees (parallel to per-vehicle-type trees). Market UI respects archetype scope gating.

### Tasks

| # | File | Change |
|---|------|--------|
| 4.1 | `data/upgrades.json` | Restructure the `clients` category: replace the shared sub-tree with per-archetype sub-trees (`lawyer`, `restaurant`, `retail`, `warehouse`, `factory`). Each contains: spawn-rate upgrade(s), payout-multiplier upgrade(s), cargo-size-bias upgrade(s), Rush-probability upgrade(s) (Rush comes in Phase 5 — scaffold the nodes now, they're zero-effect until then). |
| 4.2 | `models/UpgradeSystem.lua` | Archetype-scoped effect routing: `state.client_upgrades.<archetype>.<stat>`. Add routing as needed. |
| 4.3 | `services/TripGenerator.lua` | Trip frequency / payout / cargo-size bias consult per-archetype upgrade multipliers on top of base archetype config. |
| 4.4 | `services/EntityManager.lua` | `addClient` respects archetype `required_scope_tier` ≤ player's tier. |
| 4.5 | `views/tabs/ClientsTab.lua` + `DepotTab.lua` | Market UI shows archetype options. Locked archetypes greyed with "City License required" / "Region License required" label. |
| 4.6 | `services/SaveService.lua` | Persist `state.client_upgrades` per archetype. Migration: legacy shared values map to `retail`; old field cleared. |
| 4.7 | Grep sweep | No reads from the old shared `state.clients` upgrade fields. |

### Expected Outcome

Player can specialize. Upgrading Lawyer affects lawyers only. Market UI clearly shows which archetypes are locked behind licenses.

### Testing

- New save: market shows Lawyer/Restaurant/Retail purchasable, Warehouse/Factory greyed.
- Buy Lawyer spawn-rate upgrade. Spawn Lawyer + Retail. Verify Lawyer is faster; Retail unaffected.
- Buy City license. Warehouse becomes purchasable.
- Load old save: clients present, retail upgrade values migrated.

### AI Notes

- Per-archetype prereq ids stay within their own tree. No cross-archetype prereqs.
- UI polish is explicitly not this phase's concern; minimum legibility is enough.

---

**Status:** Not started
**Line count change:** —
**Deviation from plan:** —

---

## Phase 5 — Two-Tier Deadlines (Regular & Rush)

**Goal:** Trips can spawn as Regular (current behavior) or Rush (hard deadline, much higher bonus, $0 payout on expiry). Rush probability is per-archetype and upgradeable (Phase 4 scaffolded the upgrade nodes).

### Tasks

| # | File | Change |
|---|------|--------|
| 5.1 | `models/Trip.lua` | Add `deadline` (nil for Regular, seconds-from-now for Rush) and `is_rush` (bool, default false). |
| 5.2 | `data/client_archetypes.lua` | Add `rush_probability` (0.0–1.0), `rush_bonus_multiplier`, `rush_deadline_seconds` per archetype. Tight deadlines for Restaurant (~60s) vs longer for Warehouse (~180s). |
| 5.3 | `services/TripGenerator.lua` | After rolling cargo + destination, roll Rush from archetype probability × archetype upgrade multiplier. If Rush: set `is_rush`, `deadline = now + rush_deadline_seconds`, higher initial `speed_bonus` per archetype. |
| 5.4 | Trip update loop | When pending + `is_rush` + `now > deadline`: remove from pending, publish `rush_trip_expired`, no payout. When in-transit + expired: still deliver, but payout = 0. |
| 5.5 | `views/tabs/TripsTab.lua` | Countdown for Rush trips. Distinct visual treatment (color / icon). |
| 5.6 | `data/upgrades.json` | Activate the Rush-probability upgrade nodes scaffolded in Phase 4. |
| 5.7 | `services/SaveService.lua` | Persist `trip.deadline` / `trip.is_rush` for in-flight trips. Legacy trips default to nil/false. |

### Expected Outcome

Rush trips appear occasionally, visually distinct with countdowns. Delivered in time → big payout. Expired → $0. Regular trips behave exactly as before.

### Testing

- Buy Rush-probability upgrade for Retail. Spawn many retail clients. Observe Rush trips appearing with correct visual.
- Deliver a Rush trip before expiry: verify higher payout.
- Let a pending Rush expire: disappears, no payout.
- Let an in-transit Rush expire: completes delivery, $0 payout.
- Regression: Regular trips unchanged.

### AI Notes

- If any dispatch card wants to reason about Rush, add an `is_rush` property to `dispatch_properties.lua` — property additions are allowed.
- $0 payout on expiry is the entire penalty. No reputation / upset-client systems.

---

**Status:** Not started
**Line count change:** —
**Deviation from plan:** —

---

## Phase 6 — Card Authoring (Tier 2 + Tier 3)

**Goal:** Populate Tier-2 and Tier-3 pack queries with real content. 8–12 new Tier-2 templates, 6–10 Tier-3. Catalog triage captures which entries shipped, stayed aspirational, or were dropped.

### Tasks

| # | File | Change |
|---|------|--------|
| 6.1 | `docs/rule-pack-catalog.md` | Triage every Tier-2 and Tier-3 entry. Classify: `composable-from-existing-primitives` (implementable), `needs-new-data` (implementable — add hats/actions/properties/sorters/collections/enums), or `needs-new-primitive` (drop — should be rare). |
| 6.2 | `data/rule_templates.lua` | Author 8–12 Tier-2 templates tagged `assignment` / `routing`, matching the `assignment_pack` / `routing_pack` queries. Include `complexity` and `rarity`. |
| 6.3 | `data/rule_templates.lua` | Author 6–10 Tier-3 templates tagged `hub` / `vehicle`, matching `hub_routing_pack` / `vehicle_pack`. |
| 6.4 | `data/dispatch_*.lua` | Add supporting hats / actions / properties / sorters / collections / enum values as each template requires. |
| 6.5 | `docs/rule-pack-catalog.md` | Mark each triaged entry as **shipped** / **still aspirational** / **dropped**. |
| 6.6 | `services/PackService.lua` | Add a debug command that opens a pack 20 times and prints unique-template distribution. Use it to verify variety across tiers. |

### Expected Outcome

Opening any Tier-2 or Tier-3 pack produces meaningfully varied subsets. Rarity weighting has real effect. Catalog doc is honest about what ships vs what's still aspirational.

### Testing

- Buy a Tier-2 pack upgrade in-game. Observe cards granted. Open again on a fresh save; confirm different subset.
- Same for each Tier-3 pack.
- Regression: `starter_pack` still grants 2 starter cards.
- If any template uses a newly-added property/sorter, verify it evaluates correctly at runtime.

### AI Notes

- Don't implement all ~100 catalog entries. MVP target is 14–22 total across both tiers. Triage aggressively.
- If an entry needs a new primitive, drop it. Don't work around the primitive rule.
- Tier 1 is explicitly untouched in this phase.

---

**Status:** Not started
**Line count change:** —
**Deviation from plan:** —

---

## Phase 7 — Fuel-Aware Dispatch (Data + Cards)

**Goal:** Expose fuel economics to the dispatch system as data, then author the cards that use it. Both halves ship together because the cards are the whole reason for the data.

### Tasks

| # | File | Change |
|---|------|--------|
| **Data layer** | | |
| 7.1 | `data/dispatch_properties.lua` | Add `vehicle.fuel_rate` reading `vehicle:getEffectiveFuelRate(game)`. |
| 7.2 | `data/dispatch_properties.lua` | Add `trip.projected_fuel_cost` (requires candidate vehicle in context; returns `path_cost × vehicle.fuel_rate` for the pair). |
| 7.3 | `data/dispatch_properties.lua` | Add `trip.net_profit` = `payout − projected_fuel_cost`. |
| 7.4 | `data/dispatch_sorters.lua` | Add `by_fuel_rate_asc` and `by_net_profit_desc`. |
| 7.5 | Evaluator context | Ensure the evaluator exposes a candidate vehicle to property reads during a Find's scoring phase. One-time context-shape change, not per-property. Cache path-cost-per-(trip,vehicle) pair in evaluator scratch space to avoid repeat A*. |
| 7.6 | Confirm zero new entries in `data/dispatch_blocks.lua`. |
| **Cards** | | |
| 7.7 | `data/rule_templates.lua` | Author fuel-aware cards: |
| | | - **Skip unprofitable trip** — if `trip.projected_fuel_cost > trip.payout × threshold`, skip. Tier 2. |
| | | - **Prefer fuel-efficient vehicle** — Find with `by_fuel_rate_asc`. Tier 2. |
| | | - **Right-size by capacity** — sort ascending-by-capacity among vehicles meeting `cargo_size`. Tier 2. |
| | | - **Net-profit filter** — assign only if `trip.net_profit >= minimum_margin`. Tier 3. |
| | | - **Wait for batch** — if vehicle capacity ≥ N and pending-at-destination < M, skip. Tier 3. |
| 7.8 | `data/rule_packs.lua` | Verify pack tag queries include these cards. Adjust tags if necessary. |

### Expected Outcome

Player can author or receive fuel-aware rules that produce real economic tradeoffs. Using these cards visibly changes assignment behavior.

### Testing

- Unit test: construct a mock evaluator context, read `trip.projected_fuel_cost`, verify correctness.
- Grant "Skip unprofitable trip": verify skip fires on low-margin combos.
- Grant "Prefer fuel-efficient vehicle": with a car + truck both eligible, verify the car (lower fuel_rate) is chosen.
- Regression: rules without fuel awareness behave identically; sort on empty collection doesn't crash.

### AI Notes

- No new block types. No new hats.
- Thresholds in card parameters are placeholders — final tuning in Phase 8.

---

**Status:** Not started
**Line count change:** —
**Deviation from plan:** —

---

## Phase 8 — Onboarding + Economy Tuning

**Goal:** Fresh saves land on a playable screen with a legible first action. Every tunable number gets a real value. The two are bundled because economy tuning can't finalize until onboarding's default-tab and default-state are in their final shape.

### Tasks

| # | File | Change |
|---|------|--------|
| **Onboarding** | | |
| 8.1 | `controllers/UIManager.lua` | Change default active tab so a fresh save lands on a playable tab (Trips, or a new landing surface if introduced). |
| 8.2 | `views/tabs/DispatchTab.lua` | When dispatch is locked: hide the tab entirely OR render as clearly gated, minimal visual weight. Pick one decisively. |
| 8.3 | Tab registration | If hiding, remove from the visible tab bar until unlock. |
| 8.4 | `services/EventService.lua` | On dispatch-unlock: un-hide / re-emphasize the Dispatch tab. |
| 8.5 | (Optional, only if trivial) | First-time hint overlay on Trips explaining the click-vehicle-then-click-trip manual-assign flow. Dismissible. Skip if it adds non-trivial UI code. |
| **Tuning** | | |
| 8.6 | `data/constants.lua` | Tune `INITIAL_MONEY`, `BASE_TRIP_PAYOUT`, `TRIP_GENERATION_MIN_SEC` / `MAX_SEC`, `INITIAL_SPEED_BONUS`, and any other gameplay constants. |
| 8.7 | `data/upgrades.json` | Sweep every `cost` and `cost_multiplier`. Ensure monotonic growth within each tree and proportional cross-tree costs. |
| 8.8 | `data/licenses.lua` | Real prices. City price = the 30+ minute target. Region price significantly larger. |
| 8.9 | `data/client_archetypes.lua` | Real `base_spawn_seconds`, `payout_multiplier`, `market_cost`, `rush_probability`, `rush_bonus_multiplier`, `rush_deadline_seconds` per archetype. |
| 8.10 | `data/vehicles/*.json` | Confirm `speed`, `capacity`, `cost`, `fuel_rate` are tuned to the new economy. |
| 8.11 | `data/rule_packs.lua` pack-grant upgrade costs | Reviewed for cross-tier scaling. |
| 8.12 | Playtest loop | Multiple fresh-save runs. Record time-to-first-City-license, trips-per-minute at each stage, profitability of vehicle choices. Iterate. |
| 8.13 | Sweep for stray magic numbers in service code. Move any gameplay-relevant constant to the data layer. |

### Expected Outcome

- A brand new save presents a clear "what do I do?" answer within seconds.
- Time-to-first-City-license is 30+ minutes on a first playthrough.
- Fuel cost creates real pressure; vehicle choice matters at every tier.
- Each archetype specialization path has a plausible break-even point.
- No `TODO` / placeholder numbers remain.

### Testing

- Delete save. Start new game. Default tab is Trips (or the landing surface). Dispatch tab is hidden or clearly gated.
- Buy the Auto-Dispatcher upgrade. Dispatch tab appears / emphasizes immediately.
- Three full fresh playthroughs to the City license, timed. Report actual times in the Deviation section.
- Grep for magic numbers in `services/*.lua` — should be zero gameplay-relevant ones.

### AI Notes

- Heavy graphical polish is NOT part of this phase. Minimum legibility only.
- Tuning is iterative. Expect multiple revisions; record every non-obvious value change in the Deviation section.

---

**Status:** Not started
**Line count change:** —
**Deviation from plan:** —

---

## End State

| Capability | Delivered |
|------------|-----------|
| Starting city = smallest in ≥2-city region | Phase 1 |
| Upgrades tree audited; per-vehicle-type capacity | Phase 1 |
| Fuel-efficiency upgrades per vehicle | Phase 1 |
| License system (Downtown / City / Region) | Phase 2 |
| Client archetypes with per-archetype trip generation | Phase 3 |
| Per-archetype upgrade trees; market scope-gating | Phase 4 |
| Two-tier deadlines (Regular / Rush) | Phase 5 |
| Tier-2 and Tier-3 card pools populated | Phase 6 |
| Fuel-aware dispatch data + cards | Phase 7 |
| Onboarding default tab fixed; full economy tuned | Phase 8 |

**Explicitly NOT delivered:** Continent / World scopes, ships / planes / trains as playable modes (boats remain dormant), fuel tanks / refueling / fuel stations, new dispatch primitives, heavy graphical polish beyond onboarding legibility, depot analytics feature completion.

---

## Execution Notes

- Phases 1-2 are the **foundation**. Nothing downstream works correctly until they're done. Run sequentially.
- Phases 3-5 are the **clients layer**. 3 must precede 4, and 5 depends on both.
- Phases 6-7 are the **dispatch content layer**. Can overlap each other, but test each tier's packs separately.
- Phase 8 is the **end cap** — onboarding polish plus the full tuning pass. Intentionally last because tuning can't finalize until every system it affects is in place.

Each phase's commit should be reviewed against `docs/mvp-refactor.md` for scope conformance. If a phase would touch code outside its stated files, stop and re-plan.
