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

-- ── Yen's K-shortest loopless paths ──────────────────────────────────────────
-- Returns a list of up to `k` results, sorted by cost ascending:
--   { {path={...}, cost=num}, {path={...}, cost=num}, ... }
--
-- Classic Yen's algorithm: find the shortest path A1 via Dijkstra, then for
-- each subsequent Ai, iterate the "spur nodes" of Ai-1, temporarily banning
-- the edges of previously-found paths that share the same root, and take the
-- cheapest spur-path found.
--
-- Edge banning is implemented by wrapping `get_edges` in a filter closure.

local function _filtered_edges(get_edges, banned_edges, banned_nodes)
    return function(id)
        if banned_nodes[id] then return {} end
        local src = get_edges(id)
        if not src then return {} end
        local out = {}
        local bset = banned_edges[id]
        for _, e in ipairs(src) do
            if not (bset and bset[e.to]) then
                out[#out + 1] = e
            end
        end
        return out
    end
end

-- Sum edge costs along a path using the unfiltered edge accessor.
local function _path_cost(get_edges, path)
    local cost = 0
    for i = 1, #path - 1 do
        local a, b = path[i], path[i + 1]
        for _, e in ipairs(get_edges(a) or {}) do
            if e.to == b then cost = cost + e.cost; break end
        end
    end
    return cost
end

function Graph.k_shortest(get_edges, start_id, end_id, k)
    k = k or 3
    local first = Graph.dijkstra(get_edges, start_id, end_id)
    if not first then return {} end

    local results    = {first}
    local candidates = {}  -- {path, cost}

    for ki = 2, k do
        local prev_path = results[ki - 1].path
        for i = 1, #prev_path - 1 do
            local spur_node = prev_path[i]
            -- Root path: prev_path[1..i]
            local root_path = {}
            for j = 1, i do root_path[j] = prev_path[j] end

            -- Ban edges that, combined with this root, would reproduce an
            -- earlier result.
            local banned_edges = {}
            for _, r in ipairs(results) do
                local rp = r.path
                if #rp > i then
                    local matches = true
                    for j = 1, i do
                        if rp[j] ~= root_path[j] then matches = false; break end
                    end
                    if matches then
                        local a, b = rp[i], rp[i + 1]
                        if not banned_edges[a] then banned_edges[a] = {} end
                        banned_edges[a][b] = true
                    end
                end
            end
            -- Ban all root-path nodes except the spur node, to keep path loopless.
            local banned_nodes = {}
            for j = 1, i - 1 do banned_nodes[root_path[j]] = true end

            local filtered = _filtered_edges(get_edges, banned_edges, banned_nodes)
            local spur = Graph.dijkstra(filtered, spur_node, end_id)
            if spur then
                -- Total path = root_path[1..i-1] + spur.path
                local total = {}
                for j = 1, i - 1 do total[#total + 1] = root_path[j] end
                for _, n in ipairs(spur.path) do total[#total + 1] = n end
                -- Cost using unfiltered edges (root cost + spur cost).
                local root_cost = _path_cost(get_edges, root_path)
                -- Subtract the last edge of root_path because spur starts at spur_node,
                -- which is root_path[i] — so root_cost already covers up to spur_node.
                -- (Dijkstra on root_path[1..i] would return exactly this.)
                local total_cost = root_cost + spur.cost

                -- Dedup: don't add if this exact path is already a candidate or result.
                local duplicate = false
                for _, r in ipairs(results) do
                    if #r.path == #total then
                        local same = true
                        for j = 1, #total do
                            if r.path[j] ~= total[j] then same = false; break end
                        end
                        if same then duplicate = true; break end
                    end
                end
                if not duplicate then
                    for _, c in ipairs(candidates) do
                        if #c.path == #total then
                            local same = true
                            for j = 1, #total do
                                if c.path[j] ~= total[j] then same = false; break end
                            end
                            if same then duplicate = true; break end
                        end
                    end
                end
                if not duplicate then
                    candidates[#candidates + 1] = {path = total, cost = total_cost}
                end
            end
        end

        if #candidates == 0 then break end

        -- Pick cheapest candidate
        local best_i, best_c = 1, candidates[1].cost
        for ci = 2, #candidates do
            if candidates[ci].cost < best_c then
                best_i, best_c = ci, candidates[ci].cost
            end
        end
        results[#results + 1] = candidates[best_i]
        table.remove(candidates, best_i)
    end

    return results
end

return Graph
