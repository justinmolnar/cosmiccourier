-- views/MapLabels.lua
-- Renders continent / region / city labels over the world view. Zoom-gated
-- cross-fade: continents visible at lowest zoom, cities at highest. All
-- thresholds + fonts + colors read from data/names/map_label_config.lua.
--
-- Drawn in screen space (no world-transform push) for simplicity. Positions
-- compute from each entity's centroid (world-cell coords) × TILE_SIZE.

local MapLabels = {}

local Config       = require("data.names.map_label_config")
local ScopeService = require("services.ScopeService")
local WrapRender   = require("views.WrapRender")

-- ─── Opacity easing ──────────────────────────────────────────────────────────
-- Returns an alpha in [0, 1] for a given camera scale `cs` within a scope's
-- visibility window. Outside [visible_cs_min, visible_cs_max] → 0.
-- Inside the window it linearly fades in from min→fade_low, stays at 1 in
-- [fade_low, fade_high], and fades out fade_high→max.
local function scopeAlpha(cfg, cs)
    if cs <= cfg.visible_cs_min or cs >= cfg.visible_cs_max then return 0 end
    if cs < cfg.fade_low then
        return (cs - cfg.visible_cs_min) / math.max(0.0001, cfg.fade_low - cfg.visible_cs_min)
    end
    if cs > cfg.fade_high then
        return 1 - (cs - cfg.fade_high) / math.max(0.0001, cfg.visible_cs_max - cfg.fade_high)
    end
    return 1
end

-- Centroid of a city in world-cell space (halfway across its grid).
local function cityCentroidWorldCells(city_map)
    local w = (city_map.city_grid_width  or 3) / 6
    local h = (city_map.city_grid_height or 3) / 6
    return (city_map.world_mn_x or 1) + w, (city_map.world_mn_y or 1) + h
end

-- Project world-pixel (wpx, wpy) to screen (sx, sy) using the camera. The
-- optional `offset_x` shifts the world position to project a wrapped copy.
local function worldToScreen(Game, wpx, wpy, sidebar_w, screen_w, screen_h, offset_x)
    local game_world_w = screen_w - sidebar_w
    local cx, cy = Game.camera.x, Game.camera.y
    local cs     = Game.camera.scale
    local sx = sidebar_w + game_world_w * 0.5 + (wpx + (offset_x or 0) - cx) * cs
    local sy = screen_h  * 0.5 + (wpy - cy) * cs
    return sx, sy
end

-- Per-city scale from grid width, clamped to the config range.
local function cityEntryScale(e, cfg)
    if not cfg.proportional_to_city_size then return 1 end
    local w = e.city_grid_width or 0
    if w <= 0 then return 1 end
    local ref  = cfg.city_size_ref or 60
    local lo   = cfg.city_size_min or 0.7
    local hi   = cfg.city_size_max or 1.8
    local s    = w / ref
    if s < lo then s = lo end
    if s > hi then s = hi end
    return s
end

-- Core draw — one loop per scope, most-transparent on top. Skips labels whose
-- centroid sits under fog of war (unrevealed by the current scope tier).
local function drawScope(Game, entries, cfg, alpha, font, sidebar_w, screen_w, screen_h)
    if alpha <= 0 or not entries then return end
    local ts = Game.C.MAP.TILE_SIZE
    love.graphics.setFont(font)
    local color  = cfg.color  or {1, 1, 1, 1}
    local shadow = cfg.shadow or {0, 0, 0, 0.75}
    local th     = font:getHeight()
    for _, e in ipairs(entries) do
        local cxw, cyw
        if e.centroid then
            cxw, cyw = e.centroid.cx, e.centroid.cy
        elseif e.world_mn_x then
            cxw, cyw = cityCentroidWorldCells(e)
        end
        if e.name and cxw then
            -- Fog cull: only when the scope opts in (cities). Continents and
            -- regions are area-scale labels; they stay visible so the player
            -- can orient across unexplored territory.
            local revealed = true
            if cfg.fog_cull then
                local scx = math.max(1, math.floor(cxw * 3))
                local scy = math.max(1, math.floor(cyw * 3))
                revealed = ScopeService.isRevealed(Game, scx, scy)
            end
            if revealed then
                local wpx = (cxw - 0.5) * ts
                local wpy = (cyw - 0.5) * ts
                local text = cfg.uppercase and string.upper(e.name) or e.name
                local entry_scale = cityEntryScale(e, cfg)
                local tw = font:getWidth(text) * entry_scale
                local dh = th * entry_scale

                -- Render once per visible world copy. Outside an active wrap
                -- context this collapses to a single pass at offset=0.
                WrapRender.eachOffset(Game, function(offset_x)
                    local sx, sy = worldToScreen(Game, wpx, wpy,
                                                 sidebar_w, screen_w, screen_h, offset_x)
                    if sx >= sidebar_w - 200 and sx <= screen_w + 200
                       and sy >= -50 and sy <= screen_h + 50 then
                        love.graphics.setColor(shadow[1], shadow[2], shadow[3], (shadow[4] or 1) * alpha)
                        for _, d in ipairs({{-1,0},{1,0},{0,-1},{0,1}}) do
                            love.graphics.print(text, sx - tw * 0.5 + d[1], sy - dh * 0.5 + d[2],
                                                0, entry_scale, entry_scale)
                        end
                        love.graphics.setColor(color[1], color[2], color[3], (color[4] or 1) * alpha)
                        love.graphics.print(text, sx - tw * 0.5, sy - dh * 0.5,
                                            0, entry_scale, entry_scale)
                    end
                end)
            end
        end
    end
end

-- Build one scaled font per scope, cached on Game so we don't rebuild each frame.
local function scopedFont(Game, key, scale)
    Game._map_label_fonts = Game._map_label_fonts or {}
    local cache = Game._map_label_fonts
    if cache[key] then return cache[key] end
    local base = (Game.fonts and Game.fonts.ui) or love.graphics.getFont()
    local size = math.max(10, math.floor((base:getHeight() or 14) * (scale or 1)))
    local font = love.graphics.newFont(size)
    cache[key] = font
    return font
end

function MapLabels.render(Game, sidebar_w, screen_w, screen_h)
    if not Game or not Game.camera then return end
    if not (Game.state and Game.state.show_map_labels) then return end

    local cs = Game.camera.scale
    local a_cont = scopeAlpha(Config.continent, cs)
    local a_reg  = scopeAlpha(Config.region,    cs)
    local a_city = scopeAlpha(Config.city,      cs)
    if a_cont <= 0 and a_reg <= 0 and a_city <= 0 then return end

    drawScope(Game, Game.world_continents_list, Config.continent, a_cont,
              scopedFont(Game, "continent", Config.continent.font_scale),
              sidebar_w, screen_w, screen_h)
    drawScope(Game, Game.world_regions_list, Config.region, a_reg,
              scopedFont(Game, "region", Config.region.font_scale),
              sidebar_w, screen_w, screen_h)
    drawScope(Game, Game.maps and Game.maps.all_cities, Config.city, a_city,
              scopedFont(Game, "city", Config.city.font_scale),
              sidebar_w, screen_w, screen_h)
    love.graphics.setColor(1, 1, 1, 1)
end

return MapLabels
