-- views/sandbox/panels/DistrictPanel.lua
-- WFC generation parameters + arterial display controls.
local Slider = require("views.components.Slider")

local DistrictPanel = {}

function DistrictPanel.buildWidgets(sc, game)
    local p = sc.params
    local widgets = {}

    local function addSlider(label, key, min, max, is_int, on_change)
        table.insert(widgets, Slider:new(label, min, max, p[key], is_int, function(v)
            p[key] = v
            if on_change then on_change(v) end
        end, game))
    end

    -- WFC generation params
    addSlider("Min Block",     "min_block_size",   0, 30,  true)
    addSlider("Max Block",     "max_block_size",   0, 60,  true)
    addSlider("Num Arterials",     "num_arterials",      0, 12, true)
    addSlider("Arterial Thickness","arterial_thickness", 1,  5, true)
    addSlider("Edge Dist",         "min_edge_distance",  1, 40, true)

    -- Road generation algorithm selector + per-algo params
    addSlider("Road Algo 1-4",   "street_algo",      1,    4,    true)
    addSlider("Warp Strength",   "warp_strength",    1,    12,   true)
    addSlider("Warp Scale",      "warp_scale",       5,    60,   true)
    addSlider("Num Spokes",      "num_spokes",       4,    16,   true)
    addSlider("Num Rings",       "num_rings",        1,    8,    true)
    addSlider("Road Length",     "max_road_length",  10,   80,   true)
    addSlider("Branch Chance",   "branch_chance",    0.01, 0.30, false)
    addSlider("Num Seeds",       "num_seeds",        10,   80,   true)

    -- Arterial display controls (take effect immediately in the view)
    addSlider("Arterial Width", "arterial_width",   0.1, 3.0, false)
    addSlider("Smooth Segs",    "smooth_segments",  1,   20,  true, function()
        sc:_buildSmoothOverlays()
    end)

    return widgets
end

function DistrictPanel.draw(widgets, sc, game)
    for _, w in ipairs(widgets) do
        w:draw()
    end
end

return DistrictPanel
