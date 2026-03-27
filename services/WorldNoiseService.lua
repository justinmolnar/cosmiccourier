-- services/WorldNoiseService.lua
-- Pure FBM noise → normalized heightmap + colormap.
-- Multiple islands emerge naturally from noise topology wherever peaks exceed sea level.
-- No artificial island placement. sea level is implicitly the coast_max threshold.

local WorldNoiseService = {}

-- Standard FBM — smooth hills, used for continental shape and moisture.
local function fbm(px, py, scale, octaves, persistence, lacunarity, ox, oy)
    local val, amp, freq, total = 0, 1, scale, 0
    for _ = 1, math.floor(octaves) do
        val   = val + amp * love.math.noise(px * freq + ox, py * freq + oy)
        total = total + amp
        amp   = amp * persistence
        freq  = freq * lacunarity
    end
    return val / total
end

-- Ridged FBM — sharp peaks instead of smooth domes, used for mountain ranges.
-- Each octave is inverted so valleys become ridges; squaring sharpens the peaks.
local function ridge_fbm(px, py, scale, octaves, persistence, lacunarity, ox, oy)
    local val, amp, freq, total = 0, 1, scale, 0
    for _ = 1, math.floor(octaves) do
        local n = love.math.noise(px * freq + ox, py * freq + oy)
        n = 1 - 2 * math.abs(n - 0.5)   -- flip: valleys → peaks
        n = n * n                          -- square: sharpens ridges
        val   = val + amp * n
        total = total + amp
        amp   = amp * persistence
        freq  = freq * lacunarity
    end
    return val / total
end


-- Returns 0 at map edges, 1 once you're `margin` fraction inside.
-- Used to suppress land near borders without touching ocean floor depth.
local function edge_mask(x, y, w, h, margin)
    local nx = (x - 1) / math.max(1, w - 1)
    local ny = (y - 1) / math.max(1, h - 1)
    local dx = math.min(nx, 1 - nx)
    local dy = math.min(ny, 1 - ny)
    local fx = math.min(1, dx / math.max(0.001, margin))
    local fy = math.min(1, dy / math.max(0.001, margin))
    return fx * fy
end

-- Discrete biome colors — flat per band, no lerp between biomes.
-- This gives crisp colour bands like a classic tile map, not a smooth haze.
local function biome_color(h, m, p)
    if h < p.deep_ocean_max then
        return { 0.04, 0.08, 0.30 }
    elseif h < p.ocean_max then
        return { 0.07, 0.15, 0.45 }
    elseif h < p.coast_max then
        return { 0.76, 0.70, 0.48 }
    elseif h < p.plains_max then
        return (m > 0.5) and { 0.35, 0.62, 0.20 } or { 0.55, 0.52, 0.20 }
    elseif h < p.forest_max then
        return (m > 0.5) and { 0.14, 0.40, 0.10 } or { 0.32, 0.44, 0.14 }
    elseif h < p.highland_max then
        return { 0.40, 0.44, 0.26 }
    elseif h < p.mountain_max then
        return { 0.52, 0.48, 0.42 }
    else
        return { 0.88, 0.90, 0.95 }
    end
end

function WorldNoiseService.generate(w, h, p)
    local sx = p.seed_x or 0
    local sy = p.seed_y or 0
    local margin = p.edge_margin or 0.22

    -- Pass 1: island shapes via smooth FBM only.
    -- Terrain layer is plain FBM here — ridge noise is NOT mixed in so it
    -- doesn't fragment coastlines.
    local heightmap = {}
    local min_h, max_h = math.huge, -math.huge
    for y = 1, h do
        heightmap[y] = {}
        for x = 1, w do
            local continental = fbm(x, y, p.continental_scale, p.continental_octaves, 0.6,           2.0,          sx,        sy)
            local terrain     = fbm(x, y, p.terrain_scale,     p.terrain_octaves,     p.persistence, p.lacunarity, sx + 1000, sy + 1000)
            local detail      = fbm(x, y, p.detail_scale,      p.detail_octaves,      0.5,           2.0,          sx + 2000, sy + 2000)
            local raw = continental * p.continental_weight
                      + terrain     * p.terrain_weight
                      + detail      * p.detail_weight
            heightmap[y][x] = raw
            if raw < min_h then min_h = raw end
            if raw > max_h then max_h = raw end
        end
    end

    -- Pass 2: normalize, apply edge mask, then overlay mountain ridges ONLY on
    -- land cells so island shapes are completely untouched.
    local range = max_h - min_h
    if range < 0.0001 then range = 0.0001 end

    local colormap = {}
    for y = 1, h do
        colormap[y] = {}
        for x = 1, w do
            local norm = (heightmap[y][x] - min_h) / range

            -- Edge mask: suppress land near map borders
            local em = edge_mask(x, y, w, h, margin)
            if norm > p.deep_ocean_max then
                norm = p.deep_ocean_max + (norm - p.deep_ocean_max) * em
            end

            -- Mountain pass: ridge noise added on top of land only.
            -- land_t ramps from 0 at the coastline to 1 at the interior peak,
            -- so mountains concentrate inland and fade to zero at the shore.
            if norm > p.coast_max then
                local land_t  = (norm - p.coast_max) / (1.0 - p.coast_max)
                local ridge   = ridge_fbm(x, y, p.mountain_scale, p.mountain_octaves, 0.5, 2.0, sx + 3000, sy + 3000)
                norm = norm + ridge * p.mountain_strength * land_t
                norm = math.min(1.0, norm)
            end

            heightmap[y][x] = norm
            local moisture = fbm(x, y, p.moisture_scale, p.moisture_octaves, 0.5, 2.0, sx + 5000, sy + 5000)
            colormap[y][x] = biome_color(norm, moisture, p)
        end
    end

    return { heightmap = heightmap, colormap = colormap }
end

return WorldNoiseService
