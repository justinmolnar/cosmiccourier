-- game/generators/highway_ew.lua
-- East-West Highway Generation Module

local HighwayEW = {}

function HighwayEW.generatePaths(map_w, map_h, all_districts, cities_data, params)
    local paths = {}
    local EXTENSION = 100 -- How far off-map the highway starts/ends

    -- Use debug parameters or defaults from the params table
    local highway_step_size = (params and params.highway_step_size) or 30
    local highway_curve_distance = (params and params.highway_curve_distance) or 50
    local highway_buffer = (params and params.highway_buffer) or 35
    local vertical_offset_range = (params and params.highway_y_offset) or 40

    if not cities_data or #cities_data == 0 then return {} end

    -- Sort cities by their horizontal position to connect them from left to right
    table.sort(cities_data, function(a, b) return a.center_x < b.center_x end)

    local path_nodes = {}
    local current_point

    -- 1. Start the highway from the left edge of the map, aligned with the first city
    local first_city = cities_data[1]
    local start_y = first_city.center_y + love.math.random(-vertical_offset_range, vertical_offset_range)
    local start_point = { x = -EXTENSION, y = start_y }

    -- 2. Route the highway to the ring road of the first city
    local target_point = HighwayEW.getRandomPointOnRingRoad(first_city.ring_road, all_districts)
    if not target_point then return {} end -- Cannot proceed if city has no ring road

    local segment = HighwayEW.createFlowingPath(start_point, target_point, all_districts, highway_step_size, highway_curve_distance, highway_buffer)
    for _, node in ipairs(segment) do table.insert(path_nodes, node) end
    current_point = target_point

    -- 3. Route the highway between all subsequent cities
    for i = 2, #cities_data do
        local next_city = cities_data[i]
        target_point = HighwayEW.getRandomPointOnRingRoad(next_city.ring_road, all_districts)
        if target_point then
            segment = HighwayEW.createFlowingPath(current_point, target_point, all_districts, highway_step_size, highway_curve_distance, highway_buffer)
            for _, node in ipairs(segment) do table.insert(path_nodes, node) end
            current_point = target_point
        end
    end

    -- 4. Route the highway from the last city to the right edge of the map
    local last_city = cities_data[#cities_data]
    local end_y = last_city.center_y + love.math.random(-vertical_offset_range, vertical_offset_range)
    local end_point = { x = map_w + EXTENSION, y = end_y }
    
    segment = HighwayEW.createFlowingPath(current_point, end_point, all_districts, highway_step_size, highway_curve_distance, highway_buffer)
    for _, node in ipairs(segment) do table.insert(path_nodes, node) end

    -- Add the completed, continuous path to the final list of paths
    table.insert(paths, path_nodes)
    
    return paths
end

function HighwayEW.createFlowingPath(start_point, end_point, districts, step_size, curve_distance, buffer)
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
        local conflicting_district = HighwayEW.findConflictingDistrict(ideal_next, districts, buffer)
        
        if conflicting_district then
            -- We need to curve around this district
            local curve_point = HighwayEW.calculateCurveAroundDistrict(
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

function HighwayEW.getRandomPointOnRingRoad(ring_road_nodes, all_districts)
    if not ring_road_nodes or #ring_road_nodes == 0 then return nil end

    local attempts = 0
    while attempts < 20 do
        local random_index = love.math.random(1, #ring_road_nodes)
        local point = ring_road_nodes[random_index]
        local is_in_district = false
        
        -- Check if the point is inside any district
        for _, district in ipairs(all_districts) do
            if point.x >= district.x and point.x < district.x + district.w and
               point.y >= district.y and point.y < district.y + district.h then
                is_in_district = true
                break
            end
        end

        if not is_in_district then
            return point -- Found a good point
        end
        
        attempts = attempts + 1
    end

    -- If we failed to find a point outside a district, just return a random one
    return ring_road_nodes[love.math.random(1, #ring_road_nodes)]
end

function HighwayEW.findConflictingDistrict(point, districts, buffer)
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

function HighwayEW.calculateCurveAroundDistrict(current, ideal_next, district, curve_distance)
    -- Calculate district center and boundaries
    -- THE FIX: Use math.floor to ensure integer coordinates
    local dist_center_x = district.x + math.floor(district.w / 2)
    local dist_center_y = district.y + math.floor(district.h / 2)
    
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
        
        -- For horizontal highways, prefer curving up/down more than left/right
        curve_x = ideal_next.x * 0.7 + curve_x * 0.3
        
        return {x = curve_x, y = curve_y}
    else
        -- Fallback if calculation fails
        return ideal_next
    end
end

return HighwayEW