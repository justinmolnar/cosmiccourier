-- lib/graph.lua
-- Generic weighted-graph algorithms. Zero game-domain knowledge.
--
-- The caller provides an edge accessor:
--   get_edges(node_id) -> { {to = id, cost = number}, ... }
--
-- Node IDs are any hashable value (this codebase uses strings).
-- Any graph shape works — the algorithms never touch game state.

local Graph = {}

-- ── Binary min-heap (priority queue) ─────────────────────────────────────────
-- Entries are {key, value}. Smaller key = higher priority.
-- Lazy deletion: when a stale entry pops, the caller checks its dist and skips.

local Heap = {}
Heap.__index = Heap

local function heap_new()
    return setmetatable({n = 0}, Heap)
end

function Heap:push(key, value)
    self.n = self.n + 1
    local i = self.n
    self[i] = {key, value}
    while i > 1 do
        local p = math.floor(i / 2)
        if self[p][1] > self[i][1] then
            self[p], self[i] = self[i], self[p]
            i = p
        else
            break
        end
    end
end

function Heap:pop()
    if self.n == 0 then return nil end
    local top = self[1]
    self[1] = self[self.n]
    self[self.n] = nil
    self.n = self.n - 1
    local i, n = 1, self.n
    while true do
        local l, r = i * 2, i * 2 + 1
        local s = i
        if l <= n and self[l][1] < self[s][1] then s = l end
        if r <= n and self[r][1] < self[s][1] then s = r end
        if s ~= i then
            self[s], self[i] = self[i], self[s]
            i = s
        else
            break
        end
    end
    return top[1], top[2]
end

function Heap:empty()
    return self.n == 0
end

-- ── Dijkstra ─────────────────────────────────────────────────────────────────
-- Returns {path = {start_id, ..., end_id}, cost = number} or nil.
--
-- `get_edges(id)` is called lazily per popped node, which is what lets Yen's
-- algorithm (below) swap in a filtered edge accessor to ban specific edges.

function Graph.dijkstra(get_edges, start_id, end_id)
    if start_id == end_id then
        return {path = {start_id}, cost = 0}
    end

    local dist = {[start_id] = 0}
    local prev = {}
    local settled = {}
    local pq = heap_new()
    pq:push(0, start_id)

    while not pq:empty() do
        local d, u = pq:pop()
        if not settled[u] then
            if u == end_id then break end
            settled[u] = true
            local edges = get_edges(u)
            if edges then
                for _, e in ipairs(edges) do
                    local v = e.to
                    if not settled[v] then
                        local nd = d + e.cost
                        local cur = dist[v]
                        if not cur or nd < cur then
                            dist[v] = nd
                            prev[v] = u
                            pq:push(nd, v)
                        end
                    end
                end
            end
        end
    end

    if not dist[end_id] then return nil end

    -- Reconstruct path
    local path = {}
    local cur = end_id
    while cur do
        path[#path + 1] = cur
        cur = prev[cur]
    end
    -- Reverse
    local n = #path
    for i = 1, math.floor(n / 2) do
        path[i], path[n - i + 1] = path[n - i + 1], path[i]
    end
    return {path = path, cost = dist[end_id]}
end

return Graph
