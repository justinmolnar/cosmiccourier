-- data/dispatch_properties.lua
-- Property registry for the rep_get_property reporter block.
-- Each entry: { source, key, type, read, params }
--   source: "trip" | "vehicle" | "game" | "fleet"
--   key:    the property identifier shown in the block's "property" enum slot
--   type:   "number" | "string"
--   params: (optional) list of additional slots required by this property:
--            { key, type, options, default }
--   read:   function(ctx, slots) → value
--            slots is the node.slots table containing all selected values.

return {

    -- ── source: trip ─────────────────────────────────────────────────────────
    { source="trip", key="payout",     type="number", read = function(ctx) return ctx.trip and ctx.trip.base_payout or 0 end },
    { source="trip", key="wait_time",  type="number", read = function(ctx) return ctx.trip and ctx.trip.wait_time or 0 end },
    { source="trip", key="bonus",      type="number", read = function(ctx) return ctx.trip and ctx.trip.speed_bonus or 0 end },
    { source="trip", key="leg_count",  type="number", read = function(ctx) return ctx.trip and #ctx.trip.legs or 0 end },
    { source="trip", key="scope",      type="string", read = function(ctx) return ctx.trip and ctx.trip.scope or "" end },
    { source="trip", key="cargo_size", type="number", read = function(ctx)
          if not ctx.trip then return 1 end
          local leg = ctx.trip.legs[ctx.trip.current_leg or 1]
          return leg and leg.cargo_size or 1
      end },

    -- ── source: vehicle ───────────────────────────────────────────────────────
    { source="vehicle", key="speed",         type="number", read = function(ctx) return ctx.vehicle and ctx.vehicle:getSpeed() or 0 end },
    { source="vehicle", key="trips_completed", type="number", read = function(ctx) return ctx.vehicle and ctx.vehicle.trips_completed or 0 end },
    { source="vehicle", key="type",          type="string", read = function(ctx) return ctx.vehicle and ctx.vehicle.type or "" end },

    -- ── source: game ──────────────────────────────────────────────────────────
    { source="game", key="money",      type="number", read = function(ctx) return ctx.game.state.money or 0 end },
    { source="game", key="queue_count", type="number", read = function(ctx) return #ctx.game.entities.trips.pending end },
    { source="game", key="trips_completed", type="number", read = function(ctx) return ctx.game.state.trips_completed or 0 end },
    { source="game", key="rh_timer",   type="number", read = function(ctx)
          local rh = ctx.game.state.rush_hour
          return (rh and rh.active and rh.timer) or 0
      end },

    -- ── source: fleet ─────────────────────────────────────────────────────────
    { source="fleet", key="count",      type="number",
      params = { { key="vehicle_type", type="vehicle_enum" } },
      read = function(ctx, slots)
          local n = 0
          local vtype = (slots.vehicle_type or ""):lower()
          for _, v in ipairs(ctx.game.entities.vehicles) do
              if vtype == "" or (v.type or ""):lower() == vtype then n = n + 1 end
          end
          return n
      end },

    { source="fleet", key="idle_count", type="number",
      params = { { key="vehicle_type", type="vehicle_enum" } },
      read = function(ctx, slots)
          local n = 0
          local vtype = (slots.vehicle_type or ""):lower()
          for _, v in ipairs(ctx.game.entities.vehicles) do
              if (vtype == "" or (v.type or ""):lower() == vtype)
                 and v.state and v.state.name == "Idle" then n = n + 1 end
          end
          return n
      end },

    { source="fleet", key="utilization", type="number",
      params = { { key="vehicle_type", type="vehicle_enum" } },
      read = function(ctx, slots)
          local total, non_idle = 0, 0
          local vtype = (slots.vehicle_type or ""):lower()
          for _, v in ipairs(ctx.game.entities.vehicles) do
              if vtype == "" or (v.type or ""):lower() == vtype then
                  total = total + 1
                  if not (v.state and v.state.name == "Idle") then non_idle = non_idle + 1 end
              end
          end
          return total > 0 and math.floor(non_idle / total * 100) or 0
      end },
}
