-- lib/wfc.lua
-- A generic, robust Wave Function Collapse (WFC) implementation.

local WFC = {}

-- Helper functions are defined as local to the file before being used.
local function get_neighbors(p, width, height)
    local list = {}
    if p.x > 1 then table.insert(list, {x=p.x-1, y=p.y}) end
    if p.x < width then table.insert(list, {x=p.x+1, y=p.y}) end
    if p.y > 1 then table.insert(list, {x=p.x, y=p.y-1}) end
    if p.y < height then table.insert(list, {x=p.x, y=p.y+1}) end
    return list
end

local function count_possibilities(tbl)
    local count = 0
    for _ in pairs(tbl) do count = count + 1 end
    return count
end

function WFC.solve(width, height, tileset, adjacency_rules, initial_constraints)
    print("--- WFC Solver: Initializing new robust solver. ---")
    initial_constraints = initial_constraints or {}

    -- Step 1: Setup
    local wave = {} -- This is our main grid of cells
    local all_tile_names = {}
    for _, tile in ipairs(tileset) do
        table.insert(all_tile_names, tile.name)
    end

    -- Initialize every cell with all possibilities (using a set-like table for efficiency)
    for y = 1, height do
        wave[y] = {}
        for x = 1, width do
            wave[y][x] = {}
            for _, name in ipairs(all_tile_names) do
                wave[y][x][name] = true
            end
        end
    end

    local propagation_stack = {}

    -- Step 2: Apply initial constraints
    for key, tile_type in pairs(initial_constraints) do
        local y_str, x_str = key:match("([^,]+),([^,]+)")
        local y, x = tonumber(y_str), tonumber(x_str)
        if y and x then
            wave[y][x] = {[tile_type] = true}
            table.insert(propagation_stack, {x=x, y=y})
        end
    end
    
    -- Step 3: Main solver loop
    while true do
        -- A. Propagate any changes until the system is stable
        while #propagation_stack > 0 do
            local current_p = table.remove(propagation_stack, 1)
            local current_possibilities = wave[current_p.y][current_p.x]

            for _, neighbor_p in ipairs(get_neighbors(current_p, width, height)) do
                local neighbor_possibilities = wave[neighbor_p.y][neighbor_p.x]
                
                local valid_supporters = {}
                for tile, _ in pairs(current_possibilities) do
                    local rules = adjacency_rules[tile] or {}
                    for _, neighbor_rule in ipairs(rules) do
                        valid_supporters[neighbor_rule] = true
                    end
                end

                local changed = false
                for neighbor_tile, _ in pairs(neighbor_possibilities) do
                    if not valid_supporters[neighbor_tile] then
                        neighbor_possibilities[neighbor_tile] = nil
                        changed = true
                    end
                end

                if changed then
                    table.insert(propagation_stack, neighbor_p)
                end
            end
        end

        -- B. Observe: Find the next cell to collapse
        local min_entropy = #all_tile_names + 1
        local min_entropy_cells = {}
        for y = 1, height do
            for x = 1, width do
                local possibilities_count = count_possibilities(wave[y][x])
                if possibilities_count > 1 then
                    if possibilities_count < min_entropy then
                        min_entropy = possibilities_count
                        min_entropy_cells = {{x=x, y=y}}
                    elseif possibilities_count == min_entropy then
                        table.insert(min_entropy_cells, {x=x, y=y})
                    end
                end
            end
        end

        if #min_entropy_cells == 0 then break end -- Finished

        -- C. Collapse the chosen cell
        local cell_to_collapse = min_entropy_cells[love.math.random(1, #min_entropy_cells)]
        
        local possibilities = {}
        for tile, _ in pairs(wave[cell_to_collapse.y][cell_to_collapse.x]) do
            table.insert(possibilities, tile)
        end

        if #possibilities == 0 then print("WFC ERROR: Contradiction found."); break; end

        local chosen_tile = possibilities[love.math.random(1, #possibilities)]
        wave[cell_to_collapse.y][cell_to_collapse.x] = {[chosen_tile] = true}
        
        -- Add the newly collapsed cell to the stack to start the next propagation wave
        table.insert(propagation_stack, cell_to_collapse)
    end
    
    -- Step 4: Convert to final output format
    local output_grid = {}
    for y = 1, height do
        output_grid[y] = {}
        for x = 1, width do
            local final_type = "error"
            local count = 0
            for tile, _ in pairs(wave[y][x]) do
                final_type = tile
                count = count + 1
            end
            if count ~= 1 then final_type = "error" end
            output_grid[y][x] = {type = final_type}
        end
    end
    
    print("--- WFC Solver: Finished. ---")
    return output_grid
end

return WFC