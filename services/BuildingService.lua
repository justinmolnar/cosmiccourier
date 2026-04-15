-- services/BuildingService.lua
-- Data-driven building placement and trunk generation.
-- Adding a new transport mode requires only a new data/buildings/*.json file.
-- Core logic here is completely mode-agnostic.

local PathCacheService      = require("services.PathCacheService")
local EntranceService       = require("services.EntranceService")
local EntranceGraphService  = require("services.EntranceGraphService")
local Entrance              = require("models.Entrance")

local BuildingService = {}

-- Integer → tile name, matches all other _TILE_NAMES tables in the codebase.
local _TILE_NAMES = {
    [0]="grass", [1]="road", [2]="downtown_road", [3]="arterial", [4]="highway",
    [5]="water",  [6]="mountain", [7]="river", [8]="plot", [9]="downtown_plot",
    [10]="coastal_water", [11]="deep_water", [12]="open_ocean",
}

-- ── Placement validators ──────────────────────────────────────────────────────
-- Each entry: function(gx, gy, umap) → bool
-- New placement rules can be added here without touching any other file.
local _WATER_TYPES = {[5]=true,[10]=true,[11]=true,[12]=true}

local _validators = {
    -- At least one cardinal neighbour must be a water tile.
    adjacent_to_water = function(gx, gy, umap)
        if not umap or not umap.ffi_grid then return false end
        local fg  = umap.ffi_grid
        local fgw = umap._w
        local fgh = umap._h
        for _, d in ipairs({{0,-1},{0,1},{-1,0},{1,0}}) do
            local nx, ny = gx + d[1], gy + d[2]
            if nx >= 1 and nx <= fgw and ny >= 1 and ny <= fgh then
                if _WATER_TYPES[fg[(ny-1)*fgw+(nx-1)].type] then return true end
            end
        end
        return false
    end,
}

-- ── Water snapping (private) ──────────────────────────────────────────────────

-- Returns the nearest water-type sub-cell to (gx, gy): itself if already water,
-- else the first cardinal neighbour that is water, else the original coords.
-- Used to push dock-tile endpoints onto traversable water before A*.
local function _snapToWaterCell(gx, gy, fg, fgw, fgh)
    if fg[(gy-1)*fgw+(gx-1)] and _WATER_TYPES[fg[(gy-1)*fgw+(gx-1)].type] then
        return gx, gy
    end
    for _, d in ipairs({{0,-1},{0,1},{-1,0},{1,0}}) do
        local nx, ny = gx + d[1], gy + d[2]
        if nx >= 1 and nx <= fgw and ny >= 1 and ny <= fgh then
            if _WATER_TYPES[fg[(ny-1)*fgw+(nx-1)].type] then return nx, ny end
        end
    end
    return gx, gy  -- no adjacent water (placement validator should have caught this)
end

-- ── Trunk generation (private) ────────────────────────────────────────────────

-- Find the pathfinding cost table from the first vehicle whose transport_mode
-- matches `mode`. Used as the cost function for trunk generation A*.
local function _vehicleCostsForMode(mode, game)
    for _, vcfg in pairs(game.C.VEHICLES) do
        if vcfg.transport_mode == mode then
            return vcfg.pathfinding_costs
        end
    end
    return nil
end

-- Build and cache a trunk path between two hub positions using direction-aware A*.
-- Primes PathCacheService with the computed path and registers a trunk edge
-- in the entrance graph between the two matching entrances.
local function _buildTrunk(mode, ax, ay, city_a, bx, by, city_b,
                           costs_table, turn_costs, game)
    local umap = game.maps and game.maps.unified
    if not umap or not umap.ffi_grid then return end

    local fg       = umap.ffi_grid
    local fgw      = umap._w
    local fgh      = umap._h
    local IMPASSABLE = 9999

    -- Snap both endpoints to their nearest water cell so A* starts and ends
    -- on traversable tiles (dock tiles themselves are land plots).
    ax, ay = _snapToWaterCell(ax, ay, fg, fgw, fgh)
    bx, by = _snapToWaterCell(bx, by, fg, fgw, fgh)
    if ax == bx and ay == by then return end  -- same water entry, no trunk needed

    local function cost_fn(x, y)
        local ti = fg[(y-1)*fgw+(x-1)].type
        local tn = _TILE_NAMES[ti] or "grass"
        return costs_table[tn] or IMPASSABLE
    end

    local path = game.pathfinder.findPath(
        {}, {x=ax,y=ay}, {x=bx,y=by}, cost_fn, umap, turn_costs)

    if not path then
        print(string.format(
            "BuildingService: no %s trunk city%d→city%d (%d,%d)→(%d,%d)",
            mode, city_a, city_b, ax, ay, bx, by))
        return
    end

    -- Prime path cache so PathfindingService finds the trunk without re-running A*.
    local rev = {}
    for i = #path, 1, -1 do rev[#rev+1] = path[i] end
    PathCacheService.put(mode, ax, ay, bx, by, path)
    PathCacheService.put(mode, bx, by, ax, ay, rev)

    -- Register trunk edge in the entrance graph. The actual path length is
    -- known here (water trunks route around land) so we pass it through for
    -- an accurate cost estimate.
    local id_a = Entrance.makeId(mode, city_a, ax, ay)
    local id_b = Entrance.makeId(mode, city_b, bx, by)
    EntranceGraphService.addTrunkEdge(id_a, id_b, mode, game, #path)
end

-- After placing a new hub, generate trunks to all existing hubs of the same
-- mode in other cities.
local function _generateTrunksForNewHub(building_cfg, gx, gy, city_idx, mode, game)
    local costs_table = _vehicleCostsForMode(mode, game)
    if not costs_table then
        -- No vehicle registered for this mode yet. Trunks will be generated
        -- when the player places the next dock (after ship.json is active).
        return
    end

    local turn_costs = building_cfg.trunk_turn_costs  -- e.g. {turn_90=8, turn_180=999}

    -- One trunk per other city that already has an entrance of this mode.
    -- Picks the first registered entrance in each target city (stable order).
    if not game.entrances_by_city then return end
    for other_city, list in pairs(game.entrances_by_city) do
        if other_city ~= city_idx then
            for _, other in ipairs(list) do
                if other.mode == mode then
                    _buildTrunk(mode, gx, gy, city_idx,
                                other.ux, other.uy, other_city,
                                costs_table, turn_costs, game)
                    break
                end
            end
        end
    end
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Returns true if building_cfg can be placed at unified sub-cell (gx, gy).
function BuildingService.canPlace(building_cfg, gx, gy, umap)
    local rule      = building_cfg.placement_rule
    local validator = rule and _validators[rule]
    if not validator then return false end
    return validator(gx, gy, umap)
end

-- ─── Serialization (data-driven) ─────────────────────────────────────────────
-- Buildings are plain tables (not class instances). Persist everything on
-- each building record EXCEPT transients; `cfg` is a table ref so it's
-- flattened to `cfg_id`. Adding new data fields to the `building_ref` in
-- BuildingService.place ships them automatically.

local BUILDING_TRANSIENTS = {
    cfg      = true, -- replaced by cfg_id below
    city     = true, -- identity info; serialize keeps it as `city_idx`
}
local BUILDING_REFS = {
    cargo = { kind = "uid", list = true },
}

local AutoSerializer = require("services.AutoSerializer")

function BuildingService.serializeAll(game)
    local out = {}
    for city_idx, blist in pairs(game.buildings or {}) do
        for _, b in ipairs(blist) do
            local rec = AutoSerializer.serialize(b, BUILDING_TRANSIENTS, BUILDING_REFS)
            rec.cfg_id   = b.cfg and b.cfg.id or nil
            rec.city_idx = city_idx
            table.insert(out, rec)
        end
    end
    return out
end

function BuildingService.restoreAll(game, data, trips_by_uid)
    game.buildings = {}
    for _, rec in ipairs(data or {}) do
        local cfg = game.C.BUILDINGS and game.C.BUILDINGS[rec.cfg_id]
        if cfg then
            BuildingService.place(cfg, rec.x, rec.y, rec.city_idx, game)
            local blist = game.buildings[rec.city_idx]
            local ref = blist and blist[#blist]
            if ref then
                local function resolver(kind, id)
                    if kind == "uid" then return trips_by_uid[id] end
                end
                AutoSerializer.apply(ref, rec, BUILDING_REFS, resolver)
            end
        end
    end
end

-- Place a building at unified sub-cell (gx, gy) in city city_idx.
-- Registers the building as an entrance and generates any new trunks.
function BuildingService.place(building_cfg, gx, gy, city_idx, game)
    local mode = building_cfg.serves

    -- Register in game.buildings
    if not game.buildings then game.buildings = {} end
    if not game.buildings[city_idx] then game.buildings[city_idx] = {} end
    local building_ref = {
        cfg      = building_cfg,
        x        = gx,
        y        = gy,
        city     = city_idx,
        cargo    = {},
        capacity = building_cfg.capacity,
    }
    table.insert(game.buildings[city_idx], building_ref)

    -- Register as an entrance for this mode.
    -- Snap to nearest water cell so pathfinding can route to a traversable tile.
    local umap = game.maps and game.maps.unified
    local hx, hy = gx, gy
    if umap and umap.ffi_grid then
        hx, hy = _snapToWaterCell(gx, gy, umap.ffi_grid, umap._w, umap._h)
    end
    local new_entrance = EntranceService.register(mode, city_idx, hx, hy, building_ref, game)

    -- Add intra-city and transfer edges for the new entrance (does not
    -- require a full graph rebuild).
    EntranceGraphService.addEdgesForEntrance(new_entrance.id, game)

    -- Generate trunks to all other cities that already have an entrance of this mode.
    -- _buildTrunk also registers trunk edges in the entrance graph.
    if building_cfg.is_transfer_hub then
        _generateTrunksForNewHub(building_cfg, gx, gy, city_idx, mode, game)
    end
end

-- Returns all buildings of a given mode placed in any city.
-- Used by dispatch and pathfinding to locate hubs.
function BuildingService.getHubsForMode(mode, game)
    local result = {}
    if not game.buildings then return result end
    for _, city_buildings in pairs(game.buildings) do
        for _, b in ipairs(city_buildings) do
            if b.cfg.serves == mode and b.cfg.is_transfer_hub then
                result[#result+1] = b
            end
        end
    end
    return result
end

-- ── Building iteration ────────────────────────────────────────────────────────

-- Single source of truth for "all buildings in the game." Every function that
-- needs to scan buildings calls this, so adding a new building storage location
-- requires only one update here.
-- Each building has at minimum: cargo (table), capacity (number),
-- and a position (either .plot.x/.plot.y for depots/clients, or .x/.y for placed).
function BuildingService.allBuildings(game)
    local result = {}
    for _, d in ipairs(game.entities and game.entities.depots or {}) do
        result[#result+1] = d
    end
    for _, c in ipairs(game.entities and game.entities.clients or {}) do
        result[#result+1] = c
    end
    for _, city_buildings in pairs(game.buildings or {}) do
        for _, b in ipairs(city_buildings) do
            result[#result+1] = b
        end
    end
    return result
end

-- Normalised position for any building type.
local function _buildingPos(b)
    if b.plot then return b.plot.x, b.plot.y end
    return b.x, b.y
end

-- ── Cargo helpers ─────────────────────────────────────────────────────────────

-- Returns the building at unified sub-cell (gx, gy), or nil.
function BuildingService.findAtPlot(gx, gy, game)
    for _, b in ipairs(BuildingService.allBuildings(game)) do
        local bx, by = _buildingPos(b)
        if bx == gx and by == gy then return b end
    end
    return nil
end

-- Deposit a trip into a building's cargo. Freezes the trip (timer keeps ticking
-- via the freeze/thaw elapsed-time mechanism). Returns true on success.
-- `game` is optional — when provided, publishes a "trip_deposited" event.
function BuildingService.depositTrip(building, trip, game)
    if not building.cargo then building.cargo = {} end
    local cap = building.capacity
    if cap and #building.cargo >= cap then return false end
    -- Update the trip's pickup to this building so the next vehicle knows where
    -- to collect it from (not the original client position).
    local bx, by = _buildingPos(building)
    local leg = trip.legs and trip.legs[trip.current_leg]
    if leg then
        leg.start_plot = { x = bx, y = by }
    end

    trip:freeze()
    table.insert(building.cargo, trip)
    if game then
        local RE = require("services.DispatchRuleEngine")
        RE.fireEvent(game.state and game.state.dispatch_rules or {}, "trip_deposited",
            { building = building, trip = trip, game = game })
    end
    return true
end

-- Withdraw a specific trip from a building's cargo. Thaws the trip (calculates
-- elapsed decay). Returns true if found and removed.
function BuildingService.withdrawTrip(building, trip)
    if not building.cargo then return false end
    for i, t in ipairs(building.cargo) do
        if t == trip then
            table.remove(building.cargo, i)
            trip:thaw()
            return true
        end
    end
    return false
end

-- Search all buildings for a trip and withdraw it. Used by dispatch when the
-- caller doesn't know which building holds the trip.
function BuildingService.withdrawTripFromAny(trip, game)
    for _, b in ipairs(BuildingService.allBuildings(game)) do
        if BuildingService.withdrawTrip(b, trip) then return true end
    end
    return false
end

return BuildingService
