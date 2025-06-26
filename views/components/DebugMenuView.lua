-- views/components/DebugMenuView.lua
-- View component for the debug menu that integrates with the MVC architecture

local DebugMenuView = {}
DebugMenuView.__index = DebugMenuView

function DebugMenuView:new(debug_controller, game)
    local instance = setmetatable({}, DebugMenuView)
    instance.controller = debug_controller
    instance.game = game
    return instance
end

function DebugMenuView:_drawLabGrid()
    if not self.game.debug_lab_grid then return end

    local grid = self.game.debug_lab_grid
    local C_MAP = self.game.C.MAP
    local screen_w, screen_h = love.graphics.getDimensions()
    
    -- 1. Draw a dark overlay to dim the main game and focus on the lab grid
    love.graphics.setColor(0, 0, 0, 0.8)
    love.graphics.rectangle("fill", 0, 0, screen_w, screen_h)

    -- 2. Setup drawing parameters for the grid
    local TILE_SIZE = 4 -- Use a small tile size to see the whole grid
    local total_w = #grid[1] * TILE_SIZE
    local total_h = #grid * TILE_SIZE
    local start_x = (screen_w - total_w) / 2
    local start_y = (screen_h - total_h) / 2
    
    love.graphics.push()
    love.graphics.translate(start_x, start_y)

    -- 3. Iterate over the grid and draw each tile
    for y = 1, #grid do
        for x = 1, #grid[1] do
            local tile = grid[y][x]
            local color = C_MAP.COLORS.GRASS -- Default to grass for now
            
            -- This is where we will add more colors for different zones later
            if tile.type == "downtown_plot" then color = C_MAP.COLORS.DOWNTOWN_PLOT end

            love.graphics.setColor(color)
            love.graphics.rectangle("fill", (x-1) * TILE_SIZE, (y-1) * TILE_SIZE, TILE_SIZE, TILE_SIZE)
        end
    end
    
    love.graphics.pop()
end

