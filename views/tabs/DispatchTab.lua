-- views/tabs/DispatchTab.lua
-- Sidebar tab: visual block dispatch rule editor.
-- Block defs come from data/dispatch_blocks.lua (pure data).
-- Rules are read/written via game.state.dispatch_rules.

local DispatchTab = {}

local RE        = require("services.DispatchRuleEngine")
local Validator = require("services.DispatchValidator")

-- ── Visual constants ──────────────────────────────────────────────────────────

local BLOCK_H      = 30   -- block pill height
local BLOCK_GAP    = 5    -- horizontal gap between pills
local ROW_VGAP     = 5    -- vertical gap between rows of pills within a rule
local RULE_PAD_V   = 6    -- vertical padding above/below block area
local CAT_HDR_H    = 16   -- height reserved for a category header label
local PAL_MARGIN   = 8    -- palette inner margin

local CAT_COLOR = {
    trigger   = { 0.85, 0.65, 0.10 },
    condition = { 0.22, 0.68, 0.32 },
    logic     = { 0.82, 0.78, 0.15 },
    effect    = { 0.52, 0.28, 0.80 },
    action    = { 0.28, 0.45, 0.88 },
}

-- ── Module-level state ────────────────────────────────────────────────────────

local state = {
    selected_rule   = nil,
    palette_open    = false,
    -- [rule_i][block_i] = {x,y,w,h,def,inst} in panel content coordinates
    block_rects     = {},
    palette_rects   = {},    -- [def_id] = {x,y,w,h,def}
    palette_validity = {},   -- [def_id] = {valid,reason}  — cached from last draw frame
    -- per-card geometry for drop-target detection (set each draw frame)
    rule_card_tops  = {},    -- [rule_i] = content_y of card top
    rule_card_bots  = {},    -- [rule_i] = content_y of card bottom
    -- drag state (nil when not dragging)
    drag = nil,
    -- { type="rule"|"block", rule_i, block_i (block only),
    --   sx, sy (start screen), cx, cy (current screen), active }
}

function DispatchTab.getState() return state end

-- ── Geometry helpers ──────────────────────────────────────────────────────────

