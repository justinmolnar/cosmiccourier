-- data/entity_details/client.lua

local Archetypes = require("data.client_archetypes")

return {
    title_fn = function(item)
        return item.name or (item.archetype and Archetypes.by_id[item.archetype]
               and Archetypes.by_id[item.archetype].display_name) or "Client"
    end,
    width = 420,
    sections = {
        { type = "fields", label = "Info", rows = {
            { label = "Name",     value_fn = function(c) return c.name or "—" end },
            { label = "Type",     value_fn = function(c)
                local a = Archetypes.by_id[c.archetype]
                return a and a.display_name or c.archetype or "?"
            end },
            { label = "District", value_fn = function(c, g) return c:getDistrict(g) or "—" end },
            { label = "Cargo",    value_fn = function(c, g)
                return string.format("%d / %d", #c.cargo, c:getEffectiveCapacity(g))
            end },
            { label = "Trips Generated", value_fn = function(c) return tostring(c.trips_generated or 0) end },
            { label = "Earnings",        value_fn = function(c) return string.format("$%d", c.earnings or 0) end },
            { label = "Active",          value_fn = function(c) return c.active and "Yes" or "Paused" end },
        }},
        { type = "actions", label = "Actions", items = {
            { label = "Pause Trip Generation",
              action_fn  = function(c) c.active = false end,
              enabled_fn = function(c) return c.active == true end },
            { label = "Resume Trip Generation",
              action_fn  = function(c) c.active = true end,
              enabled_fn = function(c) return c.active == false end },
        }},
        { type = "list", label = "Pending Cargo",
          items_fn  = function(c) return c.cargo end,
          format_fn = function(t) return (t.scope or "?") .. "  $" .. (t.base_payout or 0) end,
          empty     = "No pending trips" },
    },
}
