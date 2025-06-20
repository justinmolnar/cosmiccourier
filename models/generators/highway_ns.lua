-- game/generators/highway_ns.lua
-- North-South Highway Generation Module

local HighwayNS = {}

function HighwayNS.generatePaths(map_w, map_h, districts, params)
    local paths = {}
    local EXTENSION = 100
    
    -- Use debug parameters or defaults
    local num_highways = (params and params.num_ns_highways) or 2
    local highway_step_size = (params and params.highway_step_size) or 30
    local highway_curve_distance = (params and params.highway_curve_distance) or 50
    local highway_buffer = (params and params.highway_buffer) or 35
    
    -- Generate specified number of North-South highways
    for i = 1, num_highways do
        local x_pos = map_w * (i / (num_highways + 1)) -- Distribute evenly
        local path = HighwayNS.createFlowingPath(
            {x = x_pos, y = -EXTENSION}, 
            {x = x_pos, y = map_h + EXTENSION}, 
            districts,
            highway_step_size,
            highway_curve_distance,
            highway_buffer
        )
        table.insert(paths, path)
    end
    
    return paths
end

function HighwayNS.createFlowingPath(start_point, end_point, districts, step_size, curve_distance, buffer)
    local path = {start_point}
    local current = {x = start_point.x, y = start_point.y}
    
    while true do
        -- Calculate where we want to go (straight toward goal)
        local goal_dx = end_point.x - current.x
        local goal_dy = end_point.y - current.y
        local goal_distance = math.sqrt(goal_dx * goal_dx + goal_dy * goal_dy)
        
        if goal_distance < step_size * 1.5 then
            table.insert(path, end_point)
            break
        end
        
        -- Normalize direction to goal
        local goal_dir_x = goal_dx / goal_distance
        local goal_dir_y = goal_dy / goal_distance
        
        -- Calculate next ideal position
        local ideal_next = {
            x = current.x + goal_dir_x * step_size,
            y = current.y + goal_dir_y * step_size
        }
        
        -- Check if this ideal position conflicts with any district
        local conflicting_district = HighwayNS.findConflictingDistrict(ideal_next, districts, buffer)
        
        if conflicting_district then
            -- We need to curve around this district
            local curve_point = HighwayNS.calculateCurveAroundDistrict(
                current, 
                ideal_next, 
                conflicting_district,
                curve_distance
            )
            table.insert(path, curve_point)
            current = curve_point
        else
            -- No conflict, proceed normally
            table.insert(path, ideal_next)
            current = ideal_next
        end
        
        -- Safety check
        if #path > 40 then
            table.insert(path, end_point)
            break
        end
    end
    
    -- Smooth out sharp angles in the final path
    local PathSmoother = require("models.generators.path_smoother")
    local smoothed_path = PathSmoother.smoothSharpAngles(path)
    return smoothed_path
end

function HighwayNS.findConflictingDistrict(point, districts, buffer)
    for _, district in ipairs(districts) do
        -- Check if point is too close to this district
        local dist_center_x = district.x + district.w / 2
        local dist_center_y = district.y + district.h / 2
        
        local distance = math.sqrt(
            (point.x - dist_center_x)^2 + (point.y - dist_center_y)^2
        )
        
        if distance < buffer then
            return district
        end
    end
    
    return nil
end

function HighwayNS.calculateCurveAroundDistrict(current, ideal_next, district, curve_distance)
    -- Calculate district center and boundaries
    local dist_center_x = district.x + district.w / 2
    local dist_center_y = district.y + district.h / 2
    
    -- Vector from district center to our ideal next position
    local away_x = ideal_next.x - dist_center_x
    local away_y = ideal_next.y - dist_center_y
    local away_length = math.sqrt(away_x * away_x + away_y * away_y)
    
    if away_length > 0 then
        -- Normalize the "away" vector
        away_x = away_x / away_length
        away_y = away_y / away_length
        
        -- Create a curve point that goes around the district
        local curve_x = dist_center_x + away_x * curve_distance
        local curve_y = dist_center_y + away_y * curve_distance
        
        -- For vertical highways, prefer curving left/right more than up/down
        curve_y = ideal_next.y * 0.7 + curve_y * 0.3
        
        return {x = curve_x, y = curve_y}
    else
        -- Fallback if calculation fails
        return ideal_next
    end
end

return HighwayNS