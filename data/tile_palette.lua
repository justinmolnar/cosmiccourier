-- data/tile_palette.lua
-- Maps tile type string → color key in C.MAP.COLORS.
-- getTileColor in Map.lua uses this to avoid a 28-line if/elseif chain.
--
-- Structure: { downtown = color_key, city = color_key }
-- "downtown" is the color used when the tile is inside the downtown boundary.
-- "city" is the color used elsewhere.
-- If a tile type has only one entry it uses the same color in both contexts.

local TilePalette = {
    road         = { downtown = "DOWNTOWN_ROAD", city = "ROAD" },
    downtown_road= { downtown = "DOWNTOWN_ROAD", city = "ROAD" },
    highway      = { downtown = "DOWNTOWN_ROAD", city = "ROAD" },
    arterial     = { downtown = "ARTERIAL",      city = "ARTERIAL" },
    grass        = { downtown = "DOWNTOWN_PLOT",  city = "GRASS" },
    water        = { downtown = "DOWNTOWN_PLOT",  city = "WATER" },
    mountain     = { downtown = "DOWNTOWN_PLOT",  city = "MOUNTAIN" },
    -- default (plots and any unlisted type)
    default      = { downtown = "DOWNTOWN_PLOT",  city = "PLOT" },
}

return TilePalette
