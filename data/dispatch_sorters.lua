-- data/dispatch_sorters.lua
-- Registry of scoring metrics for the Find block (vehicles) and sort_queue action (trips).
-- Agnostic: The engine calls 'score' for each item; lower (asc) or higher (desc) wins.

local SCOPE_RANK = { district=1, city=2, region=3, continent=4, world=5 }

return {
    -- ── Vehicle sorters ──────────────────────────────────────────────────────
    { 
        id       = "nearest",
        label    = "Nearest",
        for_type = "vehicles",
        order    = "asc",
        score    = function(item, ctx) 
            local leg  = ctx.trip.legs[ctx.trip.current_leg]
            local sx   = leg and leg.start_plot and leg.start_plot.x or 0
            local sy   = leg and leg.start_plot and leg.start_plot.y or 0
            local ax   = item.grid_anchor and item.grid_anchor.x or 0
            local ay   = item.grid_anchor and item.grid_anchor.y or 0
            return (ax - sx)^2 + (ay - sy)^2
        end 
    },
    { 
        id       = "fastest",
        label    = "Fastest",
        for_type = "vehicles",
        order    = "desc",
        score    = function(item, ctx) 
            return item:getSpeed() 
        end 
    },
    { 
        id       = "most_capacity",
        label    = "Most Capacity",
        for_type = "vehicles",
        order    = "desc",
        score    = function(item, ctx) 
            return item:getEffectiveCapacity(ctx.game) 
        end 
    },
    { 
        id       = "least_recent",
        label    = "Least Recently Used",
        for_type = "vehicles",
        order    = "asc",
        score    = function(item, ctx) 
            return item.last_trip_end_time or 0 
        end 
    },

    -- ── Trip sorters ─────────────────────────────────────────────────────────
    { 
        id       = "highest_payout",
        label    = "Highest Payout",
        for_type = "pending_trips",
        order    = "desc",
        score    = function(item, ctx) 
            return item.base_payout or 0 
        end 
    },
    {
        id       = "longest_wait",
        label    = "Longest Wait",
        for_type = "pending_trips",
        order    = "desc",
        score    = function(item, ctx)
            return item.wait_time or 0
        end
    },

    -- ── Queue sort metrics (used by sort_queue action block) ─────────────────
    { id="payout", label="Highest Payout",  for_type="pending_trips", order="desc",
      score = function(item, ctx) return item.base_payout or 0 end },
    { id="wait",   label="Longest Wait",    for_type="pending_trips", order="desc",
      score = function(item, ctx) return item.wait_time or 0 end },
    { id="bonus",  label="Highest Bonus",   for_type="pending_trips", order="desc",
      score = function(item, ctx) return item.speed_bonus or 0 end },
    { id="scope",  label="Scope (nearest)", for_type="pending_trips", order="asc",
      score = function(item, ctx) return SCOPE_RANK[item.scope] or 0 end },
    { id="cargo",  label="Cargo Size",      for_type="pending_trips", order="desc",
      score = function(item, ctx)
          local leg = item.legs and item.legs[item.current_leg or 1]
          return leg and leg.cargo_size or 0
      end },
}
