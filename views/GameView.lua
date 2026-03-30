-- views/GameView.lua
-- Updated to render edge-based streets between grid cells
local Bike = require("models.vehicles.Bike")
local Truck = require("models.vehicles.Truck")

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

function GameView:draw()
    local Game = self.Game
    local ui_manager = Game.ui_manager
    local sidebar_w = Game.C.UI.SIDEBAR_WIDTH
    local screen_w, screen_h = love.graphics.getDimensions()
    local DrawingUtils = require("utils.DrawingUtils")

    local active_map = Game.maps[Game.active_map_key]
    if not active_map then return end

    love.graphics.setScissor(sidebar_w, 0, screen_w - sidebar_w, screen_h)

    local S = Game.C.MAP.SCALES
    local cur_scale = Game.state.current_map_scale

    if Game.lab_grid or Game.wfc_final_grid then
        love.graphics.push()
        self:drawLabGrid()
        love.graphics.pop()

    elseif Game.world_gen_cam_params then
        -- ── World-gen camera-based rendering (mirrors WorldSandboxView exactly) ──
        local ts  = Game.C.MAP.TILE_SIZE
        local vw  = screen_w - sidebar_w

        love.graphics.setColor(0.04, 0.04, 0.07)
        love.graphics.rectangle("fill", sidebar_w, 0, vw, screen_h)

        love.graphics.push()
        love.graphics.translate(sidebar_w + vw / 2, screen_h / 2)
        love.graphics.scale(Game.camera.scale, Game.camera.scale)
        love.graphics.translate(-Game.camera.x, -Game.camera.y)
        love.graphics.setColor(1, 1, 1)

        local city_bg = Game.world_gen_city_image
        if (cur_scale == S.DOWNTOWN or cur_scale == S.CITY) and city_bg then
            local bg = (cur_scale == S.DOWNTOWN and (Game.world_gen_downtown_fogged_image or city_bg)) or city_bg
            local K  = Game.world_gen_city_img_K or 9
            local ox = (Game.world_gen_city_img_min_x - 1) * ts
            local oy = (Game.world_gen_city_img_min_y - 1) * ts
            love.graphics.draw(bg, ox, oy, 0, ts / K, ts / K)
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
                                    if tt == "arterial" or tt == "highway" or
                                       tt == "highway_ring" or tt == "highway_ns" or
                                       tt == "highway_ew" then
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
                                    px, py = node.x * tps_pv, node.y * tps_pv
                                else
                                    px, py = active_map:getPixelCoords(node.x, node.y)
                                end
                                table.insert(pixel_path, px); table.insert(pixel_path, py)
                            end
                            local hc = Game.C.MAP.COLORS.HOVER
                            love.graphics.setColor(hc[1], hc[2], hc[3], 0.7)
                            love.graphics.setLineWidth(3 / Game.camera.scale)
                            love.graphics.line(pixel_path)
                            love.graphics.setLineWidth(1)
                        end
                    end
                end
            end
        end

        love.graphics.pop()

    else
        -- ── Tile-grid fallback (no world gen loaded yet) ──
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
                local x2 = (dt.x + Game.C.MAP.DOWNTOWN_GRID_WIDTH  - 1) * TS
                local y2 = (dt.y + Game.C.MAP.DOWNTOWN_GRID_HEIGHT - 1) * TS
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
            Game.event_spawner:draw(Game)
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
                                px, py = node.x * tps_pv2, node.y * tps_pv2
                            else
                                px, py = active_map:getPixelCoords(node.x, node.y)
                            end
                            table.insert(pixel_path, px); table.insert(pixel_path, py)
                        end
                        local hc = Game.C.MAP.COLORS.HOVER
                        love.graphics.setColor(hc[1], hc[2], hc[3], 0.7)
                        love.graphics.setLineWidth(3 / Game.camera.scale)
                        love.graphics.line(pixel_path)
                        love.graphics.setLineWidth(1)
                        local cr = 5 / Game.camera.scale
                        love.graphics.setColor(hc)
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

    -- Floating payout texts (screen space)
    if #Game.state.floating_texts > 0 then
        local game_world_w = screen_w - sidebar_w
        local cx, cy = Game.camera.x, Game.camera.y
        local cs = Game.camera.scale
        -- World-gen camera is in world-pixel coords; tile-pixel positions need city offset
        local ft_ox, ft_oy = 0, 0
        if Game.world_gen_cam_params then
            local ts = Game.C.MAP.TILE_SIZE
            ft_ox = ((Game.world_gen_city_mn_x or 1) - 1) * ts
            ft_oy = ((Game.world_gen_city_mn_y or 1) - 1) * ts
        end
        love.graphics.setFont(Game.fonts.ui)
        for _, ft in ipairs(Game.state.floating_texts) do
            local sx = sidebar_w + game_world_w / 2 + (ft.x + ft_ox - cx) * cs
            local sy = screen_h / 2 + (ft.y + ft_oy - cy) * cs
            love.graphics.setColor(1, 1, 0.3, ft.alpha)
            love.graphics.printf(ft.text, sx - 60, sy, 120, "center")
        end
    end

    love.graphics.setScissor()
