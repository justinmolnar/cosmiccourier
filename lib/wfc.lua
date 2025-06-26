-- lib/wfc.lua
-- Final, corrected, and robust Wave Function Collapse implementation.

local WFC = {}

-- Constructor for a new WFC solver instance
function WFC.new(width, height, states, adjacency_rules)
    local instance = {
        width = width,
        height = height,
        states = states or {},
        adjacency_rules = adjacency_rules or {},
        
        -- The core data grid: 2D array where each cell is a table
        -- of booleans representing possible states. e.g., grid[y][x][state_id] = true
        grid = {},
        
        -- Helper for entropy calculation
        entropy_grid = {},
        
        -- Store weights for weighted random selection
        weights = {}
    }
    
    WFC._initialize(instance)
    return instance
end

-- Initializes all the internal grids to their default states
function WFC._initialize(wfc)
    local num_states = #wfc.states
    for y = 1, wfc.height do
        wfc.grid[y] = {}
        wfc.entropy_grid[y] = {}
        wfc.weights[y] = {}

        for x = 1, wfc.width do
            wfc.grid[y][x] = {}
            wfc.weights[y][x] = {}
            for _, state_id in ipairs(wfc.states) do
                wfc.grid[y][x][state_id] = true -- All states are initially possible
                wfc.weights[y][x][state_id] = 1.0 -- Default weight
            end
            wfc.entropy_grid[y][x] = num_states
        end
    end
end

-- Sets the weight for a specific state (tile ID) in a specific cell
function WFC.setWeight(wfc, x, y, state_id, weight)
    if not wfc.weights[y] or not wfc.weights[y][x] then return end
    wfc.weights[y][x][state_id] = weight
end

-- Finds the uncollapsed cell with the fewest possible states
function WFC._findLowestEntropyCell(wfc)
    local min_entropy = math.huge
    local candidates = {}
    
    for y = 1, wfc.height do
        for x = 1, wfc.width do
            if wfc.entropy_grid[y][x] > 1 then
                local e = wfc.entropy_grid[y][x]
                if e < min_entropy then
                    min_entropy = e
                    candidates = {{x=x, y=y}}
                elseif e == min_entropy then
                    table.insert(candidates, {x=x, y=y})
                end
            end
        end
    end
    
    if #candidates == 0 then return nil end -- All cells are collapsed or have only one option left.
    return candidates[love.math.random(1, #candidates)]
end

-- The main solver function
function WFC.solve(wfc)
    local total_cells = wfc.width * wfc.height
    
    for i = 1, total_cells do
        local cell_pos = WFC._findLowestEntropyCell(wfc)
        
        if not cell_pos then
            -- No more cells with entropy > 1, check for contradictions
            for y = 1, wfc.height do
                for x = 1, wfc.width do
                    if wfc.entropy_grid[y][x] == 0 then
                        print(string.format("WFC CONTRADICTION at (%d, %d). Cannot solve.", x, y))
                        return false -- Failure due to contradiction
                    end
                end
            end
            print("WFC: Successfully collapsed all cells.")
            return true -- Success
        end

        -- Collapse the chosen cell
        local x, y = cell_pos.x, cell_pos.y
        local possibilities = wfc.grid[y][x]
        
        local valid_options = {}
        local total_weight = 0
        for state, is_possible in pairs(possibilities) do
            if is_possible then
                local weight = wfc.weights[y][x][state] or 1
                table.insert(valid_options, {state=state, weight=weight})
                total_weight = total_weight + weight
            end
        end

        if #valid_options == 0 then
            print(string.format("WFC CONTRADICTION during collapse at (%d, %d).", x, y))
            return false
        end

        local rand_val = love.math.random() * total_weight
        local chosen_state = valid_options[#valid_options].state -- Fallback
        local current_weight = 0
        for _, item in ipairs(valid_options) do
            current_weight = current_weight + item.weight
            if rand_val <= current_weight then
                chosen_state = item.state
                break
            end
        end

        -- Set the chosen state and propagate
        for state, _ in pairs(wfc.grid[y][x]) do
            wfc.grid[y][x][state] = (state == chosen_state)
        end
        wfc.entropy_grid[y][x] = 1
        WFC._propagate(wfc, x, y)
    end
    
    print("WFC: Solver loop finished.")
    return true
end

-- Spreads constraints from a recently collapsed cell
function WFC._propagate(wfc, startX, startY)
    local stack = {{x=startX, y=startY}}

    while #stack > 0 do
        local pos = table.remove(stack, 1)

        local directions = {{0,-1,"N","S"}, {0,1,"S","N"}, {-1,0,"W","E"}, {1,0,"E","W"}}
        for _, dir_info in ipairs(directions) do
            local dx, dy, dir_from, dir_to = dir_info[1], dir_info[2], dir_info[3], dir_info[4]
            local nx, ny = pos.x + dx, pos.y + dy

            if nx >= 1 and nx <= wfc.width and ny >= 1 and ny <= wfc.height then
                if wfc.entropy_grid[ny][nx] > 1 then
                    
                    -- Get all valid states for the current cell
                    local valid_states_from = {}
                    for state, is_possible in pairs(wfc.grid[pos.y][pos.x]) do
                        if is_possible then table.insert(valid_states_from, state) end
                    end

                    -- Find all states the neighbor is allowed to be
                    local allowed_for_neighbor = {}
                    for _, state_from in ipairs(valid_states_from) do
                        if wfc.adjacency_rules[state_from] and wfc.adjacency_rules[state_from][dir_from] then
                            for state_to, _ in pairs(wfc.adjacency_rules[state_from][dir_from]) do
                                allowed_for_neighbor[state_to] = true
                            end
                        end
                    end
                    
                    -- Remove possibilities from neighbor
                    local changed = false
                    for state, is_possible in pairs(wfc.grid[ny][nx]) do
                        if is_possible and not allowed_for_neighbor[state] then
                            wfc.grid[ny][nx][state] = false
                            changed = true
                        end
                    end
                    
                    if changed then
                        local new_entropy = 0
                        for _, is_possible in pairs(wfc.grid[ny][nx]) do
                            if is_possible then new_entropy = new_entropy + 1 end
                        end
                        wfc.entropy_grid[ny][nx] = new_entropy
                        table.insert(stack, {x=nx, y=ny})
                    end
                end
            end
        end
    end
end

-- Returns the final grid of collapsed state IDs
function WFC.getResult(wfc)
    local result = {}
    for y = 1, wfc.height do
        result[y] = {}
        for x = 1, wfc.width do
            local possibilities = {}
            for state, is_possible in pairs(wfc.grid[y][x]) do
                if is_possible then table.insert(possibilities, state) end
            end
            if #possibilities == 1 then
                result[y][x] = possibilities[1]
            else
                result[y][x] = nil -- Unsolved or contradiction
            end
        end
    end
    return result
end

return WFC