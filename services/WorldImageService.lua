-- services/WorldImageService.lua
-- Love2D rendering: world image, hi-res world image, city image.
-- love.* is intentionally allowed here — this service is NOT portable.

local WorldGenUtils = require("utils.WorldGenUtils")

local WorldImageService = {}

-- Flat 1px-per-world-cell world image. active_colormap is already selected by view_mode.
-- Returns: love.Image
function WorldImageService.buildWorldImage(
    active_colormap, w, h,
    city_bounds, city_border, city_fringe, selected_city_bounds,
    continent_map, region_map,
    view_scope, selected_continent_id, selected_region_id, selected_downtown_bounds
)
    local imgdata = love.image.newImageData(w, h)
    for y = 1, h do
        for x = 1, w do
            local i = (y-1)*w + x
            local in_scope = true
            if view_scope == "continent" and selected_continent_id then
                in_scope = (continent_map and continent_map[i] == selected_continent_id)
            elseif view_scope == "region" and selected_region_id then
                in_scope = (region_map and region_map[i] == selected_region_id)
            elseif view_scope == "city" and selected_city_bounds then
                in_scope = (selected_city_bounds[i] == true)
            elseif view_scope == "downtown" then
                in_scope = (selected_downtown_bounds ~= nil and selected_downtown_bounds[i] == true)
            end

            local c = active_colormap[y][x]
            if not in_scope then
                imgdata:setPixel(x-1, y-1, c[1]*0.18+0.01, c[2]*0.18+0.02, c[3]*0.18+0.06, 1.0)
            elseif city_border and city_border[i] then
                imgdata:setPixel(x-1, y-1, 0.72, 0.42, 0.08, 1.0)
            elseif city_bounds and city_bounds[i] then
                imgdata:setPixel(x-1, y-1, c[1]*0.55+0.38, c[2]*0.55+0.30, c[3]*0.55+0.12, 1.0)
            elseif city_fringe and city_fringe[i] then
                imgdata:setPixel(x-1, y-1, c[1]*0.82+0.10, c[2]*0.82+0.07, c[3]*0.82+0.03, 1.0)
            else
                imgdata:setPixel(x-1, y-1, c[1], c[2], c[3], 1.0)
            end
        end
    end
    local img = love.graphics.newImage(imgdata)
    img:setFilter("nearest", "nearest")
    return img
end

-- Hi-res terrain render: bilinear elevation + analytic temp + bilinear moisture.
-- Lakes get a smooth water-mask overlay.
-- Returns: love.Image, scale_used
function WorldImageService.buildWorldImageHiRes(heightmap, moisture_map, lake_set, colormap, w, h, params, scale)
    local Biomes = require("data.biomes")
    local s      = math.max(1, math.min(8, math.floor(scale)))
    local iW, iH = w * s, h * s
    local imgdata = love.image.newImageData(iW, iH)
    local p       = params
    local hmap    = heightmap
    local mmap    = moisture_map
    local lset    = lake_set or {}
    local cmap    = colormap
    local cv      = p.vq_color_variation or 0
    local sx      = p.seed_x or 0
    local sy_off  = p.seed_y or 0
    local lat_str = p.latitude_strength or 0.7

    local lake_mask  = {}
    local lake_color = {}
    local LAKE_C     = { 0.07, 0.20, 0.55 }
    for y = 1, h do
        lake_mask[y]  = {}
        lake_color[y] = {}
        for x = 1, w do
            local i = (y-1)*w + x
            if lset[i] then
                lake_mask[y][x]  = 1.0
                lake_color[y][x] = (cmap and cmap[y][x]) or LAKE_C
            else
                lake_mask[y][x]  = 0.0
                lake_color[y][x] = nil
            end
        end
    end

    for py = 0, iH - 1 do
        for px = 0, iW - 1 do
            local fx = (px + 0.5) / s
            local fy = (py + 0.5) / s

            local elev = WorldGenUtils.bilinear2d(hmap, fy, fx, w, h)

            local lat_factor = (fy - 1.0) / math.max(1.0, h - 1.0)
            local temp_base  = lat_factor * lat_str + 0.5 * (1.0 - lat_str)
            local elev_t     = elev > p.coast_max
                               and (elev - p.coast_max) / (1.0 - p.coast_max) or 0.0
            local temp       = math.max(0.0, math.min(1.0, temp_base - elev_t * 0.4))

            local moist = WorldGenUtils.bilinear2d(mmap, fy, fx, w, h)
            local wet   = moist * 0.3 + 0.35

            local lc      = Biomes.getColor(elev, temp, wet, p)
            local r, g, b = lc[1], lc[2], lc[3]

            if cv > 0 then
                local noise  = love.math.noise(fx * 0.12 + sx * 0.001,
                                               fy * 0.12 + sy_off * 0.001)
                local factor = 1.0 + (noise - 0.5) * cv
                r = math.max(0, math.min(1, r * factor))
                g = math.max(0, math.min(1, g * factor))
                b = math.max(0, math.min(1, b * factor))
            end

            local lf = WorldGenUtils.bilinear2d(lake_mask, fy, fx, w, h)
            if lf > 0.001 then
                local nx = math.max(1, math.min(w, math.floor(fx + 0.5)))
                local ny = math.max(1, math.min(h, math.floor(fy + 0.5)))
                local wc = lake_color[ny][nx]
                if not wc then
                    local x0 = math.max(1,math.floor(fx)); local x1=math.min(w,x0+1)
                    local y0 = math.max(1,math.floor(fy)); local y1=math.min(h,y0+1)
                    wc = lake_color[y0][x0] or lake_color[y0][x1]
                      or lake_color[y1][x0] or lake_color[y1][x1] or LAKE_C
                end
                local alpha = math.min(1.0, lf * 2.0)
                r = r*(1-alpha) + wc[1]*alpha
                g = g*(1-alpha) + wc[2]*alpha
                b = b*(1-alpha) + wc[3]*alpha
            end

            imgdata:setPixel(px, py, r, g, b, 1.0)
        end
    end

    local img = love.graphics.newImage(imgdata)
    img:setFilter("nearest", "nearest")
    return img, s
