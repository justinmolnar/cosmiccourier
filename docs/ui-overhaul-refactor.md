# Cosmic Courier — UI Overhaul Refactor

> Created: 2026-04-05
> Scope: All UI — panel, tabs, components, world interaction, event feed
> Goal: Replace accordion-based hardcoded panel with a tab-routed declarative component system. Make the game actually interactive — clickable vehicle list, clickable vehicles on the map, meaningful data visible at a glance.
> Audit sources: Full read of UIManager, UIView, UIController, Accordion, all panel views, Modal, EventService, main.lua

---

## Critical Rules

1. **No phase begins until the previous phase passes the interaction smoke test listed under Testing.**
2. **The game must be fully playable after every phase.** Vehicles hire, trips assign, upgrades purchase — nothing regresses.
3. **No new game features during this refactor.** Layout changes, render changes, interaction improvements only.
4. **Each phase is a single commit.**
5. **If a phase uncovers a real bug, fix it in a separate commit first.**
6. **The world view (GameView) is not touched.** All changes are panel-side.

---

## Current State

| Component | State |
|-----------|-------|
| Panel structure | Four hardcoded accordions in UIManager |
| Layout system | Imperative `y_cursor` in `_doLayout`, positions baked into `layout_cache` |
| Click detection | Reverse-engineers layout_cache geometry in UIController |
| Vehicle list | Renders text only — no click, no selection, no expand |
| Vehicle map click | Radius-based, works but cycles through overlapping vehicles only |
| Trip list | Hover highlights on map; click-to-assign only works via separate gesture |
| Hire buttons | Functional but can't scroll to them if fleet is large |
| Upgrades | Modal works — keep it |
| Stats header | Hardcoded emoji strings built in UIManager |
| Event model | Mix of named events (`ui_buy_vehicle_clicked`, `ui_assign_trip_clicked`) — no unified `ui_action` |
| Tab system | Does not exist |
| Component tree | Does not exist |
| HUD strip | Does not exist |
| Information feed | Does not exist |

---

## Phase 1 — Panel Shell + Tab Bar

**Goal:** Replace the four hardcoded accordions with a tab-routed panel. The tab bar renders at the top of the sidebar. One content area below it scrolls independently. No accordion state, no `_doLayout`, no `layout_cache`. Game content is identical — all four sections still present, just inside tabs instead of accordions. The world view is unchanged.

### Tasks

| # | File | Change |
|---|------|--------|
| 1.1 | `views/Panel.lua` (new) | Create `Panel` class. State: `tabs = {}` (ordered list), `active_tab_id`, `scroll_y`, `scroll_target`, `content_h`. Methods: `registerTab(def)` where def = `{ id, label, icon, priority, build }`. `setActiveTab(id)` — sets active, marks dirty, resets scroll. `getActiveTab()`. No rendering yet. |
| 1.2 | `views/Panel.lua` | Add `Panel:draw(game)`. Renders: (a) sidebar background rect, (b) tab bar row at top — one button per registered tab, active tab highlighted, (c) scissor-clipped content area below tab bar. Tab bar height = 32px, stored as `Panel.TAB_BAR_H = 32`. Content area starts at `TAB_BAR_H` and fills remaining sidebar height. |
| 1.3 | `views/Panel.lua` | Add `Panel:handleScroll(dy)` — scrolls `scroll_y` within content bounds. Add `Panel:handleMouseDown(x, y, button)` — hit-tests tab bar buttons, calls `setActiveTab` if hit. Returns true if consumed. |
| 1.4 | `views/UIManager.lua` | Replace the four `Accordion:new` calls and accordion state with `Panel:new()`. Register four tabs: `"vehicles"`, `"trips"`, `"clients"`, `"upgrades"`. Each tab's `build` function calls the existing panel view draw functions (VehiclesPanelView, TripsPanelView, etc.) imperatively — this is temporary scaffolding, replaced in Phase 3. Mark each tab dirty on every frame for now. |
| 1.5 | `views/UIView.lua` | Replace the four `accordion:beginDraw / endDraw / drawScrollbar` call sequences with a single `Game.ui_manager.panel:draw(Game)`. Remove accordion-specific imports. |
| 1.6 | `controllers/UIController.lua` | Replace `accordion:handle_mouse_down` / `handle_mouse_up` / `handle_scroll` calls with `panel:handleMouseDown` / `handleMouseUp` / `handleScroll`. Remove all accordion references. |
| 1.7 | `views/components/Accordion.lua` | Keep the file — do not delete yet. It may still be referenced during the transition. |

