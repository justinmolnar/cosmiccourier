-- services/BlockSubdivisionService.lua
-- Fixed: Generate roads ON grid to form blocks, then render them BETWEEN grid cells

local BlockSubdivisionService = {}

function BlockSubdivisionService.generateStreets(city_grid, zone_grid, arterial_paths, params)
    print("BlockSubdivisionService: Starting block-forming street generation with edge rendering")
    
    local width, height = #city_grid[1], #city_grid
    local min_block_size = params.min_block_size or 3
    local max_block_size = params.max_block_size or 9
    
    -- Step 1: Identify all arterial regions
    local regions = BlockSubdivisionService._findArterialRegions(city_grid, zone_grid, width, height)
    
    -- Step 2: Create a temporary grid to track where roads should be
    local road_grid = {}
    for y = 1, height do
        road_grid[y] = {}
        for x = 1, width do
            road_grid[y][x] = false
        end
    end
    
    -- Step 3: Generate roads ON the grid to form proper blocks
    for region_idx, region in ipairs(regions) do
        BlockSubdivisionService._generateRegionRoads(region, min_block_size, max_block_size, road_grid)
    end
    
    -- Step 4: Convert the road grid to edge segments (between grid cells)
    local street_segments = BlockSubdivisionService._convertRoadGridToEdgeSegments(road_grid, width, height)
    
    -- Step 5: Find intersections where edge segments meet
    local intersections = BlockSubdivisionService._findEdgeIntersections(street_segments)
    
    -- Step 6: Store results
    Game.street_segments = street_segments
    Game.street_intersections = intersections
    
    -- Step 7: Fill city_grid with plots (don't put roads on the actual grid)
    BlockSubdivisionService._fillGridWithPlots(city_grid, zone_grid, width, height)
    
    print("BlockSubdivisionService: Generated " .. #street_segments .. " edge segments forming enclosed blocks")
    return true
end

function BlockSubdivisionService._findArterialRegions(city_grid, zone_grid, width, height)
    print("Finding arterial regions...")
    local regions = {}
    local visited = {}
    
    for y = 1, height do
        visited[y] = {}
        for x = 1, width do
            visited[y][x] = false
        end
    end
    
    for y = 1, height do
        for x = 1, width do
            if not visited[y][x] and city_grid[y][x].type ~= "arterial" then
                local region = BlockSubdivisionService._floodFillRegion(city_grid, zone_grid, visited, x, y, width, height)
                if region and #region.cells > 10 then
                    table.insert(regions, region)
                end
            end
        end
    end
    
    print("Found " .. #regions .. " arterial regions to subdivide")
    return regions
end

function BlockSubdivisionService._floodFillRegion(city_grid, zone_grid, visited, start_x, start_y, width, height)
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
           not visited[y][x] and city_grid[y][x].type ~= "arterial" then
            
            visited[y][x] = true
            table.insert(region.cells, {x = x, y = y})
            
            region.min_x = math.min(region.min_x, x)
            region.max_x = math.max(region.max_x, x)
            region.min_y = math.min(region.min_y, y)
            region.max_y = math.max(region.max_y, y)
            
            if not region.zone and zone_grid and zone_grid[y] and zone_grid[y][x] then
                region.zone = zone_grid[y][x]
            end
            
            table.insert(queue, {x = x-1, y = y})
            table.insert(queue, {x = x+1, y = y})
            table.insert(queue, {x = x, y = y-1})
            table.insert(queue, {x = x, y = y+1})
        end
    end
    
    return region
end

function BlockSubdivisionService._generateRegionRoads(region, min_block_size, max_block_size, road_grid)
    local subdivision = {
        x1 = region.min_x,
        y1 = region.min_y,
        x2 = region.max_x,
        y2 = region.max_y
    }
    
    BlockSubdivisionService._recursiveSubdivideRoads(subdivision, min_block_size, max_block_size, 0, road_grid)
end

function BlockSubdivisionService._recursiveSubdivideRoads(area, min_block_size, max_block_size, depth, road_grid)
    local width = area.x2 - area.x1 + 1
    local height = area.y2 - area.y1 + 1
    
    if (width <= max_block_size and height <= max_block_size) or 
       (width < min_block_size * 2 + 1 and height < min_block_size * 2 + 1) or
       depth > 8 then
        return
    end
    
    local split_horizontal = false
    if width > height * 1.5 then
        split_horizontal = false
    elseif height > width * 1.5 then
        split_horizontal = true
    else
        split_horizontal = love.math.random() < 0.5
    end
    
    local split_pos
    if split_horizontal then
        local min_split = area.y1 + min_block_size
        local max_split = area.y2 - min_block_size
        if min_split >= max_split then return end
        
        split_pos = love.math.random(min_split, max_split)
        
        -- Mark road tiles horizontally
        for x = area.x1, area.x2 do
            road_grid[split_pos][x] = true
        end
        
        local area1 = {
            x1 = area.x1, y1 = area.y1,
            x2 = area.x2, y2 = split_pos - 1
        }
        local area2 = {
            x1 = area.x1, y1 = split_pos + 1,
            x2 = area.x2, y2 = area.y2
        }
        
        BlockSubdivisionService._recursiveSubdivideRoads(area1, min_block_size, max_block_size, depth + 1, road_grid)
        BlockSubdivisionService._recursiveSubdivideRoads(area2, min_block_size, max_block_size, depth + 1, road_grid)
        
    else
        local min_split = area.x1 + min_block_size
        local max_split = area.x2 - min_block_size
        if min_split >= max_split then return end
        
        split_pos = love.math.random(min_split, max_split)
        
        -- Mark road tiles vertically
        for y = area.y1, area.y2 do
            road_grid[y][split_pos] = true
        end
        
        local area1 = {
            x1 = area.x1, y1 = area.y1,
            x2 = split_pos - 1, y2 = area.y2
        }
        local area2 = {
            x1 = split_pos + 1, y1 = area.y1,
            x2 = area.x2, y2 = area.y2
        }
        
        BlockSubdivisionService._recursiveSubdivideRoads(area1, min_block_size, max_block_size, depth + 1, road_grid)
        BlockSubdivisionService._recursiveSubdivideRoads(area2, min_block_size, max_block_size, depth + 1, road_grid)
    end
end

function BlockSubdivisionService._convertRoadGridToEdgeSegments(road_grid, width, height)
    local segments = {}
    
    -- Convert horizontal roads to edge segments
    for y = 1, height do
        for x = 1, width do
            if road_grid[y][x] then
                -- Check if this is part of a horizontal road
                local has_left = x > 1 and road_grid[y][x-1]
                local has_right = x < width and road_grid[y][x+1]
                local has_up = y > 1 and road_grid[y-1][x]
                local has_down = y < height and road_grid[y+1][x]
                
                -- Create edge segments around this road tile
                -- Top edge (if no road above)
                if not has_up then
                    table.insert(segments, {
                        type = "horizontal",
                        x1 = x - 0.5,
                        x2 = x + 0.5,
                        y = y - 0.5
                    })
                end
                
                -- Bottom edge (if no road below)
                if not has_down then
                    table.insert(segments, {
                        type = "horizontal",
                        x1 = x - 0.5,
                        x2 = x + 0.5,
                        y = y + 0.5
                    })
                end
                
                -- Left edge (if no road to left)
                if not has_left then
                    table.insert(segments, {
                        type = "vertical",
                        x = x - 0.5,
                        y1 = y - 0.5,
                        y2 = y + 0.5
                    })
                end
                
                -- Right edge (if no road to right)
                if not has_right then
                    table.insert(segments, {
                        type = "vertical",
                        x = x + 0.5,
                        y1 = y - 0.5,
                        y2 = y + 0.5
                    })
                end
            end
        end
    end
    
    -- Merge adjacent segments to create longer continuous lines
    local merged_segments = BlockSubdivisionService._mergeAdjacentSegments(segments)
    
    print("Converted road grid to " .. #merged_segments .. " edge segments")
    return merged_segments
end

function BlockSubdivisionService._mergeAdjacentSegments(segments)
    local merged = {}
    local used = {}
    
    for i = 1, #segments do
        if not used[i] then
            local segment = segments[i]
            used[i] = true
            
            -- Try to extend this segment by merging adjacent segments
            local extended = true
            while extended do
                extended = false
                
                for j = 1, #segments do
                    if not used[j] and segments[j].type == segment.type then
                        local other = segments[j]
                        local tolerance = 0.01
                        
                        if segment.type == "horizontal" then
                            -- Check if horizontal segments are on the same line and adjacent
                            if math.abs(segment.y - other.y) < tolerance then
                                if math.abs(segment.x2 - other.x1) < tolerance then
                                    -- Extend segment to the right
                                    segment.x2 = other.x2
                                    used[j] = true
                                    extended = true
                                elseif math.abs(segment.x1 - other.x2) < tolerance then
                                    -- Extend segment to the left
                                    segment.x1 = other.x1
                                    used[j] = true
                                    extended = true
                                end
                            end
                        elseif segment.type == "vertical" then
                            -- Check if vertical segments are on the same line and adjacent
                            if math.abs(segment.x - other.x) < tolerance then
                                if math.abs(segment.y2 - other.y1) < tolerance then
                                    -- Extend segment downward
                                    segment.y2 = other.y2
                                    used[j] = true
                                    extended = true
                                elseif math.abs(segment.y1 - other.y2) < tolerance then
                                    -- Extend segment upward
                                    segment.y1 = other.y1
                                    used[j] = true
                                    extended = true
                                end
                            end
                        end
                    end
                end
            end
            
            table.insert(merged, segment)
        end
    end
    
    return merged
end

function BlockSubdivisionService._findEdgeIntersections(street_segments)
    local intersections = {}
    local tolerance = 0.01
    
    for i = 1, #street_segments do
        for j = i + 1, #street_segments do
            local seg1, seg2 = street_segments[i], street_segments[j]
            
            if seg1.type ~= seg2.type then
                local intersection = nil
                
                if seg1.type == "horizontal" and seg2.type == "vertical" then
                    local h_seg, v_seg = seg1, seg2
                    
                    if v_seg.x >= h_seg.x1 - tolerance and v_seg.x <= h_seg.x2 + tolerance and
                       h_seg.y >= v_seg.y1 - tolerance and h_seg.y <= v_seg.y2 + tolerance then
                        intersection = {
                            x = v_seg.x,
                            y = h_seg.y
                        }
                    end
                    
                elseif seg1.type == "vertical" and seg2.type == "horizontal" then
                    local v_seg, h_seg = seg1, seg2
                    
                    if v_seg.x >= h_seg.x1 - tolerance and v_seg.x <= h_seg.x2 + tolerance and
                       h_seg.y >= v_seg.y1 - tolerance and h_seg.y <= v_seg.y2 + tolerance then
                        intersection = {
                            x = v_seg.x,
                            y = h_seg.y
                        }
                    end
                end
                
                if intersection then
                    local is_duplicate = false
                    for _, existing in ipairs(intersections) do
                        if math.abs(existing.x - intersection.x) < tolerance and 
                           math.abs(existing.y - intersection.y) < tolerance then
                            is_duplicate = true
                            break
                        end
                    end
                    
                    if not is_duplicate then
                        table.insert(intersections, intersection)
                    end
                end
            end
        end
    end
    
    print("Found " .. #intersections .. " edge intersections")
    return intersections
end

function BlockSubdivisionService._fillGridWithPlots(city_grid, zone_grid, width, height)
    for y = 1, height do
        for x = 1, width do
            if city_grid[y][x].type ~= "arterial" then
                local zone = zone_grid and zone_grid[y] and zone_grid[y][x]
                if zone and string.find(zone, "park") then
                    city_grid[y][x] = { type = "grass" }
                else
                    city_grid[y][x] = { type = "plot" }
                end
            end
        end
    end
end

return BlockSubdivisionService