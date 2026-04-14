-- views/components/LicenseModal.lua
-- Modal showing the player's current license and the next-available purchase.
-- Licenses are a pure scope gate: buying one raises scope_tier and opens
-- access to scope-gated purchases, but bundles nothing.

local LicenseService = require("services.LicenseService")

local LicenseModal = {}
LicenseModal.__index = LicenseModal

-- ── Layout constants ─────────────────────────────────────────────────────────
local PAD         = 18
local HEADER_H    = 40
local CARD_H      = 120
local CARD_GAP    = 12
local BUTTON_H    = 36
local MODAL_W     = 480
local MODAL_H     = HEADER_H + PAD + CARD_H + CARD_GAP + CARD_H + PAD + BUTTON_H + PAD

function LicenseModal:new(on_close)
    local instance = setmetatable({}, LicenseModal)
    instance.on_close = on_close
    instance.w = MODAL_W
    instance.h = MODAL_H

    local sw, sh = love.graphics.getDimensions()
    instance.x = math.floor((sw - instance.w) / 2)
    instance.y = math.floor((sh - instance.h) / 2)

    instance.close_button = {
        x = instance.x + instance.w - 30,
        y = instance.y + 8,
        w = 22, h = 22,
    }

    instance.purchase_button = nil  -- computed each draw when a next license exists
    instance.error_message = nil    -- shown inline on failed purchase
    return instance
end

function LicenseModal:update(dt, game) end

-- ── Draw ─────────────────────────────────────────────────────────────────────

local function drawCard(game, x, y, w, h, title, subtitle, owned, cost)
    local font = game.fonts and game.fonts.ui or love.graphics.getFont()
    local small_font = (game.fonts and game.fonts.ui_small) or font

    if owned then
        love.graphics.setColor(0.14, 0.26, 0.18)
    else
        love.graphics.setColor(0.14, 0.18, 0.26)
    end
    love.graphics.rectangle("fill", x, y, w, h, 6, 6)

    if owned then
        love.graphics.setColor(0.38, 0.72, 0.48, 0.7)
    else
        love.graphics.setColor(0.42, 0.56, 0.82, 0.7)
    end
    love.graphics.rectangle("line", x, y, w, h, 6, 6)

    love.graphics.setFont(font)
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf(title, x + 12, y + 10, w - 24, "left")

    if owned then
        love.graphics.setColor(0.55, 0.92, 0.65)
        love.graphics.printf("OWNED", x + 12, y + 10, w - 24, "right")
    elseif cost then
        love.graphics.setColor(1.0, 0.85, 0.25)
        love.graphics.printf(string.format("$%d", cost), x + 12, y + 10, w - 24, "right")
    end

    love.graphics.setFont(small_font)
    love.graphics.setColor(0.75, 0.78, 0.88)
    love.graphics.printf(subtitle or "", x + 12, y + 40, w - 24, "left")
    love.graphics.setFont(font)
end

