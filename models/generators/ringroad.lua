-- game/generators/ringroad.lua
-- Ring Road Generation Module

local RingRoad = {}

function RingRoad.generatePath(districts, map_w, map_h)
    local ring_road_nodes = RingRoad.getRingNodesFromDistricts(districts, map_w, map_h)
    
    if #ring_road_nodes <= 3 then
        return {}
    end
    
    local center_x, center_y = map_w / 2, map_h / 2
    
    -- Sort nodes by angle around the center
    table.sort(ring_road_nodes, function(a, b) 
        return math.atan2(a.y - center_y, a.x - center_x) < math.atan2(b.y - center_y, b.x - center_x) 
    end)
    
    -- Filter out nodes that would create sharp angles
    local smoothed_nodes = RingRoad.filterSharpAngles(ring_road_nodes, center_x, center_y)
    
    -- Add padding nodes for spline generation
    if #smoothed_nodes >= 3 then
        table.insert(smoothed_nodes, smoothed_nodes[1])
        table.insert(smoothed_nodes, smoothed_nodes[2]) 
        table.insert(smoothed_nodes, smoothed_nodes[3])
        return smoothed_nodes
    end
    
    return {}
end

function RingRoad.getRingNodesFromDistricts(districts, max_w, max_h)
    local nodes = {}
    local center_x, center_y = max_w / 2, max_h / 2
    local edge_threshold = max_w * 0.1
    local map_corners = {{x=1,y=1}, {x=max_w,y=1}, {x=1,y=max_h}, {x=max_w,y=max_h}}

    for _, dist in ipairs(districts) do
        if math.sqrt((dist.x+dist.w/2 - center_x)^2 + (dist.y+dist.h/2 - center_y)^2) >= max_w * 0.15 then
            local district_corners = {
                {x=dist.x, y=dist.y}, 
                {x=dist.x+dist.w, y=dist.y}, 
                {x=dist.x, y=dist.y+dist.h}, 
                {x=dist.x+dist.w, y=dist.y+dist.h}
            }
            
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
            
            if math.min(primary_node.x, primary_node.y, max_w - primary_node.x, max_h - primary_node.y) < edge_threshold then
                local inner_node, min_center_dist_sq = nil, math.huge
                for _, d_corner in ipairs(district_corners) do
                    local dist_sq = (d_corner.x - center_x)^2 + (d_corner.y - center_y)^2
                    if dist_sq < min_center_dist_sq then 
                        min_center_dist_sq = dist_sq 
                        inner_node = d_corner 
                    end
                end
                table.insert(nodes, inner_node)
            else
                table.insert(nodes, primary_node)
            end
        end
    end
    
    return nodes
end

function RingRoad.filterSharpAngles(ring_nodes, center_x, center_y)
    if #ring_nodes < 4 then return ring_nodes end
    
    local filtered_nodes = {}
    local MIN_ANGLE = math.pi * 0.25  -- 45 degrees minimum (permissive)
    local MIN_ARC_DISTANCE = 30       -- Allow closer nodes
    
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
        
        -- Only filter out extremely sharp angles or very close nodes
        local is_extremely_sharp = angle < MIN_ANGLE
        local is_too_close = arc_distance < MIN_ARC_DISTANCE
        
        if not (is_extremely_sharp and is_too_close) then
            -- Keep this node unless it's both extremely sharp AND too close
            table.insert(filtered_nodes, current_node)
            last_kept_node = current_node
        else
            -- Skip this node - it's both extremely sharp and too close
            print(string.format("Skipping ring road node at (%d,%d) - angle: %.1f°, arc_dist: %.1f", 
                current_node.x, current_node.y, math.deg(angle), arc_distance))
        end
    end
    
    -- Only use filtering if we keep most of the nodes
    if #filtered_nodes >= math.max(4, #ring_nodes * 0.6) then
        return filtered_nodes
    else
        print("Warning: Ring road filtering removed too many nodes, using original")
        return ring_nodes
    end
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