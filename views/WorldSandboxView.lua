-- views/WorldSandboxView.lua
-- Renders the world sandbox viewport (image + status bar).

local WorldSandboxView = {}
WorldSandboxView.__index = WorldSandboxView

-- Biome legend entries: { label, r, g, b }
local BIOME_LEGEND = {
    { "Deep Ocean",        0.04, 0.08, 0.30 },
    { "Ocean",             0.07, 0.15, 0.45 },
    { "Beach",             0.76, 0.70, 0.48 },
    { "Tundra",            0.60, 0.64, 0.52 },
    { "Boreal / Taiga",    0.22, 0.38, 0.24 },
    { "Temp. Forest",      0.24, 0.46, 0.18 },
    { "Temp. Rainforest",  0.18, 0.40, 0.16 },
    { "Grassland",         0.42, 0.58, 0.22 },
    { "Shrubland",         0.52, 0.46, 0.24 },
    { "Subtropical Forest",0.16, 0.44, 0.12 },
    { "Woodland",          0.34, 0.54, 0.20 },
    { "Savanna",           0.65, 0.60, 0.24 },
    { "Semi-arid",         0.76, 0.64, 0.32 },
    { "Jungle",            0.08, 0.30, 0.06 },
    { "Trop. Forest",      0.20, 0.48, 0.12 },
    { "Trop. Savanna",     0.68, 0.62, 0.22 },
    { "Desert",            0.80, 0.66, 0.28 },
    { "Swamp",             0.22, 0.30, 0.16 },
    { "Trop. Swamp",       0.18, 0.26, 0.12 },
    { "Highland",          0.40, 0.44, 0.26 },
    { "Frozen Rock",       0.65, 0.66, 0.70 },
    { "Mountain Rock",     0.52, 0.48, 0.42 },
    { "Snow Cap",          0.88, 0.90, 0.95 },
    { "River",             0.22, 0.52, 0.88 },
    { "Lake",              0.07, 0.20, 0.55 },
}

function WorldSandboxView:new(game)
    local inst = setmetatable({}, WorldSandboxView)
    inst.game = game
    return inst
end

