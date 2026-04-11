-- models/EntranceGraph.lua
-- Pure adjacency-list container for the mode-agnostic entrance graph.
-- Nodes are entrance IDs (strings). Edges are directed and weighted.
-- Each edge carries:
--   kind — "trunk" | "intra_city" | "transfer"
--   mode — transport mode the edge is used in ("road", "water", ...),
--          or nil for transfer edges (which span two different modes)
--   cost — numeric weight (estimated travel time in seconds)
--
-- The graph itself does not interpret kind or mode. Dijkstra lives in
-- lib/graph.lua; this file is pure data.

local EntranceGraph = {}
EntranceGraph.__index = EntranceGraph

function EntranceGraph:new()
    local instance = setmetatable({}, EntranceGraph)
    instance.adj = {}  -- adj[node_id] = { {to=id, kind=str, mode=str, cost=num}, ... }
    return instance
end

function EntranceGraph:addNode(id)
    if not self.adj[id] then
        self.adj[id] = {}
    end
end

-- Directed edge. Call twice (both directions) for bidirectional edges.
function EntranceGraph:addEdge(from_id, to_id, kind, mode, cost)
    self:addNode(from_id)
    self:addNode(to_id)
    table.insert(self.adj[from_id], {to = to_id, kind = kind, mode = mode, cost = cost})
end

-- Remove a node and all edges pointing to it.
function EntranceGraph:removeNode(id)
    self.adj[id] = nil
    for _, edges in pairs(self.adj) do
        for i = #edges, 1, -1 do
            if edges[i].to == id then
                table.remove(edges, i)
            end
        end
    end
end

function EntranceGraph:getEdges(id)
    return self.adj[id] or {}
end

function EntranceGraph:getAllNodes()
    local ids = {}
    for id in pairs(self.adj) do
        ids[#ids + 1] = id
    end
    return ids
end

function EntranceGraph:clear()
    self.adj = {}
end

return EntranceGraph
