-- Texture catalog only: never resolves spell/item IDs or requests server data.
local _,ns=...
local Catalog={}; Catalog.__index=Catalog; ns.IconCatalogModel=Catalog
local LIMIT=100000
function Catalog.New(api)
    return setmetatable({api=api,owners={}},Catalog)
end
function Catalog:Secret(value) return self.api.issecretvalue and self.api.issecretvalue(value) end
function Catalog:Reference(value)
    if self:Secret(value) then return end
    if type(value)=="number" then
        if value>0 and value<2147483648 and value==math.floor(value) then return value,"id:"..value,"File ID "..value end
    elseif type(value)=="string" and #value>0 and #value<=260 and not value:find("[%c|]") then
        local numeric=tonumber(value); if numeric then return self:Reference(numeric) end
        local path=value:gsub("/","\\")
        if not path:find("\\",1,true) then path="Interface\\Icons\\"..path end
        if path:lower():sub(1,16)~="interface\\icons\\" or path:find("..",1,true) then return end
        local key=path:lower():gsub("%.blp$",""):gsub("%.tga$","")
        return path,"path:"..key,path:match("([^\\]+)$")
    end
end
function Catalog:Identity()
    local version,build,_,interface=self.api.GetBuildInfo()
    return table.concat({tostring(self.api.WOW_PROJECT_ID),tostring(version),tostring(build),tostring(interface),self.api.GetLocale()},"|")
end
function Catalog:Stop()
    if self.timer then self.timer:Cancel(); self.timer=nil end
    self.job=nil
end
function Catalog:Open(owner)
    self.owners[owner]=true
    local ok=pcall(function()
        local identity=self:Identity()
        if self.identity~=identity then self:Stop(); self.entries=nil; self.byKey=nil; self.failure=nil; self.searchCache=nil; self.identity=identity end
        self:Start()
    end)
    if not ok then self:Stop(); self.failure="Icon catalog could not be opened. No item or spell fallback is used." end
end
function Catalog:Close(owner)
    self.owners[owner]=nil
    if not next(self.owners) then self:Stop(); self.failure=nil; self.searchCache=nil end
end
function Catalog:Start()
    if self.entries or self.job or self.failure then return end
    local sources={}
    for _,name in ipairs({"GetMacroIcons","GetMacroItemIcons","GetLooseMacroIcons","GetLooseMacroItemIcons"}) do
        if type(self.api[name])=="function" then sources[#sources+1]=name end
    end
    if #sources==0 or not (self.api.C_Timer and self.api.C_Timer.NewTicker) then
        self.failure="This client exposes no supported icon-list API."; return
    end
    self.job={sources=sources,source=1,entries={},byKey={},position=1,skipped=0,warnings=0,visited=0}
    self.timer=self.api.C_Timer.NewTicker(.016,function()
        local ok=pcall(self.Tick,self)
        if not ok then self:Stop(); self.failure="Icon-list processing failed. Close and reopen to retry." end
    end)
end
function Catalog:Tick()
    local j=self.job; if not j then return end
    if self.api.GetTime then
        local frame=self.api.GetTime(); if j.lastFrame==frame then return end; j.lastFrame=frame
    end
    if self.api.InCombatLockdown and self.api.InCombatLockdown() then j.paused=true; return end
    j.paused=false
    if not j.raw then
        local source=j.sources[j.source]
        if not source then
            if #j.entries==0 then self.failure="No readable icons returned by this client."; self:Stop(); return end
            self.entries=j.entries; self.byKey=j.byKey; self.warnings=j.warnings; self.skipped=j.skipped; self:Stop(); return
        end
        -- Native enumeration itself is synchronous; at most one list call per tick.
        local raw={}; local ok=pcall(self.api[source],raw)
        if not ok then j.warnings=j.warnings+1; j.source=j.source+1; return end
        j.raw=raw; j.position=1; return
    end
    local start=self.api.debugprofilestop and self.api.debugprofilestop()
    for _=1,128 do
        local value=j.raw[j.position]
        if not self:Secret(value) and value==nil then j.raw=nil; j.source=j.source+1; return end
        j.position=j.position+1; j.visited=j.visited+1
        if j.visited>LIMIT then self:Stop(); self.failure="Icon list exceeded the safety limit; catalog not published."; return end
        local texture,key,label=self:Reference(value)
        if texture and not j.byKey[key] then
            local filename
            local query=self.api.C_Texture and self.api.C_Texture.GetFilenameFromFileDataID
            if type(texture)=="number" and type(query)=="function" then
                local ok,result=pcall(query,texture)
                if ok and not self:Secret(result) and type(result)=="string" and #result>0 and #result<=260 and not result:find("[%c|]") then
                    filename=result:gsub("/","\\"); label=filename:match("([^\\]+)$") or label
                end
            end
            local entry={kind="icon",texture=texture,key=key,label=label,filename=filename,
                search=(tostring(texture)..(filename and (" "..filename) or "")):lower()}
            j.entries[#j.entries+1]=entry; j.byKey[key]=entry
        elseif not texture then j.skipped=j.skipped+1 end
        if start and self.api.debugprofilestop()-start>=2 then break end
    end
end
function Catalog:Status()
    if self.entries then return {ready=true,state="ready",count=#self.entries,message=#self.entries.." unique client icons"..((self.warnings or 0)>0 and " (some icon sources unavailable)" or "")} end
    if self.failure then return {ready=false,state="failed",message=self.failure} end
    local j=self.job
    return {ready=false,state=j and (j.paused and "paused" or "building") or "idle",
        message=j and (j.paused and "Catalog paused during combat." or "Preparing icon gallery: "..#j.entries.." icons") or "Open the gallery to load icons."}
end
function Catalog:Search(query)
    if not self.entries then return {} end
    query=(query or ""):sub(1,100):match("^%s*(.-)%s*$"):lower():gsub("/","\\")
    if query=="" then return self.entries end
    if self.searchCache and self.searchCache.query==query then return self.searchCache.rows end
    local tiers={{},{},{}}
    for _,entry in ipairs(self.entries) do
        local name=entry.label:lower(); local key=entry.search; local position=key:find(query,1,true) or name:find(query,1,true)
        if position then
            local rank=(tostring(entry.texture):lower()==query or name==query) and 1 or (key:sub(1,#query)==query or name:sub(1,#query)==query) and 2 or 3
            local bucket=tiers[rank]; bucket[#bucket+1]=entry
        end
    end
    local rows={}; for _,bucket in ipairs(tiers) do for _,entry in ipairs(bucket) do rows[#rows+1]=entry end end
    self.searchCache={query=query,rows=rows}; return rows
end
function Catalog:Find(reference)
    local _,key=self:Reference(reference)
    return key and self.byKey and self.byKey[key]
end
ns.IconCatalog=Catalog.New(_G)
