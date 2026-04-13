-- services/RoutePlannerService.lua
-- Multi-modal route planning over the entrance graph.
--
-- findRoute produces a single best route as a RoutePlan using a virtual
-- source/sink attached to the endpoint-mode entrances of the start and
-- end cities. The optional `allowed_modes` set restricts which interior
-- edges may be walked, so vehicle pathfinding can constrain to its own
-- mode while the trip preview can roam across all modes.
--
-- materializeRoute(plan, game, vehicle_provider) walks a RoutePlan's
-- segments and attaches a sub-cell point sequence to each:
--   local              — vehicle-aware bounded A* via
--                        PathfindingService.findLocalSegment.
--   trunk / intra_city — cached trunk path or lazy compute via _trunkPath
--                        with a mode-specific highway-first cost function.
--   transfer           — real in-city road A* between the two entrances.
--                        Placed-building endpoints (e.g. docks) are snapped
--                        to their land-side plot so the road vehicle can
--                        actually reach them.

local graph             = require("lib.graph")
local EntranceService   = require("services.EntranceService")
local RoutePlan         = require("models.RoutePlan")
local PathCacheService  = require("services.PathCacheService")
local EConfig           = require("data.entrance_config")
local WGC               = require("data.WorldGenConfig")

local IMPASSABLE = WGC.IMPASSABLE_COST

local _SRC = "__route_src__"
local _SNK = "__route_snk__"

local RoutePlannerService = {}

-- ── City lookup ───────────────────────────────────────────────────────────────

local function _cityOf(ux, uy, game)
    local umap = game.maps.unified
    if not umap or not umap.world_w then return nil end
    local wx = math.ceil(ux / 3)
    local wy = math.ceil(uy / 3)
    local ci = (wy - 1) * umap.world_w + wx
    return game.hw_all_claimed and game.hw_all_claimed[ci] or nil
end

-- ── Cost helpers ──────────────────────────────────────────────────────────────

-- Estimated travel time between a sub-cell position and an entrance,
-- penalized by LOCAL_COST_FACTOR because local driving uses city streets
-- which are much slower than the highway-grade travel assumed by trunk
-- edges.
local function _localCost(p, e, mode)
    local dx = math.abs(p.x - e.ux)
    local dy = math.abs(p.y - e.uy)
    local speed = EConfig.MODE_SPEEDS[mode] or EConfig.MODE_SPEEDS.road or 60
    return (EConfig.LOCAL_COST_FACTOR or 1) * (dx + dy) / speed
end

-- ── Edge accessor with virtual SRC/SNK ───────────────────────────────────────

