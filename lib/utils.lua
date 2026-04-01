-- lib/utils.lua
-- Generic utility functions with no domain knowledge.

local Utils = {}

-- Recursive deep-copy of a table.
function Utils.deepCopy(t)
    if type(t) ~= "table" then return t end
    local copy = {}
    for k, v in pairs(t) do
        copy[k] = Utils.deepCopy(v)
    end
    return copy
end

return Utils
