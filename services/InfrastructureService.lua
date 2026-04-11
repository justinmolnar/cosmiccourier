-- services/InfrastructureService.lua
-- Atomic world mutation for player-built infrastructure.
-- Keeps ffi_grid, world_highway_map, HPA* hierarchy, and render cache in sync.

local InfrastructureService = {}

local DIRS4 = {{1,0},{-1,0},{0,1},{0,-1}}

-- ── Coordinate helpers ────────────────────────────────────────────────────────

-- Returns the tile type (integer) of the centre sub-cell of world cell (wx, wy).
function InfrastructureService.getWorldCell(wx, wy, game)
    local umap = game.maps and game.maps.unified
    if not umap then return nil end
    local fgi = umap.ffi_grid
    local uw  = umap._w
    -- centre sub-cell of world cell (wx,wy)
    local ux = (wx - 1) * 3 + 2   -- 1-based centre
    local uy = (wy - 1) * 3 + 2
    if ux < 1 or uy < 1 or ux > uw or uy > umap._h then return nil end
    return fgi[(uy - 1) * uw + (ux - 1)].type
end

-- Returns true if world cell (wx,wy) is inside any city's map bounds.
function InfrastructureService.isCityCell(wx, wy, game)
    for _, cmap in ipairs(game.maps.all_cities or {}) do
        local ox  = cmap.world_mn_x or 1
        local oy  = cmap.world_mn_y or 1
        local cw  = math.ceil((cmap.city_grid_width  or 0) / 3)
        local ch  = math.ceil((cmap.city_grid_height or 0) / 3)
        if wx >= ox and wx < ox + cw and wy >= oy and wy < oy + ch then
            return true
        end
    end
    return false
end

-- Finds the first map in game.maps that has world_biome_data, returns (bdata, world_w).
local function _getBiomeData(game)
    local am = game.maps and game.maps[game.active_map_key]
    if am and am.world_biome_data then return am.world_biome_data, am.world_w or 1 end
    for _, m in pairs(game.maps or {}) do
        if type(m) == "table" and m.world_biome_data then
            return m.world_biome_data, m.world_w or 1
        end
    end
    return nil, 1
end

-- Cost multipliers by biome name (exact names from data/biomes.lua Biomes.getName).
-- math.huge = truly impassable.  Rivers are passable (bridge); mountains/ocean are not.
local TERRAIN_COST = {
    -- Easy flat terrain
    ["Grassland"]          = 1.0,
    ["Savanna"]            = 1.0,
    ["Tropical Savanna"]   = 1.0,
    ["Beach"]              = 1.2,
    ["Desert"]             = 1.3,
    ["Semi-arid"]          = 1.3,
    ["Shrubland"]          = 1.3,
    ["Tundra"]             = 1.5,
    -- Forested / vegetated terrain
    ["Woodland"]           = 1.5,
    ["Temp. Forest"]       = 1.8,
    ["Subtropical Forest"] = 1.8,
    ["Tropical Forest"]    = 2.0,
    ["Temp. Rainforest"]   = 2.2,
    ["Jungle"]             = 2.5,
    ["Boreal / Taiga"]     = 2.0,
    -- Highland / hilly terrain (steep but crossable)
    ["Highland"]           = 3.0,
    ["Cold Highland"]      = 3.5,
    ["Boreal Highland"]    = 3.0,
    -- Wetland
    ["Swamp"]              = 3.5,
    ["Tropical Swamp"]     = 3.5,
    -- Water crossings (bridge/causeway)
    ["River"]              = 5.0,
    ["Lake"]               = 8.0,
    -- Impassable mountain terrain (exact names from Biomes.getName)
    ["Mountain Rock"]      = math.huge,
    ["Snow Cap"]           = math.huge,
    ["Frozen Rock"]        = math.huge,
    -- Impassable ocean
    ["Ocean"]              = math.huge,
    ["Deep Ocean"]         = math.huge,
}

