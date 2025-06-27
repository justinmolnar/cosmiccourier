-- services/BlockSubdivisionService.lua
-- COMPLETE FIXED VERSION with proper array indexing

local BlockSubdivisionService = {}

local ZONE_BLOCK_SIZE_FACTORS = {
    -- zone = { min_divisor, max_divisor } -- smaller divisors = smaller blocks = denser streets
    commercial = { min = 20, max = 10 },
    residential_north = { min = 25, max = 12 },
    residential_south = { min = 28, max = 14 },
    industrial_heavy = { min = 40, max = 25 },
    industrial_light = { min = 35, max = 20 },
    university = { min = 30, max = 18 },
    medical = { min = 22, max = 11 },
    entertainment = { min = 18, max = 9 },
    waterfront = { min = 35, max = 20 },
    warehouse = { min = 45, max = 28 },
    tech = { min = 20, max = 10 },
    park_central = { min = 50, max = 30 },
    park_nature = { min = 60, max = 35 },
    -- default
    default = { min = 25, max = 12 }
}

function BlockSubdivisionService._getBlockSizeForZone(zone_type, map_width, map_height)
    local factors = ZONE_BLOCK_SIZE_FACTORS[zone_type] or ZONE_BLOCK_SIZE_FACTORS.default
    local map_diagonal = math.sqrt(map_width^2 + map_height^2)

    local min_size = math.max(4, math.floor(map_diagonal / factors.min))
    local max_size = math.max(8, math.floor(map_diagonal / factors.max))

    -- Ensure min is not greater than max and there's a valid range
    if min_size >= max_size then
        min_size = math.max(4, max_size - 4)
    end
    
    print(string.format("Zone '%s' block size: min=%d, max=%d", zone_type, min_size, max_size))

    return { min_size = min_size, max_size = max_size }
end

