-- views/sandbox/ZoneModal.lua
-- Floating modal for per-region road generation settings.
-- Visual style matches views/components/Modal.lua (same colors, header, close button).
-- Uses Slider components from the sidebar.

local ZoneModal = {}
ZoneModal.__index = ZoneModal

local Slider = require("views.components.Slider")

local MODAL_W   = 290
local MODAL_PAD = 12
local HEADER_H  = 32
local BTN_H     = 32

function ZoneModal:new(region, region_params, game, on_regen, on_close)
    local inst = setmetatable({}, ZoneModal)
    inst.region        = region
    inst.region_params = region_params   -- mutable table owned by SandboxController
    inst.game          = game
    inst.on_regen      = on_regen
    inst.on_close      = on_close

    inst.sliders  = {}
    inst.h        = 0
    inst.x, inst.y = 0, 0
    inst.btn_regen = {}
    inst.btn_close = {}
    inst.close_btn = {}

    inst:_buildContent()

    return inst
end

-- Position the modal near a screen point, clamped to screen bounds.
function ZoneModal:positionNear(sx, sy)
    local sw, sh = love.graphics.getDimensions()
    local x = math.min(sx + 20, sw - MODAL_W - 10)
    local y = math.min(sy - self.h / 2, sh - self.h - 30)
    y = math.max(y, 5)
    self.x, self.y = x, y
    self:_layoutSliders()
    self:_layoutButtons()
end

-- (Re-)build the slider list from region_params.street_algo.
-- Called on construction and whenever the algo slider changes.
function ZoneModal:_buildContent()
    local rp   = self.region_params
    local game = self.game
    local sliders = {}

    local function addSlider(label, key, min, max, is_int)
        local s = Slider:new(label, min, max, rp[key], is_int, function(v)
            rp[key] = v
            if key == "street_algo" then
                self:_buildContent()
                self:_layoutSliders()
                self:_layoutButtons()
            end
        end, game)
        s.w = MODAL_W - MODAL_PAD * 2
        table.insert(sliders, s)
    end

    addSlider("Road Algo 1-4", "street_algo", 1, 4, true)
    local algo = math.floor(rp.street_algo)
    if algo == 1 then
        addSlider("Min Block", "min_block_size", 4, 40, true)
        addSlider("Max Block", "max_block_size", 4, 60, true)
    elseif algo == 2 then
        addSlider("Block Size",    "block_size",    6,    50,   true)
        addSlider("Warp Strength", "warp_strength", 1,    12,   true)
    elseif algo == 3 then
        addSlider("Num Spokes", "num_spokes", 4, 16, true)
        addSlider("Num Rings",  "num_rings",  1,  8, true)
    elseif algo == 4 then
        addSlider("Road Length",   "max_road_length", 10,   80,   true)
        addSlider("Branch Chance", "branch_chance",   0.01, 0.30, false)
        addSlider("Num Seeds",     "num_seeds",       10,   80,   true)
    end

    self.sliders = sliders
    self.h = HEADER_H + #sliders * 32 + BTN_H + MODAL_PAD * 3
end

function ZoneModal:_layoutSliders()
    for i, s in ipairs(self.sliders) do
        s.x = self.x + MODAL_PAD
        s.y = self.y + HEADER_H + (i - 1) * 32
    end
end

function ZoneModal:_layoutButtons()
    local btn_y = self.y + HEADER_H + #self.sliders * 32 + MODAL_PAD
    local bw    = math.floor((MODAL_W - MODAL_PAD * 3) / 2)

    self.btn_regen = { x = self.x + MODAL_PAD,           y = btn_y, w = bw,  h = BTN_H }
    self.btn_close = { x = self.x + MODAL_PAD * 2 + bw,  y = btn_y, w = bw,  h = BTN_H }
    -- Close-X in header (matches Modal.lua style)
    self.close_btn = { x = self.x + MODAL_W - 26, y = self.y + 6, w = 20, h = 20 }
end

-- ── Draw ─────────────────────────────────────────────────────────────────────