-- Returns the build cost multiplier for world cell (wx, wy).
-- math.huge means the cell is impassable and cannot be built through.
-- City cells and ffi_grid-typed non-grass cells also return math.huge.
function InfrastructureService.getTerrainCost(wx, wy, game)
    if InfrastructureService.isCityCell(wx, wy, game) then return math.huge end

    -- ffi_grid belt-and-suspenders: block anything explicitly typed water/mountain/river
    local t = InfrastructureService.getWorldCell(wx, wy, game)
    if t and t ~= 0 and t ~= 4 then return math.huge end

    -- Biome data is the authoritative terrain source for inter-city world cells
    local bdata, world_w = _getBiomeData(game)
    if bdata then
        local bd = bdata[(wy - 1) * world_w + wx]
        if bd then
            local name = bd.name or ""
            local c = TERRAIN_COST[name]
            if c then return c end
            -- Fallback substring check for unlisted variants (e.g. future biome additions)
            if name:find("Ocean") or name:find("Rock") or name:find("Cap") then
                return math.huge
            end
            if bd.is_river then return TERRAIN_COST["River"] end
            if bd.is_lake  then return TERRAIN_COST["Lake"]  end
        end
    end

    return 1.0  -- default: open grass
end

-- Returns true if a highway segment can be built through this world cell.
function InfrastructureService.isPassableForHighway(wx, wy, game)
    return InfrastructureService.getTerrainCost(wx, wy, game) < math.huge
end

-- Returns true if world cell (wx,wy) is already a highway tile.
function InfrastructureService.isHighwayCell(wx, wy, game)
    return InfrastructureService.getWorldCell(wx, wy, game) == 4
end

-- ── Path computation ──────────────────────────────────────────────────────────

