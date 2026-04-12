-- services/DispatchPaletteService.lua
-- Pure palette filtering and grouping logic for the dispatch rule editor.
-- No love.* imports. No game references.

local UnlockService = require("services.UnlockService")
local Registry      = require("data.unlock_registry")

local DispatchPaletteService = {}

-- Returns the subset of `all` that passes the current tag + search + unlock filters.
-- Multi-tag: a block passes only if it has ALL active tags (AND semantics).
-- `unlock_namespace` is "block" or "prefab" — determines the unlock key prefix.
-- `state` is game.state (contains .unlocked). Pass nil to skip unlock filtering.
function DispatchPaletteService.filter(all, filter, unlock_namespace, state)
    local has_tags   = next(filter.active_tags) ~= nil
    local search     = filter.search:lower()
    local check_lock = state ~= nil and unlock_namespace ~= nil
    local result     = {}
    for _, def in ipairs(all) do
        -- Unlock: must be unlocked in the player's state
        if check_lock then
            if not UnlockService.isUnlocked(Registry.key(unlock_namespace, def.id), state) then
                goto continue
            end
        end
        -- Tag: must have every active tag
        local tag_ok = true
        if has_tags then
            for t in pairs(filter.active_tags) do
                local found = false
                if def.tags then
                    for _, dt in ipairs(def.tags) do
                        if dt == t then found = true; break end
                    end
                end
                if not found then tag_ok = false; break end
            end
        end
        -- Search: pass if empty or matches label, tooltip, or tip text
        local search_ok = search == ""
            or (def.label   and def.label:lower():find(search, 1, true))
            or (def.tooltip and def.tooltip:lower():find(search, 1, true))
            or (def.tip     and def.tip:lower():find(search, 1, true))
        if tag_ok and search_ok then result[#result+1] = def end
        ::continue::
    end
    return result
end

-- Groups a flat list of defs by category, sorted by hue within each group.
-- Returns an array of { cat, defs } in the canonical category order.
local CAT_ORDER = { "hat", "control", "loop", "find", "boolean", "reporter", "stack" }

local function rgbHue(r, g, b)
    local mx = math.max(r, g, b)
    local mn = math.min(r, g, b)
    local d  = mx - mn
    if d < 0.001 then return 0 end  -- achromatic
    local h
    if mx == r then     h = (g - b) / d % 6
    elseif mx == g then h = (b - r) / d + 2
    else                h = (r - g) / d + 4
    end
    return h / 6  -- 0–1
end

function DispatchPaletteService.group(visible)
    local by_cat  = {}
    local seen    = {}
    for _, def in ipairs(visible) do
        local c = def.category
        if not by_cat[c] then by_cat[c] = {}; seen[#seen+1] = c end
        by_cat[c][#by_cat[c]+1] = def
    end
    -- Sort each group by hue so same-coloured blocks cluster together
    for _, defs in pairs(by_cat) do
        table.sort(defs, function(a, b)
            local ca, cb = a.color or {0.5,0.5,0.5}, b.color or {0.5,0.5,0.5}
            return rgbHue(ca[1],ca[2],ca[3]) < rgbHue(cb[1],cb[2],cb[3])
        end)
    end
    local groups = {}
    for _, c in ipairs(CAT_ORDER) do
        if by_cat[c] then groups[#groups+1] = { cat=c, defs=by_cat[c] }; by_cat[c]=nil end
    end
    for _, c in ipairs(seen) do
        if by_cat[c] then groups[#groups+1] = { cat=c, defs=by_cat[c] } end
    end
    return groups
end

return DispatchPaletteService
