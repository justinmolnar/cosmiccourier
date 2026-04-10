-- views/GameView.lua
-- Updated to render edge-based streets between grid cells
local FloatingTextSystem = require("services.FloatingTextSystem")
local VehicleRenderer    = require("views.VehicleRenderer")
local MapRenderer        = require("views.MapRenderer")

-- Shader: desaturate + alpha the city zone image at draw time.
-- `saturation` 1.0 = full colour, 0.0 = greyscale.  `alpha` controls overall opacity.
local _zone_shader = love.graphics.newShader([[
    extern float saturation;
    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
        vec4 c = Texel(tex, tc) * color;
        float gray = dot(c.rgb, vec3(0.299, 0.587, 0.114));
        c.rgb = mix(vec3(gray), c.rgb, saturation);
        return c;
    }
]])

-- Zoom-driven overlay appearance.
-- Each channel linearly ramps from its _min (at cs_start) to its _max (at cs_full),
-- then clamps.  cs_full is the zoom level where that channel hits its ceiling —
-- set it lower to make the channel "fill in" earlier as you zoom in.
local CITY_OVERLAY = {
    cs_start = 1.5,   -- CITY_IMAGE_THRESHOLD — where cities first appear

    road_alpha_min = 0.50,  road_alpha_max = 1.00,  road_cs_full =   6.0,
    zone_alpha_min = 0.30,  zone_alpha_max = 1.00,  zone_cs_full =  30.0,
    zone_sat_min   = 0.30,  zone_sat_max   = 0.60,  sat_cs_full  = 400.0,
}
do  -- precompute log denominators once at startup
    local ls = math.log(CITY_OVERLAY.cs_start)
    CITY_OVERLAY._log_start   = ls
    CITY_OVERLAY._road_denom  = math.log(CITY_OVERLAY.road_cs_full) - ls
    CITY_OVERLAY._zone_denom  = math.log(CITY_OVERLAY.zone_cs_full) - ls
    CITY_OVERLAY._sat_denom   = math.log(CITY_OVERLAY.sat_cs_full)  - ls
end

-- Cache: skip recompute when cs hasn't changed; shader send skipped when sat is unchanged.
local _overlay_cache = { cs = -1, road_alpha = 1, zone_alpha = 1, zone_sat = 1 }

local function _cityOverlayParams(cs)
    if cs == _overlay_cache.cs then
        return _overlay_cache.road_alpha, _overlay_cache.zone_alpha, _overlay_cache.zone_sat
    end
    local C      = CITY_OVERLAY
    local log_cs = math.log(cs)
    local function ramp(denom, v_min, v_max)
        local t = (log_cs - C._log_start) / denom
        return v_min + (v_max - v_min) * math.max(0, math.min(1, t))
    end
    local ra = ramp(C._road_denom, C.road_alpha_min, C.road_alpha_max)
    local za = ramp(C._zone_denom, C.zone_alpha_min, C.zone_alpha_max)
    local zs = ramp(C._sat_denom,  C.zone_sat_min,   C.zone_sat_max)
    _overlay_cache.cs         = cs
    _overlay_cache.road_alpha = ra
    _overlay_cache.zone_alpha = za
    _overlay_cache.zone_sat   = zs
    return ra, za, zs
end

-- Zoom threshold: above this scale draw vectors directly (crisp quality, ~1 city visible);
-- below this scale use a cached canvas (performance when multiple cities are on screen).
local OVERLAY_VECTOR_THRESHOLD = 5.0

-- Scratch array used by the vehicle draw loop to collect visible vehicles
-- without allocating new tables each frame.
local _vis_vehicles = {}

-- View-private render caches — do not belong on the Game global.
local _road_alpha         = 1.0   -- current frame road overlay opacity
local _trip_preview_cache = nil   -- cached smoothed path for trip hover preview

