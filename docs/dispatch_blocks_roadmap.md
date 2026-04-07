# Dispatch Block Roadmap
*Comprehensive catalogue of all planned visual rule blocks. Categorised for the palette. Nothing omitted unless genuinely duplicate or subsumed by an operator slot.*

---

## Architecture Prerequisites (do these first — everything else depends on them)

| # | Item | Why it's needed |
|---|------|-----------------|
| P0-1 | **Entity context** — hat triggers propagate "this vehicle" / "this trip" through the rule | Rename, color, fire, reassign all need to know *which* vehicle/trip fired the hat |
| P0-2 | **Reporter block type** — new category `"reporter"`, oval shape, slots accept reporters as values | Dynamic values (speed, payout, counter) plugged into other blocks' number/string slots |
| P0-3 | **Math operator reporters** — `+`, `-`, `×`, `÷`, `mod`, `min`, `max`, `abs`, `round`, `random N to M` | Arithmetic on dynamic values |
| P0-4 | **String operator reporters** — `join [A] [B]`, `letter [N] of [text]`, `length of [text]`, `number to text` | Building names like "StupidBike" + counter |
| P0-5 | **Text variables** — named string slots (A-Z) in addition to number counters | Store vehicle names, last event descriptions |
| P0-6 | **Broadcast / receive** — `broadcast [name]` stack block + `when broadcast received [name]` hat | Cross-rule communication without shared state hacks |

---

## Phase 1 — More Hats (Triggers)

### Vehicle Lifecycle Hats
| Block | Notes |
|-------|-------|
| `when vehicle hired [any / type]` | Fires once when a vehicle is added to the fleet; gives "this vehicle" context |
| `when vehicle dismissed [any / type]` | Fires when a vehicle is fired/sold |
| `when vehicle becomes idle [any / type]` | Fires when a vehicle finishes all trips and goes idle |
| `when vehicle completes a trip [any / type]` | Fires on every successful dropoff |
| `when vehicle picks up cargo [any / type]` | Fires at the pickup moment |
| `when vehicle drops off cargo [any / type]` | Fires at the dropoff moment |
| `when vehicle returns to depot [any / type]` | Fires when vehicle docks home |
| `when vehicle state changes to [state] [any / type]` | Fine-grained state machine hook |
| `when vehicle enters [district / city / region] [any / type]` | Geofence trigger |
| `when vehicle leaves [district / city / region] [any / type]` | Geofence trigger |
| `when vehicle cargo is full [any / type]` | Fires when cargo count = capacity |
| `when vehicle has been idle for [N] seconds [any / type]` | Timeout trigger for idle management |
| `when vehicle has been in state [state] for [N] seconds` | General stuck-state detector |

### Trip Lifecycle Hats
| Block | Notes |
|-------|-------|
| `when trip created [scope filter / any]` | Different from "when trip pending" — fires at creation moment |
| `when trip with payout [op] [N] enters queue` | Fires only for high/low value trips |
| `when trip has waited [N] seconds` | Urgency escalation trigger |
| `when trip expires / cancelled` | Cleanup trigger |

### Economy / Game Event Hats
| Block | Notes |
|-------|-------|
| `when money drops below [N]` | Financial alert |
| `when money rises above [N]` | Financial milestone |
| `when rush hour starts` | |
| `when rush hour ends` | |
| `when queue reaches [N] trips` | Overload trigger |
| `when queue empties` | |
| `when upgrade purchased [any / name]` | Post-purchase automation |
| `when all vehicles of type [X] are busy` | Fleet overload |
| `when all vehicles are idle` | Empty-fleet trigger |
| `when [N] or more trips have waited [M] seconds` | Batch urgency trigger |

### Counter / Flag Event Hats
| Block | Notes |
|-------|-------|
| `when counter [A] reaches [N]` | Milestone trigger |
| `when counter [A] drops below [N]` | Threshold trigger |
| `when flag [X] is set` | Reactive to flag changes |
| `when flag [X] is cleared` | |

### Timer Hats
| Block | Notes |
|-------|-------|
| `every [N] seconds` | Repeating clock — periodic maintenance rules |
| `after [N] seconds` | One-shot delay (fires once N seconds after rule start) |
| `when game starts` | Initialisation rule — runs once on load |

