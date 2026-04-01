-- views/GameView.lua
-- Updated to render edge-based streets between grid cells
local Bike = require("models.vehicles.Bike")
local Truck = require("models.vehicles.Truck")
local FloatingTextSystem = require("services.FloatingTextSystem")


local GameView = {}
GameView.__index = GameView

function GameView:new(game_instance)
    local instance = setmetatable({}, GameView)
    instance.Game = game_instance
    return instance
end

-- Returns the love.graphics.Image for the given game scale (or nil if world gen not loaded)
function GameView:_getScaleImage(scale)
    local G = self.Game
    local S = G.C.MAP.SCALES
    if     scale == S.DOWNTOWN  then return G.world_gen_downtown_fogged_image or G.world_gen_city_image
    elseif scale == S.CITY      then return G.world_gen_city_image
    elseif scale == S.REGION    then return G.world_gen_region_image
    elseif scale == S.CONTINENT then return G.world_gen_continent_image
    elseif scale == S.WORLD     then return G.world_gen_world_image
    end
end

-- Draw a fitted image in the game area (no camera transform). Returns ox,oy,scl.
function GameView:_drawFitImage(img, sidebar_w, screen_w, screen_h)
    local game_world_w = screen_w - sidebar_w
    local iw, ih = img:getDimensions()
    local scl = math.min(game_world_w / iw, screen_h / ih)
    local ox  = sidebar_w + (game_world_w - iw * scl) / 2
    local oy  = (screen_h - ih * scl) / 2
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, ox, oy, 0, scl, scl)
    return ox, oy, scl, iw, ih
end

-- Draw vehicles/depot/clients at DOWNTOWN scale overlaid on the F8 city scope image.
-- The F8 image has CELL=9 pixels per world cell with origin at (img_x, img_y) in world coords.
-- Vehicle px/py are city-local tile pixels: local_x = px/TILE + 0.5, world_x = local_x + city_mn_x - 1.
function GameView:_drawEntitiesOnCityImage(ox, oy, scl, img_x, img_y)
    local Game = self.Game
    local DrawingUtils = require("utils.DrawingUtils")
    local CELL     = 9                       -- F8 pixels per world cell
    local TILE     = Game.C.MAP.TILE_SIZE    -- 2
    local city_x   = Game.world_gen_city_mn_x or 1
    local city_y   = Game.world_gen_city_mn_y or 1

    -- Map city-local tile pixel → screen position on the F8 image
    local function tilePixToScreen(tpx, tpy)
        local world_x = tpx / TILE + city_x - 0.5
        local world_y = tpy / TILE + city_y - 0.5
        local sx = ox + (world_x - img_x + 0.5) * CELL * scl
        local sy = oy + (world_y - img_y + 0.5) * CELL * scl
        return sx, sy
    end

    -- Set a virtual camera so Vehicle:draw() and drawWorldIcon() place things correctly.
    -- Standard transform: screen = center + (tpx - cam_x) * cam_scale
    -- We want:            screen = ox + (world_x - img_x + 0.5) * CELL * scl
    --                            = ox + (tpx/TILE + city_x - img_x) * CELL * scl
    -- Matching: cam_scale = CELL/TILE * scl,   cam_x centers the image
    local game_world_w = love.graphics.getWidth() - Game.C.UI.SIDEBAR_WIDTH
    local cam_scale    = CELL / TILE * scl       -- = 4.5 * scl
    local cam_x = (Game.C.UI.SIDEBAR_WIDTH + game_world_w / 2
                   - ox - (city_x - img_x) * CELL * scl) / cam_scale
    local cam_y = (love.graphics.getHeight() / 2
                   - oy - (city_y - img_y) * CELL * scl) / cam_scale

    -- Temporarily override camera for drawWorldIcon / Vehicle:draw
    local old_cx, old_cy, old_cs = Game.camera.x, Game.camera.y, Game.camera.scale
    Game.camera.x = cam_x;  Game.camera.y = cam_y;  Game.camera.scale = cam_scale

    love.graphics.push()
    love.graphics.translate(Game.C.UI.SIDEBAR_WIDTH + game_world_w / 2, love.graphics.getHeight() / 2)
    love.graphics.scale(cam_scale, cam_scale)
    love.graphics.translate(-cam_x, -cam_y)

    local active_map = Game.maps[Game.active_map_key]

    -- Depot
    if Game.entities.depot_plot then
        local dp = Game.entities.depot_plot
        local dpx, dpy = active_map:getPixelCoords(dp.x, dp.y)
        DrawingUtils.drawWorldIcon(Game, "🏢", dpx, dpy)
    end
    -- Clients
    for _, client in ipairs(Game.entities.clients) do
        DrawingUtils.drawWorldIcon(Game, "🏠", client.px, client.py)
    end
    -- Vehicles
    for _, v in ipairs(Game.entities.vehicles) do
        if v.visible then v:draw(Game) end
    end

    love.graphics.pop()

    -- Restore camera
    Game.camera.x = old_cx; Game.camera.y = old_cy; Game.camera.scale = old_cs
