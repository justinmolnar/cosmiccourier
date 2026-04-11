-- models/Entrance.lua
-- Pure data container for an inter-city connection point.
-- An entrance is anything cargo can traverse a mode-specific trunk through:
-- highway attachment nodes, docks, train yards, airports, etc. — all the same
-- abstraction. The pathfinder does not care which kind.
--
-- This file has no service requires and mutates no game state.

local Entrance = {}

-- Deterministic string key: "road_c3_47_29"
function Entrance.makeId(mode, city_idx, ux, uy)
    return string.format("%s_c%d_%d_%d", mode, city_idx, ux, uy)
end

-- Constructor. Returns a plain table — no metatables, no behaviour.
function Entrance.new(mode, city_idx, ux, uy, building_ref)
    return {
        id       = Entrance.makeId(mode, city_idx, ux, uy),
        mode     = mode,
        city_idx = city_idx,
        ux       = ux,
        uy       = uy,
        building = building_ref,  -- ref to game.buildings entry, or nil for auto-generated
    }
end

return Entrance
