-- views/components/Slider.lua
-- A draggable horizontal slider widget for the sandbox sidebar.
local Slider = {}
Slider.__index = Slider

function Slider:new(label, min_val, max_val, initial_val, is_integer, on_change, game)
    local instance = setmetatable({}, Slider)
    instance.label      = label
    instance.min        = min_val
    instance.max        = max_val
    instance.value      = initial_val
    instance.is_integer = is_integer or false
    instance.on_change  = on_change
    instance.game       = game

    -- Layout (set by sidebar manager during _doLayout)
    instance.x, instance.y = 0, 0
    instance.w = 260
    instance.h = 32

    -- Track geometry (computed during draw so input can use it)
    instance.track_x = 0
    instance.track_w = 0
    instance.track_y = 0

    instance.is_dragging = false
    return instance
end

function Slider:draw()
    local game = self.game
    local x, y, w = self.x, self.y, self.w

    love.graphics.setFont(game.fonts.ui_small)

    -- Label (left side)
    love.graphics.setColor(0.85, 0.85, 0.85)
    love.graphics.print(self.label, x, y + 9)

    -- Value text (right of label, before track)
    local val_str = self.is_integer and tostring(math.floor(self.value))
                    or string.format("%.2f", self.value)
    love.graphics.setColor(1, 1, 0.6)
    love.graphics.printf(val_str, x + 108, y + 9, 38, "right")

    -- Track background
    self.track_x = x + 150
    self.track_w = w - 155
    self.track_y = y + 13

    love.graphics.setColor(0.18, 0.18, 0.22)
    love.graphics.rectangle("fill", self.track_x, self.track_y, self.track_w, 6)

    -- Fill (progress)
    local frac = (self.value - self.min) / math.max(0.0001, self.max - self.min)
    frac = math.max(0, math.min(1, frac))
    love.graphics.setColor(0.25, 0.5, 0.85)
    love.graphics.rectangle("fill", self.track_x, self.track_y, self.track_w * frac, 6)

    -- Handle circle
    local hx = self.track_x + self.track_w * frac
    local hy = self.track_y + 3
    if self.is_dragging then
        love.graphics.setColor(1, 1, 0.3)
    else
        love.graphics.setColor(0.85, 0.85, 0.85)
    end
    love.graphics.circle("fill", hx, hy, 6)

    love.graphics.setColor(1, 1, 1)
end

function Slider:_updateValueFromMouseX(mx)
    local frac = (mx - self.track_x) / math.max(1, self.track_w)
    frac = math.max(0, math.min(1, frac))
    local v = self.min + frac * (self.max - self.min)
    if self.is_integer then v = math.floor(v + 0.5) end
    if v ~= self.value then
        self.value = v
        if self.on_change then self.on_change(v) end
    end
end

function Slider:handle_mouse_down(x, y, button)
    if button ~= 1 then return false end
    -- Hit test the track bar area (generous vertical zone)
    if x >= self.track_x - 2 and x <= self.track_x + self.track_w + 2 and
       y >= self.track_y - 9  and y <= self.track_y + 15 then
        self.is_dragging = true
        self:_updateValueFromMouseX(x)
        return true
    end
    return false
end

function Slider:handle_mouse_moved(x, y, dx, dy)
    if self.is_dragging then
        self:_updateValueFromMouseX(x)
    end
end

function Slider:handle_mouse_up(x, y, button)
    self.is_dragging = false
end

function Slider:handle_textinput(text) return false end
function Slider:handle_keypressed(key) return false end
function Slider:update(dt) end

return Slider