### Player / UI Hats
| Block | Notes |
|-------|-------|
| `when player selects a vehicle [any / type]` | Fires on UI click-select |
| `when player selects a depot` | |
| `when broadcast received [name]` | Triggered by `broadcast [name]` stack block |

---

## Phase 2 — Reporters (Dynamic Values)

Reporters are oval blocks that output a value and can be plugged into any number or string slot.

### Fleet Reporters
| Reporter | Returns |
|----------|---------|
| `[count of [type] vehicles]` | number |
| `[count of idle [type] vehicles]` | number |
| `[count of vehicles at depot [N]]` | number |
| `[count of vehicles on highway]` | number |
| `[name of this vehicle]` | string |
| `[type of this vehicle]` | string |
| `[speed of this vehicle]` | number |
| `[cargo count of this vehicle]` | number |
| `[cargo capacity of this vehicle]` | number |
| `[trips completed by this vehicle]` | number |
| `[state of this vehicle]` | string |
| `[distance from this vehicle to depot]` | number |
| `[earnings from this vehicle this session]` | number |
| `[idle time of this vehicle]` | seconds |

### Trip Reporters
| Reporter | Returns |
|----------|---------|
| `[payout of this trip]` | number |
| `[current bonus of this trip]` | number |
| `[scope of this trip]` | string |
| `[wait time of this trip]` | seconds |
| `[leg count of this trip]` | number |
| `[cargo size of this trip]` | number |

### Game / Economy Reporters
| Reporter | Returns |
|----------|---------|
| `[money]` | number |
| `[pending trip count]` | number |
| `[trips completed total]` | number |
| `[rush hour time remaining]` | seconds |
| `[fleet utilisation %]` | 0–100 |
| `[earnings per minute]` | number |
| `[average trip payout]` | number |
| `[longest pending wait time]` | seconds |
| `[time since last trip assigned]` | seconds |

### Counter / Flag / Variable Reporters
| Reporter | Returns |
|----------|---------|
| `[counter A / B / C / D / E]` | number |
| `[text variable A / B / C]` | string |
| `[flag X / Y / Z]` | bool (true/false as 1/0) |

### Math Operator Reporters
| Reporter | Returns |
|----------|---------|
| `[A] + [B]` | number |
| `[A] - [B]` | number |
| `[A] × [B]` | number |
| `[A] ÷ [B]` | number |
| `[A] mod [B]` | number |
| `round [N]` | number |
| `abs [N]` | number |
| `min [A] [B]` | number |
| `max [A] [B]` | number |
| `random [N] to [M]` | number |

### String Operator Reporters
| Reporter | Returns |
|----------|---------|
| `join [A] [B]` | string — "StupidBike" + counter |
| `letter [N] of [text]` | string |
| `length of [text]` | number |
| `number to text [N]` | string |
| `text to number [text]` | number |
| `text uppercased [text]` | string |
| `text lowercased [text]` | string |

---

## Phase 3 — Conditions (Boolean Blocks)

*All comparison conditions use a single block with `[op]` slot (>, <, =). No split gt/lt variants.*

### Trip Conditions
| Condition | Notes |
|-----------|-------|
| `scope is [scope]` | ✅ exists |
| `scope is not [scope]` | ✅ exists |
| `payout [op] [N]` | ✅ exists |
| `waited [op] [N] seconds` | ✅ exists |
| `is multi-city` | ✅ exists |
| `leg count [op] [N]` | |
| `cargo size [op] [N]` | |
| `trip is expired` | Too old, past deadline |
| `trip pickup is in [district / city name]` | Named zone filter |
| `trip dropoff is in [district / city name]` | |
| `trip requires vehicle type [type]` | Trip-to-vehicle compatibility |
| `trip current bonus [op] [N]` | Time-pressure condition |

