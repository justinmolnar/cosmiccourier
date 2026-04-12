-- data/rule_packs.lua
-- Pack definitions. Each pack is a query against rule_templates.lua.
-- PackService matches templates by tags + complexity range, then picks `count`.
--
-- Fields:
--   id             — unique string
--   name           — display name
--   tags           — ALL listed tags must be present on a template to match (AND)
--   count          — how many templates to grant from the matched pool
--   min_complexity — (optional) minimum complexity to include (default 1)
--   max_complexity — (optional) maximum complexity to include (default 5)

return {

    {   id             = "starter_pack",
        name           = "Dispatch Basics",
        tags           = { "starter" },
        count          = 4,
        max_complexity = 1,
    },

    {   id             = "assignment_pack",
        name           = "Assignment Strategies",
        tags           = { "assignment" },
        count          = 3,
        max_complexity = 2,
    },

    {   id             = "routing_pack",
        name           = "City Routing",
        tags           = { "routing" },
        count          = 3,
        max_complexity = 3,
    },

    {   id             = "hub_routing_pack",
        name           = "Hub & Spoke",
        tags           = { "hub" },
        count          = 2,
        max_complexity = 3,
    },

    {   id             = "vehicle_pack",
        name           = "Fleet Management",
        tags           = { "vehicle" },
        count          = 2,
        max_complexity = 3,
    },

    {   id             = "economy_pack",
        name           = "Economy Rules",
        tags           = { "economy" },
        count          = 2,
        max_complexity = 3,
    },

    {   id             = "queue_pack",
        name           = "Queue Control",
        tags           = { "queue" },
        count          = 2,
        max_complexity = 2,
    },

}