-- Returns the nearest passable world cell to (wx, wy) using BFS outward.
-- If (wx, wy) is already passable, returns it unchanged.
local function _snapToPassable(wx, wy, game)
    if InfrastructureService.isPassableForHighway(wx, wy, game) then return wx, wy end
    local ww = game.world_w or 1
    local wh = game.world_h or 1
    local visited = { [(wy - 1) * ww + wx] = true }
    local q = {{wx, wy}}
    local qi = 1
    while qi <= #q do
        local cx, cy = q[qi][1], q[qi][2]; qi = qi + 1
        for _, d in ipairs(DIRS4) do
            local nx, ny = cx + d[1], cy + d[2]
            if nx >= 1 and nx <= ww and ny >= 1 and ny <= wh then
                local nci = (ny - 1) * ww + nx
                if not visited[nci] then
                    visited[nci] = true
                    if InfrastructureService.isPassableForHighway(nx, ny, game) then
                        return nx, ny
                    end
                    q[#q + 1] = {nx, ny}
                end
            end
        end
        if qi > 2000 then break end  -- safety limit: give up after 2000 cells searched
    end
    return wx, wy  -- fall back to original if nothing found nearby
end

-- A* shortest path between two world cells using only 4-directional movement.
-- Intermediate cells must be grass and not inside a city; start/end are exempt
-- (they are highway tiles serving as entry/exit points).
-- Returns an ordered list of {wx, wy} world cells (inclusive of both endpoints),
-- or nil if no path exists.
function InfrastructureService.findPath(x0, y0, x1, y1, game)
    -- Snap impassable destinations to nearest passable cell (e.g. waypoint inside mountain).
    -- Start (x0,y0) is always a highway tile — no snap needed.
    if not InfrastructureService.isHighwayCell(x1, y1, game) then
        x1, y1 = _snapToPassable(x1, y1, game)
    end

    if x0 == x1 and y0 == y1 then return {{wx = x0, wy = y0}} end

    local ww = game.world_w or 1
    local wh = game.world_h or 1

    -- Build fast lookup tables once for this search
    local bdata, bio_ww = _getBiomeData(game)
    local all_claimed = {}
    for _, cmap in ipairs(game.maps.all_cities or {}) do
        local ox = cmap.world_mn_x or 1
        local oy = cmap.world_mn_y or 1
        local cw = math.ceil((cmap.city_grid_width  or 0) / 3)
        local ch = math.ceil((cmap.city_grid_height or 0) / 3)
        for wy2 = oy, oy + ch - 1 do
            for wx2 = ox, ox + cw - 1 do
                all_claimed[(wy2 - 1) * ww + wx2] = true
            end
        end
    end
    local umap = game.maps and game.maps.unified
    local fgi  = umap and umap.ffi_grid
    local uw   = umap and umap._w

    -- Returns the cost multiplier for cell (x,y); math.huge = impassable.
    local function cell_cost(x, y)
        if all_claimed[(y - 1) * ww + x] then return math.huge end
        -- ffi_grid typed non-grass (city edges etc.)
        if fgi and uw then
            local ux2 = (x - 1) * 3 + 2
            local uy2 = (y - 1) * 3 + 2
            if ux2 >= 1 and uy2 >= 1 and ux2 <= uw and uy2 <= (umap._h or 0) then
                local ft = fgi[(uy2 - 1) * uw + (ux2 - 1)].type
                if ft ~= 0 and ft ~= 4 then return math.huge end
            end
        end
        if bdata then
            local bd = bdata[(y - 1) * bio_ww + x]
            if bd then
                local nm = bd.name or ""
                local c = TERRAIN_COST[nm]
                if c then return c end
                if nm:find("Ocean") or nm:find("Rock") or nm:find("Cap") then
                    return math.huge
                end
                if bd.is_river then return TERRAIN_COST["River"] end
                if bd.is_lake  then return TERRAIN_COST["Lake"]  end
            end
        end
        return 1.0
    end

    local function ci(x, y) return (y - 1) * ww + x end
    -- Heuristic: minimum possible cost is 1.0 per cell (admissible)
    local function h(x, y)  return math.abs(x - x1) + math.abs(y - y1) end

    local open     = {{ f = h(x0, y0), g = 0, x = x0, y = y0 }}
    local g_score  = { [ci(x0, y0)] = 0 }
    local came_from = {}
    local closed   = {}

    while #open > 0 do
        local min_i = 1
        for i = 2, #open do
            if open[i].f < open[min_i].f then min_i = i end
        end
        local cur    = table.remove(open, min_i)
        local cur_ci = ci(cur.x, cur.y)
        if closed[cur_ci] then goto next_node end
        closed[cur_ci] = true

        if cur.x == x1 and cur.y == y1 then
            local path = {}
            local cx, cy = x1, y1
            while true do
                table.insert(path, 1, {wx = cx, wy = cy})
                if cx == x0 and cy == y0 then break end
                local prev = came_from[ci(cx, cy)]
                if not prev then return nil end
                cx, cy = prev[1], prev[2]
            end
            return path
        end

        for _, d in ipairs(DIRS4) do
            local nx, ny = cur.x + d[1], cur.y + d[2]
            if nx >= 1 and nx <= ww and ny >= 1 and ny <= wh then
                local nci = ci(nx, ny)
                if not closed[nci] then
                    -- Destination (highway tile) is always reachable at cost 1
                    local nc = ((nx == x1 and ny == y1) and 1.0) or cell_cost(nx, ny)
                    if nc < math.huge then
                        local ng = cur.g + nc
                        if not g_score[nci] or ng < g_score[nci] then
                            g_score[nci]   = ng
                            came_from[nci] = {cur.x, cur.y}
                            table.insert(open, { f = ng + h(nx, ny), g = ng, x = nx, y = ny })
                        end
                    end
                end
            end
        end
        ::next_node::
    end

    return nil  -- no path found
end

-- Given a list of {wx,wy} node positions, expands each adjacent pair with A*
-- and returns a flat deduplicated list of new cells to build (skipping existing
-- highway cells), plus the total dollar cost.
-- Returns: new_cells, total_cost, ok (bool)
function InfrastructureService.computeSegment(nodes, game)
    if #nodes < 2 then return {}, 0, false end

    local base_cost = (game.C.GAMEPLAY and game.C.GAMEPLAY.HIGHWAY_COST_PER_CELL) or 200
    local seen      = {}
    local new_cells = {}
    local total_cost = 0

    for i = 1, #nodes - 1 do
        local a, b  = nodes[i], nodes[i + 1]
        local cells = InfrastructureService.findPath(a.wx, a.wy, b.wx, b.wy, game)
        if cells then
            for _, c in ipairs(cells) do
                local key = c.wy * 100000 + c.wx
                if not seen[key] and not InfrastructureService.isHighwayCell(c.wx, c.wy, game) then
                    seen[key] = true
                    new_cells[#new_cells + 1] = c
                    -- Dollar cost scales with terrain difficulty
                    local mult = InfrastructureService.getTerrainCost(c.wx, c.wy, game)
                    if mult >= math.huge then mult = 1.0 end  -- shouldn't happen but guard
                    total_cost = total_cost + base_cost * mult
                end
            end
        end
    end

    return new_cells, math.floor(total_cost), true
end

-- ── World mutation ────────────────────────────────────────────────────────────

-- Stamps a list of world cells as highway into ffi_grid and world_highway_map,
-- then rebuilds all derived structures.
function InfrastructureService.applyHighway(cells, game)
    if not cells or #cells == 0 then return end

    local umap = game.maps and game.maps.unified
    if not umap then return end

    local fgi = umap.ffi_grid
    local uw  = umap._w
    local ww  = game.world_w or 1
    local wh  = game.world_h or 1
    local hw  = game.world_highway_map

    -- Reconstruct all_claimed for boundary-aware stamping
    local all_claimed = {}
    for ci2, cmap in ipairs(game.maps.all_cities or {}) do
        local ox  = cmap.world_mn_x or 1
        local oy  = cmap.world_mn_y or 1
        local cw  = math.ceil((cmap.city_grid_width  or 0) / 3)
        local ch  = math.ceil((cmap.city_grid_height or 0) / 3)
        for wy2 = oy, oy + ch - 1 do
            for wx2 = ox, ox + cw - 1 do
                all_claimed[(wy2 - 1) * ww + wx2] = ci2
            end
        end
    end

    for _, c in ipairs(cells) do
        local wx, wy = c.wx, c.wy
        local ci = (wy - 1) * ww + wx
        hw[ci] = true

        -- Boundary-aware ffi_grid stamp (mirrors WorldSandboxController:1385-1416)
        local is_city     = all_claimed[ci]
        local is_boundary = false
        if is_city then
            for _, d in ipairs(DIRS4) do
                local nx, ny = wx + d[1], wy + d[2]
                if nx >= 1 and nx <= ww and ny >= 1 and ny <= wh then
                    if not all_claimed[(ny - 1) * ww + nx] then
                        is_boundary = true; break
                    end
                else
                    is_boundary = true; break
                end
            end
        end

        if not is_city or is_boundary then
            for dy = 0, 2 do
                local base = ((wy - 1) * 3 + dy) * uw + (wx - 1) * 3
                for dx = 0, 2 do
                    fgi[base + dx].type = 4  -- HIGHWAY
                end
            end
        end
    end

    -- Invalidate render cache
    game._world_highway_smooth = nil
    game._world_highway_bounds = nil

    -- Flush path cache
    require("services.PathCacheService").invalidate()

    -- Rebuild HPA* hierarchy
    InfrastructureService.rebuildHPAHierarchy(game)
end

-- ── HPA* rebuild ─────────────────────────────────────────────────────────────

-- Rebuilds road entrances and the road trunk edges in the entrance graph
-- from world_highway_map and city map bounds. Mirrors GameBridgeService.wire().
function InfrastructureService.rebuildHPAHierarchy(game)
    local EntranceService = require("services.EntranceService")
    local ww = game.world_w or 1
    local wh = game.world_h or 1
    local hw = game.world_highway_map or {}

    -- Reconstruct all_claimed
    local all_claimed = {}
    for ci2, cmap in ipairs(game.maps.all_cities or {}) do
        local ox = cmap.world_mn_x or 1
        local oy = cmap.world_mn_y or 1
        local cw = math.ceil((cmap.city_grid_width  or 0) / 3)
        local ch = math.ceil((cmap.city_grid_height or 0) / 3)
        for wy2 = oy, oy + ch - 1 do
            for wx2 = ox, ox + cw - 1 do
                all_claimed[(wy2 - 1) * ww + wx2] = ci2
            end
        end
    end

    -- Attachment nodes: highway cell directly bordering a city
    local attachment_nodes = {}
    for ci, _ in pairs(hw) do
        local wx2 = (ci - 1) % ww + 1
        local wy2 = math.floor((ci - 1) / ww) + 1
        local this_city = all_claimed[ci]
        for _, d in ipairs(DIRS4) do
            local nx2, ny2 = wx2 + d[1], wy2 + d[2]
            if nx2 >= 1 and nx2 <= ww and ny2 >= 1 and ny2 <= wh then
                local neighbor_city = all_claimed[(ny2 - 1) * ww + nx2]
                local relevant_city = this_city or neighbor_city
                if relevant_city and this_city ~= neighbor_city then
                    local ux2 = (wx2 - 1) * 3 + 2
                    local uy2 = (wy2 - 1) * 3 + 2
                    if not attachment_nodes[relevant_city] then attachment_nodes[relevant_city] = {} end
                    local key2 = uy2 * 10000 + ux2
                    local already = false
                    for _, n in ipairs(attachment_nodes[relevant_city]) do
                        if n.key == key2 then already = true; break end
                    end
                    if not already then
                        attachment_nodes[relevant_city][#attachment_nodes[relevant_city] + 1] =
                            {ux = ux2, uy = uy2, key = key2}
                    end
                end
            end
        end
    end
    -- Replace all existing road entrances with freshly computed ones.
    EntranceService.clearMode("road", game)
    for city_idx, nodes in pairs(attachment_nodes) do
        for _, n in ipairs(nodes) do
            EntranceService.register("road", city_idx, n.ux, n.uy, nil, game)
        end
    end

    -- Highway connected-component analysis so we only wire trunks between
    -- attachments that are actually reachable by road. Without this filter,
    -- phantom road trunks get created between cities separated by water and
    -- compete with legitimate water routes in Dijkstra.
    local hw_comp = {}
    local n_comp  = 0
    for hci, _ in pairs(hw) do
        if not hw_comp[hci] then
            n_comp = n_comp + 1
            local bq, bqi = {hci}, 1
            hw_comp[hci] = n_comp
            while bqi <= #bq do
                local cc = bq[bqi]; bqi = bqi + 1
                local cwx2 = (cc - 1) % ww + 1
                local cwy2 = math.floor((cc - 1) / ww) + 1
                for _, d2 in ipairs(DIRS4) do
                    local nwx2, nwy2 = cwx2 + d2[1], cwy2 + d2[2]
                    if nwx2 >= 1 and nwx2 <= ww and nwy2 >= 1 and nwy2 <= wh then
                        local nci2 = (nwy2 - 1) * ww + nwx2
                        if hw[nci2] and not hw_comp[nci2] then
                            hw_comp[nci2] = n_comp
                            bq[#bq + 1] = nci2
                        end
                    end
                end
            end
        end
    end

    -- Group each city's attachments by the highway component they sit on.
    local by_city_comp = {}  -- city_idx → comp_id → list of attachments
    for city_idx, atts in pairs(attachment_nodes) do
        by_city_comp[city_idx] = {}
        for _, att in ipairs(atts) do
            local awx = math.ceil(att.ux / 3)
            local awy = math.ceil(att.uy / 3)
            local comp = hw_comp[(awy - 1) * ww + awx]
            if comp then
                by_city_comp[city_idx][comp] = by_city_comp[city_idx][comp] or {}
                table.insert(by_city_comp[city_idx][comp], att)
            end
        end
    end

    -- Rebuild the entrance graph and add a road trunk edge between EVERY
    -- pair of road entrances in cities connected by the same highway
    -- component. Dijkstra picks the best pair based on local distances.
    local EntranceGraphService = require("services.EntranceGraphService")
    local Entrance = require("models.Entrance")
    EntranceGraphService.rebuild(game)
    for city_a, comps_a in pairs(by_city_comp) do
        for city_b, comps_b in pairs(by_city_comp) do
            if city_a < city_b then
                for comp, atts_a_in in pairs(comps_a) do
                    local atts_b_in = comps_b[comp]
                    if atts_b_in then
                        for _, att_a in ipairs(atts_a_in) do
                            for _, att_b in ipairs(atts_b_in) do
                                local id_a = Entrance.makeId("road", city_a, att_a.ux, att_a.uy)
                                local id_b = Entrance.makeId("road", city_b, att_b.ux, att_b.uy)
                                EntranceGraphService.addTrunkEdge(id_a, id_b, "road", game)
                            end
                        end
                    end
                end
            end
        end
    end
end

return InfrastructureService
