-- views/InformationFeed.lua
-- Bottom-left event log overlay. Entries fade after LIFESPAN seconds.
-- Push entries by subscribing to EventBus events.

local InformationFeed = {}
InformationFeed.__index = InformationFeed

local MAX_ENTRIES    = 6
local LIFESPAN       = 6.0
local FADE_AFTER     = 4.0
local ENTRY_H        = 20
local FEED_X_OFFSET  = 10    -- from sidebar right edge
local FEED_Y_BOTTOM  = 48    -- margin from screen bottom

function InformationFeed:new(game)
    local instance = setmetatable({ entries = {} }, InformationFeed)

    game.EventBus:subscribe("package_delivered", function(data)
        instance:push({
            text  = string.format("+$%d delivered", math.floor(data.payout or 0)),
            color = { 0.3, 1.0, 0.45 },
        })
    end)

    game.EventBus:subscribe("vehicle_stuck", function(data)
        local v = data and data.vehicle
        local label = v and string.format("%s #%d stuck — retrying", v:getIcon(), v.id) or "Vehicle stuck"
        instance:push({ text = label, color = { 1.0, 0.75, 0.2 } })
    end)

    game.EventBus:subscribe("trip_created", function()
        instance:push({ text = "New trip available", color = { 0.6, 0.75, 1.0 } })
    end)

    game.EventBus:subscribe("fuel_consumed", function(data)
        local v = data and data.vehicle
        local label = v
            and string.format("%s #%d fuel -$%.f", v:getIcon(), v.id, data.amount)
            or  string.format("Fuel -$%.f", data.amount)
        instance:push({ text = label, color = { 1.0, 0.5, 0.3 } })
    end)

    return instance
end

function InformationFeed:push(entry)
    entry.timestamp = love.timer.getTime()
    table.insert(self.entries, entry)
    while #self.entries > MAX_ENTRIES do
        table.remove(self.entries, 1)
    end
end

function InformationFeed:update(dt)
    local now = love.timer.getTime()
    for i = #self.entries, 1, -1 do
        if now - self.entries[i].timestamp > LIFESPAN then
            table.remove(self.entries, i)
        end
    end
end

function InformationFeed:draw(game)
    if #self.entries == 0 then return end

    local sh        = love.graphics.getHeight()
    local sidebar_w = game.C.UI.SIDEBAR_WIDTH
    local x         = sidebar_w + FEED_X_OFFSET
    local now       = love.timer.getTime()
    local y         = sh - FEED_Y_BOTTOM - #self.entries * ENTRY_H

    love.graphics.setFont(game.fonts.ui_small)

    for _, entry in ipairs(self.entries) do
        local age   = now - entry.timestamp
        local alpha = age > FADE_AFTER
            and math.max(0, 1 - (age - FADE_AFTER) / (LIFESPAN - FADE_AFTER))
            or  1.0

        local c = entry.color or { 1, 1, 1 }

        -- Drop shadow
        love.graphics.setColor(0, 0, 0, alpha * 0.6)
        love.graphics.print(entry.text, x + 1, y + 1)

        love.graphics.setColor(c[1], c[2], c[3], alpha)
        love.graphics.print(entry.text, x, y)

        y = y + ENTRY_H
    end
end

return InformationFeed
