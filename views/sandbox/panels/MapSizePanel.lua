-- views/sandbox/panels/MapSizePanel.lua
local TextInput = require("views.components.TextInput")

local MapSizePanel = {}

function MapSizePanel.buildWidgets(sc, game)
    local p = sc.params
    local widgets = {}

    local function addInput(label, key, is_int)
        local w = TextInput:new(label, p[key], is_int, function(v)
            p[key] = v
        end, game)
        table.insert(widgets, w)
    end

    addInput("City Width",      "city_w",      true)
    addInput("City Height",     "city_h",      true)
    addInput("Downtown Width",  "downtown_w",  true)
    addInput("Downtown Height", "downtown_h",  true)

    return widgets
end

function MapSizePanel.draw(widgets, sc, game)
    for _, w in ipairs(widgets) do
        w:draw()
    end
end

return MapSizePanel
