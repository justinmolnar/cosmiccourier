-- views/components/PackModal.lua
-- Modal displayed when a rule pack is opened.
-- Horizontal card layout showing each unlocked rule template.
-- Uses the same block renderer as DispatchTab for visual consistency.

local PackModal = {}
PackModal.__index = PackModal

-- ── Layout constants ─────────────────────────────────────────────────────────
local CARD_PAD     = 16
local CARD_GAP     = 14
local HEADER_H     = 36
local CARD_HEADER  = 48
local CARD_MAX_H   = 380
local CARD_W       = 320

function PackModal:new(pack_data, result, on_close)
    local instance = setmetatable({}, PackModal)

    instance.pack     = pack_data
    instance.result   = result
    instance.on_close = on_close

    local templates = result and result.templates or {}
    local card_count = math.max(1, #templates)

    -- Modal sizing
    local cards_w = card_count * CARD_W + (card_count - 1) * CARD_GAP
    instance.w = cards_w + CARD_PAD * 2
    instance.h = HEADER_H + CARD_PAD + CARD_MAX_H + CARD_PAD

    local sw, sh = love.graphics.getDimensions()
    instance.x = math.floor((sw - instance.w) / 2)
    instance.y = math.floor((sh - instance.h) / 2)

    instance.game = nil -- set on first draw for scroll measurement

    instance.close_button = {
        x = instance.x + instance.w - 25,
        y = instance.y + 5,
        w = 20, h = 20,
    }

    -- Per-card scroll state
    instance.card_scrolls = {}
    for i = 1, #templates do
        instance.card_scrolls[i] = 0
    end

    return instance
end

function PackModal:update(dt, game) end

-- ── Main draw ────────────────────────────────────────────────────────────────

function PackModal:draw(game)
    -- Lazy-require to avoid circular dependency at load time
    local DT = require("views.tabs.DispatchTab")

    self.game = game
    local x, y, w, h = self.x, self.y, self.w, self.h
    local font = game.fonts and game.fonts.ui or love.graphics.getFont()
    local small_font = game.fonts and game.fonts.ui_small or font

    -- Dark overlay
    love.graphics.setColor(0, 0, 0, 0.75)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())

    -- Modal panel
    love.graphics.setColor(0.10, 0.10, 0.15)
    love.graphics.rectangle("fill", x, y, w, h, 6, 6)

    -- Header bar
    love.graphics.setColor(0.16, 0.14, 0.08)
    love.graphics.rectangle("fill", x, y, w, HEADER_H, 6, 6)
    love.graphics.rectangle("fill", x, y + HEADER_H - 6, w, 6)

    -- Header text
    local title = self.pack and self.pack.name or "Rule Pack"
    love.graphics.setFont(font)
    love.graphics.setColor(1.0, 0.85, 0.25)
    love.graphics.printf(title, x + 12, y + 9, w - 40, "left")

    -- Border
    love.graphics.setColor(0.45, 0.40, 0.20, 0.6)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x, y, w, h, 6, 6)

    -- Close button
    love.graphics.setColor(0.6, 0.3, 0.3)
    love.graphics.rectangle("fill", self.close_button.x, self.close_button.y, self.close_button.w, self.close_button.h, 3, 3)
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf("x", self.close_button.x, self.close_button.y + 2, self.close_button.w, "center")

    -- Cards
    local templates = self.result and self.result.templates or {}
    local cards_start_x = x + CARD_PAD
    local cards_y       = y + HEADER_H + CARD_PAD
    local card_body_h   = CARD_MAX_H - CARD_HEADER

    for i, t in ipairs(templates) do
        local cx = cards_start_x + (i - 1) * (CARD_W + CARD_GAP)
        local cy = cards_y
        local scroll = self.card_scrolls[i] or 0

        -- Card background
        love.graphics.setColor(0.14, 0.14, 0.20)
        love.graphics.rectangle("fill", cx, cy, CARD_W, CARD_MAX_H, 5, 5)
        love.graphics.setColor(0.28, 0.26, 0.16, 0.5)
        love.graphics.rectangle("line", cx, cy, CARD_W, CARD_MAX_H, 5, 5)

        -- Card header: name
        love.graphics.setFont(font)
        love.graphics.setColor(1.0, 0.95, 0.85)
        love.graphics.printf(t.name or t.id, cx + 8, cy + 6, CARD_W - 16, "left")

        -- Complexity dots + description
        local dots = t.complexity or 1
        for d = 1, dots do
            love.graphics.setColor(1.0, 0.85, 0.25, 0.85)
            love.graphics.circle("fill", cx + 8 + (d - 1) * 9, cy + 28, 3)
        end
        love.graphics.setFont(small_font)
        love.graphics.setColor(0.55, 0.55, 0.65)
        love.graphics.printf(t.desc or "", cx + 8 + dots * 9 + 6, cy + 24, CARD_W - 20 - dots * 9, "left")

        -- Divider
        love.graphics.setColor(0.3, 0.28, 0.18, 0.5)
        love.graphics.line(cx + 6, cy + CARD_HEADER - 2, cx + CARD_W - 6, cy + CARD_HEADER - 2)

        -- Block preview area (scissored for scroll)
        local preview_y = cy + CARD_HEADER
        love.graphics.setScissor(cx + 1, preview_y, CARD_W - 2, card_body_h - 2)
        love.graphics.push()
        love.graphics.translate(0, -scroll)

        -- Use the real DispatchTab renderer with nil for interactive params
        local stack = t.build()
        DT.drawNodeList(stack, cx + 8, preview_y, CARD_W - 16, game, nil, nil, nil, nil, 1.0)

        love.graphics.pop()
        love.graphics.setScissor()

        -- Scroll indicator if content overflows
        local stack_h = DT.measureStack(stack, game, CARD_W)
        if stack_h > card_body_h then
            local bar_h = math.max(20, card_body_h * (card_body_h / stack_h))
            local bar_y = preview_y + (scroll / (stack_h - card_body_h)) * (card_body_h - bar_h)
            love.graphics.setColor(0.5, 0.45, 0.25, 0.4)
            love.graphics.rectangle("fill", cx + CARD_W - 5, bar_y, 3, bar_h, 1, 1)
        end
    end

    if #templates == 0 then
        love.graphics.setFont(font)
        love.graphics.setColor(0.5, 0.5, 0.6)
        love.graphics.printf("No new rules unlocked.", x + CARD_PAD, cards_y + 20, w - CARD_PAD * 2, "center")
    end
