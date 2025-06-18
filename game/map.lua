-- game/map.lua (Final version with all features and bug fixes)
local Map = {}
Map.__index = Map

-- Helper function to check if a grid coordinate is within the map boundaries
local function inBounds(x, y, width, height)
    return x >= 1 and x <= width and y >= 1 and y <= height
end

-- Helper function to create a grid of a given size and type
local function createGrid(width, height, default_type)
    local grid = {}
    for y = 1, height do
        grid[y] = {}
        for x = 1, width do
            grid[y][x] = { type = default_type or "grass" }
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
    instance.transition_state = { active = false, timer = 0, duration = C.ZOOM.TRANSITION_DURATION, from_scale = 1, to_scale = 1, progress = 0 }
    return instance
end

-- =============================================================================
-- == MASTER GENERATION FUNCTION
-- =============================================================================
function Map:generate()
    print("Beginning full map generation process...")
    local downtown_grid = self:generateDowntownModule()
    self.scale_grids[self.C.MAP.SCALES.DOWNTOWN] = downtown_grid
    self.scale_building_plots[self.C.MAP.SCALES.DOWNTOWN] = self:getPlotsFromGrid(downtown_grid)
    print("Generated Downtown Core...")

    local city_grid = self:generateCityModule(downtown_grid)
    self.scale_grids[self.C.MAP.SCALES.CITY] = city_grid
    self.scale_building_plots[self.C.MAP.SCALES.CITY] = self:getPlotsFromGrid(city_grid)
    print("Generated Metropolitan Area...")

    self.grid = self.scale_grids[self.current_scale]
    self.building_plots = self.scale_building_plots[self.current_scale]
    
    print("Full map generation complete.")
end

function Map:generateDowntownModule()
    local C_MAP = self.C.MAP
    local w, h = C_MAP.DOWNTOWN_GRID_WIDTH, C_MAP.DOWNTOWN_GRID_HEIGHT
    local grid = createGrid(w, h, "plot")
    self:generateDistrictInternals(grid, {x=1, y=1, w=w, h=h}, "road", "plot", C_MAP.NUM_SECONDARY_ROADS)
    return grid
end

function Map:generateCityModule(downtown_grid_module)
    local C_MAP = self.C.MAP
    local W, H = C_MAP.CITY_GRID_WIDTH, C_MAP.CITY_GRID_HEIGHT
    local grid = createGrid(W, H, "plot")

    -- 1. Place Districts first, to define the city's shape
    local downtown_w, downtown_h = #downtown_grid_module[1], #downtown_grid_module
    local start_x, start_y = math.floor((W - downtown_w) / 2), math.floor((H - downtown_h) / 2)
    local downtown_dist = { x=start_x, y=start_y, w=downtown_w, h=downtown_h }
    local other_districts = self:placeDistricts(grid, 10, W, H, downtown_dist)
    local all_districts = {downtown_dist}
    for _,d in ipairs(other_districts) do table.insert(all_districts, d) end

    -- 2. Fill the districts with their internal road networks
    self:embedGrid(grid, downtown_grid_module, start_x, start_y, "downtown_road", "downtown_plot")
    for _, district in ipairs(other_districts) do
        self:generateDistrictInternals(grid, district, "road", "plot")
    end

    -- 3. Determine the nodes for the Ring Road based on the districts' corners
    local ring_road_nodes = self:getRingNodesFromDistricts(all_districts, W, H)
    
    -- 4. Draw the new district-defined Ring Road ON TOP
    if #ring_road_nodes > 3 then
        local center_x, center_y = W/2, H/2
        table.sort(ring_road_nodes, function(a,b) return math.atan2(a.y - center_y, a.x - center_x) < math.atan2(b.y - center_y, b.x - center_x) end)
        table.insert(ring_road_nodes, ring_road_nodes[1]); table.insert(ring_road_nodes, ring_road_nodes[2]); table.insert(ring_road_nodes, ring_road_nodes[3])
        local ring_road_curve = self:generateSplinePoints(ring_road_nodes, 10)
        for i = 1, #ring_road_curve - 1 do
            self:drawThickLine(grid, ring_road_curve[i].x, ring_road_curve[i].y, ring_road_curve[i+1].x, ring_road_curve[i+1].y, "highway", 3)
        end
    end

    -- 5. Draw structured highways ON TOP
    local highway_paths = self:generateHighwayPaths_Structured(W, H, 2, 2)
    for _, path_nodes in ipairs(highway_paths) do
        local highway_curve = self:generateSplinePoints(path_nodes, 10)
        for i = 1, #highway_curve - 1 do
            self:drawThickLine(grid, highway_curve[i].x, highway_curve[i].y, highway_curve[i+1].x, highway_curve[i+1].y, "highway", 3)
        end
    end
    
    -- 6. Finally, connect the districts to the highways
    local major_road_points = {}; for y=1,H do for x=1,W do if grid[y][x].type=='highway' then table.insert(major_road_points,{x=x,y=y}) end end end
    for _, district in ipairs(all_districts) do
        local cx, cy = math.floor(district.x+district.w/2), math.floor(district.y+district.h/2)
        local nearest = self:findNearestRoad_Optimized(cx, cy, major_road_points)
        if nearest then self:drawThickLine(grid, cx, cy, nearest.x, nearest.y, "road", 2) end
    end

    return grid
