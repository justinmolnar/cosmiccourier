# Multi-Modal Transport & Infrastructure Refactor

This document outlines the architectural shift from a road-centric system to a **mode-agnostic, data-driven infrastructure** model. The goal is to allow the addition of new transport modes (Ships, Trains, Planes) by adding JSON data files with minimal changes to core logic.

## 1. Core Architectural Generalization

### 1.1 Mode-Keyed Trunks (Inter-city HPA*)
Currently, the system uses `game.hw_city_edges` for inter-city highway routing. This will be refactored into a unified `game.trunks` map.
*   **Structure**: `game.trunks[mode] = { city_a = { city_b = { path = {...} }, ... } }`
*   **Modes**: `road` (Highways), `water` (Shiplines), `rail` (Railway).
*   **Pathfinding**: `PathfindingService` will look up the trunk map corresponding to the vehicle's `transport_mode`.

### 1.2 Data-Driven Building Registry
Infrastructure types like "Docks" or "Stations" will be defined in a new `data/buildings.json` registry.
*   **Definition Schema**:
    ```json
    {
      "id": "dock",
      "display_name": "Cargo Dock",
      "serves": "water",
      "placement_rules": ["adjacent_to_water"],
      "is_transfer_hub": true
    }
    ```
*   **Placement Logic**: The build tool will validate the `placement_rules` against the tile map before allowing a click.
*   **Automatic Trunking**: When two buildings of the same `serves` type are connected, the `InfrastructureService` will automatically calculate a pre-computed "Trunk" path between them using the specified mode's pathfinding costs.

### 1.3 Mode-Blind Pathfinding
The `PathfindingService` will be updated to be strictly cost-table driven:
*   **Snapping**: `_snapToNearestTraversable` will BFS for the nearest tile that has a cost `< IMPASSABLE` for the vehicle's specific `transport_mode` (e.g., a ship snaps to water, a truck snaps to road).
*   **Traversability**: The "Street Adjacency" cheat will be restricted to the `road` mode, ensuring ships and planes stay on their designated logical layers.

---

## 2. The "Boat MVP" Implementation

The first validation of this refactor will be the **Maritime Mode**.

### Step 1: Data Definitions
*   **`data/vehicles/ship.json`**: Define the ship with `transport_mode: "water"` and costs (Water=1, Land=9999).
*   **`data/buildings.json`**: Define the `dock` with `placement: "adjacent_to_water"`.

### Step 2: Handoff Workflow (User-Driven)
The MVP uses the existing state machine and rule engine to facilitate a 3-leg journey:
1.  **Leg 1 (Road)**: Truck picks up package $\rightarrow$ Drops at **Dock A**.
    *   *Rule*: `If trip.scope == "continent" then send_to("Dock_A")`
2.  **Leg 2 (Water)**: Ship picks up package at **Dock A** $\rightarrow$ Follows logical **Shipline** (Trunk) $\rightarrow$ Drops at **Dock B**.
    *   *Rule*: `If trip.at == "Dock_A" and trip.scope == "continent" then assign_to("ship")`
3.  **Leg 3 (Road)**: Local Van picks up package at **Dock B** $\rightarrow$ Delivers to final address.
    *   *Rule*: `If trip.at == "Dock_B" then assign_to("van")`

### Step 3: Trunk Generation
When the player builds **Dock B**, the system triggers a one-time water-based A* between Dock A and Dock B, saving it to `game.trunks.water`. This path is invisible but acts as the high-speed "highway" for all ships traveling between those hubs.

---

## 3. Future Expandability
By maintaining this decoupled, data-first approach:
*   **Trains**: Added via `train.json` and `station` (placement rule: `on_rail`).
*   **Planes**: Added via `plane.json` and `airport` (static district placement).
*   **Logic**: The code remains MVC-compliant and portable, with the "How" of routing living entirely in the user's Dispatch Rules.
