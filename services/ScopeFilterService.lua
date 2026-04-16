-- services/ScopeFilterService.lua
-- Narrows a datagrid source's items to a selected scope entity.
--
-- Usage from a tab/host:
--   local wrapped = ScopeFilterService.wrap(source, "depot_in_city", "city", selected_city_map)
--   -- pass `wrapped` to the datagrid; it behaves like `source` but items_fn
--   -- only returns rows whose registered predicate says yes.
--
-- Agnostic: this service knows nothing about specific entity types. Every
-- filter is a string-id → function(item, game, scope_kind, selected) lookup
-- registered below at module load.

local ScopeFilterService = {}

local _filters = {}  -- [filter_id] = function(item, game, scope_kind, selected) -> bool

function ScopeFilterService.register(filter_id, fn)
    _filters[filter_id] = fn
end

function ScopeFilterService.get(filter_id)
    return _filters[filter_id]
end

-- Wrap a datagrid source so its `items_fn` returns only scope-matching rows.
-- Returns a thin proxy that falls through to the original source for all
-- other fields (columns, sort, id, etc.). If the filter is unknown or the
-- selected entity is nil, the wrap is a no-op pass-through.
function ScopeFilterService.wrap(source, filter_id, scope_kind, selected)
    if not source then return source end
    local pred = _filters[filter_id]
    if not pred or selected == nil then return source end

    local original_items_fn = source.items_fn
    local proxy = setmetatable({
        items_fn = function(game)
            local items = original_items_fn and original_items_fn(game) or {}
            local out = {}
            for _, item in ipairs(items) do
                if pred(item, game, scope_kind, selected) then
                    out[#out + 1] = item
                end
            end
            return out
        end,
    }, { __index = source })
    return proxy
end

-- ─── Built-in filter predicates ─────────────────────────────────────────────
-- Registered at module load. Data files reference these by string id.
-- Every predicate is: function(item, game, scope_kind, selected) -> bool
-- `selected` is a city_map (for scope_kind = "city").

local function _cityOfDepot(depot, game)
    return depot and depot.getCity and depot:getCity(game)
end

local function _cityOfClient(client, game)
    return client and client.getCity and client:getCity(game)
end

local function _cityOfVehicle(vehicle, game)
    local d = vehicle and vehicle.depot
    return d and d.getCity and d:getCity(game)
end

local function _cityOfTrip(trip, game)
    local sc = trip and trip.source_client
    return sc and sc.getCity and sc:getCity(game)
end

local function _cityOfBuilding(building, game)
    local all = game.maps and game.maps.all_cities
    return all and building and building.city and all[building.city]
end

ScopeFilterService.register("depot_in_city", function(item, game, _, selected_city)
    return _cityOfDepot(item, game) == selected_city
end)

ScopeFilterService.register("client_in_city", function(item, game, _, selected_city)
    return _cityOfClient(item, game) == selected_city
end)

ScopeFilterService.register("vehicle_in_city", function(item, game, _, selected_city)
    return _cityOfVehicle(item, game) == selected_city
end)

ScopeFilterService.register("trip_in_city", function(item, game, _, selected_city)
    return _cityOfTrip(item, game) == selected_city
end)

ScopeFilterService.register("building_in_city", function(item, game, _, selected_city)
    return _cityOfBuilding(item, game) == selected_city
end)

return ScopeFilterService
