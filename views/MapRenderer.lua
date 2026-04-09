-- views/MapRenderer.lua
-- Rendering logic for Map objects.
-- Extracted from models/Map.lua to keep the model free of love.* calls.

local TilePalette = require("data.tile_palette")

local MapRenderer = {}

local function getTileColor(tile_type, is_in_downtown, C_MAP)
    local entry = TilePalette[tile_type] or TilePalette.default
    local key = is_in_downtown and entry.downtown or entry.city
    return C_MAP.COLORS[key]
end

function MapRenderer.draw(map)
    MapRenderer.drawGrid(map, map.grid, 1)
    love.graphics.setColor(1, 1, 1, 1)
end

-- Draws only road-type tiles (for overlaying on top of a background image).
function MapRenderer.drawRoads(map)
    local C_MAP = map.C.MAP
    if not map.grid or #map.grid == 0 then return end
    local tile_size = map.tile_pixel_size or C_MAP.TILE_SIZE
    local road_color     = C_MAP.COLORS.ROAD
    local dt_road_color  = C_MAP.COLORS.DOWNTOWN_ROAD
    local art_color      = C_MAP.COLORS.ARTERIAL
    for y = 1, #map.grid do
        local row = map.grid[y]
        for x = 1, #row do
            local t = row[x].type
            local c
            if t == "road" then
                c = road_color
            elseif t == "downtown_road" then
                c = dt_road_color
            elseif t == "arterial" then
                c = art_color
            elseif t == "highway" then
                c = C_MAP.COLORS.ROAD  -- draw highways too so they're visible
            end
            if c then
                love.graphics.setColor(c[1], c[2], c[3], 1)
                love.graphics.rectangle("fill", (x-1)*tile_size, (y-1)*tile_size, tile_size, tile_size)
            end
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function MapRenderer.buildTileCanvas(map)
    local C_MAP = map.C.MAP
    local grid = map.grid
    if not grid or #grid == 0 then return end
    local grid_h = #grid
    local grid_w = #grid[1]
    if grid_w == 0 then return end
    local tile_size = map.tile_pixel_size or C_MAP.TILE_SIZE
    local cw = grid_w * tile_size
    local ch = grid_h * tile_size
    if cw < 1 or ch < 1 then return end

    local dt_x_min = map.downtown_offset and map.downtown_offset.x or 0
    local dt_y_min = map.downtown_offset and map.downtown_offset.y or 0
    local dt_x_max = dt_x_min + (map.downtown_grid_width  or 0)
    local dt_y_max = dt_y_min + (map.downtown_grid_height or 0)

    local prev_canvas = love.graphics.getCanvas()
    local sc_x, sc_y, sc_w, sc_h = love.graphics.getScissor()
    love.graphics.setScissor()

    local canvas = love.graphics.newCanvas(cw, ch)
    canvas:setFilter("nearest", "nearest")
    love.graphics.setCanvas(canvas)
    love.graphics.push()
    love.graphics.origin()
    love.graphics.clear(0, 0, 0, 0)

    for y = 1, grid_h do
        for x = 1, grid_w do
            local tile = grid[y][x]
            local is_in_downtown = (x >= dt_x_min and x < dt_x_max and y >= dt_y_min and y < dt_y_max)
            local color = getTileColor(tile.type, is_in_downtown, C_MAP)
            love.graphics.setColor(color[1], color[2], color[3], 1)
            love.graphics.rectangle("fill", (x-1)*tile_size, (y-1)*tile_size, tile_size, tile_size)
        end
    end

    love.graphics.pop()
    love.graphics.setCanvas(prev_canvas)
    if sc_x then love.graphics.setScissor(sc_x, sc_y, sc_w, sc_h) end
    love.graphics.setColor(1, 1, 1, 1)
    map._tile_canvas = canvas
end

function MapRenderer.drawGrid(map, grid, alpha)
    local C_MAP = map.C.MAP
    if not grid or #grid == 0 then return end

    -- Fast path: use pre-rendered canvas when drawing map.grid at full alpha.
    if grid == map.grid and (alpha == nil or alpha == 1) then
        if not map._tile_canvas then
            MapRenderer.buildTileCanvas(map)
        end
        if map._tile_canvas then
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(map._tile_canvas, 0, 0)
            return
        end
    end

    -- Fallback: per-tile rendering (first frame before canvas is ready, or non-self grids).
    local grid_h, grid_w = #grid, #grid[1]
    local tile_size = map.tile_pixel_size or C_MAP.TILE_SIZE

    local dt_x_min = map.downtown_offset.x
    local dt_y_min = map.downtown_offset.y
    local dt_x_max = map.downtown_offset.x + map.downtown_grid_width
    local dt_y_max = map.downtown_offset.y + map.downtown_grid_height

    for y = 1, grid_h do
        for x = 1, grid_w do
            local tile = grid[y][x]
            local is_in_downtown = (x >= dt_x_min and x < dt_x_max and y >= dt_y_min and y < dt_y_max)
            local color = getTileColor(tile.type, is_in_downtown, C_MAP)
            love.graphics.setColor(color[1], color[2], color[3], alpha or 1)
            love.graphics.rectangle("fill", (x-1) * tile_size, (y-1) * tile_size, tile_size, tile_size)
        end
    end
end

return MapRenderer
