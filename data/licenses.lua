-- data/licenses.lua
-- Operating licenses. Each license is a pure scope gate: buying one raises
-- the player's scope tier and opens access to scope-gated purchases (vehicles,
-- packs, upgrades) — it does NOT bundle any content.
--
-- Fields:
--   id            — unique string
--   display_name  — shown in UI
--   description   — shown in the License modal
--   cost          — money cost; ignored when purchasable = false
--   scope_tier    — tier granted when this license is owned (integer 1-5)
--   purchasable   — false for starting license; true for all unlockable tiers
--
-- Sorted ascending by scope_tier.

return {
    {
        id           = "downtown_license",
        display_name = "Downtown License",
        description  = "Operate within the downtown district.",
        cost         = 0,
        scope_tier   = 1,
        purchasable  = false,
    },
    {
        id           = "city_license",
        display_name = "City License",
        description  = "Expand operations to the full metropolitan area.",
        cost         = 5000,
        scope_tier   = 2,
        purchasable  = true,
    },
    {
        id           = "region_license",
        display_name = "Region License",
        description  = "Serve neighboring cities and cross-region trips.",
        cost         = 25000,
        scope_tier   = 3,
        purchasable  = true,
    },
    {
        id           = "continent_license",
        display_name = "Continent License",
        description  = "Operate across the continent.",
        cost         = 100000,
        scope_tier   = 4,
        purchasable  = true,
    },
    {
        id           = "world_license",
        display_name = "World License",
        description  = "Unrestricted worldwide operations.",
        cost         = 400000,
        scope_tier   = 5,
        purchasable  = true,
    },
}
