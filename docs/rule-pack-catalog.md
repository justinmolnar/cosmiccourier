# Rule Pack Catalog — Prefab & Full-Rule Brainstorm

> Every entry is a potential unlock from a rule pack. Full rules include a hat + body. Prefab
> fragments are smaller pieces (conditions, actions) that slot into existing rules.
>
> **Complexity**: 1–5 stars. How many distinct block types/nesting levels.
> **Usefulness**: 1–5 stars. How much impact on a typical network.
> **Teaches**: What programming concept the player absorbs by seeing this rule.
>
> Rules marked **(FUTURE)** use blocks/properties that don't exist yet (fuel, rail, plane, etc.)
> but should be created alongside the unlock system.

---

## Table of Contents

1. [Starter Rules (Complexity 1)](#1-starter-rules)
2. [Basic Conditions (Complexity 1–2)](#2-basic-conditions)
3. [Assignment Strategies (Complexity 2)](#3-assignment-strategies)
4. [Trip Filtering & Routing (Complexity 2–3)](#4-trip-filtering--routing)
5. [Queue Management (Complexity 2–3)](#5-queue-management)
6. [Economy & Rush Hour (Complexity 2–3)](#6-economy--rush-hour)
7. [Vehicle Management (Complexity 2–3)](#7-vehicle-management)
8. [Fuel Management (Complexity 2–3) (FUTURE)](#8-fuel-management)
9. [Multi-Modal & Routing (Complexity 3)](#9-multi-modal--routing)
10. [Counter & Flag Patterns (Complexity 3)](#10-counter--flag-patterns)
11. [Fleet Scaling (Complexity 3–4)](#11-fleet-scaling)
12. [Broadcast & Coordination (Complexity 3–4)](#12-broadcast--coordination)
13. [Loop Patterns (Complexity 3–4)](#13-loop-patterns)
14. [Advanced Conditionals (Complexity 4)](#14-advanced-conditionals)
15. [Procedures & Reuse (Complexity 4–5)](#15-procedures--reuse)
16. [Visual & Debug (Complexity 1–3)](#16-visual--debug)
17. [Depot Operations (Complexity 2–3)](#17-depot-operations)
18. [Client Management (Complexity 2–3)](#18-client-management)
19. [Exotic & Creative (Complexity 4–5)](#19-exotic--creative)
20. [Fragments — Condition Prefabs](#20-fragments--condition-prefabs)
21. [Fragments — Action Prefabs](#21-fragments--action-prefabs)

---

## 1. Starter Rules

These are the first things a new player should get. Dead simple, immediately useful.

### R001 — Assign Any Vehicle
```
when trip pending
  Find nearest vehicle → assign
```
- **Complexity**: ★ | **Usefulness**: ★★★★★
- **Teaches**: The basic structure — a hat trigger, a find, an assign. This IS the game.
- **Unlocks**: `trigger_trip`, `find_match`, `assign_ctx`, `vehicles` collection, `nearest` sorter

### R002 — Assign Nearest Bike
```
when trip pending
  Find nearest vehicle where type = bike → assign
```
- **Complexity**: ★ | **Usefulness**: ★★★★
- **Teaches**: Filtering inside a Find block. "Oh, I can restrict which vehicles it picks."
- **Unlocks**: `vehicle_type` filter in find, `bike` vehicle enum

### R003 — Cancel Expired Trips
```
when trip pending
  if wait time > 60
    cancel trip
```
- **Complexity**: ★ | **Usefulness**: ★★★
- **Teaches**: if/then conditional + comparison. Trips have a wait time you can check.
- **Unlocks**: `ctrl_if`, `bool_compare`, `rep_get_property` (trip.wait_time), `cancel_trip`

### R004 — Assign Fastest Vehicle
```
when trip pending
  Find fastest vehicle → assign
```
- **Complexity**: ★ | **Usefulness**: ★★★★
- **Teaches**: Sorters — same structure as R001 but with `fastest` instead of `nearest`.
- **Unlocks**: `fastest` sorter

### R005 — Assign Any Truck
```
when trip pending
  Find nearest vehicle where type = truck → assign
```
- **Complexity**: ��� | **Usefulness**: ★★★★
- **Teaches**: Same as R002 but for trucks. Different vehicle, same pattern.
- **Unlocks**: `truck` vehicle enum

### R006 — Skip Low Payouts
```
when trip pending
  if payout < 50
    skip trip
```
- **Complexity**: ★ | **Usefulness**: ★★★
- **Teaches**: Skip as flow control — the trip stays in queue, just isn't handled by this rule.
- **Unlocks**: `skip` action, trip.payout property

### R007 — Prioritize Expensive Trips
```
when trip pending
  if payout > 200
    prioritize trip
```
- **Complexity**: ★ | **Usefulness**: ★★★
- **Teaches**: Queue manipulation — you can reorder what gets processed first.
- **Unlocks**: `prioritize_trip` action

### R008 — Cancel No-Bonus Trips
```
when trip pending
  if bonus = 0
    cancel trip
```
- **Complexity**: ★ | **Usefulness**: ★★
- **Teaches**: Comparison with equals. Bonus as a trip property.
- **Unlocks**: trip.bonus property, `=` operator

### R009 — Assign Most Capacity
```
when trip pending
  Find most capacity vehicle → assign
```
- **Complexity**: ★ | **Usefulness**: ★★★★
- **Teaches**: Another sorter. Capacity matters for multi-cargo trips.
- **Unlocks**: `most_capacity` sorter

### R010 — Assign Least Recently Used
```
when trip pending
  Find least recent vehicle → assign
```
- **Complexity**: ★ | **Usefulness**: ★★★
- **Teaches**: Round-robin fairness — spread work across fleet.
- **Unlocks**: `least_recent` sorter

---

## 2. Basic Conditions

Single-condition rules that teach "check before you act."

### R011 — Only Assign When Idle Vehicles Exist
```
when trip pending
  if any idle bike
    Find nearest bike → assign
```
- **Complexity**: ★★ | **Usefulness**: ★★★★
- **Teaches**: Guarding an assignment with a pre-check. Avoids wasted Find cycles.
- **Unlocks**: `cond_vehicle_idle` condition

### R012 — Hold Trips During Rush Hour
```
when trip pending
  if rush hour
    skip trip
```
- **Complexity**: ��★ | **Usefulness**: ★★
- **Teaches**: Game-state awareness. Rush hour is a thing you can react to.
- **Unlocks**: `cond_rush_hour` condition

### R013 — Only Assign If Queue Is Short
```
when trip pending
  if queue size < 5
    Find nearest vehicle → assign
```
- **Complexity**: ★★ | **Usefulness**: ★★★
- **Teaches**: Queue awareness. If queue is manageable, assign normally.
- **Unlocks**: game.queue_count property

### R014 — Assign Cars to City Trips
```
when trip pending
  if scope is city
    Find nearest car → assign
```
- **Complexity**: ★★ | **Usefulness**: ★★★★��
- **Teaches**: Scope-based routing. Match vehicle type to trip distance.
- **Unlocks**: `cond_scope` condition, `car` vehicle enum

### R015 — Don't Assign Bikes to City Trips
```
when trip pending
  if scope is not district
    if any idle truck
      Find nearest truck → assign
```
- **Complexity**: ★★ | **Usefulness**: ★★★★
- **Teaches**: Negative conditions. Scope filtering for vehicle-trip matching.
- **Unlocks**: `cond_scope_not` condition

### R016 — Emergency Assign (Queue Overflow)
```
while queue at least 8
  // no trip context — this is a poll hat
  sort queue by payout
```
- **Complexity**: ★★ | **Usefulness**: ★★★
- **Teaches**: Poll-based hats fire without a specific trip. Queue thresholds.
- **Unlocks**: `hat_queue_reaches` hat, `sort_queue` action

### R017 — Assign Ships to World Trips
```
when trip pending
  if scope is world
    Find nearest ship → assign
```
- **Complexity**: ���★ | **Usefulness**: ★★★���★
- **Teaches**: Ships for overseas. Scope-vehicle pairing.
- **Unlocks**: `ship` vehicle enum, `world` scope

### R018 — Cancel District Trips When Broke
```
while money below 100
  cancel all (scope = district)
```
- **Complexity**: ★★ | **Usefulness**: ★★
- **Teaches**: Bulk cancel. Money-based emergency response.
- **Unlocks**: `hat_money_below` hat, `cancel_all_scope` action

### R019 — Bonus Guard
```
when trip pending
  if bonus > 50
    Find fastest vehicle → assign
```
- **Complexity**: ★★ | **Usefulness**: ★★★★
- **Teaches**: High-bonus trips deserve fast vehicles to capture the bonus.
- **Unlocks**: trip.bonus comparison

### R020 — Multi-City Trip Handler
```
when trip pending
  if is multi-city
    Find most capacity truck → assign
```
- **Complexity**: ★★ | **Usefulness**: ★★★★
- **Teaches**: Multi-leg trips exist and need bigger vehicles.
- **Unlocks**: `cond_multi_leg` condition

---

## 3. Assignment Strategies

More nuanced assignment logic.

### R021 — Tiered Assignment (Bike → Car → Truck)
```
when trip pending
  if scope is district
    Find nearest bike → assign
  else
    if scope is city
      Find nearest car → assign
    else
      Find nearest truck → assign
```
- **Complexity**: ★★★ | **Usefulness**: ★��★★★
- **Teaches**: Nested if/else. Tiered decision-making. This is the bread-and-butter rule.
- **Unlocks**: `ctrl_if_else`, nested conditions

### R022 — Speed Priority Assignment
```
when trip pending
  if bonus > 100
    Find fastest vehicle → assign
  else
    Find nearest vehicle → assign
```
- **Complexity**: ★★ | **Usefulness**: ★★★★
- **Teaches**: If/else branching based on trip urgency.

### R023 — Capacity-Aware Assignment
```
when trip pending
  if cargo size > 5
    Find most capacity vehicle → assign
  else
    Find nearest vehicle ��� assign
```
- **Complexity**: ★★ | **Usefulness**: ★★���★
- **Teaches**: Matching vehicle capacity to cargo requirements.
- **Unlocks**: trip.cargo_size property

### R024 — Idle Fleet Balancer
```
when trip pending
  if idle count (bike) > idle count (truck)
    Find nearest bike → assign
  else
    Find nearest truck ��� assign
```
- **Complexity**: ★★★ | **Usefulness**: ★★★
- **Teaches**: Comparing two reporters. Fleet balance awareness.
- **Unlocks**: fleet.idle_count with vehicle_type param, reporter-vs-reporter comparison

### R025 — Round Robin by Counter
```
when trip pending
  if counter "assign_toggle" mod 2 = 0
    Find nearest bike → assign
  else
    Find nearest truck → assign
  counter_inc "assign_toggle"
```
- **Complexity**: ★★★ | **Usefulness**: ★★
- **Teaches**: Counters + modulo for alternating behavior.
- **Unlocks**: `counter_inc`, `cond_counter_mod`

### R026 — Cheapest Vehicle First
```
when trip pending
  if scope is district
    Find nearest bike → assign
    // comment: bikes are cheapest fuel
  else
    if any idle car
      Find nearest car → assign
    else
      Find nearest truck → assign
```
- **Complexity**: ★★★ | **Usefulness**: ★★★★
- **Teaches**: Cost-awareness, comments as documentation, fallback chains.
- **Unlocks**: `action_comment`

### R027 — Veteran Vehicle Priority
```
when trip pending
  Find vehicle where trips_completed > 10, sort by fastest → assign
```
- **Complexity**: ★★★ | **Usefulness**: ★★
- **Teaches**: Combining filters with sorters. Vehicle experience as a concept.
- **Unlocks**: vehicle.trips_completed property

### R028 — Reserve Trucks for Big Jobs
```
when trip pending
  if scope is district
    if not (cargo size > 5)
      // don't waste trucks on small district jobs
      Find nearest bike → assign
      stop rule
  Find nearest truck �� assign
```
- **Complexity**: ★★★ | **Usefulness**: ★★★★
- **Teaches**: `bool_not`, `stop_rule` for early exit. Resource reservation.

---

## 4. Trip Filtering & Routing

Rules that decide WHERE trips go, not just who delivers them.

### R029 — Route to Nearest Dock
```
when trip pending
  set leg destination → nearest dock to start
  Find nearest vehicle → assign
```
- **Complexity**: ★★ | **Usefulness**: ★★★★★
- **Teaches**: Destination override. The player can reroute trips to buildings.
- **Unlocks**: `set_leg_destination`, `building.nearest_pos`, `dock` building type

### R030 — Route Intercity to Depot First
```
when trip pending
  if scope is not district
    set leg destination → nearest depot to start
    Find nearest truck → assign
```
- **Complexity**: ★★ | **Usefulness**: ★★★★
- **Teaches**: Hub routing — send to depot for consolidation before long haul.
- **Unlocks**: `depot` building type in building properties

### R031 — Route Overseas to Far Dock
```
when trip deposited at building
  set leg destination → nearest dock to destination
  Find nearest ship → assign from building
```
- **Complexity**: ★★★ | **Usefulness**: ★★★★★
- **Teaches**: Multi-leg chaining. The `trip_deposited` hat enables hub-and-spoke.
- **Unlocks**: `hat_trip_deposited`, `assign_from_building`, `building.nearest_to_dest_pos`

### R032 — Last Mile Delivery
```
when trip deposited at building
  if scope is district
    Find nearest bike → assign from building
  else
    Find nearest car → assign from building
```
- **Complexity**: ★★★ | **Usefulness**: ★★★★
- **Teaches**: Second-leg routing from a transfer point.

### R033 — Cancel Long-Wait District Trips
```
when trip pending
  if scope is district
    if wait time > 30
      cancel trip
```
- **Complexity**: ★★ | **Usefulness**: ★★★
- **Teaches**: Combined conditions. Stale small trips aren't worth it.

### R034 — Deprioritize Low-Value Trips
```
when trip pending
  if payout < 30
    deprioritize trip
```
- **Complexity**: ★ | **Usefulness**: ★★★
- **Teaches**: Queue ordering — push cheap trips to the back.
- **Unlocks**: `deprioritize_trip`

### R035 — Route Continental to Rail **(FUTURE)**
```
when trip pending
  if scope is continent
    set leg destination → nearest rail station to start
    Find nearest truck → assign
```
- **Complexity**: ★★ | **Usefulness**: ★★★★
- **Teaches**: Rail as a transport mode. Continental routing.
- **Unlocks**: `rail_station` building type (FUTURE)

### R036 — Route by Next Transfer Mode
```
when trip pending
  if next_mode = "water"
    set leg destination → nearest dock to start
    Find nearest truck → assign
```
- **Complexity**: ★★★ | **Usefulness**: ★★★★
- **Teaches**: Reading trip.next_mode to know what transfer is coming.
- **Unlocks**: trip.next_mode property

### R037 — Skip Already-Routed Trips
```
when trip pending
  if leg count > 1
    skip trip
    // comment: multi-leg trip already has routing from another rule
```
- **Complexity**: ★★ | **Usefulness**: ★★★
- **Teaches**: Leg count as a signal that another rule already handled routing.

### R038 — Prioritize Regional Trips
```
when trip pending
  if scope is region
    prioritize trip
    add bonus 25
    Find fastest truck → assign
```
- **Complexity**: ★★ | **Usefulness**: ★★★★
- **Teaches**: Combining prioritize + bonus + assignment in one rule. Stacking actions.
- **Unlocks**: `add_bonus`

---

## 5. Queue Management

Rules focused on the pending queue itself.

### R039 — Auto-Sort by Payout
```
every 5 seconds
  sort queue by payout
```
- **Complexity**: ★ | **Usefulness**: ★★★
- **Teaches**: Periodic polling hats. Queue sorting as maintenance.
- **Unlocks**: `hat_every_n_seconds`

### R040 — Emergency Queue Flush
```
while queue at least 10
  cancel all (waited > 45)
```
- **Complexity**: ★★ | **Usefulness**: ★★★
- **Teaches**: Bulk cancel with a time threshold. Queue overflow handling.
- **Unlocks**: `cancel_all_wait`

### R041 — Sort by Wait Time
```
every 10 seconds
  sort queue by wait
```
- **Complexity**: ★ | **Usefulness**: ★★���
- **Teaches**: Fairness — longest-waiting trips get served first.

### R042 — Cancel All District When Queue Full
```
while queue at least 8
  cancel all (scope = district)
```
- **Complexity**: ★★ | **Usefulness**: ★★
- **Teaches**: Triage — sacrifice small jobs to make room for big ones.

### R043 — Pause Trip Gen When Overwhelmed
```
while queue at least 10
  pause trip gen
```
- **Complexity**: ★★ | **Usefulness**: ★★★
- **Teaches**: Trip generation control. Breathing room.
- **Unlocks**: `pause_trip_gen`

### R044 — Resume Trip Gen When Queue Clears
```
while queue empty
  resume trip gen
```
- **Complexity**: ★★ | **Usefulness**: ★★★
- **Teaches**: Pair with R043. Resume when ready.
- **Unlocks**: `hat_queue_empties`, `resume_trip_gen`

### R045 — Sort by Cargo Size
```
every 10 seconds
  sort queue by cargo
```
- **Complexity**: ★ | **Usefulness**: ★★
- **Teaches**: Cargo-based prioritization.

### R046 — Sort by Scope (Local First)
```
every 10 seconds
  sort queue by scope
```
- **Complexity**: ★ | **Usefulness**: ★★★
- **Teaches**: Handle local trips first, they're cheaper and faster.

---

## 6. Economy & Rush Hour

Money-aware and event-reactive rules.

### R047 — Rush Hour Speed Boost
```
when rush hour starts
  for each vehicle (any)
    set speed mult 1.5
```
- **Complexity**: ★★★ | **Usefulness**: ★★★★
- **Teaches**: Event-driven rules, for-each loops, vehicle modification.
- **Unlocks**: `hat_rush_hour_start`, `ctrl_for_each_vehicle`, `set_speed_mult`

### R048 — Reset Speed After Rush Hour
```
when rush hour ends
  for each vehicle (any)
    set speed mult 1.0
```
- **Complexity**: ★★��� | **Usefulness**: ★★��★
- **Teaches**: Cleanup after events. Pair with R047.
- **Unlocks**: `hat_rush_hour_end`

### R049 — Save Money When Broke
```
while money below 200
  if scope is not district
    skip trip
    // comment: only run cheap local trips when broke
```
- **Complexity**: ★★ | **Usefulness**: ★★★
- **Teaches**: Economic survival mode.

### R050 — Trigger Rush Hour When Rich
```
while money above 5000
  trigger rush hour 30
```
- **Complexity**: ★★ | **Usefulness**: ★★★
- **Teaches**: Spending money to make more money. Investment.
- **Unlocks**: `hat_money_above`, `trigger_rush_hour`

### R051 — Bonus Multiplier During Rush
```
when trip pending
  if rush hour
    add bonus 50
    Find fastest vehicle → assign
```
- **Complexity**: ★★ | **Usefulness**: ★★★★
- **Teaches**: Stacking bonuses during events for max profit.

### R052 — Shutdown When Bankrupt
```
while money below 0
  pause trip gen
  send vehicles to depot
  close depot
```
- **Complexity**: ★★ | **Usefulness**: ★★
- **Teaches**: Emergency shutdown. Multiple actions in sequence.
- **Unlocks**: `close_depot`, `send_vehicles_to_depot`

### R053 — Recovery Mode
```
while money below 50
  cancel all (scope = world)
  cancel all (scope = continent)
  // comment: cut expensive long-haul, keep local income flowing
```
- **Complexity**: ★★ | **Usefulness**: ★★★
- **Teaches**: Triage by cutting expensive operations first.

### R054 — Payout Boost for Long Hauls
```
when trip pending
  if scope is continent
    set payout (Get trip.payout × 2)
```
- **Complexity**: ★★★ | **Usefulness**: ★★★
- **Teaches**: Reporter math — multiplying a property. Dynamic payout adjustment.
- **Unlocks**: `rep_mul`, `set_payout` with reporter value

### R055 — Trip Gen Rate by Queue
```
every 5 seconds
  if queue size > 5
    set trip gen rate 0.5
  else
    set trip gen rate 1.5
```
- **Complexity**: ★★★ | **Usefulness**: ★★★
- **Teaches**: Dynamic rate adjustment. Feedback loop.
- **Unlocks**: `set_trip_gen_rate`

---

## 7. Vehicle Management

Vehicle lifecycle and maintenance rules.

### R056 — Send Idle Vehicles Home
```
when vehicle idle for 30 seconds
  send to depot
```
- **Complexity**: ★ | **Usefulness**: ★★★
- **Teaches**: Vehicle idle detection. Cleanup.
- **Unlocks**: `hat_vehicle_idle_for`, `send_to_depot`

### R057 — Welcome New Vehicle
```
when vehicle hired (any)
  flash vehicle 2
  show speech bubble "Ready!" 3
```
- **Complexity**: ★★ | **Usefulness**: ★
- **Teaches**: Vehicle lifecycle events. Visual feedback.
- **Unlocks**: `hat_vehicle_hired`, `flash_vehicle`, `show_speech_bubble`

### R058 — Retirement Program
```
when vehicle completes trip
  if vehicle trips done > 100
    fire vehicle
    // comment: old vehicles cost more in maintenance
```
- **Complexity**: ★★ | **Usefulness**: ★★
- **Teaches**: Vehicle retirement based on usage. Trips_completed as a metric.
- **Unlocks**: `hat_vehicle_trip_complete`, `fire_vehicle`

### R059 — Celebrate Trip Completion
```
when vehicle completes trip
  flash vehicle 1
  counter_inc "total_deliveries"
```
- **Complexity**: ★★ | **Usefulness**: ���★
- **Teaches**: Event-driven counters. Tracking stats.

### R060 — Color Code by Type
```
when vehicle hired (bike)
  set vehicle color 0.3 0.9 0.3
```
- **Complexity**: ★ | **Usefulness**: ★
- **Teaches**: Visual customization. Vehicle events.
- **Unlocks**: `set_vehicle_color`

### R061 — Color Code Trucks
```
when vehicle hired (truck)
  set vehicle color 1.0 0.5 0.1
```
- **Complexity**: ★ | **Usefulness**: ★
- **Teaches**: Same pattern, different vehicle. Player sees the reuse.

### R062 — Label All Vehicles on Hire
```
when vehicle hired (any)
  show vehicle label
```
- **Complexity**: ★ | **Usefulness**: ★
- **Teaches**: Vehicle display options.
- **Unlocks**: `show_vehicle_label`

### R063 — Dismiss Slow Bikes
```
when vehicle becomes idle
  if this vehicle is type bike
    if vehicle speed < 60
      fire vehicle
```
- **Complexity**: ★★★ | **Usefulness**: ★★
- **Teaches**: Per-vehicle conditions in event context. Quality control.
- **Unlocks**: `cond_this_vehicle_type`, vehicle.speed in event context

### R064 — Track Deliveries Per Vehicle Type
```
when vehicle completes trip (bike)
  counter_inc "bike_deliveries"

when vehicle completes trip (truck)
  counter_inc "truck_deliveries"
```
- **Complexity**: ★★ | **Usefulness**: ★★
- **Teaches**: Multiple rules working together. Per-type counters.

### R065 — Auto-Dismiss on Return
```
when vehicle returns to depot
  if this vehicle is type bike
    if fleet count (bike) > 5
      fire vehicle
      // comment: keep fleet lean, max 5 bikes
```
- **Complexity**: ★★★ | **Usefulness**: ★★
- **Teaches**: Fleet caps. Conditional dismissal.
- **Unlocks**: `hat_vehicle_returns_depot`, fleet.count property

---

## 8. Fuel Management (FUTURE)

These require new blocks: `vehicle.fuel`, `vehicle.fuel_pct`, `vehicle.fuel_rate`, `refuel` action, `fuel_station` building type.

### R066 — Low Fuel Return **(FUTURE)**
```
when vehicle completes trip
  if vehicle fuel < 20%
    send to depot
    // comment: refuel before next assignment
```
- **Complexity**: ★★ | **Usefulness**: ★★★★★
- **Teaches**: Fuel awareness. Preventive maintenance.
- **Unlocks**: `vehicle.fuel_pct` property (FUTURE)

### R067 — Fuel-Efficient Assignment **(FUTURE)**
```
when trip pending
  if scope is district
    Find nearest bike → assign
    // comment: bikes use 0.01 fuel, trucks use 0.10
```
- **Complexity**: ★★ | **Usefulness**: ★★★★
- **Teaches**: Fuel cost differences between vehicles. Economic routing.

### R068 — Emergency Fuel Save **(FUTURE)**
```
while money below 500
  for each vehicle (truck)
    if vehicle fuel < 30%
      send to depot
      // comment: stop burning fuel we can't afford
```
- **Complexity**: ★★★ | **Usefulness**: ★★★★
- **Teaches**: Combining money awareness with fuel management.

### R069 — Only Assign If Enough Fuel **(FUTURE)**
```
when trip pending
  Find nearest vehicle where fuel > 25% → assign
```
- **Complexity**: ★★ | **Usefulness**: ★★★★★
- **Teaches**: Fuel as a find filter. Don't send empty vehicles.
- **Unlocks**: fuel filter in find_match condition (FUTURE)

### R070 — Refuel at Depot **(FUTURE)**
```
when vehicle returns to depot
  refuel vehicle
```
- **Complexity**: ★ | **Usefulness**: ★★★★★
- **Teaches**: Depot as refueling station. Simple but critical.
- **Unlocks**: `refuel` action (FUTURE)

### R071 — Fuel Warning Alert **(FUTURE)**
```
when vehicle completes trip
  if vehicle fuel < 15%
    show alert "Low fuel!" red
    flash vehicle 2
    send to depot
```
- **Complexity**: ★★★ | **Usefulness**: ★★★★
- **Teaches**: Multi-action response. Visual + functional combined.

### R072 — Fuel-Based Speed Reduction **(FUTURE)**
```
when vehicle picks up cargo
  if vehicle fuel < 50%
    set speed mult 0.8
    // comment: heavy vehicle + low fuel = slower
```
- **Complexity**: ★★★ | **Usefulness**: ★★★
- **Teaches**: Dynamic speed adjustment based on state.

### R073 — Fuel Cost Logger **(FUTURE)**
```
when vehicle completes trip
  add to log (join "Fuel cost: $" (Get vehicle.last_fuel_cost))
```
- **Complexity**: ★★★ | **Usefulness**: ★★
- **Teaches**: String joining with reporters. Logging for awareness.
- **Unlocks**: `rep_join`, `add_to_log` with reporter

### R074 — Don't Send Ships Empty **(FUTURE)**
```
when trip pending
  if scope is world
    Find nearest ship where fuel > 40% → assign
    // comment: ships burn 0.15 fuel rate, don't strand them
```
- **Complexity**: ★★★ | **Usefulness**: ★★★★
- **Teaches**: High fuel cost vehicles need extra planning.

### R075 — Fuel Budget Limit **(FUTURE)**
```
when trip pending
  if Get game.money < Get trip.estimated_fuel_cost × 3
    skip trip
    // comment: need 3x fuel cost as safety margin
```
- **Complexity**: ★★★★ | **Usefulness**: ★★★★
- **Teaches**: Reporter math for economic decisions. Safety margins.
- **Unlocks**: trip.estimated_fuel_cost property (FUTURE), `rep_mul`

---

## 9. Multi-Modal & Routing

Hub-and-spoke, transfers, multi-leg journeys.

### R076 — Full Hub-and-Spoke (Truck → Dock → Ship)
```
// Rule 1: Route intercity trips to nearest dock
when trip pending
  if scope is not district
    set leg destination → nearest dock to start
    Find nearest truck → assign

// Rule 2: Ship from dock to far dock
when trip deposited at building
  set leg destination → nearest dock to destination
  Find nearest ship → assign from building
```
- **Complexity**: ★★★ | **Usefulness**: ★★★★★
- **Teaches**: Two-rule coordination. The backbone of logistics.
- **Name suggestion**: "Overseas Shipping Route" (comes as a 2-rule pack)

### R077 — Truck-to-Rail-to-Truck **(FUTURE)**
```
// Rule 1: Route continental to rail station
when trip pending
  if scope is continent
    set leg destination → nearest rail station
    Find nearest truck → assign

// Rule 2: Rail picks up from station
when trip deposited at building
  if building type = rail_station
    Find nearest train → assign from building
```
- **Complexity**: ★★★ | **Usefulness**: ★★★���★
- **Teaches**: Three-mode transport chain.

### R078 — Local Last-Mile
```
when trip deposited at building
  if scope is district
    Find nearest bike → assign from building
```
- **Complexity**: ★★ | **Usefulness**: ★★★★
- **Teaches**: Final-mile delivery after a transfer.

### R079 — Air Express **(FUTURE)**
```
when trip pending
  if scope is continent
    if bonus > 200
      set leg destination → nearest airport
      Find nearest truck → assign
      // comment: rush continental trips by air
```
- **Complexity**: ★★★ | **Usefulness**: ★★★★
- **Teaches**: Premium routing for high-value trips.

### R080 — Transfer Counter
```
when trip deposited at building
  counter_inc "transfers_today"
  assign from building using nearest vehicle
```
- **Complexity**: ★★ | **Usefulness**: ★★
- **Teaches**: Tracking transfers with counters.

### R081 — Smart Dock Routing (Closest to Destination)
```
when trip pending
  if scope is world
    set leg destination → nearest dock to DESTINATION
    // comment: route to dock closest to where we're going, not where we are
    Find nearest truck → assign
```
- **Complexity**: ★★★ | **Usefulness**: ★★★★
- **Teaches**: `nearest_to_dest_pos` vs `nearest_pos`. Strategic routing.

---

## 10. Counter & Flag Patterns

Rules that use variables for state tracking.

### R082 — Trip Counter
```
when vehicle completes trip
  counter_inc "total_trips"
```
- **Complexity**: ★ | **Usefulness**: ★★
- **Teaches**: Basic counter usage. Tracking game stats.
- **Unlocks**: `counter_inc`

### R083 — Revenue Tracker
```
when vehicle completes trip
  counter_inc "revenue" by (Get trip.payout)
```
- **Complexity**: ★★ | **Usefulness**: ★★
- **Teaches**: Counter increment by a reporter value, not just 1.
- **Unlocks**: `counter_inc` with reporter amount

### R084 — Milestone Alert
```
while counter "total_trips" at least 100
  if flag "milestone_100" clear
    show alert "100 trips completed!" green
    set flag "milestone_100"
```
- **Complexity**: ★★★ | **Usefulness**: ★★
- **Teaches**: Flags as one-time gates. Fire-once pattern.
- **Unlocks**: `hat_counter_reaches`, `set_flag`, `cond_flag_clear`

### R085 — Rush Hour Counter
```
when rush hour starts
  counter_inc "rush_hours_survived"

when rush hour ends
  show alert (join "Rush hours: " (Var "rush_hours_survived")) blue
```
- **Complexity**: ★★★ | **Usefulness**: ★
- **Teaches**: Counter + string join for dynamic messages.

### R086 — Night Mode Toggle
```
when hotkey pressed "N"
  toggle flag "night_mode"

when trip pending
  if flag "night_mode" set
    skip trip
    // comment: no new assignments during "night"
```
- **Complexity**: ★★★ | **Usefulness**: ★★
- **Teaches**: Hotkeys + flags for player-controlled modes.
- **Unlocks**: `hat_hotkey`, `toggle_flag`

### R087 — Batch Counter (Assign Every 5th)
```
when trip pending
  counter_inc "batch"
  if counter "batch" mod 5 = 0
    sort queue by payout
    // comment: every 5th trip, re-sort the queue
```
- **Complexity**: ★★★ | **Usefulness**: ★★
- **Teaches**: Modulo for periodic behavior within trip events.

### R088 — Flag-Based Strategy Switch
```
when hotkey pressed "1"
  set flag "aggressive_mode"
  clear flag "economy_mode"

when hotkey pressed "2"
  clear flag "aggressive_mode"
  set flag "economy_mode"

when trip pending
  if flag "aggressive_mode" set
    Find fastest vehicle → assign
  else
    if flag "economy_mode" set
      Find nearest bike → assign
```
- **Complexity**: ★★★★ | **Usefulness**: ★★★
- **Teaches**: Multi-rule flag coordination. Player-controlled strategy switching.

### R089 — Counter Reset Every 100 Trips
```
when vehicle completes trip
  counter_inc "cycle"
  if counter "cycle" mod 100 = 0
    counter_reset "revenue_this_cycle"
    show alert "New cycle started!" blue
```
- **Complexity**: ★★★ | **Usefulness**: ★
- **Teaches**: Periodic resets. Cycle-based tracking.

### R090 — Swap Counter Values
```
when hotkey pressed "S"
  swap counters "primary_target" "backup_target"
  // comment: quick swap between two tracking goals
```
- **Complexity**: ★★ | **Usefulness**: ★
- **Teaches**: Counter swapping exists.
- **Unlocks**: `swap_counters`

---

## 11. Fleet Scaling

Rules that adapt behavior based on fleet size/utilization.

### R091 — High Utilization Warning
```
every 10 seconds
  if fleet util % > 90
    show alert "Fleet at capacity!" red
```
- **Complexity**: ★★ | **Usefulness**: ★★
- **Teaches**: Fleet utilization as a metric. Awareness.
- **Unlocks**: fleet.utilization property

### R092 — Scale Trip Gen to Fleet
```
every 10 seconds
  if fleet util % > 80
    set trip gen rate 0.5
  else
    if fleet util % < 30
      set trip gen rate 2.0
    else
      set trip gen rate 1.0
```
- **Complexity**: ★★★ | **Usefulness**: ★★★��
- **Teaches**: Dynamic scaling. Matching supply with demand.

### R093 — Skip When All Busy
```
when trip pending
  if no idle (any)
    skip trip
    // comment: don't waste eval cycles when nobody's free
```
- **Complexity**: ★★ | **Usefulness**: ★★★★
- **Teaches**: Early exit optimization. `cond_vehicle_none`.
- **Unlocks**: `cond_vehicle_none`

### R094 — Emergency Recall
```
while all busy (truck)
  // poll: while no trucks available
  show alert "All trucks busy!" red
```
- **Complexity**: ★★ | **Usefulness**: ★★
- **Teaches**: Poll-based fleet awareness.
- **Unlocks**: `hat_all_busy`

### R095 — Idle Fleet Alert
```
while all idle (any)
  show alert "All vehicles idle — need trips!" blue
```
- **Complexity**: ★★ | **Usefulness**: ★
- **Teaches**: Opposite of R094. Fleet sitting idle = money being wasted.
- **Unlocks**: `hat_all_idle`

### R096 �� Fleet Count Guard
```
when trip pending
  if scope is world
    if fleet count (ship) < 1
      skip trip
      // comment: can't do overseas without ships
```
- **Complexity**: ★★ | **Usefulness**: ★★★★
- **Teaches**: Fleet composition checks before assignment.

---

## 12. Broadcast & Coordination

Rules that talk to each other.

### R097 — Broadcast Rush Alert
```
when rush hour starts
  broadcast "rush_started"

when broadcast received "rush_started"
  sort queue by payout
  // comment: immediately re-sort when rush starts
```
- **Complexity**: ★★★ | **Usefulness**: ★★★
- **Teaches**: Inter-rule messaging. Event broadcasting.
- **Unlocks**: `broadcast_message`, `hat_broadcast_received`

### R098 — Broadcast Queue Emergency
```
while queue at least 10
  broadcast "queue_emergency"

when broadcast received "queue_emergency"
  cancel all (waited > 30)
```
- **Complexity**: ★★★ | **Usefulness**: ★★★
- **Teaches**: Broadcast as a coordination mechanism between poll and action.

### R099 — Broadcast Fuel Emergency **(FUTURE)**
```
when vehicle completes trip
  if vehicle fuel < 10%
    broadcast "fuel_emergency"

when broadcast received "fuel_emergency"
  pause trip gen
  // comment: stop creating trips until vehicles refuel
```
- **Complexity**: ★★★ | **Usefulness**: ★★★
- **Teaches**: Cross-concern coordination via broadcast.

### R100 — Broadcast Shift Change
```
when hotkey pressed "X"
  broadcast "shift_change"

when broadcast received "shift_change"
  for each vehicle (any)
    send to depot
```
- **Complexity**: ★★★ | **Usefulness**: ★★
- **Teaches**: Player-triggered broadcasts affecting the whole fleet.

---

## 13. Loop Patterns

Rules using repeat, for-each, and iteration.

### R101 — Flash All Idle Vehicles
```
every 10 seconds
  for each vehicle (any)
    if this vehicle is idle
      flash vehicle 1
```
- **Complexity**: ★★★ | **Usefulness**: ★
- **Teaches**: For-each + per-vehicle condition inside a loop.

### R102 — Speed Boost All Bikes
```
when rush hour starts
  for each vehicle (bike)
    set speed mult 1.5
    show speech bubble "RUSH!" 2
```
- **Complexity**: ★★★ | **Usefulness**: ★★★
- **Teaches**: Bulk vehicle modification with for-each.

### R103 — Count Idle by Type
```
every 5 seconds
  counter_set "idle_bikes" 0
  for each vehicle (bike)
    if this vehicle is idle
      counter_inc "idle_bikes"
```
- **Complexity**: ★★★ | **Usefulness**: ★★
- **Teaches**: Manual counting via loop. (The player later realizes fleet.idle_count does this.)

### R104 — Cancel Worst Trips in Queue
```
every 10 seconds
  if queue size > 7
    for each pending trip
      if payout < 20
        cancel trip
```
- **Complexity**: ★★★ | **Usefulness**: ★★★
- **Teaches**: For-each-trip loop with inner conditions.
- **Unlocks**: `ctrl_for_each_trip`

### R105 — Batch Assign Top 3
```
when trip pending
  repeat 3
    Find nearest vehicle → assign
```
- **Complexity**: ★★ | **Usefulness**: ★★★
- **Teaches**: Repeat N for burst assignment.
- **Unlocks**: `ctrl_repeat_n`

### R106 — Repeat Until Queue Empty
```
every 5 seconds
  repeat until (queue size = 0)
    // inner logic would need trip context...
    // this teaches the concept even if impractical alone
    sort queue by payout
    break
```
- **Complexity**: ★★★ | **Usefulness**: ★
- **Teaches**: Repeat-until exists as a concept. Shows `break`.
- **Unlocks**: `ctrl_repeat_until`, `action_break`

### R107 — Label All Vehicles With Trip Count
```
every 30 seconds
  for each vehicle (any)
    show speech bubble (join "Trips: " (Get vehicle.trips_completed)) 5
```
- **Complexity**: ★★★★ | **Usefulness**: ★
- **Teaches**: Reporter inside a string join inside a loop. Complex nesting.

### R108 — Recolor Fleet by Utilization
```
every 10 seconds
  for each vehicle (any)
    if this vehicle is idle
      set vehicle color 0.3 0.9 0.3
    else
      set vehicle color 0.9 0.3 0.3
```
- **Complexity**: ★★★ | **Usefulness**: ★★
- **Teaches**: Visual state indication via loops.

---

## 14. Advanced Conditionals

Complex boolean logic, nested conditions.

### R109 — AND: High Payout + Low Wait
```
when trip pending
  if (payout > 200) AND (wait time < 10)
    Find fastest vehicle → assign
    // comment: fresh lucrative trips get the fast lane
```
- **Complexity**: ★★★ | **Usefulness**: ★★★★
- **Teaches**: Boolean AND. Two conditions must both be true.
- **Unlocks**: `bool_and`

### R110 — OR: Rush Hour OR High Bonus
```
when trip pending
  if (rush hour) OR (bonus > 100)
    Find fastest vehicle → assign
  else
    Find nearest vehicle → assign
```
- **Complexity**: ★★★ | **Usefulness**: ★★���★
- **Teaches**: Boolean OR. Either condition triggers the fast path.
- **Unlocks**: `bool_or`

### R111 — NOT: Skip Non-Urgent
```
when trip pending
  if NOT (bonus > 50)
    deprioritize trip
```
- **Complexity**: ★★ | **Usefulness**: ★★★
- **Teaches**: Boolean NOT as inversion.
- **Unlocks**: `bool_not`

### R112 — Complex: (Scope = City AND Payout > 100) OR Rush Hour
```
when trip pending
  if ((scope is city) AND (payout > 100)) OR (rush hour)
    Find fastest car → assign
```
- **Complexity**: ★★★�� | **Usefulness**: ★★★★
- **Teaches**: Nested boolean expressions. Combining AND/OR.

### R113 — Triple AND: Idle + Scope + Payout
```
when trip pending
  if (any idle truck) AND (scope is not district) AND (payout > 75)
    Find nearest truck → assign
```
- **Complexity**: ★★★★ | **Usefulness**: ★★★★
- **Teaches**: Chained AND conditions. All three must pass.

### R114 — Random Chance Assignment
```
when trip pending
  if random chance 20%
    add bonus 100
    // comment: 20% chance for a random payout boost
  Find nearest vehicle → assign
```
- **Complexity**: ★★ | **Usefulness**: ★★
- **Teaches**: Randomness in rules. Gambling mechanic.
- **Unlocks**: `cond_random_chance`

### R115 — Conditional Payout Scaling
```
when trip pending
  if scope is district
    set payout (Get trip.payout)
  else if scope is city
    set payout (Get trip.payout × 2)
  else
    set payout (Get trip.payout × 3)
```
- **Complexity**: ★★★★ | **Usefulness**: ★★★★
- **Teaches**: Nested if/else chains. Dynamic payout based on scope.

---

## 15. Procedures & Reuse

Custom blocks, define/call patterns.

### R116 — Define: Standard Assignment
```
define "standard_assign"
  Find nearest vehicle → assign
```
Then used in other rules:
```
when trip pending
  call "standard_assign"
```
- **Complexity**: ★★★ | **Usefulness**: ★★★★
- **Teaches**: Procedures/functions. Define once, call many times.
- **Unlocks**: `hat_define`, `action_call`

### R117 — Define: Rush Protocol
```
define "rush_protocol"
  sort queue by payout
  for each vehicle (any)
    set speed mult 1.3
  show alert "Rush protocol active!" red
```
- **Complexity**: ★★★★ | **Usefulness**: ★★★
- **Teaches**: Multi-action procedures. Bundling complex behavior.

### R118 — Define: Economy Mode
```
define "economy_mode"
  cancel all (scope = world)
  set trip gen rate 0.5
  for each vehicle (truck)
    send to depot
```
- **Complexity**: ★★★★ | **Usefulness**: ★★★
- **Teaches**: Procedures as strategy presets.

### R119 — Hotkey-Triggered Procedures
```
when hotkey pressed "1"
  call "rush_protocol"

when hotkey pressed "2"
  call "economy_mode"
```
- **Complexity**: ★★★ | **Usefulness**: ��★★
- **Teaches**: Hotkeys calling procedures. Player macros.

### R120 — Define: Log Status
```
define "log_status"
  add to log (join "Money: $" (Get game.money))
  add to log (join "Queue: " (Get game.queue_count))
  add to log (join "Idle: " (Get fleet.idle_count))
```
- **Complexity**: ★★★★ | **Usefulness**: ★★
- **Teaches**: String building in procedures. Debug tooling.

---

## 16. Visual & Debug

Cosmetic, logging, and feedback rules.

### R121 — Log Every Assignment
```
when vehicle picks up cargo
  add to log (join "Assigned: " (Get vehicle.type))
```
- **Complexity**: ★★ | **Usefulness**: ��★
- **Teaches**: Logging. String join with reporters.
- **Unlocks**: `hat_vehicle_pickup`, `add_to_log`, `rep_join`

### R122 — Pan to Busy Vehicle
```
when vehicle picks up cargo
  zoom to vehicle
```
- **Complexity**: ★ | **Usefulness**: ★
- **Teaches**: Camera control from rules.
- **Unlocks**: `zoom_to_vehicle`

### R123 — Alert on Trip Cancel
```
when trip pending
  if wait time > 60
    show alert "Trip timed out!" red
    cancel trip
```
- **Complexity**: ★★ | **Usefulness**: ★★★
- **Teaches**: User feedback before destructive actions.

### R124 — Sound on Rush Hour
```
when rush hour starts
  play sound "alert"
  shake screen 0.5 8
```
- **Complexity**: ★★ | **Usefulness**: ★
- **Teaches**: Sound effects and screen shake from rules.
- **Unlocks**: `play_sound`, `shake_screen`

### R125 — Benchmark Rule Performance
```
when trip pending
  benchmark
  // (all your normal logic here)
  Find nearest vehicle → assign
  benchmark
```
- **Complexity**: ★★ | **Usefulness**: ★
- **Teaches**: Performance measurement exists.
- **Unlocks**: `benchmark`

### R126 — Comment-Heavy Teaching Rule
```
when trip pending
  // comment: Step 1 — check if we can handle this trip
  if any idle (any)
    // comment: Step 2 — pick the best vehicle
    Find nearest vehicle → assign
    // comment: Step 3 — done! Vehicle is on its way
  else
    // comment: No vehicles available, skip for now
    skip trip
```
- **Complexity**: ★★ | **Usefulness**: ★★★★
- **Teaches**: Comments as documentation. Self-documenting rules.

---

## 17. Depot Operations

### R127 — Open Depot When Idle Vehicles Exist
```
every 5 seconds
  if fleet idle count (any) > 0
    open depot
  else
    close depot
```
- **Complexity**: ★★ | **Usefulness**: ★★★
- **Teaches**: Depot open/close as a control mechanism.
- **Unlocks**: `open_depot`

### R128 — Rename Depot Based on Status
```
every 10 seconds
  if fleet util % > 80
    rename depot "HQ (BUSY)"
  else
    rename depot "HQ (Ready)"
```
- **Complexity**: ★★★ | **Usefulness**: ★
- **Teaches**: Dynamic depot naming. Fun flavor.
- **Unlocks**: `rename_depot`

### R129 — Depot Vehicle Cap
```
when vehicle hired (any)
  if depot vehicle count > 10
    fire vehicle
    show alert "Depot full! Vehicle dismissed." red
```
- **Complexity**: ★★ | **Usefulness**: ★★
- **Teaches**: Depot capacity management.

### R130 — Recall Fleet to Depot
```
when hotkey pressed "R"
  send vehicles to depot
  show alert "All vehicles recalled!" blue
```
- **Complexity**: ★★ | **Usefulness**: ★★★
- **Teaches**: Emergency recall hotkey.

---

## 18. Client Management

### R131 — Pause Clients When Overwhelmed
```
while queue at least 8
  pause all clients
```
- **Complexity**: ★★ | **Usefulness**: ★★★
- **Teaches**: Client control. Throttling demand.
- **Unlocks**: `pause_all_clients`

### R132 — Resume Clients When Ready
```
while queue empty
  resume all clients
```
- **Complexity**: ★★ | **Usefulness**: ★★★
- **Teaches**: Pair with R131. Supply/demand balance.
- **Unlocks**: `resume_all_clients`

### R133 — Boost Client Frequency When Idle
```
while all idle (any)
  set client freq 2.0
  // comment: nothing to do? make clients generate faster
```
- **Complexity**: ★★ | **Usefulness**: ★��★
- **Teaches**: Dynamic client rate adjustment.
- **Unlocks**: `set_client_freq`

### R134 — Client Count Alert
```
every 30 seconds
  if client count > 5
    show alert (join "Active clients: " (Get client.active_count)) blue
```
- **Complexity**: ★★★ | **Usefulness**: ★
- **Teaches**: Client awareness. Reporter in alert.

---

## 19. Exotic & Creative

Unusual combinations, advanced patterns, edge cases.

### R135 — Gambling Rule
```
when trip pending
  if random chance 10%
    set payout (Get trip.payout × 5)
    show alert "JACKPOT TRIP!" green
    shake screen 0.3 5
  Find nearest vehicle → assign
```
- **Complexity**: ★★★ | **Usefulness**: ★★
- **Teaches**: Randomness + reporter math + visual flair. Fun.

### R136 — Escalating Bonus for Waited Trips
```
when trip pending
  if wait time > 30
    add bonus (Get trip.wait_time × 2)
    // comment: the longer it waits, the more bonus it's worth
```
- **Complexity**: ★★★ | **Usefulness**: ★★★★
- **Teaches**: Reporter math for dynamic values. Wait time as a multiplier.

### R137 — Speed Penalty for Overloaded Fleet
```
every 10 seconds
  if fleet util % > 90
    for each vehicle (any)
      set speed mult 0.8
      // comment: overworked fleet goes slower
  else
    for each vehicle (any)
      set speed mult 1.0
```
- **Complexity**: ★★★★ | **Usefulness**: ★★
- **Teaches**: Fleet-wide status effects from utilization.

### R138 — Dynamic Naming
```
when vehicle completes trip
  set rule name (join "Trips handled: " (Var "total_trips"))
```
- **Complexity**: ★★★ | **Usefulness**: ★
- **Teaches**: Dynamic rule names. Rules can modify themselves.
- **Unlocks**: `set_rule_name` with reporter

### R139 — Throttle: Max 3 Assignments Per Cycle
```
when trip pending
  if Var "cycle_assigns" >= 3
    skip trip
  Find nearest vehicle → assign
  counter_inc "cycle_assigns"

every 5 seconds
  counter_set "cycle_assigns" 0
```
- **Complexity**: ★★★★ | **Usefulness**: ★★★
- **Teaches**: Rate limiting with counters. Reset cycles.

### R140 — Weather Toggle (Player Imagined) **(FUTURE)**
```
when hotkey pressed "W"
  toggle flag "bad_weather"

when trip pending
  if flag "bad_weather" set
    if scope is not district
      skip trip
      // comment: no long-haul in bad weather
    // bikes go slower in rain
    for each vehicle (bike)
      set speed mult 0.6
```
- **Complexity**: ★★★★ | **Usefulness**: ★★★
- **Teaches**: Player-created game systems via flags. Roleplay + function.

### R141 — Priority Cascade
```
when trip pending
  if scope is world
    prioritize trip
    stop rule
  if scope is continent
    prioritize trip
    stop rule
  if scope is region
    // normal priority
    stop rule
  // district/city — deprioritize
  deprioritize trip
```
- **Complexity**: ★★★ | **Usefulness**: ★★★★
- **Teaches**: `stop_rule` for early exit. Cascade/waterfall pattern.

### R142 — Counter-Based Fleet Expansion Trigger
```
while counter "total_trips" at least 50
  if flag "expanded_fleet" clear
    show alert "50 trips! Time to expand!" green
    set flag "expanded_fleet"
```
- **Complexity**: ★★★ | **Usefulness**: ★★
- **Teaches**: Milestones via counters + flags.

### R143 — Text Variable Dispatch Log
```
when vehicle picks up cargo
  set text var "last_pickup" (Get vehicle.type)
  append text var "last_pickup" " picked up cargo"
  add to log (Var "last_pickup")
```
- **Complexity**: ★★★★ | **Usefulness**: ★
- **Teaches**: Text variable building. String manipulation.
- **Unlocks**: `set_text_var`, `append_text_var`, text var system

### R144 — Conditional Broadcast Chain
```
when trip pending
  if (scope is world) AND (payout > 500)
    broadcast "whale_trip"
    prioritize trip

when broadcast received "whale_trip"
  for each vehicle (ship)
    set speed mult 1.5
    flash vehicle 2
  show alert "High-value shipment detected!" green
```
- **Complexity**: ★★���★ | **Usefulness**: ★★★
- **Teaches**: Broadcast triggering a fleet-wide response. Dramatic.

### R145 — Anti-Starvation Timer
```
every 30 seconds
  for each pending trip
    if wait time > 45
      add bonus 25
      // comment: trips that wait too long get sweeter to encourage pickup
```
- **Complexity**: ★★★ | **Usefulness**: ★★★★
- **Teaches**: Periodic queue maintenance. Aging bonus.

### R146 — After N Seconds Startup
```
after 10 seconds
  open depot
  resume all clients
  show alert "Network online!" green
```
- **Complexity**: ★★ | **Usefulness**: ★★
- **Teaches**: One-shot delayed startup.
- **Unlocks**: `hat_after_n_seconds`

### R147 — Auto-Sort Rotating Strategy
```
every 15 seconds
  counter_inc "sort_cycle"
  if counter "sort_cycle" mod 3 = 0
    sort queue by payout
  else if counter "sort_cycle" mod 3 = 1
    sort queue by wait
  else
    sort queue by scope
```
- **Complexity**: ★★★★ | **Usefulness**: ★★
- **Teaches**: Modulo-driven rotation. Three strategies cycling.

### R148 — Ship Convoy **(FUTURE)**
```
when trip pending
  if scope is world
    if Var "ship_batch" < 5
      set leg destination → nearest dock
      counter_inc "ship_batch"
      skip trip
      // comment: batch 5 trips at the dock before shipping
    else
      counter_set "ship_batch" 0
      Find nearest ship → assign
```
- **Complexity**: ��★★★★ | **Usefulness**: ★★★★
- **Teaches**: Batching with counters. Accumulate-then-dispatch pattern.

### R149 — Income Tracker with Alert
```
when vehicle completes trip
  counter_inc "session_income" by (Get trip.payout)
  if Var "session_income" >= 10000
    if flag "income_10k" clear
      show alert "Earned $10,000 this session!" green
      set flag "income_10k"
```
- **Complexity**: ★★★★ | **Usefulness**: ★★
- **Teaches**: Reporter-amount counters + milestone flags.

### R150 — Scope-Based Vehicle Coloring
```
when vehicle picks up cargo
  if scope is district
    set vehicle color 0.3 0.9 0.3
  else if scope is city
    set vehicle color 0.3 0.3 0.9
  else
    set vehicle color 0.9 0.3 0.3
```
- **Complexity**: ★★★ | **Usefulness**: ★★
- **Teaches**: Visual encoding of trip type. Color as information.

---

## 20. Fragments — Condition Prefabs

These are standalone condition pieces, not full rules. They snap into any `if` block.

| ID | Name | Description | Complexity | Unlocks |
|---|---|---|---|---|
| F001 | Payout check | `payout > N` | ★ | trip.payout |
| F002 | Wait check | `wait_time > N` | ★ | trip.wait_time |
| F003 | Bonus check | `bonus > N` | ★ | trip.bonus |
| F004 | Scope is | `scope = X` | ★ | cond_scope |
| F005 | Scope is not | `scope != X` | ★ | cond_scope_not |
| F006 | Any idle | `any idle (type)` | ★ | cond_vehicle_idle |
| F007 | No idle | `no idle (type)` | ★ | cond_vehicle_none |
| F008 | Rush hour | `rush_hour active` | ★ | cond_rush_hour |
| F009 | Queue size | `queue_count > N` | ★ | game.queue_count |
| F010 | Money check | `money > N` | ★ | game.money |
| F011 | Fleet util | `utilization > N` | ★★ | fleet.utilization |
| F012 | Idle count | `idle_count(type) > N` | ★★ | fleet.idle_count |
| F013 | Fleet count | `count(type) > N` | ★★ | fleet.count |
| F014 | Cargo size | `cargo_size > N` | ★ | trip.cargo_size |
| F015 | Leg count | `leg_count > N` | �� | trip.leg_count |
| F016 | Multi-city | `is_multi_leg` | ★ | cond_multi_leg |
| F017 | Random chance | `random N%` | ★ | cond_random_chance |
| F018 | Flag set | `flag X set` | ★ | cond_flag_set |
| F019 | Flag clear | `flag X clear` | ★ | cond_flag_clear |
| F020 | Counter mod | `counter mod M = R` | ★★ | cond_counter_mod |
| F021 | Counter check | `counter > N` | ★★ | bool_compare + rep_get_var |
| F022 | Vehicle speed | `vehicle.speed > N` | ★★ | vehicle.speed |
| F023 | Vehicle trips | `vehicle.trips_completed > N` | ★★ | vehicle.trips_completed |
| F024 | This vehicle type | `this vehicle = type` | ★ | cond_this_vehicle_type |
| F025 | This vehicle idle | `this vehicle idle` | ★ | cond_this_vehicle_idle |
| F026 | Depot open | `depot is open` | ★ | cond_depot_open |
| F027 | Upgrade purchased | `upgrade X purchased` | ★ | cond_upgrade_purchased |
| F028 | Text var equals | `text_var = "X"` | ★★ | cond_text_var_eq |
| F029 | Text var contains | `text_var contains "X"` | ★★ | cond_text_var_contains |
| F030 | Always true | `true` | ★ | cond_always_true |
| F031 | Always false | `false` | ★ | cond_always_false |
| F032 | Vehicle fuel check **(FUTURE)** | `vehicle.fuel > N%` | ★ | vehicle.fuel_pct |
| F033 | Vehicle fuel rate **(FUTURE)** | `vehicle.fuel_rate > N` | ★ | vehicle.fuel_rate |
| F034 | Next mode check | `next_mode = "water"` | ★★ | trip.next_mode |
| F035 | RH timer check | `rh_timer > N` | ★★ | game.rh_timer |
| F036 | Depot vehicle count | `depot.vehicle_count > N` | ★★ | depot.vehicle_count |
| F037 | Client count | `client.count > N` | ★★ | client.count |
| F038 | Active clients | `client.active_count > N` | ★★ | client.active_count |
| F039 | Building cargo count | `building.cargo_count(type) > N` | ★★ | building.cargo_count |

---

## 21. Fragments — Action Prefabs

Standalone action pieces that snap into any rule body.

| ID | Name | Description | Complexity | Unlocks |
|---|---|---|---|---|
| A001 | Assign nearest | Find nearest → assign | ★ | find_match, assign_ctx, nearest |
| A002 | Assign fastest | Find fastest → assign | ★ | fastest sorter |
| A003 | Assign most capacity | Find most cap → assign | ★ | most_capacity sorter |
| A004 | Assign least recent | Find LRU → assign | ★ | least_recent sorter |
| A005 | Assign any | Find any → assign | ★ | basic find |
| A006 | Cancel trip | cancel_trip | ★ | cancel_trip |
| A007 | Skip trip | skip | ★ | skip |
| A008 | Prioritize | prioritize_trip | ★ | prioritize_trip |
| A009 | Deprioritize | deprioritize_trip | ★ | deprioritize_trip |
| A010 | Sort queue | sort_queue(metric) | ★ | sort_queue |
| A011 | Cancel all scope | cancel_all_scope(X) | ★ | cancel_all_scope |
| A012 | Cancel all waited | cancel_all_wait(N) | ★ | cancel_all_wait |
| A013 | Add money | add_money(N) | ★ | add_money |
| A014 | Subtract money | subtract_money(N) | ★ | subtract_money |
| A015 | Set payout | set_payout(N) | ★ | set_payout |
| A016 | Add bonus | add_bonus(N) | ★ | add_bonus |
| A017 | Trigger rush hour | trigger_rush_hour(N) | ★ | trigger_rush_hour |
| A018 | End rush hour | end_rush_hour | �� | end_rush_hour |
| A019 | Pause trip gen | pause_trip_gen | ★ | pause_trip_gen |
| A020 | Resume trip gen | resume_trip_gen | ★ | resume_trip_gen |
| A021 | Set trip gen rate | set_trip_gen_rate(N) | ★ | set_trip_gen_rate |
| A022 | Counter increment | counter_inc(var, N) | ★ | counter_inc |
| A023 | Counter decrement | counter_dec(var, N) | ★ | counter_dec |
| A024 | Counter set | counter_set(var, N) | �� | counter_set |
| A025 | Counter reset | counter_reset(var) | ★ | counter_reset |
| A026 | Set flag | set_flag(var) | ★ | set_flag |
| A027 | Clear flag | clear_flag(var) | ★ | clear_flag |
| A028 | Toggle flag | toggle_flag(var) | ★ | toggle_flag |
| A029 | Send to depot | send_to_depot | ★ | send_to_depot |
| A030 | Unassign vehicle | unassign_vehicle | ★ | unassign_vehicle |
| A031 | Fire vehicle | fire_vehicle | ★ | fire_vehicle |
| A032 | Set speed mult | set_speed_mult(N) | ★ | set_speed_mult |
| A033 | Flash vehicle | flash_vehicle(N) | ★ | flash_vehicle |
| A034 | Speech bubble | show_speech_bubble(text, N) | ★ | show_speech_bubble |
| A035 | Set vehicle color | set_vehicle_color(r,g,b) | ★ | set_vehicle_color |
| A036 | Reset vehicle color | reset_vehicle_color | ★ | reset_vehicle_color |
| A037 | Show alert | show_alert(text, color) | ★ | show_alert |
| A038 | Add to log | add_to_log(text) | ★ | add_to_log |
| A039 | Zoom to vehicle | zoom_to_vehicle | ★ | zoom_to_vehicle |
| A040 | Broadcast | broadcast_message(msg) | ★ | broadcast_message |
| A041 | Stop rule | stop_rule | ★ | stop_rule |
| A042 | Stop all | stop_all | ★ | stop_all |
| A043 | Break | action_break | ★ | action_break |
| A044 | Continue | action_continue | ★ | action_continue |
| A045 | Set leg destination | set_leg_destination(pos) | ★★ | set_leg_destination |
| A046 | Assign from building | assign_from_building | ★ | assign_from_building |
| A047 | Open depot | open_depot | ★ | open_depot |
| A048 | Close depot | close_depot | ★ | close_depot |
| A049 | Rename depot | rename_depot(name) | ★ | rename_depot |
| A050 | Pause clients | pause_all_clients | ★ | pause_all_clients |
| A051 | Resume clients | resume_all_clients | ★ | resume_all_clients |
| A052 | Set client freq | set_client_freq(N) | ★ | set_client_freq |
| A053 | Play sound | play_sound(name) | ★ | play_sound |
| A054 | Shake screen | shake_screen(sec, mag) | ★ | shake_screen |
| A055 | Set text var | set_text_var(key, val) | ★ | set_text_var |
| A056 | Comment | action_comment(text) | ★ | action_comment |
| A057 | Set rule name | set_rule_name(name) | ★ | set_rule_name |
| A058 | Refuel vehicle **(FUTURE)** | refuel | ★ | refuel action |
| A059 | Set zoom | set_zoom(N) | ★ | set_zoom |
| A060 | Pan to depot | pan_to_depot(id) | ★ | pan_to_depot |

---

## Summary Stats

| Category | Count |
|---|---|
| Full rules (R001–R150) | 150 |
| Condition fragments (F001–F039) | 39 |
| Action fragments (A001–A060) | 60 |
| **Total unlockable items** | **249** |
| Rules marked FUTURE (need new blocks) | ~15 |
| Complexity 1 rules | ~25 |
| Complexity 2 rules | ~45 |
| Complexity 3 rules | ~45 |
| Complexity 4 rules | ~25 |
| Complexity 5 rules | ~10 |