end

-- =============================================================================
-- == HELPER FUNCTIONS
-- =============================================================================

function Map:getRingNodesFromDistricts(districts, max_w, max_h)
    local nodes = {}
    local center_x, center_y = max_w / 2, max_h / 2
    local edge_threshold = max_w * 0.1
    local map_corners = {{x=1,y=1}, {x=max_w,y=1}, {x=1,y=max_h}, {x=max_w,y=max_h}}

    for _, dist in ipairs(districts) do
        if math.sqrt((dist.x+dist.w/2 - center_x)^2 + (dist.y+dist.h/2 - center_y)^2) >= max_w * 0.15 then
            local district_corners = {{x=dist.x, y=dist.y}, {x=dist.x+dist.w, y=dist.y}, {x=dist.x, y=dist.y+dist.h}, {x=dist.x+dist.w, y=dist.y+dist.h}}
            local primary_node, min_dist_sq = nil, math.huge
            for _, d_corner in ipairs(district_corners) do
                for _, m_corner in ipairs(map_corners) do
                    local dist_sq = (d_corner.x - m_corner.x)^2 + (d_corner.y - m_corner.y)^2
                    if dist_sq < min_dist_sq then min_dist_sq = dist_sq; primary_node = d_corner end
                end
            end
            
            if math.min(primary_node.x, primary_node.y, max_w - primary_node.x, max_h - primary_node.y) < edge_threshold then
                local inner_node, min_center_dist_sq = nil, math.huge
                for _, d_corner in ipairs(district_corners) do
                    local dist_sq = (d_corner.x - center_x)^2 + (d_corner.y - center_y)^2
                    if dist_sq < min_center_dist_sq then min_center_dist_sq = dist_sq; inner_node = d_corner end
                end
                table.insert(nodes, inner_node)
            else
                table.insert(nodes, primary_node)
            end
        end
    end
    return nodes
end

function Map:generateDistrictInternals(grid, district, road_type, plot_type, num_roads_override)
    local grid_w, grid_h = #grid[1], #grid
    for y=district.y, district.y + district.h -1 do
        for x=district.x, district.x + district.w -1 do
            if inBounds(x,y, grid_w, grid_h) then
                local current_type = grid[y][x].type
                if current_type ~= 'downtown_plot' and current_type ~= 'downtown_road' then grid[y][x].type = plot_type end
            end
        end
    end
    local num_secondary_roads = num_roads_override or (15 + love.math.random(0,15))
    for i=1,num_secondary_roads do
        local sx,sy = love.math.random(district.x, district.x + district.w - 1), love.math.random(district.y, district.y + district.h - 1)
        local dir,dx,dy = love.math.random(0,3), 0, 0
        if dir==0 then dy=-1 elseif dir==1 then dy=1 end; if dir==2 then dx=-1 elseif dir==3 then dx=1 end
        local cx,cy = sx,sy
        while inBounds(cx, cy, grid_w, grid_h) do
            if cx<district.x or cx>=district.x+district.w or cy<district.y or cy>=district.y+district.h then break end
            if grid[cy][cx].type == road_type and (cx~=sx or cy~=sy) then break end
            grid[cy][cx].type = road_type; cx,cy = cx+dx,cy+dy
        end
    end
end

function Map:getPlotsFromGrid(grid)
    local plots={}; if not grid or #grid==0 then return plots end; local h,w = #grid,#grid[1]
    for y=1,h do for x=1,w do if grid[y][x].type=='plot' or grid[y][x].type=='downtown_plot' then table.insert(plots,{x=x,y=y}) end end end
    return plots
end