end

function GameView:drawLabGrid()
    local Game = self.Game
    
    if Game.wfc_final_grid and Game.wfc_road_data then
        self:drawFinalWfcCity()
        return
    end

    if not Game.lab_grid then return end
    local grid = Game.lab_grid
    if not grid or #grid == 0 or not grid[1] then return end

    local grid_h, grid_w = #grid, #grid[1]
    local screen_w, screen_h = love.graphics.getDimensions()
    local sidebar_w = Game.C.UI.SIDEBAR_WIDTH
    local available_w, available_h = screen_w - sidebar_w, screen_h

    if not Game.lab_view then
        Game.lab_view = { zoom = 1, pan_x = 0, pan_y = 0 }
    end

    local tile_size_w = math.floor(available_w * 0.9 / grid_w)
    local tile_size_h = math.floor(available_h * 0.9 / grid_h)
    local base_tile_size = math.max(4, math.min(tile_size_w, tile_size_h, 25))
    local tile_size = math.max(1, math.floor(base_tile_size * Game.lab_view.zoom))

    local total_grid_w, total_grid_h = grid_w * tile_size, grid_h * tile_size
    local offset_x = sidebar_w + (available_w - total_grid_w) / 2 + Game.lab_view.pan_x
    local offset_y = (available_h - total_grid_h) / 2 + Game.lab_view.pan_y
    
    love.graphics.setColor(0.1, 0.1, 0.1, 0.8)
    love.graphics.rectangle("fill", offset_x - 10, offset_y - 40, total_grid_w + 20, total_grid_h + 50)
    
    if Game.show_flood_fill_regions and Game.debug_flood_fill_regions then
        self:drawFloodFillRegions(offset_x, offset_y, tile_size)
    elseif Game.lab_zone_grid then
        self:drawZoneBackground(offset_x, offset_y, tile_size)
    end
    
    for y = 1, grid_h do
        for x = 1, grid_w do
            if grid[y] and grid[y][x] and grid[y][x].type then
                local tile_type = grid[y][x].type
                
                if tile_type == "arterial" then
                    local color = self:getTileColor(tile_type)
                    love.graphics.setColor(color)
                    love.graphics.rectangle("fill", offset_x + (x-1)*tile_size, offset_y + (y-1)*tile_size, tile_size, tile_size)
                end
                
                if tile_type == "plot" then
                    love.graphics.setColor(0.5, 0.5, 0.5, 0.2)
                    love.graphics.rectangle("line", offset_x + (x-1)*tile_size, offset_y + (y-1)*tile_size, tile_size, tile_size)
                end
            end
        end
    end
    
    if Game.street_segments then
        love.graphics.setColor(0.3, 0.3, 0.3, 1.0)
        love.graphics.setLineWidth(math.max(2, tile_size * 0.15))
        
        for _, segment in ipairs(Game.street_segments) do
            if segment.type == "horizontal" then
                local x1 = offset_x + (segment.x1 - 1) * tile_size
                local x2 = offset_x + segment.x2 * tile_size
                local y_pos = offset_y + (segment.y - 0.5) * tile_size
                love.graphics.line(x1, y_pos, x2, y_pos)
            elseif segment.type == "vertical" then
                local y1 = offset_y + (segment.y1 - 1) * tile_size
                local y2 = offset_y + segment.y2 * tile_size
                local x_pos = offset_x + (segment.x - 0.5) * tile_size
                love.graphics.line(x_pos, y1, x_pos, y2)
            end
        end
        love.graphics.setLineWidth(1)
    end
    
    if Game.smooth_highway_overlay_paths and #Game.smooth_highway_overlay_paths > 0 then
        love.graphics.setLineWidth(math.max(2, tile_size / 4))
        love.graphics.setColor(1, 0.5, 0.7, 0.8)
        for _, spline_path in ipairs(Game.smooth_highway_overlay_paths) do
            local pixel_path = {}
            if #spline_path > 1 then
                for _, node in ipairs(spline_path) do
                    table.insert(pixel_path, offset_x + (node.x - 1) * tile_size + (tile_size / 2))
                    table.insert(pixel_path, offset_y + (node.y - 1) * tile_size + (tile_size / 2))
                end
                love.graphics.line(pixel_path)
            end
        end
        love.graphics.setLineWidth(1)
    end

    if Game.arterial_control_paths and #Game.arterial_control_paths > 0 then
        love.graphics.setLineWidth(math.max(3, math.floor(tile_size / 1)))
        love.graphics.setColor(0.1, 0.1, 0.1, 0.8)
        
        for _, path in ipairs(Game.arterial_control_paths) do
            if #path > 1 then
                for i = 1, #path - 1 do
                    local node1 = path[i]
                    local node2 = path[i+1]
                    local p1x = offset_x + (node1.x - 0.5) * tile_size
                    local p1y = offset_y + (node1.y - 0.5) * tile_size
                    local p2x = offset_x + (node2.x - 0.5) * tile_size
                    local p2y = offset_y + (node2.y - 0.5) * tile_size
                    love.graphics.line(p1x, p1y, p2x, p2y)
                end
            end
        end
        love.graphics.setLineWidth(1)
    end

    love.graphics.setColor(1, 1, 1)
    love.graphics.setFont(Game.fonts.ui)

    local title = "Edge-Based Streets - Scroll to zoom, right-drag to pan, 'H' for help"
    if Game.show_flood_fill_regions then
        title = "FLOOD FILL REGIONS DEBUG - Press '6' to toggle"
    end
    love.graphics.print(title, offset_x, offset_y - 35)
    
    self:drawLegend(offset_x + total_grid_w + 20, offset_y)
