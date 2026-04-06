-- data/zones.lua
-- Thin loader. All zone, district, and biome data lives in JSON files.
--   zones.json          — zone ids + colors
--   districts.json      — district weights, cannot rules, assignable flag
--   biome_zone_mults.json — per-biome zone weight multipliers

local json = require("lib.json")
local Zones = {}

-- ── Zones (from zones.json) ───────────────────────────────────────────────────

local raw_zones = json.decode(love.filesystem.read("data/zones.json"))

Zones.STATES = {}
Zones.COLORS = {}

for _, z in ipairs(raw_zones) do
    Zones.STATES[#Zones.STATES + 1] = z.id
    if z.color then
        Zones.COLORS[z.id] = z.color
    end
end

Zones.COLOR_ALPHA = 0.78

-- Fully permissive adjacency — clustering comes entirely from per-cell weights
local all = {}
for _, id in ipairs(Zones.STATES) do all[id] = true end
local function dirs(t) return {N=t, S=t, E=t, W=t} end
Zones.ADJACENCY = {}
for _, id in ipairs(Zones.STATES) do
    Zones.ADJACENCY[id] = dirs(all)
end

-- ── Districts (from districts.json) ──────────────────────────────────────────

local raw_districts = json.decode(love.filesystem.read("data/districts.json"))

Zones.DISTRICT_WEIGHTS      = {}
Zones.DISTRICT_RULES        = {}
Zones.RANDOM_DISTRICT_TYPES = {}

for _, d in ipairs(raw_districts) do
    Zones.DISTRICT_WEIGHTS[d.id] = d.weights
    if d.cannot and #d.cannot > 0 then
        Zones.DISTRICT_RULES[d.id] = { cannot = d.cannot }
    end
    if d.assignable then
        Zones.RANDOM_DISTRICT_TYPES[#Zones.RANDOM_DISTRICT_TYPES + 1] = d.id
    end
end

-- ── Zone logistics flags (from zones.json) ────────────────────────────────────
-- CAN_SEND[zone_id]    = true  → zone generates outbound commercial shipments
-- CAN_RECEIVE[zone_id] = true  → zone accepts deliveries

Zones.CAN_SEND    = {}
Zones.CAN_RECEIVE = {}

for _, z in ipairs(raw_zones) do
    Zones.CAN_SEND[z.id]    = z.can_send    == true
    Zones.CAN_RECEIVE[z.id] = z.can_receive == true
end

-- ── Biome zone multipliers (from biome_zone_mults.json) ──────────────────────

Zones.BIOME_MULTS = json.decode(love.filesystem.read("data/biome_zone_mults.json"))
-- River/lake boost applied in WorldSandboxController at generation time.

-- ── Helpers ──────────────────────────────────────────────────────────────────

function Zones.isType(zone_type, category)
    return zone_type == category
end

function Zones.getCategory(zone_type)
    return zone_type
end

return Zones
