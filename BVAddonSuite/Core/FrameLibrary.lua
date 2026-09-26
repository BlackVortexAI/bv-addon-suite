-- Account-wide descriptive references only. Never persist a live Frame or execute a path.
local _,ns=...
local F={limit=128};ns.FrameLibrary=F
local V=ns.GraphValues
local function plain(t)
    if V.IsSecret(t) or type(t)~="table" then return false end
    if canaccesstable then local ok,v=pcall(canaccesstable,t);if not ok or V.IsSecret(v) or v~=true then return false end end
    if issecrettable then local ok,v=pcall(issecrettable,t);if not ok or V.IsSecret(v) or v~=false then return false end end
    return getmetatable(t)==nil
end
function F:ValidateReference(ref)
    if V.IsSecret(ref) or type(ref)~="string" or #ref==0 or #ref>256 then return false end
    local count=0
    for part in ref:gmatch("[^.]+") do
        count=count+1
        if count>8 or #part>128 or not part:match("^[A-Za-z_][A-Za-z0-9_]*$") then return false end
    end
    return count>0 and not ref:find("..",1,true) and ref:sub(1,1)~="." and ref:sub(-1)~="."
end
function F:ValidLabel(label)
    return not V.IsSecret(label) and type(label)=="string" and #label>0 and #label<=96 and not label:find("[%c|]")
end
function F:ValidEntry(e)
    if not plain(e) then return false end
    for k in pairs(e) do if k~="reference" and k~="label" and k~="objectType" then return false end end
    return self:ValidateReference(e.reference) and self:ValidLabel(e.label)
        and (e.objectType==nil or type(e.objectType)=="string" and not V.IsSecret(e.objectType) and #e.objectType<=40 and e.objectType:match("^[A-Za-z]+$"))
end
function F:Store()
    local db=ns.Settings.db
    if not db then return nil,"Settings unavailable" end
    if db.frameLibrary==nil then db.frameLibrary={version=1,entries={}} end
    local store=db.frameLibrary
    if not plain(store) or store.version~=1 or not plain(store.entries) then return nil,"Unsupported frame library; saved data retained" end
    return store
end
function F:Lookup(ref)
    if not self:ValidateReference(ref) then return end
    local s=self:Store();local e=s and s.entries[ref]
    return self:ValidEntry(e) and e.reference==ref and {reference=ref,label=e.label,objectType=e.objectType} or nil
end
function F:List()
    local out={};local s=self:Store();if not s then return out end
    local count=0
    for ref in pairs(s.entries) do
        count=count+1;if count>self.limit then break end
        local e=self:Lookup(ref);if e then out[#out+1]=e end
    end
    table.sort(out,function(a,b)if a.label==b.label then return a.reference<b.reference end;return a.label<b.label end)
    return out
end
function F:Options()
    local out={}
    for _,e in ipairs(self:List()) do out[#out+1]={value=e.reference,label=e.label.." — "..e.reference} end
    return out
end
-- Transaction preparation is shared by capture and graph import. Existing labels win.
function F:Prepare(entries)
    local s,why=self:Store();if not s then return nil,why end
    if not plain(entries) then return nil,"Invalid frame entries" end
    local result,n,seen={},0,0
    for ref,e in pairs(s.entries) do
        n=n+1;if n>self.limit or not self:ValidEntry(e) or ref~=e.reference then return nil,"Invalid or full frame library; data retained" end
        result[ref]={reference=ref,label=e.label,objectType=e.objectType}
    end
    for ref,e in pairs(entries) do
        seen=seen+1;if seen>self.limit or not self:ValidEntry(e) or ref~=e.reference then return nil,"Invalid imported frame reference" end
        if not result[ref] then
            n=n+1;if n>self.limit then return nil,"Frame library limit reached (128)" end
            result[ref]={reference=ref,label=e.label,objectType=e.objectType}
        elseif result[ref].objectType and e.objectType and result[ref].objectType~=e.objectType then
            return nil,"Frame type conflict: "..ref
        end
    end
    return {version=1,entries=result}
end
function F:Save(ref,label,objectType)
    local e={reference=ref,label=label or ref,objectType=objectType}
    if not self:ValidEntry(e) then return nil,"Invalid frame description" end
    local prepared,why=self:Prepare({[ref]=e});if not prepared then return nil,why end
    ns.Settings.db.frameLibrary=prepared
    return self:Lookup(ref)
end
function F:Rename(ref,label)
    if not self:ValidLabel(label) then return false,"Use a name of 1–96 bytes without control characters" end
    local e=self:Lookup(ref);if not e then return false,"Frame not in library" end
    local s=self:Store();s.entries[ref]={reference=ref,label=label,objectType=e.objectType};return true
end
function F:Remove(ref)
    local s,why=self:Store();if not s then return false,why end
    if not self:ValidateReference(ref) then return false,"Invalid reference" end
    if self:InUse(ref) then return false,"Frame is referenced by a graph or layout. Remove its references first." end
    s.entries[ref]=nil;return true
end
function F:InUse(ref)
    local target="frame:"..ref
    local function layouts(nodes)
        for _,n in pairs(nodes or {}) do
            if type(n)=="table" and (n.widthTarget==target or n.heightTarget==target or n.link and n.link.target==target) then return true end
        end
    end
    if layouts(ns.Layout and ns.Layout.draft) then return true end
    local db=ns.Settings.db
    for _,profile in pairs(db and db.profiles or {}) do
        if type(profile)=="table" then
            if layouts(profile.layout and profile.layout.elements) then return true end
            local studio=profile.modules and profile.modules.aura_studio
            for _,rec in pairs(studio and studio.graphs or {}) do
                for _,graph in pairs({draft=rec.draft,applied=rec.applied}) do
                    for _,node in pairs(graph.nodes or {}) do
                        if node.type=="frame_state" and node.config and node.config.reference==ref then return true end
                    end
                end
                for _,snapshot in pairs({displayLayout=rec.displayLayout,appliedLayout=rec.appliedLayout}) do
                    if layouts(snapshot.elements) or layouts(snapshot.dependencies) then return true end
                end
            end
        end
    end
    return false
end
function F:Resolve(ref)
    if not self:ValidateReference(ref) then return nil,"invalid" end
    local current=_G
    local root=true
    for part in ref:gmatch("[^.]+") do
        if V.IsSecret(current) then return nil,"restricted" end
        if current==nil then return nil,"missing" end
        if not root then
            local permitted,access,forbidden=pcall(function()
                return current:CanBeAccessedInContext(),current:IsForbidden()
            end)
            if not permitted or V.IsSecret(access) or access~=true or V.IsSecret(forbidden) or forbidden~=false then return nil,"restricted" end
        end
        local ok,value=pcall(function()return current[part]end)
        if not ok or V.IsSecret(value) then return nil,"restricted" end
        current=value
        root=false
    end
    return current,current==nil and "missing" or "resolved"
end
