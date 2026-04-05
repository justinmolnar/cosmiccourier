# UI Overhaul

## Philosophy

The UI system has no knowledge of the game. It does not know what tabs exist, what is inside them, what clicking an upgrade does, or what a vehicle is. It renders declarative descriptions of content and fires events when the player interacts with something. Everything else is handled by game systems that listen to those events.

The game runs continuously at all times. There is no pause, no management mode, no modal that stops the world. The player manages while vehicles are moving, trips are expiring, and dispatch is running. The cost of inattention is mild (a suboptimal route for a few seconds) — it is not a crisis. This is an idle game.

---

## Layout

The screen is divided into two regions:

- **Panel** — fixed pixel width, sits on one side (left or right, TBD). Holds all management UI. Width is a constant in config. The world view gets whatever is left. Whether the panel width becomes player-adjustable is undecided; default assumption is fixed.
- **World view** — the map, vehicles, infrastructure. Always running. The player can zoom, pan, and interact with world objects while the panel is open.

A thin **HUD strip** sits along the edge of the world view (not inside the panel). It holds overlay toggle buttons — visibility controls for regions, zones, vehicle paths, infrastructure, etc. These are world-view controls, not panel content.

---

## Panel Architecture

The panel is a tab router. It knows:
- A list of tab definitions (id, label, icon)
- Which tab is currently active
- How to render the active tab's content area

It does not know what is in any tab. Each tab provides a content descriptor — a tree of UI components — and the panel renders it. The panel has no concept of vehicles, trips, upgrades, or dispatch rules.

```
Panel
  TabBar           -- renders tab buttons from tab definition list
  ContentArea      -- renders whatever the active tab describes
    ScrollContainer
      [component tree provided by active tab]
```

Tabs are registered at startup by game systems, not hardcoded in the panel. A vehicles system registers a vehicles tab. An upgrades system registers an upgrades tab. If a system doesn't exist or hasn't been unlocked, its tab isn't registered. The panel has no idea what tabs it will contain at any given moment.

---

## Component Model

The panel renders a tree of generic components. Components are data — the UI system doesn't know what they represent.

```lua
-- A label
{ type = "label", text = "some text", style = "heading" }

-- A button
{ type = "button", id = "some_action_id", label = "Click Me", icon = "🚲" }

-- A row of components
{ type = "row", children = { ... } }

-- A stat with a bar (progress, capacity, etc.)
{ type = "stat_bar", label = "Capacity", value = 7, max = 10 }

-- A list of rows (scrollable, virtualized for large counts)
{ type = "list", items = { ... }, row_height = 32 }

-- A section with a collapsible header
{ type = "section", label = "Active Vehicles", collapsible = true, children = { ... } }

-- A slider
{ type = "slider", id = "some_setting_id", label = "Budget", min = 0, max = 1000, value = 250 }

-- A badge / tag
{ type = "badge", text = "Inter-city", color = { 0.4, 0.7, 1.0 } }
```

The UI system knows how to draw these. It does not know what they mean. A `stat_bar` is just a bar. A `button` is just a button. When the player clicks it, the UI fires an event with the button's `id`. Something else handles it.

---

## Event Model

The UI fires one kind of outbound event: `"ui_action"`, with a payload of the component's `id` and any relevant value.

```lua
-- Player clicks a hire button
EventBus:publish("ui_action", { id = "hire_vehicle", data = { vehicle_type = "car" } })

-- Player clicks an upgrade
EventBus:publish("ui_action", { id = "purchase_upgrade", data = { upgrade_id = "bike_bag", level = 2 } })

-- Player moves a slider
EventBus:publish("ui_action", { id = "dispatch_rule_threshold", data = { rule_id = "r_003", value = 500 } })
```

The UI does not handle these. It fires and forgets. The relevant game system (UpgradeSystem, VehicleFactory, DispatchRuleEngine) is subscribed and acts on it.

Inbound: game systems push updated content descriptors to their tab whenever state changes. The panel re-renders the active tab's content on the next frame if it has been marked dirty.

---

## Tab Registration

At startup, game systems register tabs:

```lua
game.ui_panel:registerTab({
  id       = "vehicles",
  label    = "Vehicles",
  icon     = "🚗",
  priority = 10,           -- determines tab order
  locked   = false,        -- true = tab visible but greyed, requires unlock
  build    = function(game) return VehiclesTab.build(game) end,
})
```

