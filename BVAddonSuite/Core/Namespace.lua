local addonName, ns = ...

ns.name = addonName
ns.version = "0.8.51"
ns.errors = {}
ns.ready = false
-- Shared, versioned extension namespace for the dependent addon packages.
ns.apiVersion = 1
BVAddonSuiteCore = ns

function ns:Report(scope, message)
    local entry = { scope = tostring(scope), message = tostring(message) }
    if #self.errors == 20 then table.remove(self.errors, 1) end
    self.errors[#self.errors + 1] = entry
    -- Respect the client's installed error handler (including BugGrabber).
    local handler = geterrorhandler and geterrorhandler()
    if handler then pcall(handler, self.name .. " [" .. entry.scope .. "]: " .. entry.message) end
end

function ns:Call(scope, callback, ...)
    local ok, result = pcall(callback, ...)
    if not ok then self:Report(scope, result) end
    return ok, result
end

function ns:Print(message,prefix)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage((prefix==false and "" or "|cff20f0a0BV|r ") .. tostring(message)) end
end
function ns:RequireRelease(package,expected)
    local query=C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    local function version(name)
        if type(query)~="function" then return end
        local ok,value=pcall(query,name,"Version")
        if ok and type(value)=="string" then return value end
    end
    local core,feature=version(self.name),version(package)
    if self.apiVersion==1 and expected==self.version and core==self.version and feature==expected then return true end
    self.releaseWarnings=self.releaseWarnings or {}
    if not self.releaseWarnings[package] then
        self.releaseWarnings[package]=true
        self:Print(package.." disabled: release mismatch. Core="..tostring(core or "missing")..", "..package.."="..tostring(feature or "missing")..
            "; required "..expected..". Update all BV packages together. Saved data is preserved.")
    end
    return false
end