### Vehicle / Fleet Conditions
| Condition | Notes |
|-----------|-------|
| `any [type] idle` | ✅ exists |
| `no [type] idle` | ✅ exists |
| `idle count [op] [N]` | ✅ exists |
| `this vehicle is type [type]` | In vehicle-context rules |
| `this vehicle is idle` | |
| `this vehicle is on highway` | |
| `this vehicle is at depot` | |
| `this vehicle cargo [op] [N]` | |
| `this vehicle speed [op] [N]` | |
| `this vehicle has tag [text]` | Per-vehicle tags (see Phase 5) |
| `this vehicle has completed [op] [N] trips` | Veteran/rookie checks |
| `this vehicle name contains [text]` | |
| `this vehicle state is [state]` | |

### Game State Conditions
| Condition | Notes |
|-----------|-------|
| `queue [op] [N]` | ✅ exists |
| `money [op] [N]` | ✅ exists |
| `rush hour active` | ✅ exists |
| `fleet utilisation [op] [N]%` | Busyness check |
| `upgrade [name] is purchased` | Gate on player progress |
| `game speed is [op] [N]` | Simulation rate check |

### Counter / Flag Conditions
| Condition | Notes |
|-----------|-------|
| `counter [A] [op] [N]` | ✅ exists |
| `flag [X] set` | ✅ exists |
| `flag [X] clear` | ✅ exists |
| `text variable [A] = [text]` | String equality |
| `text variable [A] contains [text]` | Substring check |

### Logic / Utility Conditions
| Condition | Notes |
|-----------|-------|
| `and` | ✅ exists |
| `or` | ✅ exists |
| `not` | ✅ exists |
| `[A] [op] [B]` *(reporter compare)* | Compare any two reporter values |
| `[N] mod [M] = [R]` | Every Nth event filter |
| `random [N]% chance` | Probabilistic routing — 30% → bike, 70% → car |
| `always true` | Constant, useful as loop terminator placeholder |
| `always false` | For disabled branches during development |

---

## Phase 4 — Flow Control Blocks

| Block | Notes |
|-------|-------|
| `if / then` | ✅ exists |
| `if / then / else` | ✅ exists |
| `repeat [N] times:` | C-block loop |
| `repeat until [condition]:` | C-block loop with condition |
| `for each vehicle [of type / all]:` | Iterate fleet |
| `for each pending trip:` | Iterate queue |
| `wait [N] seconds` | Suspend rule; useful in repeating timer hats |
| `wait until [condition]` | Block until something is true |
| `stop this rule` | Early exit |
| `stop all rules` | Global halt |
| `stop other rules` | Let only this one continue |
| `broadcast [name]` | Signal other rules |
| `break` | Exit enclosing loop |
| `continue` | Skip to next loop iteration |

---

## Phase 5 — Trip Action Blocks

| Block | Notes |
|-------|-------|
| `assign to any` | ✅ exists |
| `assign to [type]` | ✅ exists |
| `assign to nearest [type]` | ✅ exists |
| `assign to fastest available [type]` | Highest speed stat |
| `assign to vehicle with most capacity [type]` | |
| `assign to vehicle named [text]` | Requires name match |
| `assign to least recently used [type]` | Round-robin fairness |
| `cancel trip` | ✅ exists |
| `skip (hold)` | ✅ exists |
| `prioritize this trip` | Move to front of queue |
| `deprioritize this trip` | Move to back of queue |
| `set this trip payout to [N]` | Override pricing |
| `add [N] bonus to this trip` | Incentive boost |
| `change this trip scope to [scope]` | Reclassify range |
| `drop trip at depot [N]` | Reroute to different depot |
| `cancel all trips with payout [op] [N]` | Bulk purge |
| `cancel all trips with scope [scope]` | Bulk purge |
| `cancel all trips with wait time [op] [N] seconds` | Expire old trips |
| `sort queue by [payout / wait time / scope / distance]` | Reorder pending list |
| `hold all trips of scope [X] until [condition]` | Conditional queue gate |

---

## Phase 6 — Vehicle Management Blocks