end

function GameView:_drawFloatingTexts(sidebar_w, screen_w, screen_h)
    local Game = self.Game
    local texts = FloatingTextSystem.getTexts()
    if #texts == 0 then return end
    local game_world_w = screen_w - sidebar_w
    local cx, cy = Game.camera.x, Game.camera.y
    local cs = Game.camera.scale
    local ft_ox, ft_oy = 0, 0
    if Game.world_gen_cam_params then
        local ts = Game.C.MAP.TILE_SIZE
        ft_ox = ((Game.world_gen_city_mn_x or 1) - 1) * ts
        ft_oy = ((Game.world_gen_city_mn_y or 1) - 1) * ts
    end
    love.graphics.setFont(Game.fonts.ui)
    for _, ft in ipairs(texts) do
        local sx = sidebar_w + game_world_w / 2 + (ft.x + ft_ox - cx) * cs
        local sy = screen_h / 2 + (ft.y + ft_oy - cy) * cs
        love.graphics.setColor(1, 1, 0.3, ft.alpha)
        love.graphics.printf(ft.text, sx - 60, sy, 120, "center")
    end
end

function GameView:_drawTileGridFallback(active_map, S, cur_scale, ui_manager, sidebar_w, screen_w, screen_h)
    local Game = self.Game
    local DrawingUtils = require("utils.DrawingUtils")
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
        if vehicle.visible then vehicle:draw(Game) end
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
            if vehicle.visible then vehicle:drawDebug(Game) end
        end
    end
    love.graphics.pop()
end

