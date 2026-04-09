-- services/CityPlacementService.lua
-- Portable city placement: given suitability scores, continent/region data,
-- and world dimensions + params, returns a list of city locations.
-- Zero love.* imports. Zero game references. Pure computation.

local CityPlacementService = {}

-- Place cities across the world.
-- Returns city_locations: array of {x, y, s, ...} tables.
--
-- suitability_scores  [cell_idx] = score
-- continent_map       [cell_idx] = continent_id
-- continents          array of {id, size, ...}
-- region_map          [cell_idx] = region_id
-- regions_list        [region_id] = {continent_id, ...}
-- w, h                world dimensions
-- params              .city_count, .city_min_sep
function CityPlacementService.placeCities(
    suitability_scores, continent_map, continents,
    region_map, regions_list, w, h, params
)
    local total_count = math.max(1, math.floor(params.city_count  or 12))
    local min_sep     = math.max(1, math.floor(params.city_min_sep or 30))
    local scores      = suitability_scores
    local cont_map    = continent_map
    local conts       = continents
    local reg_map     = region_map
    local reg_list    = regions_list

    -- Fall back to flat greedy if no continent/region data
    if not cont_map or not conts or #conts == 0 or not reg_map or not reg_list then
        local cands = {}
        for i = 1, w * h do
            local s = scores[i] or 0
            if s > 0 then
                cands[#cands + 1] = { x=(i-1)%w+1, y=math.floor((i-1)/w)+1, s=s }
            end
        end
        table.sort(cands, function(a, b) return a.s > b.s end)
        local cities, sq = {}, min_sep * min_sep
        for _, c in ipairs(cands) do
            local ok = true
            for _, p2 in ipairs(cities) do
                local dx, dy = c.x-p2.x, c.y-p2.y
                if dx*dx+dy*dy < sq then ok=false; break end
            end
            if ok then cities[#cities+1]=c end
            if #cities >= total_count then break end
        end
        return cities
    end

    -- Step 1: proportional city allocation per continent (largest-remainder)
    local total_land = 0
    for _, c in ipairs(conts) do total_land = total_land + c.size end
    if total_land == 0 then return {} end

    local allocs     = {}
    local alloc_sum  = 0
    local remainders = {}
    for i, c in ipairs(conts) do
        local exact   = total_count * c.size / total_land
        local floor_v = math.floor(exact)
        allocs[i]     = floor_v
        alloc_sum     = alloc_sum + floor_v
        remainders[i] = { idx = i, rem = exact - floor_v }
    end
    table.sort(remainders, function(a, b) return a.rem > b.rem end)
    for k = 1, math.min(total_count - alloc_sum, #remainders) do
        allocs[remainders[k].idx] = allocs[remainders[k].idx] + 1
    end

    -- Step 2: build per-region sorted candidate lists, grouped by continent
    local cont_id_to_idx = {}
    for i, c in ipairs(conts) do cont_id_to_idx[c.id] = i end

    -- reg_cands[rid] = sorted candidates; cont_regions[ci] = list of rids
    local reg_cands    = {}
    local cont_regions = {}
    for i = 1, #conts do cont_regions[i] = {} end

    for i = 1, w * h do
        local s   = scores[i] or 0
        local rid = reg_map[i] or 0
        if s > 0 and rid > 0 and reg_list[rid] then
            local ci = cont_id_to_idx[reg_list[rid].continent_id]
            if ci then
                if not reg_cands[rid] then
                    reg_cands[rid] = {}
                    cont_regions[ci][#cont_regions[ci]+1] = rid
                end
                local t = reg_cands[rid]
                t[#t+1] = { x=(i-1)%w+1, y=math.floor((i-1)/w)+1, s=s }
            end
        end
    end
    for _, cands in pairs(reg_cands) do
        table.sort(cands, function(a, b) return a.s > b.s end)
    end

    local reg_count = {}
    local reg_ptr   = {}
    for rid in pairs(reg_cands) do
        reg_count[rid] = 0
        reg_ptr[rid]   = 1
    end

    -- All placed cities (global, for min_sep enforcement across continents)
    local all_cities = {}
    local sq         = min_sep * min_sep

    -- Step 3: per-continent placement. Each pick selects the globally highest-
    -- scoring candidate from any region on that continent that is currently at
    -- the minimum city count. Regions above the minimum are locked until all
    -- catch up, ensuring every region gets one city before any gets two.
    for ci, c_rids in ipairs(cont_regions) do
        local want = allocs[ci]
        local placed = 0

        while placed < want do
            -- Find minimum city count among regions with remaining candidates
            local min_count = math.huge
            for _, rid in ipairs(c_rids) do
                if reg_ptr[rid] <= #reg_cands[rid] then
                    min_count = math.min(min_count, reg_count[rid])
                end
            end
            if min_count == math.huge then break end  -- all regions exhausted

            -- Among all regions at the minimum, find the single best unblocked candidate
            local best_c   = nil
            local best_rid = nil
            local best_idx = nil
            local best_s   = -1

            for _, rid in ipairs(c_rids) do
                if reg_count[rid] == min_count then
                    local cands = reg_cands[rid]
                    for idx = reg_ptr[rid], #cands do
                        local c = cands[idx]
                        local ok = true
                        for _, p2 in ipairs(all_cities) do
                            local dx, dy = c.x-p2.x, c.y-p2.y
                            if dx*dx+dy*dy < sq then ok=false; break end
                        end
                        if ok then
                            if c.s > best_s then
                                best_s = c.s; best_c = c; best_rid = rid; best_idx = idx
                            end
                            break  -- candidates sorted; first unblocked is best for this region
                        end
                    end
                end
            end

            if not best_c then break end  -- nothing placeable (min_sep too large)

            reg_ptr[best_rid] = best_idx + 1
            all_cities[#all_cities+1] = best_c
            reg_count[best_rid] = reg_count[best_rid] + 1
            placed = placed + 1
        end
    end

    return all_cities
end

return CityPlacementService
