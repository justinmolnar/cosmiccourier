-- services/BuildingService.lua
-- Data-driven building placement and trunk generation.
-- Adding a new transport mode requires only a new data/buildings/*.json file.
-- Core logic here is completely mode-agnostic.

local PathCacheService = require("services.PathCacheService")

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
-- Writes to game.trunks[mode] bidirectionally and primes PathCacheService.
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

    if not game.trunks then game.trunks = {} end
    if not game.trunks[mode] then game.trunks[mode] = {} end

    -- Forward direction
    if not game.trunks[mode][city_a] then game.trunks[mode][city_a] = {} end
    game.trunks[mode][city_a][city_b] = {
        from = {ux=ax, uy=ay},
        to   = {ux=bx, uy=by},
    }

    -- Reverse direction
    local rev = {}
    for i = #path, 1, -1 do rev[#rev+1] = path[i] end
    if not game.trunks[mode][city_b] then game.trunks[mode][city_b] = {} end
    game.trunks[mode][city_b][city_a] = {
        from = {ux=bx, uy=by},
        to   = {ux=ax, uy=ay},
    }

    -- Prime path cache so PathfindingService finds the trunk without re-running A*.
    PathCacheService.put(mode, ax, ay, bx, by, path)
    PathCacheService.put(mode, bx, by, ax, ay, rev)
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

    local mode_hubs = game.trunk_hubs and game.trunk_hubs[mode]
    if not mode_hubs then return end

    for other_city, hubs in pairs(mode_hubs) do
        if other_city ~= city_idx and hubs and #hubs > 0 then
            local hub_b = hubs[1]
            _buildTrunk(mode, gx, gy, city_idx,
                        hub_b.ux, hub_b.uy, other_city,
                        costs_table, turn_costs, game)
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

-- Place a building at unified sub-cell (gx, gy) in city city_idx.
-- Registers the building, updates trunk_hubs, and generates any new trunks.
function BuildingService.place(building_cfg, gx, gy, city_idx, game)
    local mode = building_cfg.serves

    -- Register in game.buildings
    if not game.buildings then game.buildings = {} end
    if not game.buildings[city_idx] then game.buildings[city_idx] = {} end
    table.insert(game.buildings[city_idx], {
        cfg      = building_cfg,
        x        = gx,
        y        = gy,
        city     = city_idx,
        cargo    = {},
        capacity = building_cfg.capacity,
    })

    -- Register as trunk hub for this mode.
    -- Snap to nearest water cell so pathfinding can route to a traversable tile.
    local umap = game.maps and game.maps.unified
    local hx, hy = gx, gy
    if umap and umap.ffi_grid then
        hx, hy = _snapToWaterCell(gx, gy, umap.ffi_grid, umap._w, umap._h)
    end
    if not game.trunk_hubs then game.trunk_hubs = {} end
    if not game.trunk_hubs[mode] then game.trunk_hubs[mode] = {} end
    if not game.trunk_hubs[mode][city_idx] then game.trunk_hubs[mode][city_idx] = {} end
    table.insert(game.trunk_hubs[mode][city_idx], {ux=hx, uy=hy, key=hy*10000+hx})

    -- Generate trunks to all other cities that already have a hub of this mode.
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
