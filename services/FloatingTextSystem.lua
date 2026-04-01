-- services/FloatingTextSystem.lua
-- Self-contained system for floating payout text popups.
-- Owns the list, update logic, and exposes it for rendering.

local FloatingTextSystem = {}

local _texts = {}

function FloatingTextSystem.emit(text, x, y, C)
    table.insert(_texts, {
        text  = text,
        x     = x,
        y     = y,
        timer = C.EFFECTS.PAYOUT_TEXT_LIFESPAN_SEC,
        alpha = 1,
    })
end

function FloatingTextSystem.update(dt, game)
    local speed   = game.C.EFFECTS.PAYOUT_TEXT_FLOAT_SPEED
    local lifespan = game.C.EFFECTS.PAYOUT_TEXT_LIFESPAN_SEC
    local inv_scale = 1 / game.camera.scale
    for i = #_texts, 1, -1 do
        local t = _texts[i]
        t.y     = t.y + speed * inv_scale * dt
        t.timer = t.timer - dt
        t.alpha = t.timer / lifespan
        if t.timer <= 0 then
            table.remove(_texts, i)
        end
    end
end

function FloatingTextSystem.getTexts()
    return _texts
end

function FloatingTextSystem.clear()
    _texts = {}
end

return FloatingTextSystem
