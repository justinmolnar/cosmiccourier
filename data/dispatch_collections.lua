-- data/dispatch_collections.lua
-- Registry of collections that the Find block can iterate.
-- Agnostic: The engine calls these functions to get a raw array of items.

return {
    { 
        id      = "vehicles",
        label   = "Vehicles",
        ctx_key = "vehicle", -- when filtering, current item is bound to this key
        read    = function(ctx, slots) 
            return ctx.game.entities.vehicles 
        end
    },
    {
        id      = "pending_trips",
        label   = "Pending Trips",
        ctx_key = "trip",
        read    = function(ctx, slots)
            return ctx.game.entities.trips.pending
        end
    },
    {
        id      = "building_cargo",
        label   = "Building Cargo",
        ctx_key = "trip",
        read    = function(ctx, slots)
            local BS  = require("services.BuildingService")
            local all = {}
            for _, b in ipairs(BS.allBuildings(ctx.game)) do
                for _, t in ipairs(b.cargo or {}) do all[#all+1] = t end
            end
            return all
        end
    },
}
