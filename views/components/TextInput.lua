-- views/components/TextInput.lua
-- A numeric text input widget for the sandbox sidebar.
local TextInput = {}
TextInput.__index = TextInput

function TextInput:new(label, initial_val, is_integer, on_commit, game)
    local instance = setmetatable({}, TextInput)
    instance.label      = label
    instance.value      = initial_val
    instance.is_integer = is_integer or false
    instance.on_commit  = on_commit
    instance.game       = game

    -- Layout (set by sidebar manager during _doLayout)
    instance.x, instance.y = 0, 0
    instance.w = 260
    instance.h = 36

    -- Internal state
    instance.is_focused   = false
    instance.text_buffer  = tostring(initial_val)
    instance.cursor_timer = 0
    instance.show_cursor  = true

    -- Field geometry (computed in draw)
    instance.field_x = 0
    instance.field_y = 0
    instance.field_w = 0
    instance.field_h = 24

    return instance
end

function TextInput:update(dt)
    if self.is_focused then
        self.cursor_timer = self.cursor_timer + dt
        if self.cursor_timer >= 0.5 then
            self.cursor_timer = 0
            self.show_cursor = not self.show_cursor
        end
    end
end

function TextInput:draw()
    local game = self.game
    local x, y, w = self.x, self.y, self.w

    love.graphics.setFont(game.fonts.ui_small)

    -- Label
    love.graphics.setColor(0.85, 0.85, 0.85)
    love.graphics.print(self.label, x, y + 10)

    -- Field geometry
    self.field_x = x + 145
    self.field_y = y + 6
    self.field_w = w - 148
    self.field_h = 24

    -- Field background
    if self.is_focused then
        love.graphics.setColor(0.12, 0.18, 0.28)
    else
        love.graphics.setColor(0.12, 0.12, 0.16)
    end
    love.graphics.rectangle("fill", self.field_x, self.field_y, self.field_w, self.field_h, 3)

    -- Field border
    if self.is_focused then
        love.graphics.setColor(0.3, 0.6, 1.0)
    else
        love.graphics.setColor(0.3, 0.3, 0.4)
    end
    love.graphics.rectangle("line", self.field_x, self.field_y, self.field_w, self.field_h, 3)

    -- Text content
    local display_text = self.is_focused and self.text_buffer or tostring(
        self.is_integer and math.floor(self.value) or string.format("%.4g", self.value)
    )

    love.graphics.setColor(1, 1, 0.6)
    love.graphics.setScissor(self.field_x + 2, self.field_y, self.field_w - 8, self.field_h)
    love.graphics.print(display_text, self.field_x + 4, self.field_y + 5)

    -- Cursor
    if self.is_focused and self.show_cursor then
        local text_w = game.fonts.ui_small:getWidth(display_text)
        local cx = self.field_x + 4 + text_w
        love.graphics.setColor(1, 1, 1)
        love.graphics.line(cx, self.field_y + 4, cx, self.field_y + self.field_h - 4)
    end

    love.graphics.setScissor()
    love.graphics.setColor(1, 1, 1)
end

function TextInput:focus()
    if not self.is_focused then
        self.is_focused = true
        self.text_buffer = tostring(
            self.is_integer and math.floor(self.value) or string.format("%.4g", self.value)
        )
        self.cursor_timer = 0
        self.show_cursor = true
    end
end

function TextInput:defocus()
    if self.is_focused then
        self:_commit()
        self.is_focused = false
    end
end

function TextInput:_commit()
    local n = tonumber(self.text_buffer)
    if n then
        if self.is_integer then n = math.floor(n + 0.5) end
        self.value = n
        if self.on_commit then self.on_commit(n) end
    else
        -- Revert to last valid value
        self.text_buffer = tostring(
            self.is_integer and math.floor(self.value) or string.format("%.4g", self.value)
        )
    end
end

function TextInput:handle_mouse_down(x, y, button)
    if button ~= 1 then return false end
    local in_field = x >= self.field_x and x <= self.field_x + self.field_w and
                     y >= self.field_y and y <= self.field_y + self.field_h
    if in_field then
        self:focus()
        return true
    else
        if self.is_focused then
            self:defocus()
        end
        return false
    end
end

function TextInput:handle_textinput(text)
    if not self.is_focused then return false end
    -- Only allow digits, minus (at start), and dot (once)
    for c in text:gmatch(".") do
        if c:match("%d") then
            self.text_buffer = self.text_buffer .. c
        elseif c == "-" and self.text_buffer == "" then
            self.text_buffer = "-"
        elseif c == "." and not self.is_integer and not self.text_buffer:find(".", 1, true) then
            self.text_buffer = self.text_buffer .. "."
        end
    end
    return true
end

function TextInput:handle_keypressed(key)
    if not self.is_focused then return false end
    if key == "return" or key == "kpenter" then
        self:_commit()
        self.is_focused = false
        return true
    elseif key == "escape" then
        -- Revert
        self.text_buffer = tostring(
            self.is_integer and math.floor(self.value) or string.format("%.4g", self.value)
        )
        self.is_focused = false
        return true
    elseif key == "backspace" then
        if #self.text_buffer > 0 then
            self.text_buffer = self.text_buffer:sub(1, -2)
        end
        return true
    end
    return false
end

function TextInput:handle_mouse_moved(x, y, dx, dy) end
function TextInput:handle_mouse_up(x, y, button) end

return TextInput
