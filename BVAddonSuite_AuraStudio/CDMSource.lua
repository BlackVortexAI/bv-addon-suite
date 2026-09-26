-- Read-only adapter for already existing Blizzard buff viewers. No frame is
-- activated, refreshed, hooked or retained between source captures.
local _,A=...
if A.blocked then return end
local G=A.G
local CDM={};CDM.__index=CDM;A.CDMSource=CDM
function CDM.New(source)return setmetatable({source=source,api=source.api},CDM)end
-- Trace accepts classified constants only. It observes the existing branch;
-- enabling diagnostics neither performs native reads nor changes a decision.
function CDM:Trace(name,status)
    local path=self.tracePath
    if path and not path.reason then path.gates[name]=status end
end
function CDM:TraceReject(reason)
    local path=self.tracePath
    if path and not path.reason then path.reason=reason;path.outcome="rejected" end
end
function CDM:TraceClass(value,ok,kind)
    if ok==false then return "error" end
    if self.source:Secret(value) then return "Secret" end
    if value==nil then return "missing" end
    if kind and type(value)~=kind then return "invalid" end
    return "readable"
end
function CDM:TraceCandidate(entry,id,name)
    self.tracePath=nil;self.previousTracePath=nil
    if not self.trace or not entry.info.ids[id] then return end
    local previous=self.trace[name]
    local path={gates={},outcome="not reached",candidates=(previous.candidates or 0)+1,
        priority=entry.info.spellID==id and 2 or 1,cooldownID=entry.cooldownID}
    for key in pairs(previous.gates) do path.gates[key]="not reached" end
    self.previousTracePath=previous;self.trace[name]=path;self.tracePath=path
end
function CDM:FinishTraceCandidate(name,accepted)
    local path=self.tracePath
    if not path then return end
    if self.previousTracePath and self.previousTracePath.outcome=="accepted" then
        self.previousTracePath.candidates=path.candidates;self.trace[name]=self.previousTracePath
    elseif accepted then path.outcome="accepted";path.reason=nil
    elseif self.previousTracePath and self.previousTracePath.priority and self.previousTracePath.priority>=path.priority then
        self.previousTracePath.candidates=path.candidates;self.trace[name]=self.previousTracePath
    end
    self.previousTracePath=nil
end
function CDM:Read(object,key,call)
    if self.source:Secret(object) then return nil,false end
    local kind=type(object)
    if kind~="table" and kind~="userdata" then return nil,false end
    local ok,value=pcall(function()return object[key]end)
    if not ok then return nil,false end
    if call then
        if self.source:Secret(value) or type(value)~="function" then return nil,false end
        ok,value=pcall(value,object)
    end
    return value,ok
end
function CDM:Accessible(frame)
    local accessible,ok=self:Read(frame,"CanBeAccessedInContext",true)
    if not ok or self.source:Secret(accessible) or accessible~=true then return false end
    local forbidden,valid=self:Read(frame,"IsForbidden",true)
    return valid and not self.source:Secret(forbidden) and forbidden==false
end
function CDM:ID(value)
    local n=self.source:Number(value)
    return n and n>0 and n==math.floor(n) and n or nil
end
function CDM:Bool(value)
    if not self.source:Secret(value) and type(value)=="boolean" then return value end
end
local idFields={"cooldownID","cooldownId","cooldownIDOverride","cdID","cdId"}
function CDM:FrameID(frame)
    local id
    for _,key in ipairs(idFields) do
        local raw,ok=self:Read(frame,key)
        if not ok or self.source:Secret(raw) then return end
        if raw~=nil then
            local candidate=self:ID(raw)
            if not candidate or id and id~=candidate then return end
            id=candidate
        end
    end
    return id