function ZoneModal:draw()
    local game      = self.game
    local x, y, w  = self.x, self.y, MODAL_W
    local h         = self.h

    -- Panel background (Modal.lua palette)
    love.graphics.setColor(0.15, 0.15, 0.2)
    love.graphics.rectangle("fill", x, y, w, h)

    -- Header bar
    love.graphics.setColor(0.2, 0.2, 0.25)
    love.graphics.rectangle("fill", x, y, w, HEADER_H)

    -- Border + header divider
    love.graphics.setColor(0.5, 0.5, 0.6)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x, y, w, h)
    love.graphics.line(x, y + HEADER_H, x + w, y + HEADER_H)

    -- Title
    love.graphics.setColor(1, 1, 1)
    love.graphics.setFont(game.fonts.ui_small)
    local zone = self.region.zone or "?"
    love.graphics.print(
        string.format("Region %s  (%s)", tostring(self.region.id), zone),
        x + MODAL_PAD, y + 8)

    -- Close-X button (top-right, same as Modal.lua)
    local cb = self.close_btn
    love.graphics.setColor(0.8, 0.3, 0.3)
    love.graphics.rectangle("fill", cb.x, cb.y, cb.w, cb.h)
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle("line",  cb.x, cb.y, cb.w, cb.h)
    love.graphics.printf("×", cb.x, cb.y + 2, cb.w, "center")

    -- Sliders (scissored to panel body so they don't overflow)
    love.graphics.setScissor(x + 1, y + HEADER_H + 1, w - 2, h - HEADER_H - 2)
    for _, s in ipairs(self.sliders) do s:draw() end
    love.graphics.setScissor()

    -- Regenerate button
    local br = self.btn_regen
    love.graphics.setColor(0.18, 0.52, 0.18)
    love.graphics.rectangle("fill", br.x, br.y, br.w, br.h)
    love.graphics.setColor(0.5, 0.8, 0.5)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", br.x, br.y, br.w, br.h)
    love.graphics.setColor(1, 1, 1)
    love.graphics.setFont(game.fonts.ui_small)
    love.graphics.printf("Regenerate", br.x, br.y + 8, br.w, "center")

    -- Close button
    local bc = self.btn_close
    love.graphics.setColor(0.4, 0.15, 0.15)
    love.graphics.rectangle("fill", bc.x, bc.y, bc.w, bc.h)
    love.graphics.setColor(0.7, 0.4, 0.4)
    love.graphics.rectangle("line", bc.x, bc.y, bc.w, bc.h)
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf("Close", bc.x, bc.y + 8, bc.w, "center")

    love.graphics.setColor(1, 1, 1)
end

-- ── Input ────────────────────────────────────────────────────────────────────

local function hit(rect, x, y)
    return x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h
end

function ZoneModal:handle_mouse_down(x, y, button)
    if button ~= 1 then return false end

    -- Close-X (header)
    if hit(self.close_btn, x, y) then
        if self.on_close then self.on_close() end; return true
    end
    -- Regenerate button
    if hit(self.btn_regen, x, y) then
        if self.on_regen then self.on_regen() end; return true
    end
    -- Close button
    if hit(self.btn_close, x, y) then
        if self.on_close then self.on_close() end; return true
    end
    -- Sliders
    for _, s in ipairs(self.sliders) do
        if s:handle_mouse_down(x, y, button) then return true end
    end
    -- Click outside modal → close
    if x < self.x or x > self.x + MODAL_W or y < self.y or y > self.y + self.h then
        if self.on_close then self.on_close() end
        return true
    end
    return true  -- absorb all clicks while modal is open
end

function ZoneModal:handle_mouse_moved(x, y, dx, dy)
    for _, s in ipairs(self.sliders) do
        if s.is_dragging then
            s:handle_mouse_moved(x, y, dx, dy)
        end
    end
end

function ZoneModal:handle_mouse_up(x, y, button)
    for _, s in ipairs(self.sliders) do
        s:handle_mouse_up(x, y, button)
    end
end

function ZoneModal:is_dragging_slider()
    for _, s in ipairs(self.sliders) do
        if s.is_dragging then return true end
    end
    return false
end

return ZoneModal
