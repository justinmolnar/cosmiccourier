-- views/GameView.lua
-- Updated to render edge-based streets between grid cells
local Bike = require("models.vehicles.Bike")
local Truck = require("models.vehicles.Truck")
local FloatingTextSystem = require("services.FloatingTextSystem")

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

    road_alpha_min = 0.50,  road_alpha_max = 1.00,  road_cs_full =   6.0,  -- solid well before mid-zoom
    zone_alpha_min = 0.30,  zone_alpha_max = 1.00,  zone_cs_full =  30.0,  -- full before high zoom
    zone_sat_min   = 0.30,  zone_sat_max   = 0.60,  sat_cs_full  = 400.0,  -- slowest, only 60% at max zoom
}

local function _cityOverlayParams(cs)
    local C = CITY_OVERLAY
    local function ramp(cs_full, v_min, v_max)
        local t = (math.log(cs) - math.log(C.cs_start)) / (math.log(cs_full) - math.log(C.cs_start))
        return v_min + (v_max - v_min) * math.max(0, math.min(1, t))
    end
    return
        ramp(C.road_cs_full, C.road_alpha_min, C.road_alpha_max),
        ramp(C.zone_cs_full, C.zone_alpha_min, C.zone_alpha_max),
        ramp(C.sat_cs_full,  C.zone_sat_min,   C.zone_sat_max)
end

