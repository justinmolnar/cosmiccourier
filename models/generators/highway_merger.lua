-- game/generators/highway_merger.lua
-- Highway Merging Logic Module - Simplified Fix

local HighwayMerger = {}

function HighwayMerger.applyMergingLogic(highway_paths, ring_road_curve)
    local MERGE_DISTANCE = 30  -- Reduced from 50 - less aggressive merging
    local MERGE_STRENGTH = 0.4 -- Reduced from 0.8 - gentler merging
    local PARALLEL_MERGE_DISTANCE = 50  -- Reduced from 80
    local MIN_ANGLE_DIFFERENCE = 0.7  -- NEW: Only merge if roads are going roughly same direction
    
    local merged_paths = {}
    
    -- Process each highway path
    for highway_idx, highway_path in ipairs(highway_paths) do
        local modified_path = {}
        
        for i, highway_point in ipairs(highway_path) do
            local merged_point = {x = highway_point.x, y = highway_point.y}
            local merge_influences = {}
            
            -- Get current highway direction
            local current_direction = HighwayMerger.getPathDirection(highway_path, i)
            
            -- Check for merging with ring road
            if #ring_road_curve > 0 then
                local closest_ring_point, closest_ring_distance = HighwayMerger.findClosestPointOnPath(highway_point, ring_road_curve)
                
                if closest_ring_distance < MERGE_DISTANCE then
                    -- Check if directions are compatible
                    local ring_direction = HighwayMerger.getPointDirection(closest_ring_point, ring_road_curve)
                    local direction_similarity = HighwayMerger.calculateDirectionSimilarity(current_direction, ring_direction)
                    
                    if direction_similarity > MIN_ANGLE_DIFFERENCE then
                        local strength = MERGE_STRENGTH * direction_similarity * (1 - (closest_ring_distance / MERGE_DISTANCE))
                        
                        table.insert(merge_influences, {
                            point = closest_ring_point,
                            strength = strength
                        })
                    end
                end
            end
            
            -- Check for merging with other highways
            for other_idx, other_highway in ipairs(highway_paths) do
                if other_idx ~= highway_idx then
                    local closest_other_point, closest_other_distance = HighwayMerger.findClosestPointOnPath(highway_point, other_highway)
                    
                    if closest_other_distance < MERGE_DISTANCE then
                        -- Check if directions are compatible
                        local other_direction = HighwayMerger.getPointDirection(closest_other_point, other_highway)
                        local direction_similarity = HighwayMerger.calculateDirectionSimilarity(current_direction, other_direction)
                        
                        if direction_similarity > MIN_ANGLE_DIFFERENCE then
                            local strength = MERGE_STRENGTH * 0.8 * direction_similarity * (1 - (closest_other_distance / MERGE_DISTANCE))
                            
                            table.insert(merge_influences, {
                                point = closest_other_point,
                                strength = strength
                            })
                        end
                    end
                end
            end
            
            -- Apply merge influences
            if #merge_influences > 0 then
                local total_pull_x, total_pull_y = 0, 0
                local total_weight = 0
                
                for _, influence in ipairs(merge_influences) do
                    local pull_x = (influence.point.x - highway_point.x) * influence.strength
                    local pull_y = (influence.point.y - highway_point.y) * influence.strength
                    
                    total_pull_x = total_pull_x + pull_x
                    total_pull_y = total_pull_y + pull_y
                    total_weight = total_weight + influence.strength
                end
                
                if total_weight > 0 then
                    -- Limit the maximum pull to prevent wild snaking
                    local max_pull = 15
                    total_pull_x = math.max(-max_pull, math.min(max_pull, total_pull_x))
                    total_pull_y = math.max(-max_pull, math.min(max_pull, total_pull_y))
                    
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

function HighwayMerger.getPathDirection(path, index)
    if #path < 2 then return {x = 0, y = 0} end
    
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
    
    if length == 0 then return {x = 0, y = 0} end
    
    return {x = dx / length, y = dy / length}
end

function HighwayMerger.getPointDirection(point, path)
    -- Find the point in the path and get its direction
    local point_index = HighwayMerger.findPointIndex(point, path)
    return HighwayMerger.getPathDirection(path, point_index)
end

function HighwayMerger.calculateDirectionSimilarity(dir1, dir2)
    -- Calculate dot product to measure direction similarity
    local dot_product = dir1.x * dir2.x + dir1.y * dir2.y
    return math.abs(dot_product) -- Return absolute value (parallel roads going opposite directions can also merge)
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

function HighwayMerger.findPointIndex(target_point, path)
    for i, point in ipairs(path) do
        if point.x == target_point.x and point.y == target_point.y then
            return i
        end
    end
    return 1  -- Fallback
end

return HighwayMerger