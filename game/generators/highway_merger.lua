-- game/generators/highway_merger.lua
-- Highway Merging Logic Module

local HighwayMerger = {}

function HighwayMerger.applyMergingLogic(highway_paths, ring_road_curve)
    local MERGE_DISTANCE = 50  -- How close roads need to be to consider merging
    local MERGE_STRENGTH = 0.8 -- How strongly roads are pulled toward each other
    local PARALLEL_MERGE_DISTANCE = 80  -- Special distance for parallel roads
    local merged_paths = {}
    
    -- Process each highway path
    for highway_idx, highway_path in ipairs(highway_paths) do
        local modified_path = {}
        
        for i, highway_point in ipairs(highway_path) do
            local merged_point = {x = highway_point.x, y = highway_point.y}
            local merge_influences = {}
            
            -- Check for merging with ring road
            if #ring_road_curve > 0 then
                local closest_ring_point, closest_ring_distance = HighwayMerger.findClosestPointOnPath(highway_point, ring_road_curve)
                local merge_distance = MERGE_DISTANCE
                
                -- Check if roads are running parallel - if so, use larger merge distance
                if HighwayMerger.areRoadsRunningParallel(highway_point, highway_path, closest_ring_point, ring_road_curve, i) then
                    merge_distance = PARALLEL_MERGE_DISTANCE
                end
                
                if closest_ring_distance < merge_distance then
                    local strength = MERGE_STRENGTH
                    -- Stronger pull for parallel roads
                    if merge_distance == PARALLEL_MERGE_DISTANCE then
                        strength = MERGE_STRENGTH * 1.3
                    end
                    
                    table.insert(merge_influences, {
                        point = closest_ring_point,
                        distance = closest_ring_distance,
                        strength = strength,
                        max_distance = merge_distance
                    })
                end
            end
            
            -- Check for merging with other highways
            for other_idx, other_highway in ipairs(highway_paths) do
                if other_idx ~= highway_idx then
                    local closest_other_point, closest_other_distance = HighwayMerger.findClosestPointOnPath(highway_point, other_highway)
                    local merge_distance = MERGE_DISTANCE
                    
                    -- Check if highways are running parallel
                    if HighwayMerger.areRoadsRunningParallel(highway_point, highway_path, closest_other_point, other_highway, i) then
                        merge_distance = PARALLEL_MERGE_DISTANCE
                    end
                    
                    if closest_other_distance < merge_distance then
                        local strength = MERGE_STRENGTH * 0.8  -- Slightly weaker than ring road merging
                        -- Stronger pull for parallel roads
                        if merge_distance == PARALLEL_MERGE_DISTANCE then
                            strength = strength * 1.3
                        end
                        
                        table.insert(merge_influences, {
                            point = closest_other_point,
                            distance = closest_other_distance,
                            strength = strength,
                            max_distance = merge_distance
                        })
                    end
                end
            end
            
            -- Apply merge influences
            if #merge_influences > 0 then
                local total_pull_x, total_pull_y = 0, 0
                local total_weight = 0
                
                for _, influence in ipairs(merge_influences) do
                    local pull_strength = influence.strength * (1 - (influence.distance / influence.max_distance))
                    local pull_x = (influence.point.x - highway_point.x) * pull_strength
                    local pull_y = (influence.point.y - highway_point.y) * pull_strength
                    
                    total_pull_x = total_pull_x + pull_x
                    total_pull_y = total_pull_y + pull_y
                    total_weight = total_weight + pull_strength
                end
                
                if total_weight > 0 then
                    merged_point.x = highway_point.x + total_pull_x
                    merged_point.y = highway_point.y + total_pull_y
                end
            end
            
            table.insert(modified_path, merged_point)
        end
        
        table.insert(merged_paths, modified_path)
    end
    
    return merged_paths
end

function HighwayMerger.findClosestPointOnPath(point, path)
    local closest_point = nil
    local min_distance = math.huge
    
    for _, path_point in ipairs(path) do
        local dx = point.x - path_point.x
        local dy = point.y - path_point.y
        local distance = math.sqrt(dx * dx + dy * dy)
        
        if distance < min_distance then
            min_distance = distance
            closest_point = path_point
        end
    end
    
    return closest_point, min_distance
end

function HighwayMerger.areRoadsRunningParallel(point1, path1, point2, path2, current_index)
    -- Get direction vectors for both roads at these points
    local dir1_x, dir1_y = HighwayMerger.getRoadDirection(path1, current_index)
    local dir2_x, dir2_y = HighwayMerger.getRoadDirection(path2, HighwayMerger.findPointIndex(point2, path2))
    
    -- Calculate dot product to see if directions are similar
    local dot_product = dir1_x * dir2_x + dir1_y * dir2_y
    
    -- If dot product is close to 1 or -1, roads are parallel
    -- We use 0.8 as threshold (about 36 degrees tolerance)
    return math.abs(dot_product) > 0.8
end

function HighwayMerger.getRoadDirection(path, index)
    if #path < 2 then return 0, 0 end
    
    local start_idx = math.max(1, index - 1)
    local end_idx = math.min(#path, index + 1)
    
    if start_idx == end_idx then
        if index > 1 then
            start_idx = index - 1
        else
            end_idx = index + 1
        end
    end
    
    local dx = path[end_idx].x - path[start_idx].x
    local dy = path[end_idx].y - path[start_idx].y
    local length = math.sqrt(dx * dx + dy * dy)
    
    if length == 0 then return 0, 0 end
    
    return dx / length, dy / length
end

function HighwayMerger.findPointIndex(target_point, path)
    for i, point in ipairs(path) do
        if point.x == target_point.x and point.y == target_point.y then
            return i
        end
    end
    return 1  -- Fallback
end

return HighwayMerger