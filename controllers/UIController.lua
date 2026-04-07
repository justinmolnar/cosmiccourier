-- controllers/UIController.lua
local CR = require("views.ComponentRenderer")

local UIController = {}
UIController.__index = UIController

function UIController:new(game_instance)
    local instance = setmetatable({}, UIController)
    instance.Game = game_instance
    return instance
end

function UIController:handleMouseDown(x, y, button)
    local Game       = self.Game
    local ui_manager = Game.ui_manager
    local panel      = ui_manager.panel

    -- 1. Context menu sits above everything else.
    if ui_manager.context_menu then
        return ui_manager:handleContextMenuMouseDown(x, y, button, Game)
    end

    -- 2. Modals are next.
    if ui_manager.modal_manager:handle_mouse_down(x, y, Game) then return true end

    -- 2. Panel tab bar and scrollbar.
    if panel:handleMouseDown(x, y, button) then return true end

    -- 3. Content clicks — only when mouse is in the content area.
    if not panel:isInContentArea(x, y) then return false end

    local comps = panel:getComponents()
    if not comps then return false end

    local cy  = panel:toContentY(y)
    local hit = CR.hitTest(comps, panel.x, panel.w, x, cy)
    if not hit or not hit.id then return false end

    local id   = hit.id
    local data = hit.data or {}

    if id == "assign_trip" then
        Game.EventBus:publish("ui_assign_trip_clicked", data.index)

    elseif id == "hire_vehicle" then
        Game.EventBus:publish("ui_buy_vehicle_clicked", data.vehicle_id)

    elseif id == "hire_vehicle_at_depot" then
        Game.EventBus:publish("ui_buy_vehicle_at_depot_clicked", { vehicle_id = data.vehicle_id, depot = data.depot })

    elseif id == "toggle_build_depot_mode" then
        Game.entities.build_depot_mode = not Game.entities.build_depot_mode

    elseif id == "toggle_build_highway_mode" then
        local e = Game.entities
        e.build_highway_mode = not (e.build_highway_mode or false)
        if not e.build_highway_mode then
            e.highway_build_nodes = {}
            Game._hw_ghost_cache = nil
        end

    elseif id == "market_for_clients" then
        Game.EventBus:publish("ui_market_for_clients_clicked", { depot = data.depot })

    elseif id == "buy_client" then
        Game.EventBus:publish("ui_buy_client_clicked")

    elseif id == "select_vehicle" then
        Game.entities.selected_vehicle = data.vehicle

    elseif id == "deselect_vehicle" then
        Game.entities.selected_vehicle = nil

    elseif id == "unassign_vehicle" then
        local v = data.vehicle
        if v then v:unassign(Game) end

    elseif id == "dispatch_add_rule" then
        local RE = require("services.DispatchRuleEngine")
        local rules = Game.state.dispatch_rules
        table.insert(rules, 1, RE.newRule())   -- index 1 = highest priority
        -- Auto-select the new rule and open its palette
        local DT = require("views.tabs.DispatchTab")
        local st = DT.getState()
        st.selected_rule = 1
        st.palette_open  = true

    elseif id == "dispatch_rule_header_press" then
        -- Start a drag candidate; toggle fires on mouse-up if no drag occurs
        local DT = require("views.tabs.DispatchTab")
        DT.getState().drag = {
            type = "rule", rule_i = data.rule_i,
            sx = x, sy = y, cx = x, cy = y, active = false,
        }

    elseif id == "dispatch_block_press" then
        -- Start a drag candidate; block remove fires on mouse-up if no drag occurs
        local DT = require("views.tabs.DispatchTab")
        DT.getState().drag = {
            type = "block", rule_i = data.rule_i, block_i = data.block_i,
            sx = x, sy = y, cx = x, cy = y, active = false,
        }

    elseif id == "dispatch_toggle_rule" then
        local rule = Game.state.dispatch_rules[data.rule_i]
        if rule then rule.enabled = not rule.enabled end

    elseif id == "dispatch_delete_rule" then
        local rules = Game.state.dispatch_rules
        if data.rule_i and rules[data.rule_i] then
            table.remove(rules, data.rule_i)
            local DT = require("views.tabs.DispatchTab")
            local st = DT.getState()
            st.palette_open  = false
            st.selected_rule = nil
        end

    elseif id == "dispatch_toggle_palette" then
        local DT = require("views.tabs.DispatchTab")
        local st = DT.getState()
        if st.selected_rule == data.rule_i and st.palette_open then
            st.palette_open = false
        else
            st.selected_rule = data.rule_i
            st.palette_open  = true
        end

    elseif id == "dispatch_add_block" then
        local rules = Game.state.dispatch_rules
        local rule  = rules[data.rule_i]
        if rule then
            local RE   = require("services.DispatchRuleEngine")
            local inst = RE.newBlockInst(data.def_id, Game)
            if inst then table.insert(rule.blocks, inst) end
        end

    elseif id == "dispatch_remove_block" then
        local rule = Game.state.dispatch_rules[data.rule_i]
        if rule and data.block_i then
            table.remove(rule.blocks, data.block_i)
        end

    elseif id == "dispatch_cycle_slot" then
        local DT = require("views.tabs.DispatchTab")
        DT.cycleSlot(data.rule_i, data.block_i, data.slot_key, Game)

    elseif id == "toggle_pause_trip_gen" then
        local e = Game.entities
        e.pause_trip_generation = not (e.pause_trip_generation or false)

    elseif id == "debug_spawn_trip" then
        local DebugTripFactory = require("services.DebugTripFactory")
        local depot = Game.entities.selected_depot
        if depot then
            local t = DebugTripFactory.create(data.scope, depot, Game)
            if t then
                table.insert(Game.entities.trips.pending, t)
                Game.EventBus:publish("trip_created")
            end
        end

    elseif id == "open_upgrade" then
        local Modal    = require("views.components.Modal")
        local on_close = function() ui_manager.modal_manager:hide() end
        local new_modal = Modal:new((data.name or "?") .. " Upgrades", 800, 600, on_close, data)
        ui_manager.modal_manager:show(new_modal)

    elseif id == "_noop" then
        -- swallowed click (e.g. invalid palette block) — do nothing

    end

    return true