end

function GameView:drawFinalWfcCity()
    local Game = self.Game
    local grid = Game.wfc_final_grid
    local roads = Game.wfc_road_data
    if not grid or not roads then return end

    local grid_h, grid_w = #grid, #grid[1]
    local screen_w, screen_h = love.graphics.getDimensions()
    local sidebar_w = Game.C.UI.SIDEBAR_WIDTH
    local available_w, available_h = screen_w - sidebar_w, screen_h

    local tile_size_w = math.floor(available_w * 0.9 / grid_w)
    local tile_size_h = math.floor(available_h * 0.9 / grid_h)
    local tile_size = math.max(2, math.min(tile_size_w, tile_size_h, 25))
    
    local total_grid_w, total_grid_h = grid_w * tile_size, grid_h * tile_size
    local offset_x = sidebar_w + (available_w - total_grid_w) / 2
    local offset_y = (available_h - total_grid_h) / 2
    
    -- Step 1: Draw Zone Colors as background
    if Game.lab_zone_grid then
        self:drawZoneBackground(offset_x, offset_y, tile_size)
    end
    
    -- Step 2: Draw Arterials first (as thick lines)
    if Game.arterial_control_paths and #Game.arterial_control_paths > 0 then
        love.graphics.setLineWidth(math.max(3, tile_size * 0.8))
        love.graphics.setColor(0.2, 0.2, 0.2, 1.0)
        
        for _, path in ipairs(Game.arterial_control_paths) do
            if #path > 1 then
                for i = 1, #path - 1 do
                    local node1 = path[i]
                    local node2 = path[i+1]
                    local p1x = offset_x + (node1.x - 0.5) * tile_size
                    local p1y = offset_y + (node1.y - 0.5) * tile_size
                    local p2x = offset_x + (node2.x - 0.5) * tile_size
                    local p2y = offset_y + (node2.y - 0.5) * tile_size
                    love.graphics.line(p1x, p1y, p2x, p2y)
                end
            end
        end
    end

    -- Step 3: Draw Local Streets
    love.graphics.setColor(0.3, 0.3, 0.3, 1.0)
    love.graphics.setLineWidth(math.max(1, tile_size * 0.5))
    
    for _, road in ipairs(roads) do
        if road.type == "horizontal" then
            local x1 = offset_x + (road.x1 - 1) * tile_size
            local x2 = offset_x + road.x2 * tile_size
            local y_pos = offset_y + (road.y - 0.5) * tile_size
            love.graphics.line(x1, y_pos, x2, y_pos)
        elseif road.type == "vertical" then
            local y1 = offset_y + (road.y1 - 1) * tile_size
            local y2 = offset_y + road.y2 * tile_size
            local x_pos = offset_x + (road.x - 0.5) * tile_size
            love.graphics.line(x_pos, y1, x_pos, y2)
        end
    end

    love.graphics.setLineWidth(1)
