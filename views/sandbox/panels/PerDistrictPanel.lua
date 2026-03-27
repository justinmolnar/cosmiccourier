-- views/sandbox/panels/PerDistrictPanel.lua
-- Per-district road density sliders, populated after generation.
local Slider = require("views.components.Slider")

local PerDistrictPanel = {}

function PerDistrictPanel.buildWidgets(sc, game)
    local widgets = {}

    if not sc.districts or #sc.districts == 0 then
        -- Placeholder label widget
        local placeholder = {
            x = 0, y = 0, w = 260, h = 28,
            draw = function(self)
                love.graphics.setFont(game.fonts.ui_small)
                love.graphics.setColor(0.5, 0.5, 0.5)
                love.graphics.print("  (generate first)", self.x, self.y + 7)
                love.graphics.setColor(1, 1, 1)
            end,
            handle_mouse_down = function() return false end,
            handle_mouse_moved = function() end,
            handle_mouse_up    = function() end,
            handle_textinput   = function() return false end,
            handle_keypressed  = function() return false end,
            update = function() end,
        }
        table.insert(widgets, placeholder)
        return widgets
    end

    -- One road_density slider per district
    for _, district in ipairs(sc.districts) do
        local idx = district.index
        if not sc.district_overrides[idx] then
            sc.district_overrides[idx] = { road_density = 20, block_size = 5 }
        end
        local ov = sc.district_overrides[idx]

        -- Header label
        local header = {
            x = 0, y = 0, w = 260, h = 22,
            label = district.name,
            draw = function(self)
                love.graphics.setFont(game.fonts.ui_small)
                love.graphics.setColor(0.6, 0.8, 1.0)
                love.graphics.print("  " .. self.label, self.x, self.y + 4)
                love.graphics.setColor(1, 1, 1)
            end,
            handle_mouse_down = function() return false end,
            handle_mouse_moved = function() end,
            handle_mouse_up    = function() end,
            handle_textinput   = function() return false end,
            handle_keypressed  = function() return false end,
            update = function() end,
        }
        table.insert(widgets, header)

        local rd_slider = Slider:new("Road Density", 5, 60, ov.road_density, true, function(v)
            ov.road_density = v
        end, game)
        table.insert(widgets, rd_slider)

        local bs_slider = Slider:new("Block Size", 2, 20, ov.block_size, true, function(v)
            ov.block_size = v
        end, game)
        table.insert(widgets, bs_slider)
    end

    return widgets
end

function PerDistrictPanel.draw(widgets, sc, game)
    for _, w in ipairs(widgets) do
        w:draw()
    end
end

return PerDistrictPanel