function DebugMenuView:draw()
    if not self.controller:isVisible() then return end
    
    love.graphics.push()
    
    local x, y, w, h = self.controller.x, self.controller.y, self.controller.w, self.controller.h
    local scroll_y = self.controller.scroll_y
    local active_tab = self.controller.active_tab
    local content_height = 0
    
    -- Draw main menu background
    love.graphics.setColor(0.1, 0.1, 0.15, 0.95)
    love.graphics.rectangle("fill", x, y, w, h)
    
    -- Draw border
    love.graphics.setColor(0.4, 0.4, 0.5)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", x, y, w, h)
    
    -- Draw title bar
    love.graphics.setColor(0.2, 0.2, 0.3)
    love.graphics.rectangle("fill", x, y, w, 25)
    love.graphics.setColor(1, 1, 1)
    love.graphics.setFont(self.game.fonts.ui)
    love.graphics.print("Map Generation Debug", x + 10, y + 5)
    
    -- Draw close button
    love.graphics.setColor(0.8, 0.3, 0.3)
    love.graphics.rectangle("fill", x + w - 25, y + 2, 21, 21)
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf("×", x + w - 25, y + 5, 21, "center")

    -- Draw Tabs
    local tab_y = y + 25
    local tab_h = 25
    local tab_w = w / #self.controller.tabs
    for i, tab_name in ipairs(self.controller.tabs) do
        local tab_x = x + (i-1) * tab_w
        local is_active = (tab_name == active_tab)
        
        love.graphics.setColor(is_active and {0.25, 0.25, 0.35} or {0.15, 0.15, 0.2})
        love.graphics.rectangle("fill", tab_x, tab_y, tab_w, tab_h)
        love.graphics.setColor(is_active and {0.7, 0.7, 0.8} or {0.4, 0.4, 0.5})
        love.graphics.rectangle("line", tab_x, tab_y, tab_w, tab_h)
        love.graphics.setColor(is_active and {1, 1, 1} or {0.6, 0.6, 0.6})
        love.graphics.printf(tab_name, tab_x, tab_y + 5, tab_w, "center")
    end
    
    -- Set up scrollable content area (starts below tabs)
    love.graphics.setScissor(x + 1, y + 51, w - 2, h - 52)
    love.graphics.push()
    love.graphics.translate(0, -scroll_y)
    
    local current_content_y = y + 55
    love.graphics.setFont(self.game.fonts.ui_small)
    
    -- Only draw content for the active tab
    if active_tab == "Generation" then
        -- Draw parameters section
        love.graphics.setColor(1, 1, 0.8)
        love.graphics.print("Parameters:", x + 10, current_content_y)
        current_content_y = current_content_y + 20
        
        local param_count = 0
        for param_name, value in pairs(self.controller.params) do
            param_count = param_count + 1
            local param_draw_y = current_content_y + (param_count - 1) * 25
            
            if type(value) == "number" then
                love.graphics.setColor(1, 1, 1)
                love.graphics.print(param_name, x + 10, param_draw_y + 3)
                love.graphics.printf(string.format("%.3f", value), x + 35, param_draw_y + 3, w - 140, "right")
                love.graphics.setColor(0.8, 0.4, 0.4)
                love.graphics.rectangle("fill", x + w - 70, param_draw_y, 20, 20)
                love.graphics.setColor(1, 1, 1)
                love.graphics.printf("-", x + w - 70, param_draw_y + 3, 20, "center")
                love.graphics.setColor(0.4, 0.8, 0.4)
                love.graphics.rectangle("fill", x + w - 50, param_draw_y, 20, 20)
                love.graphics.setColor(1, 1, 1)
                love.graphics.printf("+", x + w - 50, param_draw_y + 3, 20, "center")
            elseif type(value) == "boolean" then
                local toggle_color = value and {0.4, 0.8, 0.4} or {0.8, 0.4, 0.4}
                love.graphics.setColor(toggle_color)
                love.graphics.rectangle("fill", x + 10, param_draw_y, 20, 20)
                love.graphics.setColor(1, 1, 1)
                love.graphics.printf(value and "✓" or "✗", x + 10, param_draw_y + 2, 20, "center")
                love.graphics.print(param_name, x + 35, param_draw_y + 3)
            end
        end
        current_content_y = current_content_y + param_count * 25
        
        -- Draw actions section
        current_content_y = current_content_y + 10
        love.graphics.setColor(1, 1, 0.8)
        love.graphics.print("Actions:", x + 10, current_content_y)
        current_content_y = current_content_y + 20
        
        local button_count = 0
        for i, btn in ipairs(self.controller.buttons) do
            if btn.tab == active_tab then
                button_count = button_count + 1
                local btn_y = current_content_y + (button_count - 1) * 35
                local bg_color = btn.color
                love.graphics.setColor(bg_color)
                love.graphics.rectangle("fill", x + 10, btn_y, w - 20, 30)
                love.graphics.setColor(1, 1, 1)
                love.graphics.rectangle("line", x + 10, btn_y, w - 20, 30)
                love.graphics.printf(btn.text, x + 10, btn_y + 8, w - 20, "center")
            end
        end
    end
    
    love.graphics.pop()
    love.graphics.setScissor()

    -- Calculate content height for scrollbar
    if active_tab == "Generation" then
        local param_count = 0; for _ in pairs(self.controller.params) do param_count = param_count + 1 end
        local button_count = #self.controller.buttons
        content_height = (param_count * 25) + (button_count * 35) + 60
        self.controller.content_height = content_height

        -- Draw scrollbar
        if content_height > h - 80 then
            local scrollbar_h = (h - 55) * ((h - 80) / content_height)
            local scrollbar_y_pos = y + 50 + (scroll_y / content_height) * (h - 80 - scrollbar_h)
            
            love.graphics.setColor(0.3, 0.3, 0.4)
            love.graphics.rectangle("fill", x + w - 15, y + 50, 10, h - 50)
            love.graphics.setColor(0.6, 0.6, 0.7)
            love.graphics.rectangle("fill", x + w - 15, scrollbar_y_pos, 10, scrollbar_h)
        end
    end
    
    love.graphics.pop()
    love.graphics.setColor(1, 1, 1)
    love.graphics.setLineWidth(1)
end

return DebugMenuView