| Block | Notes |
|-------|-------|
| `hire vehicle of type [type] at depot [N]` | |
| `fire this vehicle` | In vehicle-context rule |
| `fire nearest idle [type]` | |
| `fire all idle vehicles of type [type]` | Bulk dismissal |
| `fire vehicle named [text]` | By name |
| `fire vehicle with lowest earnings` | Performance culling |
| `fire vehicle with longest idle time` | |
| `send this vehicle to depot` | Immediate return |
| `send all [type] to depot` | Fleet recall |
| `unassign all trips from this vehicle` | Drop queue |
| `unassign all trips from all [type]` | |
| `rename this vehicle to [text]` | Supports reporter in slot — "StupidBike" + counter |
| `set this vehicle speed multiplier to [N]%` | Runtime buff/debuff |
| `set this vehicle max cargo to [N]` | Runtime override |
| `lock this vehicle to [district / city / region]` | Zone restriction |
| `unlock this vehicle from zone` | |
| `give this vehicle tag [text]` | Per-vehicle marker |
| `remove tag [text] from this vehicle` | |
| `clear all tags from this vehicle` | |
| `transfer cargo from this vehicle to [nearest / type]` | |
| `clone this vehicle` | Duplicate at same depot |
| `pause this vehicle` | Freeze movement |
| `resume this vehicle` | |

---

## Phase 7 — Visual / Looks Blocks

### Per-Vehicle Appearance
| Block | Notes |
|-------|-------|
| `set this vehicle color to [color]` | Static color override |
| `set this vehicle color based on [speed / cargo% / state / type]` | Dynamic gradient |
| `reset this vehicle color` | Back to default |
| `set this vehicle icon to [emoji]` | Custom icon |
| `rename this vehicle to [text]` | (also in management) |
| `show speech bubble [text] for [N] seconds` | Floating label on vehicle |
| `flash this vehicle [color] for [N] seconds` | Alert pulse |
| `show label [text] above vehicle for [N] seconds` | Persistent label |
| `show / hide this vehicle path trail` | Route visualisation |
| `set this vehicle size to [N]%` | Scale icon |
| `show / hide this vehicle` | Visibility toggle |

### Camera / Map
| Block | Notes |
|-------|-------|
| `zoom camera to this vehicle` | |
| `zoom camera to depot [N]` | |
| `pan camera to [this vehicle / depot / x y]` | |
| `set zoom level to [N]` | |
| `shake screen for [N] seconds` | Event emphasis |

---

## Phase 8 — Sound Blocks

| Block | Notes |
|-------|-------|
| `play sound [beep / horn / chime / warning / success / fail / ...] ` | Global playback |
| `play sound [name] at this vehicle` | Spatial audio |
| `play sound [name] at depot [N]` | |
| `stop all sounds` | |
| `set master volume to [N]%` | |

*Sound library to grow with game; slot should be an enum that expands over time.*

---

## Phase 9 — UI / Notification Blocks

| Block | Notes |
|-------|-------|
| `show toast [text] for [N] seconds` | Non-blocking overlay |
| `show alert [title] [body]` | Blocking info modal |
| `confirm [question] → yes: [body] no: [body]` | Yes/no decision modal — "fire all bikes?" |
| `prompt [question] → store in [counter / text var]` | Text or number input dialog |
| `add to game log [text]` | Append line to scrollable event log |
| `highlight depot [N] for [N] seconds [color]` | Draw attention to depot |
| `show / hide HUD element [name]` | Toggle UI panels |
| `set game title to [text]` | Window title override |

---

## Phase 10 — Economy / Game System Blocks

| Block | Notes |
|-------|-------|
| `add [N] money` | Direct balance change |
| `subtract [N] money` | |
| `set money to [N]` | Debug / scenario setup |
| `purchase upgrade [name]` | Auto-buy from rules |
| `set trip generation rate to [N]%` | Throttle trip spawn |
| `pause trip generation` | ✅ exists |
| `resume trip generation` | ✅ exists |
| `trigger rush hour for [N] seconds` | Force event |
| `end rush hour` | |
| `set rush hour duration to [N] seconds` | Modify upgrade value at runtime |
| `set game speed to [N]x` | Simulation multiplier |
| `spawn debug trip of scope [scope] at depot` | ✅ exists |

---

## Phase 11 — Depot Management Blocks

| Block | Notes |
|-------|-------|
| `close depot [N]` | Stop accepting new trip assignments |
| `open depot [N]` | |
| `rename depot [N] to [text]` | |
| `set depot capacity to [N]` | Max vehicles |
| `send all vehicles at depot [N] to depot [M]` | Fleet migration |
| `transfer all pending trips from depot [N] to depot [M]` | Queue migration |
| `highlight depot [N]` | (also in UI section) |

