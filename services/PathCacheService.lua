-- services/PathCacheService.lua
-- LRU path result cache keyed by "sx,sy>ex,ey".
-- Vehicles read paths via path_i and never mutate the array, so sharing
-- cached table references across vehicles is safe.

local PathCacheService = {}

local MAX_ENTRIES = 800

-- Doubly-linked list node pool for O(1) LRU tracking.
-- Sentinel head (most-recent) and tail (least-recent).
local _head = {}   -- most recently used
local _tail = {}   -- least recently used
_head.next = _tail
_tail.prev = _head

local _map = {}    -- key → node { key, path, prev, next }
local _count = 0

local function _unlink(node)
    node.prev.next = node.next
    node.next.prev = node.prev
end

local function _push_front(node)
    node.next = _head.next
    node.prev = _head
    _head.next.prev = node
    _head.next = node
end

function PathCacheService.get(sx, sy, ex, ey)
    local key = sx .. "," .. sy .. ">" .. ex .. "," .. ey
    local node = _map[key]
    if not node then return nil end
    -- Move to front (most recently used)
    _unlink(node)
    _push_front(node)
    return node.path
end

function PathCacheService.put(sx, sy, ex, ey, path)
    local key = sx .. "," .. sy .. ">" .. ex .. "," .. ey
    if _map[key] then
        -- Update existing entry and move to front
        local node = _map[key]
        node.path = path
        _unlink(node)
        _push_front(node)
        return
    end
    if _count >= MAX_ENTRIES then
        -- Evict least recently used (tail.prev)
        local lru = _tail.prev
        _unlink(lru)
        _map[lru.key] = nil
        _count = _count - 1
    end
    local node = { key = key, path = path }
    _push_front(node)
    _map[key] = node
    _count = _count + 1
end

function PathCacheService.invalidate()
    _head = {}
    _tail = {}
    _head.next = _tail
    _tail.prev = _head
    _map = {}
    _count = 0
end

return PathCacheService
