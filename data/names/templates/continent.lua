-- data/names/templates/continent.lua
-- Continent name templates. Continents are root-level: no parent names to reference.
-- Templates draw from continent_bases pool and occasionally add a terrain modifier.
--
-- Template shape:
--   { t = <string>, requires = {tag=...}, requires_not = {tag=...},
--     weight = <number>, slot_overrides = { slot_name = {...pool...} } }
-- Missing `requires` / `requires_not` = any; missing `weight` = 1.

return {
    { t = "{continent_base}",                            weight = 5 },
    { t = "{continent_base} {highland_descriptor}",      weight = 1, requires = { mountainous = true } },
    { t = "{continent_base}",                            weight = 2, requires = { size_large = true } },
    { t = "Greater {continent_base}",                    weight = 1, requires = { size_large = true } },
    { t = "{continent_base} Isles",                      weight = 2, requires = { size_small = true } },
    { t = "{climate_adj} {continent_base}",              weight = 1, requires = { cold = true } },
    { t = "{climate_adj} {continent_base}",              weight = 1, requires = { hot = true } },
}