end

function GameView:drawZoneBackground(offset_x, offset_y, tile_size)
    local Game = self.Game
    
    if not Game.lab_zone_grid then return end
    
    local zone_grid = Game.lab_zone_grid
    local grid_h, grid_w = #zone_grid, #zone_grid[1]
    
    -- Draw zone colors as background
    for y = 1, grid_h do
        for x = 1, grid_w do
            if zone_grid[y] and zone_grid[y][x] then
                local zone = zone_grid[y][x]
                local zone_color = self:getZoneColor(zone)
                
                -- Draw zones prominently as background
                love.graphics.setColor(zone_color[1], zone_color[2], zone_color[3], 0.7)
                love.graphics.rectangle("fill", 
                    offset_x + (x-1) * tile_size, 
                    offset_y + (y-1) * tile_size, 
                    tile_size, 
                    tile_size)
            end
        end
    end
end

function GameView:drawFloodFillRegions(offset_x, offset_y, tile_size)
    local Game = self.Game
    
    if not Game.debug_flood_fill_regions then return end
    
    local region_colors = {
        {1.0, 0.2, 0.2, 0.6}, {0.2, 1.0, 0.2, 0.6}, {0.2, 0.2, 1.0, 0.6}, 
        {1.0, 1.0, 0.2, 0.6}, {1.0, 0.2, 1.0, 0.6}, {0.2, 1.0, 1.0, 0.6},
        {1.0, 0.5, 0.2, 0.6}, {0.5, 0.2, 1.0, 0.6}, {0.2, 0.5, 0.2, 0.6},
        {0.5, 0.5, 0.2, 0.6}, {0.2, 0.5, 0.5, 0.6}, {0.5, 0.2, 0.5, 0.6}
    }
    
    for region_idx, region in ipairs(Game.debug_flood_fill_regions) do
        local color = region_colors[((region_idx - 1) % #region_colors) + 1]
        love.graphics.setColor(color[1], color[2], color[3], color[4])
        
        for _, cell in ipairs(region.cells) do
            love.graphics.rectangle("fill", 
                offset_x + (cell.x - 1) * tile_size, 
                offset_y + (cell.y - 1) * tile_size, 
                tile_size, 
                tile_size)
        end
        
        love.graphics.setColor(color[1], color[2], color[3], 1.0)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line",
            offset_x + (region.min_x - 1) * tile_size,
            offset_y + (region.min_y - 1) * tile_size,
            (region.max_x - region.min_x + 1) * tile_size,
            (region.max_y - region.min_y + 1) * tile_size)
        
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setFont(Game.fonts.ui_small)
        local center_x = offset_x + ((region.min_x + region.max_x) / 2 - 1) * tile_size
        local center_y = offset_y + ((region.min_y + region.max_y) / 2 - 1) * tile_size
        love.graphics.print(tostring(region.id), center_x, center_y)
    end
    
    love.graphics.setLineWidth(1)
end

function GameView:drawLegend(legend_x, legend_y)
    local Game = self.Game
    
    love.graphics.setColor(1, 1, 1)
    love.graphics.setFont(Game.fonts.ui_small)
    love.graphics.print("Legend:", legend_x, legend_y)
    
    local legend_items = {
        {type = "arterial", name = "Arterial (on grid)", color = {0.1, 0.1, 0.1}},
        {type = "street", name = "Street (between grid)", color = {0.8, 0.8, 0.8}}, -- Changed color to match
        {type = "intersection", name = "Intersection", color = {0.8, 0.8, 0.8}}, -- Changed color to match
        {type = "plot", name = "Building Plot", color = {0.5, 0.5, 0.5}},
        {type = "zone", name = "Zone Color", color = {0.7, 0.7, 0.7}}
    }
    
    for i, item in ipairs(legend_items) do
        local y_pos = legend_y + 20 + (i-1) * 20
        
        love.graphics.setColor(item.color[1], item.color[2], item.color[3])
        if item.type == "street" then
            love.graphics.rectangle("fill", legend_x, y_pos + 4, 15, 8) -- Show as a filled rectangle
        elseif item.type == "intersection" then
            love.graphics.rectangle("fill", legend_x + 4, y_pos + 4, 8, 8) -- Show as a filled square
        else
            love.graphics.rectangle("fill", legend_x, y_pos, 15, 15)
        end
        
        love.graphics.setColor(1, 1, 1)
        love.graphics.print(item.name, legend_x + 20, y_pos)
    end
    
    love.graphics.print("Streets are BETWEEN grid cells", legend_x, legend_y + 120)
    love.graphics.print("Arteries are ON grid cells", legend_x, legend_y + 140)
    love.graphics.print("Zones: " .. (Game.show_districts and "VISIBLE" or "HIDDEN"), legend_x, legend_y + 160)
    
    if Game.street_intersections then
        love.graphics.print("Intersections: " .. #Game.street_intersections, legend_x, legend_y + 180)
    end
    if Game.street_segments then
        love.graphics.print("Street edges: " .. #Game.street_segments, legend_x, legend_y + 200)
    end
end

function GameView:getTileColor(tile_type)
    if tile_type == "arterial" then
        return {0.1, 0.1, 0.1}
    elseif tile_type == "road" then
        return {0.3, 0.3, 0.3}
    elseif tile_type == "plot" then
        return {0.8, 0.8, 0.9}
    elseif tile_type == "grass" then
        return {0.2, 0.8, 0.2}
    else
        return {0.5, 0.5, 0.5}
    end
end

function GameView:getZoneColor(zone_type)
    if zone_type == "downtown" then
        return {1, 1, 0}
    elseif zone_type == "commercial" then
        return {0, 0, 1}
    elseif zone_type == "residential_north" then
        return {0, 1, 0}
    elseif zone_type == "residential_south" then
        return {0, 0.7, 0}
    elseif zone_type == "industrial_heavy" then
        return {1, 0, 0}
    elseif zone_type == "industrial_light" then
        return {0.8, 0.2, 0.2}
    elseif zone_type == "university" then
        return {0.6, 0, 0.8}
    elseif zone_type == "medical" then
        return {1, 0.5, 0.8}
    elseif zone_type == "entertainment" then
        return {1, 0.5, 0}
    elseif zone_type == "waterfront" then
        return {0, 0.8, 0.8}
    elseif zone_type == "warehouse" then
        return {0.5, 0.3, 0.1}
    elseif zone_type == "tech" then
        return {0.3, 0.3, 0.8}
    elseif zone_type == "park_central" then
        return {0.2, 0.8, 0.3}
    elseif zone_type == "park_nature" then
        return {0.1, 0.6, 0.1}
    else
        return {0.5, 0.5, 0.5}
    end
end

return GameView