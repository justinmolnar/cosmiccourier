-- data/names/tags.lua
-- Single source of truth for every tag NameContextService can emit and every
-- tag templates can declare in `requires`. New tags must be added here first.
--
-- Some tags are boolean (presence-only): {coastal=true, cold=true}.
-- Others carry a string value: {in_district="waterfront", dominant_district="fuel"}.
-- Templates match tag names; if the tag carries a string, `requires` may pin
-- a specific value (see NameService for matching semantics).
--
-- This file also declares tag-derivation thresholds so the context builder's
-- numeric cutoffs live alongside the tag vocabulary, not inside service code.

return {
    -- Which tags exist at each context scope. Purely informational — lets the
    -- context builder validate that it only emits known tags.
    scopes = {
        continent = { "size_small", "size_large", "dominant_biome",
                      "mountainous", "desert", "forest", "temperate", "cold", "hot" },
        region    = { "has_continent_name", "mountainous", "coastal", "near_lake",
                      "near_river", "desert", "forest", "cold", "hot", "temperate",
                      "size_small", "size_large", "dominant_biome" },
        city      = { "has_continent_name", "has_region_name", "coastal",
                      "near_lake", "near_river", "highland", "lowland",
                      "cold", "hot", "temperate", "dominant_district" },
        building  = { "has_continent_name", "has_region_name", "has_city_name",
                      "coastal", "near_lake", "near_river", "highland",
                      "cold", "hot", "temperate", "in_district", "dominant_district" },
    },

    -- Thresholds used by NameContextService to turn raw world data into tags.
    thresholds = {
        -- Continents
        continent_small_max_frac = 0.10,  -- size/total_land <= this → size_small
        continent_large_min_frac = 0.25,  -- size/total_land >= this → size_large

        -- Regions (cell counts relative to largest region)
        region_small_max_ratio   = 0.35,
        region_large_min_ratio   = 0.75,

        -- Climate buckets (temperature 0..1 from heightmap biome data)
        climate_cold_max         = 0.35,
        climate_hot_min          = 0.65,

        -- Adjacency search radius in world sub-cells for building → water tags.
        adjacency_search_radius  = 4,
    },
}
