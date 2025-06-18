-- game/map.lua (Updated for clean MVC structure and variable grid sizes)
local Map = {}
Map.__index = Map

local function inBounds(x, y, width, height)
    return x >= 1 and x <= width and y >= 1 and y <= height
end

local function createGrid(width, height)
    local grid = {}
    for y = 1, height do
        grid[y] = {}
        for x = 1, width do
            grid[y][x] = { type = "grass" }
        end
    end
    return grid
end

function Map:new(C)
    local instance = setmetatable({}, Map)
    instance.C = C
    instance.grid = {}
    instance.building_plots = {}
    instance.current_scale = C.MAP.SCALES.DOWNTOWN
    instance.scale_grids = {}
    instance.scale_building_plots = {}
    instance.transition_state = {
        active = false,
        timer = 0,
        duration = C.ZOOM.TRANSITION_DURATION,
        from_scale = 1,
        to_scale = 1,
        progress = 0
    }
    return instance
end

function Map:generate()
    local C = self.C.MAP
    print("Generating map at scale:", C.SCALE_NAMES[self.current_scale])
    
    if self.current_scale == C.SCALES.DOWNTOWN then
        self:generateDowntown()
    elseif self.current_scale == C.SCALES.CITY then
        self:generateCity()
    else
        -- For future scales (region, planet), use downtown generation for now
        self:generateDowntown()
    end
    
    -- Store this scale's data
    self.scale_grids[self.current_scale] = self.grid
    self.scale_building_plots[self.current_scale] = self.building_plots
    
    print("Map generation complete at", C.SCALE_NAMES[self.current_scale], "scale. Found", #self.building_plots, "building plots.")
end

function Map:generateDowntown()
    local C = self.C.MAP
    self.grid = createGrid(C.DOWNTOWN_GRID_WIDTH, C.DOWNTOWN_GRID_HEIGHT)
    self.building_plots = {}
    
    -- Original downtown generation logic
    local mid_x, mid_y = math.floor(C.DOWNTOWN_GRID_WIDTH/2), math.floor(C.DOWNTOWN_GRID_HEIGHT/2)
    for y=1,C.DOWNTOWN_GRID_HEIGHT do self.grid[y][mid_x].type="road" end
    for x=1,C.DOWNTOWN_GRID_WIDTH do self.grid[mid_y][x].type="road" end
    for i=1,C.NUM_SECONDARY_ROADS do
        local sx,sy=mid_x,mid_y; if love.math.random(1,2)==1 then sx=love.math.random(1,C.DOWNTOWN_GRID_WIDTH) else sy=love.math.random(1,C.DOWNTOWN_GRID_HEIGHT) end
        local dir=love.math.random(0,3); local dx,dy=0,0; if dir==0 then dy=-1 elseif dir==1 then dy=1 end; if dir==2 then dx=-1 elseif dir==3 then dx=1 end
        local cx,cy=sx,sy; while cx >= 1 and cx <= C.DOWNTOWN_GRID_WIDTH and cy >= 1 and cy <= C.DOWNTOWN_GRID_HEIGHT do
            if self.grid[cy][cx].type=="road" and (cx~=sx or cy~=sy) then break end
            self.grid[cy][cx].type="road"
            cx,cy=cx+dx,cy+dy
        end
    end
    for y=1,C.DOWNTOWN_GRID_HEIGHT do for x=1,C.DOWNTOWN_GRID_WIDTH do if self.grid[y][x].type=="grass" then
        if (x > 1 and self.grid[y][x-1].type=="road") or
           (x < C.DOWNTOWN_GRID_WIDTH and self.grid[y][x+1].type=="road") or
           (y > 1 and self.grid[y-1][x].type=="road") or
           (y < C.DOWNTOWN_GRID_HEIGHT and self.grid[y+1][x].type=="road") then
               self.grid[y][x].type = "plot"; table.insert(self.building_plots,{x=x,y=y})
        end
    end end end
end

function Map:generateCity()
    local C = self.C.MAP
    
    -- Create large black grid for city scale
    self.grid = createGrid(C.CITY_GRID_WIDTH, C.CITY_GRID_HEIGHT)
    self.building_plots = {}
    
    -- Keep everything black (ungenerated) by default
    for y = 1, C.CITY_GRID_HEIGHT do
        for x = 1, C.CITY_GRID_WIDTH do
            self.grid[y][x].type = "black"  -- New tile type for ungenerated areas
        end
    end
    
    -- Place the downtown core in the center of the large grid
    self:embedDowntownInCity()
end

function Map:generateRandomCityBlocks()
    local C = self.C.MAP
    
    -- Define city block size
    local block_width = 20
    local block_height = 15
    
    -- Generate 3 random city blocks
    for i = 1, 3 do
        -- Pick random location, avoiding the downtown area
        local city_center_x = math.floor(C.CITY_GRID_WIDTH / 2)
        local city_center_y = math.floor(C.CITY_GRID_HEIGHT / 2)
        local downtown_radius = 40  -- Stay away from downtown
        
        local block_x, block_y
        local attempts = 0
        repeat
            block_x = love.math.random(block_width, C.CITY_GRID_WIDTH - block_width)
            block_y = love.math.random(block_height, C.CITY_GRID_HEIGHT - block_height)
            local distance_from_downtown = math.sqrt((block_x - city_center_x)^2 + (block_y - city_center_y)^2)
            attempts = attempts + 1
        until distance_from_downtown > downtown_radius or attempts > 50
        
        -- Generate the city block
        self:generateCityBlock(block_x, block_y, block_width, block_height)
        
        print("Generated city block", i, "at", block_x, block_y)
    end
end

function Map:generateCityBlock(start_x, start_y, width, height)
    local C = self.C.MAP
    
    -- Create a simple city block pattern
    for y = start_y, start_y + height - 1 do
        for x = start_x, start_x + width - 1 do
            if x >= 1 and x <= C.CITY_GRID_WIDTH and y >= 1 and y <= C.CITY_GRID_HEIGHT then
                -- Create border roads around the block
                if x == start_x or x == start_x + width - 1 or y == start_y or y == start_y + height - 1 then
                    self.grid[y][x].type = "road"
                else
                    -- Interior is mostly buildings with some green space
                    if love.math.random() < 0.7 then
                        self.grid[y][x].type = "plot"
                        table.insert(self.building_plots, {x = x, y = y})
                    else
                        self.grid[y][x].type = "grass"
                    end
                end
            end
        end
    end
    
    -- Add a few internal roads
    local mid_x = start_x + math.floor(width / 2)
    local mid_y = start_y + math.floor(height / 2)
    
    -- Vertical road through middle
    for y = start_y + 2, start_y + height - 3 do
        if y >= 1 and y <= C.CITY_GRID_HEIGHT and mid_x >= 1 and mid_x <= C.CITY_GRID_WIDTH then
            self.grid[y][mid_x].type = "road"
        end
    end
    
    -- Horizontal road through middle
    for x = start_x + 2, start_x + width - 3 do
        if x >= 1 and x <= C.CITY_GRID_WIDTH and mid_y >= 1 and mid_y <= C.CITY_GRID_HEIGHT then
            self.grid[mid_y][x].type = "road"
        end
    end
end

function Map:embedDowntownInCity()
    local C = self.C.MAP
    
    -- Generate downtown core data
    local downtown_grid = createGrid(C.DOWNTOWN_GRID_WIDTH, C.DOWNTOWN_GRID_HEIGHT)
    local downtown_plots = {}
    
    -- Use original downtown generation logic
    local mid_x, mid_y = math.floor(C.DOWNTOWN_GRID_WIDTH/2), math.floor(C.DOWNTOWN_GRID_HEIGHT/2)
    for y=1,C.DOWNTOWN_GRID_HEIGHT do downtown_grid[y][mid_x].type="road" end
    for x=1,C.DOWNTOWN_GRID_WIDTH do downtown_grid[mid_y][x].type="road" end
    for i=1,C.NUM_SECONDARY_ROADS do
        local sx,sy=mid_x,mid_y; if love.math.random(1,2)==1 then sx=love.math.random(1,C.DOWNTOWN_GRID_WIDTH) else sy=love.math.random(1,C.DOWNTOWN_GRID_HEIGHT) end
        local dir=love.math.random(0,3); local dx,dy=0,0; if dir==0 then dy=-1 elseif dir==1 then dy=1 end; if dir==2 then dx=-1 elseif dir==3 then dx=1 end
        local cx,cy=sx,sy; while cx >= 1 and cx <= C.DOWNTOWN_GRID_WIDTH and cy >= 1 and cy <= C.DOWNTOWN_GRID_HEIGHT do
            if downtown_grid[cy][cx].type=="road" and (cx~=sx or cy~=sy) then break end
            downtown_grid[cy][cx].type="road"
            cx,cy=cx+dx,cy+dy
        end
    end
    for y=1,C.DOWNTOWN_GRID_HEIGHT do for x=1,C.DOWNTOWN_GRID_WIDTH do if downtown_grid[y][x].type=="grass" then
        if (x > 1 and downtown_grid[y][x-1].type=="road") or
           (x < C.DOWNTOWN_GRID_WIDTH and downtown_grid[y][x+1].type=="road") or
           (y > 1 and downtown_grid[y-1][x].type=="road") or
           (y < C.DOWNTOWN_GRID_HEIGHT and downtown_grid[y+1][x].type=="road") then
               downtown_grid[y][x].type = "plot"; table.insert(downtown_plots,{x=x,y=y})
        end
    end end end
    
    -- Embed downtown in center of city grid
    local city_center_x = math.floor(C.CITY_GRID_WIDTH / 2)
    local city_center_y = math.floor(C.CITY_GRID_HEIGHT / 2)
    local downtown_start_x = city_center_x - math.floor(C.DOWNTOWN_GRID_WIDTH / 2)
    local downtown_start_y = city_center_y - math.floor(C.DOWNTOWN_GRID_HEIGHT / 2)
    
    for y = 1, C.DOWNTOWN_GRID_HEIGHT do
        for x = 1, C.DOWNTOWN_GRID_WIDTH do
            local city_x = downtown_start_x + x - 1
            local city_y = downtown_start_y + y - 1
            if city_x >= 1 and city_x <= C.CITY_GRID_WIDTH and city_y >= 1 and city_y <= C.CITY_GRID_HEIGHT then
                self.grid[city_y][city_x] = downtown_grid[y][x]
                -- Adjust building plot coordinates for city grid
                if downtown_grid[y][x].type == "plot" then
                    table.insert(self.building_plots, {x = city_x, y = city_y})
                end
            end
        end
    end
    
    -- Generate 3 random city blocks
    self:generateRandomCityBlocks()
end

function Map:setScale(new_scale)
    local C = self.C.MAP
    if not C.SCALE_NAMES[new_scale] then
        print("ERROR: Invalid map scale:", new_scale)
        return false
    end
    
    if new_scale == self.current_scale then
        return true -- Already at this scale
    end
    
    -- Store current scale data if it exists
    if self.grid and #self.grid > 0 then
        self.scale_grids[self.current_scale] = self.grid
        self.scale_building_plots[self.current_scale] = self.building_plots
    end
    
    -- Start transition
    self.transition_state.active = true
    self.transition_state.timer = 0
    self.transition_state.from_scale = self.current_scale
    self.transition_state.to_scale = new_scale
    self.transition_state.progress = 0
    
    -- Prepare target scale data
    if not self.scale_grids[new_scale] then
        -- Temporarily switch to generate the new scale
        local old_scale = self.current_scale
        self.current_scale = new_scale
        self:generate()
        self.current_scale = old_scale
    end
    
    print("Starting transition from", C.SCALE_NAMES[self.current_scale], "to", C.SCALE_NAMES[new_scale])
    return true
end

function Map:update(dt)
    if self.transition_state.active then
        self.transition_state.timer = self.transition_state.timer + dt
        self.transition_state.progress = self.transition_state.timer / self.transition_state.duration
        
        if self.transition_state.progress >= 1.0 then
            -- Transition complete
            self.transition_state.active = false
            self.transition_state.progress = 1.0
            
            -- Actually switch to the new scale
            self.current_scale = self.transition_state.to_scale
            self.grid = self.scale_grids[self.current_scale]
            self.building_plots = self.scale_building_plots[self.current_scale]
            
            local C = self.C.MAP
            print("Transition complete - now at", C.SCALE_NAMES[self.current_scale])
        end
    end
end

function Map:draw()
    local C = self.C.MAP 
    
    if self.transition_state.active then
        -- During transition, blend between scales
        love.graphics.push()
        
        -- Calculate transition effects
        local progress = self.transition_state.progress
        local eased_progress = 1 - (1 - progress) * (1 - progress) -- Ease out
        
        local grid_height = #self.grid
        local grid_width = grid_height > 0 and #self.grid[1] or 0
        local tile_size = self.current_scale == C.SCALES.DOWNTOWN and 16 or C.TILE_SIZE
        
        if self.transition_state.to_scale > self.transition_state.from_scale then
            -- Zooming out - shrink current view
            local scale_factor = 1.0 - (eased_progress * 0.7) -- Shrink to 30% size
            local center_x = (grid_width * tile_size) / 2
            local center_y = (grid_height * tile_size) / 2
            
            love.graphics.translate(center_x, center_y)
            love.graphics.scale(scale_factor, scale_factor)
            love.graphics.translate(-center_x, -center_y)
            
            -- Draw current scale with fade out
            love.graphics.setColor(1, 1, 1, 1 - eased_progress * 0.5)
        else
            -- Zooming in - grow target view
            local scale_factor = 0.3 + (eased_progress * 0.7) -- Grow from 30% to 100%
            local center_x = (grid_width * tile_size) / 2
            local center_y = (grid_height * tile_size) / 2
            
            love.graphics.translate(center_x, center_y)
            love.graphics.scale(scale_factor, scale_factor)
            love.graphics.translate(-center_x, -center_y)
            
            -- Draw target scale with fade in
            love.graphics.setColor(1, 1, 1, eased_progress)
        end
        
        -- Draw the transitioning map
        self:drawGrid()
        
        love.graphics.pop()
        
        -- Draw transition overlay
        love.graphics.setColor(0, 0, 0, 0.3 * math.sin(progress * math.pi))
        love.graphics.rectangle("fill", 0, 0, grid_width * tile_size, grid_height * tile_size)
        
    else
        -- Normal drawing
        love.graphics.setColor(1, 1, 1, 1)
        self:drawGrid()
    end
    
    love.graphics.setColor(1, 1, 1, 1) -- Reset color
end

function Map:drawGrid()
    local C = self.C.MAP
    local grid_height = #self.grid
    local grid_width = grid_height > 0 and #self.grid[1] or 0
    
    -- Use larger tile size for downtown, smaller for city
    local tile_size = self.current_scale == C.SCALES.DOWNTOWN and 16 or C.TILE_SIZE
    
    for y = 1, grid_height do
        for x = 1, grid_width do
            local tile = self.grid[y][x]
            if tile.type == "black" then
                love.graphics.setColor(0, 0, 0) -- Pure black for ungenerated areas
            elseif tile.type == "highway" then
                love.graphics.setColor(0.05, 0.05, 0.05)
            elseif tile.type == "arterial" then
                love.graphics.setColor(0.15, 0.15, 0.15)
            elseif tile.type == "road" then
                love.graphics.setColor(C.COLORS.ROAD)
            elseif tile.type == "plot" then
                love.graphics.setColor(C.COLORS.PLOT)
            else
                love.graphics.setColor(C.COLORS.GRASS)
            end
            love.graphics.rectangle("fill", (x-1) * tile_size, (y-1) * tile_size, tile_size, tile_size)
        end
    end
end

function Map:getCurrentScale()
    return self.current_scale
end

function Map:getScaleName()
    return self.C.MAP.SCALE_NAMES[self.current_scale] or "Unknown Scale"
end

function Map:findNearestRoadTile(plot)
    local grid_height = #self.grid
    local grid_width = grid_height > 0 and #self.grid[1] or 0
    local x, y = plot.x, plot.y
    local directions = {{x, y - 1}, {x, y + 1}, {x - 1, y}, {x + 1, y}}
    for _, dir in ipairs(directions) do
        local nx, ny = dir[1], dir[2]
        if nx >= 1 and nx <= grid_width and ny >= 1 and ny <= grid_height then
            local tile_type = self.grid[ny][nx].type
            if tile_type == "road" or tile_type == "highway" or tile_type == "arterial" then
                return {x = nx, y = ny}
            end
        end
    end
    return nil
end

function Map:getRandomBuildingPlot()
    if #self.building_plots>0 then return self.building_plots[love.math.random(1, #self.building_plots)] end; return nil
end

function Map:getPixelCoords(grid_x, grid_y)
    local C = self.C.MAP
    -- Use appropriate tile size based on current scale
    local tile_size = self.current_scale == C.SCALES.DOWNTOWN and 16 or C.TILE_SIZE
    local x = (grid_x - 0.5) * tile_size
    local y = (grid_y - 0.5) * tile_size
    return x, y
end

return Map