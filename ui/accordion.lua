-- ui/accordion.lua
local Accordion = {}
Accordion.__index = Accordion

function Accordion:new(title, starts_open, max_content_h)
    local instance = setmetatable({}, Accordion)
    instance.title = title
    instance.is_open = starts_open or false
    instance.max_content_h = max_content_h or 200

    instance.x, instance.y, instance.w = 0, 0, 0
    instance.header_h = 25
    instance.content_h = 0
    instance.total_content_h = 0
    instance.scroll_y = 0
    
    -- New properties for managing scrollbar dragging
    instance.is_dragging_scrollbar = false
    instance.drag_start_y = 0
    instance.scroll_y_at_drag_start = 0

    return instance
end

function Accordion:getScrollbarHandleBounds()
    if self.total_content_h > self.content_h then
        local handle_h = self.content_h * (self.content_h / self.total_content_h)
        handle_h = math.max(handle_h, 15)
        
        local scroll_range = self.total_content_h - self.content_h
        local scroll_percentage = (scroll_range > 0) and (self.scroll_y / scroll_range) or 0
        
        local track_h = self.content_h - handle_h
        local handle_y = self.y + self.header_h + (track_h * scroll_percentage)
        local handle_x = self.x + self.w - 8
        
        return handle_x, handle_y, 6, handle_h
    end
    return nil
end

function Accordion:handle_mouse_down(x, y, button)
    if not self.is_open or self.total_content_h <= self.content_h then return false end

    local hx, hy, hw, hh = self:getScrollbarHandleBounds()
    
    -- Check for click on the handle first (for dragging)
    if hx and x > hx and x < hx + hw and y > hy and y < hy + hh then
        self.is_dragging_scrollbar = true
        self.drag_start_y = y
        self.scroll_y_at_drag_start = self.scroll_y
        return true
    end

    -- NEW: Check for click on the scrollbar track (for paging)
    local track_x = self.x + self.w - 8
    local track_w = 6
    if x > track_x and x < track_x + track_w and y > self.y + self.header_h and y < self.y + self.header_h + self.content_h then
        if hy then -- Check if handle exists
            if y < hy then
                -- Clicked above handle: page up
                self.scroll_y = self.scroll_y - self.content_h
            else
                -- Clicked below handle: page down
                self.scroll_y = self.scroll_y + self.content_h
            end
        end
        
        -- Clamp scroll value immediately
        if self.scroll_y > self.total_content_h - self.content_h then
            self.scroll_y = math.max(0, self.total_content_h - self.content_h)
        end
        if self.scroll_y < 0 then self.scroll_y = 0 end

        return true -- Consume the click
    end

    return false
end

function Accordion:handle_mouse_up(x, y, button)
    self.is_dragging_scrollbar = false
end

function Accordion:update(total_content_h, my)
    self.total_content_h = total_content_h
    self.content_h = math.min(self.max_content_h, self.total_content_h)
    
    -- Handle dragging logic
    if self.is_dragging_scrollbar then
        local mouse_delta_y = my - self.drag_start_y
        
        local _, _, _, handle_h = self:getScrollbarHandleBounds()
        local track_h = self.content_h - (handle_h or 0)
        local content_scroll_range = self.total_content_h - self.content_h

        if track_h > 0 and content_scroll_range > 0 then
            local scroll_per_pixel = content_scroll_range / track_h
            self.scroll_y = self.scroll_y_at_drag_start + (mouse_delta_y * scroll_per_pixel)
        end
    end

    -- Clamp scroll_y to prevent scrolling past content
    if self.scroll_y > self.total_content_h - self.content_h then
        self.scroll_y = math.max(0, self.total_content_h - self.content_h)
    end
    if self.scroll_y < 0 then self.scroll_y = 0 end
end

function Accordion:handle_click(x, y)
    -- FIX: Check against the correct 'header_h' property instead of the non-existent 'h'
    if x > self.x and x < self.x + self.w and y > self.y and y < self.y + self.header_h then
        self.is_open = not self.is_open
        self.scroll_y = 0 -- Reset scroll when toggling
        return true
    end
    return false
end

function Accordion:drawScrollbar()
    if self.is_open and self.total_content_h > self.content_h then
        -- Draw the scrollbar track
        love.graphics.setColor(0, 0, 0, 0.5)
        love.graphics.rectangle("fill", self.x + self.w - 8, self.y + self.header_h, 6, self.content_h)

        -- Calculate handle size and position
        local handle_h = self.content_h * (self.content_h / self.total_content_h)
        handle_h = math.max(handle_h, 15) -- Minimum handle height

        if self.total_content_h > self.content_h then
            local scroll_percentage = self.scroll_y / (self.total_content_h - self.content_h)
            local handle_y = self.y + self.header_h + ((self.content_h - handle_h) * scroll_percentage)
            
            love.graphics.setColor(0.8, 0.8, 0.8, 0.7)
            love.graphics.rectangle("fill", self.x + self.w - 8, handle_y, 6, handle_h)
        end
    end
end

function Accordion:handle_scroll(mx, my, dy)
    if not self.is_open then return false end
    
    -- Check if mouse is within the content area of this accordion
    if mx > self.x and mx < self.x + self.w and my > self.y + self.header_h and my < self.y + self.header_h + self.content_h then
        self.scroll_y = self.scroll_y - (dy * 20) -- Adjust scroll position
        return true
    end
    return false
end

-- Sets up the drawing environment for the accordion's content
function Accordion:beginDraw()
    -- Draw header
    love.graphics.setColor(0.2, 0.2, 0.25)
    love.graphics.rectangle("fill", self.x, self.y, self.w, self.header_h)
    love.graphics.setColor(0.5, 0.5, 0.6)
    love.graphics.rectangle("line", self.x, self.y, self.w, self.header_h)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print(self.title, self.x + 5, self.y + 5)
    local indicator = self.is_open and "[-]" or "[+]"
    love.graphics.printf(indicator, self.x, self.y + 5, self.w - 5, "right")

    if self.is_open then
        love.graphics.push()
        love.graphics.setScissor(self.x, self.y + self.header_h, self.w, self.content_h)
        love.graphics.translate(0, -self.scroll_y)
    end
end

-- Resets the drawing environment
function Accordion:endDraw()
    if self.is_open then
        love.graphics.setScissor()
        love.graphics.pop()
    end
end

return Accordion