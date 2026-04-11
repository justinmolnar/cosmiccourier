-- services/EntranceGraphService.lua
-- Builds and maintains the mode-agnostic EntranceGraph in game.entrance_graph.
--
-- Edge taxonomy:
--   trunk        — inter-city, same mode. Represents a cached trunk path
--                  between two entrances of the same mode in different cities.
--                  The actual node sequence lives in PathCacheService keyed
--                  by (mode, from_ux, from_uy, to_ux, to_uy).
--   intra_city   — same-city, same mode. Represents "drive across city X
--                  from entrance A to entrance B" without leaving the network.
--                  No pre-cached path; pathfinder computes lazily.
--   transfer     — same-city, different mode. Represents cargo transfer from
--                  one mode's entrance to another's at loading/unloading cost.
--
-- The graph is incremental: register an entrance and this service adds the
-- relevant intra-city + transfer edges. Trunk edges are added by the caller
-- (GameBridgeService, BuildingService, InfrastructureService) at the points
-- where they have the trunk connectivity information.

local EntranceGraph = require("models.EntranceGraph")
local EntranceService = require("services.EntranceService")
local EConfig = require("data.entrance_config")

local EntranceGraphService = {}

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function _manhattan(a, b)
    return math.abs(a.ux - b.ux) + math.abs(a.uy - b.uy)
end

-- Travel-time cost for an intra-city edge of the given mode.
-- Distance is Manhattan sub-cell units; speed comes from entrance_config.
local function _intraCityCost(a, b, mode)
    local speed = EConfig.MODE_SPEEDS[mode] or 60
    return _manhattan(a, b) / speed
end

-- Transfer cost between two same-city entrances of different modes.
-- Road speed + the configured loading/unloading penalty.
local function _transferCost(a, b)
    local speed = EConfig.MODE_SPEEDS.road or 60
    return _manhattan(a, b) / speed + EConfig.TRANSFER_COST
end

-- Travel-time cost for an inter-city trunk edge. Caller supplies the true
-- path length when known (water trunks are pre-computed), otherwise we
-- estimate with Manhattan distance.
local function _trunkCost(a, b, mode, path_length)
    local speed = EConfig.MODE_SPEEDS[mode] or 60
    local len = path_length or _manhattan(a, b)
    return len / speed
end

-- Ensure game.entrance_graph exists and is an EntranceGraph instance.
local function _ensureGraph(game)
    if not game.entrance_graph then
        game.entrance_graph = EntranceGraph:new()
    end
    return game.entrance_graph
end

-- ── Public API ───────────────────────────────────────────────────────────────

-- Rebuild the entire graph from game.entrances. Adds all intra-city edges
-- (same-mode transit + cross-mode transfer). Inter-city trunk edges must
-- be added separately via addTrunkEdge — this function does not know about
-- trunk connectivity on its own.
function EntranceGraphService.rebuild(game)
    local g = _ensureGraph(game)
    g:clear()

    -- Add a node for every entrance.
    for _, e in ipairs(EntranceService.all(game)) do
        g:addNode(e.id)
    end

    -- Intra-city edges: walk each city's entrance list once and emit
    -- bidirectional edges between every pair.
    if not game.entrances_by_city then return end
    for _, list in pairs(game.entrances_by_city) do
        for i = 1, #list do
            for j = i + 1, #list do
                local a, b = list[i], list[j]
                if a.mode == b.mode then
                    local c = _intraCityCost(a, b, a.mode)
                    g:addEdge(a.id, b.id, "intra_city", a.mode, c)
                    g:addEdge(b.id, a.id, "intra_city", a.mode, c)
                else
                    local c = _transferCost(a, b)
                    g:addEdge(a.id, b.id, "transfer", nil, c)
                    g:addEdge(b.id, a.id, "transfer", nil, c)
                end
            end
        end
    end
end

-- Register a trunk edge between two entrances of the same mode in different
-- cities. `path_length` is optional — pass it when the actual trunk path
-- length is known (e.g. water trunks computed eagerly); otherwise Manhattan
-- distance is used as a rough cost estimate.
--
-- Adds edges in both directions.
function EntranceGraphService.addTrunkEdge(from_id, to_id, mode, game, path_length)
    local a = EntranceService.getById(from_id, game)
    local b = EntranceService.getById(to_id, game)
    if not a or not b then return end
    local g = _ensureGraph(game)
    local c = _trunkCost(a, b, mode, path_length)
    g:addEdge(from_id, to_id, "trunk", mode, c)
    g:addEdge(to_id, from_id, "trunk", mode, c)
end

-- Called after a single new entrance registers: add intra-city + transfer
-- edges between it and every other entrance already in its city.
-- Used by BuildingService.place so dock placement incrementally extends
-- the graph without a full rebuild.
function EntranceGraphService.addEdgesForEntrance(entrance_id, game)
    local new_e = EntranceService.getById(entrance_id, game)
    if not new_e then return end
    local g = _ensureGraph(game)
    g:addNode(new_e.id)

    local siblings = EntranceService.getForCity(new_e.city_idx, game)
    for _, other in ipairs(siblings) do
        if other.id ~= new_e.id then
            if other.mode == new_e.mode then
                local c = _intraCityCost(new_e, other, new_e.mode)
                g:addEdge(new_e.id, other.id, "intra_city", new_e.mode, c)
                g:addEdge(other.id, new_e.id, "intra_city", new_e.mode, c)
            else
                local c = _transferCost(new_e, other)
                g:addEdge(new_e.id, other.id, "transfer", nil, c)
                g:addEdge(other.id, new_e.id, "transfer", nil, c)
            end
        end
    end
end

-- Iterate every unique trunk edge in the graph (one direction per pair).
-- `fn(from_id, to_id, mode, cost)` is called once per undirected trunk.
-- Used by GameView to render pre-computed water trunks and by the debug
-- panel to count connectivity.
function EntranceGraphService.forEachTrunkEdge(game, fn)
    local g = game.entrance_graph
    if not g then return end
    local seen = {}
    for _, from_id in ipairs(g:getAllNodes()) do
        for _, edge in ipairs(g:getEdges(from_id)) do
            if edge.kind == "trunk" then
                local a, b = from_id, edge.to
                if a > b then a, b = b, a end
                local key = a .. "|" .. b
                if not seen[key] then
                    seen[key] = true
                    fn(from_id, edge.to, edge.mode, edge.cost)
                end
            end
        end
    end
end

return EntranceGraphService
