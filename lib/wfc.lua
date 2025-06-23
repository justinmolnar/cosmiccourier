-- lib/wfc.lua
-- Complete Wave Function Collapse implementation
-- This is a full replacement of the corrupted WFC solver

local WFC = {}

-- Create a new WFC instance
function WFC.new(width, height, states, constraints)
    local instance = {
        width = width,
        height = height,
        states = states or {"A", "B", "C"},
        constraints = constraints or {},
        
        -- Grid of possible states for each cell
        -- Each cell contains a table of possible states
        possibilities = {},
        
        -- Grid of final collapsed states
        collapsed = {},
        
        -- Track which cells have been collapsed
        is_collapsed = {},
        
        -- Constraint rules - which states can be adjacent
        adjacency_rules = {},
        
        -- Random seed for consistent results during debugging
        seed = nil
    }
    
    -- Initialize the grids
    WFC._initializeGrids(instance)
    
    -- Set up default adjacency rules if none provided
    if not constraints or #constraints == 0 then
        WFC._createDefaultConstraints(instance)
    else
        instance.adjacency_rules = constraints
    end
    
    return instance
end

-- Initialize all grids to their starting state
function WFC._initializeGrids(wfc)
    for y = 1, wfc.height do
        wfc.possibilities[y] = {}
        wfc.collapsed[y] = {}
        wfc.is_collapsed[y] = {}
        
        for x = 1, wfc.width do
            -- Start with all states possible
            wfc.possibilities[y][x] = {}
            for _, state in ipairs(wfc.states) do
                wfc.possibilities[y][x][state] = true
            end
            
            wfc.collapsed[y][x] = nil
            wfc.is_collapsed[y][x] = false
        end
    end
end

-- Create default constraints where any state can be adjacent to any other
function WFC._createDefaultConstraints(wfc)
    wfc.adjacency_rules = {}
    for _, state in ipairs(wfc.states) do
        wfc.adjacency_rules[state] = {}
        for _, other_state in ipairs(wfc.states) do
            wfc.adjacency_rules[state][other_state] = true
        end
    end
end

-- Set a constraint that stateA can be adjacent to stateB
function WFC.addConstraint(wfc, stateA, stateB, bidirectional)
    if not wfc.adjacency_rules[stateA] then
        wfc.adjacency_rules[stateA] = {}
    end
    wfc.adjacency_rules[stateA][stateB] = true
    
    if bidirectional ~= false then
        if not wfc.adjacency_rules[stateB] then
            wfc.adjacency_rules[stateB] = {}
        end
        wfc.adjacency_rules[stateB][stateA] = true
    end
end

-- Set specific constraints for zone generation
function WFC.setZoneConstraints(wfc)
    -- Clear existing rules
    wfc.adjacency_rules = {}
    
    -- Downtown can be adjacent to commercial and itself
    WFC.addConstraint(wfc, "downtown", "downtown", true)
    WFC.addConstraint(wfc, "downtown", "commercial", true)
    
    -- Commercial can be adjacent to downtown, itself, and residential
    WFC.addConstraint(wfc, "commercial", "commercial", true)
    WFC.addConstraint(wfc, "commercial", "residential", true)
    
    -- Residential can be adjacent to commercial, itself, and park
    WFC.addConstraint(wfc, "residential", "residential", true)
    WFC.addConstraint(wfc, "residential", "park", true)
    
    -- Industrial can be adjacent to itself and commercial (but not residential)
    WFC.addConstraint(wfc, "industrial", "industrial", true)
    WFC.addConstraint(wfc, "industrial", "commercial", true)
    
    -- Parks can be adjacent to residential and other parks
    WFC.addConstraint(wfc, "park", "park", true)
end

-- Force a cell to a specific state (useful for initial constraints)
function WFC.collapse(wfc, x, y, state)
    if not WFC._inBounds(wfc, x, y) then
        return false
    end
    
    -- Set this cell to the specific state
    wfc.collapsed[y][x] = state
    wfc.is_collapsed[y][x] = true
    
    -- Clear all possibilities except the chosen state
    wfc.possibilities[y][x] = {}
    wfc.possibilities[y][x][state] = true
    
    -- Propagate constraints to neighbors
    WFC._propagateFrom(wfc, x, y)
    
    return true