function WorldSandboxView:draw()
    local wsc = self.game.world_sandbox_controller
    if not wsc or not wsc:isActive() then return end

    local C         = self.game.C
    local sw, sh    = love.graphics.getDimensions()
    local sidebar_w = C.UI.SIDEBAR_WIDTH
    local vw        = sw - sidebar_w

    -- Viewport background
    love.graphics.setScissor(sidebar_w, 0, vw, sh)
    love.graphics.setColor(0.04, 0.04, 0.07)
    love.graphics.rectangle("fill", sidebar_w, 0, vw, sh)

    if wsc.world_image then
        local ts = C.MAP.TILE_SIZE
        love.graphics.push()
        love.graphics.translate(sidebar_w + vw / 2, sh / 2)
        love.graphics.scale(wsc.camera.scale, wsc.camera.scale)
        love.graphics.translate(-wsc.camera.x, -wsc.camera.y)
        love.graphics.setColor(1, 1, 1)
        if wsc.view_scope == "city" and wsc.city_image then
            -- High-res city image: K city pixels per world cell, offset by bbox origin
            local K     = wsc.city_img_K
            local ox    = (wsc.city_img_min_x - 1) * ts
            local oy    = (wsc.city_img_min_y - 1) * ts
            love.graphics.draw(wsc.city_image, ox, oy, 0, ts / K, ts / K)
        else
            love.graphics.draw(wsc.world_image, 0, 0, 0, ts, ts)
        end
        love.graphics.pop()
    else
        love.graphics.setColor(0.4, 0.4, 0.5)
        love.graphics.setFont(self.game.fonts.ui)
        love.graphics.printf("Press Generate →", sidebar_w, sh / 2 - 10, vw, "center")
    end

    -- Scope picking: tint the viewport to signal interactive mode
    if wsc.scope_mode and wsc.world_image then
        love.graphics.setScissor(sidebar_w, 0, vw, sh)
        love.graphics.setColor(0.6, 0.85, 1.0, 0.06)
        love.graphics.rectangle("fill", sidebar_w, 0, vw, sh)
        -- Crosshair at mouse position
        local mx, my = love.mouse.getPosition()
        if mx > sidebar_w then
            love.graphics.setColor(0.6, 0.85, 1.0, 0.35)
            love.graphics.setLineWidth(1)
            love.graphics.line(mx, 0, mx, sh)
            love.graphics.line(sidebar_w, my, sw, my)
        end
    end

    -- City markers (drawn in all view modes when cities are placed)
    if wsc.city_locations and wsc.world_image then
        local C  = self.game.C
        local ts = C.MAP.TILE_SIZE
        love.graphics.setScissor(sidebar_w, 0, vw, sh)

        -- Normalise suitability scores so radius spans the full range
        local min_s, max_s = math.huge, -math.huge
        for _, city in ipairs(wsc.city_locations) do
            if city.s < min_s then min_s = city.s end
            if city.s > max_s then max_s = city.s end
        end
        local s_range = math.max(max_s - min_s, 0.001)

        local scope    = wsc.view_scope
        local sel_cid  = wsc.selected_continent_id
        local sel_rid  = wsc.selected_region_id
        local cont_map = wsc.continent_map
        local reg_map  = wsc.region_map

        for _, city in ipairs(wsc.city_locations) do
            -- Skip cities outside the current scope
            if scope == "continent" and sel_cid and cont_map then
                local ci = (city.y-1)*wsc.world_w + city.x
                if cont_map[ci] ~= sel_cid then goto next_city end
            elseif scope == "region" and sel_rid and reg_map then
                local ci = (city.y-1)*wsc.world_w + city.x
                if reg_map[ci] ~= sel_rid then goto next_city end
            end

            do
            local t   = (city.s - min_s) / s_range   -- 0 = smallest, 1 = largest
            local rad = 3.5 + t * 8.5                 -- 3.5 px (hamlet) → 12 px (capital)
            -- Cell centre in world space
            local wpx = (city.x - 0.5) * ts
            local wpy = (city.y - 0.5) * ts
            -- Screen coords
            local sx = sidebar_w + vw / 2 + (wpx - wsc.camera.x) * wsc.camera.scale
            local sy = sh / 2 + (wpy - wsc.camera.y) * wsc.camera.scale
            if sx > sidebar_w and sx < sw and sy > 0 and sy < sh then
                love.graphics.setColor(0, 0, 0, 0.6)
                love.graphics.circle("fill", sx + 1, sy + 1, rad + 1.5)
                love.graphics.setColor(0.10, 0.08, 0.04)
                love.graphics.circle("fill", sx, sy, rad + 1.5)
                love.graphics.setColor(1.0, 0.85, 0.15)
                love.graphics.circle("fill", sx, sy, rad)
                love.graphics.setColor(0.15, 0.10, 0.02)
                love.graphics.circle("fill", sx, sy, math.max(1.5, rad * 0.35))
            end
            end  -- do
            ::next_city::
        end
    end

    -- POI markers (downtown + districts, visible in region scope, filtered to selected region)
    if wsc.city_pois and (wsc.view_scope == "region" or wsc.view_scope == "city") then
        local C   = self.game.C
        local ts  = C.MAP.TILE_SIZE
        local sel = wsc.selected_region_id
        love.graphics.setScissor(sidebar_w, 0, vw, sh)
        for _, poi in ipairs(wsc.city_pois) do
            if wsc.view_scope == "region" and poi.region_id ~= sel then goto next_poi end
            if wsc.view_scope == "city" then
                -- Only show POIs belonging to the selected city
                local cb = wsc.selected_city_bounds
                if not cb then goto next_poi end
                local pi = (poi.y-1)*wsc.world_w + poi.x
                if not cb[pi] then goto next_poi end
            end
            local wpx = (poi.x - 0.5) * ts
            local wpy = (poi.y - 0.5) * ts
            local sx = sidebar_w + vw / 2 + (wpx - wsc.camera.x) * wsc.camera.scale
            local sy = sh / 2 + (wpy - wsc.camera.y) * wsc.camera.scale
            if sx > sidebar_w and sx < sw and sy > 0 and sy < sh then
                if poi.type == "downtown" then
                    -- Downtown: large white circle with dark ring
                    love.graphics.setColor(0, 0, 0, 0.7)
                    love.graphics.circle("fill", sx+1, sy+1, 8)
                    love.graphics.setColor(0.15, 0.12, 0.08)
                    love.graphics.circle("fill", sx, sy, 8)
                    love.graphics.setColor(1.0, 1.0, 1.0)
                    love.graphics.circle("fill", sx, sy, 6)
                    love.graphics.setColor(0.15, 0.12, 0.08)
                    love.graphics.circle("fill", sx, sy, 2.5)
                else
                    -- District: smaller cyan circle
                    love.graphics.setColor(0, 0, 0, 0.6)
                    love.graphics.circle("fill", sx+1, sy+1, 5.5)
                    love.graphics.setColor(0.10, 0.20, 0.20)
                    love.graphics.circle("fill", sx, sy, 5.5)
                    love.graphics.setColor(0.35, 0.90, 0.85)
                    love.graphics.circle("fill", sx, sy, 4)
                    love.graphics.setColor(0.10, 0.20, 0.20)
                    love.graphics.circle("fill", sx, sy, 1.5)
                end
            end
            ::next_poi::
        end
    end

    -- Biome legend (biome view only)
    if wsc.world_image and wsc.view_mode == "biome" then
        local font      = self.game.fonts.ui_small
        local row_h     = 14
        local swatch_w  = 10
        local pad       = 6
        local col_w     = 130
        local cols      = 2
        local rows      = math.ceil(#BIOME_LEGEND / cols)
        local panel_w   = cols * col_w + pad * 2
        local panel_h   = rows * row_h + pad * 2 + 14  -- +14 for title
        local lx        = sw - panel_w - 4
        local ly        = sh - 22 - panel_h - 4
        love.graphics.setScissor()
        love.graphics.setColor(0, 0, 0, 0.72)
        love.graphics.rectangle("fill", lx, ly, panel_w, panel_h, 3, 3)
        love.graphics.setColor(0.35, 0.35, 0.50)
        love.graphics.rectangle("line", lx, ly, panel_w, panel_h, 3, 3)
        love.graphics.setColor(0.7, 0.8, 1.0)
        love.graphics.setFont(font)
        love.graphics.printf("BIOMES", lx, ly + 3, panel_w, "center")
        for idx, entry in ipairs(BIOME_LEGEND) do
            local col = (idx - 1) % cols
            local row = math.floor((idx - 1) / cols)
            local ex  = lx + pad + col * col_w
            local ey  = ly + 14 + pad + row * row_h
            love.graphics.setColor(entry[2], entry[3], entry[4])
            love.graphics.rectangle("fill", ex, ey + 1, swatch_w, swatch_w)
            love.graphics.setColor(0.6, 0.6, 0.6)
            love.graphics.rectangle("line", ex, ey + 1, swatch_w, swatch_w)
            love.graphics.setColor(0.88, 0.88, 0.88)
            love.graphics.print(entry[1], ex + swatch_w + 3, ey)
        end
    end

    -- Hover tooltip
    if wsc.world_image and wsc.heightmap then
        local mx, my = love.mouse.getPosition()
        if mx > sidebar_w and mx < sw and my > 0 and my < sh - 22 then
            local C   = self.game.C
            local ts  = C.MAP.TILE_SIZE
            -- Convert screen → world cell
            local wpx = wsc.camera.x + (mx - sidebar_w - vw / 2) / wsc.camera.scale
            local wpy = wsc.camera.y + (my - sh / 2) / wsc.camera.scale
            local cx  = math.floor(wpx / ts) + 1
            local cy  = math.floor(wpy / ts) + 1
            if cx >= 1 and cx <= wsc.world_w and cy >= 1 and cy <= wsc.world_h then
                local elev = wsc.heightmap[cy][cx]
                local bd   = wsc.biome_data and wsc.biome_data[(cy - 1) * wsc.world_w + cx]
                local font = self.game.fonts.ui_small
                -- Build tooltip lines
                local lines = {}
                if bd then
                    lines[#lines + 1] = bd.name
                else
                    -- height view: derive basic biome from elevation
                    local p = wsc.params
                    if elev < p.deep_ocean_max then lines[#lines + 1] = "Deep Ocean"
                    elseif elev < p.ocean_max  then lines[#lines + 1] = "Ocean"
                    elseif elev < p.coast_max  then lines[#lines + 1] = "Beach"
                    elseif elev < p.plains_max then lines[#lines + 1] = "Plains"
                    elseif elev < p.forest_max then lines[#lines + 1] = "Forest"
                    elseif elev < p.highland_max then lines[#lines + 1] = "Highland"
                    elseif elev < p.mountain_max then lines[#lines + 1] = "Mountain"
                    else lines[#lines + 1] = "Snow Cap" end
                end
                lines[#lines + 1] = string.format("Elevation:  %.2f", elev)
                if bd and not bd.is_river and not bd.is_lake then
                    local t = bd.temp
                    local tl = t < 0.22 and "arctic" or t < 0.45 and "cold" or t < 0.68 and "warm" or "tropical"
                    lines[#lines + 1] = string.format("Temp:       %.2f  (%s)", t, tl)
                    local wt = bd.wet
                    local wl = wt < 0.12 and "arid" or wt < 0.30 and "dry" or wt < 0.55 and "moderate" or wt < 0.72 and "wet" or "very wet"
                    lines[#lines + 1] = string.format("Wetness:    %.2f  (%s)", wt, wl)
                end
                -- Measure and draw
                local pad    = 7
                local line_h = 14
                local tw     = 170
                local th     = #lines * line_h + pad * 2
                local tx = mx + 14
                local ty = my + 14
                if tx + tw > sw then tx = mx - tw - 4 end
                if ty + th > sh - 22 then ty = my - th - 4 end
                love.graphics.setScissor()
                love.graphics.setColor(0.05, 0.05, 0.10, 0.88)
                love.graphics.rectangle("fill", tx, ty, tw, th, 3, 3)
                love.graphics.setColor(0.40, 0.55, 0.80)
                love.graphics.rectangle("line", tx, ty, tw, th, 3, 3)
                love.graphics.setFont(font)
                for idx, line in ipairs(lines) do
                    love.graphics.setColor(idx == 1 and 1 or 0.78, idx == 1 and 1 or 0.78, idx == 1 and 1 or 0.78)
                    love.graphics.print(line, tx + pad, ty + pad + (idx - 1) * line_h)
                end
            end
        end
    end

    -- Status bar
    love.graphics.setScissor(sidebar_w, sh - 22, vw, 22)
    love.graphics.setColor(0, 0, 0, 0.75)
    love.graphics.rectangle("fill", sidebar_w, sh - 22, vw, 22)
    love.graphics.setColor(0.6, 0.6, 0.7)
    love.graphics.setFont(self.game.fonts.ui_small)
    love.graphics.print(wsc.status_text or "WORLD GEN  |  F8 close", sidebar_w + 8, sh - 18)

    love.graphics.setScissor()
    love.graphics.setColor(1, 1, 1)
end

return WorldSandboxView
