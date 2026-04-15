-- services/WorldNamingService.lua
-- Orchestrates the worldgen-time naming pass in hierarchy order: continents
-- → regions → cities. Each pass can reference parent names because earlier
-- passes have already populated them.
--
-- Inputs (read from game, set by WorldSandboxController/GameBridgeService):
--   game.world_continents_list   — array of continents  (iterable)
--   game.world_continents_by_id  — { [id] = continent }  (lookup)
--   game.world_regions_list      — array of regions     (iterable)
--   game.world_regions_by_id     — { [id] = region }    (lookup)
--   game.maps.all_cities         — array of city maps
--
-- Outputs: sets `.name` on every continent, region, and city_map.

local WorldNamingService = {}

local NameService        = require("services.NameService")
local NameContextService = require("services.NameContextService")

local ContinentTemplates = require("data.names.templates.continent")
local RegionTemplates    = require("data.names.templates.region")
local CityTemplates      = require("data.names.templates.city")

local DepotTemplates = require("data.names.templates.depot")

function WorldNamingService.nameWorld(game, used_set)
    used_set = used_set or {}

    -- 1. Continents (no parents to reference).
    for _, c in ipairs(game.world_continents_list or {}) do
        local ctx = NameContextService.forContinent(c, game)
        c.name = NameService.generate(ContinentTemplates, ctx, used_set)
    end

    -- 2. Regions — attach parent continent name onto each region so the
    --    context builder can surface {continent_name}.
    local by_continent_id = game.world_continents_by_id or {}
    for _, r in ipairs(game.world_regions_list or {}) do
        local parent = by_continent_id[r.continent_id]
        if parent and parent.name then r.continent_name = parent.name end
        local ctx = NameContextService.forRegion(r, game)
        r.name = NameService.generate(RegionTemplates, ctx, used_set)
    end

    -- 3. Cities — context pulls parent region/continent names from the
    --    by_id lookups, which now have names set.
    for _, city in ipairs(game.maps.all_cities or {}) do
        local ctx = NameContextService.forCity(city, game)
        city.name = NameService.generate(CityTemplates, ctx, used_set)
    end

    -- 4. Starter depots & clients — re-name with city context now that
    --    cities have proper names. (Their constructors ran during wire,
    --    before cities were named.)
    WorldNamingService.renameStarterEntities(game, used_set)

    return used_set
end

-- Re-generate names for starter depots and clients using the now-named cities.
-- Safe to call multiple times; only runs on entities whose city context has
-- a resolved name.
function WorldNamingService.renameStarterEntities(game, used_set)
    used_set = used_set or {}
    for _, d in ipairs(game.entities and game.entities.depots or {}) do
        local cmap = d.getCity and d:getCity(game) or nil
        if cmap and cmap.name then
            local ctx = NameContextService.forBuilding(d.plot, cmap, game)
            local ok, name = pcall(NameService.generate, DepotTemplates, ctx, used_set)
            if ok then d.name = name end
        end
    end
    for _, cl in ipairs(game.entities and game.entities.clients or {}) do
        local cmap = cl.city_map
        local archetype = cl.archetype
        if cmap and cmap.name and archetype then
            local ok_mod, tmpl = pcall(require, "data.names.templates.client." .. archetype)
            if ok_mod and tmpl then
                local ctx = NameContextService.forBuilding(cl.plot, cmap, game)
                local ok, name = pcall(NameService.generate, tmpl, ctx, used_set)
                if ok then cl.name = name end
            end
        end
    end
end

-- Convenience: rebuild a used_set from already-named entities (for post-load
-- runtime naming to avoid colliding with worldgen names).
function WorldNamingService.collectUsed(game)
    local used = {}
    for _, c in ipairs(game.world_continents_list or {}) do
        if c.name then used[c.name] = true end
    end
    for _, r in ipairs(game.world_regions_list or {}) do
        if r.name then used[r.name] = true end
    end
    for _, city in ipairs(game.maps.all_cities or {}) do
        if city.name then used[city.name] = true end
    end
    for _, d in ipairs(game.entities and game.entities.depots  or {}) do
        if d.name then used[d.name] = true end
    end
    for _, cl in ipairs(game.entities and game.entities.clients or {}) do
        if cl.name then used[cl.name] = true end
    end
    return used
end

return WorldNamingService
