-- services/MapGenerationService.lua
local MapGenerationService = {}

function MapGenerationService._deepCopyParams(params)
    if not params then return {} end
    local copy = {}
    for key, value in pairs(params) do
        if type(value) == "table" then
            copy[key] = MapGenerationService._deepCopyParams(value)
        else
            copy[key] = value
        end
    end
    return copy
end

function MapGenerationService.generateMap(map)
    print("MapGenerationService: Beginning map generation...")
    local C_MAP = map.C.MAP
    local params = map.debug_params or {
        width = C_MAP.CITY_GRID_WIDTH,
        height = C_MAP.CITY_GRID_HEIGHT,
        use_wfc_for_zones = true,
        use_recursive_streets = true,
        generate_arterials = true
    }

    local result = require("services.NewCityGenService").generateDetailedCity(params)

    if result and result.city_grid then
        map.grid = result.city_grid
        map.zone_grid = result.zone_grid

        local city_w  = C_MAP.CITY_GRID_WIDTH
        local city_h  = C_MAP.CITY_GRID_HEIGHT
        local dt_w    = C_MAP.DOWNTOWN_GRID_WIDTH
        local dt_h    = C_MAP.DOWNTOWN_GRID_HEIGHT
        map.downtown_offset = {
            x = math.floor(city_w / 2) - math.floor(dt_w / 2),
            y = math.floor(city_h / 2) - math.floor(dt_h / 2),
        }

        print("MapGenerationService: Generation complete.")
    else
        print("ERROR: NewCityGenService failed to return a valid city grid. Falling back to empty grid.")
        map.grid = MapGenerationService._createGrid(params.width, params.height, "grass")
    end

    map.building_plots = map:getPlotsFromGrid(map.grid)
    map.scale_grids = nil
    map.scale_building_plots = nil

    print("MapGenerationService: Found " .. #map.building_plots .. " valid building plots.")
end

function MapGenerationService.getPlotInAnotherCity(game, origin_city_index)
    local region_map = game.maps.region
    if not region_map or not region_map.cities_data or #region_map.cities_data < 2 then
        return nil
    end

    local possible_destinations = {}
    for i, city_data in ipairs(region_map.cities_data) do
        if i ~= origin_city_index then
            table.insert(possible_destinations, city_data)
        end
    end

    if #possible_destinations == 0 then return nil end

    local destination_city = possible_destinations[love.math.random(1, #possible_destinations)]

    if destination_city.building_plots and #destination_city.building_plots > 0 then
        return destination_city.building_plots[love.math.random(1, #destination_city.building_plots)]
    end

    return nil
end

function MapGenerationService._createGrid(width, height, default_type)
    local grid = {}
    for y = 1, height do
        grid[y] = {}
        for x = 1, width do
            grid[y][x] = { type = default_type or "grass" }
        end
    end
    return grid
end

return MapGenerationService
