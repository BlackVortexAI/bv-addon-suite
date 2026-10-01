local addonName, ns = ...

ns.name = addonName
ns.version = "0.8.90"
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
-- Dotted numeric versions ("0.8.89" < "0.8.100"): -1, 0 or 1.
function ns.CompareVersions(a,b)
    local x,y={},{}
    for part in tostring(a or ""):gmatch("%d+") do x[#x+1]=tonumber(part) end
    for part in tostring(b or ""):gmatch("%d+") do y[#y+1]=tonumber(part) end
    for i=1,math.max(#x,#y) do
        local p,q=x[i] or 0,y[i] or 0
        if p~=q then return p<q and -1 or 1 end
    end
    return 0
end
-- Packages are versioned on their own (since 0.8.89). A package loads when its
-- files match its own TOC version, the Core files match the Core TOC, Core
-- offers the interface generation the package was built for (api) and Core is
-- at least `minimum`. Otherwise it stays off with one message; saved data is
-- never touched.
function ns:RequireCore(package,own,minimum,api)
    local query=C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    local function version(name)
        if type(query)~="function" then return end
        local ok,value=pcall(query,name,"Version")
        if ok and type(value)=="string" then return value end
    end
    local core,feature=version(self.name),version(package)
    local problem
    if core~=self.version then
        problem="the Core files ("..tostring(self.version)..") do not match the installed Core ("..tostring(core or "missing").."). Reinstall BV Addon Suite - Core."
    elseif feature~=own then
        problem="its files ("..tostring(own)..") do not match its installed version ("..tostring(feature or "missing").."). Reinstall "..package.."."
    elseif api~=self.apiVersion then
        problem=(type(api)=="number" and api<self.apiVersion) and "it was made for an older Core. Update "..package.."."
            or "it needs a newer BV Addon Suite - Core. Update Core."
    elseif self.CompareVersions(self.version,minimum)<0 then
        problem="it needs BV Addon Suite - Core "..tostring(minimum).." or newer (installed: "..tostring(self.version).."). Update Core."
    end
    if not problem then return true end
    self.releaseWarnings=self.releaseWarnings or {}
    if not self.releaseWarnings[package] then
        self.releaseWarnings[package]=true
        self:Print(package.." "..tostring(feature or own).." is off: "..problem.." Saved data is preserved.")
    end
    return false
end
