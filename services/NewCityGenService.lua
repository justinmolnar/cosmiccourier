-- services/NewCityGenService.lua
local NewCityGenService = {}

local pathfinder = require("lib.pathfinder")

-- (The private helper functions _getZoneCenters, _generateZoneBlobSimulation, _generateWfcZones are unchanged from the last correct version)

local function _getZoneCenters(grid)
    local width, height = #grid[1], #grid
    local zones = {}
    local zone_tiles = {}

    for y = 1, height do
        for x = 1, width do
            local tile = grid[y][x]
            if tile.zone_type and tile.zone_type ~= "grass" then
                if not zone_tiles[tile.zone_type] then
                    zone_tiles[tile.zone_type] = {}
                end
                table.insert(zone_tiles[tile.zone_type], {x=x, y=y})
            end
        end
    end

    for zone_type, tiles in pairs(zone_tiles) do
        if #tiles > 0 then
            local sum_x, sum_y = 0, 0
            for _, tile in ipairs(tiles) do
                sum_x = sum_x + tile.x
                sum_y = sum_y + tile.y
            end
            zones[zone_type] = {
                x = math.floor(sum_x / #tiles),
                y = math.floor(sum_y / #tiles)
            }
        end
    end
    print("--- GENERATOR LAB: Found zone centers ---")
    return zones
end

local function _generateZoneBlobSimulation(grid, params)
    print("--- GENERATOR LAB: Generating zone blobs (Simulation) ---")
    local width = #grid[1]
    local height = #grid
    local num_zones = 5
    local zone_types = {"commercial", "industrial", "residential"}
    
    local zone_centers = {}
    for i = 1, num_zones do
        table.insert(zone_centers, {
            x = love.math.random(1, width),
            y = love.math.random(1, height),
            radius = love.math.random(width / 8, width / 4),
            type = zone_types[love.math.random(1, #zone_types)]
        })
    end

    for y = 1, height do
        for x = 1, width do
            local min_dist = math.huge
            local closest_zone_type = "grass"
            for _, zone in ipairs(zone_centers) do
                local dist = math.sqrt((x - zone.x)^2 + (y - zone.y)^2)
                if dist < zone.radius and dist < min_dist then
                    min_dist = dist
                    closest_zone_type = zone.type
                end
            end
            grid[y][x].zone_type = closest_zone_type
            if grid[y][x].type == "arterial" or grid[y][x].type == "local_road" then
                grid[y][x].type = "grass"
            end
        end
    end
end

local function _generateWfcZones(grid, params)
    print("--- GENERATOR LAB: Generating zones with WFC ---")
    local wfc = require("lib.wfc")
    local width, height = #grid[1], #grid

    local tileset = {
        {name = "commercial"},
        {name = "residential"},
        {name = "industrial"},
        {name = "grass"}
    }

    -- THE FIX: A new, more robust and symmetrical set of rules.
    -- Grass can now touch anything, acting as a buffer.
    -- Industrial is still separated from commercial/residential by grass.
    local adjacency_rules = {
        commercial = {"commercial", "residential", "grass"},
        residential = {"commercial", "residential", "grass"},
        industrial = {"industrial", "grass"},
        grass = {"commercial", "residential", "industrial", "grass"}
    }
    
    local constraints = {}
    local downtown_w, downtown_h = math.floor(width / 5), math.floor(height / 5)
    local start_x = math.floor((width - downtown_w) / 2)
    local start_y = math.floor((height - downtown_h) / 2)

    for y = start_y, start_y + downtown_h do
        for x = start_x, start_x + downtown_w do
            constraints[y .. "," .. x] = "commercial"
        end
    end

    local wfc_grid = wfc.solve(width, height, tileset, adjacency_rules, constraints)

    for y=1, height do
        for x=1, width do
            grid[y][x].zone_type = wfc_grid[y][x].type
            if grid[y][x].type == "arterial" or grid[y][x].type == "local_road" then
                grid[y][x].type = "grass"
            end
        end
    end
end

local function _generateWfcLocalDetails(grid, params)
    print("--- GENERATOR LAB: Generating local details with WFC ---")
    local wfc = require("lib.wfc")
    local width, height = #grid[1], #grid

    -- A simple tileset: a tile is either a local road or a building plot.
    local tileset = {
        {name = "local_road"}, 
        {name = "building_plot"}
    }
    
    -- Rules: roads like to be next to other roads to form paths,
    -- but can also be next to plots. Plots must be next to a road.
    local adjacency_rules = {
        local_road = {"local_road", "building_plot", "arterial"},
        building_plot = {"local_road", "building_plot"},
        arterial = {"local_road", "building_plot"}
    }

    -- Find existing arterial roads to use as constraints
    local constraints = {}
    for y=1, height do
        for x=1, width do
            if grid[y][x].type == "arterial" then
                constraints[y .. "," .. x] = "arterial"
            end
        end
    end

    local wfc_grid = wfc.solve(width, height, tileset, adjacency_rules, constraints)
    
    -- Apply the results to the grid, but be careful to preserve the arterials
    for y=1, height do
        for x=1, width do
            if grid[y][x].type ~= "arterial" then
                grid[y][x].type = wfc_grid[y][x].type
            end
        end
    end
end

-- Renamed old walker function
local function _generateWalkerLocalRoads(grid, params)
    print("--- GENERATOR LAB: Generating local roads with walkers ---")
    local map_w, map_h = #grid[1], #grid
    
    for y=1, map_h do
        for x=1, map_w do
            if grid[y][x].type ~= "arterial" then
                grid[y][x].type = "building_plot"
            end
        end
    end

    local starting_points = {}
    for y = 1, map_h do
        for x = 1, map_w do
            if grid[y][x].type == "arterial" then
                table.insert(starting_points, {x=x, y=y})
            end
        end
    end

    if #starting_points == 0 then return end

    local walkers = {}
    local num_walkers = 75
    local directions = {{1,0}, {-1,0}, {0,1}, {0,-1}}

    for i = 1, num_walkers do
        local start_pos = starting_points[love.math.random(1, #starting_points)]
        table.insert(walkers, {
            x = start_pos.x,
            y = start_pos.y,
            life = love.math.random(20, 50),
            dir = directions[love.math.random(1, #directions)]
        })
    end

    local turn_chance = 0.2
    while #walkers > 0 do
        for i = #walkers, 1, -1 do
            local walker = walkers[i]
            
            walker.x = walker.x + walker.dir[1]
            walker.y = walker.y + walker.dir[2]
            walker.life = walker.life - 1

            local out_of_bounds = walker.x < 1 or walker.x > map_w or walker.y < 1 or walker.y > map_h
            if out_of_bounds or walker.life <= 0 then
                table.remove(walkers, i)
            else
                if grid[walker.y] and grid[walker.y][walker.x] then
                    local current_tile = grid[walker.y][walker.x]
                    if current_tile.type ~= "arterial" then
                        current_tile.type = "local_road"
                    end
                end

                if love.math.random() < turn_chance then
                    walker.dir = directions[love.math.random(1, #directions)]
                end
            end
        end
    end
    print("--- GENERATOR LAB: Finished local road walkers. ---")
end


-- PUBLIC FUNCTIONS
function NewCityGenService.generateZoneBlobs(grid, params)
    if params.use_wfc_for_zones then
        _generateWfcZones(grid, params)
    else
        _generateZoneBlobSimulation(grid, params)
    end
end

function NewCityGenService.generateArterialRoads(grid, params, game)
    print("--- GENERATOR LAB: Generating arterial roads ---")
    for y=1, #grid do for x=1, #grid[1] do if grid[y][x].type == "arterial" then grid[y][x].type = "grass" end end end

    local zone_centers = _getZoneCenters(grid)
    local map_w, map_h = #grid[1], #grid

    local highway_connections = {
        {x = math.floor(map_w / 2), y = 1},
        {x = math.floor(map_w / 2), y = map_h},
        {x = 1, y = math.floor(map_h / 2)},
        {x = map_w, y = math.floor(map_h / 2)}
    }

    local temp_map = { isRoad = function(tile_type) return tile_type ~= "arterial" end }
    local costs = { grass = 1, commercial = 5, industrial = 5, residential = 5 }

    for _, center in pairs(zone_centers) do
        local start_node = center
        local end_node = highway_connections[love.math.random(1, #highway_connections)]
        if start_node and end_node then
            local path = pathfinder.findPath(grid, start_node, end_node, costs, temp_map)
            if path then
                for _, p_node in ipairs(path) do
                    grid[p_node.y][p_node.x].type = "arterial"
                end
            end
        end
    end
end

function NewCityGenService.generateLocalRoads(grid, params)
    if params.use_wfc_for_details then
        _generateWfcLocalDetails(grid, params)
    else
        _generateWalkerLocalRoads(grid, params)
    end
end

function NewCityGenService.generateDetailedCity(params, game)
    print("--- GENERATOR LAB: generateDetailedCity called ---")
    
    local temp_grid = {}
    for y = 1, params.height do
        temp_grid[y] = {}
        for x = 1, params.width do
            temp_grid[y][x] = { type = "grass", zone_type = "grass" }
        end
    end
    
    NewCityGenService.generateZoneBlobs(temp_grid, params)
    NewCityGenService.generateArterialRoads(temp_grid, params, game)
    NewCityGenService.generateLocalRoads(temp_grid, params)
    
    print(string.format("--- GENERATOR LAB: Created a %dx%d grid with all road layers. ---", params.width, params.height))
    return temp_grid
end

return NewCityGenService