local CHAR_W_EST = 9
local function blockPillW(def, slots, font)
    local label = def.label or ""
    local slot_txt = ""
    for _, sd in ipairs(def.slots or {}) do
        slot_txt = slot_txt .. "  " .. tostring(slots and slots[sd.key] or sd.default or "")
    end
    if font then
        return math.max(60, font:getWidth(label) + font:getWidth(slot_txt) + 36)
    end
    return math.max(60, (#label + #slot_txt) * CHAR_W_EST + 36)
end

local function layoutBlocks(blocks, ox, oy, avail_w, font)
    local rects = {}
    local cx, cy = ox, oy
    for i, inst in ipairs(blocks) do
        local def = RE.getDefById(inst.def_id)
        if def then
            local w = blockPillW(def, inst.slots, font)
            if #rects > 0 and cx + w > ox + avail_w then
                cx = ox
                cy = cy + BLOCK_H + ROW_VGAP
            end
            rects[i] = { x = cx, y = cy, w = w, h = BLOCK_H, def = def, inst = inst }
            cx = cx + w + BLOCK_GAP
        end
    end
    local total_h = (#rects > 0) and ((rects[#rects].y - oy) + BLOCK_H) or 0
    return rects, total_h
end

local function layoutPalette(ox, oy, avail_w, font)
    local all_defs = RE.getAllDefs()
    local rects    = {}
    local cx, cy   = ox, oy + CAT_HDR_H
    local last_cat = nil

    for _, def in ipairs(all_defs) do
        if def.category ~= last_cat then
            if last_cat then
                cx = ox
                cy = cy + BLOCK_H + ROW_VGAP + CAT_HDR_H + 4
            end
            last_cat = def.category
        end
        local w = blockPillW(def, nil, font)
        if cx + w > ox + avail_w and cx > ox then
            cx = ox
            cy = cy + BLOCK_H + ROW_VGAP
        end
        rects[def.id] = { x = cx, y = cy, w = w, h = BLOCK_H, def = def }
        cx = cx + w + BLOCK_GAP
    end

    local max_y = oy
    for _, r in pairs(rects) do
        if r.y + r.h > max_y then max_y = r.y + r.h end
    end
    return rects, max_y - oy
end

-- ── Block rendering ───────────────────────────────────────────────────────────

-- warn=true draws an orange warning badge in the top-right corner of the pill
local function drawBlockPill(def, slots, x, y, w, h, game, alpha, warn)
    local font = game.fonts.ui_small
    local c = def.color or CAT_COLOR[def.category] or { 0.5, 0.5, 0.5 }
    local a = alpha or 1
    love.graphics.setColor(c[1], c[2], c[3], a)
    love.graphics.rectangle("fill", x, y, w, h, 4, 4)
    -- Warning: orange border instead of dark border
    if warn then
        love.graphics.setColor(0.95, 0.62, 0.12, a)
        love.graphics.setLineWidth(2)
    else
        love.graphics.setColor(0, 0, 0, 0.3 * a)
        love.graphics.setLineWidth(1)
    end
    love.graphics.rectangle("line", x, y, w, h, 4, 4)
    love.graphics.setLineWidth(1)

    love.graphics.setFont(font)
    local fh = font:getHeight()

    for _, sd in ipairs(def.slots or {}) do
        local val = tostring(slots and slots[sd.key] or sd.default or "?")
        local spw = font:getWidth(val) + 14
        local spx = x + w - spw - 4
        local spy = y + (h - 16) / 2
        love.graphics.setColor(1, 1, 1, 0.25 * a)
        love.graphics.rectangle("fill", spx, spy, spw, 16, 3, 3)
        love.graphics.setColor(1, 1, 1, a)
        love.graphics.print(val, spx + 7, spy + (16 - fh) / 2)
    end

    love.graphics.setColor(1, 1, 1, a)
    love.graphics.print(def.label or "", x + 7, y + (h - fh) / 2)

    -- Warning badge: small "!" circle in top-right of pill
    if warn then
        local bx = x + w - 7
        local by = y + 5
        love.graphics.setColor(0.95, 0.62, 0.12, a)
        love.graphics.circle("fill", bx, by, 6)
        love.graphics.setColor(0.10, 0.08, 0.02, a)
        love.graphics.printf("!", bx - 6, by - fh / 2, 12, "center")
    end
end

-- ── Component factories ───────────────────────────────────────────────────────

local CARD_PAD  = 8
local HDR_H     = 32
local ADDBTN_H  = 22

local function makeRuleCardComp(rule_i, rule, panel_w, is_palette_open)
    local pad   = 6
    local avail = panel_w - pad * 2

    local _, pre_h = layoutBlocks(rule.blocks, pad, 0, avail)
    local blocks_h = (#rule.blocks > 0) and (pre_h + RULE_PAD_V * 2) or (BLOCK_H + RULE_PAD_V * 2)
    local comp_h   = CARD_PAD + HDR_H + blocks_h + ADDBTN_H + CARD_PAD

    return {
        type = "custom",
        h    = comp_h,

        draw_fn = function(px, y, pw, h, game)
            -- Store card geometry for drag-drop detection (content-space y)
            state.rule_card_tops[rule_i] = y
            state.rule_card_bots[rule_i] = y + h

            local drag = state.drag
            local is_dragged = drag and drag.active and drag.type == "rule" and drag.rule_i == rule_i

            local font  = game.fonts.ui_small
            local fh    = font:getHeight()
            local inner = pw - pad * 2

            -- Drop indicator: draw a line where a dragged rule would land
            if drag and drag.active and drag.type == "rule" and not is_dragged then
                local panel = game.ui_manager.panel
                local cy = panel:toContentY(drag.cy)
                -- Draw insert-before line above this card
                if cy >= y - 12 and cy < y + h / 2 then
                    love.graphics.setColor(0.4, 0.6, 1.0, 0.9)
                    love.graphics.setLineWidth(2)
                    love.graphics.line(px + pad, y, px + pw - pad, y)
                    love.graphics.setLineWidth(1)
                elseif rule_i == (#game.state.dispatch_rules) and cy >= y + h / 2 then
                    -- after last card
                    love.graphics.setColor(0.4, 0.6, 1.0, 0.9)
                    love.graphics.setLineWidth(2)
                    love.graphics.line(px + pad, y + h, px + pw - pad, y + h)
                    love.graphics.setLineWidth(1)
                end
            end

            -- Dim the card being dragged
            local card_alpha = is_dragged and 0.35 or 1.0

            love.graphics.setColor(0.13, 0.13, 0.19, card_alpha)
            love.graphics.rectangle("fill", px + pad, y, inner, h, 5, 5)
            love.graphics.setColor(0.26, 0.26, 0.40, card_alpha)
            love.graphics.rectangle("line", px + pad, y, inner, h, 5, 5)

            local sc = rule.enabled and { 0.35, 0.55, 1.00 } or { 0.30, 0.30, 0.40 }
            love.graphics.setColor(sc[1], sc[2], sc[3], card_alpha)
            love.graphics.rectangle("fill", px + pad, y, 4, h, 3, 3)

            love.graphics.setFont(font)
            local hdr_y = y + CARD_PAD + (HDR_H - fh) / 2

            local mark = rule.enabled and "● " or "○ "
            love.graphics.setColor(rule.enabled and 1 or 0.5, rule.enabled and 1 or 0.5,
                                   rule.enabled and 1 or 0.5, card_alpha)
            love.graphics.print(string.format("%sRule %d", mark, rule_i), px + pad + 10, hdr_y)

            -- Drag handle indicator (subtle grip dots, left side of header)
            love.graphics.setColor(0.4, 0.4, 0.55, card_alpha * 0.5)
            for gi = 0, 1 do
                for gj = 0, 2 do
                    local gdx = px + pad + 18 + gi * 6
                    local gdy = y + CARD_PAD + 8 + gj * 7
                    love.graphics.circle("fill", gdx, gdy, 1.5)
                end
            end

            local del_label = "del"
            local del_w = font:getWidth(del_label) + 12
            local del_x = px + pw - pad - del_w - 4
            love.graphics.setColor(0.50, 0.20, 0.20, card_alpha)
            love.graphics.rectangle("fill", del_x, y + CARD_PAD + 4, del_w, HDR_H - 8, 3, 3)
            love.graphics.setColor(0.85, 0.42, 0.42, card_alpha)
            love.graphics.rectangle("line", del_x, y + CARD_PAD + 4, del_w, HDR_H - 8, 3, 3)
            love.graphics.setColor(0.95, 0.65, 0.65, card_alpha)
            love.graphics.printf(del_label, del_x, y + CARD_PAD + 4 + (HDR_H - 8 - fh) / 2, del_w, "center")

            love.graphics.setColor(0.22, 0.22, 0.34, card_alpha)
            love.graphics.line(px + pad + 4, y + CARD_PAD + HDR_H,
                               px + pw - pad - 4, y + CARD_PAD + HDR_H)

            local by    = y + CARD_PAD + HDR_H
            local rects, _ = layoutBlocks(
                rule.blocks, px + pad + 8, by + RULE_PAD_V, inner - 16, font)

            -- Detect block drop indicator
            local block_drop_i = nil
            if drag and drag.active and drag.type == "block" and drag.rule_i == rule_i then
                local panel = game.ui_manager.panel
                block_drop_i = DispatchTab.getBlockDropIndex(rule_i, drag.cx,
                    panel:toContentY(drag.cy), rects)
            end

            for _, r in ipairs(rects) do
                for _, sd in ipairs(r.def.slots or {}) do
                    local val = tostring(r.inst.slots[sd.key] or sd.default or "?")
                    r.slot_pill_x = r.x + r.w - (font:getWidth(val) + 14) - 4
                end
            end
            state.block_rects[rule_i] = rects

            -- Semantic warnings on existing blocks (e.g. vehicle/scope mismatch)
            local block_warnings = Validator.getBlockWarnings(rule.blocks, game)

            if #rule.blocks == 0 then
                love.graphics.setColor(0.38, 0.38, 0.48, card_alpha)
                love.graphics.print("(empty — add blocks below)", px + pad + 12, by + RULE_PAD_V + 4)
            else
                for bi, r in ipairs(rects) do
                    -- Dim the block being dragged
                    local is_dragged_block = drag and drag.active and drag.type == "block"
                        and drag.rule_i == rule_i and drag.block_i == bi
                    local ba   = is_dragged_block and 0.3 or card_alpha
                    local warn = block_warnings[bi] ~= nil
                    drawBlockPill(r.def, r.inst.slots, r.x, r.y, r.w, r.h, game, ba, warn)

                    -- Drop indicator line before this block
                    if block_drop_i == bi then
                        love.graphics.setColor(0.4, 0.6, 1.0, 0.9)
                        love.graphics.setLineWidth(2)
                        love.graphics.line(r.x - 3, r.y - 2, r.x - 3, r.y + r.h + 2)
                        love.graphics.setLineWidth(1)
                    end
                end
                -- Drop indicator at end of block row
                if block_drop_i == #rects + 1 and #rects > 0 then
                    local lr = rects[#rects]
                    love.graphics.setColor(0.4, 0.6, 1.0, 0.9)
                    love.graphics.setLineWidth(2)
                    love.graphics.line(lr.x + lr.w + 2, lr.y - 2, lr.x + lr.w + 2, lr.y + lr.h + 2)
                    love.graphics.setLineWidth(1)
                end
            end

            local ab_y = y + h - CARD_PAD - ADDBTN_H
            love.graphics.setColor(0.18, 0.18, 0.28, card_alpha)
            love.graphics.rectangle("fill", px + pad + 4, ab_y, inner - 8, ADDBTN_H, 3, 3)
            love.graphics.setColor(
                is_palette_open and 0.5 or 0.32,
                is_palette_open and 0.5 or 0.32,
                is_palette_open and 0.8 or 0.50,
                card_alpha)
            love.graphics.rectangle("line", px + pad + 4, ab_y, inner - 8, ADDBTN_H, 3, 3)
            love.graphics.setColor(
                is_palette_open and 0.8 or 0.55,
                is_palette_open and 0.8 or 0.55,
                is_palette_open and 1.0 or 0.75,
                card_alpha)
            local ab_label = is_palette_open and "▲ Hide Palette" or "▼ Add Block"
            love.graphics.printf(ab_label, px + pad + 4, ab_y + (ADDBTN_H - fh) / 2, inner - 8, "center")

            love.graphics.setColor(1, 1, 1)
        end,

        hit_fn = function(px, cy_start, pw, h, mx, my)
            -- Header row
            if my < cy_start + CARD_PAD + HDR_H then
                local font_w = love.graphics.getFont():getWidth("del") + 12
                local del_x  = px + pw - pad - font_w - 4
                if mx >= del_x then
                    return { id = "dispatch_delete_rule", data = { rule_i = rule_i } }
                end
                -- Initiate a drag/click on the rule header
                return { id = "dispatch_rule_header_press", data = { rule_i = rule_i } }
            end

            -- "Add block" strip at bottom
            local ab_y = cy_start + h - CARD_PAD - ADDBTN_H
            if my >= ab_y then
                return { id = "dispatch_toggle_palette", data = { rule_i = rule_i } }
            end

            -- Block pills
            local rects = state.block_rects[rule_i] or {}
            for bi, r in ipairs(rects) do
                if mx >= r.x and mx < r.x + r.w and my >= r.y and my < r.y + r.h then
                    if r.slot_pill_x and mx >= r.slot_pill_x then
                        for _, sd in ipairs(r.def.slots or {}) do
                            return { id = "dispatch_cycle_slot",
                                     data = { rule_i = rule_i, block_i = bi, slot_key = sd.key } }
                        end
                    end
                    -- Initiate a drag/click on a block pill
                    return { id = "dispatch_block_press",
                             data = { rule_i = rule_i, block_i = bi } }
                end
            end
            return nil
        end,
    }
end

local function makePaletteComp(rule_i, panel_w)
    local pad   = 10
    local avail = panel_w - pad * 2

    local _, pal_h = layoutPalette(0, 0, avail)
    local comp_h   = pal_h + PAL_MARGIN * 2

    return {
        type = "custom",
        h    = comp_h,

        draw_fn = function(px, y, pw, h, game)
            love.graphics.setColor(0.11, 0.11, 0.16)
            love.graphics.rectangle("fill", px, y, pw, h)
            love.graphics.setColor(0.28, 0.28, 0.42)
            love.graphics.rectangle("line", px, y, pw, h)

            local font     = game.fonts.ui_small
            local rects, _ = layoutPalette(px + pad, y + PAL_MARGIN, pw - pad * 2, font)
            state.palette_rects = rects

            -- Compute which blocks are valid to add next; cache for hit_fn
            local cur_rule = (game.state.dispatch_rules or {})[rule_i]
            local validity = cur_rule and Validator.getPaletteValidity(cur_rule.blocks, game) or {}
            state.palette_validity = validity

            local all_defs = RE.getAllDefs()
            local last_cat = nil
            for _, def in ipairs(all_defs) do
                if def.category ~= last_cat then
                    last_cat = def.category
                    local r  = rects[def.id]
                    if r then
                        love.graphics.setFont(font)
                        love.graphics.setColor(0.55, 0.55, 0.70)
                        love.graphics.print(def.category:upper(), px + pad, r.y - CAT_HDR_H + 2)
                    end
                end
            end

            for _, def in ipairs(all_defs) do
                local r = rects[def.id]
                if r then
                    local v  = validity[def.id]
                    local ok = not v or v.valid
                    drawBlockPill(def, nil, r.x, r.y, r.w, r.h, game, ok and 1.0 or 0.20)
                end
            end
            love.graphics.setColor(1, 1, 1)
        end,

        hit_fn = function(px, cy_start, pw, h, mx, my)
            for def_id, r in pairs(state.palette_rects) do
                if mx >= r.x and mx < r.x + r.w and my >= r.y and my < r.y + r.h then
                    local v = state.palette_validity[def_id]
                    if not v or v.valid then
                        return { id = "dispatch_add_block",
                                 data = { rule_i = rule_i, def_id = def_id } }
                    end
                    return { id = "_noop", data = {} }
                end
            end
            return nil
        end,
    }
end

-- ── Build ─────────────────────────────────────────────────────────────────────

function DispatchTab.build(game, ui_manager)
    local comps = {}
    local rules = game.state.dispatch_rules or {}
    local pw    = (ui_manager and ui_manager.panel and ui_manager.panel.w) or 300

    -- Clear stale card geometry when rebuilding
    state.rule_card_tops = {}
    state.rule_card_bots = {}

    table.insert(comps, { type = "label", style = "heading", h = 26, text = "Dispatch Rules" })
    table.insert(comps, {
        type = "button", id = "dispatch_add_rule", data = {},
        lines = {{ text = "+ New Rule", style = "body" }},
    })

    table.insert(comps, { type = "label", style = "muted", h = 16,
        text = "Click a block to remove it. Click a slot to cycle." })

    for rule_i, rule in ipairs(rules) do
        table.insert(comps, { type = "spacer", h = 8 })
        local is_open = (state.palette_open and state.selected_rule == rule_i)
        table.insert(comps, makeRuleCardComp(rule_i, rule, pw, is_open))
        if is_open then
            table.insert(comps, makePaletteComp(rule_i, pw))
        end
    end

    return comps
end

-- ── Drag helpers (called by UIController) ────────────────────────────────────

-- Find which rule index to insert at, given a content-space Y position.
function DispatchTab.getRuleDropIndex(content_y, num_rules)
    for i = 1, num_rules do
        local top = state.rule_card_tops[i]
        local bot = state.rule_card_bots[i]
        if top and bot then
            local mid = (top + bot) / 2
            if content_y < mid then return i end
        end
    end
    return num_rules + 1
end

-- Find which block index to insert at, given content-space x and y.
function DispatchTab.getBlockDropIndex(rule_i, content_x, content_y, rects_override)
    local rects = rects_override or state.block_rects[rule_i] or {}
    local n = #rects
    if n == 0 then return 1 end

    -- Find the row closest by Y
    local best_row_y = rects[1].y
    local best_row_dist = math.abs(content_y - rects[1].y)
    for _, r in ipairs(rects) do
        local d = math.abs(content_y - r.y)
        if d < best_row_dist then
            best_row_dist = d
            best_row_y = r.y
        end
    end

    -- Within that row, find insert point by X
    local insert_i = n + 1
    for i, r in ipairs(rects) do
        if math.abs(r.y - best_row_y) < BLOCK_H then
            if content_x < r.x + r.w / 2 then
                insert_i = i
                break
            end
            insert_i = i + 1
        end
    end

    return math.max(1, math.min(n + 1, insert_i))
end

-- Draw the drag ghost overlay at current mouse screen position (call after panel:draw)
function DispatchTab.drawDragGhost(panel, game)
    local drag = state.drag
    if not drag or not drag.active then return end

    local mx, my = drag.cx, drag.cy
    local rules = game.state.dispatch_rules

    if drag.type == "rule" then
        local rule = rules[drag.rule_i]
        if not rule then return end
        local font = game.fonts.ui_small
        local fh   = font:getHeight()
        local gw   = math.min(panel.w - 20, 220)
        local gh   = HDR_H + CARD_PAD * 2
        local gx   = mx - gw / 2
        local gy   = my - gh / 2
        love.graphics.setColor(0.20, 0.30, 0.55, 0.85)
        love.graphics.rectangle("fill", gx, gy, gw, gh, 5, 5)
        love.graphics.setColor(0.40, 0.60, 1.00, 0.9)
        love.graphics.rectangle("line", gx, gy, gw, gh, 5, 5)
        love.graphics.setFont(font)
        love.graphics.setColor(1, 1, 1, 0.9)
        local mark = rule.enabled and "● " or "○ "
        love.graphics.printf(string.format("%sRule %d", mark, drag.rule_i),
            gx + 8, gy + (gh - fh) / 2, gw - 16, "left")

    elseif drag.type == "block" then
        local rule = rules[drag.rule_i]
        if not rule then return end
        local inst = rule.blocks[drag.block_i]
        if not inst then return end
        local def = RE.getDefById(inst.def_id)
        if not def then return end
        local font = game.fonts.ui_small
        local w = blockPillW(def, inst.slots, font)
        local gx = mx - w / 2
        local gy = my - BLOCK_H / 2
        -- shadow
        love.graphics.setColor(0, 0, 0, 0.4)
        love.graphics.rectangle("fill", gx + 3, gy + 3, w, BLOCK_H, 4, 4)
        drawBlockPill(def, inst.slots, gx, gy, w, BLOCK_H, game)
    end

    love.graphics.setColor(1, 1, 1)
end

-- ── Slot mutation (called by UIController) ────────────────────────────────────

function DispatchTab.cycleSlot(rule_i, block_i, slot_key, game)
    local rule = (game.state.dispatch_rules or {})[rule_i]
    if not rule then return end
    local inst = rule.blocks[block_i]
    if not inst then return end
    local def = RE.getDefById(inst.def_id)
    if not def then return end

    for _, sd in ipairs(def.slots or {}) do
        if sd.key == slot_key then
            if sd.type == "enum" then
                local opts = sd.options or {}
                local idx  = 1
                for i, v in ipairs(opts) do if v == inst.slots[slot_key] then idx = i; break end end
                inst.slots[slot_key] = opts[(idx % #opts) + 1]

            elseif sd.type == "vehicle_enum" then
                local types = {}
                for id in pairs(game.C.VEHICLES or {}) do types[#types + 1] = id:lower() end
                table.sort(types)
                local idx = 1
                for i, v in ipairs(types) do if v == inst.slots[slot_key] then idx = i; break end end
                inst.slots[slot_key] = types[(idx % #types) + 1]

            elseif sd.type == "number" then
                local step = sd.step or 100
                local mn   = sd.min  or 0
                local next_v = (inst.slots[slot_key] or sd.default or 0) + step
                inst.slots[slot_key] = next_v > 9999 and mn or next_v
            end
            break
        end
    end
end

return DispatchTab
