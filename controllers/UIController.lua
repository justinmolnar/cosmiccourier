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

    -- 0. Active dropdown check (highest priority overlay)
    local DT = require("views.tabs.DispatchTab")
    local st = DT.getState()
    if st.active_dropdown then
        local comps = panel:getComponents()
        if comps then
            -- The dropdown is always the last component in build()
            local drop_comp = comps[#comps]
            if drop_comp and drop_comp.hit_fn then
                -- Dropdown hit_fn is in content space, but handles internal screen space logic
                local cy  = panel:toContentY(y)
                local hit = drop_comp.hit_fn(panel.x, cy, panel.w, 0, x, cy)
                if hit then return true end
            end
        end
    end

    -- Commit any in-progress number slot text input on any click.
    local DT_early = require("views.tabs.DispatchTab")
    DT_early.commitFocus()
    DT_early.blurPaletteSearch()  -- defocus search field; re-focused below if click lands on it

    -- 1. Context menu sits above everything else.
    if ui_manager.context_menu then
        return ui_manager:handleContextMenuMouseDown(x, y, button, Game)
    end

    -- 2. Modals are next.
    if ui_manager.modal_manager:handle_mouse_down(x, y, Game) then return true end

    -- 3. Panel tab bar and scrollbar.
    if panel:handleMouseDown(x, y, button) then return true end

    -- 4. Content clicks — only when mouse is in the content area.
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
        local RTU   = require("services.RuleTreeUtils")
        local rules = Game.state.dispatch_rules
        table.insert(rules, 1, RTU.newRule())  -- index 1 = highest priority
        -- Auto-select the new rule and open its palette
        local DT = require("views.tabs.DispatchTab")
        local st = DT.getState()
        st.selected_rule = 1
        st.palette_open  = true

    elseif id == "dispatch_rule_header_press" then
        -- Start a drag candidate; toggle fires on mouse-up if no drag occurs
        local DT = require("views.tabs.DispatchTab")
        DT.getState().drag = {
            type   = "rule",
            rule_i = data.rule_i,
            sx = x, sy = y, cx = x, cy = y, active = false,
        }

    elseif id == "dispatch_node_press" then
        -- Start a drag candidate for a tree node
        local DT  = require("views.tabs.DispatchTab")
        local RTU = require("services.RuleTreeUtils")
        local node = data.node
        local slot_type = (node and node.kind == "bool") and "boolean" or "stack"
        DT.getState().drag = {
            type      = "node",
            rule_i    = data.rule_i,
            path      = data.path,
            node      = node and RTU.deepCopy(node) or nil,
            slot_type = slot_type,
            sx = x, sy = y, cx = x, cy = y, active = false,
        }

    elseif id == "dispatch_palette_press" then
        -- Start a drag candidate from the palette
        local DT  = require("views.tabs.DispatchTab")
        local RE  = require("services.DispatchRuleEngine")
        local def = RE.getDefById(data.def_id)
        local cat = def and def.category or "stack"
        local slot_type = (cat == "boolean") and "boolean"
                       or (cat == "reporter") and "reporter"
                       or "stack"
        DT.getState().drag = {
            type      = "palette",
            rule_i    = data.rule_i,
            def_id    = data.def_id,
            node      = RE.newBlockInst(data.def_id, Game),
            slot_type = slot_type,
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

    elseif id == "dispatch_toggle_collapse" then
        local DT   = require("views.tabs.DispatchTab")
        local rule = Game.state.dispatch_rules[data.rule_i]
        if rule then
            local st = DT.getState()
            st.collapsed_rules = st.collapsed_rules or {}
            local id = rule.id
            st.collapsed_rules[id] = not st.collapsed_rules[id]
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

    elseif id == "dispatch_focus_slot" then
        local DT  = require("views.tabs.DispatchTab")
        local RE  = require("services.DispatchRuleEngine")
        local TextInput = require("views.components.TextInput")
        local node = data.node  -- passed directly from hit_fn
        if node then
            local def = RE.getDefById(node.def_id)
            local sd  = nil
            for _, s in ipairs(def and def.slots or {}) do
                if s.key == data.slot_key then sd = s; break end
            end
            -- If slot holds a reporter node, click clears it back to the default value
            local current = node.slots[data.slot_key]
            if type(current) == "table" and current.kind == "reporter" then
                node.slots[data.slot_key] = sd and sd.default
                return true
            end
            local st = DT.getState()
            local mode = (sd and sd.type == "number") and "number" or "text"
            st.slot_input = {
                node     = node,
                slot_key = data.slot_key,
                input    = TextInput:new("", current, mode, function(val)
                    if sd and sd.type == "number" and sd.min then val = math.max(sd.min, val) end
                    node.slots[data.slot_key] = val
                end, Game)
            }
            st.slot_input.input:focus()
        end

    elseif id == "dispatch_cycle_slot" then
        local DT = require("views.tabs.DispatchTab")
        DT.cycleSlot(data.rule_i, data.path, data.slot_key, Game)

    elseif id == "dispatch_cycle_rep_inner_slot" then
        local DT = require("views.tabs.DispatchTab")
        DT.cycleRepInnerSlot(data.rep_node, data.rep_key, data.rep_sd, Game)

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

    elseif id == "dispatch_palette_filter_tag" then
        local DT = require("views.tabs.DispatchTab")
        DT.toggleFilterTag(data.tag)

    elseif id == "dispatch_palette_search_focus" then
        local DT = require("views.tabs.DispatchTab")
        DT.getState().palette_filter.search_focused = true

    elseif id == "dispatch_palette_clear_filters" then
        local DT = require("views.tabs.DispatchTab")
        local f = DT.getState().palette_filter
        f.active_tags    = {}
        f.search         = ""
        f.search_focused = false

    elseif id == "dispatch_palette_toggle_legacy" then
        local DT = require("views.tabs.DispatchTab")
        local f = DT.getState().palette_filter
        f.show_legacy = not (f.show_legacy or false)

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
    if drag.active then
        DT.updateDropTarget(drag, self.Game)
    end
end

function UIController:handleMouseUp(x, y, button, game)
    if button ~= 1 then return end
    local DT  = require("views.tabs.DispatchTab")
    local RTU = require("services.RuleTreeUtils")
    local RE  = require("services.DispatchRuleEngine")
    local st  = DT.getState()
    local drag = st.drag
    if not drag then return end

    if not drag.active then
        -- Click without drag
        if drag.type == "rule" then
            local rule = game.state.dispatch_rules[drag.rule_i]
            if rule then rule.enabled = not rule.enabled end

        elseif drag.type == "node" then
            -- Click on a node = remove it
            local rule = game.state.dispatch_rules[drag.rule_i]
            if rule then
                -- Smart pruning: if we remove a child of a binary operator (AND/OR), 
                -- replace the operator itself with the other child instead of leaving a hole.
                if #drag.path > 0 then
                    local parent_path = {}
                    for i=1, #drag.path-1 do parent_path[#parent_path+1] = drag.path[i] end
                    local parent = RTU.getNodeAtPath(rule.stack, parent_path)
                    local last_key = drag.path[#drag.path]

                    if parent and (parent.def_id == "bool_and" or parent.def_id == "bool_or") then
                        local other_key = (last_key == "left") and "right" or "left"
                        local remaining = parent[other_key]
                        -- Replace parent with remaining child
                        rule.stack = RTU.insertNodeAtPath(rule.stack, parent_path, "", remaining)
                        -- The insertNodeAtPath above using "" as slot is a hack to replace the node at parent_path.
                        -- Actually, resolveParent and direct set is cleaner if we have it.
                        -- Let's use a cleaner way:
                        local new_stack = RTU.deepCopy(rule.stack)
                        local gp, p_key = {}, nil
                        if #parent_path > 0 then
                            local gpath = {}
                            for i=1, #parent_path-1 do gpath[#gpath+1] = parent_path[i] end
                            local gnode = (#gpath == 0) and new_stack or RTU.getNodeAtPath(new_stack, gpath)
                            gnode[parent_path[#parent_path]] = RTU.deepCopy(remaining)
                        else
                            -- Parent was the root of the stack? (impossible for bool_and)
                        end
                        rule.stack = new_stack
                    else
                        local _, new_stack = RTU.removeNodeAtPath(rule.stack, drag.path)
                        rule.stack = new_stack
                    end
                else
                    local _, new_stack = RTU.removeNodeAtPath(rule.stack, drag.path)
                    rule.stack = new_stack
                end
            end

        elseif drag.type == "palette" then
            -- Palette click without drag = append to end of rule stack (stack/hat nodes only)
            local rule = game.state.dispatch_rules[drag.rule_i]
            if rule and drag.node and drag.slot_type == "stack" then
                table.insert(rule.stack, drag.node)
            end
        end

    else
        -- Active drag — commit to drop target
        local rules = game.state.dispatch_rules

        if drag.type == "rule" then
            local panel     = game.ui_manager.panel
            local content_y = panel:toContentY(y)
            local num_rules = #rules
            local target_i  = DT.getRuleDropIndex(content_y, num_rules)
            local from_i    = drag.rule_i
            local sel_obj   = rules[st.selected_rule]

            if target_i ~= from_i and target_i ~= from_i + 1 then
                local rule     = table.remove(rules, from_i)
                local insert_i = (target_i > from_i) and (target_i - 1) or target_i
                insert_i       = math.max(1, math.min(#rules + 1, insert_i))
                table.insert(rules, insert_i, rule)
                if sel_obj then
                    for i, r in ipairs(rules) do
                        if r == sel_obj then st.selected_rule = i; break end
                    end
                end
            end

        elseif drag.type == "palette" and drag.slot_type == "reporter" and drag.drop_valid then
            -- Reporter dropped into a number/string slot: assign directly to slot value
            local drop_rule = rules[drag.drop_rule_i]
            if drop_rule then
                local RTU2    = require("services.RuleTreeUtils")
                local target  = RTU2.getNodeAtPath(drop_rule.stack, drag.drop_parent_path)
                if target and drag.drop_slot then
                    target.slots[drag.drop_slot] = { kind = "reporter", node = drag.node }
                end
            end

        elseif (drag.type == "node" or drag.type == "palette") and drag.drop_valid then
            local drop_rule = rules[drag.drop_rule_i]
            if drop_rule then
                local node = drag.node  -- already a copy

                if drag.type == "node" then
                    -- Remove from source first
                    local source_rule = rules[drag.rule_i]
                    if source_rule then
                        local _, new_stack = RTU.removeNodeAtPath(source_rule.stack, drag.path)
                        source_rule.stack = new_stack
                        -- If same rule, sync the drop_rule reference too
                        if source_rule == drop_rule then
                            drop_rule.stack = new_stack
                        end
                    end
                end

                -- Smart condition wrapping: dropping onto an occupied condition slot.
                if type(drag.drop_slot) == "string" and drag.drop_slot == "condition" then
                    local parent = RTU.getNodeAtPath(drop_rule.stack, drag.drop_parent_path)
                    if parent and parent.condition then
                        local existing = RTU.deepCopy(parent.condition)
                        local id = node.def_id
                        if id == "bool_and" or id == "bool_or" then
                            -- Binary operator dropped: place existing as left child, right stays empty
                            node.left  = existing
                            node.right = nil
                        elseif id == "bool_not" then
                            -- NOT dropped: wrap existing as operand
                            node.operand = existing
                        else
                            -- Leaf condition dropped: replace existing (default behavior)
                            -- No change to 'node', it will overwrite 'existing' in insertNodeAtPath below.
                        end
                    end
                end

                drop_rule.stack = RTU.insertNodeAtPath(
                    drop_rule.stack, drag.drop_parent_path, drag.drop_slot, node)
            end
        end
    end

    st.drag = nil
    -- Clear number input focus after any drag completes
    DT.clearFocus()
end

return UIController