---

## Phase 12 — Counter / Variable / Flag Blocks (Expanded)

*Beyond what currently exists:*

| Block | Notes |
|-------|-------|
| `counter [A] [op] [N]` | ✅ exists (+=, -=) |
| `reset counter [A]` | ✅ exists |
| `set counter [A] to [N]` | Absolute set (not just increment) |
| `reset all counters` | Bulk reset |
| `set flag [X]` | ✅ exists |
| `clear flag [X]` | ✅ exists |
| `toggle flag [X]` | Flip without knowing current state |
| `set text variable [A] to [text]` | String storage |
| `append [text] to text variable [A]` | |
| `clear text variable [A]` | |
| `swap counter [A] and counter [B]` | Useful for sorting patterns |

---

## Phase 13 — Custom Blocks / Procedures

| Block | Notes |
|-------|-------|
| `define [block name] (with params)` | Declare a reusable procedure; becomes a hat |
| `call [block name]` | Invoke it from any rule |
| `call [block name] with [param] [param]` | Parameterised call |

*Implementation note: a "define" block creates a named sub-rule. "call" blocks trigger it synchronously. This is Scratch's "My Blocks" system. Params are reporters in the called rule's scope.*

---

## Phase 14 — Client / Business Management (Future Feature)

*These blocks only make sense once the client system is fleshed out.*

| Block | Notes |
|-------|-------|
| `fire client [name / lowest revenue / longest without trip]` | |
| `hire new client` | |
| `set client [name] trip frequency to [low / normal / high]` | |
| `move client [name] to depot [N]` | |
| `give client [name] a bonus trip` | |
| `[condition] client [name] is active` | Boolean |
| `[condition] client [name] has had [op] [N] trips this session` | |
| `[reporter] trip count from client [name]` | |

---

## Phase 15 — Advanced / Exotic Blocks

*Low priority but genuinely useful.*

| Block | Notes |
|-------|-------|
| `comment [text]` | No-op documentation block (grey, no puzzle connector) |
| `set rule name to [text]` | Label rules in the editor |
| `throttle: run at most once every [N] seconds` | Hat modifier — prevents spam |
| `schedule: at game time [N] seconds do` | Absolute time trigger |
| `wait until [condition], timeout after [N] seconds → [flag]` | Timed wait with fallback |
| `benchmark: log time since last tick` | Dev/debug profiling block |
| `assert [condition] else log [text]` | Dev-mode sanity check |

---

## Implementation Phases Summary

| Phase | What | Blocks unlocked |
|-------|------|-----------------|
| **0** | Infrastructure: entity context, reporter type, math/string ops, text vars | All dynamic blocks |
| **1** | More hat triggers (vehicle/trip/economy/timer lifecycle) | ~25 new hats |
| **2** | Reporter blocks (fleet, trip, game, counters, math, string) | ~40 reporters |
| **3** | Expanded boolean conditions (vehicle, trip, fleet) | ~20 new conditions |
| **4** | Flow control (loops, for-each, wait, broadcast, stop variants) | ~12 control blocks |
| **5** | Trip action blocks (prioritize, bulk cancel, sort queue, reroute) | ~15 trip actions |
| **6** | Vehicle management (hire, fire, rename, tag, lock zone, clone) | ~20 vehicle actions |
| **7** | Visual / looks (color, icon, bubble, label, trail, camera) | ~15 visual blocks |
| **8** | Sound (play, spatial, volume) | ~5 sound blocks |
| **9** | UI / notifications (toast, alert, confirm dialog, prompt, log) | ~8 UI blocks |
| **10** | Economy / game system (money, trip gen, rush hour, game speed) | ~10 economy blocks |
| **11** | Depot management (close, rename, transfer, capacity) | ~7 depot blocks |
| **12** | Counter/variable/flag expansion (set absolute, toggle, text vars, swap) | ~8 blocks |
| **13** | Custom blocks / procedures (define, call, params) | Unbounded reuse |
| **14** | Client management (future feature dependency) | ~8 client blocks |
| **15** | Advanced / exotic (comment, throttle, schedule, assert) | ~6 utility blocks |

---

