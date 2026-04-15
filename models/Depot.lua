local Depot = {}
Depot.__index = Depot

function Depot:new(id, plot, game)
    local instance = setmetatable({}, Depot)
    instance.id = id
    instance.plot = plot
    
    instance.name              = id or "Depot"
    instance.open              = true

    local bcfg = game.C.BUILDINGS and game.C.BUILDINGS["depot"]
    instance.capacity          = bcfg and bcfg.capacity or 10
    instance.cargo             = {}

    instance.assigned_vehicles = {}

    instance.analytics = {
        trips_completed = 0,
        income_generated = 0,
        volume_in = 0,
        volume_out = 0
    }
    
    return instance
end

function Depot:update(dt, game)
    -- Future: process per-depot analytics decay or similar over time
end

function Depot:getCity(game)
    -- Find the city map that contains this depot's unified sub-cell plot
    if not self.plot then return nil end
    local px, py = self.plot.x, self.plot.y
    for _, cmap in ipairs(game.maps.all_cities or {}) do
        local ox = (cmap.world_mn_x - 1) * 3
        local oy = (cmap.world_mn_y - 1) * 3
        local lx = px - ox
        local ly = py - oy
        if lx >= 1 and ly >= 1
        and cmap.grid and lx <= #(cmap.grid[1] or {}) and ly <= #cmap.grid then
            return cmap
        end
    end
    return nil
end

function Depot:getDistrict(game)
    local city_map = self:getCity(game)
    if not city_map or not city_map.district_map then return nil end
    -- district_map is keyed by global sci = (uy-1)*sub_w + ux
    -- where ux/uy are 1-based unified sub-cell coords and sub_w = world_w*3
    local sub_w = (game.world_w or 0) * 3
    if sub_w == 0 then return nil end
    local sci = (self.plot.y - 1) * sub_w + self.plot.x
    local poi_idx = city_map.district_map[sci]
    if poi_idx and city_map.district_types then
        return city_map.district_types[poi_idx]
    end
    return nil
end

-- ─── Serialization (data-driven) ─────────────────────────────────────────────
Depot.TRANSIENTS = {
    capacity = true,         -- regenerated from building config on :new
    assigned_vehicles = true, -- reattached by Vehicle restore
}
Depot.REFS = {
    cargo = { kind = "uid", list = true },
}

local AutoSerializer = require("services.AutoSerializer")

function Depot:serialize()
    return AutoSerializer.serialize(self, Depot.TRANSIENTS, Depot.REFS)
end

function Depot.fromSerialized(data, game, trips_by_uid)
    local instance = Depot:new(data.id, data.plot, game)
    local function resolver(kind, id)
        if kind == "uid" then return trips_by_uid[id] end
    end
    AutoSerializer.apply(instance, data, Depot.REFS, resolver)
    return instance
end

return Depot
