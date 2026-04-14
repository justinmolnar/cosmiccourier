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
    water_tile_types,
    start_district_map
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

    local u_road_nodes, u_tile_nodes = {}, {}
    for _, cmap in ipairs(game.maps.all_cities) do
        local ox = (cmap.world_mn_x - 1) * 3
        local oy = (cmap.world_mn_y - 1) * 3
        if cmap.road_nodes then
            for ry, row in pairs(cmap.road_nodes) do
                local uy = oy + ry
                for rx in pairs(row) do
                    local ux = ox + rx
                    if not u_road_nodes[uy] then u_road_nodes[uy] = {} end
                    u_road_nodes[uy][ux] = true
                end
            end
        end
        if cmap.tile_nodes then
            for tty, row in pairs(cmap.tile_nodes) do
                local uty = oy + tty
                for ttx in pairs(row) do
                    local utx = ox + ttx
                    if not u_tile_nodes[uty] then u_tile_nodes[uty] = {} end
                    u_tile_nodes[uty][utx] = true
                end
            end
        end
    end
    -- Stamp tile nodes for inter-city arterial/highway tiles (outside any city's
    -- dual-node coverage). ffi_grid types: 3=arterial, 4=highway.
    -- Tile-node convention: tile at 1-indexed (x,y) registers as (x-1, y-1).
    for fy = 1, uh do
        for fx = 1, uw do
            local ti = ffi_grid[(fy - 1) * uw + (fx - 1)].type
            if ti == 3 or ti == 4 then
                local uty, utx = fy - 1, fx - 1
                if not u_tile_nodes[uty] then u_tile_nodes[uty] = {} end
                u_tile_nodes[uty][utx] = true
            end
        end
    end

    local uts  = C.MAP.TILE_SIZE / 3
    local Map  = require("models.Map")
    local umap = setmetatable(
        { grid = nil, ffi_grid = ffi_grid, tile_pixel_size = uts, _w = uw, _h = uh, C = C },
        { __index = Map })
    umap.zone_seg_v = uzsv
    umap.zone_seg_h = uzsh
    umap.road_nodes = u_road_nodes
    umap.tile_nodes = u_tile_nodes
    umap.road_v_rxs = {}
    umap.road_h_rys = {}
    function umap:isRoad(t)
        if type(t) == "number" then return t >= 1 and t <= 4 end
        return t == "road" or t == "downtown_road" or t == "arterial" or t == "highway"
    end
    function umap:getPixelCoords(x, y)
        return (x - 0.5) * self.tile_pixel_size, (y - 0.5) * self.tile_pixel_size
    end
    -- getNodePixel, pathStartNodeFor, pathEndNodesFor, nodeToCell, findNearestRoadNode
    -- are inherited from Map via the metatable above.
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

    -- Highway connected-component analysis so we only wire trunks between
    -- attachments that are actually reachable by road. Without this filter,
    -- phantom road trunks get created between cities separated by water and
    -- compete with legitimate water routes in Dijkstra.
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

    -- Build the entrance graph: intra-city + transfer edges from the
    -- registered entrances, then inter-city trunk edges between EVERY pair
    -- of road entrances in cities connected by the same highway component.
    -- Dijkstra picks the best pair based on local distances.
    local EntranceGraphService = require("services.EntranceGraphService")
    local Entrance = require("models.Entrance")
    EntranceGraphService.clearTrunksByMode("road", game)
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
            local anchor_node = umap:pathStartNodeFor(new_depot) or {x = new_depot.x, y = new_depot.y}
            v.grid_anchor = anchor_node
            v.px, v.py = umap:getNodePixel(anchor_node)
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

    -- ── Fog reveal masks (per-tier ImageData at sub-cell resolution) ───────
    -- Sub-cell grid is 3× world-cell in each axis.  Each pixel: white = revealed.
    -- Stored as ImageData; the view promotes to GPU Image on first use.
    local start_city = game.maps.city
    local fog_masks = {}
    local sw, sh = ww * 3, wh * 3

    if start_city then
        local cmx = start_city.world_mn_x or 1
        local cmy = start_city.world_mn_y or 1
        local sox = (cmx - 1) * 3  -- sub-cell origin x
        local soy = (cmy - 1) * 3  -- sub-cell origin y

        -- Tier 1: Downtown — use district map (poi_idx 1 = downtown)
        local mask1 = love.image.newImageData(sw, sh)
        if start_district_map then
            for sci, poi_idx in pairs(start_district_map) do
                if poi_idx == 1 then
                    local px = (sci - 1) % sw
                    local py = math.floor((sci - 1) / sw)
                    if px >= 0 and px < sw and py >= 0 and py < sh then
                        mask1:setPixel(px, py, 1, 1, 1, 1)
                    end
                end
            end
        end
        fog_masks[1] = mask1

        -- Tier 2: Full city — all sub-cells owned by any district
        local mask2 = love.image.newImageData(sw, sh)
        if start_district_map then
            for sci, _ in pairs(start_district_map) do
                local px = (sci - 1) % sw
                local py = math.floor((sci - 1) / sw)
                if px >= 0 and px < sw and py >= 0 and py < sh then
                    mask2:setPixel(px, py, 1, 1, 1, 1)
                end
            end
        end
        fog_masks[2] = mask2
    end

    -- Tier 3: Region — fill 3×3 sub-cell blocks for each matching world cell
    local start_rid = start_city and start_city.region_id
    if start_rid and region_map then
        local mask3 = love.image.newImageData(sw, sh)
        for i = 1, ww * wh do
            if region_map[i] == start_rid then
                local wx = (i - 1) % ww
                local wy = math.floor((i - 1) / ww)
                for dy = 0, 2 do for dx = 0, 2 do
                    mask3:setPixel(wx * 3 + dx, wy * 3 + dy, 1, 1, 1, 1)
                end end
            end
        end
        fog_masks[3] = mask3
    end

    -- Tier 4: Continent — fill 3×3 sub-cell blocks for each matching world cell
    local start_cid = start_city and start_city.continent_id
    if start_cid and continent_map then
        local mask4 = love.image.newImageData(sw, sh)
        for i = 1, ww * wh do
            if continent_map[i] == start_cid then
                local wx = (i - 1) % ww
                local wy = math.floor((i - 1) / ww)
                for dy = 0, 2 do for dx = 0, 2 do
                    mask4:setPixel(wx * 3 + dx, wy * 3 + dy, 1, 1, 1, 1)
                end end
            end
        end
        fog_masks[4] = mask4
    end

    game.scope_reveal_masks = fog_masks
    game.scope_mask_w = sw
    game.scope_mask_h = sh

    -- Generate per-tier distance fields via BFS flood from revealed cells.
    -- Each pixel stores normalized distance to nearest revealed cell (0=edge, 1=far).
    -- Euclidean distance transform (two-pass squared-distance method).
    -- Stores nearest-revealed-cell coordinates, computes true Euclidean distance.
    local INF = sw * sw + sh * sh
    local max_dist = math.sqrt(INF) * 0.25
    local scope_dist_fields = {}
    for tier, mask in pairs(fog_masks) do
        -- Init squared distance grid: 0 for revealed, INF for fogged
        local sd = {}
        for py = 0, sh - 1 do
            for px = 0, sw - 1 do
                local idx = py * sw + px + 1
                local r = mask:getPixel(px, py)
                sd[idx] = (r > 0.5) and 0 or INF
            end
        end
        -- Forward pass: top-left to bottom-right
        for py = 0, sh - 1 do
            for px = 0, sw - 1 do
                local idx = py * sw + px + 1
                if px > 0      then local v = sd[idx - 1];     if v + 1 < sd[idx] then sd[idx] = v + 1 end end
                if py > 0      then local v = sd[(py-1)*sw+px+1]; if v + 1 < sd[idx] then sd[idx] = v + 1 end end
                if px > 0 and py > 0 then local v = sd[(py-1)*sw+px]; if v + 2 < sd[idx] then sd[idx] = v + 2 end end
                if px < sw-1 and py > 0 then local v = sd[(py-1)*sw+px+2]; if v + 2 < sd[idx] then sd[idx] = v + 2 end end
            end
        end
        -- Backward pass: bottom-right to top-left
        for py = sh - 1, 0, -1 do
            for px = sw - 1, 0, -1 do
                local idx = py * sw + px + 1
                if px < sw-1   then local v = sd[idx + 1];     if v + 1 < sd[idx] then sd[idx] = v + 1 end end
                if py < sh-1   then local v = sd[(py+1)*sw+px+1]; if v + 1 < sd[idx] then sd[idx] = v + 1 end end
                if px < sw-1 and py < sh-1 then local v = sd[(py+1)*sw+px+2]; if v + 2 < sd[idx] then sd[idx] = v + 2 end end
                if px > 0 and py < sh-1 then local v = sd[(py+1)*sw+px]; if v + 2 < sd[idx] then sd[idx] = v + 2 end end
            end
        end
        -- Write distance values to a flat array, take sqrt, normalize
        local sqrt = math.sqrt
        local min  = math.min
        local vals = {}
        for i = 1, sw * sh do
            vals[i] = min(sqrt(sd[i]) / max_dist, 1.0)
        end
        -- Box blur passes to eliminate interpolation artifacts
        for pass = 1, 3 do
            local tmp = {}
            for py = 0, sh - 1 do
                for px = 0, sw - 1 do
                    local sum, cnt = 0, 0
                    for dy = -2, 2 do
                        local ny = py + dy
                        if ny >= 0 and ny < sh then
                            for dx = -2, 2 do
                                local nx = px + dx
                                if nx >= 0 and nx < sw then
                                    sum = sum + vals[ny * sw + nx + 1]
                                    cnt = cnt + 1
                                end
                            end
                        end
                    end
                    tmp[py * sw + px + 1] = sum / cnt
                end
            end
            vals = tmp
        end
        -- Write blurred values to ImageData
        local df = love.image.newImageData(sw, sh, "rgba16f")
        for py = 0, sh - 1 do
            for px = 0, sw - 1 do
                local v = vals[py * sw + px + 1]
                df:setPixel(px, py, v, v, v, 1)
            end
        end
        scope_dist_fields[tier] = df
    end
    game.scope_dist_fields = scope_dist_fields

    game._prewarm_pending = true
end

return GameBridgeService