The `build` function returns a component tree. The panel calls it when the tab becomes active (or when the tab's dirty flag is set). The panel does not call into `VehiclesTab` for any other reason.

Tabs can be unlocked through the upgrade/progression system — a game system calls `ui_panel:unlockTab("rail_network")` and the tab becomes active. The panel just changes a flag and re-renders the tab bar.

---

## Vehicles Tab

The vehicles tab is built entirely from loaded vehicle definitions and live entity state. It does not hardcode any vehicle type.

Content:
- For each vehicle type in `game.C.VEHICLES`: a section with a hire button, current count, and cost
- A scrollable list of all active vehicles, each row showing: icon, id, current state, cargo, destination
- Clicking a vehicle row expands it or opens a detail view

The tab builder iterates `game.C.VEHICLES`. If a new vehicle type is added by dropping a JSON file, it appears in the tab automatically.

---

## Trips Tab

A scrollable list of pending trips. Each row shows origin, destination, cargo size, time remaining on speed bonus, assigned vehicle if any. Hovering or clicking a row highlights the trip on the world map.

No trip-type-specific logic in the UI. A trip is a trip. The row renderer reads whatever fields are on the trip object.

---

## Dispatch Tab

The dispatcher rule system. The player authors a prioritised list of rules that the dispatch engine evaluates when assigning vehicles to trip legs.

Each rule:
```
IF  [condition] [operator] [value]
AND [condition] [operator] [value]   (optional, multiple)
THEN [action]
```

Example rules:
```
IF trip.distance > 500 AND trip.inter_city = true
THEN route_via = "rail_station_nearest"

IF vehicle.cargo_size_available < 5
THEN skip

IF trip.age > 120
THEN priority = "critical"
```

The UI renders these as rows of editable condition/action blocks. Drag to reorder. Toggle to enable/disable without deleting.

The UI does not evaluate these rules. It renders them from a list of rule data objects and fires events when the player edits them. The DispatchRuleEngine owns and evaluates the rules at dispatch time.

Conditions, operators, and actions are registered by game systems — not hardcoded in the UI. When the rail system is built, it registers `"route_via_rail"` as an available action. It appears in the dropdown.

---

## HUD Strip (World View Overlays)

A row of small toggle buttons along the edge of the world view. Not part of the panel. These control what is rendered on the map.

Each button is registered by a game system, same pattern as tabs:

```lua
game.hud:registerOverlay({
  id      = "show_regions",
  icon    = "🗺",
  tooltip = "Region boundaries",
  locked  = true,    -- hidden until unlocked
  key     = "r",     -- optional hotkey
})
```

Toggling fires `"ui_action"` with the overlay id. The rendering system listens and toggles its draw flag. The HUD doesn't know what "show_regions" draws.

This replaces the current hardcoded debug key toggles for player-facing overlays. Debug overlays (F3, road segments, etc.) stay separate and are not part of the HUD system.

---

## Information Feed

A small persistent feed in a corner of the world view (or bottom of the panel) showing recent notable events: delivery completed, vehicle stuck, trip expired, infrastructure built. Entries fade after a few seconds.

The feed is generic — it renders strings with optional icons and colors. Game systems push entries to it:

```lua
game.feed:push({ text = "Delivery completed: +$420", icon = "📦", color = "green" })
game.feed:push({ text = "Vehicle 12 stuck — retrying", icon = "⚠️", color = "yellow" })
```

The feed does not know what these mean. It just shows them in order and times them out.

This replaces floating payout text as the primary feedback mechanism, or complements it. Floating text stays for the immediate "money appeared" feel; the feed provides a scrollable history.

---

## Unlock Gating

UI elements have an optional `locked` state. Locked tabs are greyed out or hidden. Locked HUD buttons are invisible. Locked components within a tab are dimmed with a tooltip explaining the requirement.

The unlock system calls into the UI when something is unlocked:
```lua
game.ui_panel:unlockTab("dispatch")
game.hud:unlockOverlay("show_regions")
```

The UI has no knowledge of what condition triggers an unlock. It just has a flag. The progression/upgrade system owns the logic of when to call unlock.

---

## What This Replaces

| Current | Replacement |
|---------|-------------|
| Hardcoded accordion panels | Registered tabs, data-driven content |
| Hardcoded hire buttons per vehicle type | Loop over vehicle definitions |
| H/C/debug key toggles for player overlays | HUD strip with registered overlays |
| Floating text as sole event feedback | Information feed + floating text |
| UIManager knowing about trips/vehicles | UIManager as pure renderer + event emitter |
| UIController checking specific button IDs | Game systems subscribe to `ui_action` events |
| `debug_hide_vehicles` etc. as game fields | HUD overlay flags owned by render system |

---

## What Does Not Change

- The world view rendering (GameView) is untouched by this system
- The EventBus is the communication layer — no direct calls from UI into game logic
- The game runs continuously — no pause state, no modal blocking gameplay
- Debug overlays (F3, road graph, pathfinding debug) stay as developer tools outside this system