end

-- ── Input ────────────────────────────────────────────────────────────────────

function PackModal:handle_mouse_down(x, y, game)
    -- Outside modal → close
    if not (x >= self.x and x <= self.x + self.w and y >= self.y and y <= self.y + self.h) then
        if self.on_close then self.on_close() end
        return true
    end

    -- Close button
    local cb = self.close_button
    if x >= cb.x and x <= cb.x + cb.w and y >= cb.y and y <= cb.y + cb.h then
        if self.on_close then self.on_close() end
        return true
    end

    return true
end

function PackModal:handle_mouse_up(x, y, game)
    return false
end

function PackModal:wheelmoved(wx, wy)
    if not self.result or not self.result.templates then return false end

    local DT = require("views.tabs.DispatchTab")
    local mx, my = love.mouse.getPosition()
    local cards_start_x = self.x + CARD_PAD
    local cards_y       = self.y + HEADER_H + CARD_PAD
    local card_body_h   = CARD_MAX_H - CARD_HEADER

    for i, t in ipairs(self.result.templates) do
        local cx = cards_start_x + (i - 1) * (CARD_W + CARD_GAP)
        if mx >= cx and mx <= cx + CARD_W and my >= cards_y and my <= cards_y + CARD_MAX_H then
            local stack = t.build()
            local stack_h = DT.measureStack(stack, self.game or {}, CARD_W)
            local max_scroll = math.max(0, stack_h - card_body_h)
            self.card_scrolls[i] = math.max(0, math.min(max_scroll,
                (self.card_scrolls[i] or 0) - wy * 30))
            return true
        end
    end
    return false
end

return PackModal
