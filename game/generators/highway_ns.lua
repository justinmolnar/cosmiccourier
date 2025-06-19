-- game/generators/highway_ns.lua
-- North-South Highway Generation Module

local HighwayNS = {}

function HighwayNS.generatePaths(map_w, map_h, districts)
    local paths = {}
    local EXTENSION = 100
    
    -- 2 North-South highways at 33% and 67% of map width
    local ns_positions = {map_w * 0.33, map_w * 0.67}
    
    for _, x_pos in ipairs(ns_positions) do
        local path = HighwayNS.createFlowingPath(
            {x = x_pos, y = -EXTENSION}, 
            {x = x_pos, y = map_h + EXTENSION}, 
            districts
        )
        table.insert(paths, path)
    end
    
    return paths
end

function HighwayNS.createFlowingPath(start_point, end_point, districts)
    local path = {start_point}
    local current = {x = start_point.x, y = start_point.y}
    local STEP_SIZE = 30
    
    while true do
        -- Calculate where we want to go (straight toward goal)
        local goal_dx = end_point.x - current.x
        local goal_dy = end_point.y - current.y
        local goal_distance = math.sqrt(goal_dx * goal_dx + goal_dy * goal_dy)
        
        if goal_distance < STEP_SIZE * 1.5 then
            table.insert(path, end_point)
            break
        end
        
        -- Normalize direction to goal
        local goal_dir_x = goal_dx / goal_distance
        local goal_dir_y = goal_dy / goal_distance
        
        -- Calculate next ideal position
        local ideal_next = {
            x = current.x + goal_dir_x * STEP_SIZE,
            y = current.y + goal_dir_y * STEP_SIZE
        }
        
        -- Check if this ideal position conflicts with any district
        local conflicting_district = HighwayNS.findConflictingDistrict(ideal_next, districts)
        
        if conflicting_district then
            -- We need to curve around this district
            local curve_point = HighwayNS.calculateCurveAroundDistrict(
                current, 
                ideal_next, 
                conflicting_district
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
    local PathSmoother = require("game.generators.path_smoother")
    local smoothed_path = PathSmoother.smoothSharpAngles(path)
    return smoothed_path
end

function HighwayNS.findConflictingDistrict(point, districts)
    local BUFFER = 35  -- How close is too close
    
    for _, district in ipairs(districts) do
        -- Check if point is too close to this district
        local dist_center_x = district.x + district.w / 2
        local dist_center_y = district.y + district.h / 2
        
        local distance = math.sqrt(
            (point.x - dist_center_x)^2 + (point.y - dist_center_y)^2
        )
        
        if distance < BUFFER then
            return district
        end
    end
    
    return nil
end

function HighwayNS.calculateCurveAroundDistrict(current, ideal_next, district)
    -- Calculate district center and boundaries
    local dist_center_x = district.x + district.w / 2
    local dist_center_y = district.y + district.h / 2
    local CURVE_DISTANCE = 50  -- How far to curve around
    
    -- Vector from district center to our ideal next position
    local away_x = ideal_next.x - dist_center_x
    local away_y = ideal_next.y - dist_center_y
    local away_length = math.sqrt(away_x * away_x + away_y * away_y)
    
    if away_length > 0 then
        -- Normalize the "away" vector
        away_x = away_x / away_length
        away_y = away_y / away_length
        
        -- Create a curve point that goes around the district
        local curve_x = dist_center_x + away_x * CURVE_DISTANCE
        local curve_y = dist_center_y + away_y * CURVE_DISTANCE
        
        -- For vertical highways, prefer curving left/right more than up/down
        curve_y = ideal_next.y * 0.7 + curve_y * 0.3
        
        return {x = curve_x, y = curve_y}
    else
        -- Fallback if calculation fails
        return ideal_next
    end
end

return HighwayNS