end

-- ── Drag tracking ─────────────────────────────────────────────────────────────

local DRAG_THRESHOLD = 8

function UIController:handleMouseMoved(x, y)
    local DT   = require("views.tabs.DispatchTab")
    local drag = DT.getState().drag
    if not drag then return end
    drag.cx = x
    drag.cy = y
    if not drag.active then
        local dist = math.abs(x - drag.sx) + math.abs(y - drag.sy)
        if dist > DRAG_THRESHOLD then drag.active = true end
    end
end

function UIController:handleMouseUp(x, y, button, game)
    if button ~= 1 then return end
    local DT = require("views.tabs.DispatchTab")
    local st = DT.getState()
    local drag = st.drag
    if not drag then return end

    if not drag.active then
        -- Treat as a click
        if drag.type == "rule" then
            local rule = game.state.dispatch_rules[drag.rule_i]
            if rule then rule.enabled = not rule.enabled end
        elseif drag.type == "block" then
            local rule = game.state.dispatch_rules[drag.rule_i]
            if rule and drag.block_i then
                table.remove(rule.blocks, drag.block_i)
            end
        end
    else
        -- Commit drag reorder
        local rules = game.state.dispatch_rules
        local panel = game.ui_manager.panel

        if drag.type == "rule" then
            local content_y  = panel:toContentY(y)
            local num_rules  = #rules
            local target_i   = DT.getRuleDropIndex(content_y, num_rules)
            local from_i     = drag.rule_i

            -- Save the object whose selection we want to preserve
            local selected_obj = rules[st.selected_rule]

            if target_i ~= from_i and target_i ~= from_i + 1 then
                local rule = table.remove(rules, from_i)
                local insert_i = (target_i > from_i) and (target_i - 1) or target_i
                insert_i = math.max(1, math.min(#rules + 1, insert_i))
                table.insert(rules, insert_i, rule)

                -- Update selection to follow the moved or previously-selected rule
                if selected_obj then
                    for i, r in ipairs(rules) do
                        if r == selected_obj then st.selected_rule = i; break end
                    end
                end
            end

        elseif drag.type == "block" then
            local rule = rules[drag.rule_i]
            if rule then
                local content_y = panel:toContentY(y)
                local target_bi = DT.getBlockDropIndex(drag.rule_i, x, content_y)
                local from_bi   = drag.block_i
                if target_bi ~= from_bi and target_bi ~= from_bi + 1 then
                    local block = table.remove(rule.blocks, from_bi)
                    local insert_bi = (target_bi > from_bi) and (target_bi - 1) or target_bi
                    insert_bi = math.max(1, math.min(#rule.blocks + 1, insert_bi))
                    table.insert(rule.blocks, insert_bi, block)
                end
            end
        end
    end

    st.drag = nil
end

return UIController
