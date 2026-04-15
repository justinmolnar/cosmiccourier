-- views/WrapRender.lua
-- Per-frame "world wrap" context shared between the world renderer and
-- anything else that draws in world coordinates. The world tiles horizontally
-- (no vertical wrap), so the camera viewport may overlap multiple "copies"
-- of the world; we need every world-coord draw to render once per visible
-- copy.
--
--                          ──── RULE FOR ALL FUTURE CODE ────
--   If you draw at WORLD coordinates inside the world view:
--     • call utils/DrawingUtils.drawWorldIcon (it auto-wraps via this module)
--     • OR wrap your draw block in WrapRender.eachOffset(game, fn)
--   Drawing in screen-space UI does NOT need to wrap.
--   Drawing outside an active wrap context (e.g., world-gen modal) is a no-op
--   for wrap concerns — eachOffset still runs your fn once with offset=0.
-- ──────────────────────────────────────────────────────────
--
-- The world renderer publishes the wrap context once per frame:
--   WrapRender.beginFrame(game, tile_i0, tile_i1, mpw)
--   ... draw world ...
--   WrapRender.endFrame(game)
--
-- Consumers iterate offsets:
--   WrapRender.eachOffset(game, function(offset_x) ... end)
--
-- Knows nothing about specific entity kinds — purely a (range, callback)
-- iterator with a tiny per-frame state holder.

local WrapRender = {}

function WrapRender.beginFrame(game, tile_i0, tile_i1, mpw)
    if not game then return end
    game._world_wrap = {
        tile_i0 = tile_i0 or 0,
        tile_i1 = tile_i1 or 0,
        mpw     = mpw     or 0,
    }
end

function WrapRender.endFrame(game)
    if not game then return end
    game._world_wrap = nil
end

function WrapRender.isActive(game)
    return game ~= nil and game._world_wrap ~= nil
end

-- Re-entry depth counter. When greater than 0, `eachOffset` runs `fn(0)` once
-- (single pass) instead of iterating wrap tiles — so a wrap-aware helper
-- (e.g., DrawingUtils.drawWorldIcon) called from inside an outer
-- `eachOffset` block doesn't double-wrap.
local _depth = 0

-- Run `fn(offset_x)` once per visible wrapped tile. When no wrap context is
-- active (or the range collapses to a single tile), fn runs once with offset
-- 0 — so callers don't need to special-case unwrapped contexts.
-- Re-entrant: nested `eachOffset` calls are flattened (inner runs once at 0).
function WrapRender.eachOffset(game, fn)
    if not fn then return end
    local wrap = game and game._world_wrap
    if not wrap or wrap.mpw == 0 or wrap.tile_i0 == nil or wrap.tile_i1 == nil then
        fn(0)
        return
    end
    if _depth > 0 then
        fn(0)
        return
    end
    _depth = _depth + 1
    local ok, err = pcall(function()
        for i = wrap.tile_i0, wrap.tile_i1 do
            fn(i * wrap.mpw)
        end
    end)
    _depth = _depth - 1
    if not ok then error(err) end
end

return WrapRender