## Colour Coding Convention (palette)

| Category | Colour |
|----------|--------|
| Hats | Gold `{0.85, 0.65, 0.10}` |
| Control / flow | Orange `{0.85, 0.55, 0.08}` |
| Trip conditions | Green `{0.22, 0.68, 0.32}` |
| Vehicle conditions | Teal `{0.28, 0.72, 0.58}` |
| Game state conditions | Cyan `{0.35, 0.65, 0.72}` |
| Counter / flag conditions | Purple `{0.55, 0.38, 0.80}` |
| Logic operators | Yellow `{0.82, 0.78, 0.15}` |
| Math / string reporters | Lime `{0.55, 0.78, 0.22}` |
| Trip actions | Blue `{0.28, 0.45, 0.88}` |
| Vehicle management | Sky `{0.25, 0.60, 0.90}` |
| Visual / looks | Pink `{0.82, 0.40, 0.72}` |
| Sound | Magenta `{0.75, 0.30, 0.65}` |
| UI / notifications | Warm grey `{0.60, 0.55, 0.50}` |
| Economy / game | Red-orange `{0.85, 0.40, 0.20}` |
| Depot | Brown `{0.65, 0.45, 0.25}` |
| Counter / flag effects | Purple `{0.52, 0.28, 0.80}` |
| Custom blocks | Dark blue `{0.20, 0.30, 0.65}` |
| Client | Olive `{0.58, 0.62, 0.22}` |
| Utility / comment | Grey `{0.40, 0.40, 0.45}` |

---

## Palette UI Design

### Overview

The palette is the block picker that appears below a rule when "Add Blocks" is clicked. As the block library grows into hundreds of entries, it needs a proper filtering and search system. All filters can be active simultaneously — the results are the **intersection** (AND) of every active filter dimension.

---

### Filter Dimensions

There are three independent ways to filter the palette at the same time:

| Dimension | How it works |
|-----------|--------------|
| **Topic tag** | Toggle-pill buttons; multiple can be active. Shows blocks matching ANY active tag (union within the tag dimension). No active tags = show all. |
| **Shape / slot type** | Optionally restrict to only `boolean` (hexagonal) or `stack`/`hat`/`control` blocks. Context-aware: auto-activates when mid-drag. |
| **Text search** | Free-text field; matches against label and tooltip text. Empty = show all. |

Combining all three: result = (matches any active topic tag) **AND** (matches shape filter if set) **AND** (matches search text if any).

Example: topic tags `[trip] [vehicle]` active + search `"assign"` → shows only trip/vehicle-topic blocks whose label or tooltip contains "assign".

---

### Topic Tags

Every block definition carries a `tags` array. Tags are non-exclusive — a block can have multiple. The palette groups its filter pills by topic.

| Tag | Colour | Blocks it covers |
|-----|--------|-----------------|
| `trigger` | Gold `{0.85, 0.65, 0.10}` | All hat blocks |
| `logic` | Yellow `{0.82, 0.78, 0.15}` | `and`, `or`, `not`, `if/then`, `if/then/else`, loops, flow control |
| `trip` | Green `{0.22, 0.68, 0.32}` | Trip conditions (scope, payout, wait, multi-city…), trip actions (assign, cancel, skip, prioritize, bulk cancel…) |
| `vehicle` | Teal `{0.28, 0.72, 0.58}` | Vehicle conditions (idle, idle count…), vehicle management actions (hire, fire, rename, tag, lock zone…) |
| `game` | Cyan `{0.35, 0.65, 0.72}` | Game-state conditions (money, queue, rush hour, fleet utilisation), economy blocks, game speed |
| `counter` | Purple `{0.55, 0.38, 0.80}` | Counter conditions + effects, flag conditions + effects, text variables |
| `visual` | Pink `{0.82, 0.40, 0.72}` | Vehicle color, icon, label, trail, speech bubble, camera blocks |
| `sound` | Magenta `{0.75, 0.30, 0.65}` | All sound playback blocks |
| `ui` | Warm grey `{0.60, 0.55, 0.50}` | Toast, alert, confirm dialog, prompt, log, HUD toggle blocks |
| `depot` | Brown `{0.65, 0.45, 0.25}` | Depot open/close, rename, capacity, transfer blocks |
| `reporter` | Lime `{0.55, 0.78, 0.22}` | All reporter (oval) blocks — fleet, trip, game, counter, math, string reporters |