-- Infer the endpoint mode (how the start and end positions are physically
-- reached) from allowed_modes. If exactly one mode is allowed, use it;
-- otherwise default to road because trip start/end positions are building
-- plots and only road vehicles can reach those. The endpoint mode restricts
-- which entrances SRC and SNK can attach to — without this, Dijkstra will
-- happily pick a water entrance for the final leg into the destination
-- plot, which is physically impossible (ships can't drive onto plots) and
-- produces broken materialization.
local function _inferEndpointMode(allowed_modes)
    if not allowed_modes then return "road" end
    local n, last = 0, nil
    for k in pairs(allowed_modes) do n = n + 1; last = k end
    if n == 1 then return last end
    return "road"
end

-- Build a get_edges closure over game.entrance_graph plus virtual SRC/SNK
-- nodes. SRC connects to entrances of start_city matching endpoint_mode;
-- every endpoint_mode entrance of end_city connects to SNK.
--
-- Terminal rule: once Dijkstra reaches an endpoint_mode entrance in
-- end_city, the only outgoing edge is SNK. No intra_city hop, no transfer,
-- no further trunk traversal. Without this rule Dijkstra can "hop" between
-- entrances in the destination city looking for one that's closer to
-- end_pos, producing visual detours that drive past the destination,
-- loop to another entrance, then come back.
local function _routedEdges(game, start_city, start_pos, end_city, end_pos, allowed_modes)
    local g = game.entrance_graph
    local endpoint_mode = _inferEndpointMode(allowed_modes)
    return function(id)
        if id == _SRC then
            local out = {}
            for _, e in ipairs(EntranceService.getForCity(start_city, game)) do
                if e.mode == endpoint_mode then
                    out[#out+1] = {to = e.id, cost = _localCost(start_pos, e, e.mode)}
                end
            end
            return out
        end
        if id == _SNK then return {} end

        -- Terminal node: first endpoint_mode entrance we hit in end_city.
        -- Bail out immediately to SNK so the rest of the route is the
        -- local A* from this entrance to end_pos — no graph detours.
        local ent = EntranceService.getById(id, game)
        if ent and ent.city_idx == end_city and ent.mode == endpoint_mode then
            return {{to = _SNK, cost = _localCost(end_pos, ent, ent.mode)}}
        end

        -- Start-city intra_city edges are blocked: Dijkstra should pick one
        -- start-city entrance directly from SRC and leave via trunk/transfer,
        -- not hop between entrances in the start city first. Transfers are
        -- still allowed so multi-modal outbound (road → water) works.
        local in_start = ent and ent.city_idx == start_city

        local ScopeService = require("services.ScopeService")
        local out = {}
        if g then
            for _, e in ipairs(g:getEdges(id)) do
                local ok = (e.kind == "trunk" or e.kind == "intra_city" or e.kind == "transfer")
                if ok and in_start and e.kind == "intra_city" then ok = false end
                if ok and allowed_modes then
                    if e.mode and not allowed_modes[e.mode] then ok = false end
                    if e.kind == "transfer" then
                        local dst = EntranceService.getById(e.to, game)
                        if dst and not allowed_modes[dst.mode] then ok = false end
                    end
                end
                -- Skip edges whose destination is in fog
                if ok then
                    local dst = EntranceService.getById(e.to, game)
                    if dst and not ScopeService.isRevealed(game, dst.ux, dst.uy) then ok = false end
                end
                if ok then out[#out+1] = e end
            end
        end
        return out
    end
end

-- ── Segment reconstruction ───────────────────────────────────────────────────

-- Walk a [_SRC, e1, ..., eN, _SNK] id sequence and produce RoutePlan segments.
-- For each consecutive entrance pair, look up the underlying graph edge to
-- discover whether it's a trunk, intra_city, or transfer hop.
local function _segmentsFromIds(ids, game, start_city, start_pos, end_city, end_pos)
    local mid = {}
    for _, id in ipairs(ids) do
        if id ~= _SRC and id ~= _SNK then mid[#mid+1] = id end
    end
    if #mid == 0 then return {} end

    local segs = {}

    -- Leading local: start_pos → first entrance.
    local first_e = EntranceService.getById(mid[1], game)
    if first_e then
        segs[#segs+1] = {
            kind = "local", mode = first_e.mode,
            from_pos = {x = start_pos.x, y = start_pos.y},
            to_e = first_e, city_idx = start_city,
        }
    end

    -- Walk consecutive entrances and resolve each pair to a graph edge.
    local g = game.entrance_graph
    for i = 1, #mid - 1 do
        local a = EntranceService.getById(mid[i], game)
        local b = EntranceService.getById(mid[i+1], game)
        if not (a and b and g) then break end
        local edge_kind, edge_mode
        for _, e in ipairs(g:getEdges(a.id)) do
            if e.to == b.id then
                edge_kind, edge_mode = e.kind, e.mode
                break
            end
        end
        segs[#segs+1] = {
            kind = edge_kind or "intra_city",
            mode = edge_mode,
            from_e = a, to_e = b,
            city_idx = (edge_kind == "intra_city" or edge_kind == "transfer") and a.city_idx or nil,
        }
    end

    -- Trailing local: last entrance → end_pos.
    local last_e = EntranceService.getById(mid[#mid], game)
    if last_e then
        segs[#segs+1] = {
            kind = "local", mode = last_e.mode,
            from_e = last_e,
            to_pos = {x = end_pos.x, y = end_pos.y},
            city_idx = end_city,
        }
    end

    return segs
end

-- ── Public: findRoute ────────────────────────────────────────────────────────

-- Plan a route from start_pos to end_pos through the entrance graph.
-- Returns a RoutePlan or nil. Same-city (or unknown city) calls produce a
-- single local segment with no entrance graph involvement.
function RoutePlannerService.findRoute(start_pos, end_pos, game, allowed_modes)
    local start_city = _cityOf(start_pos.x, start_pos.y, game)
    local end_city   = _cityOf(end_pos.x,   end_pos.y,   game)

    if start_city == nil or end_city == nil or start_city == end_city then
        return RoutePlan.new(0, {{
            kind = "local",
            mode = nil,
            from_pos = {x = start_pos.x, y = start_pos.y},
            to_pos   = {x = end_pos.x,   y = end_pos.y},
            city_idx = start_city or end_city,
        }})
    end

    if not game.entrance_graph then return nil end

    local get_edges = _routedEdges(game, start_city, start_pos, end_city, end_pos, allowed_modes)
    local result = graph.dijkstra(get_edges, _SRC, _SNK)
    if not result then return nil end

    local segs = _segmentsFromIds(result.path, game, start_city, start_pos, end_city, end_pos)
    if #segs == 0 then return nil end
    return RoutePlan.new(result.cost, segs)
end

-- ── Trunk / intra-city pixel paths ───────────────────────────────────────────

-- Vehicle-agnostic, mode-specific cost function for trunk/intra-city A*.
-- Highway-first for road; deeper-water-first for water. Used only on cache
-- miss; pre-computed paths from BuildingService stay in PathCacheService.
local function _trunkCostFor(mode, game)
    local umap = game.maps.unified
    local fgi  = umap and umap.ffi_grid
    local gw   = umap and umap._w or 0
    if not fgi then return nil end
    if mode == "road" then
        return function(x, y)
            local ti = fgi[(y-1)*gw + (x-1)].type
            if ti == 4 then return 1 end   -- highway
            if ti == 3 then return 5 end   -- arterial
            if ti == 1 or ti == 2 then return 10 end
            return IMPASSABLE
        end
    elseif mode == "water" then
        return function(x, y)
            local ti = fgi[(y-1)*gw + (x-1)].type
            if ti == 12 then return 1 end  -- open ocean
            if ti == 11 then return 2 end  -- deep water
            if ti == 10 then return 4 end  -- coastal water
            if ti == 5  then return 6 end  -- water (river/lake)
            return IMPASSABLE
        end
    end
    return nil
end

local function _trunkProxy(game)
    local umap = game.maps.unified
    return setmetatable({road_v_rxs = false}, {__index = umap})
end

-- Read a trunk/intra_city segment from the cache or compute it lazily with
-- a mode-specific cost function. Updates the cache on compute.
local function _trunkPath(seg, game)
    local a, b = seg.from_e, seg.to_e
    if not (a and b) then return nil end
    local cached = PathCacheService.get(seg.mode, a.ux, a.uy, b.ux, b.uy)
    if cached then return cached end

    local cost_fn = _trunkCostFor(seg.mode, game)
    if not cost_fn then return nil end
    local proxy = _trunkProxy(game)
    local turn_costs = (seg.mode ~= "road") and {turn_90 = 0, turn_180 = 0} or nil
    local p = game.pathfinder.findPath({},
        {x = a.ux, y = a.uy}, {x = b.ux, y = b.uy}, cost_fn, proxy, turn_costs)
    if p then PathCacheService.put(seg.mode, a.ux, a.uy, b.ux, b.uy, p) end
    return p
end

-- ── Public: makeMockVehicle ──────────────────────────────────────────────────

-- Construct a minimal mock vehicle from game.C.VEHICLES for a given mode.
-- Used by trip-preview pathfinding when no real vehicle is available.
-- Returns nil if no vehicle config matches the mode.
function RoutePlannerService.makeMockVehicle(mode, game)
    local vp
    for _, cfg in pairs(game.C.VEHICLES or {}) do
        if cfg.transport_mode == mode then vp = cfg; break end
    end
    if not vp then return nil end
    return {
        operational_map_key = "unified",
        pathfinding_bounds  = nil,
        type                = mode,
        id                  = 0,
        transport_mode      = mode,
        getMovementCostFor  = function(self, t) return vp.pathfinding_costs[t] or 9999 end,
        getSpeed            = function(self) return vp.base_speed or vp.speed or 60 end,
    }
end

-- ── Public: materializeRoute ─────────────────────────────────────────────────

-- Return the land-side plot position for a placed building's entrance
-- (docks, stations, airports — anything with a .building reference),
-- where a truck can actually drive to pick up or drop off cargo. The
-- entrance's own ux/uy typically sits on the traversable tile for its
-- own mode (water cell for docks, etc.) which is unreachable by road.
-- Auto-generated entrances without a building (highway attachments)
-- fall through to their own coords.
local function _buildingPlotOf(e)
    if e and e.building and e.building.x and e.building.y then
        return {x = e.building.x, y = e.building.y}
    end
    return e and {x = e.ux, y = e.uy} or nil
end

-- Walk a RoutePlan and attach a sub-cell point sequence to each segment.
-- `vehicle_provider` is either a vehicle table OR a function(mode) → vehicle.
-- Returns {segments = [{kind, mode, points}]}.
--
-- Segment handling:
--   trunk / intra_city — cached trunk path or lazy compute via _trunkPath.
--   local              — vehicle-aware bounded A* via findLocalSegment.
--   transfer           — a real in-city road path from one entrance to the
--                        other, representing the truck that physically moves
--                        the cargo between a dock and a road (or between any
--                        two entrances of different modes). Water-mode
--                        endpoints are snapped to their dock's land plot so
--                        road A* can actually reach them.
function RoutePlannerService.materializeRoute(plan, game, vehicle_provider)
    if not plan then return nil end
    local PathfindingService = require("services.PathfindingService")

    local provide
    if type(vehicle_provider) == "function" then
        provide = vehicle_provider
    else
        provide = function() return vehicle_provider end
    end

    local out = {segments = {}}

    for _, seg in ipairs(plan.segments) do
        local points
        if seg.kind == "trunk" or seg.kind == "intra_city" then
            points = _trunkPath(seg, game)
        elseif seg.kind == "local" then
            local v = provide(seg.mode or "road")
            if v then
                local from = seg.from_pos or (seg.from_e and {x = seg.from_e.ux, y = seg.from_e.uy})
                local to   = seg.to_pos   or (seg.to_e   and {x = seg.to_e.ux,   y = seg.to_e.uy})
                if from and to then
                    points = PathfindingService.findLocalSegment(v, from, to, seg.city_idx, game)
                end
            end
        elseif seg.kind == "transfer" then
            local from = _buildingPlotOf(seg.from_e)
            local to   = _buildingPlotOf(seg.to_e)
            if from and to then
                local v = provide("road")
                if v then
                    points = PathfindingService.findLocalSegment(v, from, to, seg.city_idx, game)
                end
            end
            -- Fallback to a straight line if A* can't find a path (e.g., the
            -- dock plot has no adjacent road — shouldn't happen in practice).
            if not points or #points == 0 then
                if seg.from_e and seg.to_e then
                    points = {
                        {x = seg.from_e.ux, y = seg.from_e.uy},
                        {x = seg.to_e.ux,   y = seg.to_e.uy},
                    }
                end
            end
        end
        out.segments[#out.segments+1] = {
            kind   = seg.kind,
            mode   = seg.mode,
            points = points or {},
        }
    end
    return out
end

return RoutePlannerService
