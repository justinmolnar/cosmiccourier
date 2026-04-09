# Architectural Audit Report — April 8, 2026

## Executive Summary
The Cosmic Courier codebase is functional but suffers from significant architectural "gravity" centered around several massive God Objects and a global state pattern. While the previous audit (March 2026) identified these trends, several components have since ballooned in size, creating a high risk for technical debt and making the engine difficult to expand or port.

---

## 1. Top Critical Issues

### 1.1 God Objects (The "3000-Line Club")
Two files have grown beyond manageable limits, violating the Single Responsibility Principle:
*   **`controllers/WorldSandboxController.lua` (~3,750 lines)**: Acts as a monolithic hub for terrain generation, WFC coordination, input handling, and state management. This is the single biggest bottleneck for maintainability.
*   **`views/tabs/DispatchTab.lua` (~2,420 lines)**: A View component that is performing heavy logic lifting, likely including complex filtering and rule evaluation that belongs in a Service or Model.

### 1.2 Non-Agnostic Rendering (MVC Leakage)
The codebase is tightly coupled to the Love2D framework in layers where it should be agnostic:
*   **`models/vehicles/Vehicle.lua`**: Contains direct `love.graphics` calls.
*   **`models/Map.lua`**: Contains direct `love.graphics` calls.
*   **Impact**: You cannot run the game logic "headless" (e.g., for a server or unit tests) without loading the entire Love2D graphics module or heavily mocking it.

### 1.3 Global State Coupling
The `Game` global object is used as a "blackboard" where Views, Models, and Controllers all read and write freely.
*   **Violation**: `views/GameView.lua` directly modifies state on the `Game` object.
*   **Impact**: State changes are difficult to trace, and components cannot be tested in isolation.

---

## 2. Expandability & Scalability

### 2.1 Hardcoded Branching
Expansion of the game world (new biomes, road types, or vehicle classes) is currently hindered by string-based logic branching:
*   **Example**: `if type == "city" then ...` is scattered across services rather than using a Registry or Strategy pattern.
*   **Recommendation**: Move these into the existing JSON data files and use a data-driven factory to instantiate behaviors.

### 2.2 Dispatcher System Brittleness
The `dispatch_*.lua` system (e.g., `dispatch_blocks.lua`) relies on hardcoded property names. Adding a new property to a block or vehicle requires manual updates to the dispatcher's evaluation logic rather than being automatically discovered.

---

## 3. Comparison with March 2026 Audit
| Metric | March 2026 | April 2026 | Trend |
|--------|------------|------------|-------|
| Largest File | `RoadSmoother.lua` (972 lines) | `WorldSandboxController.lua` (3,750 lines) | 🚩 Extreme Growth |
| God Functions | 16 | 25+ | 🚩 Degrading |
| MVC Violations | 20+ | 30+ | 🚩 Degrading |

---

## 4. Recommended Action Plan (High Priority)
1.  **Decouple Vehicle/Map Rendering**: Move `love.graphics` calls into a dedicated `VehicleRenderer` and `MapRenderer` in the `views/` directory.
2.  **Fragment WorldSandboxController**: Extract terrain logic into `WorldGenService` and WFC logic into `WfcService`.
3.  **Data-Driven Dispatcher**: Refactor the dispatcher to use a registry of properties rather than hardcoded string checks.
4.  **Formalize the Controller Layer**: Prevent Views from writing to the `Game` global; enforce that all state mutations go through a Controller method.
