-- services/ArterialRoadService.lua
-- Generates arterial roads that snake around districts using pathfinding

local ArterialRoadService = {}

-- Import pathfinding
local Pathfinder = require("lib.pathfinder")

-- NEW: Private function containing the core generation logic
function ArterialRoadService._calculateArterialPaths(zone_grid, params)
    local all_paths = {}
    local width, height = #zone_grid[1], #zone_grid
    local num_arterials = params.num_arterials or 4
    local min_distance_between_points = params.min_edge_distance or 15
    local cost_grid = ArterialRoadService._createCostGrid(zone_grid, width, height)
    local all_boundary_points = ArterialRoadService._findDistrictBoundaryPoints(zone_grid, width, height)
    local quadrant_coverage = { ["top-left"]=0, ["top-right"]=0, ["bottom-left"]=0, ["bottom-right"]=0 }

    -- Node Constraint Setup
    local downtown_node, largest_district_node, largest_district_info
    local downtown_bounds = ArterialRoadService._findZoneBounds(zone_grid, "downtown")
    if downtown_bounds then
        downtown_node = {
            x = love.math.random(downtown_bounds.min_x, downtown_bounds.max_x),
            y = love.math.random(downtown_bounds.min_y, downtown_bounds.max_y)
        }
    end
    largest_district_info = ArterialRoadService._findLargestDistrict(zone_grid, width, height)
    if largest_district_info then
        largest_district_node = largest_district_info.center
    end

    for i = 1, num_arterials do
        local final_path, entry_point, exit_point

        local start_quad_candidates = ArterialRoadService._findLeastServicedQuadrants(quadrant_coverage)
        local start_quad = start_quad_candidates[love.math.random(#start_quad_candidates)]
        local exit_quad = ArterialRoadService._findBestOpposingQuadrant(start_quad)
        
        local entry_edges = ArterialRoadService._getEdgesForQuadrant(start_quad)
        local exit_edges = ArterialRoadService._getEdgesForQuadrant(exit_quad)
        
        local constraint_node, specialized_cost_grid = nil, nil
        if i == 1 and downtown_node then
            constraint_node = downtown_node
            specialized_cost_grid = ArterialRoadService._createSpecializedCostGrid(cost_grid, zone_grid, {zone_name = "downtown", cost = 2})
        elseif i == 2 and largest_district_node then
            constraint_node = largest_district_node
            specialized_cost_grid = ArterialRoadService._createSpecializedCostGrid(cost_grid, zone_grid, {tiles = largest_district_info.tiles, cost = 2})
        end

        if constraint_node then
            entry_point = ArterialRoadService._getRandomEdgePoint(width, height, "entry", nil, nil, zone_grid, entry_edges, all_boundary_points)
            if entry_point then
                local path1 = ArterialRoadService._findArterialPath(specialized_cost_grid, entry_point, constraint_node, width, height)
                if path1 then
                    local incoming_direction = ArterialRoadService._getIncomingDirection(path1)
                    exit_point = ArterialRoadService._findBestExitPoint(constraint_node, incoming_direction, all_boundary_points, entry_point, exit_edges)
                    if exit_point then
                        local temp_cost_grid = ArterialRoadService._cloneCostGrid(specialized_cost_grid)
                        for _, node in ipairs(path1) do temp_cost_grid[node.y][node.x] = 9999 end
                        local path2 = ArterialRoadService._findArterialPath(temp_cost_grid, constraint_node, exit_point, width, height)
                        if path2 then
                            table.remove(path2, 1); final_path = path1; for _, node in ipairs(path2) do table.insert(final_path, node) end
                        end
                    end
                end
            end
        else
            entry_point = ArterialRoadService._getRandomEdgePoint(width, height, "entry", nil, nil, zone_grid, entry_edges, all_boundary_points)
            exit_point = ArterialRoadService._getRandomEdgePoint(width, height, "exit", entry_point, min_distance_between_points, zone_grid, exit_edges, all_boundary_points)
            if entry_point and exit_point then
                final_path = ArterialRoadService._findArterialPath(cost_grid, entry_point, exit_point, width, height)
            end
        end

        if final_path then
            quadrant_coverage[start_quad] = quadrant_coverage[start_quad] + 1
            quadrant_coverage[exit_quad] = quadrant_coverage[exit_quad] + 1
            
            local smoothed_path = ArterialRoadService._smoothPath(final_path)
            table.insert(all_paths, smoothed_path)
            ArterialRoadService._updateCostGridWithNewRoad(cost_grid, smoothed_path)
        end
    end
    return all_paths
end

-- PUBLIC FUNCTION: Generates roads and draws them to the grid
function ArterialRoadService.generateArterialRoads(city_grid, zone_grid, params)
    print("ArterialRoadService: Starting arterial road generation")
    local generated_paths = ArterialRoadService._calculateArterialPaths(zone_grid, params)
    
    for _, path in ipairs(generated_paths) do
        ArterialRoadService._drawArterialToGrid(city_grid, path)
    end
    
    print("ArterialRoadService: Arterial road generation complete")
    return generated_paths
end

-- PUBLIC FUNCTION: Only returns the calculated control points
function ArterialRoadService.getArterialControlPoints(zone_grid, params)
    print("ArterialRoadService: Getting arterial road control points")
    local generated_paths = ArterialRoadService._calculateArterialPaths(zone_grid, params)
    print("ArterialRoadService: Arterial control point calculation complete")
    return generated_paths
end


-- Make this compatible with your existing WFC system
ArterialRoadService.generateArterialsWFC = function(city_grid, zone_grid, params)
    return ArterialRoadService.generateArterialRoads(city_grid, zone_grid, params)
end

function ArterialRoadService._findLeastServicedQuadrants(coverage)
    local min_val = math.huge
    for _, count in pairs(coverage) do
        if count < min_val then min_val = count end
    end
    
    local candidates = {}
    for quad, count in pairs(coverage) do
        if count == min_val then table.insert(candidates, quad) end
    end
    return candidates
end

function ArterialRoadService._findBestOpposingQuadrant(start_quad)
    local opposites = {
        ["top-left"] = "bottom-right", ["top-right"] = "bottom-left",
        ["bottom-left"] = "top-right", ["bottom-right"] = "top-left"
    }
    return opposites[start_quad]
end

function ArterialRoadService._getEdgesForQuadrant(quadrant)
    if quadrant == "top-left" then return {"top", "left"}
    elseif quadrant == "top-right" then return {"top", "right"}
    elseif quadrant == "bottom-left" then return {"bottom", "left"}
    elseif quadrant == "bottom-right" then return {"bottom", "right"}
    end
    return {"top", "left", "bottom", "right"}
end

function ArterialRoadService._findBestExitPoint(constraint_node, incoming_direction, all_boundary_points, entry_point, allowed_exit_edges)
    local best_exit, best_score = nil, -math.huge
    for _, candidate_point in ipairs(all_boundary_points) do
        local is_allowed = false
        for _, allowed_edge in ipairs(allowed_exit_edges) do if candidate_point.edge == allowed_edge then is_allowed=true; break end end
        if is_allowed and candidate_point.edge ~= entry_point.edge then
            local score = 0; local exit_vector_x = candidate_point.x - constraint_node.x; local exit_vector_y = candidate_point.y - constraint_node.y
            local exit_vector_len = math.sqrt(exit_vector_x^2 + exit_vector_y^2)
            if exit_vector_len > 10 then
                local norm_exit_x, norm_exit_y = exit_vector_x/exit_vector_len, exit_vector_y/exit_vector_len
                score = score + ((incoming_direction.x*norm_exit_x + incoming_direction.y*norm_exit_y) * 150)
                score = score + (math.sqrt((candidate_point.x-entry_point.x)^2 + (candidate_point.y-entry_point.y)^2) * 1.0)
                if score > best_score then best_score=score; best_exit=candidate_point end
            end
        end
    end
    if best_exit then return best_exit end
    return ArterialRoadService._getRandomEdgePoint(0,0,"","",0,{},allowed_exit_edges, all_boundary_points)
end

function ArterialRoadService._getIncomingDirection(path)
    if not path or #path < 2 then return {x=0, y=1} end
    local start_node, end_node = path[math.max(1,#path-5)], path[#path]
    local dx, dy, len = end_node.x-start_node.x, end_node.y-start_node.y, math.sqrt((end_node.x-start_node.x)^2 + (end_node.y-start_node.y)^2)
    if len==0 then return {x=0,y=1} end
    return {x=dx/len, y=dy/len}
end

function ArterialRoadService._createSpecializedCostGrid(base_grid, zone_grid, target_zone_info)
    local new_grid=ArterialRoadService._cloneCostGrid(base_grid); local low_cost=target_zone_info.cost
    if target_zone_info.tiles then for _,tile in ipairs(target_zone_info.tiles)do new_grid[tile.y][tile.x]=low_cost end
    elseif target_zone_info.zone_name then for y,row in ipairs(zone_grid)do for x,zone in ipairs(row)do if zone==target_zone_info.zone_name then new_grid[y][x]=low_cost end end end end
    return new_grid
end

function ArterialRoadService._cloneCostGrid(original_grid)
    local new_grid={}; for y,row in ipairs(original_grid)do new_grid[y]={};for x,cost in ipairs(row)do new_grid[y][x]=cost end end
    return new_grid
end

function ArterialRoadService._findZoneBounds(zone_grid, target_zone)
    local min_x,max_x,min_y,max_y=math.huge,-math.huge,math.huge,-math.huge; local found=false
    for y,row in ipairs(zone_grid)do for x,zone in ipairs(row)do if zone==target_zone then min_x=math.min(min_x,x);max_x=math.max(max_x,x);min_y=math.min(min_y,y);max_y=math.max(max_y,y);found=true end end end
    if not found then return nil end
    return {min_x=min_x,min_y=min_y,max_x=max_x,max_y=max_y}
end

function ArterialRoadService._findLargestDistrict(zone_grid,width,height)
    local visited={};for y=1,height do visited[y]={}end;local largest_district={tiles={},center=nil,quadrant=nil}
    local valid_zone_map={commercial=true,residential_north=true,residential_south=true,industrial_heavy=true,industrial_light=true,university=true,medical=true,entertainment=true,waterfront=true,warehouse=true,tech=true}
    for y=1,height do for x=1,width do if not visited[y][x] and valid_zone_map[zone_grid[y][x]] then
        local current_district_tiles={};local q={{x=x,y=y}};visited[y][x]=true;local zone_type=zone_grid[y][x];local head=1
        while head<=#q do local curr=q[head];head=head+1;table.insert(current_district_tiles,curr)
            local neighbors={{curr.x,curr.y-1},{curr.x,curr.y+1},{curr.x-1,curr.y},{curr.x+1,curr.y}}
            for _,pos in ipairs(neighbors)do local nx,ny=pos[1],pos[2] if nx>0 and nx<=width and ny>0 and ny<=height and not visited[ny][nx] and zone_grid[ny][nx]==zone_type then visited[ny][nx]=true;table.insert(q,{x=nx,y=ny})end end
        end
        if #current_district_tiles>#largest_district.tiles then largest_district.tiles=current_district_tiles end
    end end end
    if #largest_district.tiles>0 then
        local sum_x,sum_y=0,0;for _,tile in ipairs(largest_district.tiles)do sum_x=sum_x+tile.x;sum_y=sum_y+tile.y end
        local center_x=math.floor(sum_x/#largest_district.tiles);local center_y=math.floor(sum_y/#largest_district.tiles)
        largest_district.center={x=center_x,y=center_y};local mid_w,mid_h=width/2,height/2
        if center_y<=mid_h then if center_x<=mid_w then largest_district.quadrant="top-left"else largest_district.quadrant="top-right"end else if center_x<=mid_w then largest_district.quadrant="bottom-left"else largest_district.quadrant="bottom-right"end end
        return largest_district
    end
    return nil
end

function ArterialRoadService._updateCostGridWithNewRoad(cost_grid,path)
    if not cost_grid or not path then return end;local merge_cost=1
    for _,node in ipairs(path)do if cost_grid[node.y]and cost_grid[node.y][node.x]then cost_grid[node.y][node.x]=merge_cost end end
end

function ArterialRoadService._createCostGrid(zone_grid,width,height)
    local cost_grid={};local boundary_cost=5;local district_interior_cost=150
    for y=1,height do cost_grid[y]={};for x=1,width do local current_zone=zone_grid[y][x];local is_boundary=false;local neighbors={{x,y-1},{x,y+1},{x-1,y},{x+1,y}}
        for _,pos in ipairs(neighbors)do local nx,ny=pos[1],pos[2]if nx>0 and nx<=width and ny>0 and ny<=height and zone_grid[ny][nx]~=current_zone then is_boundary=true;break end end
        if is_boundary then cost_grid[y][x]=boundary_cost else cost_grid[y][x]=district_interior_cost end
        if current_zone and string.find(current_zone,"park")then cost_grid[y][x]=20 end
    end end
    return cost_grid
end

function ArterialRoadService._getRandomEdgePoint(width,height,point_type,other_point,min_distance,zone_grid,allowed_edges,all_boundary_points)
    local boundary_points=all_boundary_points or ArterialRoadService._findDistrictBoundaryPoints(zone_grid,width,height)
    local valid_points={};for _,point in ipairs(boundary_points)do local is_valid=true
        if allowed_edges then local is_allowed=false;for _,allowed in ipairs(allowed_edges)do if point.edge==allowed then is_allowed=true;break end end;if not is_allowed then is_valid=false end end
        if is_valid and other_point and min_distance then if math.sqrt((point.x-other_point.x)^2+(point.y-other_point.y)^2)<min_distance then is_valid=false end;if point.edge==other_point.edge then is_valid=false end end
        if is_valid then table.insert(valid_points,point)end
    end
    if #valid_points>0 then return valid_points[love.math.random(1,#valid_points)]end
    return ArterialRoadService._getRandomEdgePointFallback(width,height,point_type,other_point,min_distance,allowed_edges)
end

function ArterialRoadService._getRandomEdgePointFallback(width,height,point_type,other_point,min_distance,allowed_edges)
    local edges={{name="top",points={}},{name="bottom",points={}},{name="left",points={}},{name="right",points={}}};for x=1,width do table.insert(edges[1].points,{x=x,y=1,edge="top"});table.insert(edges[2].points,{x=x,y=height,edge="bottom"})end
    for y=1,height do table.insert(edges[3].points,{x=1,y=y,edge="left"});table.insert(edges[4].points,{x=width,y=y,edge="right"})end
    local valid_points={};for _,edge in ipairs(edges)do local edge_is_allowed=not allowed_edges
        if allowed_edges then for _,allowed in ipairs(allowed_edges)do if edge.name==allowed then edge_is_allowed=true;break end end end
        if edge_is_allowed then for _,point in ipairs(edge.points)do local is_valid=true
            if other_point and min_distance then if math.sqrt((point.x-other_point.x)^2+(point.y-other_point.y)^2)<min_distance then is_valid=false end;if point.edge==other_point.edge then is_valid=false end end
            if is_valid then table.insert(valid_points,point)end
    end end end;if #valid_points>0 then return valid_points[love.math.random(1,#valid_points)]end
    return nil
end

function ArterialRoadService._findDistrictBoundaryPoints(zone_grid,width,height)
    local boundary_points={};for x=2,width do if zone_grid[1][x]~=zone_grid[1][x-1]then table.insert(boundary_points,{x=x,y=1,edge="top",zone_from=zone_grid[1][x-1],zone_to=zone_grid[1][x]})end;if zone_grid[height][x]~=zone_grid[height][x-1]then table.insert(boundary_points,{x=x,y=height,edge="bottom",zone_from=zone_grid[height][x-1],zone_to=zone_grid[height][x]})end end
    for y=2,height do if zone_grid[y][1]~=zone_grid[y-1][1]then table.insert(boundary_points,{x=1,y=y,edge="left",zone_from=zone_grid[y-1][1],zone_to=zone_grid[y][1]})end;if zone_grid[y][width]~=zone_grid[y-1][width]then table.insert(boundary_points,{x=width,y=y,edge="right",zone_from=zone_grid[y-1][width],zone_to=zone_grid[y][width]})end end
    return boundary_points
end

function ArterialRoadService._findArterialPath(cost_grid,start_point,end_point,width,height)
    if not start_point or not end_point then return nil end
    local open_set={};local came_from={};local g_score,f_score={}, {};local open_hash={}
    local function node_key(x,y)return y*width+x end;local function heuristic(x1,y1,x2,y2)return math.abs(x1-x2)+math.abs(y1-y2)end
    local function reconstruct_path(current)local path={current};while came_from[node_key(current.x,current.y)]do current=came_from[node_key(current.x,current.y)];table.insert(path,1,current)end;return path end
    local start_key=node_key(start_point.x,start_point.y);g_score[start_key]=0;f_score[start_key]=heuristic(start_point.x,start_point.y,end_point.x,end_point.y);table.insert(open_set,start_point);open_hash[start_key]=true
    while #open_set>0 do
        local lowest_f_idx=1;for i=2,#open_set do if f_score[node_key(open_set[i].x,open_set[i].y)]<f_score[node_key(open_set[lowest_f_idx].x,open_set[lowest_f_idx].y)]then lowest_f_idx=i end end
        local current=table.remove(open_set,lowest_f_idx);local current_key=node_key(current.x,current.y);open_hash[current_key]=nil
        if current.x==end_point.x and current.y==end_point.y then return reconstruct_path(current)end
        local neighbors={{current.x,current.y-1},{current.x,current.y+1},{current.x-1,current.y},{current.x+1,current.y}}
        for _,pos in ipairs(neighbors)do local nx,ny=pos[1],pos[2]
            if nx>=1 and nx<=width and ny>=1 and ny<=height then
                local neighbor={x=nx,y=ny};local tentative_g=g_score[current_key]+cost_grid[ny][nx];local neighbor_key=node_key(nx,ny)
                if not g_score[neighbor_key]or tentative_g<g_score[neighbor_key]then came_from[neighbor_key]=current;g_score[neighbor_key]=tentative_g;f_score[neighbor_key]=tentative_g+heuristic(nx,ny,end_point.x,end_point.y)if not open_hash[neighbor_key]then table.insert(open_set,neighbor);open_hash[neighbor_key]=true end end
            end
        end
    end
    return nil
end

function ArterialRoadService._smoothPath(path)
    if not path or #path<3 then return path end;local smoothed={path[1]}
    for i=2,#path-1 do local p1,p2,p3=path[i-1],path[i],path[i+1]if(p2.x-p1.x)~=(p3.x-p2.x)or(p2.y-p1.y)~=(p3.y-p2.y)then table.insert(smoothed,p2)end end
    table.insert(smoothed,path[#path]);return smoothed
end

function ArterialRoadService._drawArterialToGrid(city_grid,path)
    for i=1,#path-1 do ArterialRoadService._drawLine(city_grid,path[i].x,path[i].y,path[i+1].x,path[i+1].y,"arterial")end
end

function ArterialRoadService._drawLine(grid,x1,y1,x2,y2,road_type)
    local dx,dy=math.abs(x2-x1),math.abs(y2-y1);local sx,sy=x1<x2 and 1 or -1,y1<y2 and 1 or -1
    local err,x,y=dx-dy,x1,y1
    while true do if grid[y]and grid[y][x]and grid[y][x].type~="arterial"and grid[y][x].type~="road"then grid[y][x]={type=road_type}end
        if x==x2 and y==y2 then break end;local e2=2*err
        if e2>-dy then err=err-dy;x=x+sx end;if e2<dx then err=err+dx;y=y+sy end
    end
end

function ArterialRoadService.findPathBetweenPoints(zone_grid, start_point, end_point)
    local width, height = #zone_grid[1], #zone_grid
    
    -- Create the cost grid where zone boundaries are cheap and interiors are expensive
    local cost_grid = ArterialRoadService._createCostGrid(zone_grid, width, height)

    -- Use the existing A* pathfinder
    local path = ArterialRoadService._findArterialPath(cost_grid, start_point, end_point, width, height)
    
    return path
end

return ArterialRoadService