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
    
    if hx and x > hx and x < hx + hw and y > hy and y < hy + hh then
        self.is_dragging_scrollbar = true
        self.drag_start_y = y
        self.scroll_y_at_drag_start = self.scroll_y
        return true
    end

    local track_x = self.x + self.w - 8
    local track_w = 6
    if x > track_x and x < track_x + track_w and y > self.y + self.header_h and y < self.y + self.header_h + self.content_h then
        if hy then
            if y < hy then
                self.scroll_y = self.scroll_y - self.content_h
            else
                self.scroll_y = self.scroll_y + self.content_h
            end
        end
        
        if self.scroll_y > self.total_content_h - self.content_h then
            self.scroll_y = math.max(0, self.total_content_h - self.content_h)
        end
        if self.scroll_y < 0 then self.scroll_y = 0 end

        return true
    end

    return false
end

function Accordion:handle_mouse_up(x, y, button)
    self.is_dragging_scrollbar = false
end

function Accordion:update(total_content_h, my)
    self.total_content_h = total_content_h
    self.content_h = math.min(self.max_content_h, self.total_content_h)
    
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

    if self.scroll_y > self.total_content_h - self.content_h then
        self.scroll_y = math.max(0, self.total_content_h - self.content_h)
    end
    if self.scroll_y < 0 then self.scroll_y = 0 end
end

function Accordion:handle_click(x, y)
    if x > self.x and x < self.x + self.w and y > self.y and y < self.y + self.header_h then
        self.is_open = not self.is_open
        self.scroll_y = 0
        return true
    end
    return false
end

function Accordion:drawScrollbar()
    if self.is_open and self.total_content_h > self.content_h then
        love.graphics.setColor(0, 0, 0, 0.5)
        love.graphics.rectangle("fill", self.x + self.w - 8, self.y + self.header_h, 6, self.content_h)

        local handle_h = self.content_h * (self.content_h / self.total_content_h)
        handle_h = math.max(handle_h, 15)

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
    
    if mx > self.x and mx < self.x + self.w and y > self.y + self.header_h and my < self.y + self.header_h + self.content_h then
        self.scroll_y = self.scroll_y - (dy * 20)
        return true
    end
    return false
end

-- MODIFIED FUNCTION: Now accepts an optional stats_text parameter
function Accordion:beginDraw(stats_text)
    love.graphics.setColor(0.2, 0.2, 0.25)
    love.graphics.rectangle("fill", self.x, self.y, self.w, self.header_h)
    love.graphics.setColor(0.5, 0.5, 0.6)
    love.graphics.rectangle("line", self.x, self.y, self.w, self.header_h)
    love.graphics.setColor(1, 1, 1)
    
    local indicator = self.is_open and "[-]" or "[+]"
    love.graphics.print(self.title, self.x + 5, self.y + 5)
    
    -- NEW: Draw the stats text on the right side of the header
    if stats_text and stats_text ~= "" then
        love.graphics.setFont(love.graphics.getFont()) -- Ensure we use the correct font
        local stats_width = love.graphics.getFont():getWidth(stats_text)
        love.graphics.print(stats_text, self.x + self.w - stats_width - 25, self.y + 5)
    end
    
    love.graphics.printf(indicator, self.x, self.y + 5, self.w - 5, "right")

    if self.is_open then
        love.graphics.push()
        love.graphics.setScissor(self.x, self.y + self.header_h, self.w, self.content_h)
        love.graphics.translate(0, -self.scroll_y)
    end
end

function Accordion:endDraw()
    if self.is_open then
        love.graphics.setScissor()
        love.graphics.pop()
    end
end

return Accordion