---

### Filter Pill UI

```
┌─────────────────────────────────────────────────────┐
│ [trigger] [logic] [trip] [vehicle] [game] [counter] │  ← row 1 of topic pills
│ [visual] [sound] [ui] [depot] [reporter]            │  ← row 2 (wraps if needed)
│ ┌─────────────────────────────────────────────────┐ │
│ │ 🔍  search blocks...                            │ │  ← text search field
│ └─────────────────────────────────────────────────┘ │
│                                                     │
│  LOGIC                                              │  ← category header (existing)
│  [if/then]  [if/then/else]  [and]  [or]  [not]     │
│  TRIP                                               │
│  [scope is] [payout >] [waited >] ...               │
│  ...                                                │
└─────────────────────────────────────────────────────┘
```

- Active tag pill: solid fill with block's tag colour, white text.
- Inactive tag pill: dark fill, dim text, coloured left border.
- Tags with zero matching blocks (given current shape filter + search): dimmed and non-interactive.
- Clear all button (small × or "all") appears when any filter is active.

---

### Search Field

- Single-line text input at top of palette, always visible.
- Click to focus; `Escape` clears + defocuses.
- While focused: all key presses route to search (letters, digits, backspace, space). Navigation keys (arrow keys) still scroll the sidebar.
- Placeholder text: `search blocks...`
- Matches against block `label` (case-insensitive) and `tooltip` text.
- Search is live (filters as you type, no Enter needed).
- When a search term is active, a small clear `×` button appears at the right end of the field.

---

### Keyboard Support

| Key | Behaviour |
|-----|-----------|
| Click search field | Focus search input |
| Any printable char (when search focused) | Appends to search query |
| `Backspace` (when search focused) | Deletes last character |
| `Escape` (when search focused) | Clears query and defocuses |
| `Escape` (general, when any filter active) | Clears all active topic tags and search |
| Tag pill click | Toggles that topic tag on/off |
| Click palette block | Begins drag (or appends if stack type, as before) |

---

### Data Model: `tags` field

Each block in `data/dispatch_blocks.lua` gets a `tags` array:

```lua
{ id = "cond_payout", category = "boolean", tags = { "trip" }, ... }
{ id = "action_assign_any", category = "stack", tags = { "trip", "vehicle" }, ... }
{ id = "bool_and", category = "boolean", tags = { "logic" }, ... }
{ id = "effect_counter_change", category = "stack", tags = { "counter" }, ... }
```

Blocks can have multiple tags if they span topics. The palette filter shows a block if its `tags` array contains **at least one** of the currently active tags (union within dimension).

---

### State additions in `DispatchTab`

```lua
state.palette_filter = {
    active_tags    = {},     -- map of tag_id → true when active
    search         = "",     -- current search string
    search_focused = false,  -- whether search field has keyboard focus
}
state.palette_filter_rects = {}   -- { {tag, x, y, w, h}, ... } — populated during draw
state.palette_search_rect  = nil  -- { x, y, w, h }
```

---

## Notes on Removed / Consolidated Blocks

The following were considered but collapsed into single blocks with operator slots:

- `cond_payout_gt` + `cond_payout_lt` + `cond_payout_between` → `cond_payout [op] [N]` ✅ done
- `cond_wait_gt` + `cond_wait_lt` → `cond_wait [op] [N]` ✅ done
- `cond_queue_gt` + `cond_queue_lt` → `cond_queue [op] [N]` ✅ done
- `cond_money_gt` + `cond_money_lt` → `cond_money [op] [N]` ✅ done
- `cond_counter_gt` + `cond_counter_lt` + `cond_counter_eq` → `cond_counter [op] [N]` ✅ done
- `effect_counter_add` + `effect_counter_sub` → `effect_counter_change [op] [N]` ✅ done
- `logic_and/or/not` (flat connectors) → `bool_and/or/not` tree nodes ✅ done
- Any future comparison-type block follows the same rule: one block, `[op]` slot

*Total planned blocks: ~200+ across all phases.*
