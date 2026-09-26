-- Named external frames are read-only geometry sources. No foreign hooks/mutation.
local _,ns=...
local X={cache={},names={},wanted={},layoutWanted={},watchers={},owned=setmetatable({},{__mode="k"}),generation=0,cursor=1,limit=32}
ns.ExternalFrames=X
local V=ns.GraphValues
local function secret(v) return V.IsSecret(v) end
local function global(name)
    local ok,value=pcall(function()return _G[name]end)
    if not ok or secret(value) then return false end
    return true,value
end
local function identity(name,frame)
    local current,state=ns.FrameLibrary:Resolve(name)
    local ok=state=="resolved"
    return ok and current==frame
end
local function finite(v,low,high)
    return not secret(v) and type(v)=="number" and v==v and v~=math.huge and v~=-math.huge and v>=low and v<=high
end
local function read(object,method,...)
    if secret(object) then return false end
    local args={...}
    return pcall(function()
        local fn=object and object[method]
        if secret(fn) or type(fn)~="function" then error("Accessor unavailable") end
        return fn(object,unpack(args))
    end)
end
function X:ValidateName(name)
    return not secret(name) and type(name)=="string" and #name>0 and #name<=128 and name:match("^[A-Za-z_][A-Za-z0-9_]*$")~=nil
end
function X:MarkOwned(frame) if not secret(frame) and frame~=nil then self.owned[frame]=true end end
function X:IsOwned(frame)
    if secret(frame) then return true end
    local current=frame
    for _=1,16 do
        if not current or current==UIParent then return false end
        if self.owned[current] then return true end
        local ok,parent=read(current,"GetParent")
        if not ok or secret(parent) then return true end
        current=parent
    end
    return true
end
local function viewport()
    local a,s=read(UIParent,"GetEffectiveScale");local b,w=read(UIParent,"GetWidth");local c,h=read(UIParent,"GetHeight")
    if a and b and c and finite(s,.01,100) and finite(w,1,100000) and finite(h,1,100000) then return {scale=s,width=w,height=h} end
end
function X:ValidateReference(name) return ns.FrameLibrary:ValidateReference(name) end
function X:Inspect(frame,screen,reference,anonymous)
    if secret(frame) then return {state="restricted"} end
    if frame==nil then return {state="missing"} end
    local ok,access=read(frame,"CanBeAccessedInContext")
    if not ok or secret(access) or access~=true then return {state="restricted"} end
    local safe,forbidden=read(frame,"IsForbidden")
    if not safe or secret(forbidden) or forbidden~=false then return {state="restricted"} end
    local typed,isFrame=read(frame,"IsObjectType","Frame")
    if not typed or secret(isFrame) or isFrame~=true then return {state="invalid"} end
    local named,name=read(frame,"GetName")
    if not named or secret(name) then return {state="restricted"} end
    name=reference or name
    if frame==UIParent or self:IsOwned(frame) then return {state="invalid"} end
    if not anonymous and (not self:ValidateReference(name) or not identity(name,frame)) then return {state="invalid"} end
    local shown,visible=read(frame,"IsVisible")
    if not shown or secret(visible) or type(visible)~="boolean" then return {name=name,state="restricted"} end
    if not visible then return {name=name,state="hidden"} end
    local rectOK,left,bottom,width,height=read(frame,"GetRect")
    local scaleOK,scale=read(frame,"GetEffectiveScale")
    screen=screen or viewport()
    if not rectOK or not scaleOK or not screen or not finite(left,-1000000,1000000) or not finite(bottom,-1000000,1000000)
        or not finite(width,.001,100000) or not finite(height,.001,100000) or not finite(scale,.01,100) then return {name=name,state="restricted"} end
    local ratio=scale/screen.scale
    local rect={x=(left+width/2)*ratio-screen.width/2,y=(bottom+height/2)*ratio-screen.height/2,width=width*ratio,height=height*ratio}
    for _,key in ipairs({"x","y","width","height"}) do if not finite(rect[key],-10000,10000) then return {name=name,state="invalid"} end end
    if name and self:ValidateReference(name) and not identity(name,frame) then return {name=name,state="pending"} end
    return {name=name,state="ready",rect=rect}
