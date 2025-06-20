-- game/generators/path_smoother.lua
-- Path Smoothing Utilities

local PathSmoother = {}

function PathSmoother.smoothSharpAngles(path)
    if #path < 3 then return path end
    
    local smoothed_path = {path[1]}  -- Keep first point
    local MAX_ANGLE = math.pi * 0.7  -- About 126 degrees - anything sharper gets smoothed
    
    for i = 2, #path - 1 do
        local prev_point = path[i - 1]
        local current_point = path[i]
        local next_point = path[i + 1]
        
        -- Calculate the angle at this point
        local angle = PathSmoother.calculateAngleAtPoint(prev_point, current_point, next_point)
        
        if angle < MAX_ANGLE then
            -- Sharp angle detected! Insert smoothing points
            local smooth_points = PathSmoother.createSmoothingPoints(prev_point, current_point, next_point)
            for _, smooth_point in ipairs(smooth_points) do
                table.insert(smoothed_path, smooth_point)
            end
        else
            -- Angle is fine, keep the original point
            table.insert(smoothed_path, current_point)
        end
    end
    
    table.insert(smoothed_path, path[#path])  -- Keep last point
    return smoothed_path
end

function PathSmoother.calculateAngleAtPoint(prev_point, current_point, next_point)
    -- Calculate vectors from current point to prev and next
    local vec1_x = prev_point.x - current_point.x
    local vec1_y = prev_point.y - current_point.y
    local vec2_x = next_point.x - current_point.x
    local vec2_y = next_point.y - current_point.y
    
    -- Calculate lengths
    local len1 = math.sqrt(vec1_x * vec1_x + vec1_y * vec1_y)
    local len2 = math.sqrt(vec2_x * vec2_x + vec2_y * vec2_y)
    
    if len1 == 0 or len2 == 0 then return math.pi end
    
    -- Normalize vectors
    vec1_x, vec1_y = vec1_x / len1, vec1_y / len1
    vec2_x, vec2_y = vec2_x / len2, vec2_y / len2
    
    -- Calculate dot product
    local dot_product = vec1_x * vec2_x + vec1_y * vec2_y
    
    -- Clamp dot product to avoid floating point errors
    dot_product = math.max(-1, math.min(1, dot_product))
    
    -- Return angle in radians
    return math.acos(dot_product)
end

function PathSmoother.createSmoothingPoints(prev_point, sharp_point, next_point)
    -- Create a gentle curve instead of a sharp angle
    local smooth_points = {}
    
    -- Calculate midpoints for smoother transitions
    local mid1_x = (prev_point.x + sharp_point.x) / 2
    local mid1_y = (prev_point.y + sharp_point.y) / 2
    local mid2_x = (sharp_point.x + next_point.x) / 2
    local mid2_y = (sharp_point.y + next_point.y) / 2
    
    -- Create a curved path through these midpoints
    table.insert(smooth_points, {x = mid1_x, y = mid1_y})
    
    -- Add a point that's slightly displaced from the original sharp point
    local displaced_x = sharp_point.x + (mid2_x - mid1_x) * 0.2
    local displaced_y = sharp_point.y + (mid2_y - mid1_y) * 0.2
    table.insert(smooth_points, {x = displaced_x, y = displaced_y})
    
    table.insert(smooth_points, {x = mid2_x, y = mid2_y})
    
    return smooth_points
end

return PathSmoother