function BlockSubdivisionService.generateStreets(city_grid, zone_grid, arterial_paths, params)
    print("=== BlockSubdivisionService.generateStreets START ===")

    local C_MAP = require("data.constants").MAP
    local width, height = #city_grid[1], #city_grid

    local downtown_w = math.min(width, C_MAP.DOWNTOWN_GRID_WIDTH)
    local downtown_h = math.min(height, C_MAP.DOWNTOWN_GRID_HEIGHT)

    local downtown_district = {
        x1 = math.floor((width - downtown_w) / 2) + 1,
        y1 = math.floor((height - downtown_h) / 2) + 1,
        x2 = math.floor((width - downtown_w) / 2) + downtown_w,
        y2 = math.floor((height - downtown_h) / 2) + downtown_h
    }

    print("DOWNTOWN DEBUG: District bounds (" .. downtown_district.x1 .. "," .. downtown_district.y1 .. ") to (" .. downtown_district.x2 .. "," .. downtown_district.y2 .. ")")
    print("DOWNTOWN DEBUG: Size " .. downtown_w .. "x" .. downtown_h .. " = " .. (downtown_w * downtown_h) .. " total tiles")

    local all_blocks = {}
    local downtown_blocks = {}
    
    -- ULTRA-AGGRESSIVE downtown subdivision
    print("--- Subdividing Downtown with FORCED small blocks ---")
    local debug_info = BlockSubdivisionService._recursiveSplitBlock(downtown_district, 2, 3, 0, downtown_blocks)
    
    print("DOWNTOWN SUBDIVISION RESULTS:")
    print("  Final blocks created: " .. #downtown_blocks)
    
    -- If still too few blocks, force even smaller
    if #downtown_blocks < 100 then
        print("WARNING: Only " .. #downtown_blocks .. " blocks, forcing 2x2 maximum...")
        downtown_blocks = {}
        BlockSubdivisionService._recursiveSplitBlock(downtown_district, 2, 2, 0, downtown_blocks)
        print("FORCED 2x2: Created " .. #downtown_blocks .. " blocks")
    end
    
    for _, block in ipairs(downtown_blocks) do
        table.insert(all_blocks, block)
    end

    local regions = BlockSubdivisionService._findArterialRegionsExcludeDowntown(city_grid, zone_grid, width, height, downtown_district)
    
    for region_idx, region in ipairs(regions) do
        local zone_type = region.zone or "residential_north"
        local zone_params = BlockSubdivisionService._getBlockSizeForZone(zone_type, width, height)
        local region_blocks = BlockSubdivisionService._generateProperBlocks(region, zone_params.min_size, zone_params.max_size)
        for _, block in ipairs(region_blocks) do
            table.insert(all_blocks, block)
        end
    end

    local street_segments = BlockSubdivisionService._convertBlocksToStreetSegments(all_blocks, width, height)
    BlockSubdivisionService._drawStreetsToGrid(city_grid, street_segments, width, height)

    Game.street_segments = street_segments
    Game.street_intersections = BlockSubdivisionService._findEdgeIntersections(street_segments)

    print("=== BlockSubdivisionService.generateStreets COMPLETE ===")
    print("Total blocks: " .. #all_blocks .. ", Downtown blocks: " .. #downtown_blocks .. ", Outer regions: " .. #regions)
    return true
end

-- FIXED: Find regions but exclude downtown (proper array indexing)
function BlockSubdivisionService._findArterialRegionsExcludeDowntown(city_grid, zone_grid, width, height, downtown_district)
    print("Finding arterial regions (excluding downtown)...")
    local regions = {}
    local visited = {}
    
    -- FIXED: Proper 2D array initialization
    for y = 1, height do
        visited[y] = {}
        for x = 1, width do
            visited[y][x] = false
        end
    end
    
    -- Helper function to check if point is in downtown
    local function isInDowntown(x, y)
        return x >= downtown_district.x1 and x <= downtown_district.x2 and 
               y >= downtown_district.y1 and y <= downtown_district.y2
    end

    for y = 1, height do
        for x = 1, width do
            -- SKIP if in downtown, arterial, or already visited
            if not visited[y][x] and not isInDowntown(x, y) and city_grid[y][x].type ~= "arterial" then
                local region = BlockSubdivisionService._floodFillRegionExcludeDowntown(city_grid, zone_grid, visited, x, y, width, height, isInDowntown)
                if region and #region.cells > 10 then
                    table.insert(regions, region)
                end
            end
        end
    end
    
    print("Found " .. #regions .. " non-downtown regions to subdivide")
    return regions
end

-- FIXED: Flood fill that respects downtown boundaries
function BlockSubdivisionService._floodFillRegionExcludeDowntown(city_grid, zone_grid, visited, start_x, start_y, width, height, isInDowntown)
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

    print("  Depth " .. depth .. ": Block (" .. block.x1 .. "," .. block.y1 .. ") to (" .. block.x2 .. "," .. block.y2 .. ") size " .. width .. "x" .. height)

    -- Stop if block is small enough or we've gone too deep
    if (width <= max_block_size and height <= max_block_size) then
        print("  Depth " .. depth .. ": KEEPING block (size limit reached)")
        table.insert(blocks, block)
        return
    end
    
    if (width <= min_block_size * 2 or height <= min_block_size * 2) then
        print("  Depth " .. depth .. ": KEEPING block (too narrow to split: " .. width .. "x" .. height .. ")")
        table.insert(blocks, block)
        return
    end
    
    if depth > 12 then
        print("  Depth " .. depth .. ": KEEPING block (max depth reached)")
        table.insert(blocks, block)
        return
    end

    -- Force splitting for large blocks
    local force_split = (width > 8 or height > 8)
    
    -- Decide split direction
    local split_vertical = false
    if width > height * 1.2 then
        split_vertical = true
        print("  Depth " .. depth .. ": Splitting VERTICALLY (wide block)")
    elseif height > width * 1.2 then
        split_vertical = false
        print("  Depth " .. depth .. ": Splitting HORIZONTALLY (tall block)")
    else
        split_vertical = love.math.random() < 0.5
        print("  Depth " .. depth .. ": Splitting " .. (split_vertical and "VERTICALLY" or "HORIZONTALLY") .. " (random)")
    end

    if split_vertical then
        local min_split = block.x1 + min_block_size - 1
        local max_split = block.x2 - min_block_size + 1
        if min_split >= max_split then
            print("  Depth " .. depth .. ": FAILED vertical split (not enough space)")
            table.insert(blocks, block)
            return
        end

        local split_x = love.math.random(min_split, max_split)
        print("  Depth " .. depth .. ": Splitting at x=" .. split_x)

        local left_block = {x1 = block.x1, y1 = block.y1, x2 = split_x, y2 = block.y2}
        local right_block = {x1 = split_x + 2, y1 = block.y1, x2 = block.x2, y2 = block.y2}

        BlockSubdivisionService._recursiveSplitBlock(left_block, min_block_size, max_block_size, depth + 1, blocks)
        BlockSubdivisionService._recursiveSplitBlock(right_block, min_block_size, max_block_size, depth + 1, blocks)

    else
        local min_split = block.y1 + min_block_size - 1
        local max_split = block.y2 - min_block_size + 1
        if min_split >= max_split then
            print("  Depth " .. depth .. ": FAILED horizontal split (not enough space)")
            table.insert(blocks, block)
            return
        end

        local split_y = love.math.random(min_split, max_split)
        print("  Depth " .. depth .. ": Splitting at y=" .. split_y)

        local top_block = {x1 = block.x1, y1 = block.y1, x2 = block.x2, y2 = split_y}
        local bottom_block = {x1 = block.x1, y1 = split_y + 2, x2 = block.x2, y2 = block.y2}

        BlockSubdivisionService._recursiveSplitBlock(top_block, min_block_size, max_block_size, depth + 1, blocks)
        BlockSubdivisionService._recursiveSplitBlock(bottom_block, min_block_size, max_block_size, depth + 1, blocks)
    end
end

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

function BlockSubdivisionService._drawStreetsToGrid(city_grid, street_segments, width, height)
    print("Drawing " .. #street_segments .. " street segments onto the main grid...")
    
    -- Calculate downtown bounds
    local C_MAP = require("data.constants").MAP
    local downtown_w = math.min(width, C_MAP.DOWNTOWN_GRID_WIDTH)
    local downtown_h = math.min(height, C_MAP.DOWNTOWN_GRID_HEIGHT)
    local downtown_bounds = {
        x1 = math.floor((width - downtown_w) / 2) + 1,
        y1 = math.floor((height - downtown_h) / 2) + 1,
        x2 = math.floor((width - downtown_w) / 2) + downtown_w,
        y2 = math.floor((height - downtown_h) / 2) + downtown_h
    }
    
    for _, segment in ipairs(street_segments) do
        if segment.type == "horizontal" then
            for x = segment.x1, segment.x2 do
                if x >= 1 and x <= width and segment.y >= 1 and segment.y <= height then
                    if city_grid[segment.y][x].type ~= "arterial" then
                        -- Use downtown_road in downtown area, regular road elsewhere
                        local is_downtown = (x >= downtown_bounds.x1 and x <= downtown_bounds.x2 and 
                                           segment.y >= downtown_bounds.y1 and segment.y <= downtown_bounds.y2)
                        city_grid[segment.y][x] = { type = is_downtown and "downtown_road" or "road" }
                    end
                end
            end
        elseif segment.type == "vertical" then
            for y = segment.y1, segment.y2 do
                if y >= 1 and y <= height and segment.x >= 1 and segment.x <= width then
                    if city_grid[y][segment.x].type ~= "arterial" then
                        -- Use downtown_road in downtown area, regular road elsewhere
                        local is_downtown = (segment.x >= downtown_bounds.x1 and segment.x <= downtown_bounds.x2 and 
                                           y >= downtown_bounds.y1 and y <= downtown_bounds.y2)
                        city_grid[y][segment.x] = { type = is_downtown and "downtown_road" or "road" }
                    end
                end
            end
        end
    end
end

function BlockSubdivisionService._fillGridWithPlots(city_grid, zone_grid, width, height)
    for y = 1, height do
        for x = 1, width do
            local tile = city_grid[y][x]
            -- THE FIX: Also check for "downtown_road" to prevent it from being paved over
            if tile.type ~= "arterial" and tile.type ~= "road" and tile.type ~= "downtown_road" then
                local zone = zone_grid and zone_grid[y] and zone_grid[y][x]
                if zone and string.find(zone, "park") then
                    tile.type = "grass"
                else
                    tile.type = "plot"
                end
            end
        end
    end
end

return BlockSubdivisionService