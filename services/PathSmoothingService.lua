-- services/PathSmoothingService.lua
-- Builds smooth pixel waypoint lists from A* paths, using lib/path_utils.chaikin.

local chaikin = require("lib.path_utils").chaikin

local PathSmoothingService = {}

function PathSmoothingService.buildSmoothPath(vehicle, game)
    if not vehicle.path or #vehicle.path == 0 then
        vehicle.smooth_path = nil
        return
    end
    local map = game.maps[vehicle.operational_map_key]
    if not map then
        vehicle.smooth_path = nil
        return
    end
    local tps = map.tile_pixel_size or game.C.MAP.TILE_SIZE

    local function nodePixels(node)
        if map.road_v_rxs then
            return node.x * tps, node.y * tps
        else
            return map:getPixelCoords(node.x, node.y)
        end
    end

    local smooth = {}
    local function add(x, y)
        local s = smooth[#smooth]
        if not s or s[1] ~= x or s[2] ~= y then smooth[#smooth+1] = {x, y} end
    end

    local function flush_chain(flat)
        if #flat < 4 then
            if #flat >= 2 then add(flat[#flat-1], flat[#flat]) end
            return
        end
        local s = chaikin(flat, 4)
        for i = 2, #s / 2 do
            add(s[2*i-1], s[2*i])
        end
    end

    local chain = {vehicle.px, vehicle.py}

    for _, node in ipairs(vehicle.path) do
        local npx, npy = nodePixels(node)
        if node.is_tile then
            flush_chain(chain)
            add(npx, npy)
            chain = {npx, npy}
        else
            chain[#chain+1] = npx
            chain[#chain+1] = npy
        end
    end
    flush_chain(chain)

    vehicle.smooth_path = {}
    for k = 2, #smooth do
        vehicle.smooth_path[#vehicle.smooth_path+1] = smooth[k]
    end
    if #vehicle.smooth_path == 0 then vehicle.smooth_path = nil end
end

return PathSmoothingService
