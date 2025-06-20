-- game/generators/ringroad.lua
-- Ring Road Generation Module with improved angle filtering

local RingRoad = {}

function RingRoad.generatePath(districts, map_w, map_h, params)
    -- Use debug parameters or defaults
    local ring_min_angle = (params and params.ring_min_angle) or 45 -- degrees
    local ring_min_arc_distance = (params and params.ring_min_arc_distance) or 30
    local ring_edge_threshold = (params and params.ring_edge_threshold) or 0.1 -- percentage of map
    local ring_center_distance_threshold = (params and params.ring_center_distance_threshold) or 0.15 -- percentage of map
    
    local ring_road_nodes = RingRoad.getRingNodesFromDistricts(districts, map_w, map_h, 
                                                               ring_edge_threshold, ring_center_distance_threshold)
    
    if #ring_road_nodes <= 3 then
        return {}
    end
    
    local center_x, center_y = map_w / 2, map_h / 2
    
    -- Sort nodes by angle around the center
    table.sort(ring_road_nodes, function(a, b) 
        return math.atan2(a.y - center_y, a.x - center_x) < math.atan2(b.y - center_y, b.x - center_x) 
    end)
    
    -- IMPROVED: More aggressive filtering of sharp angles
    local smoothed_nodes = RingRoad.filterSharpAnglesAggressive(ring_road_nodes, center_x, center_y, 
                                                               ring_min_angle, ring_min_arc_distance)
    
    -- Add padding nodes for spline generation
    if #smoothed_nodes >= 3 then
        table.insert(smoothed_nodes, smoothed_nodes[1])
        table.insert(smoothed_nodes, smoothed_nodes[2]) 
        table.insert(smoothed_nodes, smoothed_nodes[3])
        return smoothed_nodes
    end
    
    return {}
end

