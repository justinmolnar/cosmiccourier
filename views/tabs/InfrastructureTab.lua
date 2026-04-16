-- views/tabs/InfrastructureTab.lua
-- Building tab (formerly "Roads"). Hosts player-directed infrastructure:
-- depot placement always, highway construction when that upgrade is bought,
-- dock placement when that upgrade is bought.
--
-- Tab itself is gated in UIManager by the same upgrade flags.

local InfrastructureTab = {}

local TAB_ID = "building"

local function buildDepotSection(game)
    local e = game.entities
    local in_mode = e.build_depot_mode or false
    return {
        type = "accordion_section",
        tab_id = TAB_ID, section_id = "depot_placement",
        header = "Depot Placement",
        children = {
            {
                type  = "button",
                id    = "toggle_build_depot_mode",
                lines = {{ text = in_mode and "Cancel Depot Placement" or "Place Depot", style = "body" }},
            },
            { type = "label", style = "muted", h = 20,
              text = "Click a downtown road tile to place a new depot." },
        },
    }
end

local function buildHighwaySection(game)
    local e       = game.entities
    local in_mode = e.build_highway_mode or false
    local nodes   = e.highway_build_nodes or {}
    local cost_pp = (game.C.GAMEPLAY and game.C.GAMEPLAY.HIGHWAY_COST_PER_CELL) or 200

    local children = {
        {
            type  = "button",
            id    = "toggle_build_highway_mode",
            lines = {{ text = in_mode and "Cancel Highway Build" or "Build Highway", style = "body" }},
        },
    }

    if in_mode then
        if #nodes == 0 then
            children[#children + 1] = { type = "label", style = "muted", h = 20,
                text = "Click an existing highway to start" }
        else
            local IS = require("services.InfrastructureService")
            local _, est_cost = IS.computeSegment(nodes, game)
            children[#children + 1] = { type = "label", style = "body", h = 20,
                text = string.format("Nodes placed: %d", #nodes) }
            children[#children + 1] = { type = "label", style = "muted", h = 20,
                text = string.format("Est. cost: $%d", est_cost) }
            children[#children + 1] = { type = "label", style = "muted", h = 20,
                text = "Click a highway tile to finish" }
            children[#children + 1] = { type = "label", style = "muted", h = 20,
                text = "Click elsewhere to add waypoint" }
        end
    else
        children[#children + 1] = { type = "label", style = "muted", h = 20,
            text = string.format("Base: $%d/cell (terrain scales cost)", cost_pp) }
        children[#children + 1] = { type = "label", style = "muted", h = 20,
            text = "River: 5x  |  Swamp: 3.5x  |  Forest: ~2x" }
    end

    return {
        type = "accordion_section",
        tab_id = TAB_ID, section_id = "highway_construction",
        header = "Highway Construction",
        children = children,
    }
end

local function buildDockSection(game)
    return {
        type = "accordion_section",
        tab_id = TAB_ID, section_id = "dock_placement",
        header = "Dock Placement",
        children = {
            { type = "label", style = "muted", h = 20,
              text = "Dock palette — click a coastal tile to place." },
            { type = "label", style = "muted", h = 20,
              text = "(Placement UI stub — extend per dock cfg.)" },
        },
    }
end

function InfrastructureTab.build(game, ui_manager)
    local comps = {}
    local upgrades = game.state and game.state.upgrades or {}

    -- Depot placement — shown whenever the tab is visible (a placeable
    -- infrastructure action that doesn't need its own unlock at this point).
    comps[#comps + 1] = buildDepotSection(game)

    if upgrades.building_highway_unlocked then
        comps[#comps + 1] = buildHighwaySection(game)
    end
    if upgrades.building_dock_unlocked then
        comps[#comps + 1] = buildDockSection(game)
    end

    return comps
end

return InfrastructureTab