end
function X:Probe(name,screen)
    if not self:ValidateReference(name) then return {state="invalid"} end
    local frame,state=ns.FrameLibrary:Resolve(name)
    if state~="resolved" then return {name=name,state=state} end
    local entry=ns.FrameLibrary:Lookup(name)
    if entry and entry.objectType then
        local ok,kind=read(frame,"GetObjectType")
        if not ok or secret(kind) then return {name=name,state="restricted"} end
        if kind~=entry.objectType then return {name=name,state="invalid"} end
    end
    local result=self:Inspect(frame,screen,name)
    if result.state=="ready" or result.state=="hidden" then result.identity=frame end
    result.name=name;return result
end
function X:Snapshot(name)
    if not self:ValidateReference(name) then return {state="invalid"} end
    return self.cache[name] or {name=name,state="pending"}
end
-- Build paths from native parent keys, never from debug strings or child indices.
function X:Reference(frame)
    local current=frame;local parts={};local seen={}
    for _=1,8 do
        if not current or secret(current) or seen[current] or current==UIParent or self:IsOwned(current) then return end
        seen[current]=true
        local safe,access=read(current,"CanBeAccessedInContext")
        local forbiddenOK,forbidden=read(current,"IsForbidden")
        if not safe or secret(access) or access~=true or not forbiddenOK or secret(forbidden) or forbidden~=false then return end
        local ok,name=read(current,"GetName")
        if ok and self:ValidateName(name) and identity(name,current) then
            local ref=name
            for i=#parts,1,-1 do ref=ref.."."..parts[i] end
            if self:ValidateReference(ref) and identity(ref,frame) then return ref end
            return
        end
        local pk,key=read(current,"GetParentKey");local pp,parent=read(current,"GetParent")
        if not pk or not self:ValidateName(key) or not pp or secret(parent) or not parent then return end
        local fieldOK,child=pcall(function()return parent[key]end)
        if not fieldOK or secret(child) or child~=current then return end
        parts[#parts+1]=key;current=parent
    end
end
function X:Describe(frame)
    if secret(frame) or not frame or self:IsOwned(frame) or frame==UIParent or frame==WorldFrame then return end
    local ok,access=read(frame,"CanBeAccessedInContext");local safe,forbidden=read(frame,"IsForbidden")
    if not ok or secret(access) or access~=true or not safe or secret(forbidden) or forbidden~=false then return end
    local ref=self:Reference(frame)
    local named,name=read(frame,"GetName");if not named or secret(name) or type(name)~="string" or #name>256 then name=nil end
    local typed,kind=read(frame,"GetObjectType");if not typed or secret(kind) or type(kind)~="string" or #kind>40 then kind="Frame" end
    local sample=self:Inspect(frame,nil,ref,true)
    local isFrameOK,isFrame=read(frame,"IsObjectType","Frame")
    local persistable=ref~=nil and isFrameOK and not secret(isFrame) and isFrame==true and (sample.state=="ready" or sample.state=="hidden")
    local pOK,parent=read(frame,"GetParent");local parentName
    if pOK and not secret(parent) and parent then
        local nameOK,value=read(parent,"GetName")
        if nameOK and not secret(value) and type(value)=="string" and #value<=256 then parentName=value end
    end
    return {frame=frame,reference=ref,name=name or "Unnamed "..kind,label=ref or name or "Unnamed "..kind,
        objectType=kind,parentName=parentName,state=sample.state,rect=sample.rect,persistable=persistable==true}
end
local function accessibleList(list)
    if secret(list) or type(list)~="table" then return false end
    if canaccesstable then local ok,v=pcall(canaccesstable,list);if not ok or secret(v) or v~=true then return false end end
    if issecrettable then local ok,v=pcall(issecrettable,list);if not ok or secret(v) or v~=false then return false end end
    return true
end
function X:Candidates()
    local ok,list=pcall(function()return C_System.GetFrameStack()end)
    local source="stack"
    if not ok or not accessibleList(list) then
        source="focus_only";ok,list=pcall(function()return GetMouseFoci()end)
    end
    if not ok or not accessibleList(list) then return {},"unavailable" end
    local out,seen={},{}
    for index=1,256 do
        local valid,frame=pcall(function()return list[index]end)
        if not valid or secret(frame) then frame=false
        elseif frame==nil then break end
        for _=1,8 do
            if not frame or secret(frame) or seen[frame] then break end
            seen[frame]=true
            local sample=self:Describe(frame)
            if sample then out[#out+1]=sample;if #out>=64 then return out,source end end
            local parentOK,parent=read(frame,"GetParent")
            if not parentOK or secret(parent) then break end
            frame=parent
        end
    end
    return out,source
end
local function namesFrom(nodes,roots)
    local wanted,seen={},{}
    local function visit(id)
        if type(id)~="string" or seen[id] then return end;seen[id]=true
        local name=id:match("^frame:(.*)$")
        if name then wanted[name]=true;return end
        local n=nodes[id];if type(n)~="table" then return end
        visit(n.link and n.link.target);visit(n.widthTarget);visit(n.heightTarget)
    end
    for id in pairs(roots or nodes) do visit(id) end
    local names={};for name in pairs(wanted) do names[#names+1]=name end;table.sort(names)
    return names,wanted
end
function X:CanReference(name,nodes)
    if not self:ValidateReference(name) then return false end
    local names,wanted=namesFrom(nodes or ns.Layout:Nodes())
    return wanted[name]==true or #names<self.limit
end
function X:Targets(nodes)
    local result,seen={},{}
    for _,e in ipairs(ns.FrameLibrary:List()) do
        result[#result+1]={value="frame:"..e.reference,label=e.label.." ("..self:State(e.reference)..")"};seen[e.reference]=true
    end
    for _,name in ipairs(namesFrom(nodes or ns.Layout:Nodes())) do
        if not seen[name] then result[#result+1]={value="frame:"..name,label=name.." ("..self:State(name)..")"} end
    end
    return result
end
function X:State(name)
    if not self:ValidateReference(name) then return "invalid" end
    return self.cache[name] and self.cache[name].state or "pending"
end
function X:Resolve(name)
    if not self:ValidateReference(name) then return nil end
    local entry=self.cache[name]
    return entry and (entry.state=="ready" or entry.state=="hidden") and entry.rect or nil
end
function X:Allows(id,nodes,memo,visiting)
    memo=memo or {};visiting=visiting or {}
    if memo[id]~=nil then return memo[id] end
    if visiting[id] then return false end;visiting[id]=true
    local name=type(id)=="string" and id:match("^frame:(.*)$")
    local n=nodes[id];local allowed
    if name then allowed=self:State(name)=="ready"
    elseif n and n.link then allowed=self:Allows(n.link.target,nodes,memo,visiting)
    else allowed=true end
    visiting[id]=nil;memo[id]=allowed;return allowed
end
local function same(a,b)
    if not a or a.state~=b.state or a.identity~=b.identity then return false end
    if not a.rect or not b.rect then return a.rect==b.rect end
    for _,k in ipairs({"x","y","width","height"}) do if a.rect[k]~=b.rect[k] then return false end end
    return true
end
function X:NotifySample(name,sample,old)
    local notify={}
    for owner,watch in pairs(self.watchers) do if watch.refs[name] then notify[#notify+1]={owner=owner,watch=watch} end end
    for _,item in ipairs(notify) do
        if self.watchers[item.owner]==item.watch then ns:Call("frame/watch",item.watch.callback,name,sample,old) end
    end
end
function X:Poll()
    local names=self.names;local count=#names;if count==0 then return end
    local screen=viewport();local changed=false
    local clock=type(debugprofilestop)=="function" and debugprofilestop
    local started=clock and clock()
    for index=1,math.min(8,count) do
        if self.cursor>count then self.cursor=1 end
        local name=names[self.cursor];self.cursor=self.cursor+1
        local sample=self:Probe(name,screen);local old=self.cache[name]
        if not old or sample.identity~=old.identity then
            self.bindingNext=(self.bindingNext or 0)+1;sample.binding=self.bindingNext
        else sample.binding=old.binding end
        if sample.state=="hidden" and old then sample.rect=old.rect end
        if not same(old,sample) then
            self.cache[name]=sample;changed=true
            self:NotifySample(name,sample,old)
        end
        if self.names~=names then break end
        if clock and index>=1 and clock()-started>=.35 then break end
    end
    if changed then ns.Layout:Notify() end
end
function X:Start()
    if self.timer or #self.names==0 or not (C_Timer and C_Timer.NewTicker) then return end
    local generation=self.generation
    self.timer=C_Timer.NewTicker(.05,function()
        if generation~=self.generation then return end
        local ok=ns:Call("layout/external",function()self:Poll()end)
        if not ok then self:Stop() end
    end)
    for _,event in ipairs({"ADDON_LOADED","UI_SCALE_CHANGED","DISPLAY_SIZE_CHANGED"}) do
        ns.Events:Subscribe(self,event,function()self.cursor=1 end)
    end
    ns.Events:Subscribe(self,"PLAYER_LOGOUT",function()self:Stop()end)
end
function X:RebuildDemand()
    local wanted={};for name in pairs(self.layoutWanted) do wanted[name]=true end
    for _,watch in pairs(self.watchers) do for name in pairs(watch.refs) do wanted[name]=true end end
    local names={};for name in pairs(wanted) do names[#names+1]=name end;table.sort(names)
    local active,changes={},{}
    for index,name in ipairs(names) do
        local old=self.cache[name]
        if index<=self.limit then
            active[#active+1]=name
            if not self.cache[name] or self.cache[name].state=="limit" then self.cache[name]={name=name,state="pending"} end
        else self.cache[name]={name=name,state="limit"} end
        local new=self.cache[name]
        if old and old.state~=new.state then changes[#changes+1]={name=name,sample=new,old=old} end
    end
    for name in pairs(self.cache) do if not wanted[name] then self.cache[name]=nil end end
    self.names=active;self.wanted=wanted
    if #active==0 then
        if self.timer then self.timer:Cancel();self.timer=nil end
        self.generation=self.generation+1;ns.Events:Release(self);self.cursor=1
    else self:Start() end
    for _,change in ipairs(changes) do
        if self.cache[change.name]==change.sample then self:NotifySample(change.name,change.sample,change.old) end
    end
end
function X:Watch(owner,refs,callback)
    assert(owner and type(refs)=="table" and type(callback)=="function","Invalid frame observer")
    local copy={}
    local n=0
    for name,enabled in pairs(refs) do
        if enabled then n=n+1;assert(n<=4096 and self:ValidateReference(name),"Invalid frame observer reference");copy[name]=true end
    end
    self.watchers[owner]={refs=copy,callback=callback};self:RebuildDemand()
end
function X:Unwatch(owner) self.watchers[owner]=nil;self:RebuildDemand() end
function X:SyncDemand(nodes,elements,editing)
    local roots={}
    for id,def in pairs(elements) do if editing or not def.enabled or def.enabled() then roots[id]=true end end
    local _,wanted=namesFrom(nodes,roots);self.layoutWanted=wanted;self:RebuildDemand()
end
function X:Stop()
    if not self.timer and not next(self.cache) and #self.names==0 and not next(self.watchers) then return end
    self.generation=self.generation+1
    if self.timer then self.timer:Cancel();self.timer=nil end
    ns.Events:Release(self);self.cache={};self.names={};self.wanted={};self.layoutWanted={};self.watchers={};self.cursor=1
    ns.Layout.availability=nil;ns.Layout.appliedAvailability={}
end
ns.Layout:RegisterProvider("frame",{resolve=function(name)return X:Resolve(name)end})
ns.Settings:BeforeProfileChange(X,function()X:Stop()end)
