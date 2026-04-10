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
        cfg  = building_cfg,
        x    = gx,
        y    = gy,
        city = city_idx,
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

return BuildingService
