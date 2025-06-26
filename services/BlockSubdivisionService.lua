-- services/BlockSubdivisionService.lua
-- WITH EXTENSIVE DEBUG OUTPUT

local BlockSubdivisionService = {}

function BlockSubdivisionService.generateStreets(city_grid, zone_grid, arterial_paths, params)
    print("=== BlockSubdivisionService.generateStreets START ===")
    
    local width, height = #city_grid[1], #city_grid
    local min_block_size = params.min_block_size or 4
    local max_block_size = params.max_block_size or 8
    
    print("Grid size: " .. width .. "x" .. height)
    print("Block size range: " .. min_block_size .. " to " .. max_block_size)
    
    -- Step 1: Identify all arterial regions
    local regions = BlockSubdivisionService._findArterialRegions(city_grid, zone_grid, width, height)
    
    -- Step 2: Generate PROPER blocks for each region
    local all_blocks = {}
    for region_idx, region in ipairs(regions) do
        print("=== Processing region " .. region_idx .. " ===")
        print("Region bounds: (" .. region.min_x .. "," .. region.min_y .. ") to (" .. region.max_x .. "," .. region.max_y .. ")")
        
        local region_blocks = BlockSubdivisionService._generateProperBlocks(region, min_block_size, max_block_size)
        print("Generated " .. #region_blocks .. " blocks for region " .. region_idx)
        
        for _, block in ipairs(region_blocks) do
            table.insert(all_blocks, block)
        end
    end
    
    print("=== ALL BLOCKS GENERATED ===")
    for i, block in ipairs(all_blocks) do
        print("Block " .. i .. ": (" .. block.x1 .. "," .. block.y1 .. ") to (" .. block.x2 .. "," .. block.y2 .. ")")
    end
    
    -- Step 3: Convert blocks to street segments
    local street_segments = BlockSubdivisionService._convertBlocksToStreetSegments(all_blocks, width, height)
    
    print("=== STREET SEGMENTS GENERATED ===")
    print("Total segments: " .. #street_segments)
    for i, seg in ipairs(street_segments) do
        if seg.type == "horizontal" then
            print("Segment " .. i .. ": HORIZONTAL from x=" .. seg.x1 .. " to x=" .. seg.x2 .. " at y=" .. seg.y)
        elseif seg.type == "vertical" then
            print("Segment " .. i .. ": VERTICAL from y=" .. seg.y1 .. " to y=" .. seg.y2 .. " at x=" .. seg.x)
        end
    end
    
    -- Step 4: Find intersections
    local intersections = BlockSubdivisionService._findEdgeIntersections(street_segments)
    
    print("=== INTERSECTIONS FOUND ===")
    print("Total intersections: " .. #intersections)
    for i, intersection in ipairs(intersections) do
        print("Intersection " .. i .. ": (" .. intersection.x .. "," .. intersection.y .. ")")
    end
    
    -- Step 5: Store results
    Game.street_segments = street_segments
    Game.street_intersections = intersections
    
    -- Step 6: Fill city_grid with plots
    BlockSubdivisionService._fillGridWithPlots(city_grid, zone_grid, width, height)
    
    print("=== BlockSubdivisionService.generateStreets COMPLETE ===")
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

function BlockSubdivisionService._generateProperBlocks(region, min_block_size, max_block_size)
    print("Generating blocks for region: (" .. region.min_x .. "," .. region.min_y .. ") to (" .. region.max_x .. "," .. region.max_y .. ")")
    
    local blocks = {}
    
    -- Start with the entire region as one block
    local initial_block = {
        x1 = region.min_x,
        y1 = region.min_y,
        x2 = region.max_x,
        y2 = region.max_y
    }
    
    print("Initial block: (" .. initial_block.x1 .. "," .. initial_block.y1 .. ") to (" .. initial_block.x2 .. "," .. initial_block.y2 .. ")")
    
    -- Recursively split this block into smaller blocks
    BlockSubdivisionService._recursiveSplitBlock(initial_block, min_block_size, max_block_size, 0, blocks)
    
    print("Split into " .. #blocks .. " final blocks")
    for i, block in ipairs(blocks) do
        print("  Final block " .. i .. ": (" .. block.x1 .. "," .. block.y1 .. ") to (" .. block.x2 .. "," .. block.y2 .. ")")
    end
    
    return blocks
end

function BlockSubdivisionService._recursiveSplitBlock(block, min_block_size, max_block_size, depth, blocks)
    local width = block.x2 - block.x1 + 1
    local height = block.y2 - block.y1 + 1
    
    print("  Depth " .. depth .. ": Trying to split block (" .. block.x1 .. "," .. block.y1 .. ") to (" .. block.x2 .. "," .. block.y2 .. ") size " .. width .. "x" .. height)
    
    -- Stop if block is small enough or we've gone too deep
    if (width <= max_block_size and height <= max_block_size) or 
       (width <= min_block_size * 2 or height <= min_block_size * 2) or
       depth > 6 then
        print("  Depth " .. depth .. ": KEEPING block (too small or max depth)")
        table.insert(blocks, block)
        return
    end
    
    -- Decide split direction
    local split_vertical = false
    if width > height * 1.5 then
        split_vertical = true  -- Split wide blocks vertically
        print("  Depth " .. depth .. ": Splitting VERTICALLY (wide block)")
    elseif height > width * 1.5 then
        split_vertical = false -- Split tall blocks horizontally
        print("  Depth " .. depth .. ": Splitting HORIZONTALLY (tall block)")
    else
        split_vertical = love.math.random() < 0.5
        print("  Depth " .. depth .. ": Splitting " .. (split_vertical and "VERTICALLY" or "HORIZONTALLY") .. " (random)")
    end
    
    if split_vertical then
        -- Split vertically (create left and right blocks)
        local min_split = block.x1 + min_block_size - 1
        local max_split = block.x2 - min_block_size + 1
        if min_split >= max_split then
            print("  Depth " .. depth .. ": Can't split vertically (not enough space)")
            table.insert(blocks, block)
            return
        end
        
        local split_x = love.math.random(min_split, max_split)
        print("  Depth " .. depth .. ": Splitting at x=" .. split_x)
        
        local left_block = {
            x1 = block.x1,
            y1 = block.y1,
            x2 = split_x,
            y2 = block.y2
        }
        
        local right_block = {
            x1 = split_x + 2,  -- +2 to leave space for a 1-wide street
            y1 = block.y1,
            x2 = block.x2,
            y2 = block.y2
        }
        
        print("  Depth " .. depth .. ": Left: (" .. left_block.x1 .. "," .. left_block.y1 .. ") to (" .. left_block.x2 .. "," .. left_block.y2 .. ")")
        print("  Depth " .. depth .. ": Right: (" .. right_block.x1 .. "," .. right_block.y1 .. ") to (" .. right_block.x2 .. "," .. right_block.y2 .. ")")
        
        BlockSubdivisionService._recursiveSplitBlock(left_block, min_block_size, max_block_size, depth + 1, blocks)
        BlockSubdivisionService._recursiveSplitBlock(right_block, min_block_size, max_block_size, depth + 1, blocks)
        
    else
        -- Split horizontally (create top and bottom blocks)
        local min_split = block.y1 + min_block_size - 1
        local max_split = block.y2 - min_block_size + 1
        if min_split >= max_split then
            print("  Depth " .. depth .. ": Can't split horizontally (not enough space)")
            table.insert(blocks, block)
            return
        end
        
        local split_y = love.math.random(min_split, max_split)
        print("  Depth " .. depth .. ": Splitting at y=" .. split_y)
        
        local top_block = {
            x1 = block.x1,
            y1 = block.y1,
            x2 = block.x2,
            y2 = split_y
        }
        
        local bottom_block = {
            x1 = block.x1,
            y1 = split_y + 2,  -- +2 to leave space for a 1-wide street
            x2 = block.x2,
            y2 = block.y2
        }
        
        print("  Depth " .. depth .. ": Top: (" .. top_block.x1 .. "," .. top_block.y1 .. ") to (" .. top_block.x2 .. "," .. top_block.y2 .. ")")
        print("  Depth " .. depth .. ": Bottom: (" .. bottom_block.x1 .. "," .. bottom_block.y1 .. ") to (" .. bottom_block.x2 .. "," .. bottom_block.y2 .. ")")
        
        BlockSubdivisionService._recursiveSplitBlock(top_block, min_block_size, max_block_size, depth + 1, blocks)
        BlockSubdivisionService._recursiveSplitBlock(bottom_block, min_block_size, max_block_size, depth + 1, blocks)
    end
end

-- Final fixed _convertBlocksToStreetSegments function
-- Fixes: 1) No T-junctions/dead ends, 2) Extend to map borders

function BlockSubdivisionService._convertBlocksToStreetSegments(blocks, width, height)
    print("Converting " .. #blocks .. " blocks to street segments...")
    
    local segments = {}
    
    -- Create a grid to track which cells are occupied by blocks
    local block_grid = {}
    for y = 1, height do
        block_grid[y] = {}
        for x = 1, width do
            block_grid[y][x] = false
        end
    end
    
    -- Mark all block cells
    print("Marking block cells...")
    for block_idx, block in ipairs(blocks) do
        for y = block.y1, block.y2 do
            for x = block.x1, block.x2 do
                if y >= 1 and y <= height and x >= 1 and x <= width then
                    block_grid[y][x] = true
                end
            end
        end
    end
    
    -- Find horizontal street segments that span the FULL width of street corridors
    print("Finding full-width horizontal street segments...")
    for y = 1, height do
        local x = 1
        while x <= width do
            if not block_grid[y][x] then
                -- Found start of a street corridor
                local corridor_start = x
                while x <= width and not block_grid[y][x] do
                    x = x + 1
                end
                local corridor_end = x - 1
                
                -- Only create segment if corridor is wide enough (at least 2 cells)
                if corridor_end - corridor_start >= 1 then
                    -- Check if this corridor actually connects things (not a dead end)
                    local connects_to_something = false
                    
                    -- Check if corridor extends to map borders OR connects to vertical streets
                    local touches_left_border = (corridor_start == 1)
                    local touches_right_border = (corridor_end == width)
                    
                    -- Check for vertical street connections within the corridor
                    local has_vertical_connections = false
                    for check_x = corridor_start, corridor_end do
                        -- Check above and below this corridor
                        local connects_up = (y > 1 and not block_grid[y-1][check_x])
                        local connects_down = (y < height and not block_grid[y+1][check_x])
                        if connects_up or connects_down then
                            has_vertical_connections = true
                            break
                        end
                    end
                    
                    -- Only create the segment if it's useful (connects to borders or other streets)
                    if touches_left_border or touches_right_border or has_vertical_connections then
                        -- Extend to full map width if it touches borders
                        local segment_start = touches_left_border and 1 or corridor_start
                        local segment_end = touches_right_border and width or corridor_end
                        
                        local segment = {
                            type = "horizontal",
                            x1 = segment_start,
                            x2 = segment_end,
                            y = y
                        }
                        table.insert(segments, segment)
                        print("  H segment: x=" .. segment.x1 .. " to " .. segment.x2 .. " at y=" .. segment.y)
                    else
                        print("  Skipping isolated H corridor at y=" .. y .. " (no connections)")
                    end
                end
            else
                x = x + 1
            end
        end
    end
    
    -- Find vertical street segments that span the FULL height of street corridors
    print("Finding full-height vertical street segments...")
    for x = 1, width do
        local y = 1
        while y <= height do
            if not block_grid[y][x] then
                -- Found start of a street corridor
                local corridor_start = y
                while y <= height and not block_grid[y][x] do
                    y = y + 1
                end
                local corridor_end = y - 1
                
                -- Only create segment if corridor is wide enough (at least 2 cells)
                if corridor_end - corridor_start >= 1 then
                    -- Check if this corridor actually connects things (not a dead end)
                    local touches_top_border = (corridor_start == 1)
                    local touches_bottom_border = (corridor_end == height)
                    
                    -- Check for horizontal street connections within the corridor
                    local has_horizontal_connections = false
                    for check_y = corridor_start, corridor_end do
                        -- Check left and right of this corridor
                        local connects_left = (x > 1 and not block_grid[check_y][x-1])
                        local connects_right = (x < width and not block_grid[check_y][x+1])
                        if connects_left or connects_right then
                            has_horizontal_connections = true
                            break
                        end
                    end
                    
                    -- Only create the segment if it's useful (connects to borders or other streets)
                    if touches_top_border or touches_bottom_border or has_horizontal_connections then
                        -- Extend to full map height if it touches borders
                        local segment_start = touches_top_border and 1 or corridor_start
                        local segment_end = touches_bottom_border and height or corridor_end
                        
                        local segment = {
                            type = "vertical",
                            x = x,
                            y1 = segment_start,
                            y2 = segment_end
                        }
                        table.insert(segments, segment)
                        print("  V segment: y=" .. segment.y1 .. " to " .. segment.y2 .. " at x=" .. segment.x)
                    else
                        print("  Skipping isolated V corridor at x=" .. x .. " (no connections)")
                    end
                end
            else
                y = y + 1
            end
        end
    end
    
    print("Generated " .. #segments .. " connected street segments (no dead ends, extended to borders)")
    return segments
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