### Expected Outcome

The sidebar now has a tab bar across the top. Clicking tabs switches content. The same four content areas exist but as tabs rather than accordions. Scrolling works per-tab. Visual result is similar to before but the structural substrate has changed.

### Testing

- Start game → four tabs visible in tab bar.
- Click each tab → content switches, scroll resets.
- Scroll within a tab → scroll position preserved when switching away and back.
- Hire a vehicle → button still works.
- Purchase a client → button still works.
- Assign a trip manually → still works.

---

## Phase 2 — Component Renderer

**Goal:** The panel renders a declarative component tree, not imperative draw calls. Each tab's `build` function returns a table of component descriptors. The panel renderer knows how to draw `label`, `button`, `row`, `list`, `section`, `stat_bar`, `badge`. Click detection is derived from the component tree, not a separate layout_cache. This eliminates `layout_cache`, `_doLayout`, UIController's geometry reversal, and all the scattered button-position dictionaries.

### Tasks

| # | File | Change |
|---|------|--------|
| 2.1 | `views/ComponentRenderer.lua` (new) | Create `ComponentRenderer`. Single entry point: `ComponentRenderer.draw(components, x, y, w, scissor_h, scroll_y)` — iterates component list, dispatches to per-type draw functions, tracks `cursor_y` for vertical stacking. Returns `total_h` (used by Panel for scroll bounds). |
| 2.2 | `views/ComponentRenderer.lua` | Implement draw functions for each type: `label` (love.graphics.print, style = heading/body/small), `button` (rect + centered text, hover highlight), `row` (horizontal children, fixed height), `section` (header bar + indented children, collapsible flag), `list` (virtualized — only renders rows where `cursor_y + row_height > scroll_y` and `cursor_y < scroll_y + scissor_h`), `stat_bar` (label + filled rect proportional to value/max), `badge` (colored pill with text). |
| 2.3 | `views/ComponentRenderer.lua` | Add `ComponentRenderer.hitTest(components, mx, my, scroll_y)` — walks the same component tree, returns the first `button` or `list` item whose screen rect contains `(mx, my - scroll_y)`. Returns `{ component, data }` or nil. This replaces all layout_cache click detection in UIController. |
| 2.4 | `views/Panel.lua` | Update `Panel:draw(game)` — call active tab's `build(game)` if dirty, store result as `self._components`. Call `ComponentRenderer.draw(self._components, ...)` in the content area. Store returned `total_h` for scroll clamping. |
| 2.5 | `views/Panel.lua` | Update `Panel:handleMouseDown(x, y)` — after tab bar hit test, call `ComponentRenderer.hitTest` on active tab components. If a `button` is hit, publish `EventBus:publish("ui_action", { id = component.id, data = component.data })`. Return true. |
| 2.6 | `services/EventService.lua` | Add subscription to `"ui_action"`. Dispatch to existing handlers based on `event.id`: `"hire_vehicle"` → existing hire logic, `"buy_client"` → existing client logic, `"assign_trip"` → existing assignment logic, `"purchase_upgrade"` → existing upgrade logic. Keep old named event subscriptions temporarily — remove in Phase 3 once tab builders emit the new event. |
| 2.7 | `views/UIManager.lua` | Remove `layout_cache`, `_doLayout`, `_buildLayoutKey`, `_layout_key`. These are replaced by component trees. Keep `_calculateAccordionStats` and `_calculatePerSecondStats` — stats are still needed, just fed into component descriptors instead of accordion header strings. |
| 2.8 | `controllers/UIController.lua` | Remove all `layout_cache` references, all geometry-reversal click detection, all accordion-specific input. The controller now only routes raw mouse events to `panel:handleMouseDown`, `handleMouseUp`, `handleScroll`. It becomes ~20 lines. |