end

-- Get the entropy (number of possible states) for a cell
function WFC._getEntropy(wfc, x, y)
    if not WFC._inBounds(wfc, x, y) or wfc.is_collapsed[y][x] then
        return 0
    end
    
    local count = 0
    for state, possible in pairs(wfc.possibilities[y][x]) do
        if possible then
            count = count + 1
        end
    end
    return count
end

-- Find the cell with the lowest entropy (most constrained)
function WFC._findLowestEntropyCell(wfc)
    local min_entropy = math.huge
    local candidates = {}
    
    for y = 1, wfc.height do
        for x = 1, wfc.width do
            if not wfc.is_collapsed[y][x] then
                local entropy = WFC._getEntropy(wfc, x, y)
                
                if entropy == 0 then
                    -- Contradiction found - no valid states possible
                    return nil, nil, 0
                elseif entropy < min_entropy then
                    min_entropy = entropy
                    candidates = {{x = x, y = y}}
                elseif entropy == min_entropy then
                    table.insert(candidates, {x = x, y = y})
                end
            end
        end
    end
    
    if #candidates == 0 then
        return nil, nil, -1 -- All cells collapsed
    end
    
    -- Randomly choose among cells with equal entropy
    local chosen = candidates[love.math.random(1, #candidates)]
    return chosen.x, chosen.y, min_entropy
end

-- Choose a random valid state for a cell
function WFC._chooseRandomState(wfc, x, y)
    local valid_states = {}
    
    for state, possible in pairs(wfc.possibilities[y][x]) do
        if possible then
            table.insert(valid_states, state)
        end
    end
    
    if #valid_states == 0 then
        return nil
    end
    
    return valid_states[love.math.random(1, #valid_states)]
end

-- Check if coordinates are within bounds
function WFC._inBounds(wfc, x, y)
    return x >= 1 and x <= wfc.width and y >= 1 and y <= wfc.height
end

-- Get the neighbors of a cell
function WFC._getNeighbors(wfc, x, y)
    local neighbors = {}
    local directions = {{0, -1}, {1, 0}, {0, 1}, {-1, 0}} -- up, right, down, left
    
    for _, dir in ipairs(directions) do
        local nx, ny = x + dir[1], y + dir[2]
        if WFC._inBounds(wfc, nx, ny) then
            table.insert(neighbors, {x = nx, y = ny})
        end
    end
    
    return neighbors
end

-- Propagate constraints from a cell to its neighbors
function WFC._propagateFrom(wfc, x, y)
    local changed_cells = {}
    local to_process = {{x = x, y = y}}
    
    while #to_process > 0 do
        local current = table.remove(to_process, 1)
        local cx, cy = current.x, current.y
        
        -- Skip if already processed in this wave
        local key = cx .. "," .. cy
        if changed_cells[key] then
            goto continue
        end
        changed_cells[key] = true
        
        local neighbors = WFC._getNeighbors(wfc, cx, cy)
        
        for _, neighbor in ipairs(neighbors) do
            local nx, ny = neighbor.x, neighbor.y
            
            if not wfc.is_collapsed[ny][nx] then
                local original_possibilities = {}
                for state, possible in pairs(wfc.possibilities[ny][nx]) do
                    original_possibilities[state] = possible
                end
                
                -- Update this neighbor's possibilities based on current cell
                WFC._updateCellConstraints(wfc, nx, ny)
                
                -- Check if possibilities changed
                local changed = false
                for state, possible in pairs(wfc.possibilities[ny][nx]) do
                    if original_possibilities[state] ~= possible then
                        changed = true
                        break
                    end
                end
                
                -- If this neighbor changed, add it to the processing queue
                if changed then
                    table.insert(to_process, {x = nx, y = ny})
                end
            end
        end
        
        ::continue::
    end
end

-- Update a cell's possibilities based on its neighbors
function WFC._updateCellConstraints(wfc, x, y)
    if wfc.is_collapsed[y][x] then
        return
    end
    
    local neighbors = WFC._getNeighbors(wfc, x, y)
    local new_possibilities = {}
    
    -- For each possible state of this cell
    for state, _ in pairs(wfc.possibilities[y][x]) do
        if wfc.possibilities[y][x][state] then
            local state_valid = true
            
            -- Check if this state is compatible with all neighbors
            for _, neighbor in ipairs(neighbors) do
                local nx, ny = neighbor.x, neighbor.y
                
                if wfc.is_collapsed[ny][nx] then
                    -- Neighbor is collapsed to a specific state
                    local neighbor_state = wfc.collapsed[ny][nx]
                    if not WFC._statesCompatible(wfc, state, neighbor_state) then
                        state_valid = false
                        break
                    end
                else
                    -- Neighbor has multiple possibilities
                    -- Check if our state is compatible with at least one neighbor possibility
                    local compatible_with_neighbor = false
                    for neighbor_state, neighbor_possible in pairs(wfc.possibilities[ny][nx]) do
                        if neighbor_possible and WFC._statesCompatible(wfc, state, neighbor_state) then
                            compatible_with_neighbor = true
                            break
                        end
                    end
                    
                    if not compatible_with_neighbor then
                        state_valid = false
                        break
                    end
                end
            end
            
            new_possibilities[state] = state_valid
        else
            new_possibilities[state] = false
        end
    end
    
    wfc.possibilities[y][x] = new_possibilities
end

-- Check if two states can be adjacent
function WFC._statesCompatible(wfc, stateA, stateB)
    if not wfc.adjacency_rules[stateA] then
        return false
    end
    return wfc.adjacency_rules[stateA][stateB] == true
end

-- Main solve function
function WFC.solve(wfc)
    local iterations = 0
    local max_iterations = wfc.width * wfc.height * 10
    
    while iterations < max_iterations do
        iterations = iterations + 1
        
        -- Find cell with lowest entropy
        local x, y, entropy = WFC._findLowestEntropyCell(wfc)
        
        if entropy == -1 then
            -- All cells are collapsed - success!
            print("WFC: Successfully completed in " .. iterations .. " iterations")
            return true
        elseif entropy == 0 then
            -- Contradiction - failure
            print("WFC: Contradiction found at iteration " .. iterations)
            return false
        end
        
        -- Choose a random state for this cell
        local chosen_state = WFC._chooseRandomState(wfc, x, y)
        if not chosen_state then
            print("WFC: No valid state found for cell (" .. x .. ", " .. y .. ")")
            return false
        end
        
        -- Collapse the cell
        wfc.collapsed[y][x] = chosen_state
        wfc.is_collapsed[y][x] = true
        wfc.possibilities[y][x] = {}
        wfc.possibilities[y][x][chosen_state] = true
        
        -- Propagate constraints
        WFC._propagateFrom(wfc, x, y)
        
        -- Check for contradictions after propagation
        local contradiction = false
        for check_y = 1, wfc.height do
            for check_x = 1, wfc.width do
                if not wfc.is_collapsed[check_y][check_x] and WFC._getEntropy(wfc, check_x, check_y) == 0 then
                    contradiction = true
                    break
                end
            end
            if contradiction then break end
        end
        
        if contradiction then
            print("WFC: Contradiction after propagation at iteration " .. iterations)
            return false
        end
    end
    
    print("WFC: Reached maximum iterations (" .. max_iterations .. ")")
    return false
end

-- Get the final result grid
function WFC.getResult(wfc)
    local result = {}
    for y = 1, wfc.height do
        result[y] = {}
        for x = 1, wfc.width do
            result[y][x] = wfc.collapsed[y][x] or "unknown"
        end
    end
    return result
end

-- Debug function to print current state
function WFC.debugPrint(wfc)
    print("WFC Grid State:")
    for y = 1, wfc.height do
        local row = ""
        for x = 1, wfc.width do
            if wfc.is_collapsed[y][x] then
                local state = wfc.collapsed[y][x]
                row = row .. (state and string.sub(state, 1, 1) or "?") .. " "
            else
                local entropy = WFC._getEntropy(wfc, x, y)
                row = row .. entropy .. " "
            end
        end
        print(row)
    end
end

return WFC