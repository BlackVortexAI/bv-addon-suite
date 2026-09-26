local _, ns = ...
local Events = { buckets = {} }
ns.Events = Events

-- Nonvisual transport frame: the sole CreateFrame exception outside UI/.
local frame = CreateFrame("Frame")
Events.frame = frame

local function compact(event, bucket)
    if bucket.depth > 0 then return end
    local items, write = bucket.items, 1
    for read = 1, #items do
        if items[read].active then
            items[write] = items[read]
            write = write + 1
        end
    end
    for index = #items, write, -1 do items[index] = nil end
    bucket.dirty = false
    if #items == 0 then
        frame:UnregisterEvent(event)
        Events.buckets[event] = nil
    end
end

function Events:Subscribe(owner, event, callback)
    assert(owner ~= nil and type(event) == "string" and type(callback) == "function", "Invalid subscription")
    local bucket = self.buckets[event]
    if not bucket then
        -- Register first; invalid client events must not leave phantom subscriptions.
        frame:RegisterEvent(event)
        bucket = { items = {}, depth = 0 }
        self.buckets[event] = bucket
    end
    local entry = { owner = owner, callback = callback, active = true }
    bucket.items[#bucket.items + 1] = entry
    return function()
        if not entry.active then return end
        entry.active = false
        bucket.dirty = true
        compact(event, bucket)
    end
end

function Events:Release(owner)
    for event, bucket in pairs(self.buckets) do
        for _, entry in ipairs(bucket.items) do
            if entry.owner == owner then entry.active = false; bucket.dirty = true end
        end
        if bucket.dirty then compact(event, bucket) end
    end
end

function Events:Count()
    local events, subscribers = 0, 0
    for _, bucket in pairs(self.buckets) do
        events = events + 1
        for _, entry in ipairs(bucket.items) do
            if entry.active then subscribers = subscribers + 1 end
        end
    end
    return events, subscribers
end

frame:SetScript("OnEvent", function(_, event, ...)
    local bucket = Events.buckets[event]
    if not bucket then return end
    bucket.depth = bucket.depth + 1
    -- New listeners are deferred to the next dispatch; removed listeners are skipped.
    local count = #bucket.items
    for index = 1, count do
        local entry = bucket.items[index]
        if entry.active then
            local ok = ns:Call(event, entry.callback, event, ...)
            if not ok then
                entry.active = false
                bucket.dirty = true
                if ns.Modules then ns.Modules:Fault(entry.owner) end
            end
        end
    end
    bucket.depth = bucket.depth - 1
    if bucket.dirty then compact(event, bucket) end
end)
