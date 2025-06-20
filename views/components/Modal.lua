-- ui/modal.lua
-- Defines a modal window that can display and interact with a pannable tech tree.

local Modal = {}
Modal.__index = Modal

function Modal:new(title, w, h, on_close_callback, tech_tree_data)
    local instance = setmetatable({}, Modal)
    
    instance.title = title or "Modal"
    instance.w = w or 400
    instance.h = h or 300
    
    local screen_w, screen_h = love.graphics.getDimensions()
    instance.x = (screen_w - instance.w) / 2
    instance.y = (screen_h - instance.h) / 2
    
    instance.close_button = { x = instance.x + instance.w - 25, y = instance.y + 5, w = 20, h = 20 }
    instance.on_close = on_close_callback

    -- Tech tree properties
    instance.tree_data = tech_tree_data
    instance.node_layout = {}
    instance.hovered_node_id = nil
    instance.visible_nodes = {} -- Nodes to be drawn (purchased or prerequisites met)

    -- Panning properties
    instance.is_panning = false
    instance.pan_start_x = 0
    instance.pan_start_y = 0
    instance.view_offset_x = 0
    instance.view_offset_y = 0

    -- Constants for drawing
    instance.NODE_SIZE = 64
    instance.GRID_SPACING_X = 140
    instance.GRID_SPACING_Y = 120
    instance.CONTENT_PADDING = 50

    instance:_calculateLayout()

    return instance
end

function Modal:_calculateLayout()
    if not self.tree_data or not self.tree_data.tree then return end

    local min_x, max_x = math.huge, -math.huge
    local min_y, max_y = math.huge, -math.huge

    -- 1. Calculate the bounds of the tree based on grid positions
    for _, node in ipairs(self.tree_data.tree) do
        min_x = math.min(min_x, node.position.x)
        max_x = math.max(max_x, node.position.x)
        min_y = math.min(min_y, node.position.y)
        max_y = math.max(max_y, node.position.y)
    end
    
    local tree_grid_width = (max_x - min_x)
    local tree_pixel_width = tree_grid_width * self.GRID_SPACING_X

    -- 2. Calculate the horizontal offset to center the tree
    local content_width = self.w - (self.CONTENT_PADDING * 2)
    local center_offset_x = (content_width - tree_pixel_width) / 2
    
    -- 3. Calculate the final screen positions for each node
    for _, node in ipairs(self.tree_data.tree) do
        self.node_layout[node.id] = {
            x = self.x + self.CONTENT_PADDING + center_offset_x + ((node.position.x - min_x) * self.GRID_SPACING_X),
            -- The tree now builds UP from the bottom
            y = self.y + self.h - self.CONTENT_PADDING - self.NODE_SIZE - (node.position.y * self.GRID_SPACING_Y),
            w = self.NODE_SIZE,
            h = self.NODE_SIZE
        }
    end
end


function Modal:update(dt, game)
    -- Update Panning
    if self.is_panning then
        local mx, my = love.mouse.getPosition()
        local dx = mx - self.pan_start_x
        local dy = my - self.pan_start_y
        self.view_offset_x = self.view_offset_x + dx
        self.view_offset_y = self.view_offset_y + dy
        self.pan_start_x = mx
        self.pan_start_y = my
    end

    -- Update visible nodes based on game state
    self.visible_nodes = {}
    for _, node_data in ipairs(self.tree_data.tree) do
        local is_purchased = (game.state.upgrades_purchased[node_data.id] or 0) > 0
        local prereqs_met = true
        for _, prereq_id in ipairs(node_data.prerequisites) do
            if (game.state.upgrades_purchased[prereq_id] or 0) == 0 then
                prereqs_met = false
                break
            end
        end
        if is_purchased or prereqs_met then
            self.visible_nodes[node_data.id] = true
        end
    end

    -- Update hovered node
    self.hovered_node_id = nil
    local mx, my = love.mouse.getPosition()
    for id, layout in pairs(self.node_layout) do
        local node_x = layout.x + self.view_offset_x
        local node_y = layout.y + self.view_offset_y
        if self.visible_nodes[id] and mx > node_x and mx < node_x + layout.w and my > node_y and my < node_y + layout.h then
            self.hovered_node_id = id
            break
        end
    end
end

