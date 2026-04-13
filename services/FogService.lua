-- services/FogService.lua
-- Stateless fog-of-war service. Provides reveal mask data and generates cloud
-- noise texture data. No love.graphics calls — view layer handles rendering.
local FogService = {}

--- Returns the current fog tier (integer 1-5).
local function _getTier(game)
    local st = game.state
    if not st then return 1 end
    return (st.upgrades and st.upgrades.fog_tier) or st.fog_tier or 1
end

--- Returns the fog reveal mask ImageData for the current tier,
--- or nil when the world is fully revealed (tier >= 5).
---
--- @return table|nil  { mask_data, mask_w, mask_h }
function FogService.getRevealMask(game)
    local tier = _getTier(game)
    if tier >= 5 then return nil end

    local masks = game.fog_reveal_masks
    if not masks then return nil end

    local mask_data = masks[tier]
    if not mask_data then return nil end

    return {
        mask_data = mask_data,
        mask_w    = game.fog_mask_w or 1,
        mask_h    = game.fog_mask_h or 1,
    }
end

--- Generates a tileable cloud noise ImageData using FBM.
--- Uses 4D torus sampling for seamless tiling.
--- Returns love.image.ImageData (not a GPU image — caller promotes to Image).
function FogService.generateCloudTexture(C)
    local FC   = C.FOG
    local size = FC.CLOUD_TEXTURE_SIZE
    local oct  = FC.CLOUD_OCTAVES
    local pers = FC.CLOUD_PERSISTENCE
    local freq = FC.CLOUD_BASE_FREQ

    local imgdata = love.image.newImageData(size, size)
    local pi2 = math.pi * 2

    for py = 0, size - 1 do
        local ny = py / size
        local cy = math.cos(ny * pi2)
        local sy = math.sin(ny * pi2)
        for px = 0, size - 1 do
            local nx = px / size
            local cx = math.cos(nx * pi2)
            local sx = math.sin(nx * pi2)

            local val = 0
            local amp = 1
            local f   = freq
            local max_amp = 0

            for _ = 1, oct do
                local s = f / pi2
                val = val + amp * love.math.noise(cx*s, sx*s, cy*s, sy*s)
                max_amp = max_amp + amp
                amp = amp * pers
                f   = f * 2
            end

            val = val / max_amp
            imgdata:setPixel(px, py, val, val, val, 1)
        end
    end

    return imgdata
end

return FogService