-- Traces the unique world highway road network from the highway cell map,
-- producing one non-overlapping set of chains.  Multiple A* paths that share
-- terrain corridor cells collapse into a single path here, eliminating the
-- "multiple roads" visual where several chains follow the same route.
local function _buildWorldHighwayPaths(Game, ts)
    local PathUtils = require("lib.path_utils")
    local hmap = Game.world_highway_map
    local w    = Game.world_w
    if not hmap or not w then return {} end

    local DIRS = {{1,0},{-1,0},{0,1},{0,-1}}

    -- Build x/y lookup set
    local cs = {}
    for ci in pairs(hmap) do
        local x = (ci-1) % w + 1
        local y = math.floor((ci-1) / w) + 1
        if not cs[x] then cs[x] = {} end
        cs[x][y] = true
    end

    local function nbrs(x, y)
        local r = {}
        for _, d in ipairs(DIRS) do
            local nx, ny = x+d[1], y+d[2]
            if cs[nx] and cs[nx][ny] then r[#r+1] = {nx, ny} end
        end
        return r
    end

    -- Degree of each cell (cardinal highway neighbors only)
    local deg = {}
    for ci in pairs(hmap) do
        local x = (ci-1) % w + 1
        local y = math.floor((ci-1) / w) + 1
        if not deg[x] then deg[x] = {} end
        deg[x][y] = #nbrs(x, y)
    end

    -- Walk from a terminal/junction cell toward one neighbor, following degree-2
    -- pass-throughs until reaching the next terminal/junction.  Marks interior
    -- degree-2 cells as used so they are not re-walked.
    local used = {}
    local function markUsed(x, y)
        if not used[x] then used[x] = {} end
        used[x][y] = true
    end
    local function isUsed(x, y) return used[x] and used[x][y] end

    local function walkFrom(sx, sy, nx, ny)
        local chain = {{sx, sy}, {nx, ny}}
        local px, py = sx, sy
        local cx, cy = nx, ny
        while (deg[cx] and deg[cx][cy] == 2) and not isUsed(cx, cy) do
            markUsed(cx, cy)
            local found = false
            for _, nb in ipairs(nbrs(cx, cy)) do
                if not (nb[1] == px and nb[2] == py) then
                    px, py = cx, cy
                    cx, cy = nb[1], nb[2]
                    chain[#chain+1] = {cx, cy}
                    found = true
                    break
                end
            end
            if not found then break end
        end
        return chain
    end

    -- Avoid walking the same junction→junction edge twice
    local walked = {}
    local function edgeKey(x1,y1,x2,y2)
        if x1 < x2 or (x1==x2 and y1 < y2) then
            return x1..","..y1.."|"..x2..","..y2
        else
            return x2..","..y2.."|"..x1..","..y1
        end
    end

    local raw = {}
    for ci in pairs(hmap) do
        local x = (ci-1) % w + 1
        local y = math.floor((ci-1) / w) + 1
        if deg[x] and deg[x][y] ~= 2 then
            for _, nb in ipairs(nbrs(x, y)) do
                local ek = edgeKey(x, y, nb[1], nb[2])
                if not walked[ek] and not isUsed(nb[1], nb[2]) then
                    walked[ek] = true
                    local chain = walkFrom(x, y, nb[1], nb[2])
                    raw[#raw+1] = chain
                end
            end
        end
    end
    -- Degree-2 loops (no terminals anywhere)
    for ci in pairs(hmap) do
        local x = (ci-1) % w + 1
        local y = math.floor((ci-1) / w) + 1
        if not isUsed(x, y) then
            local nbs = nbrs(x, y)
            if #nbs >= 1 then
                raw[#raw+1] = walkFrom(x, y, nbs[1][1], nbs[1][2])
            end
        end
    end

    local paths  = {}
    local bounds = {}
    for _, chain in ipairs(raw) do
        if #chain >= 2 then
            local pts = {}
            for _, c in ipairs(chain) do
                pts[#pts+1] = (c[1] - 0.5) * ts
                pts[#pts+1] = (c[2] - 0.5) * ts
            end
            pts = PathUtils.simplify(pts, ts * 2.0)
            pts = PathUtils.chaikin(pts, 3)
            if #pts >= 4 then
                local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
                for i = 1, #pts, 2 do
                    local px, py = pts[i], pts[i+1]
                    if px < x0 then x0 = px end
                    if py < y0 then y0 = py end
                    if px > x1 then x1 = px end
                    if py > y1 then y1 = py end
                end
                paths[#paths+1]  = pts
                bounds[#bounds+1] = {x0, y0, x1, y1}
            end
        end
    end
    return paths, bounds
end

-- Shared drawing routine: renders all overlay layers in city-local coordinates.
-- The caller is responsible for setting up any transform so that (0,0) maps to the
-- city's top-left corner in the destination space (canvas or world).
local function _renderCityOverlayContent(m, Game, RS, m_tps, road_alpha)
    road_alpha = road_alpha or 1.0
    -- Bridges
    if m.bridge_cells then
        love.graphics.setLineStyle("rough")
        love.graphics.setColor(0.72, 0.60, 0.38, 0.95 * road_alpha)
        love.graphics.setLineWidth(m_tps * 0.45)
        for gy, row in pairs(m.bridge_cells) do
            for gx, entry in pairs(row) do
                local px = (gx - 1) * m_tps
                local py = (gy - 1) * m_tps
                if entry.ew then love.graphics.line(px, py + m_tps*0.5, px+m_tps, py + m_tps*0.5) end
                if entry.ns then love.graphics.line(px + m_tps*0.5, py, px + m_tps*0.5, py+m_tps) end
            end
        end
        love.graphics.setLineWidth(1)
    end

    -- Rivers
    if not m._river_smooth_paths_v1 then
        m._river_smooth_paths_v1 = RS.buildRiverPaths(m.grid, m_tps)
    end
    if m._river_smooth_paths_v1 and #m._river_smooth_paths_v1 > 0 then
        local cap_r = m_tps * 0.4
        love.graphics.setColor(0.20, 0.45, 0.75, 0.92 * road_alpha)
        love.graphics.setLineWidth(m_tps * 0.75)
        love.graphics.setLineJoin("bevel")
        for _, pts in ipairs(m._river_smooth_paths_v1) do
            if #pts >= 4 then
                love.graphics.line(pts)
                love.graphics.circle("fill", pts[1], pts[2], cap_r)
                love.graphics.circle("fill", pts[#pts-1], pts[#pts], cap_r)
            end
        end
        love.graphics.setLineWidth(1)
        love.graphics.setLineJoin("miter")
    end

    -- Streets (flag-gated)
    if Game.debug_smooth_roads_like then
        if not m._street_smooth_paths_like_v5 then
            m._street_smooth_paths_like_v5 = RS.buildStreetPathsLike(
                m.zone_seg_v, m.zone_seg_h, m.zone_grid, m_tps, m.grid)
            if Game.maps.unified then Game.maps.unified._snap_lookup = nil end
        end
        if m._street_smooth_paths_like_v5 and #m._street_smooth_paths_like_v5 > 0 then
            love.graphics.setColor(0.30, 0.29, 0.28, road_alpha)
            love.graphics.setLineWidth(m_tps * 0.35)
            love.graphics.setLineStyle("smooth")
            love.graphics.setLineJoin("miter")
            for _, pts in ipairs(m._street_smooth_paths_like_v5) do
                love.graphics.line(pts)
            end
            love.graphics.setLineStyle("rough")
            love.graphics.setLineWidth(1)
            love.graphics.setLineJoin("miter")
        end
    end

    -- Arterials (flag-gated)
    if Game.debug_smooth_roads then
        if not m._road_smooth_paths_v8 then
            if m.road_centerlines and #m.road_centerlines > 0 then
                m._road_smooth_paths_v8 = RS.buildPathsFromCenterlines(m.road_centerlines, m_tps)
            else
                m._road_smooth_paths_v8 = RS.buildPaths(m.grid, m_tps)
            end
            if Game.maps.unified then Game.maps.unified._snap_lookup = nil end
        end
        if m._road_smooth_paths_v8 and #m._road_smooth_paths_v8 > 0 then
            local cap_r = m_tps * 0.35
            love.graphics.setColor(0.22, 0.21, 0.20, road_alpha)
            love.graphics.setLineWidth(m_tps * 0.7)
            love.graphics.setLineJoin("bevel")
            for _, pts in ipairs(m._road_smooth_paths_v8) do
                if #pts >= 4 then
                    love.graphics.line(pts)
                    love.graphics.circle("fill", pts[1], pts[2], cap_r)
                    love.graphics.circle("fill", pts[#pts-1], pts[#pts], cap_r)
                end
            end
            love.graphics.setLineWidth(1)
            love.graphics.setLineJoin("miter")
        end
    end

    love.graphics.setColor(1, 1, 1)
    love.graphics.setLineWidth(1)
    love.graphics.setLineStyle("rough")
    love.graphics.setLineJoin("miter")
end

-- High-zoom path: draw overlay vectors directly into the world (camera transform active).
-- m_ox / m_oy are the city's top-left in world-pixel space (including tile-copy offset).
local function _drawCityOverlayVectors(m, Game, RS, m_ox, m_oy)
    local m_tps = m.tile_pixel_size or Game.C.MAP.TILE_SIZE
    love.graphics.push()
    love.graphics.translate(m_ox, m_oy)
    _renderCityOverlayContent(m, Game, RS, m_tps, _road_alpha or 1.0)
    love.graphics.pop()
end

-- Zoom tier for canvas resolution: higher tier = more canvas pixels per world pixel.
-- We upgrade (rebuild at higher S) when the camera zooms in past a threshold.
-- We never downgrade — a high-res canvas still looks fine at lower zoom levels and
-- avoids a rebuild spike when the player zooms back out.
local function _canvasTier(cs)
    if cs < 2 then return 0 end
    if cs < 5 then return 1 end
    return 2
end

-- Pre-render overlay into a Canvas (built once per tier, reused every frame).
local function _cityCanvasStale(m, Game)
    if not m._overlay_canvas then return true end
    local f = m._overlay_canvas_flags
    if not f then return true end
    if f.roads      ~= (Game.debug_smooth_roads      or false) then return true end
    if f.roads_like ~= (Game.debug_smooth_roads_like or false) then return true end
    if f.had_highways ~= (Game.world_highway_paths ~= nil and #Game.world_highway_paths > 0) then return true end
    -- Upgrade if zoomed in further than when canvas was baked; never downgrade.
    if _canvasTier(Game.camera.scale) > (f.zoom_tier or 0) then return true end
    return false
end

local function _buildCityOverlayCanvas(m, Game, RS)
    local ts   = Game.C.MAP.TILE_SIZE
    local cw   = (m.world_city_mx_x - m.world_mn_x + 1) * ts
    local ch   = (m.world_city_mx_y - m.world_mn_y + 1) * ts
    if cw < 1 or ch < 1 then return end

    if m._overlay_canvas then m._overlay_canvas:release() end

    local m_tps  = m.tile_pixel_size or ts
    local base_S = math.max(1, math.floor(12.0 / m_tps + 0.5))
    local tier   = _canvasTier(Game.camera.scale)
    -- Tier 0: base res; Tier 1: 2× (city overview); Tier 2: 4× (city detail zoom)
    local tier_S = (tier == 2) and 4 or (tier == 1) and 2 or 1
    local S      = math.max(base_S, tier_S)

    local canvas = love.graphics.newCanvas(cw * S, ch * S)
    canvas:setFilter("linear", "linear")

    local prev_canvas = love.graphics.getCanvas()
    -- Clear any active scissor; it is in screen coords and would corrupt canvas rendering.
    local sc_x, sc_y, sc_w, sc_h = love.graphics.getScissor()
    love.graphics.setScissor()
    love.graphics.setCanvas(canvas)
    love.graphics.push()
    love.graphics.origin()
    love.graphics.scale(S, S)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setBlendMode("alpha")

    _renderCityOverlayContent(m, Game, RS, m_tps, 1.0)  -- canvas baked at full alpha; alpha applied at draw time

    love.graphics.setBlendMode("alpha")
    love.graphics.pop()
    love.graphics.setCanvas(prev_canvas)
    if sc_x then love.graphics.setScissor(sc_x, sc_y, sc_w, sc_h) end

    m._overlay_canvas       = canvas
    m._overlay_canvas_scale = S
    m._overlay_canvas_flags = {
        roads        = Game.debug_smooth_roads      or false,
        roads_like   = Game.debug_smooth_roads_like or false,
        had_highways = Game.world_highway_paths ~= nil and #Game.world_highway_paths > 0,
        zoom_tier    = tier,
    }
end

local GameView = {}
GameView.__index = GameView

function GameView:new(game_instance)
    local instance = setmetatable({}, GameView)
    instance.Game = game_instance
    return instance
end


function GameView:_drawFloatingTexts(sidebar_w, screen_w, screen_h)
    local Game = self.Game
    local texts = FloatingTextSystem.getTexts()
    if #texts == 0 then return end
    local game_world_w = screen_w - sidebar_w
    local cx, cy = Game.camera.x, Game.camera.y
    local cs = Game.camera.scale
    love.graphics.setFont(Game.fonts.ui)
    for _, ft in ipairs(texts) do
        -- ft.x/ft.y are world-pixel coords (city origin already baked in at emit time)
        local sx = sidebar_w + game_world_w / 2 + (ft.x - cx) * cs
        local sy = screen_h / 2 + (ft.y - cy) * cs
        love.graphics.setColor(1, 1, 0.3, ft.alpha)
        love.graphics.printf(ft.text, sx - 60, sy, 120, "center")
    end
end

function GameView:_drawTileGridFallback(active_map, S, cur_scale, ui_manager, sidebar_w, screen_w, screen_h)
    local Game = self.Game
    local DrawingUtils = require("utils.DrawingUtils")
    -- Compute viewport bounds in world-pixel space for culling.
    local fb_cs = Game.camera.scale
    local fb_game_world_w = screen_w - sidebar_w
    local fb_half_w = fb_game_world_w * 0.5 / fb_cs
    local fb_half_h = screen_h * 0.5 / fb_cs
    local fb_vp_left  = Game.camera.x - fb_half_w
    local fb_vp_right = Game.camera.x + fb_half_w
    local fb_vp_top   = Game.camera.y - fb_half_h
    local fb_vp_bot   = Game.camera.y + fb_half_h
    love.graphics.push()
    local game_world_w = screen_w - sidebar_w
    local _shake_dx, _shake_dy = 0, 0
    local _ss = Game.screen_shake
    if _ss and _ss.timer and _ss.timer > 0 then
        local _mag = _ss.magnitude * (_ss.timer / _ss.max_time)
        _shake_dx = (love.math.random() * 2 - 1) * _mag
        _shake_dy = (love.math.random() * 2 - 1) * _mag
    end
    love.graphics.translate(sidebar_w + game_world_w / 2 + _shake_dx, screen_h / 2 + _shake_dy)
    love.graphics.scale(Game.camera.scale, Game.camera.scale)
    love.graphics.translate(-Game.camera.x, -Game.camera.y)
    MapRenderer.draw(active_map)
    -- Fog outside downtown
    if cur_scale == S.DOWNTOWN then
        local map = active_map
        if map.downtown_offset and #map.grid > 0 and #map.grid[1] > 0 then
            local TS = Game.C.MAP.TILE_SIZE
            local dt = map.downtown_offset
            local x1 = (dt.x - 1) * TS;  local y1 = (dt.y - 1) * TS
            local x2 = (dt.x + map.downtown_grid_width  - 1) * TS
            local y2 = (dt.y + map.downtown_grid_height - 1) * TS
            local gw = #map.grid[1] * TS; local gh = #map.grid * TS
            love.graphics.setColor(0, 0, 0, 0.72)
            love.graphics.rectangle("fill", 0,  0,  x1,      gh)
            love.graphics.rectangle("fill", x2, 0,  gw-x2,  gh)
            love.graphics.rectangle("fill", x1, 0,  x2-x1,  y1)
            love.graphics.rectangle("fill", x1, y2, x2-x1,  gh-y2)
        end
    end
    if Game.active_map_key == "city" then
        local umap = Game.maps.unified
        local uts = umap and umap.tile_pixel_size or Game.C.MAP.TILE_SIZE
        for _, depot in ipairs(Game.entities.depots) do
            if depot.plot then
                DrawingUtils.drawWorldIcon(Game, "🏢",
                    (depot.plot.x - 0.5) * uts,
                    (depot.plot.y - 0.5) * uts)
            end
        end
        for _, client in ipairs(Game.entities.clients) do
            DrawingUtils.drawWorldIcon(Game, "🏠", client.px, client.py)
        end
        if Game.event_spawner and Game.event_spawner.clickable then
            local ec = Game.event_spawner.clickable
            DrawingUtils.drawWorldIcon(Game, "☎️", ec.x, ec.y)
        end
    end
    if not Game.debug_hide_vehicles then
        local fb_cs = Game.camera.scale
        local fb_Z  = Game.C.ZOOM
        if true then  -- draw all vehicles that pass per-type zoom threshold
            local nv = 0
            for _, v in ipairs(Game.entities.vehicles) do
                local vcfg = Game.C.VEHICLES[v.type_upper]
                local thresh = vcfg and vcfg.rendering.render_zoom_threshold or fb_Z.ENTITY_THRESHOLD
                if fb_cs >= thresh
                and v.px > fb_vp_left and v.px < fb_vp_right
                and v.py > fb_vp_top  and v.py < fb_vp_bot then
                    nv = nv + 1; _vis_vehicles[nv] = v
                end
            end
            if Game.debug_dot_vehicles then
                local fb_r = (active_map.tile_pixel_size or Game.C.MAP.TILE_SIZE) * 0.2
                for i = 1, nv do
                    local v    = _vis_vehicles[i]
                    local vcfg = Game.C.VEHICLES[v.type_upper]
                    local dc   = vcfg and vcfg.dot_color or {1,1,1}
                    love.graphics.setColor(dc[1], dc[2], dc[3])
                    love.graphics.circle("fill", v.px, v.py, fb_r)
                end
                love.graphics.setColor(1, 1, 1)
            else
                for i = 1, nv do VehicleRenderer.draw(_vis_vehicles[i], Game) end
            end
            for i = 1, nv do _vis_vehicles[i] = nil end
        end
    end
    if Game.active_map_key == "city" and ui_manager.hovered_trip_index then
        local trip = Game.entities.trips.pending[ui_manager.hovered_trip_index]
        if trip and trip.legs[trip.current_leg] then
            local leg = trip.legs[trip.current_leg]
            local path_grid = active_map.grid
            local is_rn3 = active_map.road_v_rxs ~= nil
            local function nearestNode(plot)
                return is_rn3 and active_map:findNearestRoadNode(plot)
                               or active_map:findNearestRoadTile(plot)
            end
            local start_node = nearestNode(leg.start_plot)
            local end_node   = nearestNode(leg.end_plot)
            if start_node and end_node and path_grid then
                -- Pick the first vehicle config matching this leg's transport mode for preview pathfinding
                local leg_mode = leg.transport_mode or "road"
                local vp = nil
                for _, cfg in pairs(Game.C.VEHICLES) do
                    if cfg.transport_mode == leg_mode then vp = cfg; break end
                end
                vp = vp or next(Game.C.VEHICLES) and select(2, next(Game.C.VEHICLES))
                local cost_function
                if is_rn3 then
                    cost_function = function(rx, ry)
                        local tile = path_grid[ry+1] and path_grid[ry+1][rx+1]
                        return tile and (vp.pathfinding_costs[tile.type] or 9999) or 9999
                    end
                else
                    cost_function = function(x, y)
                        local tile = path_grid[y] and path_grid[y][x]
                        return tile and (vp.pathfinding_costs[tile.type] or 9999) or 9999
                    end
                end
                local path = Game.pathfinder.findPath(path_grid, start_node, end_node, cost_function, active_map)
                if path then
                    local pixel_path = {}
                    local tps_pv2 = active_map.tile_pixel_size or Game.C.MAP.TILE_SIZE
                    local is_rn2  = active_map.road_v_rxs ~= nil
                    for _, node in ipairs(path) do
                        local px, py
                        if is_rn2 then
                            if node.is_tile then
                                px, py = (node.x + 0.5) * tps_pv2, (node.y + 0.5) * tps_pv2
                            else
                                px, py = node.x * tps_pv2, node.y * tps_pv2
                            end
                        else
                            px, py = active_map:getPixelCoords(node.x, node.y)
                        end
                        table.insert(pixel_path, px); table.insert(pixel_path, py)
                    end
                    love.graphics.setColor(0.2, 0.8, 1, 0.85)
                    love.graphics.setLineWidth(3 / Game.camera.scale)
                    love.graphics.line(pixel_path)
                    love.graphics.setLineWidth(1)
                    local cr = 5 / Game.camera.scale
                    love.graphics.setColor(0.2, 0.8, 1, 1)
                    love.graphics.circle("fill", pixel_path[1], pixel_path[2], cr)
                    love.graphics.circle("fill", pixel_path[#pixel_path-1], pixel_path[#pixel_path], cr)
                end
            end
        end
    end
    if Game.debug_mode then
        for _, vehicle in ipairs(Game.entities.vehicles) do
            if vehicle.visible and vehicle.px > fb_vp_left and vehicle.px < fb_vp_right
            and vehicle.py > fb_vp_top and vehicle.py < fb_vp_bot then
                VehicleRenderer.drawDebug(vehicle, Game)
            end
        end
    end
    love.graphics.pop()
end

function GameView:_drawWorldGenMode(active_map, ui_manager, sidebar_w, screen_w, screen_h)
    local Game = self.Game
    local DrawingUtils = require("utils.DrawingUtils")
    local ts  = Game.C.MAP.TILE_SIZE
    local Z   = Game.C.ZOOM
    local cs  = Game.camera.scale
    local vw  = screen_w - sidebar_w
    local tps = active_map.tile_pixel_size or ts

    -- City origin offset in world-pixel space (same formula as CITY scale before)
    local city_mn_x = Game.world_gen_city_mn_x or 1
    local city_mn_y = Game.world_gen_city_mn_y or 1
    local ox = (city_mn_x - 1) * ts
    local oy = (city_mn_y - 1) * ts

    -- Dark background
    love.graphics.setColor(0.04, 0.04, 0.07)
    love.graphics.rectangle("fill", sidebar_w, 0, vw, screen_h)

    -- Camera transform
    love.graphics.push()
    love.graphics.translate(sidebar_w + vw / 2, screen_h / 2)
    love.graphics.scale(cs, cs)
    love.graphics.translate(-Game.camera.x, -Game.camera.y)
    love.graphics.setColor(1, 1, 1)

    -- Compute horizontal tile range once; all layers reuse tile_i0/tile_i1
    local mpw = (Game.world_w or 0) * ts
    local tile_i0, tile_i1 = 0, 0
    if mpw > 0 then
        local half = vw * 0.5 / cs
        tile_i0 = math.floor((Game.camera.x - half) / mpw)
        tile_i1 = math.ceil( (Game.camera.x + half) / mpw)
    end

    -- Viewport AABB in world coords (used to cull off-screen cities)
    local vp_half_w = vw * 0.5 / cs
    local vp_half_h = screen_h * 0.5 / cs
    local vp_left   = Game.camera.x - vp_half_w
    local vp_right  = Game.camera.x + vp_half_w
    local vp_top    = Game.camera.y - vp_half_h
    local vp_bot    = Game.camera.y + vp_half_h
    local function cityInView(m, x_offset)
        local cl = x_offset + (m.world_mn_x - 1) * ts
        local cr = x_offset + (m.world_city_mx_x or m.world_mn_x) * ts
        local ct = (m.world_mn_y - 1) * ts
        local cb = (m.world_city_mx_y or m.world_mn_y) * ts
        return cr > vp_left and cl < vp_right and cb > vp_top and ct < vp_bot
    end

    -- LAYER: World image (tiled horizontally for seamless east-west looping)
    if Game.world_gen_world_image then
        for i = tile_i0, tile_i1 do
            love.graphics.draw(Game.world_gen_world_image, i * mpw, 0, 0, ts, ts)
        end
    end


    -- LAYER: Inter-city highways (full city-to-city, drawn before city images)
    -- Paths are NOT clipped — the opaque city background image covers the in-city portion,
    -- so only the external segment between cities is ever visible.  This eliminates the
    -- bounding-box-vs-actual-road gap that clipping approaches suffer from.
    if Game.world_highway_map and next(Game.world_highway_map) and not Game.overlay_only_mode then
        if not Game._world_highway_smooth then
            Game._world_highway_smooth, Game._world_highway_bounds = _buildWorldHighwayPaths(Game, ts)
            _trip_preview_cache   = nil
            if Game.maps.unified then Game.maps.unified._snap_lookup = nil end
        end
        local hpaths  = Game._world_highway_smooth
        local hbounds = Game._world_highway_bounds or {}
        if hpaths and #hpaths > 0 then
            love.graphics.setColor(0.22, 0.21, 0.20, 1.0)
            love.graphics.setLineWidth(ts * 0.85)
            love.graphics.setLineJoin("bevel")
            love.graphics.setLineStyle("smooth")
            for i = tile_i0, tile_i1 do
                local xoff = i * mpw
                love.graphics.push()
                love.graphics.translate(xoff, 0)
                for idx, pts in ipairs(hpaths) do
                    local b = hbounds[idx]
                    if b and (b[3]+xoff < vp_left or b[1]+xoff > vp_right or b[4] < vp_top or b[2] > vp_bot) then
                        -- entirely outside viewport, skip
                    elseif #pts >= 4 then
                        love.graphics.line(pts)
                    end
                end
                love.graphics.pop()
            end
            love.graphics.setLineStyle("rough")
            love.graphics.setLineWidth(1)
            love.graphics.setLineJoin("miter")
            love.graphics.setColor(1, 1, 1)
        end
    end

    -- Compute zoom-driven overlay params once for this frame
    local _ra, _zone_alpha, _zone_sat = _cityOverlayParams(cs)
    _road_alpha = _ra  -- update module-level so _drawCityOverlayVectors can read it

    -- LAYER: City background images (tiled, culled)
    -- Drawn after highways so the opaque image hides the in-city highway portion.
    if cs >= Z.CITY_IMAGE_THRESHOLD and not Game.overlay_only_mode then
        local shader_active = false
        love.graphics.setColor(1, 1, 1, _zone_alpha)
        for i = tile_i0, tile_i1 do
            for _, m in ipairs(Game.maps.all_cities or {}) do
                if m.city_image and cityInView(m, i * mpw) then
                    if not shader_active then
                        _zone_shader:send("saturation", _zone_sat)
                        love.graphics.setShader(_zone_shader)
                        shader_active = true
                    end
                    local K = m.city_img_K or 9
                    love.graphics.draw(m.city_image,
                        i * mpw + (m.city_img_min_x - 1) * ts,
                        (m.city_img_min_y - 1) * ts,
                        0, ts / K, ts / K)
                end
            end
        end
        if shader_active then love.graphics.setShader() end
        love.graphics.setColor(1, 1, 1)
    end

    -- LAYER: City road/river overlays
    -- High-zoom (≤2 cities visible, cs ≥ OVERLAY_VECTOR_THRESHOLD): draw vectors directly
    -- for crisp Chaikin-curved roads at any zoom.  ~60 draw calls for 1–2 on-screen cities
    -- is fine at high zoom.  Low-zoom (>2 cities visible or below threshold): use cached
    -- canvas — 1 draw call each; slight blur is invisible when cities are small on screen.
    if cs >= Z.CITY_IMAGE_THRESHOLD then
        local RS = require("utils.RoadSmoother")

        -- Count distinct cities currently in view to pick render mode.
        local cities_in_view = 0
        for _, m in ipairs(Game.maps.all_cities or {}) do
            for i = tile_i0, tile_i1 do
                if cityInView(m, i * mpw) then
                    cities_in_view = cities_in_view + 1
                    break
                end
            end
        end
        local use_vectors = cs >= OVERLAY_VECTOR_THRESHOLD and cities_in_view <= 2

        love.graphics.setColor(1, 1, 1)
        for i = tile_i0, tile_i1 do
            for _, m in ipairs(Game.maps.all_cities or {}) do
                if not cityInView(m, i * mpw) then goto continue_overlay end
                local m_ox = (m.world_mn_x - 1) * ts
                local m_oy = (m.world_mn_y - 1) * ts
                if use_vectors then
                    -- Vectors: always crisp, road_alpha applied inside via _road_alpha
                    _drawCityOverlayVectors(m, Game, RS, i * mpw + m_ox, m_oy)
                else
                    if _cityCanvasStale(m, Game) then
                        _buildCityOverlayCanvas(m, Game, RS)
                    end
                    if m._overlay_canvas then
                        local S = m._overlay_canvas_scale or 1
                        love.graphics.setColor(1, 1, 1, _road_alpha)
                        love.graphics.draw(m._overlay_canvas, i * mpw + m_ox, m_oy, 0, 1/S, 1/S)
                        love.graphics.setColor(1, 1, 1)
                    end
                end
                ::continue_overlay::
            end
        end
    end  -- CITY_IMAGE_THRESHOLD

    -- Rebuild snap lookup if city smooth paths were newly built this frame
    if Game.maps.unified and not Game.maps.unified._snap_lookup then
        require("services.PathSmoothingService").buildSnapLookup(Game)
        _trip_preview_cache = nil
    end

    -- LAYER: City-local debug overlays (building plots, road nodes — use city translate)
    for i = tile_i0, tile_i1 do
    if active_map.world_mn_x and not cityInView(active_map, i * mpw) then goto continue_entities end
    love.graphics.push()
    love.graphics.translate(i * mpw + ox, oy)

    -- [B] Building plots debug overlay
    if Game.debug_building_plots and active_map.building_plots then
        love.graphics.setColor(0.2, 0.5, 1, 0.35)
        for _, plot in ipairs(active_map.building_plots) do
            love.graphics.rectangle("fill", (plot.x-1)*tps, (plot.y-1)*tps, tps, tps)
        end
        local mx, my = love.mouse.getPosition()
        local wx, wy = Game.camera:screenToWorld(mx, my, Game)
        local ts_full = Game.C.MAP.TILE_SIZE
        local lwx = wx - (city_mn_x - 1) * ts_full
        local lwy = wy - (city_mn_y - 1) * ts_full
        local hgx = math.floor(lwx / tps) + 1
        local hgy = math.floor(lwy / tps) + 1
        local grid_w = active_map.grid and #(active_map.grid[1] or {}) or 0
        local grid_h = active_map.grid and #active_map.grid or 0
        if hgx >= 1 and hgx <= grid_w and hgy >= 1 and hgy <= grid_h then
            local ht = active_map.grid[hgy][hgx].type
            if ht == "plot" or ht == "downtown_plot" then
                love.graphics.setColor(1, 1, 1, 0.9)
                love.graphics.rectangle("line", (hgx-1)*tps+1, (hgy-1)*tps+1, tps-2, tps-2)
                local rv = active_map.road_v_rxs or {}
                local rh = active_map.road_h_rys or {}
                local lw = math.max(2, tps * 0.25)
                if rv[hgx-1] then love.graphics.setColor(1,1,0,1); love.graphics.rectangle("fill", (hgx-1)*tps-lw*0.5, (hgy-1)*tps, lw, tps) end
                if rv[hgx]   then love.graphics.setColor(1,1,0,1); love.graphics.rectangle("fill", hgx*tps-lw*0.5,     (hgy-1)*tps, lw, tps) end
                if rh[hgy-1] then love.graphics.setColor(1,.5,0,1); love.graphics.rectangle("fill", (hgx-1)*tps, (hgy-1)*tps-lw*0.5, tps, lw) end
                if rh[hgy]   then love.graphics.setColor(1,.5,0,1); love.graphics.rectangle("fill", (hgx-1)*tps, hgy*tps-lw*0.5,     tps, lw) end
                for _, d in ipairs({{-1,0},{1,0},{0,-1},{0,1}}) do
                    local nx, ny = hgx+d[1], hgy+d[2]
                    if nx >= 1 and nx <= grid_w and ny >= 1 and ny <= grid_h then
                        local tt = active_map.grid[ny][nx].type
                        if tt == "arterial" or tt == "highway" then
                            love.graphics.setColor(0,1,0,0.6)
                            love.graphics.rectangle("fill", (nx-1)*tps, (ny-1)*tps, tps, tps)
                        end
                    end
                end
            end
        end
    end

    love.graphics.pop()  -- city translate pop
    ::continue_entities::
    end  -- end debug overlay tile loop
    love.graphics.setColor(1, 1, 1)

    -- LAYER: Entities — depot, clients, vehicles (unified world pixels, tiled)
    local umap = Game.maps.unified
    local uts  = umap and umap.tile_pixel_size or (ts / 3)
    for i = tile_i0, tile_i1 do
        love.graphics.push()
        love.graphics.translate(i * mpw, 0)

        -- Depots
        if cs >= Z.ZONE_THRESHOLD then
            for _, depot in ipairs(Game.entities.depots or {}) do
                local dp = depot.plot
                DrawingUtils.drawWorldIcon(Game, "🏢", (dp.x - 0.5) * uts, (dp.y - 0.5) * uts)
            end
        end

        -- Clients
        if cs >= Z.ZONE_THRESHOLD then
            for _, client in ipairs(Game.entities.clients) do
                if client.px > vp_left and client.px < vp_right and client.py > vp_top and client.py < vp_bot then
                    DrawingUtils.drawWorldIcon(Game, "🏠", client.px, client.py)
                end
            end
        end

        -- [P] Client/pickup overlay
        if Game.debug_pickup_locations and umap then
            local r = uts * 0.3
            for _, client in ipairs(Game.entities.clients) do
                love.graphics.setColor(1, 0.5, 0, 0.8)
                love.graphics.circle("fill", client.px, client.py, r)
            end
            love.graphics.setColor(0, 1, 1, 0.8)
            local r2 = uts * 0.2
            for _, trip in ipairs(Game.entities.trips.pending) do
                local leg = trip.legs and trip.legs[trip.current_leg]
                if leg and leg.start_plot then
                    love.graphics.circle("fill", (leg.start_plot.x - 0.5) * uts, (leg.start_plot.y - 0.5) * uts, r2)
                end
            end
        end

        -- Event spawner
        if Game.event_spawner and Game.event_spawner.clickable then
            DrawingUtils.drawWorldIcon(Game, "☎️", Game.event_spawner.clickable.x, Game.event_spawner.clickable.y)
        end

        -- Vehicles — spatial-grid query: only visits buckets that overlap the viewport.
        -- With 10k vehicles spread across the world, only the ~50-200 near the camera
        -- are ever touched; the rest are completely skipped. (H toggles draw.)
        if not Game.debug_hide_vehicles then
            local nv = 0
            for _, v in ipairs(Game.entities.vehicles) do
                local vcfg  = Game.C.VEHICLES[v.type_upper]
                local thresh = vcfg and vcfg.rendering.render_zoom_threshold or Z.ENTITY_THRESHOLD
                if cs >= thresh
                and v.px > vp_left and v.px < vp_right
                and v.py > vp_top  and v.py < vp_bot then
                    nv = nv + 1; _vis_vehicles[nv] = v
                end
            end

            if nv > 0 then
                if Game.debug_dot_vehicles then
                    -- Dot mode (C key): per-vehicle color from vcfg.dot_color
                    local dot_r = ts * 0.2
                    local sel   = Game.entities.selected_vehicle
                    if sel and sel.px > vp_left and sel.px < vp_right
                    and sel.py > vp_top and sel.py < vp_bot then
                        love.graphics.setColor(1, 1, 0, 0.85)
                        love.graphics.setLineWidth(2 / Game.camera.scale)
                        love.graphics.circle("line", sel.px, sel.py, 16 / Game.camera.scale)
                        love.graphics.setLineWidth(1 / Game.camera.scale)
                    end
                    for i = 1, nv do
                        local v    = _vis_vehicles[i]
                        local vcfg = Game.C.VEHICLES[v.type_upper]
                        local dc   = vcfg and vcfg.dot_color or {1,1,1}
                        love.graphics.setColor(dc[1], dc[2], dc[3])
                        love.graphics.circle("fill", v.px, v.py, dot_r)
                    end
                    love.graphics.setColor(1, 1, 1)
                else
                    for i = 1, nv do VehicleRenderer.draw(_vis_vehicles[i], Game) end
                end

                -- Clear scratch list
                for i = 1, nv do _vis_vehicles[i] = nil end
            end
        end

        -- Debug vehicle overlay (viewport culled)
        if Game.debug_mode then
            for _, vehicle in ipairs(Game.entities.vehicles) do
                if vehicle.visible
                and vehicle.px > vp_left and vehicle.px < vp_right and vehicle.py > vp_top and vehicle.py < vp_bot then
                    VehicleRenderer.drawDebug(vehicle, Game)
                end
            end
        end

        love.graphics.pop()
    end

    -- LAYER: Trip preview (unified pathfinding, cached per trip)
    if ui_manager.hovered_trip_index and umap then
        local htrip = Game.entities.trips.pending[ui_manager.hovered_trip_index]
        local leg   = htrip and htrip.legs and htrip.legs[htrip.current_leg]
        if leg then
            local cache = _trip_preview_cache
            if not cache or cache.trip ~= htrip then
                _trip_preview_cache = nil
                -- Pick the first vehicle config matching this leg's transport mode
                local leg_mode = leg.transport_mode or "road"
                local vp = nil
                for _, cfg in pairs(Game.C.VEHICLES) do
                    if cfg.transport_mode == leg_mode then vp = cfg; break end
                end
                vp = vp or select(2, next(Game.C.VEHICLES))
                local mock = {
                    operational_map_key = "unified",
                    grid_anchor         = leg.start_plot,
                    pathfinding_bounds  = nil,
                    type                = leg_mode,
                    id                  = 0,
                    getMovementCostFor  = function(self, t) return (vp and vp.pathfinding_costs[t]) or 9999 end,
                    getSpeed            = function(self) return (vp and (vp.base_speed or vp.speed)) or 60 end,
                }
                local PathfindingService = require("services.PathfindingService")
                local path = PathfindingService.findVehiclePath(mock, leg.start_plot, leg.end_plot, Game)
                if path and #path >= 2 then
                    local hw_smooth  = Game._world_highway_smooth
                    local all_cities = Game.maps.all_cities or {}
                    local function snapToChains(opx, opy, chains, wox, woy)
                        local bd, sx, sy = math.huge, opx, opy
                        for _, ch in ipairs(chains) do
                            for j = 1, #ch - 1, 2 do
                                local d2 = (ch[j]+wox-opx)^2 + (ch[j+1]+woy-opy)^2
                                if d2 < bd then bd=d2; sx=ch[j]+wox; sy=ch[j+1]+woy end
                            end
                        end
                        return sx, sy
                    end
                    local _fg = umap.ffi_grid
                    local _fgw = umap._w
                    local _TN = _fg and {[0]="grass",[1]="road",[2]="downtown_road",[3]="arterial",[4]="highway"} or nil
                    local pixel_path = {}
                    for _, node in ipairs(path) do
                        local orig_px = (node.x - 0.5) * uts
                        local orig_py = (node.y - 0.5) * uts
                        local px, py  = orig_px, orig_py
                        local tt = _fg and _TN[_fg[(node.y-1)*_fgw + (node.x-1)].type]
                                       or (umap.grid and umap.grid[node.y] and umap.grid[node.y][node.x] and umap.grid[node.y][node.x].type)
                        if tt == "highway" and hw_smooth then
                            local bd = math.huge
                            for _, chain in ipairs(hw_smooth) do
                                for j = 1, #chain - 1, 2 do
                                    local d2 = (chain[j]-orig_px)^2 + (chain[j+1]-orig_py)^2
                                    if d2 < bd then bd=d2; px=chain[j]; py=chain[j+1] end
                                end
                            end
                        elseif tt == "arterial" or tt == "road" or tt == "downtown_road" then
                            for _, cmap in ipairs(all_cities) do
                                local ox = (cmap.world_mn_x - 1) * 3
                                local oy = (cmap.world_mn_y - 1) * 3
                                local cw = cmap.city_grid_width  or (cmap.grid[1] and #cmap.grid[1] or 0)
                                local ch = cmap.city_grid_height or #cmap.grid
                                if node.x > ox and node.x <= ox+cw and node.y > oy and node.y <= oy+ch then
                                    local chains = (tt == "arterial") and cmap._road_smooth_paths_v8
                                               or cmap._street_smooth_paths_like_v5
                                    if chains then
                                        local wox = (cmap.world_mn_x - 1) * ts
                                        local woy = (cmap.world_mn_y - 1) * ts
                                        px, py = snapToChains(orig_px, orig_py, chains, wox, woy)
                                    end
                                    break
                                end
                            end
                        end
                        table.insert(pixel_path, px)
                        table.insert(pixel_path, py)
                    end
                    local PathUtils = require("lib.path_utils")
                    local smoothed  = PathUtils.chaikin(pixel_path, 3)
                    if #smoothed >= 4 then
                        _trip_preview_cache = {trip = htrip, pts = smoothed}
                    end
                end
            end
            local cache2 = _trip_preview_cache
            if cache2 and cache2.pts then
                local pts = cache2.pts
                for i = tile_i0, tile_i1 do
                    love.graphics.push()
                    love.graphics.translate(i * mpw, 0)
                    love.graphics.setColor(0.2, 0.8, 1, 0.85)
                    love.graphics.setLineWidth(3 / cs)
                    love.graphics.setLineJoin("bevel")
                    love.graphics.line(pts)
                    local cr = 5 / cs
                    love.graphics.setColor(0.2, 0.8, 1, 1)
                    love.graphics.circle("fill", pts[1], pts[2], cr)
                    love.graphics.circle("fill", pts[#pts-1], pts[#pts], cr)
                    love.graphics.setLineWidth(1)
                    love.graphics.setLineJoin("miter")
                    love.graphics.pop()
                end
            end
        end
    end

    -- LAYER: Delivery debug overlays (T = trip hover, K = stuck vehicles)
    if (Game.debug_trip_hover or Game.debug_stuck_vehicles) and umap then
        self:_drawDeliveryDebug(umap, uts, tile_i0, tile_i1, mpw, cs)
    end

    love.graphics.pop()  -- camera transform pop
end

function GameView:_drawDeliveryDebug(umap, uts, tile_i0, tile_i1, mpw, cs)
    local Game   = self.Game
    local zsv    = umap.zone_seg_v
    local zsh    = umap.zone_seg_h
    local fgi    = umap.ffi_grid
    local fgw    = umap._w or 0
    local fgh    = umap._h or 0
    local _TNAMES= {[0]="grass",[1]="road",[2]="downtown_road",[3]="arterial",[4]="highway",
                    [5]="water",[6]="mountain",[7]="river",[8]="plot",[9]="downtown_plot",
                    [10]="coastal_water",[11]="deep_water",[12]="open_ocean"}

    local function ttype(gx, gy)
        if fgi and gx >= 1 and gx <= fgw and gy >= 1 and gy <= fgh then
            return _TNAMES[fgi[(gy-1)*fgw+(gx-1)].type] or "grass"
        end
        return "grass"
    end

    -- Draw one cell rect (top-left corner coords in unified world pixels)
    local function cell(gx, gy, r, g, b, a)
        love.graphics.setColor(r, g, b, a)
        love.graphics.rectangle("fill", (gx-1)*uts, (gy-1)*uts, uts, uts)
    end

    -- Highlight the traversable neighbours of a plot cell (zone_seg edges + arterials/highways)
    local function neighbours(gx, gy)
        local dirs = {{-1,0},{1,0},{0,-1},{0,1}}
        local checks = {
            -- {dx, dy, zsv_rx_offset, use_zsv}
            -- left:  zone_seg_v[gy][gx-1]
            -- right: zone_seg_v[gy][gx]
            -- up:    zone_seg_h[gy-1][gx]
            -- down:  zone_seg_h[gy][gx]
        }
        for _, d in ipairs(dirs) do
            local nx, ny = gx+d[1], gy+d[2]
            if nx >= 1 and nx <= fgw and ny >= 1 and ny <= fgh then
                local has_edge = false
                if d[1] == -1 then has_edge = zsv and zsv[gy] and zsv[gy][gx-1]
                elseif d[1] ==  1 then has_edge = zsv and zsv[gy] and zsv[gy][gx]
                elseif d[2] == -1 then has_edge = zsh and zsh[gy-1] and zsh[gy-1][gx]
                elseif d[2] ==  1 then has_edge = zsh and zsh[gy]   and zsh[gy][gx]
                end
                local tt = ttype(nx, ny)
                if has_edge or tt == "arterial" or tt == "highway" or tt == "road" or tt == "downtown_road" then
                    cell(nx, ny, 1, 1, 0, 0.45)  -- yellow: reachable road cell
                end
            end
        end
    end

    -- Draw origin (green) and destination (orange) with adjacent road highlights
    local function drawOD(origin, dest)
        if origin then
            neighbours(origin.x, origin.y)
            cell(origin.x, origin.y, 0.15, 1, 0.15, 0.85)   -- green = origin
        end
        if dest then
            neighbours(dest.x, dest.y)
            cell(dest.x, dest.y, 1, 0.45, 0.05, 0.85)        -- orange = destination
        end
    end

    -- Collect (origin, dest) pairs to draw
    local pairs_to_draw = {}

    -- T: trip hover debug — highlight hovered trip's leg plots
    if Game.debug_trip_hover then
        local ui_manager = Game.ui_manager
        local idx = ui_manager and ui_manager.hovered_trip_index
        if idx then
            local trip = Game.entities.trips.pending[idx]
            local leg  = trip and trip.legs and trip.legs[trip.current_leg]
            if leg then
                pairs_to_draw[#pairs_to_draw+1] = {leg.start_plot, leg.end_plot}
            end
        end
    end

    -- K: stuck vehicle debug — highlight each stuck vehicle and its trip plots
    if Game.debug_stuck_vehicles then
        for _, v in ipairs(Game.entities.vehicles) do
            if v.state and v.state.name == "Stuck" then
                local origin, dest
                local lsbs = v.last_state_before_stuck
                local sname = lsbs and (lsbs.name or "") or ""
                if sname == "To Pickup" then
                    local trip = v.trip_queue and v.trip_queue[1]
                    local leg  = trip and trip.legs and trip.legs[trip.current_leg]
                    origin = leg and leg.start_plot
                    dest   = leg and leg.end_plot
                elseif sname == "To Dropoff" then
                    local trip = v.cargo and v.cargo[1]
                    local leg  = trip and trip.legs and trip.legs[trip.current_leg]
                    origin = leg and leg.start_plot
                    dest   = leg and leg.end_plot
                elseif sname == "Returning" then
                    dest = v.depot and v.depot.plot or v.depot_plot
                end
                pairs_to_draw[#pairs_to_draw+1] = {origin, dest}
                -- Red dot on vehicle position
                love.graphics.setColor(1, 0, 0, 0.9)
                love.graphics.circle("fill", v.px, v.py, uts * 0.7)
            end
        end
    end

    -- Render all OD pairs (tiled)
    if #pairs_to_draw == 0 then return end
    for i = tile_i0, tile_i1 do
        love.graphics.push()
        love.graphics.translate(i * mpw, 0)
        for _, od in ipairs(pairs_to_draw) do
            drawOD(od[1], od[2])
        end
        love.graphics.pop()
    end
    love.graphics.setColor(1, 1, 1)
end

function GameView:_drawDistrictOverlay(active_map, sidebar_w, screen_w, screen_h)
    local Game = self.Game
    if not Game.debug_district_overlay then return end
    if Game.camera.scale < Game.C.ZOOM.ZONE_THRESHOLD then return end

    local CoordSvc = require("services.CoordinateService")
    local ZT       = require("data.zones")
    local ts       = Game.C.MAP.TILE_SIZE
    local font     = Game.fonts and Game.fonts.ui_small

    -- Collect all maps with district data
    local district_maps = {}
    for _, m in pairs(Game.maps) do
        if m.district_map then table.insert(district_maps, m) end
    end
    if #district_maps == 0 then return end

    -- Hover detection on whichever map the mouse is over
    local mx, my = love.mouse.getPosition()
    local hovered_poi, hovered_in_map = nil, nil
    if mx >= sidebar_w then
        for _, m in ipairs(district_maps) do
            local city_mn_x = m.world_mn_x or (Game.world_gen_city_mn_x or 1)
            local city_mn_y = m.world_mn_y or (Game.world_gen_city_mn_y or 1)
            local tps = m.tile_pixel_size or ts
            local wx, wy = CoordSvc.screenToWorld(mx, my, Game.C, Game.camera)
            local lscx = math.floor((wx - (city_mn_x - 1) * ts) / tps)
            local lscy = math.floor((wy - (city_mn_y - 1) * ts) / tps)
            local gx, gy = lscx + 1, lscy + 1
            local grid_h = #m.grid
            local grid_w = grid_h > 0 and #(m.grid[1] or {}) or 0
            if gx >= 1 and gx <= grid_w and gy >= 1 and gy <= grid_h then
                local sci = ((m.zone_gscy_off or 0) + lscy) * (m.zone_sw or 1)
                          + (m.zone_gscx_off or 0) + lscx + 1
                local poi = m.district_map[sci]
                if poi then hovered_poi = poi; hovered_in_map = m; break end
            end
        end
    end

    -- Excluded set (for hovered map only)
    local excluded = {}
    if hovered_poi and hovered_in_map and hovered_in_map.district_types then
        local htype = hovered_in_map.district_types[hovered_poi]
        local rules = ZT.DISTRICT_RULES or {}
        for other_poi, other_type in pairs(hovered_in_map.district_types) do
            if other_poi ~= hovered_poi then
                local blocked = false
                local hr = rules[htype]
                if hr then for _, c in ipairs(hr.cannot or {}) do if c == other_type then blocked = true; break end end end
                if not blocked then
                    local or_ = rules[other_type]
                    if or_ then for _, c in ipairs(or_.cannot or {}) do if c == htype then blocked = true; break end end end
                end
                if blocked then excluded[other_poi] = true end
            end
        end
    end

    local is_hovering = hovered_poi ~= nil
    local vw = screen_w - sidebar_w

    -- Tint pass (camera space) — all maps
    love.graphics.push()
    love.graphics.translate(sidebar_w + vw / 2, screen_h / 2)
    love.graphics.scale(Game.camera.scale, Game.camera.scale)
    love.graphics.translate(-Game.camera.x, -Game.camera.y)

    for _, m in ipairs(district_maps) do
        local city_mn_x = m.world_mn_x or (Game.world_gen_city_mn_x or 1)
        local city_mn_y = m.world_mn_y or (Game.world_gen_city_mn_y or 1)
        local tps    = m.tile_pixel_size or ts
        local dmap   = m.district_map
        local dcolors = m.district_colors
        if not dmap or not dcolors then goto next_map end
        local ox = (city_mn_x - 1) * ts
        local oy = (city_mn_y - 1) * ts
        local lw = math.max(0.5, tps * 0.18)
        love.graphics.setLineWidth(lw)
        local is_hm = (m == hovered_in_map)

        for gy_i = 1, #m.grid do
            for gx_i = 1, #(m.grid[gy_i] or {}) do
                local lscx = gx_i - 1
                local lscy = gy_i - 1
                local sci  = ((m.zone_gscy_off or 0) + lscy) * (m.zone_sw or 1)
                           + (m.zone_gscx_off or 0) + lscx + 1
                local poi_idx = dmap[sci]
                local col = poi_idx and dcolors[poi_idx]
                if col then
                    local cx = ox + lscx * tps
                    local cy = oy + lscy * tps
                    if is_hm and poi_idx == hovered_poi then
                        love.graphics.setColor(col[1], col[2], col[3], 0.45)
                        love.graphics.rectangle("fill", cx, cy, tps, tps)
                    elseif is_hm and excluded[poi_idx] then
                        love.graphics.setColor(col[1]*0.4, col[2]*0.4, col[3]*0.4, 0.55)
                        love.graphics.rectangle("fill", cx, cy, tps, tps)
                        love.graphics.setColor(0, 0, 0, 0.55)
                        love.graphics.line(cx, cy, cx+tps, cy+tps)
                        love.graphics.line(cx+tps, cy, cx, cy+tps)
                    elseif is_hm and is_hovering then
                        love.graphics.setColor(col[1], col[2], col[3], 0.07)
                        love.graphics.rectangle("fill", cx, cy, tps, tps)
                    else
                        love.graphics.setColor(col[1], col[2], col[3], 0.15)
                        love.graphics.rectangle("fill", cx, cy, tps, tps)
                    end
                end
            end
        end
        ::next_map::
    end
    love.graphics.setLineWidth(1)
    love.graphics.pop()

    -- Labels — all maps (screen space)
    if font then
        love.graphics.setFont(font)
        for _, m in ipairs(district_maps) do
            local pois   = m.district_pois
            local dtypes = m.district_types
            local dcolors = m.district_colors
            if not pois or not dtypes or not dcolors then goto next_label_map end
            local is_hm = (m == hovered_in_map)
            for poi_idx, poi in ipairs(pois) do
                local dtype = (dtypes[poi_idx] or "?"):gsub("_", " ")
                local wx = (poi.x - 1) * ts + ts * 0.5
                local wy = (poi.y - 1) * ts + ts * 0.5
                local sx, sy = CoordSvc.worldToScreen(wx, wy, Game.C, Game.camera)
                if sx > sidebar_w and sx < screen_w and sy > 0 and sy < screen_h then
                    local col   = dcolors[poi_idx] or {1,1,1}
                    local dim   = is_hm and is_hovering and poi_idx ~= hovered_poi and not excluded[poi_idx]
                    local tw    = font:getWidth(dtype)
                    local th    = font:getHeight()
                    local alpha = dim and 0.35 or 1.0
                    love.graphics.setColor(0, 0, 0, 0.6 * alpha)
                    love.graphics.rectangle("fill", sx-tw/2-3, sy-th/2-2, tw+6, th+4, 3)
                    love.graphics.setColor(col[1], col[2], col[3], alpha)
                    love.graphics.print(dtype, sx-tw/2, sy-th/2)
                end
            end
            ::next_label_map::
        end
    end

    -- Hover tooltip
    if hovered_poi and font and hovered_in_map then
        local m = hovered_in_map
        local city_mn_x = m.world_mn_x or (Game.world_gen_city_mn_x or 1)
        local city_mn_y = m.world_mn_y or (Game.world_gen_city_mn_y or 1)
        local tps = m.tile_pixel_size or ts
        local wx, wy = CoordSvc.screenToWorld(mx, my, Game.C, Game.camera)
        local lscx = math.floor((wx - (city_mn_x - 1) * ts) / tps)
        local lscy = math.floor((wy - (city_mn_y - 1) * ts) / tps)
        local gx, gy = lscx + 1, lscy + 1
        local grid_h = #m.grid
        local grid_w = grid_h > 0 and #(m.grid[1] or {}) or 0
        if gx >= 1 and gx <= grid_w and gy >= 1 and gy <= grid_h then
            local zone     = (m.zone_grid and m.zone_grid[gy] and m.zone_grid[gy][gx]) or "none"
            local district = (m.district_types and m.district_types[hovered_poi] or "residential"):gsub("_", " ")
            local line1 = "District: " .. district
            local line2 = "Zone: " .. zone
            local tw  = math.max(font:getWidth(line1), font:getWidth(line2))
            local th  = font:getHeight()
            local pad = 6
            local bx  = math.min(mx + 14, screen_w - tw - pad*2 - 4)
            local by  = math.min(my + 14, screen_h - th*2 - pad*2 - 8)
            love.graphics.setFont(font)
            love.graphics.setColor(0, 0, 0, 0.78)
            love.graphics.rectangle("fill", bx-pad, by-pad, tw+pad*2, th*2+pad*2+4, 4)
            love.graphics.setColor(1, 1, 1, 0.95)
            love.graphics.print(line1, bx, by)
            love.graphics.print(line2, bx, by+th+4)
        end
    end

    love.graphics.setColor(1, 1, 1)
end

-- Logistics overlay: 0=no activity (dark), 1=receive-only (amber), 2=send+receive (green)
function GameView:_drawLogisticsOverlay(active_map, sidebar_w, screen_w, screen_h)
    local Game = self.Game
    if not Game.debug_logistics_overlay then return end
    if Game.camera.scale < Game.C.ZOOM.ZONE_THRESHOLD then return end

    local ZT  = require("data.zones")
    local ts  = Game.C.MAP.TILE_SIZE
    local vw  = screen_w - sidebar_w

    -- Colours for each tier
    local COL = {
        [0] = {0.15, 0.05, 0.05, 0.55},  -- dead  — dark red
        [1] = {0.90, 0.65, 0.10, 0.45},  -- receive-only — amber
        [2] = {0.20, 0.80, 0.30, 0.45},  -- send+receive — green
    }

    -- Collect maps with a grid
    local city_maps = {}
    for _, m in pairs(Game.maps) do
        if m.grid and m.world_mn_x then city_maps[#city_maps+1] = m end
    end
    if #city_maps == 0 and active_map and active_map.grid then
        city_maps[1] = active_map
    end

    love.graphics.push()
    love.graphics.translate(sidebar_w + vw / 2, screen_h / 2)
    love.graphics.scale(Game.camera.scale, Game.camera.scale)
    love.graphics.translate(-Game.camera.x, -Game.camera.y)

    for _, m in ipairs(city_maps) do
        local tps = m.tile_pixel_size or ts
        local ox  = ((m.world_mn_x or 1) - 1) * ts
        local oy  = ((m.world_mn_y or 1) - 1) * ts

        local zg = m.zone_grid
        if not zg then goto next_logistics_map end
        for gy_i = 1, #zg do
            local row = zg[gy_i]
            if row then
                for gx_i = 1, #row do
                    local zone = row[gx_i]
                    if zone and zone ~= "none" then
                        local tier
                        if ZT.CAN_SEND[zone] then
                            tier = 2
                        elseif ZT.CAN_RECEIVE[zone] then
                            tier = 1
                        else
                            tier = 0
                        end
                        local c = COL[tier]
                        love.graphics.setColor(c[1], c[2], c[3], c[4])
                        love.graphics.rectangle("fill",
                            ox + (gx_i-1) * tps, oy + (gy_i-1) * tps, tps, tps)
                    end
                end
            end
        end
        ::next_logistics_map::
    end

    love.graphics.pop()
    love.graphics.setColor(1, 1, 1)
end

function GameView:_drawRegionOverlay(active_map, sidebar_w, screen_w, screen_h)
    local Game = self.Game
    if not Game.debug_region_overlay then return end
    local segs = Game._region_borders
    local n    = Game._region_borders_n or 0
    if not segs or n == 0 then return end

    local cs = Game.camera.scale
    local vw = screen_w - sidebar_w
    love.graphics.push()
    love.graphics.translate(sidebar_w + vw / 2, screen_h / 2)
    love.graphics.scale(cs, cs)
    love.graphics.translate(-Game.camera.x, -Game.camera.y)

    love.graphics.setColor(0.9, 0.7, 0.2, 0.75)
    love.graphics.setLineWidth(math.max(0.5, 1.5 / cs))
    for i = 1, n do
        local s = segs[i]
        love.graphics.line(s.x1, s.y1, s.x2, s.y2)
    end
    love.graphics.setLineWidth(1)
    love.graphics.pop()
    love.graphics.setColor(1, 1, 1)
end

function GameView:_drawBiomeOverlay(active_map, sidebar_w, screen_w, screen_h)
    local Game = self.Game
    if not Game.debug_biome_overlay then return end
    if Game.camera.scale < Game.C.ZOOM.ZONE_THRESHOLD then return end
    if not active_map.world_biome_data then return end

    local CoordSvc = require("services.CoordinateService")
    local ts       = Game.C.MAP.TILE_SIZE
    local tps      = active_map.tile_pixel_size or ts
    local bdata    = active_map.world_biome_data
    local world_w  = active_map.world_w or 1
    local mn_x     = active_map.world_city_mn_x or (Game.world_gen_city_mn_x or 1)
    local mn_y     = active_map.world_city_mn_y or (Game.world_gen_city_mn_y or 1)
    local mx_x     = active_map.world_city_mx_x or mn_x
    local mx_y     = active_map.world_city_mx_y or mn_y
    local font     = Game.fonts and Game.fonts.ui_small
    local cell_px  = tps * 3  -- pixels per world tile in city sub-cell space

    local BCOLORS = {
        ["River"]              = {0.25, 0.50, 0.95},
        ["Lake"]               = {0.20, 0.42, 0.88},
        ["Beach"]              = {0.92, 0.86, 0.50},
        ["Desert"]             = {0.92, 0.72, 0.36},
        ["Semi-arid"]          = {0.82, 0.68, 0.44},
        ["Tundra"]             = {0.76, 0.84, 0.90},
        ["Cold Highland"]      = {0.70, 0.78, 0.82},
        ["Highland"]           = {0.65, 0.70, 0.62},
        ["Boreal Highland"]    = {0.52, 0.70, 0.60},
        ["Boreal / Taiga"]     = {0.30, 0.56, 0.42},
        ["Temp. Rainforest"]   = {0.20, 0.54, 0.34},
        ["Temp. Forest"]       = {0.26, 0.56, 0.36},
        ["Subtropical Forest"] = {0.28, 0.58, 0.36},
        ["Tropical Forest"]    = {0.24, 0.60, 0.36},
        ["Jungle"]             = {0.18, 0.58, 0.30},
        ["Woodland"]           = {0.36, 0.62, 0.40},
        ["Swamp"]              = {0.32, 0.50, 0.44},
        ["Tropical Swamp"]     = {0.28, 0.48, 0.40},
        ["Grassland"]          = {0.62, 0.82, 0.42},
        ["Savanna"]            = {0.74, 0.80, 0.42},
        ["Tropical Savanna"]   = {0.72, 0.76, 0.40},
        ["Shrubland"]          = {0.66, 0.74, 0.48},
    }

    -- Resolve hovered world tile
    local hover_wx, hover_wy, hover_bd
    local mx, my = love.mouse.getPosition()
    if mx >= sidebar_w then
        local wpx, wpy = CoordSvc.screenToWorld(mx, my, Game.C, Game.camera)
        local lscx = math.floor((wpx - (mn_x - 1) * ts) / tps)
        local lscy = math.floor((wpy - (mn_y - 1) * ts) / tps)
        local twx  = mn_x + math.floor(lscx / 3)
        local twy  = mn_y + math.floor(lscy / 3)
        if twx >= mn_x and twx <= mx_x and twy >= mn_y and twy <= mx_y then
            hover_wx = twx
            hover_wy = twy
            hover_bd = bdata[(twy - 1) * world_w + twx]
        end
    end

    -- Tile tints (inside camera transform)
    local vw = screen_w - sidebar_w
    love.graphics.push()
    love.graphics.translate(sidebar_w + vw / 2, screen_h / 2)
    love.graphics.scale(Game.camera.scale, Game.camera.scale)
    love.graphics.translate(-Game.camera.x, -Game.camera.y)
    local ox = (mn_x - 1) * ts
    local oy = (mn_y - 1) * ts

    for wy = mn_y, mx_y do
        for wx = mn_x, mx_x do
            local bd = bdata[(wy - 1) * world_w + wx]
            if bd then
                local col     = BCOLORS[bd.name] or {0.55, 0.55, 0.55}
                local px      = ox + (wx - mn_x) * cell_px
                local py      = oy + (wy - mn_y) * cell_px
                local hovered = hover_wx == wx and hover_wy == wy
                love.graphics.setColor(col[1], col[2], col[3], hovered and 0.72 or 0.45)
                love.graphics.rectangle("fill", px, py, cell_px, cell_px)
                if hovered then
                    love.graphics.setColor(1, 1, 1, 0.9)
                    love.graphics.setLineWidth(math.max(1, tps * 0.15))
                    love.graphics.rectangle("line", px, py, cell_px, cell_px)
                    love.graphics.setLineWidth(1)
                end
            end
        end
    end
    love.graphics.pop()

    -- Hover tooltip (screen space)
    if hover_bd and font then
        local bn   = hover_bd.name or "Unknown"
        local line1 = "Biome: " .. bn
        local line2
        if hover_bd.is_river then
            line2 = "Tile: river"
        elseif hover_bd.is_lake then
            line2 = "Tile: lake"
        else
            line2 = string.format("temp %.2f   wet %.2f", hover_bd.temp or 0, hover_bd.wet or 0)
        end
        local tw  = math.max(font:getWidth(line1), font:getWidth(line2))
        local th  = font:getHeight()
        local pad = 6
        local bx  = math.min(mx + 14, screen_w - tw - pad * 2 - 4)
        local by  = math.min(my + 14, screen_h - th * 2 - pad * 2 - 8)
        love.graphics.setFont(font)
        love.graphics.setColor(0, 0, 0, 0.78)
        love.graphics.rectangle("fill", bx - pad, by - pad, tw + pad * 2, th * 2 + pad * 2 + 4, 4)
        love.graphics.setColor(1, 1, 1, 0.95)
        love.graphics.print(line1, bx, by)
        love.graphics.print(line2, bx, by + th + 4)
    end

    love.graphics.setColor(1, 1, 1)
end

-- Press U to toggle.  Draws the unified navigation grid in world-pixel space:
--   highway      = blue filled tile
--   arterial     = cyan filled tile
--   plot cells   = faint gray (city footprint)
--   streets      = white line segments drawn BETWEEN cells (zone_seg edges)
function GameView:_drawUnifiedGridOverlay(sidebar_w, screen_w, screen_h)
    local Game = self.Game
    if not Game.debug_unified_grid then return end
    local umap  = Game.maps and Game.maps.unified
    if not umap then return end
    local fgi = umap.ffi_grid
    if not fgi then return end
    local gw = umap._w
    local gh = umap._h
    if gw == 0 or gh == 0 then return end

    local ts  = Game.C.MAP.TILE_SIZE
    local uts = umap.tile_pixel_size or (ts / 3)
    local cs  = Game.camera.scale
    local vw  = screen_w - sidebar_w

    -- Viewport bounds in world-pixel space for culling
    local vp_hw = vw * 0.5 / cs
    local vp_hh = screen_h * 0.5 / cs
    local ux0 = math.max(1,  math.floor((Game.camera.x - vp_hw) / uts))
    local ux1 = math.min(gw, math.ceil( (Game.camera.x + vp_hw) / uts) + 1)
    local uy0 = math.max(1,  math.floor((Game.camera.y - vp_hh) / uts))
    local uy1 = math.min(gh, math.ceil( (Game.camera.y + vp_hh) / uts) + 1)

    love.graphics.push()
    love.graphics.translate(sidebar_w + vw / 2, screen_h / 2)
    love.graphics.scale(cs, cs)
    love.graphics.translate(-Game.camera.x, -Game.camera.y)

    -- Filled tiles: all road types
    for uy = uy0, uy1 do
        local base = (uy - 1) * gw
        for ux = ux0, ux1 do
            local ti = fgi[base + ux - 1].type
            if     ti == 4 then love.graphics.setColor(1.0,  0.55, 0.0,  0.85)  -- highway    (orange)
            elseif ti == 3 then love.graphics.setColor(0.0,  1.0,  0.75, 0.85)  -- arterial   (cyan)
            elseif ti == 2 then love.graphics.setColor(0.9,  0.9,  1.0,  0.70)  -- downtown road (light blue)
            elseif ti == 1 then love.graphics.setColor(0.75, 0.75, 0.75, 0.60)  -- road        (gray)
            else ti = nil end
            if ti then
                love.graphics.rectangle("fill", (ux-1)*uts, (uy-1)*uts, uts, uts)
            end
        end
    end

    -- Street edges: draw zone_seg boundaries as line segments between cells.
    -- zone_seg_v[uy][ux] = N-S street between cells (ux,uy) and (ux+1,uy): vertical line at x=ux*uts
    -- zone_seg_h[uy][ux] = E-W street between cells (ux,uy) and (ux,uy+1): horizontal line at y=uy*uts
    local uzsv = umap.zone_seg_v
    local uzsh = umap.zone_seg_h
    love.graphics.setLineWidth(1.5 / cs)
    if uzsv then
        love.graphics.setColor(0.0, 1.0, 0.2, 0.9)
        for uy, row in pairs(uzsv) do
            if uy >= uy0 and uy <= uy1 then
                for ux in pairs(row) do
                    if ux >= ux0 and ux <= ux1 then
                        love.graphics.line(ux*uts, (uy-1)*uts, ux*uts, uy*uts)
                    end
                end
            end
        end
    end
    if uzsh then
        love.graphics.setColor(0.2, 0.5, 1.0, 0.9)
        for uy, row in pairs(uzsh) do
            if uy >= uy0 and uy <= uy1 then
                for ux in pairs(row) do
                    if ux >= ux0 and ux <= ux1 then
                        love.graphics.line((ux-1)*uts, uy*uts, ux*uts, uy*uts)
                    end
                end
            end
        end
    end
    love.graphics.setLineWidth(1)
    love.graphics.pop()
    love.graphics.setColor(1, 1, 1)
end

function GameView:_drawF3Overlay()
    local Game       = self.Game
    local screen_w, screen_h = love.graphics.getDimensions()
    local font       = Game.fonts and Game.fonts.ui_small
    if not font then return end

    local sidebar_w = Game.C.UI.SIDEBAR_WIDTH
    local lh = 15   -- line height
    local px = sidebar_w + 6  -- left column starts after sidebar
    local py = 6    -- top padding
    local col2_x = screen_w - 320  -- right column x

    -- ── Gather data ──────────────────────────────────────────────────────────

    local fps       = love.timer.getFPS()
    local frame_ms  = Game.game_controller and Game.game_controller.performance_stats.avg_frame_time * 1000 or 0
    local gc_kb     = collectgarbage("count")
    local gc_mb     = gc_kb / 1024
    local gfx_stats = love.graphics.getStats()

    local entities  = Game.entities
    local vehicles  = entities and entities.vehicles or {}
    local clients   = entities and entities.clients  or {}
    local pending   = entities and entities.trips and entities.trips.pending or {}

    local n_abstracted = 0
    local vehicle_type_counts = {}
    local states_count = {}
    for _, v in ipairs(vehicles) do
        vehicle_type_counts[v.type] = (vehicle_type_counts[v.type] or 0) + 1
        if v:shouldUseAbstractedSimulation(Game) then n_abstracted = n_abstracted + 1 end
        local sn = v.state and v.state.name or "?"
        states_count[sn] = (states_count[sn] or 0) + 1
    end
    local state_parts = {}
    for sn, cnt in pairs(states_count) do state_parts[#state_parts+1] = sn..":"..cnt end
    table.sort(state_parts)

    local PathScheduler    = require("services.PathScheduler")
    local PathCacheService = require("services.PathCacheService")
    local sched_queue = #PathScheduler._queue - PathScheduler._head + 1
    local cache_entries = PathCacheService._count or 0

    local umap   = Game.maps and Game.maps.unified
    local uw     = umap and umap._w  or 0
    local uh     = umap and umap._h  or 0
    local ww     = Game.world_w or 0
    local wh     = Game.world_h or 0

    local n_cities = 0
    local n_att_nodes = 0
    if Game.hw_attachment_nodes then
        for _, nodes in pairs(Game.hw_attachment_nodes) do
            n_cities = n_cities + 1
            n_att_nodes = n_att_nodes + #nodes
        end
    end
    local n_city_edges = 0
    if Game.hw_city_edges then
        for ca, row in pairs(Game.hw_city_edges) do
            for _ in pairs(row) do n_city_edges = n_city_edges + 1 end
        end
        n_city_edges = n_city_edges / 2  -- each edge stored in both directions
    end

    local cam    = Game.camera
    local cam_x  = cam and math.floor(cam.x) or 0
    local cam_y  = cam and math.floor(cam.y) or 0
    local cam_z  = cam and string.format("%.2f", cam.scale) or "?"

    local gc_pause   = 300
    local gc_stepmul = 400

    -- ── Left column lines ─────────────────────────────────────────────────────

    local left = {
        string.format("FPS: %d  (%.2f ms/frame)", fps, frame_ms),
        string.format("GC heap: %.1f MB  (%.0f KB)", gc_mb, gc_kb),
        string.format("GC pause: %d%%  stepmul: %d%%", gc_pause, gc_stepmul),
        "",
        string.format("Draw calls:    %d", gfx_stats.drawcalls),
        string.format("Canvas sw:     %d", gfx_stats.canvasswitches),
        string.format("Image binds:   %d", gfx_stats.texturememory and math.floor(gfx_stats.texturememory/1024) or 0) .. " KB tex mem",
        string.format("Shader sw:     %d", gfx_stats.shaderswitches),
        "",
        string.format("PathScheduler queue: %d (%.1f ms budget)", math.max(0, sched_queue), PathScheduler.budget_ms),
        string.format("PathCache entries:   %d / 750", cache_entries),
        "",
        string.format("Smooth movement: %s", Game.debug_smooth_vehicle_movement and "ON" or "off"),
        string.format("Snap lookup:     %s", (umap and umap._snap_lookup) and "built" or "nil"),
    }

    -- ── Right column lines ────────────────────────────────────────────────────

    local right = {
        string.format("World:  %d x %d cells", ww, wh),
        string.format("Unified grid:  %d x %d sub-cells", uw, uh),
        string.format("FFI grid:  %s", (umap and umap.ffi_grid) and "yes" or "no"),
        "",
        string.format("Cities:        %d", n_cities),
        string.format("Att. nodes:    %d total", n_att_nodes),
        string.format("City edges:    %d", math.floor(n_city_edges)),
        "",
        string.format("Vehicles:  %d  (abstracted %d)", #vehicles, n_abstracted),
        string.format("Clients:   %d", #clients),
        string.format("Trips pending: %d", #pending),
        "",
        "Vehicle states:",
    }
    for _, s in ipairs(state_parts) do right[#right+1] = "  " .. s end
    right[#right+1] = ""
    right[#right+1] = string.format("Camera: (%d, %d)  zoom: %s", cam_x, cam_y, cam_z)
    right[#right+1] = string.format("Active map: %s", Game.active_map_key or "?")
    right[#right+1] = string.format("Map scale: %s", tostring(Game.state and Game.state.current_map_scale))

    -- ── Draw ─────────────────────────────────────────────────────────────────

    love.graphics.setFont(font)

    -- measure max widths for background panels
    local lw, rw = 0, 0
    for _, line in ipairs(left)  do lw = math.max(lw, font:getWidth(line)) end
    for _, line in ipairs(right) do rw = math.max(rw, font:getWidth(line)) end

    local pad = 4
    love.graphics.setColor(0, 0, 0, 0.65)
    love.graphics.rectangle("fill", px - pad, py - pad, lw + pad*2, #left * lh + pad*2)
    love.graphics.rectangle("fill", col2_x - pad, py - pad, rw + pad*2, #right * lh + pad*2)

    for i, line in ipairs(left) do
        if line == "" then
            -- skip blank lines (already accounted for in height)
        else
            local r, g, b = 1, 1, 1
            -- colour-code FPS line
            if i == 1 then
                if fps >= 55 then r,g,b = 0.4,1,0.4
                elseif fps >= 30 then r,g,b = 1,1,0.4
                else r,g,b = 1,0.4,0.4 end
            end
            love.graphics.setColor(r, g, b, 1)
        end
        love.graphics.print(line, px, py + (i-1)*lh)
    end

    for i, line in ipairs(right) do
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print(line, col2_x, py + (i-1)*lh)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

function GameView:prewarm()
    local Game = self.Game
    if not Game.maps or not Game.maps.all_cities then return end
    local RS  = require("utils.RoadSmoother")
    local ts  = Game.C.MAP.TILE_SIZE

    -- Highway smooth paths (pure data, no GPU)
    if not Game._world_highway_smooth and Game.world_highway_map and next(Game.world_highway_map) then
        Game._world_highway_smooth, Game._world_highway_bounds = _buildWorldHighwayPaths(Game, ts)
        _trip_preview_cache   = nil
        if Game.maps.unified then Game.maps.unified._snap_lookup = nil end
    end

    -- Per-city smooth paths (pure data, no GPU)
    for _, m in ipairs(Game.maps.all_cities) do
        local m_tps = m.tile_pixel_size or ts
        if not m._river_smooth_paths_v1 then
            m._river_smooth_paths_v1 = RS.buildRiverPaths(m.grid, m_tps)
        end
        if Game.debug_smooth_roads_like and not m._street_smooth_paths_like_v5 then
            m._street_smooth_paths_like_v5 = RS.buildStreetPathsLike(
                m.zone_seg_v, m.zone_seg_h, m.zone_grid, m_tps, m.grid)
            if Game.maps.unified then Game.maps.unified._snap_lookup = nil end
        end
        if Game.debug_smooth_roads and not m._road_smooth_paths_v8 then
            if m.road_centerlines and #m.road_centerlines > 0 then
                m._road_smooth_paths_v8 = RS.buildPathsFromCenterlines(m.road_centerlines, m_tps)
            else
                m._road_smooth_paths_v8 = RS.buildPaths(m.grid, m_tps)
            end
            if Game.maps.unified then Game.maps.unified._snap_lookup = nil end
        end
    end

    -- Snap lookup (pure data, depends on smooth paths above)
    if Game.maps.unified and not Game.maps.unified._snap_lookup then
        require("services.PathSmoothingService").buildSnapLookup(Game)
        _trip_preview_cache = nil
    end

    -- Overlay canvases + tile canvases (GPU — must be called from draw context)
    for _, m in ipairs(Game.maps.all_cities) do
        if _cityCanvasStale(m, Game) then
            _buildCityOverlayCanvas(m, Game, RS)
        end
        if not m._tile_canvas then
            MapRenderer.buildTileCanvas(m)
        end
    end
end

function GameView:draw()
    local Game = self.Game
    local active_map = Game.maps[Game.active_map_key]
    if not active_map then return end

    if Game._prewarm_pending then
        Game._prewarm_pending = nil
        self:prewarm()
    end
    local sidebar_w  = Game.C.UI.SIDEBAR_WIDTH
    local screen_w, screen_h = love.graphics.getDimensions()
    local S          = Game.C.MAP.SCALES
    local cur_scale  = Game.state.current_map_scale
    local ui_manager = Game.ui_manager
    love.graphics.setScissor(sidebar_w, 0, screen_w - sidebar_w, screen_h)
    if Game.world_gen_cam_params then
        self:_drawWorldGenMode(active_map, ui_manager, sidebar_w, screen_w, screen_h)
        self:_drawDistrictOverlay(active_map, sidebar_w, screen_w, screen_h)
        self:_drawRegionOverlay(active_map, sidebar_w, screen_w, screen_h)
        self:_drawBiomeOverlay(active_map, sidebar_w, screen_w, screen_h)
        self:_drawUnifiedGridOverlay(sidebar_w, screen_w, screen_h)
    else
        self:_drawTileGridFallback(active_map, S, cur_scale, ui_manager, sidebar_w, screen_w, screen_h)
    end
    self:_drawHighwayBuildGhost(sidebar_w, screen_w, screen_h)
    self:_drawLogisticsOverlay(active_map, sidebar_w, screen_w, screen_h)
    if not Game.debug_hide_vehicles then
        self:_drawFloatingTexts(sidebar_w, screen_w, screen_h)
    end
    love.graphics.setScissor()
    if Game.debug_f3 then self:_drawF3Overlay() end
end

-- Highway build ghost: previews the player's in-progress highway segment.
-- Uses A* paths (matching what will actually be built) drawn as Chaikin-smoothed
-- lines, plus a colour-coded highlight on the hover world cell.
function GameView:_drawHighwayBuildGhost(sidebar_w, screen_w, screen_h)
    local Game = self.Game
    if not (Game.entities and Game.entities.build_highway_mode) then return end

    local IS        = require("services.InfrastructureService")
    local PathUtils = require("lib.path_utils")
    local nodes     = Game.entities.highway_build_nodes or {}
    local ts        = Game.C.MAP.TILE_SIZE
    local cs        = Game.camera.scale
    local vw        = screen_w - sidebar_w
    local umap      = Game.maps and Game.maps.unified
    if not umap then return end

    -- Helper: convert a list of {wx,wy} cells to a flat pixel array (cell centres).
    local function cellsToPixels(cells)
        local pts = {}
        for _, c in ipairs(cells) do
            pts[#pts + 1] = (c.wx - 0.5) * ts
            pts[#pts + 1] = (c.wy - 0.5) * ts
        end
        return pts
    end

    -- ── Hover cell detection ─────────────────────────────────────────────────
    local mx, my = love.mouse.getPosition()
    local tps    = umap.tile_pixel_size or (ts / 3)
    local wx_px  = (mx - (sidebar_w + vw / 2)) / cs + Game.camera.x
    local wy_px  = (my - screen_h / 2)         / cs + Game.camera.y
    local ugx    = math.floor(wx_px / tps) + 1
    local ugy    = math.floor(wy_px / tps) + 1
    local hwx, hwy  -- hover world cell (may be nil if out of bounds)
    if ugx >= 1 and ugx <= umap._w and ugy >= 1 and ugy <= umap._h then
        hwx = math.ceil(ugx / 3)
        hwy = math.ceil(ugy / 3)
    end

    -- ── Path cache (avoid A* every frame; recompute only when cells change) ──
    -- Cache key: serialise nodes + hover cell
    local last_node = nodes[#nodes]
    local nodes_key = #nodes > 0 and (last_node.wx .. "," .. last_node.wy) or ""
    local hover_key = hwx and (hwx .. "," .. hwy) or ""
    local cache_key = nodes_key .. "|" .. hover_key

    local ghost_cache = Game._hw_ghost_cache
    if not ghost_cache or ghost_cache.key ~= cache_key then
        -- Rebuild confirmed path pixels
        local confirmed_pts = {}
        if #nodes >= 2 then
            for i = 1, #nodes - 1 do
                local cells = IS.findPath(nodes[i].wx, nodes[i].wy,
                                          nodes[i+1].wx, nodes[i+1].wy, Game)
                if cells then
                    for _, c in ipairs(cells) do
                        confirmed_pts[#confirmed_pts + 1] = (c.wx - 0.5) * ts
                        confirmed_pts[#confirmed_pts + 1] = (c.wy - 0.5) * ts
                    end
                else
                    -- No path found — draw straight line in red between the two nodes
                    confirmed_pts[#confirmed_pts + 1] = (nodes[i].wx   - 0.5) * ts
                    confirmed_pts[#confirmed_pts + 1] = (nodes[i].wy   - 0.5) * ts
                    confirmed_pts[#confirmed_pts + 1] = (nodes[i+1].wx - 0.5) * ts
                    confirmed_pts[#confirmed_pts + 1] = (nodes[i+1].wy - 0.5) * ts
                end
            end
        end

        -- Rebuild preview path pixels (last node → hover cell)
        local preview_pts   = {}
        local preview_no_path = false
        if hwx and #nodes >= 1 then
            local cells = IS.findPath(last_node.wx, last_node.wy, hwx, hwy, Game)
            if cells then
                preview_pts = cellsToPixels(cells)
            else
                -- No path — straight red line as fallback
                preview_pts = {
                    (last_node.wx - 0.5) * ts, (last_node.wy - 0.5) * ts,
                    (hwx          - 0.5) * ts, (hwy          - 0.5) * ts,
                }
                preview_no_path = true
            end
        end

        ghost_cache = {
            key             = cache_key,
            confirmed_pts   = confirmed_pts,
            preview_pts     = preview_pts,
            preview_no_path = preview_no_path,
        }
        Game._hw_ghost_cache = ghost_cache
    end

    -- ── Draw ─────────────────────────────────────────────────────────────────
    love.graphics.push()
    love.graphics.translate(sidebar_w + vw / 2, screen_h / 2)
    love.graphics.scale(cs, cs)
    love.graphics.translate(-Game.camera.x, -Game.camera.y)

    local lw = math.max(ts * 0.6, 2 / cs)
    love.graphics.setLineJoin("bevel")
    love.graphics.setLineStyle("smooth")

    -- Confirmed path legs — solid orange
    if #ghost_cache.confirmed_pts >= 4 then
        local smooth = PathUtils.chaikin(ghost_cache.confirmed_pts, 3)
        love.graphics.setColor(1.0, 0.55, 0.1, 0.85)
        love.graphics.setLineWidth(lw)
        love.graphics.line(smooth)
    end

    -- Preview leg — semi-transparent orange (or red dashes if no path found)
    if #ghost_cache.preview_pts >= 4 then
        if ghost_cache.preview_no_path then
            love.graphics.setColor(1.0, 0.2, 0.2, 0.5)
            love.graphics.setLineWidth(lw * 0.5)
            love.graphics.setLineStyle("rough")
            love.graphics.line(ghost_cache.preview_pts)
            love.graphics.setLineStyle("smooth")
        else
            local smooth = PathUtils.chaikin(ghost_cache.preview_pts, 3)
            love.graphics.setColor(1.0, 0.55, 0.1, 0.35)
            love.graphics.setLineWidth(lw)
            love.graphics.line(smooth)
        end
    end

    love.graphics.setLineWidth(1)
    love.graphics.setLineStyle("rough")
    love.graphics.setLineJoin("miter")

    -- Node markers — yellow circles
    love.graphics.setColor(1, 1, 0, 0.9)
    for _, n in ipairs(nodes) do
        love.graphics.circle("fill", (n.wx - 0.5) * ts, (n.wy - 0.5) * ts, ts * 0.3)
    end

    -- Hover cell highlight — colour-coded by terrain cost
    if hwx then
        if IS.isHighwayCell(hwx, hwy, Game) then
            love.graphics.setColor(0.2, 1.0, 0.2, 0.65)   -- green: valid endpoint
        else
            local cost = IS.getTerrainCost(hwx, hwy, Game)
            if cost >= math.huge then
                love.graphics.setColor(1.0, 0.15, 0.15, 0.55)  -- red: impassable
            elseif cost >= 6 then
                love.graphics.setColor(1.0, 0.40, 0.05, 0.60)  -- dark orange: very expensive
            elseif cost >= 3 then
                love.graphics.setColor(1.0, 0.65, 0.10, 0.60)  -- orange: expensive
            elseif cost >= 1.5 then
                love.graphics.setColor(1.0, 0.90, 0.20, 0.55)  -- yellow: moderate
            else
                love.graphics.setColor(0.55, 1.0, 0.30, 0.50)  -- light green: cheap
            end
        end
        love.graphics.rectangle("fill", (hwx - 1) * ts, (hwy - 1) * ts, ts, ts)
    end

    love.graphics.pop()
    love.graphics.setColor(1, 1, 1)
end

return GameView