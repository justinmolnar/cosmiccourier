-- services/WFCZoningService.lua
-- Two-pass WFC system for coherent city zoning

local WFCZoningService = {}

-- Zone definitions - EXPANDED with more distinct zones
local ZONES = {
    commercial = { color = {0, 0, 1}, weight = 4 },
    residential_north = { color = {0, 1, 0}, weight = 4 },
    residential_south = { color = {0, 0.7, 0}, weight = 4 }, 
    industrial_heavy = { color = {1, 0, 0}, weight = 4 },
    industrial_light = { color = {0.8, 0.2, 0.2}, weight = 4 },
    university = { color = {0.6, 0, 0.8}, weight = 3 },
    medical = { color = {1, 0.5, 0.8}, weight = 3 },
    entertainment = { color = {1, 0.5, 0}, weight = 3 },
    waterfront = { color = {0, 0.8, 0.8}, weight = 3 },
    warehouse = { color = {0.5, 0.3, 0.1}, weight = 3 },
    tech = { color = {0.3, 0.3, 0.8}, weight = 3 },
    park_central = { color = {0.2, 0.8, 0.3}, weight = 2 },
    park_nature = { color = {0.1, 0.6, 0.1}, weight = 2 }
}

-- Zone clustering constraints - EXPANDED
local ZONE_CONSTRAINTS = {
    commercial = { min_cluster = 12, cluster_weight = 8 },
    residential_north = { min_cluster = 20, cluster_weight = 10 },
    residential_south = { min_cluster = 18, cluster_weight = 9 },
    industrial_heavy = { min_cluster = 15, cluster_weight = 8 },
    industrial_light = { min_cluster = 12, cluster_weight = 7 },
    university = { min_cluster = 16, cluster_weight = 9 },
    medical = { min_cluster = 10, cluster_weight = 7 },
    entertainment = { min_cluster = 8, cluster_weight = 6 },
    waterfront = { min_cluster = 12, cluster_weight = 8 },
    warehouse = { min_cluster = 14, cluster_weight = 8 },
    tech = { min_cluster = 10, cluster_weight = 7 },
    park_central = { min_cluster = 8, cluster_weight = 6 },
    park_nature = { min_cluster = 10, cluster_weight = 7 }
}

