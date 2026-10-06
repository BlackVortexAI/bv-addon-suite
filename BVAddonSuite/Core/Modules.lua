local _, ns = ...
local Modules = { records = {}, order = {} }
ns.Modules = Modules

local function release(record)
    ns.Events:Release(record)
    for index = #record.cleanup, 1, -1 do
        ns:Call(record.id .. "/cleanup", record.cleanup[index])
        record.cleanup[index] = nil
    end
end

function Modules:Register(definition)
    assert(type(definition) == "table" and type(definition.id) == "string", "Module requires an id")
    assert(definition.id:match("^[a-z][a-z0-9_]*$") and not self.records[definition.id], "Invalid or duplicate module id")
    assert(type(definition.OnEnable) == "function", "Module requires OnEnable")
    local record = { id = definition.id, definition = definition, state = "disabled", cleanup = {} }
    local context = {}
    function context:Subscribe(event, callback)
        assert(record.state == "enabling" or record.state == "enabled", "Module is not enabled")
        return ns.Events:Subscribe(record, event, callback)
    end
    function context:Defer(callback)
        assert(record.state == "enabling" or record.state == "enabled", "Module is not enabled")
        assert(type(callback) == "function", "Cleanup must be callable")
        record.cleanup[#record.cleanup + 1] = callback
    end
    function context:Settings() return ns.Settings:Module(record.id) end
    context.UI = ns.UI -- UI library is loaded before feature files in the TOC.
    record.context = context
    self.records[record.id] = record
    self.order[#self.order + 1] = record
    return record
end

function Modules:Stop(record, faulted)
    if record.state == "disabling" then return end
    local active = record.state == "enabled" or record.state == "enabling"
    record.state = "disabling"
    ns.Events:Release(record)
    local ok = true
    if active and record.definition.OnDisable then
        ok = ns:Call(record.id .. "/disable", record.definition.OnDisable, record.context)
    end
    release(record)
    record.state = (faulted or not ok) and "faulted" or "disabled"
end

function Modules:Fault(record)
    if type(record) == "table" and self.records[record.id] == record then self:Stop(record, true) end
end

function Modules:Start(record)
    if record.state == "enabled" or record.state == "faulted" then return end
    record.state = "enabling"
    local ok = ns:Call(record.id .. "/enable", record.definition.OnEnable, record.context)
    if ok and record.state == "enabling" then record.state = "enabled"
    elseif not ok then self:Fault(record) end
end

function Modules:SetEnabled(id, enabled)
    local record = assert(self.records[id], "Unknown module")
    assert(type(enabled) == "boolean", "Enabled must be boolean")
    ns.Settings:Module(id).enabled = enabled
    if enabled then
        -- Explicit user retry is allowed after a fault; no automatic retry loop.
        if record.state == "faulted" then record.state = "disabled" end
        self:Start(record)
    else
        self:Stop(record)
        if ns.Tutorial then ns.Tutorial:Recheck() end
    end
end

function Modules:Reconcile()
    for _, record in ipairs(self.order) do
        local enabled = ns.Settings:Module(record.id).enabled == true
        if enabled then self:Start(record) else self:Stop(record) end
    end
end

function Modules:StopAll()
    for index = #self.order, 1, -1 do self:Stop(self.order[index]) end
end
