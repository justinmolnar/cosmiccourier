-- services/NameService.lua
-- Agnostic name generator. Knows nothing about cities, archetypes, or entity
-- kinds — it consumes template lists, contexts, and pool data.
--
-- Core pipeline:
--   filterEligible(templates, context.tags)  →  subset whose `requires` match
--   weightedPick(subset)                     →  one template chosen by weight
--   fill(template, context, extras)          →  substitute every {slot}
--
-- Slot resolution order inside fill():
--   1. context.slots[slot]                  — pre-resolved by NameContextService
--   2. template.slot_overrides[slot]        — per-template inline pool
--   3. extras[slot]                         — caller-provided (pool or string)
--   4. data/names/slot_registry.lua         — global registry (pure data)
--   5. error loudly                         — unresolved slot = missing data
--
-- Determinism: defaults to love.math.random (seeded for seed-replay). Callers
-- may pass their own rng for testing.

local NameService = {}

-- ─── Global slot-registry cache ──────────────────────────────────────────────

local _registry_cache
local function loadRegistry()
    if _registry_cache then return _registry_cache end
    local Registry = require("data.names.slot_registry")
    _registry_cache = {}
    for slot, cfg in pairs(Registry) do
        local mod = require(cfg.module)
        local pool = cfg.key and mod[cfg.key] or mod
        _registry_cache[slot] = pool
    end
    return _registry_cache
end

-- ─── Roman numerals (used as dedup suffix when pools exhaust) ────────────────

local ROMAN = { "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X",
                "XI", "XII", "XIII", "XIV", "XV", "XVI", "XVII", "XVIII", "XIX", "XX" }
local function roman(n) return ROMAN[n - 1] or tostring(n) end

-- ─── Primitives ──────────────────────────────────────────────────────────────

-- Uniform pick from a flat pool with dedup against `used_set`. When all pool
-- entries are used, falls back to "<base> II", "III", …
function NameService.pick(pool, used_set, rng)
    rng = rng or love.math.random
    if not pool or #pool == 0 then return nil end
    used_set = used_set or {}
    local n = #pool

    -- First try: a single random shot (cheap common path).
    local candidate = pool[rng(1, n)]
    if not used_set[candidate] then
        used_set[candidate] = true
        return candidate
    end

    -- Full shuffle scan for any unused entry.
    local order = {}
    for i = 1, n do order[i] = i end
    for i = n, 2, -1 do
        local j = rng(1, i)
        order[i], order[j] = order[j], order[i]
    end
    for _, idx in ipairs(order) do
        local v = pool[idx]
        if not used_set[v] then
            used_set[v] = true
            return v
        end
    end

    -- Exhausted: build "<something> II", "III", etc.
    local base = pool[rng(1, n)]
    local i = 2
    while used_set[base .. " " .. roman(i)] do i = i + 1 end
    local final = base .. " " .. roman(i)
    used_set[final] = true
    return final
end

-- Pick one item from a list by each item's `.weight` (default 1).
function NameService.weightedPick(list, rng)
    rng = rng or love.math.random
    if not list or #list == 0 then return nil end
    local total = 0
    for _, t in ipairs(list) do total = total + (t.weight or 1) end
    if total <= 0 then return list[1] end
    local r = rng() * total
    local acc = 0
    for _, t in ipairs(list) do
        acc = acc + (t.weight or 1)
        if r <= acc then return t end
    end
    return list[#list]
end

-- Return the subset of `templates` whose `requires` / `requires_not` are
-- satisfied by `tags`. A requires value of `true` means the tag must be
-- truthy; any other value means equality.
function NameService.filterEligible(templates, tags)
    local out = {}
    tags = tags or {}
    for _, t in ipairs(templates) do
        local ok = true
        if t.requires then
            for k, v in pairs(t.requires) do
                local tv = tags[k]
                if v == true then
                    if not tv then ok = false; break end
                elseif tv ~= v then
                    ok = false; break
                end
            end
        end
        if ok and t.requires_not then
            for k, v in pairs(t.requires_not) do
                local tv = tags[k]
                if v == true and tv then ok = false; break
                elseif tv == v then ok = false; break end
            end
        end
        if ok then out[#out + 1] = t end
    end
    return out
end

-- Fill a template object `{ t = "…{slot}…", slot_overrides = {...} }` into a
-- string. See top-of-file resolution order.
function NameService.fill(template, context, extras, rng)
    rng = rng or love.math.random
    local registry = loadRegistry()
    local ctx_slots = (context and context.slots) or {}
    local overrides = template.slot_overrides or {}
    local function pickFrom(pool)
        if type(pool) ~= "table" or #pool == 0 then return nil end
        return pool[rng(1, #pool)]
    end
    return (template.t:gsub("%{([%w_]+)%}", function(slot)
        local v = ctx_slots[slot]
        if v ~= nil then return tostring(v) end

        local pool = overrides[slot]
        if pool then
            local p = pickFrom(pool)
            if p ~= nil then return p end
        end

        if extras and extras[slot] ~= nil then
            local e = extras[slot]
            if type(e) == "table" then
                local p = pickFrom(e)
                if p ~= nil then return p end
            else
                return tostring(e)
            end
        end

        pool = registry[slot]
        if pool then
            local p = pickFrom(pool)
            if p ~= nil then return p end
        end

        error("NameService.fill: unresolved slot {" .. slot ..
              "} in template \"" .. tostring(template.t) .. "\"")
    end))
end

-- End-to-end: filter → weighted pick → fill → dedup.
-- Retries up to 8 times if picked name collides with used_set before falling
-- back to roman-numeral suffixing.
function NameService.generate(templates, context, used_set, extras, rng)
    rng = rng or love.math.random
    used_set = used_set or {}
    local eligible = NameService.filterEligible(templates, context and context.tags or nil)
    if #eligible == 0 then
        -- Fallback: any template with no requires.
        eligible = NameService.filterEligible(templates, {})
        if #eligible == 0 then
            error("NameService.generate: no eligible templates (empty list or all gated)")
        end
    end
    for _ = 1, 8 do
        local pick = NameService.weightedPick(eligible, rng)
        local name = NameService.fill(pick, context, extras, rng)
        if not used_set[name] then
            used_set[name] = true
            return name
        end
    end
    -- Dupe-stuck: roman-numeral the latest result.
    local pick = NameService.weightedPick(eligible, rng)
    local base = NameService.fill(pick, context, extras, rng)
    local i = 2
    while used_set[base .. " " .. roman(i)] do i = i + 1 end
    local final = base .. " " .. roman(i)
    used_set[final] = true
    return final
end

-- ─── Convenience: flat-pool person name (driver) ─────────────────────────────

function NameService.person(used_set, rng)
    rng = rng or love.math.random
    local firsts = require("data.names.pools.person_firsts")
    local lasts  = require("data.names.pools.person_lasts")
    local first  = firsts[rng(1, #firsts)]
    local last   = lasts[rng(1, #lasts)]
    local full   = first .. " " .. last
    if used_set then used_set[full] = true end
    return full
end

return NameService