function GameView:_drawWorldGenMode(active_map, S, cur_scale, ui_manager, sidebar_w, screen_w, screen_h)
    local Game = self.Game
    local DrawingUtils = require("utils.DrawingUtils")
    local ts  = Game.C.MAP.TILE_SIZE
    local vw  = screen_w - sidebar_w

    -- ── World-gen camera-based rendering (mirrors WorldSandboxView exactly) ──
        love.graphics.setColor(0.04, 0.04, 0.07)
        love.graphics.rectangle("fill", sidebar_w, 0, vw, screen_h)

        love.graphics.push()
        love.graphics.translate(sidebar_w + vw / 2, screen_h / 2)
        love.graphics.scale(Game.camera.scale, Game.camera.scale)
        love.graphics.translate(-Game.camera.x, -Game.camera.y)
        love.graphics.setColor(1, 1, 1)

        local city_bg = Game.world_gen_city_image
        if (cur_scale == S.DOWNTOWN or cur_scale == S.CITY) and city_bg then
            if not Game.overlay_only_mode and not Game.debug_hide_roads then
                local bg = (cur_scale == S.DOWNTOWN and (Game.world_gen_downtown_fogged_image or city_bg)) or city_bg
                local K  = Game.world_gen_city_img_K or 9
                local ox = (Game.world_gen_city_img_min_x - 1) * ts
                local oy = (Game.world_gen_city_img_min_y - 1) * ts
                love.graphics.draw(bg, ox, oy, 0, ts / K, ts / K)
            end
        elseif cur_scale == S.REGION and Game.world_gen_region_image then
            love.graphics.draw(Game.world_gen_region_image, 0, 0, 0, ts, ts)
        elseif cur_scale == S.CONTINENT and Game.world_gen_continent_image then
            love.graphics.draw(Game.world_gen_continent_image, 0, 0, 0, ts, ts)
        elseif cur_scale == S.WORLD and Game.world_gen_world_image then
            love.graphics.draw(Game.world_gen_world_image, 0, 0, 0, ts, ts)
        end

        -- At DOWNTOWN: draw entities translated into world-pixel space
        if cur_scale == S.DOWNTOWN then
            local city_mn_x = Game.world_gen_city_mn_x or 1
            local city_mn_y = Game.world_gen_city_mn_y or 1
            love.graphics.translate((city_mn_x - 1) * ts, (city_mn_y - 1) * ts)

            -- Zone grid overlay: one pass over all tiles, each drawn exactly once
            if not Game.overlay_only_mode and active_map.zone_grid and active_map.all_city_plots then
                local ZT   = require("data.zones")
                local zg   = active_map.zone_grid
                local tps  = active_map.tile_pixel_size or Game.C.MAP.TILE_SIZE
                local dirs = {{0,-1},{0,1},{-1,0},{1,0}}
                for gy = 1, #active_map.grid do
                    local row  = active_map.grid[gy]
                    local zrow = zg[gy]
                    for gx = 1, #row do
                        local col = zrow and ZT.COLORS[zrow[gx]]
                        if not col then
                            -- non-zone tile: sample adjacent zone color
                            for _, d in ipairs(dirs) do
                                local nz = zg[gy+d[2]] and zg[gy+d[2]][gx+d[1]]
                                if nz then col = ZT.COLORS[nz]; if col then break end end
                            end
                        end
                        if col then
                            love.graphics.setColor(col[1], col[2], col[3], ZT.COLOR_ALPHA)
                            love.graphics.rectangle("fill", (gx-1)*tps, (gy-1)*tps, tps, tps)
                        end
                    end
                end
            end

            -- Street overlay (zone-boundary city streets)
            if Game.debug_smooth_streets then do
                local tps_r = active_map.tile_pixel_size or Game.C.MAP.TILE_SIZE
                if not active_map._street_smooth_paths_v7 then
                    local RS = require("utils.RoadSmoother")
                    active_map._street_smooth_paths_v7 = RS.buildStreetPaths(
                        active_map.zone_seg_v, active_map.zone_seg_h, active_map.zone_grid, tps_r, active_map.grid)
                end
                if #active_map._street_smooth_paths_v7 > 0 then
                    love.graphics.setColor(0.85, 0.78, 0.55, 0.88)
                    love.graphics.setLineWidth(tps_r * 0.35)
                    love.graphics.setLineStyle("smooth")
                    love.graphics.setLineJoin("miter")
                    for _, pts in ipairs(active_map._street_smooth_paths_v7) do
                        love.graphics.line(pts)
                    end
                    love.graphics.setLineStyle("rough")
                    love.graphics.setLineWidth(1)
                    love.graphics.setLineJoin("miter")
                    love.graphics.setColor(1, 1, 1)
                end
            end end  -- Street overlay / debug_smooth_streets

            -- Merged street overlay (M hotkey — old pre-split approach for comparison)
            if Game.debug_smooth_roads_merged then do
                local tps_r = active_map.tile_pixel_size or Game.C.MAP.TILE_SIZE
                if not active_map._street_smooth_paths_merged_v1 then
                    local RS = require("utils.RoadSmoother")
                    active_map._street_smooth_paths_merged_v1 = RS.buildStreetPathsMerged(
                        active_map.zone_seg_v, active_map.zone_seg_h, active_map.zone_grid, tps_r, active_map.grid)
                end
                if #active_map._street_smooth_paths_merged_v1 > 0 then
                    love.graphics.setColor(0.85, 0.78, 0.55, 0.88)
                    love.graphics.setLineWidth(tps_r * 0.35)
                    love.graphics.setLineStyle("smooth")
                    love.graphics.setLineJoin("miter")
                    for _, pts in ipairs(active_map._street_smooth_paths_merged_v1) do
                        love.graphics.line(pts)
                    end
                    love.graphics.setLineStyle("rough")
                    love.graphics.setLineWidth(1)
                    love.graphics.setLineJoin("miter")
                    love.graphics.setColor(1, 1, 1)
                end
            end end  -- Merged street overlay / debug_smooth_roads_merged

            -- Streets-like-big-roads overlay (J hotkey)
            if Game.debug_smooth_roads_like then do
                local tps_r = active_map.tile_pixel_size or Game.C.MAP.TILE_SIZE
                if not active_map._street_smooth_paths_like_v5 then
                    local RS = require("utils.RoadSmoother")
                    active_map._street_smooth_paths_like_v5 = RS.buildStreetPathsLike(
                        active_map.zone_seg_v, active_map.zone_seg_h, active_map.zone_grid, tps_r, active_map.grid)
                end
                if active_map._street_smooth_paths_like_v5 and #active_map._street_smooth_paths_like_v5 > 0 then
                    love.graphics.setColor(0.30, 0.29, 0.28, 1.0)
                    love.graphics.setLineWidth(tps_r * 0.35)
                    love.graphics.setLineStyle("smooth")
                    love.graphics.setLineJoin("miter")
                    for _, pts in ipairs(active_map._street_smooth_paths_like_v5) do
                        love.graphics.line(pts)
                    end
                    love.graphics.setLineStyle("rough")
                    love.graphics.setLineWidth(1)
                    love.graphics.setLineJoin("miter")
                    love.graphics.setColor(1, 1, 1)
                end
            end end  -- Streets-like-big-roads overlay / debug_smooth_roads_like

            -- Smooth road overlay (arterial / highway)
            if Game.debug_smooth_roads then do
                local tps_r = active_map.tile_pixel_size or Game.C.MAP.TILE_SIZE
                if not active_map._road_smooth_paths_v8 then
                    local RS = require("utils.RoadSmoother")
                    if active_map.road_centerlines and #active_map.road_centerlines > 0 then
                        active_map._road_smooth_paths_v8 = RS.buildPathsFromCenterlines(active_map.road_centerlines, tps_r)
                    else
                        active_map._road_smooth_paths_v8 = RS.buildPaths(active_map.grid, tps_r)
                    end
                end
                if #active_map._road_smooth_paths_v8 > 0 then
                    local cap_r = tps_r * 0.35   -- half line-width → fills junction gaps
                    love.graphics.setColor(0.22, 0.21, 0.20, 1.0)
                    love.graphics.setLineWidth(tps_r * 0.7)
                    love.graphics.setLineJoin("bevel")
                    for _, pts in ipairs(active_map._road_smooth_paths_v8) do
                        if #pts >= 4 then
                            love.graphics.line(pts)
                            love.graphics.circle("fill", pts[1],      pts[2],      cap_r)
                            love.graphics.circle("fill", pts[#pts-1], pts[#pts],   cap_r)
                        end
                    end
                    love.graphics.setLineWidth(1)
                    love.graphics.setLineJoin("miter")
                    love.graphics.setColor(1, 1, 1)
                end
            end end  -- Arterial overlay / debug_smooth_roads

            -- Entities drawn on top of all road overlays
            if Game.entities.depot_plot then
                local dp = Game.entities.depot_plot
                local dpx, dpy = active_map:getPixelCoords(dp.x, dp.y)
                DrawingUtils.drawWorldIcon(Game, "🏢", dpx, dpy)
            end
            for _, client in ipairs(Game.entities.clients) do
                DrawingUtils.drawWorldIcon(Game, "🏠", client.px, client.py)
            end
            for _, v in ipairs(Game.entities.vehicles) do
                if v.visible then v:draw(Game) end
            end
            -- Debug overlays (world-gen mode)
            do
                local tps_dbg = active_map.tile_pixel_size or Game.C.MAP.TILE_SIZE

                -- [B] Building plots: blue highlight on every valid building sub-cell
                if Game.debug_building_plots and active_map.building_plots then
                    love.graphics.setColor(0.2, 0.5, 1, 0.35)
                    for _, plot in ipairs(active_map.building_plots) do
                        love.graphics.rectangle("fill",
                            (plot.x - 1) * tps_dbg, (plot.y - 1) * tps_dbg,
                            tps_dbg, tps_dbg)
                    end

                    -- Hover: highlight the cell under the mouse and show what road it's beside
                    -- screenToWorld returns world-pixel coords; drawing is offset by city origin,
                    -- so subtract that to get local sub-cell pixel coords.
                    local mx, my = love.mouse.getPosition()
                    local wx, wy = Game.camera:screenToWorld(mx, my, Game)
                    local ts_full = Game.C.MAP.TILE_SIZE
                    local c_off_x = (Game.world_gen_city_mn_x or 1) - 1
                    local c_off_y = (Game.world_gen_city_mn_y or 1) - 1
                    local lwx = wx - c_off_x * ts_full
                    local lwy = wy - c_off_y * ts_full
                    local hgx = math.floor(lwx / tps_dbg) + 1
                    local hgy = math.floor(lwy / tps_dbg) + 1
                    local grid_w = active_map.grid and #(active_map.grid[1] or {}) or 0
                    local grid_h = active_map.grid and #active_map.grid or 0
                    if hgx >= 1 and hgx <= grid_w and hgy >= 1 and hgy <= grid_h then
                        local ht = active_map.grid[hgy][hgx].type
                        if ht == "plot" or ht == "downtown_plot" then
                            -- Bright white outline on the hovered cell
                            love.graphics.setColor(1, 1, 1, 0.9)
                            love.graphics.rectangle("line",
                                (hgx-1)*tps_dbg + 1, (hgy-1)*tps_dbg + 1,
                                tps_dbg - 2, tps_dbg - 2)

                            local rv = active_map.road_v_rxs or {}
                            local rh = active_map.road_h_rys or {}
                            local lw = math.max(2, tps_dbg * 0.25)

                            -- Yellow vertical road lines this cell is beside
                            if rv[hgx-1] then  -- road line to the left
                                love.graphics.setColor(1, 1, 0, 1)
                                love.graphics.rectangle("fill",
                                    (hgx-1)*tps_dbg - lw*0.5, (hgy-1)*tps_dbg,
                                    lw, tps_dbg)
                            end
                            if rv[hgx] then  -- road line to the right
                                love.graphics.setColor(1, 1, 0, 1)
                                love.graphics.rectangle("fill",
                                    hgx*tps_dbg - lw*0.5, (hgy-1)*tps_dbg,
                                    lw, tps_dbg)
                            end
                            -- Orange horizontal road lines this cell is beside
                            if rh[hgy-1] then  -- road line above
                                love.graphics.setColor(1, 0.5, 0, 1)
                                love.graphics.rectangle("fill",
                                    (hgx-1)*tps_dbg, (hgy-1)*tps_dbg - lw*0.5,
                                    tps_dbg, lw)
                            end
                            if rh[hgy] then  -- road line below
                                love.graphics.setColor(1, 0.5, 0, 1)
                                love.graphics.rectangle("fill",
                                    (hgx-1)*tps_dbg, hgy*tps_dbg - lw*0.5,
                                    tps_dbg, lw)
                            end
                            -- Green: adjacent arterial/highway tile
                            for _, d in ipairs({{-1,0},{1,0},{0,-1},{0,1}}) do
                                local nx, ny = hgx+d[1], hgy+d[2]
                                if nx >= 1 and nx <= grid_w and ny >= 1 and ny <= grid_h then
                                    local tt = active_map.grid[ny][nx].type
                                    if tt == "arterial" or tt == "highway" then
                                        love.graphics.setColor(0, 1, 0, 0.6)
                                        love.graphics.rectangle("fill",
                                            (nx-1)*tps_dbg, (ny-1)*tps_dbg,
                                            tps_dbg, tps_dbg)
                                    end
                                end
                            end
                        end
                    end
                end

                -- [P] Client/pickup overlay: orange dot at client plot, green dots at
                -- adjacent road_nodes, cyan dots at pending-trip start_plots.
                if Game.debug_pickup_locations then
                    local r = tps_dbg * 0.3
                    for _, client in ipairs(Game.entities.clients) do
                        -- Client sub-cell centre (where the house icon is)
                        love.graphics.setColor(1, 0.5, 0, 0.8)
                        love.graphics.circle("fill", client.px, client.py, r)
                        -- Adjacent road_nodes (where a vehicle can stop for pickup)
                        if active_map.road_nodes then
                            local gx, gy = client.plot.x, client.plot.y
                            for _, c in ipairs({{gx-1,gy-1},{gx,gy-1},{gx-1,gy},{gx,gy}}) do
                                local rx, ry = c[1], c[2]
                                if active_map.road_nodes[ry] and active_map.road_nodes[ry][rx] then
                                    love.graphics.setColor(0, 1, 0, 0.9)
                                    love.graphics.circle("fill", rx * tps_dbg, ry * tps_dbg, tps_dbg * 0.2)
                                end
                            end
                        end
                    end
                    -- Pending trip start_plots
                    love.graphics.setColor(0, 1, 1, 0.8)
                    local r2 = tps_dbg * 0.2
                    for _, trip in ipairs(Game.entities.trips.pending) do
                        local leg = trip.legs and trip.legs[trip.current_leg]
                        if leg and leg.start_plot then
                            local spx, spy = active_map:getPixelCoords(leg.start_plot.x, leg.start_plot.y)
                            love.graphics.circle("fill", spx, spy, r2)
                        end
                    end
                end

                -- [Tab] Vehicle paths and debug boxes
                if Game.debug_mode then
                    for _, vehicle in ipairs(Game.entities.vehicles) do
                        if vehicle.visible then vehicle:drawDebug(Game) end
                    end
                end

                -- [G] Road segment overlay: every segment the pathfinder can traverse.
                -- Green lines = zone_seg_v (N/S traversable gap between zone columns).
                -- Blue  lines = zone_seg_h (E/W traversable gap between zone rows).
                if Game.debug_road_segments and active_map.zone_seg_v then
                    local zsv = active_map.zone_seg_v
                    local zsh = active_map.zone_seg_h
                    local scale = Game.camera and Game.camera.scale or 1
                    love.graphics.setLineWidth(4 / scale)
                    -- zone_seg_v[gy][rx]: vertical line at x=rx*tps, y (gy-1)*tps → gy*tps
                    love.graphics.setColor(0, 1, 0.2, 0.9)
                    for gy, row in pairs(zsv) do
                        for rx in pairs(row) do
                            love.graphics.line(
                                rx * tps_dbg, (gy - 1) * tps_dbg,
                                rx * tps_dbg, gy * tps_dbg)
                        end
                    end
                    -- zone_seg_h[ry][gx]: horizontal line at y=ry*tps, x (gx-1)*tps → gx*tps
                    love.graphics.setColor(0.2, 0.5, 1, 0.9)
                    for ry, row in pairs(zsh) do
                        for gx in pairs(row) do
                            love.graphics.line(
                                (gx - 1) * tps_dbg, ry * tps_dbg,
                                gx * tps_dbg, ry * tps_dbg)
                        end
                    end
                    love.graphics.setLineWidth(1)
                end

                love.graphics.setColor(1, 1, 1)
            end

            -- Trip route preview on hover (same as tile-grid branch)
            if ui_manager.hovered_trip_index then
                local trip = Game.entities.trips.pending[ui_manager.hovered_trip_index]
                if trip and trip.legs[trip.current_leg] then
                    local leg = trip.legs[trip.current_leg]
                    local is_rn = active_map.road_v_rxs ~= nil
                    local start_node = is_rn and active_map:findNearestRoadNode(leg.start_plot)
                                               or active_map:findNearestRoadTile(leg.start_plot)
                    local end_node   = is_rn and active_map:findNearestRoadNode(leg.end_plot)
                                               or active_map:findNearestRoadTile(leg.end_plot)
                    if start_node and end_node and active_map.grid then
                        local vp = (leg.vehicleType == "bike") and Game.C.VEHICLES.BIKE or Game.C.VEHICLES.TRUCK
                        local cost_fn
                        if is_rn then
                            cost_fn = function(rx, ry)
                                local tile = active_map.grid[ry+1] and active_map.grid[ry+1][rx+1]
                                return tile and (vp.pathfinding_costs[tile.type] or 9999) or 9999
                            end
                        else
                            cost_fn = function(x, y)
                                local tile = active_map.grid[y] and active_map.grid[y][x]
                                return tile and (vp.pathfinding_costs[tile.type] or 9999) or 9999
                            end
                        end
                        local path = Game.pathfinder.findPath(active_map.grid, start_node, end_node, cost_fn, active_map)
                        if path and #path >= 2 then
                            local pixel_path = {}
                            local tps_pv = active_map.tile_pixel_size or Game.C.MAP.TILE_SIZE
                            for _, node in ipairs(path) do
                                local px, py
                                if is_rn then
                                    if node.is_tile then
                                        px, py = (node.x + 0.5) * tps_pv, (node.y + 0.5) * tps_pv
                                    else
                                        px, py = node.x * tps_pv, node.y * tps_pv
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
                        end
                    end
                end
            end
        end

        -- Zone overlay + debug at CITY scale (world-pixel coords, no city translate active)
        if cur_scale == S.CITY then
            local tps = active_map.tile_pixel_size or Game.C.MAP.TILE_SIZE
            local ox  = (Game.world_gen_city_mn_x - 1) * ts
            local oy  = (Game.world_gen_city_mn_y - 1) * ts

            -- Zone grid overlay: one pass over all tiles, each drawn exactly once
            if not Game.overlay_only_mode and active_map.zone_grid and active_map.all_city_plots then
                local ZT   = require("data.zones")
                local zg   = active_map.zone_grid
                local dirs = {{0,-1},{0,1},{-1,0},{1,0}}
                for gy = 1, #active_map.grid do
                    local row  = active_map.grid[gy]
                    local zrow = zg[gy]
                    for gx = 1, #row do
                        local col = zrow and ZT.COLORS[zrow[gx]]
                        if not col then
                            local t = row[gx].type
                            if t == "arterial" or t == "highway" then
                                for _, d in ipairs(dirs) do
                                    local nz = zg[gy+d[2]] and zg[gy+d[2]][gx+d[1]]
                                    if nz then col = ZT.COLORS[nz]; if col then break end end
                                end
                            end
                        end
                        if col then
                            love.graphics.setColor(col[1], col[2], col[3], ZT.COLOR_ALPHA)
                            love.graphics.rectangle("fill", ox + (gx-1)*tps, oy + (gy-1)*tps, tps, tps)
                        end
                    end
                end
            end

            -- Street overlay at CITY scale (zone-boundary city streets, offset by ox,oy)
            if Game.debug_smooth_streets then do
                if not active_map._street_smooth_paths_v7 then
                    local RS = require("utils.RoadSmoother")
                    active_map._street_smooth_paths_v7 = RS.buildStreetPaths(
                        active_map.zone_seg_v, active_map.zone_seg_h, active_map.zone_grid, tps, active_map.grid)
                end
                if #active_map._street_smooth_paths_v7 > 0 then
                    love.graphics.setColor(0.85, 0.78, 0.55, 0.88)
                    love.graphics.setLineWidth(tps * 0.35)
                    love.graphics.setLineStyle("smooth")
                    love.graphics.setLineJoin("miter")
                    for _, pts in ipairs(active_map._street_smooth_paths_v7) do
                        if #pts >= 4 then
                            local shifted = {}
                            for i = 1, #pts, 2 do
                                shifted[i]   = ox + pts[i]
                                shifted[i+1] = oy + pts[i+1]
                            end
                            love.graphics.line(shifted)
                        end
                    end
                    love.graphics.setLineStyle("rough")
                    love.graphics.setLineWidth(1)
                    love.graphics.setLineJoin("miter")
                    love.graphics.setColor(1, 1, 1)
                end
            end end  -- Street overlay CITY / debug_smooth_streets

            -- Merged street overlay CITY (M hotkey)
            if Game.debug_smooth_roads_merged then do
                if not active_map._street_smooth_paths_merged_v1 then
                    local RS = require("utils.RoadSmoother")
                    active_map._street_smooth_paths_merged_v1 = RS.buildStreetPathsMerged(
                        active_map.zone_seg_v, active_map.zone_seg_h, active_map.zone_grid, tps, active_map.grid)
                end
                if #active_map._street_smooth_paths_merged_v1 > 0 then
                    love.graphics.setColor(0.85, 0.78, 0.55, 0.88)
                    love.graphics.setLineWidth(tps * 0.35)
                    love.graphics.setLineStyle("smooth")
                    love.graphics.setLineJoin("miter")
                    for _, pts in ipairs(active_map._street_smooth_paths_merged_v1) do
                        local shifted = {}
                        for i = 1, #pts, 2 do shifted[i] = ox + pts[i]; shifted[i+1] = oy + pts[i+1] end
                        love.graphics.line(shifted)
                    end
                    love.graphics.setLineStyle("rough")
                    love.graphics.setLineWidth(1)
                    love.graphics.setLineJoin("miter")
                    love.graphics.setColor(1, 1, 1)
                end
            end end  -- Merged street overlay CITY / debug_smooth_roads_merged

            -- Streets-like-big-roads overlay CITY (J hotkey)
            if Game.debug_smooth_roads_like then do
                if not active_map._street_smooth_paths_like_v5 then
                    local RS = require("utils.RoadSmoother")
                    active_map._street_smooth_paths_like_v5 = RS.buildStreetPathsLike(
                        active_map.zone_seg_v, active_map.zone_seg_h, active_map.zone_grid, tps, active_map.grid)
                end
                if active_map._street_smooth_paths_like_v5 and #active_map._street_smooth_paths_like_v5 > 0 then
                    love.graphics.setColor(0.30, 0.29, 0.28, 1.0)
                    love.graphics.setLineWidth(tps * 0.35)
                    love.graphics.setLineStyle("smooth")
                    love.graphics.setLineJoin("miter")
                    for _, pts in ipairs(active_map._street_smooth_paths_like_v5) do
                        local shifted = {}
                        for i = 1, #pts, 2 do shifted[i] = ox + pts[i]; shifted[i+1] = oy + pts[i+1] end
                        love.graphics.line(shifted)
                    end
                    love.graphics.setLineStyle("rough")
                    love.graphics.setLineWidth(1)
                    love.graphics.setLineJoin("miter")
                    love.graphics.setColor(1, 1, 1)
                end
            end end  -- Streets-like-big-roads overlay CITY / debug_smooth_roads_like

            -- Smooth road overlay at CITY scale (same paths as downtown, offset by ox,oy)
            if Game.debug_smooth_roads then do
                if not active_map._road_smooth_paths_v8 then
                    local RS = require("utils.RoadSmoother")
                    if active_map.road_centerlines and #active_map.road_centerlines > 0 then
                        active_map._road_smooth_paths_v8 = RS.buildPathsFromCenterlines(active_map.road_centerlines, tps)
                    else
                        active_map._road_smooth_paths_v8 = RS.buildPaths(active_map.grid, tps)
                    end
                end
                if #active_map._road_smooth_paths_v8 > 0 then
                    -- Build offset paths on the fly (city origin ox,oy)
                    local cap_r = tps * 0.35
                    love.graphics.setColor(0.22, 0.21, 0.20, 1.0)
                    love.graphics.setLineWidth(tps * 0.7)
                    love.graphics.setLineJoin("bevel")
                    for _, pts in ipairs(active_map._road_smooth_paths_v8) do
                        if #pts >= 4 then
                            local shifted = {}
                            for i = 1, #pts, 2 do
                                shifted[i]   = ox + pts[i]
                                shifted[i+1] = oy + pts[i+1]
                            end
                            love.graphics.line(shifted)
                            love.graphics.circle("fill", shifted[1],         shifted[2],         cap_r)
                            love.graphics.circle("fill", shifted[#shifted-1], shifted[#shifted], cap_r)
                        end
                    end
                    love.graphics.setLineWidth(1)
                    love.graphics.setLineJoin("miter")
                    love.graphics.setColor(1, 1, 1)
                end
            end end  -- Arterial overlay CITY / debug_smooth_roads

            -- Entities drawn on top of all road overlays (CITY scale)
            love.graphics.push()
            love.graphics.translate(ox, oy)
            if Game.entities.depot_plot then
                local dp = Game.entities.depot_plot
                local dpx, dpy = active_map:getPixelCoords(dp.x, dp.y)
                DrawingUtils.drawWorldIcon(Game, "🏢", dpx, dpy)
            end
            for _, client in ipairs(Game.entities.clients) do
                DrawingUtils.drawWorldIcon(Game, "🏠", client.px, client.py)
            end
            for _, v in ipairs(Game.entities.vehicles) do
                if v.visible then v:draw(Game) end
            end
            if Game.event_spawner and Game.event_spawner.clickable then
                local ec = Game.event_spawner.clickable
                DrawingUtils.drawWorldIcon(Game, "☎️", ec.x, ec.y)
            end
            if Game.debug_mode then
                for _, vehicle in ipairs(Game.entities.vehicles) do
                    if vehicle.visible then vehicle:drawDebug(Game) end
                end
            end
            love.graphics.pop()
            love.graphics.setColor(1, 1, 1)

            -- [G] Road segment overlay at CITY scale
            if Game.debug_road_segments and active_map.zone_seg_v then
                local zsv    = active_map.zone_seg_v
                local zsh    = active_map.zone_seg_h
                local scale  = Game.camera and Game.camera.scale or 1
                local tps_dbg = tps
                love.graphics.setLineWidth(4 / scale)
                love.graphics.setColor(0, 1, 0.2, 0.9)
                for gy, row in pairs(zsv) do
                    for rx in pairs(row) do
                        love.graphics.line(
                            ox + rx * tps_dbg,       oy + (gy - 1) * tps_dbg,
                            ox + rx * tps_dbg,       oy + gy * tps_dbg)
                    end
                end
                love.graphics.setColor(0.2, 0.5, 1, 0.9)
                for ry, row in pairs(zsh) do
                    for gx in pairs(row) do
                        love.graphics.line(
                            ox + (gx - 1) * tps_dbg, oy + ry * tps_dbg,
                            ox + gx * tps_dbg,        oy + ry * tps_dbg)
                    end
                end
                love.graphics.setLineWidth(1)
            end
        end

        -- Fog non-downtown subcells at DOWNTOWN scale
        if cur_scale == S.DOWNTOWN then
            local ds  = active_map.downtown_subcells
            local tps = active_map.tile_pixel_size or Game.C.MAP.TILE_SIZE
            if ds and #active_map.grid > 0 and #active_map.grid[1] > 0 then
                local cw = #active_map.grid[1] * tps
                local ch = #active_map.grid    * tps
                love.graphics.stencil(function()
                    for gy, row in pairs(ds) do
                        for gx in pairs(row) do
                            love.graphics.rectangle("fill", (gx-1)*tps, (gy-1)*tps, tps, tps)
                        end
                    end
                end, "replace", 1)
                love.graphics.setStencilTest("notequal", 1)
                love.graphics.setColor(0, 0, 0, 0.72)
                love.graphics.rectangle("fill", 0, 0, cw, ch)
                love.graphics.setStencilTest()
            end
        end

        -- Draw event spawner icon on top of everything (including fog).
        -- At DOWNTOWN the city-translate from above is still active, so local coords work directly.
        -- At CITY it is already drawn in the entity block above.
        -- At outer scales we need to apply the city-origin translate ourselves.
        if Game.event_spawner and Game.event_spawner.clickable then
            local ec = Game.event_spawner.clickable
            if cur_scale == S.DOWNTOWN then
                DrawingUtils.drawWorldIcon(Game, "☎️", ec.x, ec.y)
            elseif cur_scale == S.REGION or cur_scale == S.CONTINENT or cur_scale == S.WORLD then
                local ox = ((Game.world_gen_city_mn_x or 1) - 1) * ts
                local oy = ((Game.world_gen_city_mn_y or 1) - 1) * ts
                love.graphics.push()
                love.graphics.translate(ox, oy)
                DrawingUtils.drawWorldIcon(Game, "☎️", ec.x, ec.y)
                love.graphics.pop()
            end
        end

        love.graphics.pop()
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
        self:_drawWorldGenMode(active_map, S, cur_scale, ui_manager, sidebar_w, screen_w, screen_h)
    else
        self:_drawTileGridFallback(active_map, S, cur_scale, ui_manager, sidebar_w, screen_w, screen_h)
    end
    self:_drawFloatingTexts(sidebar_w, screen_w, screen_h)
    love.graphics.setScissor()
end

return GameView