function Modal:draw(game)
    -- Draw background overlay
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())

    -- Draw modal panel
    love.graphics.setColor(0.15, 0.15, 0.2)
    love.graphics.rectangle("fill", self.x, self.y, self.w, self.h)
    love.graphics.setColor(0.2, 0.2, 0.25)
    love.graphics.rectangle("fill", self.x, self.y, self.w, 30)
    love.graphics.setColor(0.5, 0.5, 0.6)
    love.graphics.rectangle("line", self.x, self.y, self.w, self.h)
    love.graphics.line(self.x, self.y + 30, self.x + self.w, self.y + 30)

    -- Push a scissor to contain the tree content within the modal body
    love.graphics.push()
    love.graphics.setScissor(self.x + 1, self.y + 31, self.w - 2, self.h - 32)
    
    -- Apply the panning view offset
    love.graphics.translate(self.view_offset_x, self.view_offset_y)
    self:_drawTree(game)
    love.graphics.pop() -- Removes translate and scissor

    -- Draw UI elements that should not be panned (title, close button)
    love.graphics.setColor(1, 1, 1)
    love.graphics.setFont(game.fonts.ui)
    love.graphics.print(self.title, self.x + 10, self.y + 7)
    
    -- RESTORED: Explicitly draw the close button box and the "X" text inside it.
    love.graphics.rectangle("line", self.close_button.x, self.close_button.y, self.close_button.w, self.close_button.h)
    love.graphics.printf("X", self.close_button.x, self.close_button.y + 2, self.close_button.w, "center")

    -- Draw tooltips on top of everything
    if self.hovered_node_id then
        self:_drawTooltip(game)
    end
end

function Modal:_drawTree(game)
    if not self.tree_data then return end

    -- 1. Draw connecting lines
    love.graphics.setLineWidth(3)
    for _, node_data in ipairs(self.tree_data.tree) do
        local node_layout = self.node_layout[node_data.id]
        for _, prereq_id in ipairs(node_data.prerequisites) do
            local prereq_layout = self.node_layout[prereq_id]
            -- Only draw the line if both the prerequisite and the target node are visible
            if prereq_layout and self.visible_nodes[prereq_id] and self.visible_nodes[node_data.id] then
                local is_purchased = (game.state.upgrades_purchased[node_data.id] or 0) > 0
                if is_purchased then
                    love.graphics.setColor(0.6, 1.0, 0.6, 0.8) -- Bright green for purchased path
                else
                    love.graphics.setColor(0.7, 0.7, 1.0, 0.6) -- Blue for available path
                end
                -- Line now goes from top of prerequisite node to bottom of current node
                love.graphics.line(prereq_layout.x + self.NODE_SIZE / 2, prereq_layout.y,
                                   node_layout.x + self.NODE_SIZE / 2, node_layout.y + self.NODE_SIZE)
            end
        end
    end
    love.graphics.setLineWidth(1)

    -- 2. Draw the upgrade nodes
    for _, node_data in ipairs(self.tree_data.tree) do
        -- Only draw nodes that are visible (purchased or prerequisites met)
        if self.visible_nodes[node_data.id] then
            local layout = self.node_layout[node_data.id]
            local purchased_level = game.state.upgrades_purchased[node_data.id] or 0
            local is_available = game.state:isUpgradeAvailable(node_data.id)
            local cost = node_data.cost * (node_data.cost_multiplier ^ purchased_level)
            local can_afford = game.state.money >= cost

            -- Base color
            if purchased_level >= node_data.max_level then love.graphics.setColor(0.4, 0.8, 0.4) -- Maxed out
            elseif purchased_level > 0 then love.graphics.setColor(0.8, 0.8, 0.6) -- Purchased
            else love.graphics.setColor(0.5, 0.5, 0.8) end -- Available
            love.graphics.rectangle("fill", layout.x, layout.y, layout.w, layout.h)

            -- Border color
            if self.hovered_node_id == node_data.id then love.graphics.setColor(1, 1, 0) -- Hover
            elseif is_available and can_afford and purchased_level < node_data.max_level then love.graphics.setColor(1, 1, 1) -- Purchasable
            else love.graphics.setColor(0.6, 0.6, 0.6) end -- Default
            love.graphics.rectangle("line", layout.x, layout.y, layout.w, layout.h)

            -- Icon
            love.graphics.setFont(game.fonts.emoji)
            love.graphics.printf(node_data.icon, layout.x, layout.y + 4, layout.w, "center")

            -- Price
            love.graphics.setFont(game.fonts.ui_small)
            love.graphics.setColor(1,1,1)
            love.graphics.printf("$"..math.floor(cost), layout.x, layout.y + layout.h - 28, layout.w, "center")

            -- Level indicator (now shows 0/N for available upgrades)
            if is_available then
                love.graphics.setFont(game.fonts.ui_small)
                love.graphics.setColor(0,0,0,0.5)
                love.graphics.rectangle("fill", layout.x, layout.y + layout.h - 14, layout.w, 14)
                love.graphics.setColor(1,1,1)
                love.graphics.printf(string.format("%d/%d", purchased_level, node_data.max_level), layout.x, layout.y + layout.h - 13, layout.w, "center")
            end
        end

        -- Draw undiscovered nodes ("fog of war")
        local prereqs_met = game.state:isUpgradeAvailable(node_data.id)
        if not prereqs_met then
            local should_draw_fogged = false
            for _, prereq_id in ipairs(node_data.prerequisites) do
                if self.visible_nodes[prereq_id] then should_draw_fogged = true; break; end
            end
            if should_draw_fogged then
                local layout = self.node_layout[node_data.id]
                love.graphics.setColor(0.3, 0.3, 0.3)
                love.graphics.rectangle("fill", layout.x, layout.y, layout.w, layout.h)
                love.graphics.setColor(0.6, 0.6, 0.6)
                love.graphics.rectangle("line", layout.x, layout.y, layout.w, layout.h)
                love.graphics.setFont(game.fonts.emoji)
                love.graphics.printf(node_data.icon, layout.x, layout.y + 4, layout.w, "center")
                love.graphics.setFont(game.fonts.ui_small)
                love.graphics.printf("???", layout.x, layout.y + layout.h - 28, layout.w, "center")
            end
        end
    end
