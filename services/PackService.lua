-- services/PackService.lua
-- Stateless pack opening logic.
-- Queries rule_templates by pack definition, picks random selection, grants unlocks.
-- Block/enum unlocks are derived automatically by walking each template's node tree.

local UnlockService = require("services.UnlockService")
local Registry      = require("data.unlock_registry")

local PackService = {}

--- Check if a template matches a pack's tag query (AND semantics).
local function matchesTags(template, pack_tags)
    for _, tag in ipairs(pack_tags) do
        local found = false
        for _, t in ipairs(template.tags or {}) do
            if t == tag then found = true; break end
        end
        if not found then return false end
    end
    return true
end

--- Check if a template is already owned.
local function isOwned(template, state)
    return state.unlocked[Registry.key("template", template.id)] == true
end

--- Weighted random selection of `count` items from a pool.
--- Higher rarity = less likely. rarity=1 is common, rarity=3 is 3x rarer.
local function weightedPick(pool, count)
    if #pool == 0 then return {} end

    local weights = {}
    local total   = 0
    for i, t in ipairs(pool) do
        weights[i] = 1 / (t.rarity or 1)
        total = total + weights[i]
    end

    local picked = {}
    local used   = {}
    for _ = 1, math.min(count, #pool) do
        local roll = math.random() * total
        local sum  = 0
        for i, t in ipairs(pool) do
            if not used[i] then
                sum = sum + weights[i]
                if sum >= roll then
                    picked[#picked + 1] = t
                    used[i] = true
                    total = total - weights[i]
                    break
                end
            end
        end
    end
    return picked
end

--- Open a pack: query templates, pick random selection, grant unlocks.
--- Block/enum keys are derived by walking each template's build() output.
--- Returns { templates = { ... }, new_keys = { ... } }.
function PackService.openPack(pack_def, all_templates, state)
    local min_c = pack_def.min_complexity or 1
    local max_c = pack_def.max_complexity or 5

    -- Build candidate pool
    local pool = {}
    for _, t in ipairs(all_templates) do
        local c = t.complexity or 1
        if c >= min_c and c <= max_c
           and matchesTags(t, pack_def.tags or {})
           and not isOwned(t, state) then
            pool[#pool + 1] = t
        end
    end

    -- Guaranteed templates: if the pack declares `guaranteed = {"id", ...}`,
    -- those templates are picked first (if in the pool and not already owned).
    -- Remaining slots filled randomly from whatever's left.
    local picked = {}
    local used = {}
    if pack_def.guaranteed then
        for _, gid in ipairs(pack_def.guaranteed) do
            for pi, t in ipairs(pool) do
                if t.id == gid and not used[pi] then
                    picked[#picked + 1] = t
                    used[pi] = true
                    break
                end
            end
        end
    end
    local remaining_count = (pack_def.count or 3) - #picked
    if remaining_count > 0 then
        local leftover = {}
        for pi, t in ipairs(pool) do
            if not used[pi] then leftover[#leftover + 1] = t end
        end
        local extras = weightedPick(leftover, remaining_count)
        for _, t in ipairs(extras) do picked[#picked + 1] = t end
    end

    -- Grant unlocks
    local new_keys = {}
    for _, t in ipairs(picked) do
        -- Mark the template itself as unlocked
        local tkey = Registry.key("template", t.id)
        if not state.unlocked[tkey] then
            state.unlocked[tkey] = true
            new_keys[#new_keys + 1] = tkey
        end

        -- Grant any explicitly listed prefab unlocks
        for _, key in ipairs(t.unlocks or {}) do
            if not state.unlocked[key] then
                state.unlocked[key] = true
                new_keys[#new_keys + 1] = key
            end
        end

        -- Derive block/action/enum keys from the template's node tree
        local stack = t.build()
        local derived = UnlockService.deriveKeys(stack)
        for key in pairs(derived) do
            if not state.unlocked[key] then
                state.unlocked[key] = true
                new_keys[#new_keys + 1] = key
            end
        end
    end

    -- Also derive keys from any newly unlocked prefabs
    local PREFABS = require("data.dispatch_prefabs")
    for _, pf in ipairs(PREFABS) do
        if state.unlocked[Registry.key("prefab", pf.id)] then
            local ok, built = pcall(pf.build, {})
            if ok and built then
                local nodes = type(built[1]) == "table" and built or { built }
                local derived = UnlockService.deriveKeys(nodes)
                for key in pairs(derived) do
                    if not state.unlocked[key] then
                        state.unlocked[key] = true
                        new_keys[#new_keys + 1] = key
                    end
                end
            end
        end
    end

    return { templates = picked, new_keys = new_keys }
end

--- Find a pack definition by id.
function PackService.findPack(pack_id, all_packs)
    for _, p in ipairs(all_packs) do
        if p.id == pack_id then return p end
    end
    return nil
end

--- Returns true if the pack still has unowned templates in its pool.
function PackService.hasCardsRemaining(pack_def, all_templates, state)
    local min_c = pack_def.min_complexity or 1
    local max_c = pack_def.max_complexity or 5
    for _, t in ipairs(all_templates) do
        local c = t.complexity or 1
        if c >= min_c and c <= max_c
           and matchesTags(t, pack_def.tags or {})
           and not isOwned(t, state) then
            return true
        end
    end
    return false
end

return PackService