function LicenseModal:draw(game)
    local x, y, w, h = self.x, self.y, self.w, self.h
    local font = game.fonts and game.fonts.ui or love.graphics.getFont()
    local small_font = (game.fonts and game.fonts.ui_small) or font

    -- Overlay
    love.graphics.setColor(0, 0, 0, 0.75)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())

    -- Panel
    love.graphics.setColor(0.10, 0.12, 0.18)
    love.graphics.rectangle("fill", x, y, w, h, 8, 8)

    -- Header
    love.graphics.setColor(0.14, 0.20, 0.30)
    love.graphics.rectangle("fill", x, y, w, HEADER_H, 8, 8)
    love.graphics.rectangle("fill", x, y + HEADER_H - 8, w, 8)

    love.graphics.setFont(font)
    love.graphics.setColor(1.0, 0.92, 0.55)
    love.graphics.printf("Operating Licenses", x + 14, y + 11, w - 50, "left")

    -- Border
    love.graphics.setColor(0.42, 0.56, 0.82, 0.6)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x, y, w, h, 8, 8)

    -- Close button
    local cb = self.close_button
    love.graphics.setColor(0.6, 0.3, 0.3)
    love.graphics.rectangle("fill", cb.x, cb.y, cb.w, cb.h, 3, 3)
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf("x", cb.x, cb.y + 3, cb.w, "center")

    -- Current license card
    local current = LicenseService.getCurrent(game)
    local current_x, current_y = x + PAD, y + HEADER_H + PAD
    local card_w = w - PAD * 2
    drawCard(game, current_x, current_y, card_w, CARD_H,
        "Current: " .. (current and current.display_name or "None"),
        current and current.description or "",
        true, nil)

    -- Next license card
    local next_lic = LicenseService.getNextAvailable(game)
    local next_y = current_y + CARD_H + CARD_GAP
    if next_lic then
        drawCard(game, current_x, next_y, card_w, CARD_H,
            "Next: " .. next_lic.display_name,
            next_lic.description or "",
            false, next_lic.cost)
    else
        love.graphics.setColor(0.16, 0.20, 0.26)
        love.graphics.rectangle("fill", current_x, next_y, card_w, CARD_H, 6, 6)
        love.graphics.setColor(0.55, 0.58, 0.68, 0.8)
        love.graphics.rectangle("line", current_x, next_y, card_w, CARD_H, 6, 6)
        love.graphics.setFont(font)
        love.graphics.setColor(0.75, 0.78, 0.88)
        love.graphics.printf("You hold the highest MVP license.",
            current_x, next_y + CARD_H / 2 - 10, card_w, "center")
    end

    -- Purchase button (only when a next license exists)
    if next_lic then
        local ok = LicenseService.canPurchase(game, next_lic.id)
        local btn_x = current_x + card_w / 2 - 120
        local btn_y = next_y + CARD_H + PAD
        local btn_w, btn_h = 240, BUTTON_H
        self.purchase_button = { x = btn_x, y = btn_y, w = btn_w, h = btn_h, license_id = next_lic.id, enabled = ok }

        if ok then
            love.graphics.setColor(0.28, 0.56, 0.32)
        else
            love.graphics.setColor(0.26, 0.28, 0.32)
        end
        love.graphics.rectangle("fill", btn_x, btn_y, btn_w, btn_h, 5, 5)
        love.graphics.setColor(1, 1, 1, ok and 1.0 or 0.5)
        love.graphics.printf(string.format("Purchase  ($%d)", next_lic.cost),
            btn_x, btn_y + 9, btn_w, "center")

        if not ok then
            love.graphics.setFont(small_font)
            love.graphics.setColor(0.95, 0.55, 0.55)
            love.graphics.printf("Insufficient funds",
                btn_x, btn_y + btn_h + 4, btn_w, "center")
            love.graphics.setFont(font)
        end
    else
        self.purchase_button = nil
    end

    if self.error_message then
        love.graphics.setFont(small_font)
        love.graphics.setColor(0.95, 0.55, 0.55)
        love.graphics.printf(self.error_message, x + PAD, y + h - PAD - 14, w - PAD * 2, "center")
        love.graphics.setFont(font)
    end
end

-- ── Input ────────────────────────────────────────────────────────────────────

local function pointIn(px, py, r)
    return px >= r.x and px <= r.x + r.w and py >= r.y and py <= r.y + r.h
end

function LicenseModal:handle_mouse_down(x, y, game)
    -- Outside modal → close
    if not (x >= self.x and x <= self.x + self.w and y >= self.y and y <= self.y + self.h) then
        if self.on_close then self.on_close() end
        return true
    end

    if pointIn(x, y, self.close_button) then
        if self.on_close then self.on_close() end
        return true
    end

    if self.purchase_button and self.purchase_button.enabled and pointIn(x, y, self.purchase_button) then
        local ok, reason = LicenseService.purchase(game, self.purchase_button.license_id)
        if not ok then
            self.error_message = "Purchase failed: " .. tostring(reason)
        else
            self.error_message = nil
        end
        return true
    end

    return true
end

function LicenseModal:handle_mouse_up(x, y, game)
    return false
end

return LicenseModal
