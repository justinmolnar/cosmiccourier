-- services/PathfindingService.lua
local WGC            = require("data.WorldGenConfig")
local IMPASSABLE     = WGC.IMPASSABLE_COST
local SNAP_CAP       = WGC.SNAP_SEARCH_CAP
local PathCacheService = require("services.PathCacheService")

-- Integer → string tile type translation for FFI grid reads.
-- Indices match TILE_INT in WorldSandboxController and C.TILE in constants.lua.
local _TILE_NAMES = {
    [0]="grass", [1]="road", [2]="downtown_road", [3]="arterial", [4]="highway",
    [5]="water",  [6]="mountain", [7]="river", [8]="plot", [9]="downtown_plot",
}

local PathfindingService = {}

-- ── HPA* helpers ──────────────────────────────────────────────────────────────

-- O(1) city membership lookup for a unified sub-cell position.
local function _cityOf(ux, uy, game)
    local umap = game.maps.unified
    if not umap or not umap.world_w then return nil end
    local wx = math.ceil(ux / 3)
    local wy = math.ceil(uy / 3)
    local ci = (wy - 1) * umap.world_w + wx
    return game.hw_all_claimed and game.hw_all_claimed[ci] or nil
end

-- BFS on the city graph to find the shortest sequence of city hops from
-- start_city to end_city. Returns a list of hop tables:
--   {from_city, to_city, edge={from={ux,uy}, to={ux,uy}}}
-- Returns nil if no route exists.
local function _planCityRoute(start_city, end_city, city_edges, max_hops)
    if start_city == end_city then return {} end
    local visited = {[start_city] = true}
    local q = {{city = start_city, path = {}}}
    local qi = 1
    while qi <= #q do
        local cur = q[qi]; qi = qi + 1
        local edges = city_edges[cur.city]
        if edges then
            for neighbor, edge in pairs(edges) do
                if not visited[neighbor] then
                    local new_path = {}
                    for _, e in ipairs(cur.path) do new_path[#new_path+1] = e end
                    new_path[#new_path+1] = {from_city=cur.city, to_city=neighbor, edge=edge}
                    if neighbor == end_city then return new_path end
                    if #new_path < (max_hops or 10) then
                        visited[neighbor] = true
                        q[#q+1] = {city=neighbor, path=new_path}
                    end
                end
            end
        end
    end
    return nil
end

-- ── Snap helper ───────────────────────────────────────────────────────────────

-- BFS snap to nearest traversable tile on a sandbox (sub-cell) map.
-- Accepts road-type tiles AND zone_seg-adjacent cells (city streets are edges, not tiles).
local function _snapToNearestTraversable(plot, map, path_grid, grid_w, grid_h, vehicle)
    local x, y = plot.x, plot.y
    local zsv = map.zone_seg_v
    local zsh = map.zone_seg_h
    local fgi = map.ffi_grid
    local fgw = grid_w
    local function inBounds(gx, gy) return gx>=1 and gx<=grid_w and gy>=1 and gy<=grid_h end
    local function getTileType(cx, cy)
        if fgi then return _TILE_NAMES[fgi[(cy-1)*fgw + (cx-1)].type] or "grass" end
        return path_grid[cy][cx].type
    end
    local function isTraversable(cx, cy)
        if not inBounds(cx, cy) then return false end
        local t = getTileType(cx, cy)
        if map:isRoad(t) and vehicle:getMovementCostFor(t) < IMPASSABLE then return true end
        -- Zone_seg-adjacent: a plot cell flanking a street edge is traversable at road cost.
        if vehicle:getMovementCostFor("road") < IMPASSABLE then
            if (zsv and zsv[cy] and (zsv[cy][cx] or zsv[cy][cx-1]))
            or (zsh and zsh[cy]   and zsh[cy][cx])
            or (zsh and zsh[cy-1] and zsh[cy-1][cx]) then
                return true
            end
        end
        return false
    end
    if isTraversable(x, y) then return {x=x, y=y} end
    local visited = {[y*10000+x] = true}
    local q, qi = {{x, y}}, 1
    while qi <= #q and qi <= SNAP_CAP do
        local cx, cy = q[qi][1], q[qi][2]; qi = qi + 1
        if isTraversable(cx, cy) then return {x=cx, y=cy} end
        for _, d in ipairs({{0,-1},{0,1},{-1,0},{1,0}}) do
            local nx, ny = cx+d[1], cy+d[2]
            local k = ny*10000+nx
            if inBounds(nx, ny) and not visited[k] then
                visited[k] = true; q[#q+1] = {nx, ny}
            end
        end
    end
    return map:findNearestRoadTile(plot)
end

-- ── Sandbox A* (used for all vehicle pathfinding on the unified map) ──────────

local function findVehiclePathSandbox(vehicle, start_node, end_plot, map, game)
    local path_grid = map.grid  -- nil for unified map (FFI); Lua table for city maps
    local grid_h = map._h or (path_grid and #path_grid or 0)
    local grid_w = map._w or (path_grid and path_grid[1] and #path_grid[1] or 0)

    -- FFI tile type read (unified map) or Lua table read (city/sandbox maps).
    local fgi = map.ffi_grid
    local fgw = grid_w
    local function getTileType(gx, gy)
        if fgi then return _TILE_NAMES[fgi[(gy-1)*fgw + (gx-1)].type] or "grass" end
        return path_grid[gy][gx].type
    end

    local start_sub = _snapToNearestTraversable(start_node, map, path_grid, grid_w, grid_h, vehicle)
    if not start_sub then return nil end

    local bounds = vehicle.pathfinding_bounds
    local zsv = map.zone_seg_v
    local zsh = map.zone_seg_h
    local function get_cost(node_x, node_y)
        if bounds and (node_x < bounds.x1 or node_x > bounds.x2
                    or node_y < bounds.y1 or node_y > bounds.y2) then
            return IMPASSABLE
        end
        local t = getTileType(node_x, node_y)
        local cost = vehicle:getMovementCostFor(t)
        -- Streets are edges (zone_seg), not cells. A cell flanking a street edge is
        -- traversable at road cost even if its tile type is plot/downtown_plot/etc.
        if cost >= IMPASSABLE and (zsv or zsh) then
            local has_edge =
                (zsv and zsv[node_y] and (zsv[node_y][node_x] or zsv[node_y][node_x-1]))
             or (zsh and zsh[node_y]   and zsh[node_y][node_x])
             or (zsh and zsh[node_y-1] and zsh[node_y-1][node_x])
            if has_edge then return vehicle:getMovementCostFor("road") end
        end
        return cost
    end

    local end_candidates, seen = {}, {}
    for _, d in ipairs({{0,-1},{0,1},{-1,0},{1,0}}) do
        local nx, ny = end_plot.x + d[1], end_plot.y + d[2]
        if nx >= 1 and nx <= grid_w and ny >= 1 and ny <= grid_h then
            local t = getTileType(nx, ny)
            if map:isRoad(t) and vehicle:getMovementCostFor(t) < IMPASSABLE then
                local key = ny * 10000 + nx
                if not seen[key] then seen[key] = true; end_candidates[#end_candidates+1] = {x=nx, y=ny} end
            end
        end
    end
    if #end_candidates == 0 then
        local fallback = _snapToNearestTraversable(end_plot, map, path_grid, grid_w, grid_h, vehicle)
        if not fallback then return nil end
        end_candidates = {fallback}
    end

    -- Proxy map: forward everything from the real map but hide road_v_rxs so
    -- the pathfinder always uses sandbox (sub-cell) neighbor logic, even for
    -- city maps that also carry road-node data.
    local sandbox_proxy = setmetatable({road_v_rxs = false}, {__index = map})

    -- ── HPA* inter-city hierarchical routing ──────────────────────────────────
    -- Only runs for highway-capable vehicles (bikes cannot traverse highways).
    -- Falls through to direct A* on failure or same-city trips.
    -- _cityOf falls back to original start_node in case the snap moved the vehicle
    -- onto a highway cell just outside city bounds (e.g. city boundary highway tile).
    local can_highway = vehicle:getMovementCostFor("highway") < IMPASSABLE
    local start_city  = can_highway and (_cityOf(start_sub.x, start_sub.y, game)
                                      or _cityOf(start_node.x, start_node.y, game)) or nil
    local end_city    = can_highway and _cityOf(end_plot.x, end_plot.y, game) or nil

    if start_city and end_city and start_city ~= end_city and game.hw_city_edges then
        local hops = _planCityRoute(start_city, end_city, game.hw_city_edges)

        if hops and #hops > 0 then
            local full = {}

            -- Trunk cost: vehicle-agnostic, highway-first. Trunk paths are shared
            -- across all highway-capable vehicle types so they stay in the cache.
            local _umap = game.maps.unified
            local _tfgi = _umap and _umap.ffi_grid
            local _tgw  = _umap and _umap._w or 0
            local trunk_proxy = setmetatable({road_v_rxs = false}, {__index = _umap or map})
            local function trunk_cost(x, y)
                if not _tfgi then return IMPASSABLE end
                local ti = _tfgi[(y-1)*_tgw + (x-1)].type
                if ti == 4 then return 1 end   -- highway
                if ti == 3 then return 5 end   -- arterial
                if ti == 1 or ti == 2 then return 10 end
                return IMPASSABLE
            end

            -- Tier 1: local out — snapped start → first attachment node.
            -- Bounded to the start city's sub-cell area to avoid exploring the full grid.
            local first_att = hops[1].edge.from
            local bounds1 = game.hw_city_sc_bounds and game.hw_city_sc_bounds[start_city]
            local function tier1_cost(x, y)
                if bounds1 and (x < bounds1.x1 or x > bounds1.x2
                             or y < bounds1.y1 or y > bounds1.y2) then
                    return IMPASSABLE
                end
                return get_cost(x, y)
            end
            local seg1 = game.pathfinder.findPath(path_grid or {}, start_sub,
                {x=first_att.ux, y=first_att.uy}, tier1_cost, sandbox_proxy)
            if seg1 then for _, n in ipairs(seg1) do full[#full+1] = n end end

            -- Tiers 2 + 3: for each city hop, trunk segment then (if not last) intra-city transit.
            for hi, hop in ipairs(hops) do
                local att_out = hop.edge.from
                local att_in  = hop.edge.to

                -- Tier 2: trunk (cached highway segment, vehicle-agnostic cost).
                local trunk = PathCacheService.get(att_out.ux, att_out.uy, att_in.ux, att_in.uy)
                if not trunk then
                    trunk = game.pathfinder.findPath({},
                        {x=att_out.ux,y=att_out.uy}, {x=att_in.ux,y=att_in.uy}, trunk_cost, trunk_proxy)
                    if trunk then PathCacheService.put(att_out.ux, att_out.uy, att_in.ux, att_in.uy, trunk) end
                end
                if trunk then for _, n in ipairs(trunk) do full[#full+1] = n end end

                -- Tier 3: intra-city transit when more hops follow (also trunk cost).
                if hi < #hops then
                    local next_att_out = hops[hi+1].edge.from
                    local transit = PathCacheService.get(att_in.ux, att_in.uy, next_att_out.ux, next_att_out.uy)
                    if not transit then
                        transit = game.pathfinder.findPath({},
                            {x=att_in.ux,y=att_in.uy}, {x=next_att_out.ux,y=next_att_out.uy}, trunk_cost, trunk_proxy)
                        if transit then PathCacheService.put(att_in.ux, att_in.uy, next_att_out.ux, next_att_out.uy, transit) end
                    end
                    if transit then for _, n in ipairs(transit) do full[#full+1] = n end end
                end
            end

            -- Tier 4: local in — final attachment node → destination.
            -- Bounded to the end city's sub-cell area to avoid exploring the full grid.
            local last_in = hops[#hops].edge.to
            local local_in = PathCacheService.get(last_in.ux, last_in.uy, end_plot.x, end_plot.y)
            if not local_in then
                local end_node = end_candidates[1]
                if end_node then
                    local bounds4 = game.hw_city_sc_bounds and game.hw_city_sc_bounds[end_city]
                    local function tier4_cost(x, y)
                        if bounds4 and (x < bounds4.x1 or x > bounds4.x2
                                     or y < bounds4.y1 or y > bounds4.y2) then
                            return IMPASSABLE
                        end
                        return get_cost(x, y)
                    end
                    local_in = game.pathfinder.findPath(path_grid or {},
                        {x=last_in.ux,y=last_in.uy}, end_node, tier4_cost, sandbox_proxy)
                    if local_in then PathCacheService.put(last_in.ux, last_in.uy, end_plot.x, end_plot.y, local_in) end
                end
            end
            if local_in then for _, n in ipairs(local_in) do full[#full+1] = n end end

            if #full > 0 then
                table.remove(full, 1)  -- remove start node (vehicle already there)
                return full
            end
        end
        -- Fallback: direct full A* if city graph route failed.
    end
    -- ── End HPA* ─────────────────────────────────────────────────────────────

    -- Cache lookup: key on snapped start + original end_plot
    local cached = PathCacheService.get(start_sub.x, start_sub.y, end_plot.x, end_plot.y)
    if cached then return cached end

    local best_path = nil
    for _, end_node in ipairs(end_candidates) do
        if end_node.x == start_sub.x and end_node.y == start_sub.y then return {} end
        local path = game.pathfinder.findPath(path_grid or {}, start_sub, end_node, get_cost, sandbox_proxy)
        if path and (not best_path or #path < #best_path) then best_path = path end
    end

    if not best_path then
        print(string.format("ERROR: PathfindingService - No path found for %s %d. start_sub=(%d,%d) end_candidates=%d grid=%dx%d",
            vehicle.type, vehicle.id, start_sub.x, start_sub.y, #end_candidates, grid_w, grid_h))
        return nil
    end

    if #best_path > 0 then table.remove(best_path, 1) end
    PathCacheService.put(start_sub.x, start_sub.y, end_plot.x, end_plot.y, best_path)
    return best_path
end

-- ── Public router ─────────────────────────────────────────────────────────────

function PathfindingService.findVehiclePath(vehicle, start_node, end_plot, game)
    if not start_node or not end_plot then
        print(string.format("ERROR: PathfindingService - Invalid plots for %s %d", vehicle.type, vehicle.id))
        return nil
    end
    local map = game.maps[vehicle.operational_map_key]
    if not map then
        print(string.format("ERROR: PathfindingService - Could not find operational map '%s' for vehicle %d",
            vehicle.operational_map_key, vehicle.id))
        return nil
    end
    -- Unified map uses FFI grid (map.ffi_grid); city maps use Lua grid (map.grid).
    if not map.ffi_grid and (not map.grid or #map.grid == 0) then
        print(string.format("ERROR: PathfindingService - No map grid available for %s %d", vehicle.type, vehicle.id))
        return nil
    end
    return findVehiclePathSandbox(vehicle, start_node, end_plot, map, game)
end

function PathfindingService.findPathToDepot(vehicle, game)
    return PathfindingService.findVehiclePath(vehicle, vehicle.grid_anchor, vehicle.depot_plot, game)
end

function PathfindingService.findPathToPickup(vehicle, trip, game)
    local leg = trip.legs[trip.current_leg]
    if not leg then return nil end
    return PathfindingService.findVehiclePath(vehicle, vehicle.grid_anchor, leg.start_plot, game)
end

-- Returns pixel coords for a path node on the unified (sandbox) map.
local function nodePixel(node, TPS)
    return (node.x - 0.5) * TPS, (node.y - 0.5) * TPS
end

function PathfindingService.estimatePathTravelTime(path, vehicle, game)
    if not path or #path == 0 then return 0 end
    local map            = game.maps[vehicle.operational_map_key]
    local TPS            = map.tile_pixel_size or map.C.MAP.TILE_SIZE
    local total_distance = 0
    local last_px, last_py = vehicle.px, vehicle.py
    for _, node in ipairs(path) do
        local node_px, node_py = nodePixel(node, TPS)
        total_distance = total_distance + math.sqrt((node_px-last_px)^2 + (node_py-last_py)^2)
        last_px, last_py = node_px, node_py
    end
    local base_speed = vehicle:getSpeed()
    local speed_normalization_factor = game.C.GAMEPLAY.BASE_TILE_SIZE / TPS
    local normalized_speed = base_speed / speed_normalization_factor
    if normalized_speed == 0 then return math.huge end
    return total_distance / normalized_speed
end

function PathfindingService.findPathToDropoff(vehicle, game)
    -- Only pathfind to the first cargo trip's destination.
    -- Running one A* per cargo item is too expensive on the unified grid.
    local leg = vehicle.cargo[1] and vehicle.cargo[1].legs[vehicle.cargo[1].current_leg]
    if not leg then return nil end
    return PathfindingService.findVehiclePath(vehicle, vehicle.grid_anchor, leg.end_plot, game)
end

return PathfindingService
