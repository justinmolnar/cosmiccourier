-- services/WfcBlockService.lua
-- This service handles the high-fidelity WFC pass for generating local blocks and roads.

local WfcBlockService = {}

local WFC = require("lib.wfc")
local WfcBlockTiles = require("data.WfcBlockTiles")

function WfcBlockService.generateBlocks(params)
    print("--- Starting WFC Block Generation Service (Final Tuning Pass) ---")
    local width, height = params.width, params.height
    local zone_grid, arterial_paths = params.zone_grid, params.arterial_paths

    if not (width and height and zone_grid and arterial_paths) then
        print("ERROR: WfcBlockService.generateBlocks - Missing required parameters.")
        return nil
    end

    local tileset = WfcBlockTiles.getTileset()
    local adjacency_rules = WfcBlockTiles.getAdjacencyRules()
    local tiles_by_id = {}
    for _, tile in ipairs(tileset) do tiles_by_id[tile.id] = tile end

    local states = {}
    for i = 1, #tileset do table.insert(states, i) end
    
    local wfc = WFC.new(width, height, states, adjacency_rules)
    print("WFC Solver initialized for a " .. width .. "x" .. height .. " grid.")

    -- FINAL TUNING: Apply much more opinionated weights
    print("Applying tuned weights...")
    for y = 1, height do
        for x = 1, width do
            local target_zone = zone_grid[y][x]
            for _, tile in ipairs(tileset) do
                -- 1. Base weight strongly favors tiles with FEWER roads to prevent mazes
                local num_connections = (tile.connections.N and 1 or 0) + (tile.connections.E and 1 or 0) + (tile.connections.S and 1 or 0) + (tile.connections.W and 1 or 0)
                local base_weight = 1
                if num_connections == 0 then base_weight = 100 -- Heavily favor solid blocks
                elseif num_connections == 1 then base_weight = 50  -- Favor dead ends
                elseif num_connections == 2 then base_weight = 10  -- Straights and corners are common
                else base_weight = 1 end                   -- T-junctions and Crossroads are rare

                -- 2. Zone-matching weight
                local zone_multiplier = 1
                if tile.zone == target_zone then zone_multiplier = 50 -- Good bonus for matching the zone
                elseif tile.zone == "empty" then zone_multiplier = 5
                end

                WFC.setWeight(wfc, x, y, tile.id, base_weight * zone_multiplier)
            end
        end
    end
    print("Tuned weights applied.")

    -- Influence grid with Arterial Roads using an overwhelming weight
    print("Applying arterial road influences...")
    local ARTERIAL_MULTIPLIER = 1e9 -- Effectively infinite weight

    for _, path in ipairs(arterial_paths) do
        for i = 1, #path - 1 do
            local p1, p2 = path[i], path[i+1]
            if p1.y == p2.y and p1.x ~= p2.x then -- Horizontal
                local x, y_top, y_bottom = math.floor(math.min(p1.x, p2.x)), math.floor(p1.y) - 1, math.floor(p1.y)
                if y_top >= 1 and y_bottom <= height and x >= 1 and x <= width then
                    for id, _ in pairs(wfc.weights[y_top][x]) do if tiles_by_id[id].connections.S then wfc.weights[y_top][x][id] = wfc.weights[y_top][x][id] * ARTERIAL_MULTIPLIER end end
                    for id, _ in pairs(wfc.weights[y_bottom][x]) do if tiles_by_id[id].connections.N then wfc.weights[y_bottom][x][id] = wfc.weights[y_bottom][x][id] * ARTERIAL_MULTIPLIER end end
                end
            elseif p1.x == p2.x and p1.y ~= p2.y then -- Vertical
                local y, x_left, x_right = math.floor(math.min(p1.y, p2.y)), math.floor(p1.x) - 1, math.floor(p1.x)
                if x_left >= 1 and x_right <= width and y >= 1 and y <= height then
                    for id, _ in pairs(wfc.weights[y][x_left]) do if tiles_by_id[id].connections.E then wfc.weights[y][x_left][id] = wfc.weights[y][x_left][id] * ARTERIAL_MULTIPLIER end end
                    for id, _ in pairs(wfc.weights[y][x_right]) do if tiles_by_id[id].connections.W then wfc.weights[y][x_right][id] = wfc.weights[y][x_right][id] * ARTERIAL_MULTIPLIER end end
                end
            end
        end
    end
    print("Arterial influences applied.")

    -- Run the WFC Solver
    local success = WFC.solve(wfc)
    if not success then
        print("ERROR: WFC solver failed to find a valid solution.")
        return nil
    end

    -- Interpret the Results
    print("WFC Solve successful. Interpreting results...")
    local result_grid_ids = WFC.getResult(wfc)
    local final_render_grid, road_segments = {}, {}

    for y = 1, height do
        final_render_grid[y] = {}
        for x = 1, width do
            local tile_id = result_grid_ids[y][x]
            if tile_id and tiles_by_id[tile_id] then
                local tile_data = tiles_by_id[tile_id]
                final_render_grid[y][x] = { zone = tile_data.zone }
                if tile_data.connections.N then table.insert(road_segments, {x1=x-1, y1=y-1, x2=x, y2=y-1}) end
                if tile_data.connections.W then table.insert(road_segments, {x1=x-1, y1=y-1, x2=x-1, y2=y}) end
            else
                final_render_grid[y][x] = { zone = "empty" }
            end
        end
    end
    
    print("Interpretation complete. Returning final grid and road data.")
    return { grid = final_render_grid, roads = road_segments }
end

return WfcBlockService