### Expected Outcome

All four tabs render via component trees. Clicking buttons fires `ui_action` events and all purchases/assignments still work. UIController is gutted to a routing stub. No layout_cache anywhere.

### Testing

- Hire bike, car, truck → all three work via `ui_action`.
- Purchase client → works.
- Open upgrades tab → icons visible, clicking an upgrade opens modal (modal untouched).
- Trips tab → pending trips listed.
- Scroll in vehicles tab with 10+ vehicles → list virtualizes correctly, no lag.
- No console errors about missing layout_cache keys.

---

## Phase 3 — Tab Content Builders

**Goal:** Replace the temporary scaffolding tab builds (which called old imperative draw functions) with real `build(game)` functions that return proper component trees. Each tab is now a self-contained module. Delete the old panel view files.

### Tasks

| # | File | Change |
|---|------|--------|
| 3.1 | `views/tabs/VehiclesTab.lua` (new) | `VehiclesTab.build(game)` returns component tree. Top section: for each `game.C.VEHICLES` entry — a `row` with hire button (`{ type="button", id="hire_vehicle", data={vehicle_type=id}, label="Hire "..vcfg.display_name, icon=vcfg.icon }`) and cost badge. Below: a `list` of all vehicles, each row showing icon + id + state name + capacity fraction. Each row has `id="select_vehicle"` and `data={vehicle_id=v.id}`. Dirty when vehicle count or states change. |
| 3.2 | `views/tabs/TripsTab.lua` (new) | `TripsTab.build(game)` returns a `list` of pending trips. Each row: origin district badge, destination badge, bonus bar (stat_bar with current/max bonus), assigned vehicle icon if any. Row has `id="select_trip"` and `data={trip_index=i}`. Hovering a row fires `ui_action` with `id="hover_trip"` — GameView listens and highlights the trip path. Dirty when trip count or bonus values change. |
| 3.3 | `views/tabs/ClientsTab.lua` (new) | `ClientsTab.build(game)` returns: a button `{ id="buy_client", label="Market for New Client" }` with cost badge, then a `list` of clients showing district, trip generation rate if visible. Dirty when client count changes. |
| 3.4 | `views/tabs/UpgradesTab.lua` (new) | `UpgradesTab.build(game)` returns: for each upgrade category — a `section` with collapsible=false, children being a `row` of `button` components per upgrade icon. Clicking an upgrade button fires `ui_action { id="open_upgrade_modal", data={upgrade_id=...} }`. Modal manager handles that event as before. |
| 3.5 | `views/UIManager.lua` | Register the four new tab builders. Remove the temporary scaffolding build functions from Phase 1. |
| 3.6 | `views/components/VehiclesPanelView.lua` | Delete. |
| 3.7 | `views/components/TripsPanelView.lua` | Delete. |
| 3.8 | `views/components/ClientsPanelView.lua` | Delete. |
| 3.9 | `views/components/UpgradesPanelView.lua` | Delete. |
| 3.10 | `views/components/Accordion.lua` | Delete. |
| 3.11 | `views/UIView.lua` | Remove all accordion and per-panel references. The entire sidebar draw is now `panel:draw(game)` plus the stats header row at the top (money/income/rate). |

### Expected Outcome

All four tabs are built from real component trees. Each tab module has no knowledge of other tabs. Adding a new tab means creating a new file and registering it — no other changes.

### Testing

- All tabs display correct live data.
- Vehicle rows show current state (Idle/Delivering/Returning).
- Trip rows show bonus decay visually.
- Client list shows all clients.
- Upgrade grid renders all categories and icons.
- Buying upgrades still opens modal correctly.

---

## Phase 4 — Clickable Vehicle List + Map Selection