function Map:embedGrid(large_grid, small_grid, start_x, start_y, road_type, plot_type)
    local small_h,small_w = #small_grid,#small_grid[1]; local large_w,large_h = #large_grid[1],#large_grid
    for y=1,small_h do for x=1,small_w do
        local tx,ty = start_x+x, start_y+y
        if inBounds(tx,ty,large_w,large_h) then
            if small_grid[y][x].type=='road' then large_grid[ty][tx].type=road_type else large_grid[ty][tx].type=plot_type end
        end
    end end
end

function Map:generateHighwayPaths_Structured(max_w, max_h, num_ns, num_ew)
    local paths={}; for i=1,num_ns do local p,x={},math.floor(max_w*(i/(num_ns+1)));table.insert(p,{x=x+love.math.random(-20,20),y=1});table.insert(p,{x=x+love.math.random(-20,20),y=max_h*0.5});table.insert(p,{x=x+love.math.random(-20,20),y=max_h});table.insert(p,1,{x=p[1].x,y=p[1].y-50});table.insert(p,{x=p[#p].x,y=p[#p].y+50});table.insert(paths,p) end
    for i=1,num_ew do local p,y={},math.floor(max_h*(i/(num_ew+1)));table.insert(p,{x=1,y=y+love.math.random(-20,20)});table.insert(p,{x=max_w*0.5,y=y+love.math.random(-20,20)});table.insert(p,{x=max_w,y=y+love.math.random(-20,20)});table.insert(p,1,{x=p[1].x-50,y=p[1].y});table.insert(p,{x=p[#p].x+50,y=p[#p].y});table.insert(paths,p) end
    return paths
end

function Map:generateSplinePoints(points, num_segments)
    local curve_points={}; if #points<4 then return points end
    for i=2,#points-2 do
        local p0,p1,p2,p3=points[i-1],points[i],points[i+1],points[i+2]
        for t=0,1,1/num_segments do
            local x=0.5*((2*p1.x)+(-p0.x+p2.x)*t+(2*p0.x-5*p1.x+4*p2.x-p3.x)*t*t+(-p0.x+3*p1.x-3*p2.x+p3.x)*t*t*t)
            local y=0.5*((2*p1.y)+(-p0.y+p2.y)*t+(2*p0.y-5*p1.y+4*p2.y-p3.y)*t*t+(-p0.y+3*p1.y-3*p2.y+p3.y)*t*t*t)
            table.insert(curve_points,{x=math.floor(x),y=math.floor(y)})
        end
    end
    return curve_points
end

-- *** RESTORED THIS FUNCTION ***
function Map:placeDistricts(grid, num_districts, max_w, max_h, downtown_dist)
    local districts={}; local attempts=0
    while #districts<num_districts and attempts<500 do
        local w,h=love.math.random(40,80),love.math.random(40,80)
        local x,y=love.math.random(1,max_w-w),love.math.random(1,max_h-h)
        local valid=true
        if x<downtown_dist.x+downtown_dist.w and x+w>downtown_dist.x and y<downtown_dist.y+downtown_dist.h and y+h>downtown_dist.y then valid=false end
        if valid then for i=1,5 do local cx,cy=love.math.random(x,x+w),love.math.random(y,y+h); if not inBounds(cx,cy,max_w,max_h) or grid[cy][cx].type~='plot' then valid=false; break end end end
        if valid then table.insert(districts,{x=x,y=y,w=w,h=h}) end
        attempts=attempts+1
    end
    return districts
end

function Map:findNearestRoad_Optimized(start_x, start_y, road_points)
    if not road_points or #road_points==0 then return nil end
    local best_point,min_dist_sq=nil,math.huge
    for _,p in ipairs(road_points) do local d=(p.x-start_x)^2+(p.y-start_y)^2; if d<min_dist_sq then min_dist_sq=d;best_point=p end end
    return best_point
end

function Map:drawThickLine(grid, x1, y1, x2, y2, road_type, thickness)
    if not grid or #grid==0 then return end
    local w,h=#grid[1],#grid; local dx,dy=math.abs(x2-x1),math.abs(y2-y1)
    local sx,sy=(x1<x2)and 1 or-1,(y1<y2)and 1 or-1; local err,x,y=dx-dy,x1,y1
    local half_thick=math.floor(thickness/2)
    while true do
        for i=-half_thick,half_thick do for j=-half_thick,half_thick do if inBounds(x+i,y+j,w,h)then grid[y+j][x+i].type=road_type end end end
        if x==x2 and y==y2 then break end
        local e2=2*err; if e2>-dy then err=err-dy;x=x+sx end; if e2<dx then err=err+dx;y=y+sy end
    end
end

function Map:setScale(new_scale)
    local C_MAP = self.C.MAP; if not C_MAP.SCALE_NAMES[new_scale] then print("ERROR: Invalid map scale:",new_scale) return false end
    if new_scale==self.current_scale then return true end
    self.transition_state.active=true; self.transition_state.timer=0; self.transition_state.from_scale=self.current_scale
    self.transition_state.to_scale=new_scale; self.transition_state.progress=0
    print("Starting transition from",C_MAP.SCALE_NAMES[self.current_scale],"to",C_MAP.SCALE_NAMES[new_scale])
    return true
end

function Map:update(dt)
    if self.transition_state.active then
        self.transition_state.timer=self.transition_state.timer+dt
        self.transition_state.progress=self.transition_state.timer/self.transition_state.duration
        if self.transition_state.progress>=1.0 then
            self.transition_state.active=false;self.transition_state.progress=1.0;self.current_scale=self.transition_state.to_scale
            self.grid=self.scale_grids[self.current_scale];self.building_plots=self.scale_building_plots[self.current_scale]
            print("Transition complete - now at",self.C.MAP.SCALE_NAMES[self.current_scale])
        end
    end
end

function Map:draw()
    if self.transition_state.active then
        local progress=self.transition_state.progress; local eased_progress=1-(1-progress)*(1-progress)
        self:drawGrid(self.scale_grids[self.transition_state.from_scale], 1-eased_progress)
        self:drawGrid(self.scale_grids[self.transition_state.to_scale], eased_progress)
    else
        self:drawGrid(self.grid, 1)
    end
    love.graphics.setColor(1,1,1,1)
end

function Map:drawGrid(grid, alpha)
    local C_MAP=self.C.MAP; if not grid or #grid==0 then return end
    local grid_h,grid_w=#grid,#grid[1]
    local tile_size=(#grid[1]==C_MAP.DOWNTOWN_GRID_WIDTH) and 16 or C_MAP.TILE_SIZE
    for y=1,grid_h do for x=1,grid_w do
        local tile=grid[y][x]; local color=C_MAP.COLORS.PLOT
        if tile.type=="road" or tile.type=="arterial" then color=C_MAP.COLORS.ROAD
        elseif tile.type=="highway" then color={0.1,0.1,0.1}
        elseif tile.type=="downtown_plot" then color=C_MAP.COLORS.DOWNTOWN_PLOT
        elseif tile.type=="downtown_road" then color=C_MAP.COLORS.DOWNTOWN_ROAD
        elseif tile.type=="grass" then color=C_MAP.COLORS.GRASS end
        love.graphics.setColor(color[1], color[2], color[3], alpha or 1)
        love.graphics.rectangle("fill",(x-1)*tile_size,(y-1)*tile_size,tile_size,tile_size)
    end end
end

function Map:getCurrentScale() return self.current_scale end
function Map:getScaleName() return self.C.MAP.SCALE_NAMES[self.current_scale] or "Unknown Scale" end

function Map:findNearestRoadTile(plot)
    if not plot then return nil end
    local grid=self.scale_grids[self.current_scale] or self.grid; if not grid or #grid==0 then return nil end
    local grid_h,grid_w=#grid,#grid[1]; local x,y=plot.x,plot.y
    for r=0,2 do for dy=-r,r do for dx=-r,r do if math.abs(dx)==r or math.abs(dy)==r then
        local nx,ny=x+dx,y+dy
        if inBounds(nx,ny,grid_w,grid_h) then if grid[ny][nx].type=="road" or grid[ny][nx].type=="highway" or grid[ny][nx].type=="downtown_road" then return {x=nx,y=ny} end end
    end end end end
    return nil
end

function Map:getRandomBuildingPlot()
    if #self.building_plots>0 then return self.building_plots[love.math.random(1,#self.building_plots)] end
    return nil
end

function Map:getPixelCoords(grid_x, grid_y)
    local grid=self.scale_grids[self.current_scale] or self.grid; if not grid or #grid==0 then return 0,0 end
    local C_MAP=self.C.MAP
    local tile_size=(#grid[1]==C_MAP.DOWNTOWN_GRID_WIDTH) and 16 or C_MAP.TILE_SIZE
    return (grid_x-0.5)*tile_size,(grid_y-0.5)*tile_size
end

return Map