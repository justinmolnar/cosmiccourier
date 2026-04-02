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

    -- Snap highway tile centres to the smooth visual highway curve (same logic as
    -- the trip preview).  Built once per path assignment, not per frame.
    local hw_smooth = game._world_highway_smooth
    local ugrid     = game.maps.unified and game.maps.unified.grid

    local function nodePixels(node)
        local orig_px, orig_py = map:getPixelCoords(node.x, node.y)
        if hw_smooth and ugrid then
            local row  = ugrid[node.y]
            local tile = row and row[node.x]
            if tile and tile.type == "highway" then
                local best_d2 = math.huge
                local snap_px, snap_py = orig_px, orig_py
                for _, chain in ipairs(hw_smooth) do
                    for j = 1, #chain - 1, 2 do
                        local d2 = (chain[j]-orig_px)^2 + (chain[j+1]-orig_py)^2
                        if d2 < best_d2 then
                            best_d2 = d2; snap_px = chain[j]; snap_py = chain[j+1]
                        end
                    end
                end
                return snap_px, snap_py
            end
        end
        return orig_px, orig_py
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
