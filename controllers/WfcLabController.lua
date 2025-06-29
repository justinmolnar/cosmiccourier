-- controllers/WfcLabController.lua
-- Updated with recursive block subdivision testing

local WfcLabController = {}
WfcLabController.__index = WfcLabController

function WfcLabController:new(game)
    local instance = setmetatable({}, WfcLabController)
    instance.game = game
    return instance
end

function WfcLabController:getHandledKeys()
    return {
        ["w"] = true, ["e"] = true, ["r"] = true, ["y"] = true,
        ["s"] = true, ["d"] = true, ["f"] = true,
        ["c"] = true, ["t"] = true, ["h"] = true, ["u"] = true,
        ["1"] = true, ["2"] = true, ["3"] = true, ["6"] = true,
        ["space"] = true
    }
end

function WfcLabController:keypressed(key)
    local Game = self.game

    if key == "space" then
        print("=== Loading Main City into Lab Visualization ===")
        if Game.main_city_debug_data and Game.main_city_debug_data.city_grid then
            Game.lab_grid = nil -- Ensure the old debug grid is cleared
            Game.wfc_final_grid = Game.main_city_debug_data.city_grid
            Game.lab_zone_grid = Game.main_city_debug_data.zone_grid
            Game.wfc_road_data = Game.main_city_debug_data.street_segments
            Game.arterial_control_paths = Game.main_city_debug_data.arterial_paths
            print("Main city data loaded into lab view.")
        else
            print("ERROR: No main city debug data found to display.")
        end
        return -- End the function here to not process other keys
    end

        if key == "6" then
        Game.show_flood_fill_regions = not Game.show_flood_fill_regions
        
        if Game.show_flood_fill_regions then
            print("=== SHOWING FLOOD FILL REGIONS ===")
            if Game.lab_grid and Game.lab_zone_grid then
                local regions = WfcLabController._debugFloodFillRegions(Game.lab_grid, Game.lab_zone_grid)
                Game.debug_flood_fill_regions = regions
                print("Generated " .. #regions .. " flood fill regions for visualization")
                for i, region in ipairs(regions) do
                    print("  Region " .. i .. ": " .. #region.cells .. " cells, zone: " .. (region.zone or "none"))
                end
            else
                print("ERROR: No lab grid available for flood fill analysis")
            end
        else
            print("=== HIDING FLOOD FILL REGIONS ===")
            Game.debug_flood_fill_regions = nil
        end
        return
    end

    if key == "w" or key == "e" then
        print("=== Testing WFC Grid Generation ===")
        local NewCityGenService = require("services.NewCityGenService")
        local wfc_params = { 
            width = (key == "w") and 32 or 64, 
            height = (key == "w") and 24 or 48, 
            use_wfc_for_zones = true,
            use_recursive_streets = false, 
            generate_arterials = false 
        }
        local result = NewCityGenService.generateDetailedCity(wfc_params)
        if result and result.city_grid then
            Game.lab_grid = result.city_grid
            Game.lab_zone_grid = result.zone_grid
            Game.arterial_control_paths = {} 
            Game.smooth_highway_overlay_paths = {}
            Game.wfc_final_grid = nil
            Game.wfc_road_data = nil
            print("WFC Zone Generation SUCCESS!")
        else
            print("WFC Zone Generation FAILED!")
        end
    end

    if key == "1" or key == "2" or key == "3" then
        print("=== Testing Larger WFC Grid Generation ===")
        local NewCityGenService = require("services.NewCityGenService")
        local width, height
        if key == "1" then
            width, height = 100, 200
        elseif key == "2" then
            width, height = 200, 100
        else -- key == "3"
            width, height = 250, 250
        end

        local wfc_params = { 
            width = width, 
            height = height, 
            use_wfc_for_zones = true,
            use_recursive_streets = true,
            generate_arterials = true,
        }
        local result = NewCityGenService.generateDetailedCity(wfc_params)
        if result and result.city_grid then
            Game.lab_grid = result.city_grid
            Game.lab_zone_grid = result.zone_grid
            Game.arterial_control_paths = result.arterial_paths or {}
            Game.smooth_highway_overlay_paths = {}
            Game.wfc_final_grid = nil
            Game.wfc_road_data = nil
            print("Large WFC Generation SUCCESS! (" .. width .. "x" .. height .. ")")
        else
            print("Large WFC Generation FAILED! (" .. width .. "x" .. height .. ")")
        end
    end
    
    if key == "r" then
        print("=== Generating and SAVING Arterial Roads ===")
        if Game.lab_grid and Game.lab_zone_grid then
            local NewCityGenService = require("services.NewCityGenService")
            local arterial_params = { min_edge_distance = 15 }
            local success, generated_paths = NewCityGenService.generateArterialsOnly(Game.lab_grid, Game.lab_zone_grid, arterial_params)
            if success then
                Game.arterial_control_paths = generated_paths
                print("Arterial road generation SUCCESS! Saved " .. #Game.arterial_control_paths .. " paths.")
            else
                print("Arterial road generation FAILED!")
            end
        else
            print("ERROR: No lab grid available. Press 'W' or 'E' first.")
        end
    end

    if key == "s" or key == "d" or key == "f" then
        print("=== Generating Streets with Recursive Subdivision ===")
        if Game.lab_grid and Game.lab_zone_grid then
            local NewCityGenService = require("services.NewCityGenService")
            local street_params = {}
            if key == "d" then
                street_params = { min_block_size = 2, max_block_size = 5 }
                print("Forcing SMALL block sizes (2-5)")
            elseif key == "f" then
                street_params = { min_block_size = 10, max_block_size = 20 }
                print("Forcing LARGE block sizes (10-20)")
            else
                print("Using DYNAMIC block sizes")
            end
            
            local success = NewCityGenService.generateStreetsOnly(Game.lab_grid, Game.lab_zone_grid, Game.arterial_control_paths or {}, street_params)
            if success then
                print("Street generation SUCCESS!")
            else
                print("Street generation FAILED!")
            end
        else
            print("ERROR: No lab grid available. Press 'W' or 'E' first.")
        end
    end

    if key == "y" then
        print("=== Visualizing Smoothed Overlay from 'R' key data ===")
        if not Game.arterial_control_paths or #Game.arterial_control_paths == 0 then
            print("ERROR: No arterial paths found. Press 'R' to generate them first.")
            return
        end
        Game.smooth_highway_overlay_paths = {}
        for _, control_points in ipairs(Game.arterial_control_paths) do
            local smooth_path = WfcLabController._smoothPathForOverlay(control_points)
            if #smooth_path > 1 then table.insert(Game.smooth_highway_overlay_paths, smooth_path) end
        end
        print("Generated " .. #Game.smooth_highway_overlay_paths .. " smooth overlays.")
    end

    if key == "u" then
        print("=== Full Pipeline Test: Zones + Arterials + Streets ===")
        local NewCityGenService = require("services.NewCityGenService")
        local full_params = { 
            width = 48, 
            height = 36, 
            use_wfc_for_zones = true,
            use_recursive_streets = true,
            generate_arterials = true,
        }
        local result = NewCityGenService.generateDetailedCity(full_params)
        if result and result.city_grid then
            Game.lab_grid = result.city_grid
            Game.lab_zone_grid = result.zone_grid
            Game.arterial_control_paths = result.arterial_paths or {}
            Game.smooth_highway_overlay_paths = {}
            Game.wfc_final_grid = nil
            Game.wfc_road_data = nil
            print("Full pipeline SUCCESS!")
        else
            print("Full pipeline FAILED!")
        end
    end
    
    if key == "c" then
        Game.lab_grid = nil
        Game.lab_zone_grid = nil
        Game.arterial_control_paths = {} 
        Game.smooth_highway_overlay_paths = {}
        Game.wfc_final_grid = nil
        Game.wfc_road_data = nil
        print("=== Cleared lab grid and all overlays ===")
    end
    
    if key == "t" then
        Game.show_districts = not Game.show_districts
        print("=== Toggled district visibility to: " .. tostring(Game.show_districts) .. " ===")
    end

    if key == "z" then
        print("=== MINIMAL TEST: Zones + Arterials Only ===")
        local NewCityGenService = require("services.NewCityGenService")
        local params = { width = 48, height = 36 }
        local result = NewCityGenService.generateMinimalTest(params)
        if result then
            Game.lab_grid = result.city_grid
            Game.lab_zone_grid = result.zone_grid
            Game.arterial_control_paths = result.arterial_paths
            print("Minimal test complete - check downtown area")
        end
    end
    
    if key == "h" then
        print("=== Recursive Block Subdivision Test Controls ===")
        print("W/E - Generate zones only (small/large)")
        print("1/2/3 - Generate larger grids (100x200, 200x100, 250x250)")
        print("R - Generate arterials on top of zones")
        print("S - Generate streets with recursive subdivision (normal blocks)")
        print("D - Generate streets with small blocks (2-5 size)")
        print("F - Generate streets with large blocks (5-12 size)")
        print("U - Full pipeline test (zones + arterials + streets)")
        print("Y - Show arterial overlay visualization")
        print("SPACE - Show a copy of the main game's generated city")
        print("C - Clear all")
        print("T - Toggle district zone visibility")
        print("H - Show this help")
    end
end

function WfcLabController._debugFloodFillRegions(city_grid, zone_grid)
    local width, height = #city_grid[1], #city_grid
    local regions = {}
    local visited = {}
    
    for y = 1, height do
        visited[y] = {}
        for x = 1, width do
            visited[y][x] = false
        end
    end
    
    local C_MAP = require("data.constants").MAP
    local downtown_w = math.min(width, C_MAP.DOWNTOWN_GRID_WIDTH)
    local downtown_h = math.min(height, C_MAP.DOWNTOWN_GRID_HEIGHT)
    local downtown_district = {
        x1 = math.floor((width - downtown_w) / 2) + 1,
        y1 = math.floor((height - downtown_h) / 2) + 1,
        x2 = math.floor((width - downtown_w) / 2) + downtown_w,
        y2 = math.floor((height - downtown_h) / 2) + downtown_h
    }
    
    local function isInDowntown(x, y)
        return x >= downtown_district.x1 and x <= downtown_district.x2 and 
               y >= downtown_district.y1 and y <= downtown_district.y2
    end
    
    print("DEBUG: Downtown bounds: (" .. downtown_district.x1 .. "," .. downtown_district.y1 .. ") to (" .. downtown_district.x2 .. "," .. downtown_district.y2 .. ")")
    
    local region_count = 0
    
    for y = 1, height do
        for x = 1, width do
            if not visited[y][x] and not isInDowntown(x, y) and city_grid[y][x].type ~= "arterial" then
                local region = WfcLabController._debugFloodFillSingleRegion(city_grid, zone_grid, visited, x, y, width, height, isInDowntown)
                if region and #region.cells > 10 then
                    region_count = region_count + 1
                    region.id = region_count
                    table.insert(regions, region)
                    print("  Found region " .. region_count .. ": " .. #region.cells .. " cells, zone: " .. (region.zone or "none"))
                end
            end
        end
    end
    
    return regions
end

-- New smoothing function specifically for overlay visualization
function WfcLabController._smoothPathForOverlay(points)
    if not points or #points < 2 then
        return points or {}
    end
    
    -- If we have less than 4 points, use simple linear interpolation
    if #points < 4 then
        return WfcLabController._linearInterpolation(points, 5)
    end
    
    -- For 4+ points, use a gentle Catmull-Rom spline with reduced segments
    local smooth_points = {}
    local segments_per_span = 8 -- Reduced from 10 for less jaggedness
    
    -- Add the first point
    table.insert(smooth_points, {x = points[1].x, y = points[1].y})
    
    -- Process each span between control points
    for i = 2, #points - 2 do
        local p0 = points[i-1]
        local p1 = points[i]
        local p2 = points[i+1]
        local p3 = points[i+2]
        
        for t = 0, 1, 1/segments_per_span do
            if t > 0 then -- Skip t=0 to avoid duplicating points
                local x = WfcLabController._catmullRom(p0.x, p1.x, p2.x, p3.x, t)
                local y = WfcLabController._catmullRom(p0.y, p1.y, p2.y, p3.y, t)
                table.insert(smooth_points, {x = math.floor(x + 0.5), y = math.floor(y + 0.5)})
            end
        end
    end
    
    -- Add the last point
    table.insert(smooth_points, {x = points[#points].x, y = points[#points].y})
    
    -- Remove consecutive duplicate points and fix lightning bolt patterns
    local deduplicated = WfcLabController._removeDuplicates(smooth_points)
    return WfcLabController._fixLightningBolts(deduplicated)
end

function WfcLabController._linearInterpolation(points, segments_per_span)
    local smooth_points = {}
    
    for i = 1, #points - 1 do
        local p1 = points[i]
        local p2 = points[i + 1]
        
        for t = 0, 1, 1/segments_per_span do
            local x = p1.x + (p2.x - p1.x) * t
            local y = p1.y + (p2.y - p1.y) * t
            table.insert(smooth_points, {x = math.floor(x + 0.5), y = math.floor(y + 0.5)})
        end
    end
    
    return WfcLabController._removeDuplicates(smooth_points)
end

function WfcLabController._catmullRom(p0, p1, p2, p3, t)
    local t2 = t * t
    local t3 = t2 * t
    
    return 0.5 * ((2 * p1) +
                  (-p0 + p2) * t +
                  (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 +
                  (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
end

function WfcLabController._removeDuplicates(points)
    if #points <= 1 then return points end
    
    local cleaned = {points[1]}
    
    for i = 2, #points do
        local prev = cleaned[#cleaned]
        local curr = points[i]
        
        -- Only add if it's different from the previous point
        if prev.x ~= curr.x or prev.y ~= curr.y then
            table.insert(cleaned, curr)
        end
    end
    
    return cleaned
end

function WfcLabController._fixLightningBolts(points)
    if #points <= 2 then return points end
    
    local fixed = {points[1]}
    
    for i = 2, #points - 1 do
        local prev = fixed[#fixed]
        local curr = points[i]
        local next = points[i + 1]
        
        -- Check if we have a "lightning bolt" pattern
        local dx1 = curr.x - prev.x
        local dy1 = curr.y - prev.y
        local dx2 = next.x - curr.x
        local dy2 = next.y - curr.y
        
        -- If both segments are short (1-2 tiles) and go in roughly opposite directions
        local dist1 = math.sqrt(dx1*dx1 + dy1*dy1)
        local dist2 = math.sqrt(dx2*dx2 + dy2*dy2)
        
        if dist1 <= 2 and dist2 <= 2 then
            -- Check if directions are opposing (creating a zigzag)
            local dot_product = dx1*dx2 + dy1*dy2
            if dot_product < 0 then -- Opposite directions
                -- Skip this middle point to create a direct diagonal
                goto skip_point
            end
        end
        
        table.insert(fixed, curr)
        ::skip_point::
    end
    
    table.insert(fixed, points[#points]) -- Always keep the last point
    return fixed
end

function WfcLabController._debugFloodFillSingleRegion(city_grid, zone_grid, visited, start_x, start_y, width, height, isInDowntown)
    local region = {
        cells = {},
        min_x = start_x, max_x = start_x,
        min_y = start_y, max_y = start_y,
        zone = nil
    }
    
    local queue = {{x = start_x, y = start_y}}
    local head = 1
    
    while head <= #queue do
        local current = queue[head]
        head = head + 1
        
        local x, y = current.x, current.y
        
        if x >= 1 and x <= width and y >= 1 and y <= height and 
           not visited[y][x] and not isInDowntown(x, y) and city_grid[y][x].type ~= "arterial" then
            
            visited[y][x] = true
            table.insert(region.cells, {x = x, y = y})
            
            region.min_x = math.min(region.min_x, x)
            region.max_x = math.max(region.max_x, x)
            region.min_y = math.min(region.min_y, y)
            region.max_y = math.max(region.max_y, y)
            
            if not region.zone and zone_grid and zone_grid[y] and zone_grid[y][x] then
                region.zone = zone_grid[y][x]
            end
            
            -- FIXED: Check downtown boundary before adding neighbors to queue
            local neighbors = {{x-1, y}, {x+1, y}, {x, y-1}, {x, y+1}}
            for _, neighbor in ipairs(neighbors) do
                local nx, ny = neighbor[1], neighbor[2]
                if nx >= 1 and nx <= width and ny >= 1 and ny <= height and
                not visited[ny][nx] and not isInDowntown(nx, ny) then
                    table.insert(queue, {x = nx, y = ny})
                end
            end
        end
    end
    
    return region
end

return WfcLabController