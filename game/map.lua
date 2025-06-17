-- game/map.lua (Updated for new structure)
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
    instance.C = C -- Store constants for other functions to use
    instance.grid = {}
    instance.building_plots = {}
    instance.tile_size = C.MAP.TILE_SIZE
    return instance
end

function Map:generate()
    local C = self.C.MAP
    print("Generating map...")
    self.grid = createGrid(C.GRID_WIDTH, C.GRID_HEIGHT)
    self.building_plots = {}
    
    local mid_x, mid_y = math.floor(C.GRID_WIDTH/2), math.floor(C.GRID_HEIGHT/2)
    for y=1,C.GRID_HEIGHT do self.grid[y][mid_x].type="road" end
    for x=1,C.GRID_WIDTH do self.grid[mid_y][x].type="road" end
    for i=1,C.NUM_SECONDARY_ROADS do
        local sx,sy=mid_x,mid_y; if love.math.random(1,2)==1 then sx=love.math.random(1,C.GRID_WIDTH) else sy=love.math.random(1,C.GRID_HEIGHT) end
        local dir=love.math.random(0,3); local dx,dy=0,0; if dir==0 then dy=-1 elseif dir==1 then dy=1 end; if dir==2 then dx=-1 elseif dir==3 then dx=1 end
        local cx,cy=sx,sy; while inBounds(cx,cy,C.GRID_WIDTH, C.GRID_HEIGHT) do
            if self.grid[cy][cx].type=="road" and (cx~=sx or cy~=sy) then break end
            self.grid[cy][cx].type="road"
            cx,cy=cx+dx,cy+dy
        end
    end
    for y=1,C.GRID_HEIGHT do for x=1,C.GRID_WIDTH do if self.grid[y][x].type=="grass" then
        if (inBounds(x,y-1,C.GRID_WIDTH,C.GRID_HEIGHT) and self.grid[y-1][x].type=="road") or
           (inBounds(x,y+1,C.GRID_WIDTH,C.GRID_HEIGHT) and self.grid[y+1][x].type=="road") or
           (inBounds(x-1,y,C.GRID_WIDTH,C.GRID_HEIGHT) and self.grid[y][x-1].type=="road") or
           (inBounds(x+1,y,C.GRID_WIDTH,C.GRID_HEIGHT) and self.grid[y][x+1].type=="road") then
               self.grid[y][x].type = "plot"; table.insert(self.building_plots,{x=x,y=y})
        end
    end end end
    print("Map generation complete. Found " .. #self.building_plots .. " building plots.")
end

function Map:findNearestRoadTile(plot)
    local C_MAP = self.C.MAP
    local x, y = plot.x, plot.y
    local directions = {{x, y - 1}, {x, y + 1}, {x - 1, y}, {x + 1, y}}
    for _, dir in ipairs(directions) do
        local nx, ny = dir[1], dir[2]
        -- BUG FIX: Pass the grid width and height to the inBounds function.
        if inBounds(nx, ny, C_MAP.GRID_WIDTH, C_MAP.GRID_HEIGHT) and self.grid[ny][nx].type == "road" then
            return {x = nx, y = ny}
        end
    end
    return nil -- Should not happen if plots are always next to roads
end

function Map:draw()
    -- Access constants from the 'self.C' table stored during initialization
    local C = self.C.MAP 
    
    -- Loop through the grid and draw a colored rectangle for each tile
    for y = 1, C.GRID_HEIGHT do
        for x = 1, C.GRID_WIDTH do
            local tile = self.grid[y][x]
            if tile.type == "road" then
                love.graphics.setColor(C.COLORS.ROAD)
            elseif tile.type == "plot" then
                love.graphics.setColor(C.COLORS.PLOT)
            else -- "grass"
                love.graphics.setColor(C.COLORS.GRASS)
            end
            love.graphics.rectangle("fill", (x-1) * self.tile_size, (y-1) * self.tile_size, self.tile_size, self.tile_size)
        end
    end
end

function Map:getRandomBuildingPlot()
    if #self.building_plots>0 then return self.building_plots[love.math.random(1, #self.building_plots)] end; return nil
end

function Map:getPixelCoords(grid_x, grid_y)
    local x = (grid_x - 0.5) * self.tile_size
    local y = (grid_y - 0.5) * self.tile_size
    return x, y
end

return Map