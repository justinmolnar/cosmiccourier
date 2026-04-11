-- services/RoutePlannerService.lua
-- Runs Dijkstra on game.entrance_graph to plan routes through entrances.
-- The graph encodes mode-agnostic connectivity; this service is where mode
-- filtering is applied via the closure passed to lib/graph.dijkstra.
--
-- Phase 3: only single-mode routing is exposed (findRouteForMode) — this is
-- what PathfindingService needs for vehicle movement. Phase 4 will add
-- multi-modal findRoute and materializeRoute for the trip preview.

local graph = require("lib.graph")
local EntranceService = require("services.EntranceService")

local RoutePlannerService = {}

-- Build a get_edges closure over game.entrance_graph that only returns
-- edges usable by a vehicle of the given transport mode. Transfer edges
-- are excluded (they represent a mode switch, impossible mid-vehicle).
local function _edgeFilterForMode(game, mode)
    local g = game.entrance_graph
    return function(node_id)
        local out = {}
        if not g then return out end
        for _, e in ipairs(g:getEdges(node_id)) do
            if (e.kind == "trunk" or e.kind == "intra_city") and e.mode == mode then
                out[#out + 1] = e
            end
        end
        return out
    end
end

-- Plan a mode-constrained route through the entrance graph.
-- Returns a sequence of entrance tables [E0, E1, ..., EN] or nil.
--   start_city_idx: numeric city index where the journey begins
--   start_pos: {x, y} sub-cell position within start_city_idx
--   end_city_idx: numeric city index where the journey ends
--   end_pos: {x, y} sub-cell position within end_city_idx
--   mode: transport mode ("road", "water", ...)
--
-- The returned sequence includes at minimum [nearest_start, nearest_end],
-- and may include intermediate entrances for multi-hop routes.
function RoutePlannerService.findRouteForMode(start_city_idx, start_pos,
                                               end_city_idx, end_pos, mode, game)
    if not game.entrance_graph then return nil end
    if start_city_idx == end_city_idx then return nil end  -- same-city: caller does direct A*

    local start_e = EntranceService.nearest(start_city_idx, start_pos.x, start_pos.y, mode, game)
    local end_e   = EntranceService.nearest(end_city_idx,   end_pos.x,   end_pos.y,   mode, game)
    if not start_e or not end_e then return nil end
    if start_e.id == end_e.id then return {start_e} end

    local get_edges = _edgeFilterForMode(game, mode)
    local result = graph.dijkstra(get_edges, start_e.id, end_e.id)
    if not result then return nil end

    -- Materialize the ID sequence into entrance tables.
    local seq = {}
    for _, id in ipairs(result.path) do
        local e = EntranceService.getById(id, game)
        if not e then return nil end
        seq[#seq + 1] = e
    end
    return seq
end

return RoutePlannerService
