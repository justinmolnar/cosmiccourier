-- data/tile_palette.lua
-- Maps tile type string → color key in C.MAP.COLORS.
-- getTileColor in Map.lua uses this to avoid a 28-line if/elseif chain.
--
-- Structure: { downtown = color_key, city = color_key }
-- "downtown" is the color used when the tile is inside the downtown boundary.
-- "city" is the color used elsewhere.
-- If a tile type has only one entry it uses the same color in both contexts.

local json = require("lib.json")

local raw        = love.filesystem.read("data/tile_palette.json")
local TilePalette = json.decode(raw)

return TilePalette
