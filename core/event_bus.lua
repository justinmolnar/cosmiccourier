-- core/event_bus.lua
local EventBus = {
    subscribers = {}
}

function EventBus:subscribe(event, callback)
    if not self.subscribers[event] then
        self.subscribers[event] = {}
    end
    table.insert(self.subscribers[event], callback)
end

function EventBus:publish(event, ...)
    if self.subscribers[event] then
        for _, callback in ipairs(self.subscribers[event]) do
            callback(...)
        end
    end
end

return EventBus