function RingRoad.filterSharpAnglesAggressive(ring_nodes, center_x, center_y, min_angle_deg, min_arc_distance)
    if #ring_nodes < 4 then return ring_nodes end
    
    local filtered_nodes = {}
    local VERY_SHARP_ANGLE = math.pi * (min_angle_deg / 180) -- Convert to radians
    local EXTREMELY_CLOSE = min_arc_distance
    
    -- Always keep the first node
    table.insert(filtered_nodes, ring_nodes[1])
    local last_kept_node = ring_nodes[1]
    
    for i = 2, #ring_nodes do
        local current_node = ring_nodes[i]
        local next_node = ring_nodes[i + 1] or ring_nodes[1]  -- Wrap around for last node
        
        -- Calculate the angle this node would create
        local angle = RingRoad.calculateAngleAtPoint(last_kept_node, current_node, next_node)
        
        -- Calculate arc distance from last kept node
        local arc_distance = RingRoad.calculateArcDistance(last_kept_node, current_node, center_x, center_y)
        
        -- Check for sharp angles - now more aggressive about catching them
        local is_sharp_angle = angle < VERY_SHARP_ANGLE
        local is_extremely_close = arc_distance < EXTREMELY_CLOSE
        
        -- Check for backtracking (this should catch the 180-degree turns)
        local creates_backtrack = RingRoad.wouldCreateBacktrack(last_kept_node, current_node, next_node, center_x, center_y)
        
        -- Skip if it's a sharp angle OR if it backtracks (changed from AND to OR for backtracking)
        local should_skip = (is_sharp_angle and is_extremely_close) or creates_backtrack
        
        if not should_skip then
            -- Keep this node
            table.insert(filtered_nodes, current_node)
            last_kept_node = current_node
            print(string.format("Kept ring road node at (%d,%d) - angle: %.1f°, arc_dist: %.1f", 
                current_node.x, current_node.y, math.deg(angle), arc_distance))
        else
            -- Skip this node
            local reason = creates_backtrack and "backtrack/reversal" or "sharp angle + close"
            print(string.format("Skipped ring road node at (%d,%d) - %s - angle: %.1f°, arc_dist: %.1f", 
                current_node.x, current_node.y, reason, math.deg(angle), arc_distance))
        end
    end
    
    -- Only use filtering if we keep at least 5 nodes for a good organic ring
    if #filtered_nodes >= 5 then
        print(string.format("Ring road filtering successful: kept %d/%d nodes", #filtered_nodes, #ring_nodes))
        return filtered_nodes
    else
        print(string.format("Ring road filtering kept %d nodes, using fallback", #filtered_nodes))
        -- Fallback to more lenient filtering
        return RingRoad.filterSharpAnglesLenient(ring_nodes, center_x, center_y, min_angle_deg / 3, min_arc_distance)
    end
end

function RingRoad.filterSharpAnglesLenient(ring_nodes, center_x, center_y, min_angle_deg, min_arc_distance)
    local filtered_nodes = {}
    local VERY_SHARP_ANGLE = math.pi * (min_angle_deg / 180) -- Even more lenient
    local VERY_CLOSE = min_arc_distance
    
    table.insert(filtered_nodes, ring_nodes[1])
    local last_kept_node = ring_nodes[1]
    
    for i = 2, #ring_nodes do
        local current_node = ring_nodes[i]
        local next_node = ring_nodes[i + 1] or ring_nodes[1]
        
        local angle = RingRoad.calculateAngleAtPoint(last_kept_node, current_node, next_node)
        local arc_distance = RingRoad.calculateArcDistance(last_kept_node, current_node, center_x, center_y)
        
        -- Even more lenient - only filter the absolute worst angles
        if angle >= VERY_SHARP_ANGLE or arc_distance >= VERY_CLOSE then
            table.insert(filtered_nodes, current_node)
            last_kept_node = current_node
        end
    end
    
    return #filtered_nodes >= 4 and filtered_nodes or ring_nodes
end

-- NEW: Check if a node would create a "backtrack" - going backwards around the ring
function RingRoad.wouldCreateBacktrack(prev_node, current_node, next_node, center_x, center_y)
    -- Simple distance-based check: if going from prev->current->next creates a path
    -- where next is closer to prev than current is, it's likely a sharp reversal
    local prev_to_current_dist = math.sqrt((current_node.x - prev_node.x)^2 + (current_node.y - prev_node.y)^2)
    local current_to_next_dist = math.sqrt((next_node.x - current_node.x)^2 + (next_node.y - current_node.y)^2)
    local prev_to_next_dist = math.sqrt((next_node.x - prev_node.x)^2 + (next_node.y - prev_node.y)^2)
    
    -- If the direct distance from prev to next is much shorter than going through current,
    -- then current is creating a detour (likely a sharp angle)
    local total_path_dist = prev_to_current_dist + current_to_next_dist
    local detour_ratio = total_path_dist / prev_to_next_dist
    
    -- If the detour ratio is very high, it's probably a sharp reversal
    local is_major_detour = detour_ratio > 2.0
    
    -- Also check if we're making a very sharp turn by looking at the dot product
    local vec1_x = current_node.x - prev_node.x
    local vec1_y = current_node.y - prev_node.y
    local vec2_x = next_node.x - current_node.x
    local vec2_y = next_node.y - current_node.y
    
    -- Normalize vectors
    local len1 = math.sqrt(vec1_x * vec1_x + vec1_y * vec1_y)
    local len2 = math.sqrt(vec2_x * vec2_x + vec2_y * vec2_y)
    
    if len1 > 0 and len2 > 0 then
        vec1_x, vec1_y = vec1_x / len1, vec1_y / len1
        vec2_x, vec2_y = vec2_x / len2, vec2_y / len2
        
        -- Dot product gives us the cosine of the angle between vectors
        local dot_product = vec1_x * vec2_x + vec1_y * vec2_y
        
        -- If dot product is close to -1, the vectors are pointing in opposite directions (180° turn)
        local is_reversal = dot_product < -0.7  -- Catches angles sharper than about 135°
        
        if is_major_detour or is_reversal then
            print(string.format("Backtrack detected: detour_ratio=%.2f, dot_product=%.2f", detour_ratio, dot_product))
            return true
        end
    end
    
    return false
end

function RingRoad.getRingNodesFromDistricts(districts, max_w, max_h, edge_threshold, center_distance_threshold)
    local nodes = {}
    local center_x, center_y = max_w / 2, max_h / 2
    local edge_threshold_pixels = max_w * edge_threshold
    local map_corners = {{x=1,y=1}, {x=max_w,y=1}, {x=1,y=max_h}, {x=max_w,y=max_h}}
    
    print(string.format("Ring road generation: %d districts to consider", #districts))

    for district_idx, dist in ipairs(districts) do
        local district_distance = math.sqrt((dist.x+dist.w/2 - center_x)^2 + (dist.y+dist.h/2 - center_y)^2)
        
        -- Only consider districts that are far enough from downtown center
        if district_distance >= max_w * center_distance_threshold then
            print(string.format("District %d: distance %.1f (considering for ring)", district_idx, district_distance))
            
            local district_corners = {
                {x=dist.x, y=dist.y}, 
                {x=dist.x+dist.w, y=dist.y}, 
                {x=dist.x, y=dist.y+dist.h}, 
                {x=dist.x+dist.w, y=dist.y+dist.h}
            }
            
            -- STEP 1: Find the corner closest to map edge (original logic)
            local primary_node, min_dist_sq = nil, math.huge
            for _, d_corner in ipairs(district_corners) do
                for _, m_corner in ipairs(map_corners) do
                    local dist_sq = (d_corner.x - m_corner.x)^2 + (d_corner.y - m_corner.y)^2
                    if dist_sq < min_dist_sq then 
                        min_dist_sq = dist_sq 
                        primary_node = d_corner 
                    end
                end
            end
            
            local chosen_corner = nil
            
            -- STEP 2: If primary corner is too close to edge, use inner corner instead
            local edge_distance = math.min(primary_node.x, primary_node.y, max_w - primary_node.x, max_h - primary_node.y)
            if edge_distance < edge_threshold_pixels then
                print(string.format("District %d: primary corner (%d,%d) too close to edge (dist: %.1f), finding inner corner", 
                      district_idx, primary_node.x, primary_node.y, edge_distance))
                
                -- Find the corner closest to center (inner corner)
                local inner_node, min_center_dist_sq = nil, math.huge
                for _, d_corner in ipairs(district_corners) do
                    local dist_sq = (d_corner.x - center_x)^2 + (d_corner.y - center_y)^2
                    if dist_sq < min_center_dist_sq then 
                        min_center_dist_sq = dist_sq 
                        inner_node = d_corner 
                    end
                end
                chosen_corner = inner_node
                print(string.format("District %d: using inner corner (%d,%d)", district_idx, chosen_corner.x, chosen_corner.y))
            else
                chosen_corner = primary_node
                print(string.format("District %d: using primary corner (%d,%d)", district_idx, chosen_corner.x, chosen_corner.y))
            end
            
            -- STEP 3: If we have existing nodes, check if this corner would create a sharp angle
            if #nodes > 1 and chosen_corner then
                local last_node = nodes[#nodes]
                local second_last_node = nodes[#nodes - 1]
                local test_angle = RingRoad.calculateAngleAtPoint(second_last_node, last_node, chosen_corner)
                
                -- RELAXED: Only reject if extremely sharp (< 45 degrees instead of 72)
                if test_angle < math.pi * 0.25 then -- Less than 45 degrees
                    print(string.format("District %d: corner (%d,%d) would create very sharp angle (%.1f°), trying alternatives", 
                          district_idx, chosen_corner.x, chosen_corner.y, math.deg(test_angle)))
                    
                    local best_corner = nil
                    local best_angle = 0
                    
                    -- Try all corners to find the one with the best (largest) angle
                    for _, corner in ipairs(district_corners) do
                        -- Be more lenient about edge distance for alternatives
                        local corner_edge_dist = math.min(corner.x, corner.y, max_w - corner.x, max_h - corner.y)
                        if corner_edge_dist >= edge_threshold_pixels * 0.5 then -- Half the normal threshold
                            local angle = RingRoad.calculateAngleAtPoint(second_last_node, last_node, corner)
                            if angle > best_angle then
                                best_angle = angle
                                best_corner = corner
                            end
                        end
                    end
                    
                    -- RELAXED: Accept any corner that's better than extremely sharp (> 30 degrees)
                    if best_corner and best_angle > math.pi * 0.17 then -- At least 30 degrees
                        chosen_corner = best_corner
                        print(string.format("District %d: using alternative corner (%d,%d) with angle %.1f°", 
                              district_idx, chosen_corner.x, chosen_corner.y, math.deg(best_angle)))
                    else
                        -- FALLBACK: If no alternatives work, just use the original corner anyway
                        print(string.format("District %d: no good alternatives, keeping original corner despite sharp angle", district_idx))
                        -- chosen_corner is already set to the original
                    end
                else
                    print(string.format("District %d: corner (%d,%d) creates acceptable angle (%.1f°)", 
                          district_idx, chosen_corner.x, chosen_corner.y, math.deg(test_angle)))
                end
            elseif #nodes <= 1 then
                print(string.format("District %d: early district, no angle checking needed", district_idx))
            end
            
            -- STEP 4: Add the chosen corner to nodes
            if chosen_corner then
                table.insert(nodes, chosen_corner)
                print(string.format("District %d: ADDED ring node at (%d,%d) (total nodes: %d)", 
                      district_idx, chosen_corner.x, chosen_corner.y, #nodes))
            end
        else
            print(string.format("District %d: distance %.1f too close to center, skipping", district_idx, district_distance))
        end
    end
    
    print(string.format("Ring road node generation complete: %d nodes from %d districts", #nodes, #districts))
    return nodes
end

-- NEW: Find the corner of a district that would create the smoothest ring road
function RingRoad.findBestCornerForRing(corners, center_x, center_y, existing_nodes)
    if #existing_nodes == 0 then
        -- For the first district, just pick the corner farthest from center
        local best_corner = nil
        local max_distance = 0
        
        for _, corner in ipairs(corners) do
            local distance = math.sqrt((corner.x - center_x)^2 + (corner.y - center_y)^2)
            if distance > max_distance then
                max_distance = distance
                best_corner = corner
            end
        end
        
        return best_corner
    end
    
    -- For subsequent districts, pick the corner that creates the best angle
    local best_corner = nil
    local best_angle = 0  -- We want the largest angle (most gradual turn)
    
    local last_node = existing_nodes[#existing_nodes]
    local second_last_node = existing_nodes[#existing_nodes - 1] or existing_nodes[1]
    
    for _, corner in ipairs(corners) do
        local angle = RingRoad.calculateAngleAtPoint(second_last_node, last_node, corner)
        
        if angle > best_angle then
            best_angle = angle
            best_corner = corner
        end
    end
    
    return best_corner
end

function RingRoad.calculateAngleAtPoint(prev_node, current_node, next_node)
    -- Calculate vectors from current node to prev and next nodes
    local vec1_x = prev_node.x - current_node.x
    local vec1_y = prev_node.y - current_node.y
    local vec2_x = next_node.x - current_node.x
    local vec2_y = next_node.y - current_node.y
    
    -- Calculate lengths
    local len1 = math.sqrt(vec1_x * vec1_x + vec1_y * vec1_y)
    local len2 = math.sqrt(vec2_x * vec2_x + vec2_y * vec2_y)
    
    if len1 == 0 or len2 == 0 then return math.pi end
    
    -- Normalize vectors
    vec1_x, vec1_y = vec1_x / len1, vec1_y / len1
    vec2_x, vec2_y = vec2_x / len2, vec2_y / len2
    
    -- Calculate dot product
    local dot_product = vec1_x * vec2_x + vec1_y * vec2_y
    
    -- Clamp to avoid floating point errors
    dot_product = math.max(-1, math.min(1, dot_product))
    
    -- Return angle in radians
    return math.acos(dot_product)
end

function RingRoad.calculateArcDistance(node1, node2, center_x, center_y)
    -- Calculate the angular distance between two nodes around the ring
    local angle1 = math.atan2(node1.y - center_y, node1.x - center_x)
    local angle2 = math.atan2(node2.y - center_y, node2.x - center_x)
    
    -- Calculate angular difference
    local angle_diff = math.abs(angle2 - angle1)
    if angle_diff > math.pi then
        angle_diff = 2 * math.pi - angle_diff
    end
    
    -- Convert to approximate distance (assuming average radius)
    local avg_radius = 100  -- Approximate ring radius
    return angle_diff * avg_radius
end

return RingRoad