end

function Modal:_drawTooltip(game)
    local node_data = game.state.Upgrades.AllUpgrades[self.hovered_node_id]
    if not node_data then return end

    -- Do not show tooltip for undiscovered nodes
    if not game.state:isUpgradeAvailable(self.hovered_node_id) then return end

    local mx, my = love.mouse.getPosition()
    local purchased_level = game.state.upgrades_purchased[node_data.id] or 0
    local cost = node_data.cost * (node_data.cost_multiplier ^ purchased_level)
    
    local text_lines = { node_data.name .. string.format(" (%d/%d)", purchased_level, node_data.max_level), node_data.description }
    if purchased_level < node_data.max_level then table.insert(text_lines, "Cost: $" .. math.floor(cost)) end

    if purchased_level >= node_data.max_level then table.insert(text_lines, "Status: MAX LEVEL")
    elseif not (game.state.money >= cost) then table.insert(text_lines, "Status: Insufficient Funds")
    else table.insert(text_lines, "Status: Click to purchase") end

    love.graphics.setFont(game.fonts.ui_small)
    local max_w = 0
    for _, line in ipairs(text_lines) do max_w = math.max(max_w, game.fonts.ui_small:getWidth(line)) end
    
    local tooltip_w, tooltip_h = max_w + 20, #text_lines * 15 + 10
    local tooltip_x, tooltip_y = mx + 15, my
    love.graphics.setColor(0, 0, 0, 0.9); love.graphics.rectangle("fill", tooltip_x, tooltip_y, tooltip_w, tooltip_h)
    love.graphics.setColor(1, 1, 1); love.graphics.rectangle("line", tooltip_x, tooltip_y, tooltip_w, tooltip_h)
    for i, line in ipairs(text_lines) do love.graphics.print(line, tooltip_x + 10, tooltip_y + 5 + (i-1) * 15) end
end

function Modal:handle_mouse_down(x, y, game)
    -- This check for the close button is now guaranteed to work.
    if x > self.close_button.x and x < self.close_button.x + self.close_button.w and
       y > self.close_button.y and y < self.close_button.y + self.close_button.h then
        if self.on_close then self.on_close() end
        return true
    end

    local click_handled = false
    -- Handle clicks on tech tree nodes (adjusting for view offset)
    if self.hovered_node_id then
        local node_data = game.state.Upgrades.AllUpgrades[self.hovered_node_id]
        local purchased_level = game.state.upgrades_purchased[self.hovered_node_id] or 0
        local is_available = game.state:isUpgradeAvailable(self.hovered_node_id)
        local cost = node_data.cost * (node_data.cost_multiplier ^ purchased_level)
        if is_available and purchased_level < node_data.max_level and game.state.money >= cost then
            game.EventBus:publish("ui_purchase_upgrade_clicked", self.hovered_node_id)
        end
        click_handled = true
    end
    
    -- If the click was not on a node, start panning
    if not click_handled and (x > self.x and x < self.x + self.w and y > self.y and y < self.y + self.h) then
        self.is_panning = true
        self.pan_start_x = x
        self.pan_start_y = y
        click_handled = true
    end

    return click_handled
end

function Modal:handle_mouse_up(x, y, game)
    -- Stop panning when the mouse is released
    self.is_panning = false
    -- We return true if the mouse was released anywhere, to signify the event was handled by the modal
    return true
end

return Modal