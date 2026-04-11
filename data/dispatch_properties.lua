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
    -- Mode of the next inter-modal transfer in this trip's planned route, or
    -- "" if the route is single-modal / unplanned. Reads trip.route_plan.
    { source="trip", key="next_mode", type="string", read = function(ctx)
          local plan = ctx.trip and ctx.trip.route_plan
          if not plan or not plan.segments then return "" end
          for _, seg in ipairs(plan.segments) do
              if seg.kind == "transfer" and seg.to_e then
                  return seg.to_e.mode or ""
              end
          end
          return ""
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

    -- ── source: depot ─────────────────────────────────────────────────────────
    { source="depot", key="vehicle_count", type="number", read = function(ctx)
          local d = ctx.game.entities.depots and ctx.game.entities.depots[1]
          return d and #(d.assigned_vehicles or {}) or 0
      end },
    { source="depot", key="open",          type="string", read = function(ctx)
          local d = ctx.game.entities.depots and ctx.game.entities.depots[1]
          return d and (d.open and "true" or "false") or "false"
      end },

    -- ── source: client ────────────────────────────────────────────────────────
    { source="client", key="count",        type="number", read = function(ctx)
          return #(ctx.game.entities.clients or {})
      end },
    { source="client", key="active_count", type="number", read = function(ctx)
          local n = 0
          for _, c in ipairs(ctx.game.entities.clients or {}) do if not c.paused then n = n + 1 end end
          return n
      end },

    -- ── source: building ─────────────────────────────────────────────────────
    { source="building", key="nearest_pos", type="table",
      params = { { key="building_type", type="enum", options={"dock","depot","client"} } },
      read = function(ctx, slots)
          if not ctx.trip then return nil end
          local leg = ctx.trip.legs[ctx.trip.current_leg or 1]
          local sp  = leg and leg.start_plot
          if not sp then return nil end
          local BS    = require("services.BuildingService")
          local btype = (slots.building_type or ""):lower()
          local best, best_d2 = nil, math.huge
          for _, b in ipairs(BS.allBuildings(ctx.game)) do
              local bid = b.cfg and b.cfg.id or b.id or ""
              if bid:lower() == btype then
                  local bx = b.plot and b.plot.x or b.x
                  local by = b.plot and b.plot.y or b.y
                  local d2 = (bx - sp.x)^2 + (by - sp.y)^2
                  if d2 < best_d2 then best_d2 = d2; best = {x = bx, y = by} end
              end
          end
          return best
      end },

    { source="building", key="nearest_to_dest_pos", type="table",
      params = { { key="building_type", type="enum", options={"dock","depot","client"} } },
      read = function(ctx, slots)
          if not ctx.trip then return nil end
          -- Use the original final destination if the trip has been rerouted,
          -- otherwise use the current leg's end_plot.
          local ep = ctx.trip.final_destination
          if not ep then
              local leg = ctx.trip.legs[ctx.trip.current_leg or 1]
              ep = leg and leg.end_plot
          end
          if not ep then return nil end
          local BS    = require("services.BuildingService")
          local btype = (slots.building_type or ""):lower()
          local best, best_d2 = nil, math.huge
          for _, b in ipairs(BS.allBuildings(ctx.game)) do
              local bid = b.cfg and b.cfg.id or b.id or ""
              if bid:lower() == btype then
                  local bx = b.plot and b.plot.x or b.x
                  local by = b.plot and b.plot.y or b.y
                  local d2 = (bx - ep.x)^2 + (by - ep.y)^2
                  if d2 < best_d2 then best_d2 = d2; best = {x = bx, y = by} end
              end
          end
          return best
      end },

    { source="building", key="cargo_count", type="number",
      params = { { key="building_type", type="enum", options={"dock","depot","client"} } },
      read = function(ctx, slots)
          local BS    = require("services.BuildingService")
          local btype = (slots.building_type or ""):lower()
          local total = 0
          for _, b in ipairs(BS.allBuildings(ctx.game)) do
              local bid = b.cfg and b.cfg.id or b.id or ""
              if bid:lower() == btype then total = total + #(b.cargo or {}) end
          end
          return total
      end },
}
