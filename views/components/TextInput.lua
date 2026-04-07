-- views/components/TextInput.lua
-- A generic text/numeric input widget for UI panels.
local utf8 = require("utf8")

local TextInput = {}
TextInput.__index = TextInput

-- mode: "text", "number", or "integer"
function TextInput:new(label, initial_val, mode, on_commit, game)
    local instance = setmetatable({}, TextInput)
    instance.label      = label or ""
    instance.value      = initial_val
    instance.mode       = mode or "text" -- "text", "number", "integer"
    instance.on_commit  = on_commit
    instance.game       = game

    -- Layout
    instance.x, instance.y = 0, 0
    instance.w = 260
    instance.h = 36

    -- Internal state
    instance.is_focused   = false
    instance.text_buffer  = tostring(initial_val or "")
    instance.cursor_timer = 0
    instance.show_cursor  = true

    -- Field geometry (computed in draw)
    instance.field_x = 0
    instance.field_y = 0
    instance.field_w = 0
    instance.field_h = 0

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

function TextInput:draw(override_x, override_y, override_w, override_h)
    local game = self.game
    local x = override_x or self.x
    local y = override_y or self.y
    local w = override_w or self.w
    local h = override_h or self.h

    love.graphics.setFont(game.fonts.ui_small)
    local fh = game.fonts.ui_small:getHeight()

    -- Label (only if provided and not overridden in a way that hides it)
    if self.label ~= "" and not override_w then
        love.graphics.setColor(0.85, 0.85, 0.85)
        love.graphics.print(self.label, x, y + (h - fh) / 2)
        self.field_x = x + 145
        self.field_w = w - 148
    else
        self.field_x = x
        self.field_w = w
    end

    -- Respect the passed height but cap it for aesthetics if desired
    self.field_h = h
    self.field_y = y

    -- Field background
    if self.is_focused then
        love.graphics.setColor(0.05, 0.08, 0.15)
    else
        love.graphics.setColor(0.12, 0.12, 0.16)
    end
    love.graphics.rectangle("fill", self.field_x, self.field_y, self.field_w, self.field_h, 3)

    -- Field border
    if self.is_focused then
        love.graphics.setColor(0.4, 0.6, 1.0)
    else
        love.graphics.setColor(0.3, 0.3, 0.4)
    end
    love.graphics.rectangle("line", self.field_x, self.field_y, self.field_w, self.field_h, 3)

    -- Text content
    local display_text = self.is_focused and self.text_buffer or tostring(self.value or "")
    if not self.is_focused and (self.mode == "number" or self.mode == "integer") then
        local n = tonumber(self.value) or 0
        display_text = self.mode == "integer" and tostring(math.floor(n)) or string.format("%.4g", n)
    end

    love.graphics.setColor(1, 1, 1)
    -- Vertical center the text within the field
    local ty = self.field_y + (self.field_h - fh) / 2
    love.graphics.print(display_text, self.field_x + 6, ty)

    -- Cursor
    if self.is_focused and self.show_cursor then
        local text_w = game.fonts.ui_small:getWidth(display_text)
        local cx = self.field_x + 6 + text_w
        love.graphics.setColor(1, 1, 1)
        love.graphics.line(cx, self.field_y + 2, cx, self.field_y + self.field_h - 2)
    end

    love.graphics.setColor(1, 1, 1)
end

function TextInput:focus()
    if not self.is_focused then
        self.is_focused = true
        self.text_buffer = tostring(self.value or "")
        if self.mode == "number" or self.mode == "integer" then
            local n = tonumber(self.value) or 0
            self.text_buffer = self.mode == "integer" and tostring(math.floor(n)) or string.format("%.4g", n)
        end
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
    local val = self.text_buffer
    if self.mode == "number" or self.mode == "integer" then
        local n = tonumber(val)
        if n then
            if self.mode == "integer" then n = math.floor(n + 0.5) end
            self.value = n
        else
            -- Revert
            return
        end
    else
        self.value = val
    end
    if self.on_commit then self.on_commit(self.value) end
end

function TextInput:handle_mouse_down(x, y, button)
    local in_field = x >= self.field_x and x <= self.field_x + self.field_w and
                     y >= self.field_y and y <= self.field_y + self.field_h
    if in_field then
        self:focus()
        return true
    else
        if self.is_focused then self:defocus() end
        return false
    end
end

function TextInput:handle_textinput(text)
    if not self.is_focused then return false end
    if self.mode == "number" or self.mode == "integer" then
        for c in text:gmatch(".") do
            if c:match("%d") then
                self.text_buffer = self.text_buffer .. c
            elseif c == "-" and self.text_buffer == "" then
                self.text_buffer = "-"
            elseif c == "." and self.mode == "number" and not self.text_buffer:find(".", 1, true) then
                self.text_buffer = self.text_buffer .. "."
            end
        end
    else
        self.text_buffer = self.text_buffer .. text
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
        self.is_focused = false
        return true
    elseif key == "backspace" then
        local byteoffset = utf8.offset(self.text_buffer, -1)
        if byteoffset then
            self.text_buffer = self.text_buffer:sub(1, byteoffset - 1)
        end
        return true
    end
    return false
end

function TextInput:handle_mouse_moved(x, y, dx, dy) end
function TextInput:handle_mouse_up(x, y, button) end

return TextInput