**Goal:** Clicking a vehicle row in the Vehicles tab selects it. The selected vehicle is highlighted on the map. Clicking a vehicle on the map also selects it and switches to the Vehicles tab. A selected vehicle detail section expands below the list — showing its current trip, path, cargo, and an "Unassign" button.

### Tasks

| # | File | Change |
|---|------|--------|
| 4.1 | `views/tabs/VehiclesTab.lua` | When `game.entities.selected_vehicle` is set, render a `section` at top of tab: "Selected: {icon} {id}" header, children = `label` for state, `stat_bar` for cargo capacity, `label` for current destination if en-route, `button { id="unassign_vehicle" }`. The section is only rendered when a vehicle is selected. |
| 4.2 | `services/EventService.lua` | Subscribe `"ui_action"` where `id == "select_vehicle"` → set `game.entities.selected_vehicle` to the vehicle matching `data.vehicle_id`. Subscribe `id == "unassign_vehicle"` → call unassign logic on selected vehicle (return trip to pending, set vehicle Idle). |
| 4.3 | `views/tabs/VehiclesTab.lua` | Selected vehicle row renders with a distinct background color. Pass `selected = (v.id == selected_vehicle_id)` flag into the row component's `style` field — ComponentRenderer highlights it. |
| 4.4 | `controllers/InputController.lua` | In `handle_mouse_down` world-click path: when `entities:handle_click` returns a vehicle, also call `panel:setActiveTab("vehicles")` and mark VehiclesTab dirty so the selected vehicle section appears immediately. |
| 4.5 | `views/GameView.lua` | When a vehicle is selected, draw a circle or highlight ring around its pixel position. Read from `game.entities.selected_vehicle`. This is the only GameView change — one conditional draw, no structural changes. |
| 4.6 | `controllers/UIController.lua` | In `handleMouseDown`, when `ui_action { id="select_trip" }` fires: if `game.entities.selected_vehicle` is set, attempt assignment immediately (publish `ui_action { id="assign_trip", data={trip_index=...} }`). This replaces the old two-gesture assignment flow. |

### Expected Outcome

Clicking any vehicle row selects it and shows a detail section. Clicking the vehicle on the map does the same and switches to Vehicles tab. Clicking a trip row when a vehicle is selected assigns immediately. Vehicle is highlighted on map.

### Testing

- Click vehicle in list → selected, detail section appears, map highlights vehicle.
- Click vehicle on map → same result, tab switches.
- Cycle through overlapping vehicles on map with repeated clicks → selection cycles correctly.
- With vehicle selected, click a trip row → trip assigned, vehicle departs.
- Click "Unassign" → trip returns to pending, vehicle goes Idle.
- Deselect by clicking empty map area → no vehicle selected, detail section gone.

---

## Phase 5 — HUD Strip + Information Feed

**Goal:** Add a persistent HUD strip of overlay toggle buttons along the right edge of the world view. Add an information feed (event log) in the bottom-left of the world view showing recent notable events. Both are registered by game systems, not hardcoded.

### Tasks