-- Zoom threshold: above this scale draw vectors directly (crisp quality, ~1 city visible);
-- below this scale use a cached canvas (performance when multiple cities are on screen).
local OVERLAY_VECTOR_THRESHOLD = 5.0

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

    local paths = {}
    for _, chain in ipairs(raw) do
        if #chain >= 2 then
            local pts = {}
            for _, c in ipairs(chain) do
                pts[#pts+1] = (c[1] - 0.5) * ts
                pts[#pts+1] = (c[2] - 0.5) * ts
            end
            pts = PathUtils.simplify(pts, ts * 2.0)
            pts = PathUtils.chaikin(pts, 3)
            if #pts >= 4 then paths[#paths+1] = pts end
        end
    end
    return paths
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
    _renderCityOverlayContent(m, Game, RS, m_tps, Game._road_alpha or 1.0)
    love.graphics.pop()
end

-- Low-zoom path: pre-render overlay into a Canvas (built once, reused every frame).
local function _cityCanvasStale(m, Game)
    if not m._overlay_canvas then return true end
    local f = m._overlay_canvas_flags
    return not f
        or (f.roads      ~= (Game.debug_smooth_roads      or false))
        or (f.roads_like ~= (Game.debug_smooth_roads_like or false))
        -- Rebuild if highway data arrived after the canvas was first built
        or (f.had_highways ~= (Game.world_highway_paths ~= nil and #Game.world_highway_paths > 0))
end

local function _buildCityOverlayCanvas(m, Game, RS)
    local ts   = Game.C.MAP.TILE_SIZE
    local cw   = (m.world_city_mx_x - m.world_mn_x + 1) * ts
    local ch   = (m.world_city_mx_y - m.world_mn_y + 1) * ts
    if cw < 1 or ch < 1 then return end

    if m._overlay_canvas then m._overlay_canvas:release() end

    local m_tps = m.tile_pixel_size or ts
    -- S: canvas pixels per world pixel, sized so line widths are clearly visible.
    local S     = math.max(1, math.floor(12.0 / m_tps + 0.5))

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
    love.graphics.translate(sidebar_w + game_world_w / 2, screen_h / 2)
    love.graphics.scale(Game.camera.scale, Game.camera.scale)
    love.graphics.translate(-Game.camera.x, -Game.camera.y)
    active_map:draw()
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
        if Game.entities.depot_plot then
            local dpx, dpy = active_map:getPixelCoords(Game.entities.depot_plot.x, Game.entities.depot_plot.y)
            DrawingUtils.drawWorldIcon(Game, "🏢", dpx, dpy)
        end
        for _, client in ipairs(Game.entities.clients) do
            DrawingUtils.drawWorldIcon(Game, "🏠", client.px, client.py)
        end
        if Game.event_spawner and Game.event_spawner.clickable then
            local ec = Game.event_spawner.clickable
            DrawingUtils.drawWorldIcon(Game, "☎️", ec.x, ec.y)
        end
    end
    for _, vehicle in ipairs(Game.entities.vehicles) do
        if vehicle.visible and vehicle.px > fb_vp_left and vehicle.px < fb_vp_right
        and vehicle.py > fb_vp_top and vehicle.py < fb_vp_bot then
            vehicle:draw(Game)
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
            local start_node = (leg.vehicleType == "truck" and trip.current_leg > 1)
                and nearestNode(Game.entities.depot_plot)
                or  nearestNode(leg.start_plot)
            local end_node = nearestNode(leg.end_plot)
            if start_node and end_node and path_grid then
                local vp = (leg.vehicleType == "bike") and Game.C.VEHICLES.BIKE or Game.C.VEHICLES.TRUCK
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
                vehicle:drawDebug(Game)
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
            Game._world_highway_smooth = _buildWorldHighwayPaths(Game, ts)
            Game._trip_preview_cache   = nil
            if Game.maps.unified then Game.maps.unified._snap_lookup = nil end
        end
        local hpaths = Game._world_highway_smooth
        if hpaths and #hpaths > 0 then
            love.graphics.setColor(0.22, 0.21, 0.20, 1.0)
            love.graphics.setLineWidth(ts * 0.85)
            love.graphics.setLineJoin("bevel")
            love.graphics.setLineStyle("smooth")
            for i = tile_i0, tile_i1 do
                love.graphics.push()
                love.graphics.translate(i * mpw, 0)
                for _, pts in ipairs(hpaths) do
                    if #pts >= 4 then love.graphics.line(pts) end
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
    local _road_alpha, _zone_alpha, _zone_sat = _cityOverlayParams(cs)
    Game._road_alpha = _road_alpha  -- stored so _drawCityOverlayVectors can read it

    -- LAYER: City background images (tiled, culled)
    -- Drawn after highways so the opaque image hides the in-city highway portion.
    if cs >= Z.CITY_IMAGE_THRESHOLD and not Game.overlay_only_mode then
        _zone_shader:send("saturation", _zone_sat)
        love.graphics.setShader(_zone_shader)
        love.graphics.setColor(1, 1, 1, _zone_alpha)
        for i = tile_i0, tile_i1 do
            for _, m in ipairs(Game.maps.all_cities or {}) do
                if m.city_image and cityInView(m, i * mpw) then
                    local K = m.city_img_K or 9
                    love.graphics.draw(m.city_image,
                        i * mpw + (m.city_img_min_x - 1) * ts,
                        (m.city_img_min_y - 1) * ts,
                        0, ts / K, ts / K)
                end
            end
        end
        love.graphics.setShader()
        love.graphics.setColor(1, 1, 1)
    end

    -- LAYER: City road/river overlays
    -- High zoom (cs >= OVERLAY_VECTOR_THRESHOLD): draw vectors directly — crisp at any zoom,
    --   fast because only ~1 city is visible at this scale.
    -- Low zoom (cs < OVERLAY_VECTOR_THRESHOLD): draw a cached canvas — multiple cities may be
    --   on screen simultaneously so the per-frame vector cost would be too high.
    if cs >= Z.CITY_IMAGE_THRESHOLD then
        local RS = require("utils.RoadSmoother")
        love.graphics.setColor(1, 1, 1)
        for i = tile_i0, tile_i1 do
            for _, m in ipairs(Game.maps.all_cities or {}) do
                if not cityInView(m, i * mpw) then goto continue_overlay end
                local m_ox = (m.world_mn_x - 1) * ts
                local m_oy = (m.world_mn_y - 1) * ts
                if cs >= OVERLAY_VECTOR_THRESHOLD then
                    -- High zoom: draw vectors directly; _road_alpha read inside via Game._road_alpha
                    _drawCityOverlayVectors(m, Game, RS, i * mpw + m_ox, m_oy)
                else
                    -- Low zoom: draw cached canvas; apply road_alpha at draw time (canvas baked at 1.0)
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
        Game._trip_preview_cache = nil
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

        -- Depot
        if cs >= Z.ZONE_THRESHOLD and Game.entities.depot_plot then
            local dp = Game.entities.depot_plot
            DrawingUtils.drawWorldIcon(Game, "🏢", (dp.x - 0.5) * uts, (dp.y - 0.5) * uts)
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

        -- Vehicles (viewport culled)
        for _, v in ipairs(Game.entities.vehicles) do
            if v.visible and v:shouldDrawAtCameraScale(Game)
            and v.px > vp_left and v.px < vp_right and v.py > vp_top and v.py < vp_bot then
                v:draw(Game)
            end
        end

        -- Debug vehicle overlay (viewport culled)
        if Game.debug_mode then
            for _, vehicle in ipairs(Game.entities.vehicles) do
                if vehicle.visible
                and vehicle.px > vp_left and vehicle.px < vp_right and vehicle.py > vp_top and vehicle.py < vp_bot then
                    vehicle:drawDebug(Game)
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
            local cache = Game._trip_preview_cache
            if not cache or cache.trip ~= htrip then
                Game._trip_preview_cache = nil
                local vtype = ((leg.vehicleType or "truck"):upper())
                local vp = Game.C.VEHICLES[vtype] or Game.C.VEHICLES.TRUCK
                local mock = {
                    operational_map_key = "unified",
                    grid_anchor         = leg.start_plot,
                    pathfinding_bounds  = nil,
                    type                = leg.vehicleType or "truck",
                    id                  = 0,
                    getMovementCostFor  = function(self, t) return vp.pathfinding_costs[t] or 9999 end,
                    getSpeed            = function(self) return vp.speed end,
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
                        Game._trip_preview_cache = {trip = htrip, pts = smoothed}
                    end
                end
            end
            local cache2 = Game._trip_preview_cache
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
                    [5]="water",[6]="mountain",[7]="river",[8]="plot",[9]="downtown_plot"}

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
                    dest = Game.entities.depot_plot
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
    if not active_map.district_map then return end

    local CoordSvc  = require("services.CoordinateService")
    local ZT        = require("data.zones")
    local ts        = Game.C.MAP.TILE_SIZE
    local tps       = active_map.tile_pixel_size or ts
    local city_mn_x = Game.world_gen_city_mn_x or 1
    local city_mn_y = Game.world_gen_city_mn_y or 1
    local dmap      = active_map.district_map
    local dtypes    = active_map.district_types
    local dcolors   = active_map.district_colors
    local pois      = active_map.district_pois
    local font      = Game.fonts and Game.fonts.ui_small

    -- Resolve hovered district first so tint pass can use it
    local hovered_poi = nil
    local mx, my = love.mouse.getPosition()
    if mx >= sidebar_w then
        local wx, wy = CoordSvc.screenToWorld(mx, my, Game.C, Game.camera)
        local lscx = math.floor((wx - (city_mn_x - 1) * ts) / tps)
        local lscy = math.floor((wy - (city_mn_y - 1) * ts) / tps)
        local gx, gy = lscx + 1, lscy + 1
        local grid_h = #active_map.grid
        local grid_w = grid_h > 0 and #(active_map.grid[1] or {}) or 0
        if gx >= 1 and gx <= grid_w and gy >= 1 and gy <= grid_h then
            local sci = ((active_map.zone_gscy_off or 0) + lscy) * (active_map.zone_sw or 1)
                      + (active_map.zone_gscx_off or 0) + lscx + 1
            hovered_poi = dmap[sci]
        end
    end

    -- Build excluded set: districts that cannot coexist with the hovered district
    local excluded = {}
    if hovered_poi and dtypes then
        local htype = dtypes[hovered_poi]
        local rules = ZT.DISTRICT_RULES or {}
        for other_poi, other_type in pairs(dtypes) do
            if other_poi ~= hovered_poi then
                local blocked = false
                local hr = rules[htype]
                if hr then
                    for _, c in ipairs(hr.cannot or {}) do
                        if c == other_type then blocked = true; break end
                    end
                end
                if not blocked then
                    local or_ = rules[other_type]
                    if or_ then
                        for _, c in ipairs(or_.cannot or {}) do
                            if c == htype then blocked = true; break end
                        end
                    end
                end
                if blocked then excluded[other_poi] = true end
            end
        end
    end

    local is_hovering = hovered_poi ~= nil

    -- Tint + interaction pass (inside camera transform)
    local vw = screen_w - sidebar_w
    love.graphics.push()
    love.graphics.translate(sidebar_w + vw / 2, screen_h / 2)
    love.graphics.scale(Game.camera.scale, Game.camera.scale)
    love.graphics.translate(-Game.camera.x, -Game.camera.y)
    local ox  = (city_mn_x - 1) * ts
    local oy  = (city_mn_y - 1) * ts
    local lw  = math.max(0.5, tps * 0.18)  -- hatch line width
    love.graphics.setLineWidth(lw)

    for gy = 1, #active_map.grid do
        for gx = 1, #active_map.grid[gy] do
            local lscx    = gx - 1
            local lscy    = gy - 1
            local sci     = ((active_map.zone_gscy_off or 0) + lscy) * (active_map.zone_sw or 1)
                          + (active_map.zone_gscx_off or 0) + lscx + 1
            local poi_idx = dmap[sci]
            local col     = poi_idx and dcolors and dcolors[poi_idx]
            if col then
                local cx = ox + lscx * tps
                local cy = oy + lscy * tps
                if poi_idx == hovered_poi then
                    -- Hovered: bright tint
                    love.graphics.setColor(col[1], col[2], col[3], 0.45)
                    love.graphics.rectangle("fill", cx, cy, tps, tps)
                elseif excluded[poi_idx] then
                    -- Excluded: dark tint + diagonal hatch lines
                    love.graphics.setColor(col[1] * 0.4, col[2] * 0.4, col[3] * 0.4, 0.55)
                    love.graphics.rectangle("fill", cx, cy, tps, tps)
                    love.graphics.setColor(0, 0, 0, 0.55)
                    love.graphics.line(cx, cy, cx + tps, cy + tps)
                    love.graphics.line(cx + tps, cy, cx, cy + tps)
                elseif is_hovering then
                    -- Other districts: slightly dimmed
                    love.graphics.setColor(col[1], col[2], col[3], 0.07)
                    love.graphics.rectangle("fill", cx, cy, tps, tps)
                else
                    -- No hover active: normal tint
                    love.graphics.setColor(col[1], col[2], col[3], 0.15)
                    love.graphics.rectangle("fill", cx, cy, tps, tps)
                end
            end
        end
    end
    love.graphics.setLineWidth(1)
    love.graphics.pop()

    -- District name labels (screen space)
    if pois and dtypes and dcolors and font then
        love.graphics.setFont(font)
        for poi_idx, poi in ipairs(pois) do
            local dtype = (dtypes[poi_idx] or "?"):gsub("_", " ")
            local wx = (poi.x - 1) * ts + ts * 0.5
            local wy = (poi.y - 1) * ts + ts * 0.5
            local sx, sy = CoordSvc.worldToScreen(wx, wy, Game.C, Game.camera)
            if sx > sidebar_w and sx < screen_w and sy > 0 and sy < screen_h then
                local col  = dcolors[poi_idx] or {1,1,1}
                local dim  = is_hovering and poi_idx ~= hovered_poi and not excluded[poi_idx]
                local tw   = font:getWidth(dtype)
                local th   = font:getHeight()
                local alpha = dim and 0.35 or 1.0
                love.graphics.setColor(0, 0, 0, 0.6 * alpha)
                love.graphics.rectangle("fill", sx - tw/2 - 3, sy - th/2 - 2, tw + 6, th + 4, 3)
                love.graphics.setColor(col[1], col[2], col[3], alpha)
                love.graphics.print(dtype, sx - tw/2, sy - th/2)
            end
        end
    end

    -- Hover tooltip
    if hovered_poi and font then
        local wx, wy = CoordSvc.screenToWorld(mx, my, Game.C, Game.camera)
        local lscx = math.floor((wx - (city_mn_x - 1) * ts) / tps)
        local lscy = math.floor((wy - (city_mn_y - 1) * ts) / tps)
        local gx, gy = lscx + 1, lscy + 1
        local grid_h = #active_map.grid
        local grid_w = grid_h > 0 and #(active_map.grid[1] or {}) or 0
        if gx >= 1 and gx <= grid_w and gy >= 1 and gy <= grid_h then
            local zone     = (active_map.zone_grid and active_map.zone_grid[gy] and active_map.zone_grid[gy][gx]) or "none"
            local district = (dtypes and dtypes[hovered_poi] or "residential"):gsub("_", " ")
            local line1 = "District: " .. district
            local line2 = "Zone: " .. zone
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
    end

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

    local n_bikes, n_trucks = 0, 0
    local states_count = {}
    for _, v in ipairs(vehicles) do
        if v.type == "bike"  then n_bikes  = n_bikes  + 1 end
        if v.type == "truck" then n_trucks = n_trucks + 1 end
        local sn = v.state and v.state.name or "?"
        states_count[sn] = (states_count[sn] or 0) + 1
    end
    local state_parts = {}
    for sn, cnt in pairs(states_count) do state_parts[#state_parts+1] = sn..":"..cnt end
    table.sort(state_parts)

    local PathScheduler    = require("services.PathScheduler")
    local PathCacheService = require("services.PathCacheService")
    local sched_queue = #PathScheduler._queue
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
        string.format("PathScheduler queue: %d / %d budget", sched_queue, PathScheduler.budget),
        string.format("PathCache entries:   %d / 3000", cache_entries),
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
        string.format("Vehicles:  %d  (bikes %d  trucks %d)", #vehicles, n_bikes, n_trucks),
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

function GameView:draw()
    local Game = self.Game
    local active_map = Game.maps[Game.active_map_key]
    if not active_map then return end
    local sidebar_w  = Game.C.UI.SIDEBAR_WIDTH
    local screen_w, screen_h = love.graphics.getDimensions()
    local S          = Game.C.MAP.SCALES
    local cur_scale  = Game.state.current_map_scale
    local ui_manager = Game.ui_manager
    love.graphics.setScissor(sidebar_w, 0, screen_w - sidebar_w, screen_h)
    if Game.world_gen_cam_params then
        self:_drawWorldGenMode(active_map, ui_manager, sidebar_w, screen_w, screen_h)
        self:_drawDistrictOverlay(active_map, sidebar_w, screen_w, screen_h)
        self:_drawBiomeOverlay(active_map, sidebar_w, screen_w, screen_h)
        self:_drawUnifiedGridOverlay(sidebar_w, screen_w, screen_h)
    else
        self:_drawTileGridFallback(active_map, S, cur_scale, ui_manager, sidebar_w, screen_w, screen_h)
    end
    self:_drawFloatingTexts(sidebar_w, screen_w, screen_h)
    love.graphics.setScissor()
    if Game.debug_f3 then self:_drawF3Overlay() end
end

return GameView