end
function CDM:Info(id)
    if self.infos[id]~=nil then return self.infos[id] or nil end
    self.infos[id]=false
    local fn=self:Read(self.api.C_CooldownViewer,"GetCooldownViewerCooldownInfo")
    if self.source:Secret(fn) or type(fn)~="function" then return end
    local ok,info=pcall(fn,id)
    if not ok or not self.source:ReadableTable(info) then return end
    local ids,count={},0
    local function add(value)
        if self.source:Secret(value) then return false end
        if value==nil then return true end
        local spell=self:ID(value);if not spell then return false end
        if not ids[spell] then ids[spell]=true;count=count+1 end
        return true
    end
    if not add(rawget(info,"spellID")) or not add(rawget(info,"overrideSpellID")) then return end
    local linked=rawget(info,"linkedSpellIDs")
    if self.source:Secret(linked) then return end
    if linked~=nil then
        if not self.source:ReadableTable(linked) then return end
        local complete=false
        for index=1,33 do
            local value=rawget(linked,index)
            if self.source:Secret(value) then return end
            if value==nil then complete=true;break end
            if index==33 or not add(value) then return end
        end
        if not complete then return end
    end
    if count==0 then return end
    local result={ids=ids,count=count,spellID=self:ID(rawget(info,"spellID")),
        overrideSpellID=self:ID(rawget(info,"overrideSpellID")),
        selfAura=self:Bool(rawget(info,"selfAura")),hasAura=self:Bool(rawget(info,"hasAura"))}
    self.infos[id]=result;return result