end

-- High-resolution city image: K_SC content pixels + 1px gap per sub-cell.
-- Returns: love.Image, img_min_x, img_min_y, img_K  (img_K = 3 * STRIDE)
function WorldImageService.buildCityImage(
    city_idx, min_x, max_x, min_y, max_y,
    bounds, view_mode, view_scope,
    dist_colors, dist_owner_map, pois_for_city,
    w, art_city_map, street_city_map,
    terrain_cmap, active_colormap, heightmap,
    zone_grid, zone_offsets
)
    if not bounds then return nil end

    local ZT         = require("data.zones")
    local ZT_COLORS  = ZT.COLORS
    local ZONE_ALPHA = ZT.COLOR_ALPHA

    local use_districts = (view_mode == "districts")

    if use_districts and not terrain_cmap then return nil end
    if not use_districts and not active_colormap then return nil end

    local sub_w   = w * 3
    local bbox_w  = max_x - min_x + 1
    local bbox_h  = max_y - min_y + 1

    local K_SC    = 8
    local STRIDE  = K_SC + 1
    local sc_min_x  = (min_x - 1) * 3
    local sc_min_y  = (min_y - 1) * 3
    local sc_bbox_w = bbox_w * 3
    local sc_bbox_h = bbox_h * 3
    local img_w = sc_bbox_w * STRIDE
    local img_h = sc_bbox_h * STRIDE

    local imgdata = love.image.newImageData(img_w, img_h)

    local pois_list = pois_for_city or {}

    for py = 0, img_h - 1 do
        local scy  = math.floor(py / STRIDE)
        local iy   = py % STRIDE
        local gscy = sc_min_y + scy
        local wy   = math.floor(gscy / 3) + 1
        for px = 0, img_w - 1 do
            local scx  = math.floor(px / STRIDE)
            local ix   = px % STRIDE
            local gscx = sc_min_x + scx
            local wx   = math.floor(gscx / 3) + 1
            local ci   = (wy - 1) * w + wx

            local is_gap = (ix == 0) or (iy == 0)

            local c
            if use_districts then
                local best_poi = dist_owner_map and dist_owner_map[gscy * sub_w + gscx + 1]
                if not best_poi and #pois_list > 0 then
                    local best_wd = math.huge
                    for poi_idx, poi in ipairs(pois_list) do
                        local px2 = (poi.x - 1) * 3 + 1
                        local py2 = (poi.y - 1) * 3 + 1
                        local dx  = gscx - px2
                        local dy  = gscy - py2
                        local wd  = dx*dx + dy*dy
                        if wd < best_wd then best_wd = wd; best_poi = poi_idx end
                    end
                end
                c = (best_poi and dist_colors and dist_colors[best_poi]) or {0.25, 0.25, 0.28}
            else
                local bc      = active_colormap[wy] and active_colormap[wy][wx] or {0.1, 0.1, 0.1}
                local world_e = heightmap[wy][wx]
                local sub_e   = WorldGenUtils.subcell_elev_at(gscx, gscy, heightmap, love.math.noise)
                local adjust  = (sub_e - world_e) * 3.0
                c = {
                    math.max(0, math.min(1, bc[1] + adjust)),
                    math.max(0, math.min(1, bc[2] + adjust)),
                    math.max(0, math.min(1, bc[3] + adjust)),
                }
            end

            if bounds[ci] then
                local is_street = false
                local zg_ox = zone_offsets and zone_offsets.x or sc_min_x
                local zg_oy = zone_offsets and zone_offsets.y or sc_min_y
                if zone_grid and is_gap then
                    local lscx = gscx - zg_ox + 1
                    local lscy = gscy - zg_oy + 1
                    if ix == 0 and lscx > 1 then
                        local z1 = zone_grid[lscy] and zone_grid[lscy][lscx-1]
                        local z2 = zone_grid[lscy] and zone_grid[lscy][lscx]
                        if z1 and z1 ~= "none" and z2 and z2 ~= "none" and z1 ~= z2 then
                            is_street = true
                        end
                    end
                    if not is_street and iy == 0 and lscy > 1 then
                        local z1 = zone_grid[lscy-1] and zone_grid[lscy-1][lscx]
                        local z2 = zone_grid[lscy] and zone_grid[lscy][lscx]
                        if z1 and z1 ~= "none" and z2 and z2 ~= "none" and z1 ~= z2 then
                            is_street = true
                        end
                    end
                elseif street_city_map and is_gap then
                    local sv2, sh2 = street_city_map.v, street_city_map.h
                    if ix == 0 and gscx > sc_min_x and gscx % 3 == 0 then
                        if sv2 and sv2[(math.floor(gscx / 3)) * 1000 + wy] then is_street = true end
                    end
                    if not is_street and iy == 0 and gscy > sc_min_y and gscy % 3 == 0 then
                        if sh2 and sh2[(math.floor(gscy / 3)) * 1000 + wx] then is_street = true end
                    end
                end

                if not is_street and art_city_map and is_gap then
                    if ix == 0 and gscx > sc_min_x then
                        local curr = art_city_map[gscy * sub_w + gscx + 1]
                        local left = art_city_map[gscy * sub_w + (gscx - 1) + 1]
                        if (curr and not left) or (left and not curr) then is_street = true end
                    end
                    if not is_street and iy == 0 and gscy > sc_min_y then
                        local curr  = art_city_map[gscy * sub_w + gscx + 1]
                        local above = art_city_map[(gscy - 1) * sub_w + gscx + 1]
                        if (curr and not above) or (above and not curr) then is_street = true end
                    end
                end

                if zone_grid then
                    local lscx_z = gscx - zg_ox + 1
                    local lscy_z = gscy - zg_oy + 1
                    local ztype  = zone_grid[lscy_z] and zone_grid[lscy_z][lscx_z]
                    if (not ztype or ztype == "none") and art_city_map and art_city_map[gscy * sub_w + gscx + 1] then
                        for _, d in ipairs({{0,-1},{0,1},{-1,0},{1,0}}) do
                            local nz = zone_grid[lscy_z + d[2]] and zone_grid[lscy_z + d[2]][lscx_z + d[1]]
                            if nz and nz ~= "none" then ztype = nz; break end
                        end
                    end
                    if ztype then
                        local zcol = ZT_COLORS[ztype]
                        if zcol then
                            c = {
                                c[1]*(1-ZONE_ALPHA) + zcol[1]*ZONE_ALPHA,
                                c[2]*(1-ZONE_ALPHA) + zcol[2]*ZONE_ALPHA,
                                c[3]*(1-ZONE_ALPHA) + zcol[3]*ZONE_ALPHA,
                            }
                        end
                    end
                end

                local r, g, b = c[1], c[2], c[3]
                imgdata:setPixel(px, py, r, g, b, 1.0)
            else
                imgdata:setPixel(px, py, 0, 0, 0, 0)
            end
        end
    end

    local img = love.graphics.newImage(imgdata)
    img:setFilter("nearest", "nearest")
    return img, min_x, min_y, 3 * STRIDE
end

return WorldImageService
