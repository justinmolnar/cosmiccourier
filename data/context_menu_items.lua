-- data/context_menu_items.lua
-- Context menu item builders keyed by entity type.
-- Each function returns an array of menu items for that entity.
-- The controller hit-tests and delegates here; no entity logic in the controller.

local ContextMenuItems = {}

function ContextMenuItems.vehicle(vehicle, game)
    local items = {}
    local vcfg = game.C.VEHICLES[vehicle.type_upper]
    local name = (vcfg and vcfg.display_name or vehicle.type) .. " #" .. vehicle.id
    table.insert(items, { label = name, disabled = true })
    table.insert(items, { separator = true })
    table.insert(items, { icon = "🚗", label = "Select Vehicle",
        action = function(g)
            g.entities.selected_vehicle = vehicle
            g.entities.selected_depot   = nil
        end })
    table.insert(items, { icon = "🏠", label = "Recall to Depot",
        action = function(g)
            vehicle:unassign(g)
        end })
    return items
end

function ContextMenuItems.depot(depot, game)
    local items = {}
    table.insert(items, { label = depot.id or "Depot", disabled = true })
    table.insert(items, { separator = true })
    table.insert(items, { icon = "📊", label = "View Depot Info",
        action = function(g)
            g.ui_manager.panel.depot_view = depot
        end })
    -- Hire menu per vehicle type
    local sorted = {}
    for id, vcfg in pairs(game.C.VEHICLES) do
        sorted[#sorted + 1] = { id = id, vcfg = vcfg }
    end
    table.sort(sorted, function(a, b) return a.vcfg.base_cost < b.vcfg.base_cost end)
    for _, entry in ipairs(sorted) do
        local vid  = entry.id:lower()
        local vcfg = entry.vcfg
        local cost = game.state.costs[vid] or vcfg.base_cost
        local can_afford = game.state.money >= cost
        local district_ok = true
        local suffix = ""
        if vcfg.required_depot_district then
            district_ok = (depot:getDistrict(game) == vcfg.required_depot_district)
            if not district_ok then suffix = " [needs " .. vcfg.required_depot_district .. "]" end
        end
        if vcfg.transport_mode == "water" then
            local EntranceService = require("services.EntranceService")
            if not EntranceService.anyOfMode("water", game) then
                district_ok = false; suffix = " [place a dock first]"
            end
        end
        table.insert(items, {
            icon     = vcfg.icon,
            label    = string.format("Hire %s ($%d)%s", vcfg.display_name, cost, suffix),
            disabled = not can_afford or not district_ok,
            action   = function(g)
                g.EventBus:publish("ui_buy_vehicle_at_depot_clicked",
                    { vehicle_id = vid, depot = depot })
            end,
        })
    end
    table.insert(items, { separator = true })
    table.insert(items, { icon = "📢", label = "Market for Clients ($100)",
        disabled = true })  -- placeholder
    return items
end

function ContextMenuItems.highway(hw_wx, hw_wy, game)
    local items = {}
    table.insert(items, { label = "Highway", disabled = true })
    table.insert(items, { separator = true })
    table.insert(items, { icon = "🛣️", label = "Extend Highway from here",
        action = function(g)
            g.entities.build_highway_mode = true
            g.entities.highway_build_nodes = {{ wx = hw_wx, wy = hw_wy }}
        end })
    return items
end

function ContextMenuItems.empty(world_x, world_y, sx, sy, gx, gy, umap, game)
    local items = {}

    -- Depot placement
    local valid_site = gx and umap and ContextMenuItems._isValidDepotSite(gx, gy, umap)
    local depot_cost = 500
    local district_taken = false
    local depot_district_label = nil
    if valid_site then
        local Depot_cls = require("models.Depot")
        local cand = Depot_cls:new("_cand", {x = gx, y = gy}, game)
        local cand_district = cand:getDistrict(game)
        local cand_city     = cand:getCity(game)
        if cand_district then
            for _, existing in ipairs(game.entities.depots) do
                if existing:getCity(game) == cand_city and existing:getDistrict(game) == cand_district then
                    district_taken = true
                    depot_district_label = "District already has a depot"
                    break
                end
            end
        end
    end
    local depot_disabled = not valid_site or game.state.money < depot_cost or district_taken
    local depot_label = "Build Depot ($" .. depot_cost .. ")"
    if district_taken then depot_label = "Build Depot — " .. (depot_district_label or "unavailable") end
    table.insert(items, { icon = "🏢", label = depot_label,
        disabled = depot_disabled,
        action   = function(g)
            g.entities.build_depot_mode = true
            local ic = g.input_controller
            if ic then ic:_tryPlaceDepot(world_x, world_y, sx, sy) end
        end })

    -- Dock placement
    local dock_cfg  = game.C.BUILDINGS and game.C.BUILDINGS["dock"]
    local dock_city = gx and ContextMenuItems._cityIdxForSubcell(gx, gy, game)
    local BS        = dock_cfg and require("services.BuildingService")
    local dock_ok   = BS and gx and dock_city and BS.canPlace(dock_cfg, gx, gy, umap)
    local dock_cost = dock_cfg and dock_cfg.build_cost or 800
    local dock_disabled = not dock_ok or game.state.money < dock_cost
    if dock_cfg then
        table.insert(items, { icon = dock_cfg.icon or "⚓",
            label    = "Build Dock ($" .. dock_cost .. ")",
            disabled = dock_disabled,
            action   = function(g)
                if g.state.money < dock_cost then return end
                g.state.money = g.state.money - dock_cost
                BS.place(dock_cfg, gx, gy, dock_city, g)
                require("services.FloatingTextSystem").emit(
                    "Dock Built! -$" .. dock_cost, world_x, world_y, g.C)
            end })
    end

    table.insert(items, { separator = true })
    table.insert(items, { icon = "📍", label = "Set Camera Here",
        action = function(g)
            g.camera.x = world_x
            g.camera.y = world_y
        end })
    return items
end

-- ── Helpers (moved from InputController) ─────────────────────────────────────

function ContextMenuItems._isValidDepotSite(gx, gy, umap)
    if umap.ffi_grid then
        local ti = umap.ffi_grid[(gy - 1) * umap._w + (gx - 1)].type
        if ti == 8 or ti == 9 then return true end  -- plot / downtown_plot
    end
    local zsv, zsh = umap.zone_seg_v, umap.zone_seg_h
    if (zsv and zsv[gy] and (zsv[gy][gx] or zsv[gy][gx - 1]))
    or (zsh and zsh[gy]     and zsh[gy][gx])
    or (zsh and zsh[gy - 1] and zsh[gy - 1][gx]) then
        return true
    end
    return false
end

function ContextMenuItems._cityIdxForSubcell(gx, gy, game)
    for i, cmap in ipairs(game.maps and game.maps.all_cities or {}) do
        local ox = (cmap.world_mn_x - 1) * 3
        local oy = (cmap.world_mn_y - 1) * 3
        local lx = gx - ox
        local ly = gy - oy
        if lx >= 1 and ly >= 1
        and cmap.grid and lx <= #(cmap.grid[1] or {}) and ly <= #cmap.grid then
            return i
        end
    end
    return nil
end

return ContextMenuItems