end
function CDM:ScanViewer(root)
    if not self:Accessible(root) then return end
    local queue,seen={{frame=root,depth=0}},{[root]=true}
    local slots,unique=0,0
    local function enqueue(frame,depth)
        if slots>=128 then return end
        slots=slots+1
        if self.source:Secret(frame) then return end
        local kind=type(frame);if kind~="table" and kind~="userdata" then return end
        if seen[frame] or unique>=64 then return end
        seen[frame]=true;unique=unique+1;queue[#queue+1]={frame=frame,depth=depth}
    end
    local pool=self:Read(root,"itemFramePool")
    local enumerate=self:Read(pool,"EnumerateActive")
    if not self.source:Secret(enumerate) and type(enumerate)=="function" then
        local ok,iter,state,control=pcall(enumerate,pool)
        if ok and not self.source:Secret(iter) and type(iter)=="function"
            and not self.source:Secret(state) and not self.source:Secret(control) then
            for _=1,64 do
                local success,child=pcall(iter,state,control)
                if not success or self.source:Secret(child) or child==nil then break end
                local kind=type(child);if kind~="table" and kind~="userdata" then break end
                control=child;enqueue(child,1)
            end
        end
    end
    local index=1
    while index<=#queue do
        local entry=queue[index];index=index+1
        local frame=entry.frame
        if self:Accessible(frame) then
            local id=self:FrameID(frame)
            if id and not self.seen[frame] then
                self.seen[frame]=true
                local info=self:Info(id)
                if info then self.frames[#self.frames+1]={frame=frame,info=info,viewer=root,cooldownID=id} end
            end
            if entry.depth<4 and slots<128 then
                local children=self:Read(frame,"GetChildren")
                if not self.source:Secret(children) and type(children)=="function" then
                    pcall(function()
                        local function visit(...)
                            for i=1,math.min(select("#",...),64,128-slots) do enqueue(select(i,...),entry.depth+1) end
                        end
                        visit(children(frame))
                    end)
                end
            end
        end
    end
end
function CDM:Snapshot()
    if self.frames then return end
    self.frames,self.infos,self.seen={},{},{}
    self:ScanViewer(self.api.BuffIconCooldownViewer)
    self:ScanViewer(self.api.BuffBarCooldownViewer)
end
function CDM:Activity(frame)
    self.activities=self.activities or {}
    local cached=self.activities[frame]
    if cached then return cached.value,cached.valid end
    local raw,rawRead=self:Read(frame,"isActive")
    local methodRaw,methodRead=self:Read(frame,"IsActive",true)
    if self.tracePath then
        self:Trace("activeField",self:TraceClass(raw,rawRead,"boolean"))
        self:Trace("activeMethod",self:TraceClass(methodRaw,methodRead,"boolean"))
    end
    local active,method=self:Bool(raw),self:Bool(methodRaw)
    local valid=not (active~=nil and method~=nil and active~=method)
    if active==nil then active=method end
    self.activities[frame]={value=active,valid=valid}
    return active,valid
end
-- Target frames have no public per-item target generation. A viewer GUID alone
-- can match again after A -> B -> A while its cached aura still belongs to A's
-- old visit. Re-query the public instance on the current target every capture;
-- never use auraDataCached as target evidence or treat a secret ID as a key.
function CDM:TargetGUID()
    local query=self.api.UnitGUID
    if self.source:Secret(query) or type(query)~="function" then
        if self.tracePath then self:Trace("guid",self:TraceClass(query,true,"function")) end
        return
    end
    local ok,value=pcall(query,"target")
    if self.tracePath then self:Trace("guid",self:TraceClass(value,ok,"string")) end
    if ok and not self.source:Secret(value) and type(value)=="string" and #value>0 and #value<=256 then return value end
    if self.tracePath and self:TraceClass(value,ok,"string")=="readable" then self:Trace("guid","invalid") end
end
function CDM:TargetContextCurrent()
    local guid=self:TargetGUID();local epoch=self.source.cdmTargetEpoch
    if not self.targetContext then self.targetContext={guid=guid,epoch=epoch} end
    return guid~=nil and guid==self.targetContext.guid and epoch==self.targetContext.epoch
end
function CDM:TargetContextChanged()
    return self.targetContext and (self:TargetGUID()~=self.targetContext.guid or self.source.cdmTargetEpoch~=self.targetContext.epoch)
end
function CDM:TargetEntryCurrent(entry,instance)
    if not self:TargetContextCurrent() then return false end
    local unit=self:Read(entry.frame,"auraDataUnit")
    local current=self:Read(entry.viewer,"currentTarget")
    local owner=self:Read(entry.frame,"viewerFrame")
    return not self.source:Secret(unit) and unit=="target" and not self.source:Secret(owner) and owner==entry.viewer
        and not self.source:Secret(current) and current==self.targetContext.guid
        and self:ID(self:Read(entry.frame,"auraInstanceID"))==instance
end
function CDM:TargetData(entry)
    if not self:TargetContextCurrent() then self:TraceReject("context");return end
    if entry.targetChecked then
        if entry.targetData and self:TargetEntryCurrent(entry,self:ID(rawget(entry.targetData,"auraInstanceID"))) then self:Trace("query","cached readable");return entry.targetData end
        self:TraceReject("cached target data");return
    end
    entry.targetChecked=true
    local frame,viewer=entry.frame,entry.viewer
    local owner,ownerOK=self:Read(frame,"viewerFrame")
    if self.tracePath then self:Trace("owner",self:TraceClass(owner,ownerOK)) end
    if not ownerOK or self.source:Secret(owner) or owner~=viewer then self:TraceReject("owner");return end
    self:Trace("owner","match")
    local current,read=self:Read(viewer,"currentTarget")
    local initialized,initializedRead=self:Read(viewer,"hasDoneInitialTargetUpdate")
    local guid=self:TargetGUID();local epoch=self.source.cdmTargetEpoch
    if self.tracePath then
        local currentClass=self:TraceClass(current,read,"string")
        self:Trace("viewerGUID",currentClass=="readable" and guid and (current==guid and "match" or "mismatch") or currentClass)
        local initializedClass=self:TraceClass(initialized,initializedRead,"boolean")
        self:Trace("initialized",initializedClass=="readable" and tostring(initialized) or initializedClass)
    end
    if not guid or not read or self.source:Secret(current) or current~=guid or self:Bool(initialized)~=true then self:TraceReject("viewer binding");return end
    self:Trace("viewerGUID","match");self:Trace("initialized","true")
    local instanceRaw,instanceRead=self:Read(frame,"auraInstanceID")
    local instance=self:ID(instanceRaw)
    local query,queryRead=self:Read(self.api.C_UnitAuras,"GetAuraDataByAuraInstanceID")
    if self.tracePath then
        local instanceClass=self:TraceClass(instanceRaw,instanceRead,"number")
        self:Trace("instance",instanceClass=="readable" and not instance and "invalid" or instanceClass)
        self:Trace("queryAPI",self:TraceClass(query,queryRead,"function"))
    end
    if not instance or self.source:Secret(query) or type(query)~="function" then self:TraceReject(not instance and "instance" or "queryAPI");return end
    local ok,raw=pcall(query,"target",instance)
    if self.tracePath then self:Trace("query",self:TraceClass(raw,ok,"table")) end
    if self.source.cdmTargetEpoch~=epoch or self:TargetGUID()~=guid or not self:TargetEntryCurrent(entry,instance) then self:TraceReject("binding");return end
    self:Trace("binding","current")
    if not ok or not self.source:ReadableTable(raw) or self:ID(rawget(raw,"auraInstanceID"))~=instance then
        if self.tracePath then
            local readable=ok and self.source:ReadableTable(raw)
            if readable then self:Trace("returnedInstance",self:TraceClass(rawget(raw,"auraInstanceID"),true,"number")) end
            self:TraceReject(readable and "returnedInstance" or "query")
        end
        return
    end
    self:Trace("returnedInstance","match")
    -- Blizzard's added-aura path explicitly selects sourceUnit == player.
    -- A hidden/missing caster cannot widen this viewer's caster subset.
    local caster=rawget(raw,"sourceUnit")
    if self.tracePath then self:Trace("caster",self:TraceClass(caster,true,"string")) end
    if self.source:Secret(caster) or caster~="player" then self:TraceReject("caster");return end
    self:Trace("caster","match")
    local helpful,harmful=self:Bool(rawget(raw,"isHelpful")),self:Bool(rawget(raw,"isHarmful"))
    if not (helpful==true and harmful==false or helpful==false and harmful==true) then self:Trace("filter","unproven or conflicting");self:TraceReject("filter");return end
    self:Trace("filter",helpful and "HELPFUL" or "HARMFUL")
    entry.targetData=raw
    return raw
end
-- Estimate-only public family observation. Secret aura details and instance IDs
-- are not identity gates here; exact native details still use TargetData below.
function CDM:TargetHint(entry,id,filter)
    if not self:TargetContextCurrent() then self:TraceReject("context");return end
    local owner,ownerOK=self:Read(entry.frame,"viewerFrame")
    if self.tracePath then self:Trace("owner",self:TraceClass(owner,ownerOK)) end
    if not ownerOK or self.source:Secret(owner) or owner~=entry.viewer then self:TraceReject("owner");return end
    self:Trace("owner","match")
    local current,currentOK=self:Read(entry.viewer,"currentTarget")
    local initialized,initOK=self:Read(entry.viewer,"hasDoneInitialTargetUpdate")
    if self.tracePath then
        self:Trace("viewerGUID",self:TraceClass(current,currentOK,"string"))
        self:Trace("initialized",self:TraceClass(initialized,initOK,"boolean"))
    end
    if not currentOK or self.source:Secret(current) or current~=self.targetContext.guid or self:Bool(initialized)~=true then self:TraceReject("viewer binding");return end
    self:Trace("viewerGUID","match");self:Trace("initialized","true")
    local raw,read=self:Read(entry.frame,"auraDataCached")
    if not read then self:TraceReject("cache read");return end
    if self.source:ReadableTable(raw) then
        local spell=rawget(raw,"spellId")
        if self.tracePath then self:Trace("spell",self:TraceClass(spell,true,"number")) end
        if not self.source:Secret(spell) and spell~=nil and self:ID(spell)~=id then self:TraceReject("spell");return end
        local helpful,harmful=self:Bool(rawget(raw,"isHelpful")),self:Bool(rawget(raw,"isHarmful"))
        if helpful==true and harmful==true or filter=="HELPFUL" and (helpful==false or harmful==true)
            or filter=="HARMFUL" and (harmful==false or helpful==true) then self:TraceReject("filter mismatch");return end
        self:Trace("filter","no readable contradiction")
        local caster=rawget(raw,"sourceUnit")
        if self.tracePath then self:Trace("caster",self:TraceClass(caster,true,"string")) end
        if not self.source:Secret(caster) and caster~=nil and caster~="player" then self:TraceReject("caster");return end
    elseif not self.source:Secret(raw) and raw~=nil then self:TraceReject("cache shape");return end
    local active,valid=self:Activity(entry.frame)
    self:Trace("activity",not valid and "conflict" or active==nil and "unknown" or tostring(active))
    if not valid or active==nil then self:TraceReject("activity");return end
    if not self:TargetContextCurrent() then self:TraceReject("binding");return end
    return active
end
-- Public activity identifies a configured CDM spell family, not an exact aura
-- rank. Keep this hint separate from native Present and from all aura details.
function CDM:PresenceHint(entry,id,filter,requestedUnit)
    local info,frame=entry.info,entry.frame
    -- selfAura identifies this player-buff family. hasAura is separate static
    -- metadata, not current presence: Forever reports selfAura=true/hasAura=false
    -- for Demon Armor both while active and absent. Activity is checked below.
    if info.spellID~=id or info.overrideSpellID and info.overrideSpellID~=id then self:Trace("mapping","conflicting or linked only");self:TraceReject("mapping");return end
    self:Trace("mapping","canonical")
    if requestedUnit=="player" and (filter~="HELPFUL" or info.selfAura~=true) then return end
    local unit,ok=self:Read(frame,"auraDataUnit")
    if self.tracePath then self:Trace("unit",self:TraceClass(unit,ok,"string")) end
    if not ok or self.source:Secret(unit) then self:TraceReject("unit");return end
    if requestedUnit=="target" then
        if unit~="target" or info.selfAura==true then self:TraceReject(unit~="target" and "unit" or "selfAura");return end
        self:Trace("unit","target");self:Trace("selfAura","not true")
    elseif unit~=nil and unit~="player" then return end
    for _,key in ipairs({"totemData","editModeIndex"}) do
        local value,read=self:Read(frame,key)
        if self.tracePath then self:Trace(key,self:TraceClass(value,read)) end
        if not read or self.source:Secret(value) or value~=nil then self:TraceReject(key);return end
    end
    if requestedUnit=="target" then return self:TargetHint(entry,id,filter) end
    local active,valid=self:Activity(frame)
    self:Trace("activity",not valid and "conflict" or active==nil and "unknown" or tostring(active))
    if not valid or active~=true then self:TraceReject("activity");return end
    local raw,read=self:Read(frame,"auraDataCached")
    if not read then return end
    if self.source:ReadableTable(raw) then
        local spell=rawget(raw,"spellId")
        if self.tracePath then self:Trace("spell",self:TraceClass(spell,true,"number")) end
        if not self.source:Secret(spell) and spell~=nil and self:ID(spell)~=id then self:TraceReject("spell");return end
        if self:Bool(rawget(raw,"isHelpful"))==false or self:Bool(rawget(raw,"isHarmful"))==true then return end
    elseif not self.source:Secret(raw) and raw~=nil then return end
    return true
end
function CDM:LookupPresenceHint(id,filter,unit)
    self.tracePath=self.trace and self.trace.hintPath
    if unit=="target" and not self:TargetContextCurrent() then self:TraceReject("context");return end
    self:Trace("context","current")
    self.presenceHints=self.presenceHints or {}
    local key=unit..":"..filter..":"..id
    if self.presenceHints[key]~=nil then
        if self.tracePath then self:Trace("cache","hit");self.tracePath.outcome=self.presenceHints[key] and "accepted cached" or "rejected cached";if not self.presenceHints[key] then self:TraceReject("cached result") end end
        return self.presenceHints[key] or nil
    end
    self.presenceHints[key]=false;self.targetObservations=self.targetObservations or {};self:Snapshot()
    for _,entry in ipairs(self.frames) do
        self:TraceCandidate(entry,id,"hintPath")
        local ok,present=pcall(self.PresenceHint,self,entry,id,filter,unit)
        if not ok then self:TraceReject("adapter error") end
        self:FinishTraceCandidate("hintPath",ok and present==true)
        if unit=="target" and ok and type(present)=="boolean" then self.targetObservations[key]=present end
        if ok and present==true then
            if self.trace then self.trace.hintPath.outcome="accepted" end
            self.presenceHints[key]=true;return true
        end
    end
end
-- Independent of TargetData's numeric identity gate: this payload is usable
-- only by native duration consumers. It never feeds estimates or scalar data.
function CDM:RealTime(id,filter,unit)
    self.tracePath=nil;self:Snapshot()
    self.realTimes=self.realTimes or {};local key=unit..":"..filter..":"..id
    if self.realTimes[key]~=nil then return self.realTimes[key] or nil end
    self.realTimes[key]=false
    for _,entry in ipairs(self.frames) do
        local ok,value=pcall(function()
            if self:PresenceHint(entry,id,filter,unit)~=true then return end
            local frame=entry.frame
            local instance=self:Read(frame,"auraInstanceID")
            local raw=self:Read(frame,"auraDataCached")
            local timer=self.source:RealTime(unit,instance,raw)
            if not timer then
                local getter=self:Read(frame,"GetCooldownValues")
                if not self.source:Secret(getter) and type(getter)=="function" then
                    local success,expiration,duration,rate,paused=pcall(getter,frame)
                    if success and not self.source:Secret(paused) and paused~=true then
                        timer=self.source:RealTimeFromTimes(expiration,duration,rate)
                    end
                end
            end
            self.activities[frame]=nil
            if self:PresenceHint(entry,id,filter,unit)~=true then return end
            return timer
        end)
        if ok and value then self.realTimes[key]=value;return value end
    end
end
function CDM:Resolve(entry,id,filter,transport,requestedUnit)
    if not entry.info.ids[id] then return end
    self:Trace("mapping","mapped")
    local frame=entry.frame
    -- Buff viewers also host target auras and totems. Their visibility or an
    -- active cooldown alone is not proof of this player's requested aura.
    local unit,unitOK=self:Read(frame,"auraDataUnit")
    if self.tracePath then self:Trace("unit",self:TraceClass(unit,unitOK,"string")) end
    if not unitOK or self.source:Secret(unit) or unit~=requestedUnit then self:TraceReject("unit");return end
    self:Trace("unit","target")
    for _,field in ipairs({"totemData","editModeIndex"}) do
        local value,ok=self:Read(frame,field)
        if self.tracePath then self:Trace(field,self:TraceClass(value,ok)) end
        if not ok or self.source:Secret(value) or value~=nil then self:TraceReject(field);return end
    end
    local active,valid=self:Activity(frame)
    self:Trace("activity",not valid and "conflict" or active==nil and "unknown" or tostring(active))
    if not valid then self:TraceReject("activity");return end
    local instanceRaw=self:Read(frame,"auraInstanceID")
    local instance=self:ID(instanceRaw)
    -- The viewer scans player-cast auras, a subset of Unit Aura's HELPFUL /
    -- HARMFUL filters. Inactivity cannot prove general absence (an aura from
    -- another caster may still exist), even if old cached metadata remains.
    if active==false then self:TraceReject("activity");return end
    if active==nil and instance then active=true end
    if active==nil then self:TraceReject("activity");return end
    local raw
    if requestedUnit=="target" then
        if entry.info.selfAura==true then self:TraceReject("selfAura");return end
        raw=self:TargetData(entry);if not raw then return end
    else raw=self:Read(frame,"auraDataCached") end
    -- The current frame's readable instance may be re-queried; secret IDs are
    -- never compared, cached as keys, or passed back to aura lookup functions.
    if not self.source:ReadableTable(raw) and instance then
        local query=self:Read(self.api.C_UnitAuras,"GetAuraDataByAuraInstanceID")
        if not self.source:Secret(query) and type(query)=="function" then
            local ok,value=pcall(query,requestedUnit,instance)
            if ok and self.source:ReadableTable(value) and self:ID(rawget(value,"auraInstanceID"))==instance then raw=value end
        end
    end
    if not self.source:ReadableTable(raw) then return end
    local cachedInstance=self:ID(rawget(raw,"auraInstanceID"))
    if instance and cachedInstance and instance~=cachedInstance then return end
    local spell=rawget(raw,"spellId")
    if self.tracePath then self:Trace("spell",self:TraceClass(spell,true,"number")) end
    if self.source:Secret(spell) then
        if entry.info.count~=1 then self:TraceReject("ambiguous exact rank");return end
    elseif self:ID(spell)~=id then self:TraceReject("spell");return end
    local helpful=self:Bool(rawget(raw,"isHelpful"));local harmful=self:Bool(rawget(raw,"isHarmful"))
    if helpful==true and harmful==true then self:TraceReject("filter conflict");return end
    if filter=="HELPFUL" and helpful~=true or filter=="HARMFUL" and harmful~=true then self:TraceReject("filter mismatch");return end
    local ok,data=pcall(self.source.Data,self.source,raw,filter,true,id)
    if not ok or not data then self:TraceReject("data parse");return end
    local out={values={present=true,stacks=data.stacks,duration=data.duration,hasExpiration=data.hasExpiration,texture=data.texture},
        fields=data.fields,expirationTime=data.expirationTime,auraInstanceID=instance or data.auraInstanceID,unit=requestedUnit,status="present / CDM"}
    if not transport then for key,value in pairs(out.values) do if G.IsSecret(value) then out.values[key]=nil end end end
    if out.auraInstanceID then
        local query=self:Read(self.api.C_UnitAuras,"GetAuraDuration")
        if not self.source:Secret(query) and type(query)=="function" then
            local success,duration=pcall(query,requestedUnit,out.auraInstanceID)
            if success and not self.source:Secret(duration) then
                for key,methodName in pairs({duration="GetTotalDuration",remaining="GetRemainingDuration"}) do
                    if (key~="remaining" or out.expirationTime==nil) and (out.values[key]==nil or G.IsSecret(out.values[key])) then
                        local value,read=self:Read(duration,methodName,true)
                        if read then
                            local number=self.source:Number(value)
                            if number then out.values[key]=number;out.fields[key]="readable"
                            elseif transport and self.source:Secret(value) and out.values[key]==nil then out.values[key]=G.Capture(value,"float",function()return true end);out.fields[key]="protected" end
                        end
                    end
                end
            end
        end
    end
    -- A readable remaining duration is a current sample, not a constant. Turn
    -- it into the same expiry representation used by the primary aura reader
    -- so the normal runtime countdown continues between aura events.
    if out.expirationTime==nil and G.Number(out.values.remaining) and (out.values.remaining>0 or out.values.hasExpiration==true) then
        local clock=self.api.GetTime
        if not self.source:Secret(clock) and type(clock)=="function" then
            local ok,now=pcall(clock)
            local readable=ok and self.source:Number(now)
            if readable then
                out.expirationTime=readable+out.values.remaining
                out.values.remaining=nil;out.values.hasExpiration=true;out.fields.hasExpiration="readable"
            end
        end
    end
    if requestedUnit=="target" and not self:TargetEntryCurrent(entry,instance) then self:TraceReject("binding");return end
    return out
end
function CDM:Lookup(id,filter,transport,unit)
    self.tracePath=self.trace and self.trace.detailPath
    if unit=="target" and not self:TargetContextCurrent() then self:TraceReject("context");return end
    self:Trace("context","current")
    if filter~="HELPFUL" and filter~="HARMFUL" then return end
    self.results=self.results or {}
    local key=unit..":"..filter..":"..id..":"..tostring(transport)
    if self.results[key]~=nil then
        if self.tracePath then self:Trace("cache","hit");self.tracePath.outcome=self.results[key] and "accepted cached" or "rejected cached";if not self.results[key] then self:TraceReject("cached result") end end
        return self.results[key] or nil
    end
    self.results[key]=false
    self:Snapshot()
    local result
    for _,entry in ipairs(self.frames) do
        self:TraceCandidate(entry,id,"detailPath")
        local ok,candidate=pcall(self.Resolve,self,entry,id,filter,transport,unit)
        if not ok then self:TraceReject("adapter error") end
        self:FinishTraceCandidate("detailPath",ok and candidate~=nil)
        if ok and candidate then
            if result and result.values.present~=candidate.values.present then return end
            if not result then result=candidate end
        end
    end
    if self.trace and result then self.trace.detailPath.outcome="accepted" end
    self.results[key]=result or false
    return result
end
function CDM:Fill(result,id,filter,transport,unit)
    unit=unit or "player"
    if unit~="player" and unit~="target" then return end
    if result.values and result.values.present==false then return end
    result.cdmPresence=self:LookupPresenceHint(id,filter,unit)
    if unit=="target" and self.targetObservations then result.cdmTargetObservation=self.targetObservations[unit..":"..filter..":"..id] end
    local candidate=self:Lookup(id,filter,transport,unit)
    if self.trace then
        for _,path in ipairs({self.trace.hintPath,self.trace.detailPath}) do
            if path.outcome=="not reached" then path.outcome="rejected";path.reason=path.reason or "no qualifying readable viewer" end
        end
    end
    self.tracePath=nil
    if unit=="target" and not self:TargetContextCurrent() then result.cdmPresence=nil;result.cdmTargetObservation=nil;return end
    if not candidate then return end
    if result.values and result.values.present==true and candidate.values.present~=true then return end
    if result.auraInstanceID and candidate.auraInstanceID and result.auraInstanceID~=candidate.auraInstanceID then return end
    local hadPresence=result.values and result.values.present~=nil
    result.values=result.values or {};result.fields=result.fields or {}
    for key,value in pairs(candidate.values) do
        local current=result.values[key]
        if (key~="remaining" or result.expirationTime==nil) and (current==nil or G.IsSecret(current) and not G.IsSecret(value)) then
            result.values[key]=value;result.fields[key]=candidate.fields[key] or "readable"
        end
    end
    -- Secret fields may have no scalar payload (notably expiration/remaining).
    -- Keep this metadata when CDM supplies presence; otherwise replacing the
    -- overall source status would erase the field's independently known state.
    for key,status in pairs(candidate.fields or {}) do
        local current=result.fields[key]
        if status=="protected" and result.values[key]==nil and (current==nil or current=="unavailable")
            and (key~="remaining" or result.expirationTime==nil) then result.fields[key]=status end
    end
    if result.expirationTime==nil and candidate.expirationTime~=nil then result.expirationTime=candidate.expirationTime;result.fields.remaining=candidate.fields.remaining end
    result.auraInstanceID=result.auraInstanceID or candidate.auraInstanceID
    result.unit=result.unit or candidate.unit
    if not hadPresence then result.status=candidate.status end
end
