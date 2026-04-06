-- views/tabs/InfrastructureTab.lua
-- Infrastructure sidebar tab: highway building controls.

local InfrastructureTab = {}

function InfrastructureTab.build(game, ui_manager)
    local comps   = {}
    local e       = game.entities
    local in_mode = e.build_highway_mode or false
    local nodes   = e.highway_build_nodes or {}
    local cost_pp = (game.C.GAMEPLAY and game.C.GAMEPLAY.HIGHWAY_COST_PER_CELL) or 200

    -- Toggle / cancel button
    table.insert(comps, {
        type     = "button",
        id       = "toggle_build_highway_mode",
        data     = {},
        lines    = {{ text = in_mode and "Cancel Highway Build" or "Build Highway", style = "body" }},
    })

    if in_mode then
        if #nodes == 0 then
            table.insert(comps, {
                type = "label", style = "muted", h = 20,
                text = "Click an existing highway to start",
            })
        else
            -- Estimate cost
            local IS = require("services.InfrastructureService")
            local _, est_cost = IS.computeSegment(nodes, game)
            table.insert(comps, {
                type = "label", style = "body", h = 20,
                text = string.format("Nodes placed: %d", #nodes),
            })
            table.insert(comps, {
                type = "label", style = "muted", h = 20,
                text = string.format("Est. cost: $%d", est_cost),
            })
            table.insert(comps, {
                type = "label", style = "muted", h = 20,
                text = "Click a highway tile to finish",
            })
            table.insert(comps, {
                type = "label", style = "muted", h = 20,
                text = "Click elsewhere to add waypoint",
            })
        end
    else
        table.insert(comps, {
            type = "label", style = "muted", h = 20,
            text = string.format("Base: $%d/cell (terrain scales cost)", cost_pp),
        })
        table.insert(comps, {
            type = "label", style = "muted", h = 20,
            text = "River: 5x  |  Swamp: 3.5x  |  Forest: ~2x",
        })
        table.insert(comps, {
            type = "label", style = "muted", h = 20,
            text = "Start and end on existing highways",
        })
    end

    return comps
end

return InfrastructureTab
