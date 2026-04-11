-- services/GameBridgeService.lua
-- Wires generated world data into the running game:
--   · Unified FFI navigation grid
--   · Highway attachment nodes + city edges + city SC bounds
--   · Vehicle / depot reset
--   · Client respawn + world state
--   · Downtown zoom signal + region borders + world hierarchy
-- game.* is the only external dependency.

local ffi = require("ffi")
local _ffi_cdef_done = false

local TILE_INT = {
    grass=0, road=1, downtown_road=2, arterial=3, highway=4,
    water=5, mountain=6, river=7, plot=8, downtown_plot=9,
    coastal_water=10, deep_water=11, open_ocean=12,
}

local GameBridgeService = {}

-- Wire world-gen output into game state. Mutates game.maps.*, game.hw_*, game.world_*, etc.
function GameBridgeService.wire(
    game, new_map, all_claimed,
    highway_map, city_bounds_list,
    region_map, continent_map,
    city_locations, highway_paths,
    world_w, world_h,
    water_tile_types
)
    local C  = game.C
    local hw = highway_map or {}
    local ww = world_w
    local wh = world_h

    require("services.PathCacheService").invalidate()

    -- ── Unified FFI navigation grid ───────────────────────────────────────────
    if not _ffi_cdef_done then
        ffi.cdef[[ typedef struct { uint8_t type; uint8_t _pad[3]; } CosmicTile; ]]
        _ffi_cdef_done = true
    end

    local uw = ww * 3
    local uh = wh * 3
    local ffi_grid = ffi.new("CosmicTile[?]", uw * uh)

    -- Stamp water tile subtypes (coastal_water=10, deep_water=11, open_ocean=12).
    -- Each world cell maps to a 3×3 sub-cell block. City and highway tiles overwrite these.
    if water_tile_types then
        for ci, tile_type in pairs(water_tile_types) do
            local wx = (ci - 1) % ww + 1
            local wy = math.floor((ci - 1) / ww) + 1
            for dy = 0, 2 do
                local base = ((wy - 1) * 3 + dy) * uw + (wx - 1) * 3
                for dx = 0, 2 do
                    ffi_grid[base + dx].type = tile_type
                end
            end
        end
    end

    for _, cmap in ipairs(game.maps.all_cities) do
        local ox = (cmap.world_mn_x - 1) * 3
        local oy = (cmap.world_mn_y - 1) * 3
        for cy = 1, #cmap.grid do
            local row  = cmap.grid[cy]
            local base = (oy + cy - 1) * uw + ox
            for cx = 1, #row do
                ffi_grid[base + cx - 1].type = TILE_INT[row[cx].type] or 0
            end
        end
    end

    local dirs4 = {{1,0},{-1,0},{0,1},{0,-1}}
    for ci, _ in pairs(hw) do
        local wx = (ci - 1) % ww + 1
        local wy = math.floor((ci - 1) / ww) + 1
        local is_city     = all_claimed[ci]
        local is_boundary = false
        if is_city then
            for _, d in ipairs(dirs4) do
                local nx, ny = wx + d[1], wy + d[2]
                if nx >= 1 and nx <= ww and ny >= 1 and ny <= wh then
                    if not all_claimed[(ny - 1) * ww + nx] then is_boundary = true; break end
                else
                    is_boundary = true; break
                end
            end
        end
        if not is_city or is_boundary then
            for dy = 0, 2 do
                local base = ((wy - 1) * 3 + dy) * uw + (wx - 1) * 3
                for dx = 0, 2 do ffi_grid[base + dx].type = 4 end  -- HIGHWAY
            end
        end
    end

    local uzsv, uzsh = {}, {}
    for _, cmap in ipairs(game.maps.all_cities) do
        local ox = (cmap.world_mn_x - 1) * 3
        local oy = (cmap.world_mn_y - 1) * 3
        if cmap.zone_seg_v then
            for gy, row in pairs(cmap.zone_seg_v) do
                local uy = oy + gy
                if uy >= 1 and uy <= uh then
                    for rx in pairs(row) do
                        local ux = ox + rx
                        if ux >= 1 and ux <= uw then
                            if not uzsv[uy] then uzsv[uy] = {} end
                            uzsv[uy][ux] = true
                        end
                    end
                end
            end
        end
        if cmap.zone_seg_h then
            for ry, row in pairs(cmap.zone_seg_h) do
                local uy = oy + ry
                if uy >= 1 and uy <= uh then
                    for gx in pairs(row) do
                        local ux = ox + gx
                        if ux >= 1 and ux <= uw then
                            if not uzsh[uy] then uzsh[uy] = {} end
                            uzsh[uy][ux] = true
                        end
                    end
                end
            end
        end
    end

    local uts  = C.MAP.TILE_SIZE / 3
    local umap = { grid = nil, ffi_grid = ffi_grid, tile_pixel_size = uts, _w = uw, _h = uh }
    umap.zone_seg_v = uzsv
    umap.zone_seg_h = uzsh
    function umap:isRoad(t)
        if type(t) == "number" then return t >= 1 and t <= 4 end
        return t == "road" or t == "downtown_road" or t == "arterial" or t == "highway"
    end
    function umap:getPixelCoords(x, y)
        return (x - 0.5) * self.tile_pixel_size, (y - 0.5) * self.tile_pixel_size
    end
    function umap:findNearestRoadTile(plot)
        local gw, gh = self._w, self._h
        local fg = self.ffi_grid
        local sx = math.max(1, math.min(gw, plot.x))
        local sy = math.max(1, math.min(gh, plot.y))
        local visited = {[sy * (gw + 1) + sx] = true}
        local q, qi = {{sx, sy}}, 1
        while qi <= #q and qi <= 4000 do
            local cx, cy = q[qi][1], q[qi][2]; qi = qi + 1
            if self:isRoad(fg[(cy-1)*gw + (cx-1)].type) then return {x=cx, y=cy} end
            for _, d in ipairs({{0,-1},{0,1},{-1,0},{1,0}}) do
                local nx, ny = cx+d[1], cy+d[2]
                local k = ny*(gw+1)+nx
                if nx>=1 and nx<=gw and ny>=1 and ny<=gh and not visited[k] then
                    visited[k]=true; q[#q+1]={nx,ny}
                end
            end
        end
        return nil
    end
    game.maps.unified = umap
    umap.world_w = ww

    -- ── Attachment nodes ──────────────────────────────────────────────────────
    local attachment_nodes = {}
    for ci, _ in pairs(hw) do
        local wx2 = (ci - 1) % ww + 1
        local wy2 = math.floor((ci - 1) / ww) + 1
        local this_city = all_claimed[ci]
        for _, d in ipairs(dirs4) do
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
                        attachment_nodes[relevant_city][#attachment_nodes[relevant_city]+1] =
                            {ux=ux2, uy=uy2, key=key2}
                    end
                end
            end
        end
    end
    -- Register road attachment nodes as first-class entrances.
    -- Clear any prior road entrances (world regen) so stale nodes don't linger.
    local EntranceService = require("services.EntranceService")
    EntranceService.clearMode("road", game)
    for city_idx, nodes in pairs(attachment_nodes) do
        for _, n in ipairs(nodes) do
            EntranceService.register("road", city_idx, n.ux, n.uy, nil, game)
        end
    end

    -- ── City edges via highway connected-component analysis ───────────────────
    local hw_comp = {}; local n_comp = 0
    for hci, _ in pairs(hw) do
        if not hw_comp[hci] then
            n_comp = n_comp + 1
            local bq, bqi = {hci}, 1
            hw_comp[hci] = n_comp
            while bqi <= #bq do
                local cc = bq[bqi]; bqi = bqi + 1
                local cwx2 = (cc - 1) % ww + 1
                local cwy2 = math.floor((cc - 1) / ww) + 1
                for _, d2 in ipairs(dirs4) do
                    local nwx2, nwy2 = cwx2 + d2[1], cwy2 + d2[2]
                    if nwx2 >= 1 and nwx2 <= ww and nwy2 >= 1 and nwy2 <= wh then
                        local nci2 = (nwy2 - 1) * ww + nwx2
                        if hw[nci2] and not hw_comp[nci2] then
                            hw_comp[nci2] = n_comp; bq[#bq + 1] = nci2
                        end
                    end
                end
            end
        end
    end
    local city_comp = {}
    for city_idx, nodes2 in pairs(attachment_nodes) do
        city_comp[city_idx] = {}
        for _, att in ipairs(nodes2) do
            local awx  = math.ceil(att.ux / 3)
            local awy  = math.ceil(att.uy / 3)
            local comp2 = hw_comp[(awy - 1) * ww + awx]
            if comp2 and not city_comp[city_idx][comp2] then
                city_comp[city_idx][comp2] = att
            end
        end
    end
    -- Build the entrance graph: intra-city + transfer edges from the
    -- registered entrances, then inter-city trunk edges from component pairs.
    local EntranceGraphService = require("services.EntranceGraphService")
    local Entrance = require("models.Entrance")
    EntranceGraphService.rebuild(game)
    for city_a, comps_a in pairs(city_comp) do
        for city_b, comps_b in pairs(city_comp) do
            if city_a < city_b then
                for comp3, att_a in pairs(comps_a) do
                    local att_b = comps_b[comp3]
                    if att_b then
                        local id_a = Entrance.makeId("road", city_a, att_a.ux, att_a.uy)
                        local id_b = Entrance.makeId("road", city_b, att_b.ux, att_b.uy)
                        EntranceGraphService.addTrunkEdge(id_a, id_b, "road", game)
                    end
                end
            end
        end
    end

    -- ── City sub-cell bounding boxes ──────────────────────────────────────────
    local MARGIN        = 6
    local city_sc_bounds = {}
    for city_idx, bounds_set in pairs(city_bounds_list or {}) do
        local mn_wx, mx_wx = ww + 1, 0
        local mn_wy, mx_wy = wh + 1, 0
        for ci in pairs(bounds_set) do
            local cwx2 = (ci - 1) % ww + 1
            local cwy2 = math.floor((ci - 1) / ww) + 1
            if cwx2 < mn_wx then mn_wx = cwx2 end; if cwx2 > mx_wx then mx_wx = cwx2 end
            if cwy2 < mn_wy then mn_wy = cwy2 end; if cwy2 > mx_wy then mx_wy = cwy2 end
        end
        if mn_wx <= mx_wx then
            city_sc_bounds[city_idx] = {
                x1 = math.max(1,  (mn_wx - 1) * 3 + 1 - MARGIN),
                y1 = math.max(1,  (mn_wy - 1) * 3 + 1 - MARGIN),
                x2 = math.min(uw, mx_wx * 3 + MARGIN),
                y2 = math.min(uh, mx_wy * 3 + MARGIN),
            }
        end
    end
    game.city_sc_bounds = city_sc_bounds

    -- ── Vehicle / depot reset ─────────────────────────────────────────────────
    local States          = require("models.vehicles.vehicle_states")
    local depot_local     = new_map:getRandomDowntownBuildingPlot() or new_map:getRandomBuildingPlot()
    local new_depot = depot_local and {
        x = (new_map.world_mn_x - 1) * 3 + depot_local.x,
        y = (new_map.world_mn_y - 1) * 3 + depot_local.y,
    }
    if new_depot then
        local _fg, _gw, _gh = umap.ffi_grid, umap._w, umap._h
        local _sx = math.max(1, math.min(_gw, new_depot.x))
        local _sy = math.max(1, math.min(_gh, new_depot.y))
        local _vis = {[_sy*(_gw+1)+_sx] = true}
        local _q, _qi = {{_sx, _sy}}, 1
        local _snap = nil
        while _qi <= #_q and _qi <= 4000 do
            local _cx, _cy = _q[_qi][1], _q[_qi][2]; _qi = _qi + 1
            local _ti = _fg[(_cy-1)*_gw+(_cx-1)].type
            if _ti == 1 or _ti == 2 then _snap = {x=_cx, y=_cy}; break end
            for _, _d in ipairs({{0,-1},{0,1},{-1,0},{1,0}}) do
                local _nx, _ny = _cx+_d[1], _cy+_d[2]
                local _k = _ny*(_gw+1)+_nx
                if _nx>=1 and _nx<=_gw and _ny>=1 and _ny<=_gh and not _vis[_k] then
                    _vis[_k]=true; _q[#_q+1]={_nx,_ny}
                end
            end
        end
        if _snap then new_depot = _snap end
    end
    if new_depot then
        local Depot = require("models.Depot")
        game.entities.depots = {}
        table.insert(game.entities.depots, Depot:new("sandbox_1", new_depot, game))
    end
    require("services.PathScheduler").clear()
    for _, v in ipairs(game.entities.vehicles) do
        v.cargo = {}; v.trip_queue = {}; v.path = {}; v.path_i = 1
        v.smooth_path = nil; v.smooth_path_i = nil; v._path_pending = false
        v.operational_map_key = "unified"
        if new_depot and game.entities.depots[1] then
            v.depot       = game.entities.depots[1]
            v.depot_plot  = new_depot
            v.grid_anchor = {x = new_depot.x, y = new_depot.y}
            v.px = (new_depot.x - 0.5) * uts
            v.py = (new_depot.y - 0.5) * uts
        end
        if States and States.Idle then v:changeState(States.Idle, game) end
    end

    -- ── World state ───────────────────────────────────────────────────────────
    game.world_city_locations    = city_locations
    game.world_w                 = world_w
    game.world_h                 = world_h
    game.entities.trips.pending  = {}
    local num_clients = math.max(1, #game.entities.clients)
    game.entities.clients = {}
    local depots = game.entities.depots
    for i = 1, num_clients do
        local depot = depots[((i - 1) % math.max(1, #depots)) + 1]
        game.entities:addClient(game, depot)
    end
    game.world_highway_paths   = highway_paths or {}
    game.world_highway_map     = hw
    game._world_highway_smooth = nil

    local RS = require("utils.RoadSmoother")
    for _, m in ipairs(game.maps and game.maps.all_cities or {}) do
        m._overlay_canvas = nil
        m._tile_canvas    = nil
        local m_tps = m.tile_pixel_size or C.MAP.TILE_SIZE
        m._street_smooth_paths_like_v5 = RS.buildStreetPathsLike(
            m.zone_seg_v, m.zone_seg_h, m.zone_grid, m_tps, m.grid)
    end
    if game.maps.unified then game.maps.unified._snap_lookup = nil end

    -- ── Downtown zoom ─────────────────────────────────────────────────────────
    local ok, err = pcall(function() game.maps.city:setScale(C.MAP.SCALES.DOWNTOWN, game) end)
    if not ok then print("GameBridgeService.wire: setScale failed: " .. tostring(err)) end

    -- ── Region border segment cache ───────────────────────────────────────────
    if region_map then
        local ts = C.MAP.TILE_SIZE
        local segs, n = {}, 0
        for y = 1, wh do
            local row_i = (y - 1) * ww
            for x = 1, ww do
                local rid = region_map[row_i + x] or 0
                if x < ww and (region_map[row_i + x + 1] or 0) ~= rid then
                    n=n+1; segs[n]={x1=x*ts, y1=(y-1)*ts, x2=x*ts, y2=y*ts}
                end
                if y < wh and (region_map[row_i + ww + x] or 0) ~= rid then
                    n=n+1; segs[n]={x1=(x-1)*ts, y1=y*ts, x2=x*ts, y2=y*ts}
                end
            end
        end
        game._region_borders   = segs
        game._region_borders_n = n
    end

    -- ── World hierarchy ───────────────────────────────────────────────────────
    local continents = {}
    for _, city in ipairs(game.maps.all_cities or {}) do
        local half_w = math.floor((city.city_grid_width  or 30) / 6)
        local half_h = math.floor((city.city_grid_height or 30) / 6)
        local cwx    = (city.world_mn_x or 1) + half_w
        local cwy    = (city.world_mn_y or 1) + half_h
        local ci2    = (cwy - 1) * ww + cwx
        local rid    = region_map    and region_map[ci2]    or 0
        local cid    = continent_map and continent_map[ci2] or 0
        city.region_id = rid; city.continent_id = cid
        if not continents[cid] then continents[cid] = {id=cid, regions={}} end
        local cont = continents[cid]
        if not cont.regions[rid] then
            cont.regions[rid] = {id=rid, continent_id=cid, cities={}}
        end
        table.insert(cont.regions[rid].cities, city)
    end
    game.world_continents = continents

    game._prewarm_pending = true
end

return GameBridgeService
