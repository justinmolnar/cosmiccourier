-- data/client_archetypes.lua
-- Client archetype registry. Each archetype differs in spawn zone preference,
-- cargo size range, destination scope distribution, base spawn frequency,
-- payout multiplier, market cost, and scope-tier gating.
--
-- Services consult this registry by archetype id. No archetype ids should
-- appear in service/model code outside this file and data/upgrades.json.
--
-- Fields:
--   id                   — unique string; used as key in state.upgrades for
--                          per-archetype multipliers (e.g. "<id>_spawn_rate_mult")
--   display_name         — UI label
--   icon                 — emoji / glyph for UI
--   description          — one-line flavour text
--   spawn_zones          — list of zone ids (data/zones.json) where the archetype
--                          can be placed. Placement prefers these zones; falls back
--                          to any can_send plot if none available in the city.
--   cargo_size_range     — {min, max} inclusive; TripGenerator rolls uniformly.
--   dest_scope_weights   — weighted distribution of trip destination scope.
--   base_spawn_seconds   — {min, max} inclusive; base trip-timer interval.
--   payout_multiplier    — applied to base trip payout.
--   required_scope_tier  — license tier needed to buy this archetype at market.
--   market_cost          — flat cost at the market; no escalation per-buy.
--
-- All numeric values are placeholders; Phase 8 does the tuning pass.

local Archetypes = {
    list = {
        {
            id                  = "lawyer",
            display_name        = "Law Firm",
            icon                = "⚖️",
            description         = "Small parcels, mostly local.",
            spawn_zones         = { "government", "courthouse" },
            cargo_size_range    = { 1, 3 },
            dest_scope_weights  = { district = 90, city = 10, region = 0 },
            base_spawn_seconds  = { 8, 14 },
            payout_multiplier   = 1.20,
            required_scope_tier = 1,
            market_cost         = 150,
        },
        {
            id                  = "restaurant",
            display_name        = "Restaurant",
            icon                = "🍽️",
            description         = "Frequent tiny deliveries, short range.",
            spawn_zones         = { "restaurant_row", "fine_dining", "fast_food_strip" },
            cargo_size_range    = { 1, 2 },
            dest_scope_weights  = { district = 100, city = 0, region = 0 },
            base_spawn_seconds  = { 5, 9 },
            payout_multiplier   = 0.85,
            required_scope_tier = 1,
            market_cost         = 100,
        },
        {
            id                  = "retail",
            display_name        = "Retail Shop",
            icon                = "🛍️",
            description         = "General commerce; mostly local with some cross-district.",
            spawn_zones         = { "retail_strip", "shopping_mall", "boutique_shops",
                                    "luxury_retail", "market", "farmers_market" },
            cargo_size_range    = { 2, 5 },
            dest_scope_weights  = { district = 70, city = 30, region = 0 },
            base_spawn_seconds  = { 7, 12 },
            payout_multiplier   = 1.00,
            required_scope_tier = 1,
            market_cost         = 200,
        },
        {
            id                  = "warehouse",
            display_name        = "Warehouse",
            icon                = "📦",
            description         = "Bulk shipments; mix of district / city / region.",
            spawn_zones         = { "warehouse_zone", "freight_yard" },
            cargo_size_range    = { 10, 30 },
            dest_scope_weights  = { district = 30, city = 50, region = 20 },
            base_spawn_seconds  = { 15, 25 },
            payout_multiplier   = 2.50,
            required_scope_tier = 2,
            market_cost         = 800,
        },
        {
            id                  = "factory",
            display_name        = "Factory",
            icon                = "🏭",
            description         = "Massive cross-region freight.",
            spawn_zones         = { "factory" },
            cargo_size_range    = { 25, 60 },
            dest_scope_weights  = { district = 10, city = 40, region = 50 },
            base_spawn_seconds  = { 20, 35 },
            payout_multiplier   = 4.00,
            required_scope_tier = 3,
            market_cost         = 2500,
        },
    },
}

-- Build the id -> archetype map once at load time for O(1) lookup.
Archetypes.by_id = {}
for _, a in ipairs(Archetypes.list) do
    Archetypes.by_id[a.id] = a
end

-- Default archetype id. Services reference this instead of hardcoding a name,
-- so the archetype pick can be changed in one place.
-- "restaurant" is the starter because its cargo range (1-2) fits the
-- fresh-save bike's capacity (1) — any larger range strands the player
-- on trips they can't assign.
Archetypes.default_id = "restaurant"

return Archetypes