-- Adjacency compatibility - EXPANDED (different zone types don't like each other)
local ADJACENCY = {
    commercial = { commercial = 5, entertainment = 4, tech = 3, medical = 2 },
    residential_north = { residential_north = 5, park_central = 4, medical = 3, university = 2 },
    residential_south = { residential_south = 5, park_nature = 4, entertainment = 3, waterfront = 2 },
    industrial_heavy = { industrial_heavy = 5, warehouse = 4, waterfront = 3 },
    industrial_light = { industrial_light = 5, tech = 4, warehouse = 3, commercial = 2 },
    university = { university = 5, residential_north = 3, park_central = 4, tech = 3 },
    medical = { medical = 5, residential_north = 3, commercial = 2, park_central = 3 },
    entertainment = { entertainment = 5, commercial = 4, residential_south = 3 },
    waterfront = { waterfront = 5, industrial_heavy = 3, park_nature = 4 },
    warehouse = { warehouse = 5, industrial_heavy = 4, industrial_light = 3 },
    tech = { tech = 5, university = 3, industrial_light = 4, commercial = 3 },
    park_central = { park_central = 5, residential_north = 4, university = 4, medical = 3 },
    park_nature = { park_nature = 5, residential_south = 4, waterfront = 4 }
}

function WFCZoningService.generateCoherentZones(width, height, downtown_center_x, downtown_center_y, params)
    params = params or {}
    print("WFC: Starting two-pass coherent zone generation")
    
    -- DEBUG: Check if this function is accidentally modifying a city_grid instead of zone_grid
    print("WFC DEBUG: This function should ONLY create zone_grid, NOT modify city_grid!")
    
    local coarse_width = math.max(4, math.floor(width / 4))
    local coarse_height = math.max(4, math.floor(height / 4))
    local coarse_downtown_x = math.max(1, math.min(coarse_width, math.floor(downtown_center_x / 4)))
    local coarse_downtown_y = math.max(1, math.min(coarse_height, math.floor(downtown_center_y / 4)))
    
    print("WFC: Pass 1 - Coarse grid:", coarse_width .. "x" .. coarse_height)
    local coarse_grid = WFCZoningService._generateCoarseZones(coarse_width, coarse_height, coarse_downtown_x, coarse_downtown_y)
    
    print("WFC: Pass 2 - Fine grid:", width .. "x" .. height)
    local fine_grid = WFCZoningService._generateConstrainedFineGrid(width, height, coarse_grid)
    
    print("WFC: Pass 3 - Stamping downtown square")
    local downtown_w = params.downtown_width or 64
    local downtown_h = params.downtown_height or 64
    WFCZoningService._stampDowntownSquare(fine_grid, width, height, downtown_center_x, downtown_center_y, downtown_w, downtown_h)
    
    print("WFC DEBUG: Returning zone_grid, should NOT affect city_grid!")
    return fine_grid
end

function WFCZoningService._generateCoarseZones(width, height, downtown_x, downtown_y)
    local grid = {}
    
    -- Initialize empty grid
    for y = 1, height do
        grid[y] = {}
        for x = 1, width do
            grid[y][x] = nil
        end
    end
    
    -- GUARANTEED DISTRICT PLACEMENT: Force minimum sizes
    WFCZoningService._placeGuaranteedDistricts(grid, width, height, downtown_x, downtown_y)
    
    -- THE FIX: Define seed categories with specific zone types
    local SEED_CATEGORIES = {
        residential = {"residential_north", "residential_south"},
        commercial = {"commercial", "entertainment", "tech"},
        industrial = {"industrial_heavy", "industrial_light", "warehouse"},
        park = {"park_central", "park_nature"}
    }
    
    local zone_seeds = {
        { category = "residential", count = math.max(2, math.floor(width * height / 25)) },
        { category = "commercial", count = math.max(2, math.floor(width * height / 35)) },
        { category = "industrial", count = math.max(1, math.floor(width * height / 45)) },
        { category = "park", count = math.max(2, math.floor(width * height / 30)) }
    }
    
    for _, seed_info in ipairs(zone_seeds) do
        local placed = 0
        local attempts = 0
        
        while placed < seed_info.count and attempts < 100 do
            local x = love.math.random(1, width)
            local y = love.math.random(1, height)
            
            -- RANDOMLY select a specific zone from the category
            local possible_zones = SEED_CATEGORIES[seed_info.category]
            local specific_zone_to_place = possible_zones[love.math.random(1, #possible_zones)]

            if not grid[y][x] and WFCZoningService._isValidSeedLocation(grid, x, y, specific_zone_to_place, width, height) then
                grid[y][x] = specific_zone_to_place
                placed = placed + 1
                print("WFC: Placed", specific_zone_to_place, "seed at", x, y)
            end
            attempts = attempts + 1
        end
    end
    
    -- FIXED: Grow seeds into blobs before filling remaining cells
    WFCZoningService._growSeedsIntoBlobs(grid, width, height, 2) -- Reduced from 3 to 2 iterations to prevent overgrowth
    
    -- Fill remaining cells using neighbor-biased selection
    local max_iterations = width * height * 2
    local iteration = 0
    local changed = true
    
    while changed and iteration < max_iterations do
        changed = false
        iteration = iteration + 1
        
        for y = 1, height do
            for x = 1, width do
                if not grid[y][x] then
                    local zone = WFCZoningService._getBestZoneForCell(grid, x, y, width, height)
                    if zone then
                        grid[y][x] = zone
                        changed = true
                    end
                end
            end
        end
    end
    
    -- Fill any remaining empty cells with parks (FALLBACK TO PARKS)
    local fallback_zones = {"park_central", "park_nature"}
    for y = 1, height do
        for x = 1, width do
            if not grid[y][x] then
                grid[y][x] = fallback_zones[love.math.random(1, #fallback_zones)]
            elseif grid[y][x] == "RESERVED" then
                grid[y][x] = nil -- Clear reserved markers, they'll be filled by downtown stamp
            end
        end
    end
    
    -- CLEANUP: Remove isolated single cells (more aggressive - 3 passes)
    WFCZoningService._cleanupIsolatedCells(grid, width, height, 5) -- Increased from 2 to 5 passes
    
    print("WFC: Coarse grid completed in", iteration, "iterations")
    return grid
end

-- NEW: Reserve downtown area so WFC never touches it
function WFCZoningService._reserveDowntownArea(grid, width, height, center_x, center_y)
    local half_side = 7 -- 15x15 square
    
    for dy = -half_side, half_side do
        for dx = -half_side, half_side do
            local x, y = center_x + dx, center_y + dy
            if x >= 1 and x <= width and y >= 1 and y <= height then
                grid[y][x] = "RESERVED" -- Special marker that WFC will skip
            end
        end
    end
    
    print("WFC: Reserved 15x15 downtown area - WFC will NOT touch these cells")
end
-- NEW: Place guaranteed minimum-sized districts first (SMALLER PARKS)
function WFCZoningService._placeGuaranteedDistricts(grid, width, height, downtown_x, downtown_y)
    -- FIXED: Much smaller park sizes to prevent mega-parks
    local district_requirements = {
        {zone = "industrial_heavy", min_size = 15, max_size = 25, center_x = nil, center_y = nil},
        {zone = "industrial_light", min_size = 12, max_size = 20, center_x = nil, center_y = nil},
        {zone = "residential_north", min_size = 18, max_size = 28, center_x = nil, center_y = nil},
        {zone = "residential_south", min_size = 16, max_size = 26, center_x = nil, center_y = nil},
        {zone = "commercial", min_size = 12, max_size = 22, center_x = nil, center_y = nil},
        {zone = "university", min_size = 14, max_size = 24, center_x = nil, center_y = nil},
        {zone = "tech", min_size = 10, max_size = 18, center_x = nil, center_y = nil},
        {zone = "medical", min_size = 8, max_size = 16, center_x = nil, center_y = nil},
        {zone = "entertainment", min_size = 8, max_size = 15, center_x = nil, center_y = nil},
        {zone = "warehouse", min_size = 12, max_size = 20, center_x = nil, center_y = nil},
        {zone = "waterfront", min_size = 10, max_size = 18, center_x = nil, center_y = nil},
        {zone = "park_central", min_size = 6, max_size = 10, center_x = nil, center_y = nil}, -- MUCH SMALLER
        {zone = "park_nature", min_size = 8, max_size = 12, center_x = nil, center_y = nil}   -- MUCH SMALLER
    }
    
    for _, req in ipairs(district_requirements) do
        -- All districts use strategic placement (no downtown special case)
        local center_x, center_y = WFCZoningService._findBestDistrictLocation(grid, width, height, req.zone, req.min_size, downtown_x, downtown_y)
        
        if center_x and center_y then
            WFCZoningService._carveDistrict(grid, width, height, center_x, center_y, req.min_size, req.max_size, req.zone)
            print("WFC: Placed guaranteed", req.zone, "district at", center_x, center_y, "size", req.min_size, "-", req.max_size)
        else
            print("WFC: WARNING - Could not place guaranteed", req.zone, "district")
        end
    end
end

-- NEW: Strategic district placement instead of random (EXPANDED FOR ALL ZONES)
function WFCZoningService._findBestDistrictLocation(grid, width, height, zone_type, target_size, downtown_x, downtown_y)
    local best_x, best_y = nil, nil
    local best_score = -1
    
    -- Try multiple strategic locations based on zone type
    local candidate_locations = {}
    
    if zone_type == "industrial_heavy" or zone_type == "industrial_light" or zone_type == "warehouse" then
        -- Industrial/warehouse prefers edges/corners
        table.insert(candidate_locations, {x = math.floor(width * 0.15), y = math.floor(height * 0.15)})
        table.insert(candidate_locations, {x = math.floor(width * 0.85), y = math.floor(height * 0.15)})
        table.insert(candidate_locations, {x = math.floor(width * 0.15), y = math.floor(height * 0.85)})
        table.insert(candidate_locations, {x = math.floor(width * 0.85), y = math.floor(height * 0.85)})
        table.insert(candidate_locations, {x = math.floor(width * 0.05), y = math.floor(height * 0.5)})
        table.insert(candidate_locations, {x = math.floor(width * 0.95), y = math.floor(height * 0.5)})
    elseif zone_type == "commercial" or zone_type == "entertainment" or zone_type == "tech" then
        -- Commercial/entertainment/tech prefers mid-range areas
        table.insert(candidate_locations, {x = math.floor(width * 0.25), y = downtown_y})
        table.insert(candidate_locations, {x = math.floor(width * 0.75), y = downtown_y})
        table.insert(candidate_locations, {x = downtown_x, y = math.floor(height * 0.25)})
        table.insert(candidate_locations, {x = downtown_x, y = math.floor(height * 0.75)})
        table.insert(candidate_locations, {x = math.floor(width * 0.3), y = math.floor(height * 0.3)})
        table.insert(candidate_locations, {x = math.floor(width * 0.7), y = math.floor(height * 0.7)})
    elseif zone_type == "residential_north" or zone_type == "residential_south" then
        -- Residential areas spread around
        table.insert(candidate_locations, {x = math.floor(width * 0.2), y = math.floor(height * 0.6)})
        table.insert(candidate_locations, {x = math.floor(width * 0.8), y = math.floor(height * 0.4)})
        table.insert(candidate_locations, {x = math.floor(width * 0.4), y = math.floor(height * 0.2)})
        table.insert(candidate_locations, {x = math.floor(width * 0.6), y = math.floor(height * 0.8)})
        table.insert(candidate_locations, {x = math.floor(width * 0.3), y = math.floor(height * 0.7)})
        table.insert(candidate_locations, {x = math.floor(width * 0.7), y = math.floor(height * 0.3)})
    elseif zone_type == "university" or zone_type == "medical" then
        -- University/medical prefer quieter areas
        table.insert(candidate_locations, {x = math.floor(width * 0.2), y = math.floor(height * 0.3)})
        table.insert(candidate_locations, {x = math.floor(width * 0.8), y = math.floor(height * 0.7)})
        table.insert(candidate_locations, {x = math.floor(width * 0.3), y = math.floor(height * 0.8)})
        table.insert(candidate_locations, {x = math.floor(width * 0.7), y = math.floor(height * 0.2)})
    elseif zone_type == "waterfront" then
        -- Waterfront prefers edges
        table.insert(candidate_locations, {x = math.floor(width * 0.1), y = math.floor(height * 0.3)})
        table.insert(candidate_locations, {x = math.floor(width * 0.9), y = math.floor(height * 0.7)})
        table.insert(candidate_locations, {x = math.floor(width * 0.3), y = math.floor(height * 0.1)})
        table.insert(candidate_locations, {x = math.floor(width * 0.7), y = math.floor(height * 0.9)})
    else
        -- Parks and other zones - spread around
        table.insert(candidate_locations, {x = math.floor(width * 0.3), y = math.floor(height * 0.7)})
        table.insert(candidate_locations, {x = math.floor(width * 0.7), y = math.floor(height * 0.3)})
        table.insert(candidate_locations, {x = math.floor(width * 0.2), y = math.floor(height * 0.3)})
        table.insert(candidate_locations, {x = math.floor(width * 0.8), y = math.floor(height * 0.7)})
    end
    
    -- Evaluate each candidate location
    for _, loc in ipairs(candidate_locations) do
        if WFCZoningService._canPlaceDistrictAt(grid, width, height, loc.x, loc.y, target_size) then
            local score = WFCZoningService._scoreDistrictLocation(grid, width, height, loc.x, loc.y, zone_type, downtown_x, downtown_y)
            if score > best_score then
                best_score = score
                best_x, best_y = loc.x, loc.y
            end
        end
    end
    
    return best_x, best_y
end

-- NEW: Score potential district locations (UPDATED FOR ALL ZONES)
function WFCZoningService._scoreDistrictLocation(grid, width, height, x, y, zone_type, downtown_x, downtown_y)
    local score = 0
    
    -- Distance from downtown
    local downtown_dist = math.sqrt((x - downtown_x)^2 + (y - downtown_y)^2)
    
    if zone_type == "industrial_heavy" or zone_type == "industrial_light" or zone_type == "warehouse" then
        -- Industrial wants to be far from downtown
        score = score + downtown_dist
        -- And prefers corners/edges
        local edge_dist = math.min(x, width - x, y, height - y)
        score = score + (10 - edge_dist) -- Closer to edge = higher score
    elseif zone_type == "commercial" or zone_type == "entertainment" or zone_type == "tech" then
        -- Commercial/entertainment/tech wants to be medium distance from downtown
        local ideal_dist = math.min(width, height) * 0.3
        score = score + (ideal_dist - math.abs(downtown_dist - ideal_dist))
    elseif zone_type == "residential_north" or zone_type == "residential_south" then
        -- Residential prefers medium distance
        local ideal_dist = math.min(width, height) * 0.4
        score = score + (ideal_dist - math.abs(downtown_dist - ideal_dist))
    elseif zone_type == "university" or zone_type == "medical" then
        -- University/medical prefers quieter areas (not too close, not too far)
        local ideal_dist = math.min(width, height) * 0.5
        score = score + (ideal_dist - math.abs(downtown_dist - ideal_dist))
    elseif zone_type == "waterfront" then
        -- Waterfront prefers edges
        local edge_dist = math.min(x, width - x, y, height - y)
        score = score + (8 - edge_dist)
    else
        -- Parks and other zones - neutral scoring
        score = score + 5
    end
    
    return score
end

-- NEW: Check if we can place a district of given size at location (SKIP RESERVED)
function WFCZoningService._canPlaceDistrictAt(grid, width, height, center_x, center_y, target_size)
    local radius = math.ceil(math.sqrt(target_size / math.pi))
    local conflicts = 0
    
    for dy = -radius, radius do
        for dx = -radius, radius do
            local x, y = center_x + dx, center_y + dy
            if x >= 1 and x <= width and y >= 1 and y <= height then
                if grid[y][x] and grid[y][x] ~= "RESERVED" then
                    conflicts = conflicts + 1
                elseif grid[y][x] == "RESERVED" then
                    conflicts = conflicts + 10 -- Heavy penalty for reserved areas
                end
            end
        end
    end
    
    -- Allow if less than 25% conflicts
    local total_checked = (radius * 2 + 1) * (radius * 2 + 1)
    return conflicts < (total_checked * 0.25)
end

-- FIXED: Carve out a square district (for downtown) - don't allow growing
function WFCZoningService._carveSquareDistrict(grid, width, height, center_x, center_y, target_size, zone_type)
    -- Calculate square dimensions - force it to be exactly target_size
    local side_length = math.floor(math.sqrt(target_size))
    local half_side = math.floor(side_length / 2)
    
    local placed_cells = {}
    
    -- Place exact square centered on the given point - NO GROWING
    for dy = -half_side, half_side do
        for dx = -half_side, half_side do
            local x, y = center_x + dx, center_y + dy
            if x >= 1 and x <= width and y >= 1 and y <= height then
                grid[y][x] = zone_type
                table.insert(placed_cells, {x = x, y = y})
            end
        end
    end
    
    print("WFC: Carved EXACT square", zone_type, "district with", #placed_cells, "cells (", side_length .. "x" .. side_length, ")")
end

-- UPDATED: Carve out a district with size limits (SKIP RESERVED CELLS)
function WFCZoningService._carveDistrict(grid, width, height, center_x, center_y, min_size, max_size, zone_type)
    local placed_cells = {}
    
    -- Start with center cell (if not reserved)
    if center_x >= 1 and center_x <= width and center_y >= 1 and center_y <= height and grid[center_y][center_x] ~= "RESERVED" then
        grid[center_y][center_x] = zone_type
        table.insert(placed_cells, {x = center_x, y = center_y})
    end
    
    -- Grow outward until we reach target size (but respect max size and skip reserved)
    local target_size = min_size + love.math.random(0, max_size - min_size)
    local growth_queue = {{x = center_x, y = center_y}}
    local directions = {{0,1}, {0,-1}, {1,0}, {-1,0}, {1,1}, {1,-1}, {-1,1}, {-1,-1}}
    
    while #placed_cells < target_size and #growth_queue > 0 do
        -- Pick a random cell from growth queue to grow from
        local queue_idx = love.math.random(1, #growth_queue)
        local current = growth_queue[queue_idx]
        table.remove(growth_queue, queue_idx)
        
        -- Try to place adjacent cells (skip reserved)
        local adjacent_positions = {}
        for _, dir in ipairs(directions) do
            local nx, ny = current.x + dir[1], current.y + dir[2]
            if nx >= 1 and nx <= width and ny >= 1 and ny <= height and not grid[ny][nx] then
                table.insert(adjacent_positions, {x = nx, y = ny})
            end
        end
        
        -- Place some adjacent cells
        for _, pos in ipairs(adjacent_positions) do
            if #placed_cells >= target_size then break end
            
            grid[pos.y][pos.x] = zone_type
            table.insert(placed_cells, pos)
            table.insert(growth_queue, pos)
        end
    end
    
    print("WFC: Carved", zone_type, "district with", #placed_cells, "cells (target:", target_size .. ")")
end
function WFCZoningService._growSeedsIntoBlobs(grid, width, height, iterations)
    for iter = 1, iterations do
        local growth_candidates = {}
        
        -- Find all empty cells adjacent to existing zones
        for y = 1, height do
            for x = 1, width do
                if not grid[y][x] then
                    local adjacent_zones = WFCZoningService._getAdjacentZones(grid, x, y, width, height)
                    if #adjacent_zones > 0 then
                        -- Pick the most common adjacent zone (creates blob growth)
                        local zone_counts = {}
                        for _, zone in ipairs(adjacent_zones) do
                            zone_counts[zone] = (zone_counts[zone] or 0) + 1
                        end
                        
                        local best_zone = nil
                        local best_count = 0
                        for zone, count in pairs(zone_counts) do
                            if count > best_count then
                                best_count = count
                                best_zone = zone
                            end
                        end
                        
                        if best_zone and best_count >= 2 then -- Only grow if strongly supported
                            table.insert(growth_candidates, {x = x, y = y, zone = best_zone})
                        end
                    end
                end
            end
        end
        
        -- Apply growth
        for _, candidate in ipairs(growth_candidates) do
            if not grid[candidate.y][candidate.x] then -- Double-check it's still empty
                grid[candidate.y][candidate.x] = candidate.zone
            end
        end
        
        print("WFC: Growth iteration", iter, "- grew", #growth_candidates, "cells")
    end
end

-- FIXED: Clean up isolated single cells more aggressively
function WFCZoningService._cleanupIsolatedCells(grid, width, height, passes)
    for pass = 1, passes do
        local changes_made = 0
        
        for y = 1, height do
            for x = 1, width do
                local current_zone = grid[y][x]
                
                -- Check all 4 cardinal directions
                local neighbors = {}
                local directions = {{0,-1}, {1,0}, {0,1}, {-1,0}} -- up, right, down, left
                
                for _, dir in ipairs(directions) do
                    local nx, ny = x + dir[1], y + dir[2]
                    if nx >= 1 and nx <= width and ny >= 1 and ny <= height then
                        table.insert(neighbors, grid[ny][nx])
                    end
                end
                
                -- If this cell is different from ALL its neighbors, it's isolated
                if #neighbors > 0 then
                    local matches_any_neighbor = false
                    for _, neighbor_zone in ipairs(neighbors) do
                        if neighbor_zone == current_zone then
                            matches_any_neighbor = true
                            break
                        end
                    end
                    
                    if not matches_any_neighbor then
                        -- This cell is isolated, change it to the most common neighbor
                        local zone_counts = {}
                        for _, zone in ipairs(neighbors) do
                            zone_counts[zone] = (zone_counts[zone] or 0) + 1
                        end
                        
                        local best_zone = current_zone
                        local best_count = 0
                        for zone, count in pairs(zone_counts) do
                            if count > best_count then
                                best_count = count
                                best_zone = zone
                            end
                        end
                        
                        if best_zone ~= current_zone then
                            grid[y][x] = best_zone
                            changes_made = changes_made + 1
                        end
                    end
                end
            end
        end
        
        print("WFC: Cleanup pass", pass, "- fixed", changes_made, "isolated cells")
        if changes_made == 0 then break end -- No more isolated cells
    end
end
function WFCZoningService._getAdjacentZones(grid, x, y, width, height)
    local zones = {}
    local directions = {{0,1}, {0,-1}, {1,0}, {-1,0}}
    
    for _, dir in ipairs(directions) do
        local nx, ny = x + dir[1], y + dir[2]
        if nx >= 1 and nx <= width and ny >= 1 and ny <= height then
            if grid[ny] and grid[ny][nx] then
                table.insert(zones, grid[ny][nx])
            end
        end
    end
    
    return zones
end

function WFCZoningService._isValidSeedLocation(grid, x, y, zone, width, height)
    -- Don't place too close to downtown
    local min_distance_from_downtown = 2
    
    for dy = -min_distance_from_downtown, min_distance_from_downtown do
        for dx = -min_distance_from_downtown, min_distance_from_downtown do
            local nx, ny = x + dx, y + dy
            if nx >= 1 and nx <= width and ny >= 1 and ny <= height then
                if grid[ny] and grid[ny][nx] == "downtown" then
                    return false
                end
            end
        end
    end
    
    -- Don't place too close to same zone type
    for dy = -1, 1 do
        for dx = -1, 1 do
            local nx, ny = x + dx, y + dy
            if nx >= 1 and nx <= width and ny >= 1 and ny <= height then
                if grid[ny] and grid[ny][nx] == zone then
                    return false
                end
            end
        end
    end
    
    return true
end

function WFCZoningService._getBestZoneForCell(grid, x, y, width, height)
    local zone_weights = {}
    
    -- FIXED: Start with much lower base weights so neighbors dominate
    for zone_name, zone_data in pairs(ZONES) do
        zone_weights[zone_name] = zone_data.weight * 0.1 -- Reduced base influence
    end
    
    -- MASSIVELY boost weights based on neighbors (this creates clustering)
    local directions = {{0,1}, {0,-1}, {1,0}, {-1,0}, {1,1}, {1,-1}, {-1,1}, {-1,-1}}
    
    for _, dir in ipairs(directions) do
        local nx, ny = x + dir[1], y + dir[2]
        if nx >= 1 and nx <= width and ny >= 1 and ny <= height then
            if grid[ny] and grid[ny][nx] and grid[ny][nx] ~= "RESERVED" then
                local neighbor_zone = grid[ny][nx]
                
                -- SAFETY CHECK: Only process if neighbor_zone exists in our ADJACENCY table
                if ADJACENCY[neighbor_zone] then
                    -- Use adjacency rules to determine compatibility
                    for zone_name, _ in pairs(zone_weights) do
                        local compatibility = ADJACENCY[neighbor_zone][zone_name] or 1
                        zone_weights[zone_name] = zone_weights[zone_name] + (compatibility * 2)
                    end
                    
                    -- MASSIVE boost for same zone (creates strong blob growth)
                    if zone_weights[neighbor_zone] then
                        zone_weights[neighbor_zone] = zone_weights[neighbor_zone] + 50
                    end
                else
                    print("WFC: WARNING - Unknown neighbor zone:", neighbor_zone)
                end
            end
        end
    end
    
    -- Convert weights to selection array
    local selection_array = {}
    for zone_name, weight in pairs(zone_weights) do
        for i = 1, math.max(1, math.floor(weight)) do
            table.insert(selection_array, zone_name)
        end
    end
    
    if #selection_array > 0 then
        return selection_array[love.math.random(1, #selection_array)]
    else
        return "park_central" -- Fallback to park
    end
end

function WFCZoningService._generateConstrainedFineGrid(width, height, coarse_grid)
    local fine_grid = {}
    local coarse_width = #coarse_grid[1]
    local coarse_height = #coarse_grid
    
    for y = 1, height do
        fine_grid[y] = {}
        for x = 1, width do
            -- Map fine coordinates to coarse coordinates
            local coarse_x = math.min(coarse_width, math.max(1, math.floor((x-1) * coarse_width / width) + 1))
            local coarse_y = math.min(coarse_height, math.max(1, math.floor((y-1) * coarse_height / height) + 1))
            
            local base_zone = coarse_grid[coarse_y][coarse_x]
            
            -- NO DOWNTOWN HANDLING - it will be stamped later
            if love.math.random() < 0.95 then
                fine_grid[y][x] = base_zone
            else
                fine_grid[y][x] = WFCZoningService._getCompatibleZone(base_zone)
            end
        end
    end
    
    return fine_grid
end

function WFCZoningService._stampDowntownSquare(grid, width, height, center_x, center_y, downtown_w, downtown_h)
    local half_w = math.floor(downtown_w / 2)
    local half_h = math.floor(downtown_h / 2)
    
    local stamped_cells = 0
    
    for dy = -half_h, half_h do
        for dx = -half_w, half_w do
            local x, y = center_x + dx, center_y + dy
            if x >= 1 and x <= width and y >= 1 and y <= height then
                -- CRITICAL FIX: Only stamp if the cell is not already "downtown"
                -- This prevents overwriting when the zone grid is used later
                if grid[y][x] ~= "downtown" then
                    grid[y][x] = "downtown"
                    stamped_cells = stamped_cells + 1
                end
            end
        end
    end
    
    print(string.format("WFC: Stamped downtown square with %d cells (%dx%d)", stamped_cells, downtown_w, downtown_h))
end

function WFCZoningService._getCompatibleZone(base_zone)
    local compatible_zones = {
        commercial = {"commercial", "tech", "entertainment"},
        residential_north = {"residential_north", "park_central", "medical"},
        residential_south = {"residential_south", "park_nature", "entertainment"},
        industrial_heavy = {"industrial_heavy", "warehouse"},
        industrial_light = {"industrial_light", "tech", "warehouse"},
        university = {"university", "tech", "park_central"},
        medical = {"medical", "residential_north"},
        entertainment = {"entertainment", "commercial"},
        waterfront = {"waterfront", "park_nature"},
        warehouse = {"warehouse", "industrial_heavy", "industrial_light"},
        tech = {"tech", "university", "commercial"},
        park_central = {"park_central", "residential_north"},
        park_nature = {"park_nature", "residential_south"}
    }
    
    local options = compatible_zones[base_zone] or {base_zone}
    return options[love.math.random(1, #options)]
end

-- Utility function to convert zone grid to colors for visualization
function WFCZoningService.gridToColors(zone_grid)
    local color_grid = {}
    
    for y = 1, #zone_grid do
        color_grid[y] = {}
        for x = 1, #zone_grid[y] do
            local zone = zone_grid[y][x]
            if zone == "downtown" then
                color_grid[y][x] = {1, 1, 0} -- Yellow for downtown (only from stamping)
            else
                color_grid[y][x] = ZONES[zone] and ZONES[zone].color or {0.5, 0.5, 0.5}
            end
        end
    end
    
    return color_grid
end

-- Debug function to get zone statistics (EXPANDED ZONES)
function WFCZoningService.getZoneStats(zone_grid)
    local stats = {}
    local total = 0
    
    -- Include all possible zones
    local all_zones = {"commercial", "residential_north", "residential_south", "industrial_heavy", "industrial_light", 
                      "university", "medical", "entertainment", "waterfront", "warehouse", "tech", 
                      "park_central", "park_nature", "downtown"}
    for _, zone_name in ipairs(all_zones) do
        stats[zone_name] = 0
    end
    
    for y = 1, #zone_grid do
        for x = 1, #zone_grid[y] do
            local zone = zone_grid[y][x]
            if stats[zone] ~= nil then
                stats[zone] = stats[zone] + 1
            end
            total = total + 1
        end
    end
    
    -- Convert to percentages
    for zone_name, count in pairs(stats) do
        stats[zone_name] = {
            count = count,
            percentage = math.floor((count / total) * 100)
        }
    end
    
    return stats, total
end

return WFCZoningService