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

    -- LAYER: World image (always)
    if Game.world_gen_world_image then
        love.graphics.draw(Game.world_gen_world_image, 0, 0, 0, ts, ts)
    end

    -- LAYER: City circles on world map (inside camera transform — use world coords directly)
    if cs < Z.ZONE_THRESHOLD and Game.world_city_locations then
        local cities  = Game.world_city_locations
        local min_s, max_s = math.huge, -math.huge
        for _, city in ipairs(cities) do
            if city.s < min_s then min_s = city.s end
            if city.s > max_s then max_s = city.s end
        end
        local s_range = math.max(max_s - min_s, 0.001)
        -- Scale radius inversely with camera scale so circles stay constant on screen
        local r_scale = 1 / cs
        for _, city in ipairs(cities) do
            local t   = (city.s - min_s) / s_range
            local rad = (3.5 + t * 8.5) * r_scale
            local wpx = (city.x - 0.5) * ts
            local wpy = (city.y - 0.5) * ts
            love.graphics.setColor(0, 0, 0, 0.6)
            love.graphics.circle("fill", wpx + r_scale, wpy + r_scale, rad + 1.5 * r_scale)
            love.graphics.setColor(0.10, 0.08, 0.04)
            love.graphics.circle("fill", wpx, wpy, rad + 1.5 * r_scale)
            love.graphics.setColor(1.0, 0.85, 0.15)
            love.graphics.circle("fill", wpx, wpy, rad)
            love.graphics.setColor(0.15, 0.10, 0.02)
            love.graphics.circle("fill", wpx, wpy, math.max(1.5 * r_scale, rad * 0.35))
        end
        love.graphics.setColor(1, 1, 1)
    end

    -- LAYER: City / downtown background image
    if cs >= Z.CITY_IMAGE_THRESHOLD then
        local city_bg = Game.world_gen_city_image
        if city_bg and not Game.overlay_only_mode and not Game.debug_hide_roads then
            local bg = cs >= Z.DOWNTOWN_IMG_THRESHOLD
                       and (Game.world_gen_downtown_fogged_image or city_bg)
                       or city_bg
            local K  = Game.world_gen_city_img_K or 9
            love.graphics.draw(bg, (Game.world_gen_city_img_min_x - 1) * ts,
                                   (Game.world_gen_city_img_min_y - 1) * ts, 0, ts / K, ts / K)
        end
    end

    -- LAYER: Zone grid + bridges + rivers + streets (city-detail threshold)
    if cs >= Z.ZONE_THRESHOLD then

        -- Zone grid overlay
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

        -- Bridge rendering
        if active_map.bridge_cells then
            love.graphics.setLineStyle("rough")
            love.graphics.setColor(0.72, 0.60, 0.38, 0.95)
            love.graphics.setLineWidth(tps * 0.45)
            for gy, row in pairs(active_map.bridge_cells) do
                for gx, entry in pairs(row) do
                    local px = ox + (gx - 1) * tps
                    local py = oy + (gy - 1) * tps
                    if entry.ew then love.graphics.line(px, py + tps*0.5, px+tps, py + tps*0.5) end
                    if entry.ns then love.graphics.line(px + tps*0.5, py, px + tps*0.5, py+tps) end
                end
            end
            love.graphics.setLineWidth(1)
            love.graphics.setColor(1, 1, 1)
        end

        -- Smooth river overlay
        if not active_map._river_smooth_paths_v1 then
            local RS = require("utils.RoadSmoother")
            active_map._river_smooth_paths_v1 = RS.buildRiverPaths(active_map.grid, tps)
        end
        if active_map._river_smooth_paths_v1 and #active_map._river_smooth_paths_v1 > 0 then
            local cap_r = tps * 0.4
            love.graphics.setColor(0.20, 0.45, 0.75, 0.92)
            love.graphics.setLineWidth(tps * 0.75)
            love.graphics.setLineJoin("bevel")
            for _, pts in ipairs(active_map._river_smooth_paths_v1) do
                if #pts >= 4 then
                    local s2 = {}
                    for i = 1, #pts, 2 do s2[i] = ox + pts[i]; s2[i+1] = oy + pts[i+1] end
                    love.graphics.line(s2)
                    love.graphics.circle("fill", s2[1], s2[2], cap_r)
                    love.graphics.circle("fill", s2[#s2-1], s2[#s2], cap_r)
                end
            end
            love.graphics.setLineWidth(1)
            love.graphics.setLineJoin("miter")
            love.graphics.setColor(1, 1, 1)
        end

        -- Street overlays (debug only)
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
                        local s2 = {}
                        for i = 1, #pts, 2 do s2[i] = ox + pts[i]; s2[i+1] = oy + pts[i+1] end
                        love.graphics.line(s2)
                    end
                end
                love.graphics.setLineStyle("rough")
                love.graphics.setLineWidth(1)
                love.graphics.setLineJoin("miter")
                love.graphics.setColor(1, 1, 1)
            end
        end end

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
                    local s2 = {}
                    for i = 1, #pts, 2 do s2[i] = ox + pts[i]; s2[i+1] = oy + pts[i+1] end
                    love.graphics.line(s2)
                end
                love.graphics.setLineStyle("rough")
                love.graphics.setLineWidth(1)
                love.graphics.setLineJoin("miter")
                love.graphics.setColor(1, 1, 1)
            end
        end end

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
                    local s2 = {}
                    for i = 1, #pts, 2 do s2[i] = ox + pts[i]; s2[i+1] = oy + pts[i+1] end
                    love.graphics.line(s2)
                end
                love.graphics.setLineStyle("rough")
                love.graphics.setLineWidth(1)
                love.graphics.setLineJoin("miter")
                love.graphics.setColor(1, 1, 1)
            end
        end end

        -- [G] Road segment overlay
        if Game.debug_road_segments and active_map.zone_seg_v then
            local zsv   = active_map.zone_seg_v
            local zsh   = active_map.zone_seg_h
            local scale = Game.camera and Game.camera.scale or 1
            love.graphics.setLineWidth(4 / scale)
            love.graphics.setColor(0, 1, 0.2, 0.9)
            for gy, row in pairs(zsv) do
                for rx in pairs(row) do
                    love.graphics.line(ox + rx*tps, oy + (gy-1)*tps, ox + rx*tps, oy + gy*tps)
                end
            end
            love.graphics.setColor(0.2, 0.5, 1, 0.9)
            for ry, row in pairs(zsh) do
                for gx in pairs(row) do
                    love.graphics.line(ox + (gx-1)*tps, oy + ry*tps, ox + gx*tps, oy + ry*tps)
                end
            end
            love.graphics.setLineWidth(1)
            love.graphics.setColor(1, 1, 1)
        end
    end  -- ZONE_THRESHOLD

    -- LAYER: Arterial / highway smooth paths
    if cs >= Z.ARTERIAL_THRESHOLD and Game.debug_smooth_roads then do
        if not active_map._road_smooth_paths_v8 then
            local RS = require("utils.RoadSmoother")
            if active_map.road_centerlines and #active_map.road_centerlines > 0 then
                active_map._road_smooth_paths_v8 = RS.buildPathsFromCenterlines(active_map.road_centerlines, tps)
            else
                active_map._road_smooth_paths_v8 = RS.buildPaths(active_map.grid, tps)
            end
        end
        if #active_map._road_smooth_paths_v8 > 0 then
            local cap_r = tps * 0.35
            love.graphics.setColor(0.22, 0.21, 0.20, 1.0)
            love.graphics.setLineWidth(tps * 0.7)
            love.graphics.setLineJoin("bevel")
            for _, pts in ipairs(active_map._road_smooth_paths_v8) do
                if #pts >= 4 then
                    local s2 = {}
                    for i = 1, #pts, 2 do s2[i] = ox + pts[i]; s2[i+1] = oy + pts[i+1] end
                    love.graphics.line(s2)
                    love.graphics.circle("fill", s2[1], s2[2], cap_r)
                    love.graphics.circle("fill", s2[#s2-1], s2[#s2], cap_r)
                end
            end
            love.graphics.setLineWidth(1)
            love.graphics.setLineJoin("miter")
            love.graphics.setColor(1, 1, 1)
        end
    end end  -- ARTERIAL_THRESHOLD / debug_smooth_roads

    -- LAYER: Entities (inside city-local translated scope)
    love.graphics.push()
    love.graphics.translate(ox, oy)

    -- Depot + clients: only once city circles are gone
    if cs >= Z.ZONE_THRESHOLD then
        if Game.entities.depot_plot then
            local dp = Game.entities.depot_plot
            local dpx, dpy = active_map:getPixelCoords(dp.x, dp.y)
            DrawingUtils.drawWorldIcon(Game, "🏢", dpx, dpy)
        end
        for _, client in ipairs(Game.entities.clients) do
            DrawingUtils.drawWorldIcon(Game, "🏠", client.px, client.py)
        end
    end
    for _, v in ipairs(Game.entities.vehicles) do
        if v.visible and v:shouldDrawAtCameraScale(Game) then v:draw(Game) end
    end
    -- Event spawner: always
    if Game.event_spawner and Game.event_spawner.clickable then
        DrawingUtils.drawWorldIcon(Game, "☎️", Game.event_spawner.clickable.x, Game.event_spawner.clickable.y)
    end
    if Game.debug_mode then
        for _, vehicle in ipairs(Game.entities.vehicles) do
            if vehicle.visible then vehicle:drawDebug(Game) end
        end
    end

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

    -- [P] Client/pickup overlay
    if Game.debug_pickup_locations then
        local r = tps * 0.3
        for _, client in ipairs(Game.entities.clients) do
            love.graphics.setColor(1, 0.5, 0, 0.8)
            love.graphics.circle("fill", client.px, client.py, r)
            if active_map.road_nodes then
                local gx, gy = client.plot.x, client.plot.y
                for _, c in ipairs({{gx-1,gy-1},{gx,gy-1},{gx-1,gy},{gx,gy}}) do
                    local rx, ry = c[1], c[2]
                    if active_map.road_nodes[ry] and active_map.road_nodes[ry][rx] then
                        love.graphics.setColor(0, 1, 0, 0.9)
                        love.graphics.circle("fill", rx*tps, ry*tps, tps*0.2)
                    end
                end
            end
        end
        love.graphics.setColor(0, 1, 1, 0.8)
        local r2 = tps * 0.2
        for _, trip in ipairs(Game.entities.trips.pending) do
            local leg = trip.legs and trip.legs[trip.current_leg]
            if leg and leg.start_plot then
                local spx, spy = active_map:getPixelCoords(leg.start_plot.x, leg.start_plot.y)
                love.graphics.circle("fill", spx, spy, r2)
            end
        end
    end

    -- Trip route preview on hover
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
                    for _, node in ipairs(path) do
                        local px, py
                        if is_rn then
                            if node.is_tile then px, py = (node.x+0.5)*tps, (node.y+0.5)*tps
                            else               px, py = node.x*tps, node.y*tps end
                        else
                            px, py = active_map:getPixelCoords(node.x, node.y)
                        end
                        table.insert(pixel_path, px); table.insert(pixel_path, py)
                    end
                    love.graphics.setColor(0.2, 0.8, 1, 0.85)
                    love.graphics.setLineWidth(3 / cs)
                    love.graphics.line(pixel_path)
                    love.graphics.setLineWidth(1)
                end
            end
        end
    end

    love.graphics.pop()  -- city translate pop
    love.graphics.setColor(1, 1, 1)


    love.graphics.pop()  -- camera transform pop
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
    else
        self:_drawTileGridFallback(active_map, S, cur_scale, ui_manager, sidebar_w, screen_w, screen_h)
    end
    self:_drawFloatingTexts(sidebar_w, screen_w, screen_h)
    love.graphics.setScissor()
end

return GameView