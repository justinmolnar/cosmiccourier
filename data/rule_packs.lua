-- data/rule_packs.lua
-- Pack definitions. Each pack is a query against rule_templates.lua.
-- PackService matches templates by tags + complexity range, then picks `count`.
--
-- Fields:
--   id             — unique string
--   name           — display name
--   scope_tier     — which scope tier unlocks this pack (1=district..5=world)
--   tags           — ALL listed tags must be present on a template to match (AND)
--   count          — how many templates to grant from the matched pool
--   min_complexity — (optional) minimum complexity to include (default 1)
--   max_complexity — (optional) maximum complexity to include (default 5)
--
-- Sorted by scope_tier (district → world), then by complexity within tier.

return {

    -- ── Tier 1: District (Downtown) ──────────────────────────────────────────

    {   id             = "starter_pack",
        name           = "Dispatch Basics",
        scope_tier     = 1,
        tags           = { "starter" },
        count          = 2,
        max_complexity = 1,
        guaranteed     = { "assign_any_vehicle" },
    },

    -- ── Tier 2: City ─────────────────────────────────────────────────────────

    {   id             = "assignment_pack",
        name           = "Assignment Strategies",
        scope_tier     = 2,
        tags           = { "assignment" },
        count          = 3,
        max_complexity = 2,
        shop_cost      = 500,
    },

    {   id             = "routing_pack",
        name           = "City Routing",
        scope_tier     = 2,
        tags           = { "routing" },
        count          = 3,
        max_complexity = 3,
        shop_cost      = 800,
    },

    -- ── Tier 3: Region ───────────────────────────────────────────────────────

    {   id             = "hub_routing_pack",
        name           = "Hub & Spoke",
        scope_tier     = 3,
        tags           = { "hub" },
        count          = 2,
        max_complexity = 3,
        shop_cost      = 1200,
    },

    {   id             = "vehicle_pack",
        name           = "Fleet Management",
        scope_tier     = 3,
        tags           = { "vehicle" },
        count          = 2,
        max_complexity = 3,
        shop_cost      = 1200,
    },

    -- ── Tier 4: Continent ────────────────────────────────────────────────────

    {   id             = "economy_pack",
        name           = "Economy Rules",
        scope_tier     = 4,
        tags           = { "economy" },
        count          = 2,
        max_complexity = 3,
        shop_cost      = 2000,
    },

    {   id             = "queue_pack",
        name           = "Queue Control",
        scope_tier     = 4,
        tags           = { "queue" },
        count          = 2,
        max_complexity = 2,
        shop_cost      = 2000,
    },

}
