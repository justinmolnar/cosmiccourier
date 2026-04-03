-- services/PathSmoothingService.lua
-- Builds smooth pixel waypoint lists from A* paths, using lib/path_utils.chaikin.

local chaikin = require("lib.path_utils").chaikin

local PathSmoothingService = {}

-- Build (or rebuild) a lookup table: unified sub-cell key → {snap_x, snap_y}.
-- For each point in every smooth road/highway chain, mark the nearest sub-cell
-- (and its cardinal neighbours) so buildSmoothPath can do O(1) lookups instead
-- of searching all smooth-path points per node per path assignment.
-- Call this from GameView whenever new smooth paths are built.
function PathSmoothingService.buildSnapLookup(game)
    local umap = game.maps.unified
    if not umap then return end

    local uts = umap.tile_pixel_size
    local uw  = umap._w
    local uh  = umap._h
    local ts  = game.C.MAP.TILE_SIZE
    local lookup = {}

    local function stamp(chain, world_ox, world_oy)
        for j = 1, #chain - 1, 2 do
            local wx = chain[j] + world_ox
            local wy = chain[j+1] + world_oy
            local ux = math.floor(wx / uts + 0.5)
            local uy = math.floor(wy / uts + 0.5)
            for dy = -1, 1 do
                for dx = -1, 1 do
                    local nx, ny = ux + dx, uy + dy
                    if nx >= 1 and nx <= uw and ny >= 1 and ny <= uh then
                        local k = ny * (uw + 1) + nx
                        if not lookup[k] then
                            lookup[k] = {wx, wy}
                        end
                    end
                end
            end
        end
    end

    if game._world_highway_smooth then
        for _, chain in ipairs(game._world_highway_smooth) do
            stamp(chain, 0, 0)
        end
    end

    for _, cmap in ipairs(game.maps.all_cities or {}) do
        local wox = (cmap.world_mn_x - 1) * ts
        local woy = (cmap.world_mn_y - 1) * ts
        if cmap._road_smooth_paths_v8 then
            for _, chain in ipairs(cmap._road_smooth_paths_v8) do
                stamp(chain, wox, woy)
            end
        end
        if cmap._street_smooth_paths_like_v5 then
            for _, chain in ipairs(cmap._street_smooth_paths_like_v5) do
                stamp(chain, wox, woy)
            end
        end
    end

    umap._snap_lookup = lookup
end

function PathSmoothingService.buildSmoothPath(vehicle, game)
    if not vehicle.path or #vehicle.path == 0 then
        vehicle.smooth_path = nil
        vehicle.smooth_path_i = nil
        return
    end
    local map = game.maps[vehicle.operational_map_key]
    if not map then
        vehicle.smooth_path = nil
        vehicle.smooth_path_i = nil
        return
    end
    local tps = map.tile_pixel_size or game.C.MAP.TILE_SIZE

    local snap_lookup = game.maps.unified and game.maps.unified._snap_lookup
    local uw = game.maps.unified and game.maps.unified._w or 0

    local function nodePixels(node)
        local orig_px, orig_py = map:getPixelCoords(node.x, node.y)
        if snap_lookup then
            local snapped = snap_lookup[node.y * (uw + 1) + node.x]
            if snapped then return snapped[1], snapped[2] end
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
    if #vehicle.smooth_path == 0 then
        vehicle.smooth_path   = nil
        vehicle.smooth_path_i = nil
    else
        vehicle.smooth_path_i = 1
    end
end

return PathSmoothingService
