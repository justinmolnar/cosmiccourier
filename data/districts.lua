-- data/districts.lua
-- District definitions and configurations for city generation

local Districts = {
    CITY_LAYOUT = {
        -- Central Business District
        {
            name = "downtown_core",
            type = "commercial",
            x1_percent = 0.40, y1_percent = 0.40,
            x2_percent = 0.60, y2_percent = 0.60,
            density = 0.95,
            road_density = 0.2,
            center_x_percent = 0.5,
            center_y_percent = 0.5
        },
        
        -- Northern Suburbs
        {
            name = "north_suburbs",
            type = "residential",
            x1_percent = 0.2, y1_percent = 0.1,
            x2_percent = 0.8, y2_percent = 0.4,
            density = 0.3,
            road_density = 0.05,
            center_x_percent = 0.5,
            center_y_percent = 0.25
        },
        
        -- Southern Industrial
        {
            name = "south_industrial",
            type = "industrial",
            x1_percent = 0.1, y1_percent = 0.6,
            x2_percent = 0.9, y2_percent = 0.9,
            density = 0.2,
            road_density = 0.03,
            center_x_percent = 0.5,
            center_y_percent = 0.75
        },
        
        -- Eastern Tech Campus
        {
            name = "east_tech",
            type = "commercial",
            x1_percent = 0.6, y1_percent = 0.3,
            x2_percent = 0.9, y2_percent = 0.7,
            density = 0.4,
            road_density = 0.04,
            center_x_percent = 0.75,
            center_y_percent = 0.5
        },
        
        -- Western Residential
        {
            name = "west_residential",
            type = "residential",
            x1_percent = 0.1, y1_percent = 0.3,
            x2_percent = 0.4, y2_percent = 0.7,
            density = 0.3,
            road_density = 0.04,
            center_x_percent = 0.25,
            center_y_percent = 0.5
        }
    },

    ROAD_HIERARCHY = {
        primary_highways = {
            -- Major north-south highway
            {
                start_x_percent = 0.5, start_y_percent = 0.0,
                end_x_percent = 0.5, end_y_percent = 1.0,
                type = "highway"
            },
            -- Major east-west highway
            {
                start_x_percent = 0.0, start_y_percent = 0.5,
                end_x_percent = 1.0, end_y_percent = 0.5,
                type = "highway"
            },
            -- Ring road
            {
                start_x_percent = 0.0, start_y_percent = 0.3,
                end_x_percent = 1.0, end_y_percent = 0.3,
                type = "highway"
            },
            {
                start_x_percent = 0.0, start_y_percent = 0.7,
                end_x_percent = 1.0, end_y_percent = 0.7,
                type = "highway"
            }
        },
        
        secondary_roads = {
            connection_distance = 15,
            road_type = "arterial"
        }
    },

    -- NEW, DENSER SPACING
    ROAD_SPACING = {
        industrial = 25,    -- Wider spacing for industrial
        commercial = 8,     -- Very tight grid for downtown/commercial
        residential = 15,   -- Medium density for suburbs
        park = 40
    }
}

return Districts