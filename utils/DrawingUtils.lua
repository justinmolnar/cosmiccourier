-- utils/DrawingUtils.lua
local DrawingUtils = {}

-- Font management utilities
function DrawingUtils.withFont(font, func, ...)
    local old_font = love.graphics.getFont()
    love.graphics.setFont(font)
    local result = func(...)
    love.graphics.setFont(old_font)
    return result
end

function DrawingUtils.drawWorldIcon(game, icon, px, py)
    local g = love.graphics
    
    g.push()
    g.translate(px, py)
    g.scale(1 / game.camera.scale, 1 / game.camera.scale)
    
    -- Draw icon with a slight black outline/shadow for better visibility
    g.setFont(game.fonts.emoji)
    g.setColor(0, 0, 0, 0.6)
    g.print(icon, -13, -13) -- Offset for shadow
    
    g.setColor(1, 1, 1)
    g.print(icon, -14, -14) -- Centered icon
    
    g.pop()
end

function DrawingUtils.setFontSafe(font)
    if font then
        love.graphics.setFont(font)
    end
end

-- Color management utilities
function DrawingUtils.withColor(color, func, ...)
    local old_r, old_g, old_b, old_a = love.graphics.getColor()
    if #color >= 3 then
        love.graphics.setColor(color[1], color[2], color[3], color[4] or 1)
    end
    local result = func(...)
    love.graphics.setColor(old_r, old_g, old_b, old_a)
    return result
end

function DrawingUtils.setColorSafe(color, alpha)
    if color then
        if #color >= 3 then
            love.graphics.setColor(color[1], color[2], color[3], alpha or color[4] or 1)
        end
    end
end

-- Scissor management utilities
function DrawingUtils.withScissor(x, y, w, h, func, ...)
    love.graphics.push()
    love.graphics.setScissor(x, y, w, h)
    local result = func(...)
    love.graphics.setScissor()
    love.graphics.pop()
    return result
end

function DrawingUtils.setScissorSafe(x, y, w, h)
    if x and y and w and h then
        love.graphics.setScissor(x, y, w, h)
    end
end

-- Transform utilities
function DrawingUtils.withTransform(tx, ty, sx, sy, func, ...)
    love.graphics.push()
    if tx or ty then
        love.graphics.translate(tx or 0, ty or 0)
    end
    if sx or sy then
        love.graphics.scale(sx or 1, sy or sx or 1)
    end
    local result = func(...)
    love.graphics.pop()
    return result
end

-- Combined drawing state utilities
function DrawingUtils.withDrawingState(state, func, ...)
    local old_font = love.graphics.getFont()
    local old_r, old_g, old_b, old_a = love.graphics.getColor()
    
    if state.font then love.graphics.setFont(state.font) end
    if state.color then DrawingUtils.setColorSafe(state.color, state.alpha) end
    if state.scissor then 
        love.graphics.setScissor(state.scissor.x, state.scissor.y, state.scissor.w, state.scissor.h) 
    end
    
    local result = func(...)
    
    if state.scissor then love.graphics.setScissor() end
    love.graphics.setColor(old_r, old_g, old_b, old_a)
    love.graphics.setFont(old_font)
    
    return result
end

-- Text drawing utilities
function DrawingUtils.drawTextCentered(text, x, y, w, font, color)
    DrawingUtils.withDrawingState({font = font, color = color}, function()
        love.graphics.printf(text, x, y, w, "center")
    end)
end

function DrawingUtils.drawTextWithBackground(text, x, y, bg_color, text_color, padding)
    padding = padding or 5
    local font = love.graphics.getFont()
    local text_w = font:getWidth(text)
    local text_h = font:getHeight()
    
    -- Draw background
    DrawingUtils.withColor(bg_color, function()
        love.graphics.rectangle("fill", x - padding, y - padding, text_w + padding * 2, text_h + padding * 2)
    end)
    
    -- Draw text
    DrawingUtils.withColor(text_color, function()
        love.graphics.print(text, x, y)
    end)
end

-- Icon drawing utilities
function DrawingUtils.drawIconScaled(icon, x, y, scale, font, color)
    DrawingUtils.withTransform(x, y, 1/scale, 1/scale, function()
        DrawingUtils.withDrawingState({font = font, color = color}, function()
            love.graphics.print(icon, -14, -14) -- Centered
        end)
    end)
end

-- UI element utilities
function DrawingUtils.drawButton(x, y, w, h, text, bg_color, border_color, text_color, font)
    -- Background
    DrawingUtils.withColor(bg_color, function()
        love.graphics.rectangle("fill", x, y, w, h)
    end)
    
    -- Border
    DrawingUtils.withColor(border_color, function()
        love.graphics.rectangle("line", x, y, w, h)
    end)
    
    -- Text
    DrawingUtils.withDrawingState({font = font, color = text_color}, function()
        love.graphics.printf(text, x, y + h/2 - love.graphics.getFont():getHeight()/2, w, "center")
    end)
end

function DrawingUtils.drawPanel(x, y, w, h, bg_color, border_color)
    -- Background
    DrawingUtils.withColor(bg_color, function()
        love.graphics.rectangle("fill", x, y, w, h)
    end)
    
    -- Border
    DrawingUtils.withColor(border_color, function()
        love.graphics.rectangle("line", x, y, w, h)
    end)
end

return DrawingUtils