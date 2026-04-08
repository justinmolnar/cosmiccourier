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
}