| # | File | Change |
|---|------|--------|
| 5.1 | `views/HUDStrip.lua` (new) | `HUDStrip` class. `registerOverlay(def)` where def = `{ id, icon, tooltip, key, locked }`. `draw(game)` — renders a vertical column of small square buttons along the right edge of the world view (left side of sidebar). Active overlays are highlighted. `handleMouseDown(x,y)` — hit test, publishes `EventBus:publish("ui_action", { id="toggle_overlay", data={overlay_id=...} })`. |
| 5.2 | `views/HUDStrip.lua` | `handleKey(key)` — if any registered overlay has `key == key`, fire toggle. This replaces the current hardcoded debug key handlers for player-facing overlays (not F3/F4 dev tools). |
| 5.3 | `services/EventService.lua` | Subscribe `"ui_action"` where `id == "toggle_overlay"` → look up overlay id in a registry, flip its active flag, publish `"overlay_changed"` with `{ id, active }`. GameView subscribes to `overlay_changed` and toggles the relevant draw flag. |
| 5.4 | `views/InformationFeed.lua` (new) | `InformationFeed` class. `push(entry)` where entry = `{ text, icon, color, timestamp }`. `draw(game)` — renders last N entries bottom-to-top in bottom-left of world view. Entries fade after 6 seconds. Max 5 visible. `update(dt)` — ages entries out. |
| 5.5 | `views/InformationFeed.lua` | `InformationFeed` subscribes to `EventBus` events: `"trip_completed"` → push green entry, `"vehicle_stuck"` → push yellow entry, `"client_added"` → push entry. Game systems already publish these events (or should — add publish calls where missing). |
| 5.6 | `main.lua` | Instantiate `HUDStrip` and `InformationFeed`. Register initial overlays: vehicle paths, district boundaries. Wire `HUDStrip` into input routing after world-click handling. Wire `InformationFeed.update(dt)` into game update loop. Wire both draws into the draw order after GameView. |
| 5.7 | `controllers/InputController.lua` | Remove hardcoded player-facing overlay key handlers (e.g. current T, G, M key toggles if they exist for player overlays). Route those keys through HUDStrip instead. Keep F3/F4/debug keys as-is. |

### Expected Outcome

Overlay toggles live in the HUD strip, not the keyboard. Notable events appear in the feed with color coding. Feed fades cleanly. The keyboard is no longer the primary way to control player-facing overlays.

### Testing

- Click HUD overlay button → overlay toggles on map.
- Keyboard shortcut for same overlay → same toggle.
- Complete a delivery → feed shows green "+$NNN" entry, fades after ~6 seconds.
- Vehicle gets stuck → yellow warning entry appears.
- Register a new overlay from a game system → appears in HUD strip automatically.
- Locked overlay → dimmed, unclickable.

---

## What Gets Deleted

| File | Reason |
|------|--------|
| `views/components/Accordion.lua` | Replaced by tab system |
| `views/components/VehiclesPanelView.lua` | Replaced by VehiclesTab |
| `views/components/TripsPanelView.lua` | Replaced by TripsTab |
| `views/components/ClientsPanelView.lua` | Replaced by ClientsTab |
| `views/components/UpgradesPanelView.lua` | Replaced by UpgradesTab |
| `views/UIManager.lua` `layout_cache` | Replaced by component trees |
| `views/UIManager.lua` `_doLayout` | Replaced by ComponentRenderer |
| `views/UIManager.lua` `_buildLayoutKey` | No longer needed |
| Named UI events (`ui_buy_vehicle_clicked` etc.) | Replaced by `ui_action` with id |

## What Does Not Change

| File | Reason |
|------|--------|
| `views/GameView.lua` | World rendering is untouched beyond the selected vehicle highlight in Phase 4 |
| `views/components/Modal.lua` | Upgrade modal stays as-is — it works |
| `models/AutoDispatcher.lua` | No UI changes |
| `services/TripEligibilityService.lua` | No UI changes |
| `lib/pathfinder.lua` | No UI changes |
| All map / world generation files | No UI changes |
| `core/event_bus.lua` | No changes |

---

## Critical Files

| File | Phase |
|------|-------|
| `views/Panel.lua` | 1 (new) |
| `views/ComponentRenderer.lua` | 2 (new) |
| `views/tabs/VehiclesTab.lua` | 3 (new) |
| `views/tabs/TripsTab.lua` | 3 (new) |
| `views/tabs/ClientsTab.lua` | 3 (new) |
| `views/tabs/UpgradesTab.lua` | 3 (new) |
| `views/HUDStrip.lua` | 5 (new) |
| `views/InformationFeed.lua` | 5 (new) |
| `views/UIManager.lua` | 1, 2, 3 (gutted progressively) |
| `views/UIView.lua` | 1, 3 (simplified progressively) |
| `controllers/UIController.lua` | 2 (gutted to routing stub) |
| `services/EventService.lua` | 2, 4, 5 |
| `main.lua` | 1, 5 |
