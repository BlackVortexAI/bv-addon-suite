-- Opt-in capability observations; no secure APIs, payload dumps, or CDM mutations.
local _,A=...
if A.blocked then return end
local ns=BVAddonSuiteCore
local D={};D.__index=D;A.InfoDiagnostics=D
function D.New(api,events,collector)
    return setmetatable({api=api or _G,events=events or ns.Events,collector=collector or A.infoCollector},D)
end
function D:Function(fn) local f=self.collector:Field(fn);return f.status~="protected" and type(fn)=="function" end
function D:Table(value)
    local f=self.collector:Field(value)
    return f.status~="protected" and type(value)=="table" and getmetatable(value)==nil and value or nil
end
-- Public CDM contract: pinned Blizzard c6e8998, Environment All. Never load or
-- enable a viewer. Every foreign value is classified before use, including keys.
local categories={"Essential","Utility","TrackedBuff","TrackedBar","GroupBuff","SpecAgnosticEssential","SpecAgnosticTracked","EquipSlotEssential","EquipSlotTracked"}
local infoFields={"cooldownID","spellID","overrideSpellID","overrideTooltipSpellID","spellCategoryID","equipSlot","buffSlot","category","selfAura","hasAura","charges","isKnown","isInvisible","flags"}
local function bump(counts,status) counts[status]=(counts[status] or 0)+1 end
function D:DataStatus(value)
    local field=self.collector:Field(value)
    if field.status=="protected" then return "protected" end
    if field.type=="nil" then return "missing" end
    if type(value)~="table" or getmetatable(value)~=nil then return "invalid" end
    return "readable"
end
function D:Scalar(value,kind)
    local f=self.collector:Field(value)
    if f.status=="protected" then return nil,"protected" end
    if f.type=="nil" then return nil,"missing" end
    if f.status~="readable" or f.type~=kind then return nil,"invalid" end
    return f.value,"readable"
end
function D:ID(value)
    local number,status=self:Scalar(value,"number")
    if status~="readable" then return nil,status end
    if number<0 or number>2147483647 or number~=math.floor(number) then return nil,"invalid" end
    return number,"readable"
end
function D:Query(namespace,name,...)
    local status=self:DataStatus(namespace)
    if status~="readable" then return nil,status end
    local fn=namespace[name];local f=self.collector:Field(fn)
    if f.status=="protected" then return nil,"protected" end
    if f.type=="nil" then return nil,"missing" end
    if not self:Function(fn) then return nil,"invalid" end
    local ok,value=pcall(fn,...)
    if not ok then return nil,"error" end
    return value,"success"
end
-- This diagnostic is deliberately separate from AuraSource: it records each
-- public path, never changes runtime presence or uses a hidden value as a key.
function D:AuraField(value,kind,retain)
    local parsed,status
    if kind=="id" then parsed,status=self:ID(value) else parsed,status=self:Scalar(value,kind) end
    local out={status=status};if retain then out.value=parsed end;return out
end
function D:AuraRaw(raw,queryStatus)
    local out={query=queryStatus,raw=queryStatus=="success" and self:DataStatus(raw) or "not-read",access={},fields={}}
    for _,name in ipairs({"issecretvalue","issecrettable","canaccesstable"}) do
        local fn=self.api[name];local f=self.collector:Field(fn)
        if f.status=="protected" then out.access[name]={status="protected"}
        elseif f.type=="nil" then out.access[name]={status="missing"}
        elseif not self:Function(fn) then out.access[name]={status="invalid"}
        elseif queryStatus~="success" then out.access[name]={status="not-read"}
        else
            local ok,value=pcall(fn,raw)
            out.access[name]=ok and self:AuraField(value,"boolean",true) or {status="error"}
        end
    end
    if out.raw=="readable" then
        for _,name in ipairs({"spellId","spellID","auraInstanceID"}) do out.fields[name]=self:AuraField(rawget(raw,name),"id",true) end
        for _,name in ipairs({"isHelpful","isHarmful"}) do out.fields[name]=self:AuraField(rawget(raw,name),"boolean",true) end
        for _,name in ipairs({"applications","duration","expirationTime"}) do out.fields[name]=self:AuraField(rawget(raw,name),"number",false) end
    end
    return out
end
function D:AuraRequests()
    local requests,seen={},{};local skipped,truncated=0,false
    local studio=ns.AuraStudio
    for _,map in ipairs({studio and studio.auraRequests or {},studio and studio.unitAuraRequests or {}}) do
        if self:DataStatus(map)=="readable" then
            local keys,scanned={},0
            for key in pairs(map) do
                scanned=scanned+1;if scanned>128 then truncated=true;break end
                local name,status=self:Scalar(key,"string")
                if status=="readable" then keys[#keys+1]=name else skipped=skipped+1 end
            end
            table.sort(keys)
            for _,key in ipairs(keys) do
                local request=rawget(map,key)
                if self:DataStatus(request)=="readable" then
                    local unit,us=self:Scalar(rawget(request,"unit"),"string")
                    if us=="missing" then unit,us="player","readable" end
                    local spell,ss=self:ID(rawget(request,"spellID"))
                    local filter,fs=self:Scalar(rawget(request,"filter"),"string")
                    local transport,ts=self:Scalar(rawget(request,"transport"),"boolean")
                    if us=="readable" and A.UnitSource.ValidToken(unit) and ss=="readable" and spell>0 and fs=="readable"
                        and (filter=="HELPFUL" or filter=="HARMFUL") and (ts=="readable" or ts=="missing") then
                        local identity=unit..":"..filter..":"..spell..":"..tostring(transport==true)
                        if not seen[identity] then
                            seen[identity]=true
                            if #requests<4 then requests[#requests+1]={unit=unit,filter=filter,spellID=spell,transport=transport==true,origin="active"}
                            else truncated=true end
                        end
                    else skipped=skipped+1 end
                else skipped=skipped+1 end
            end
        end
    end
    if #requests==0 then
        for _,spell in ipairs({5697,706,687}) do requests[#requests+1]={unit="player",filter="HELPFUL",spellID=spell,transport=false,origin="default (no valid active request)"} end
    end
    return requests,skipped,truncated
end
function D:AuraPaths()
    local requests,skipped,truncated=self:AuraRequests()
    local out={requests=requests,scans={},reads=0,skippedRequests=skipped,requestsTruncated=truncated}
    local namespace=self.api.C_UnitAuras
    local function take()
        if out.reads>=128 then return false end
        out.reads=out.reads+1;return true
    end
    local scans={}
    for _,request in ipairs(requests) do
        if request.unit=="player" then
            local raw,status=self:Query(namespace,"GetPlayerAuraBySpellID",request.spellID)
            request.playerGetter=self:AuraRaw(raw,status)
        else request.playerGetter={query="not-applicable",raw="not-read",fields={},access={}} end
        local raw,status=self:Query(namespace,"GetUnitAuraBySpellID",request.unit,request.spellID)
        request.unitGetter=self:AuraRaw(raw,status)
        raw,status=self:Query(self.api.C_Secrets,"ShouldSpellAuraBeSecret",request.spellID)
        request.restriction=status=="success" and self:AuraField(raw,"boolean",true) or {status=status}
        local key=request.unit..":"..request.filter
        if not scans[key] then
            local scan={unit=request.unit,filter=request.filter,list={entries={},fields={}},instances={entries={},fields={}},index={entries={},fields={}}}
            scans[key]=scan;out.scans[#out.scans+1]=scan
        end
        request.scan=key
    end
    local function summarize(path,raw,status,index,instance)
        local row=self:AuraRaw(raw,status);row.index=index;row.instance=instance
        path.entries[#path.entries+1]=row
        bump(path.fields,"raw:"..row.raw)
        for name,value in pairs(row.fields) do bump(path.fields,name..":"..value.status) end
        for name,value in pairs(row.access) do bump(path.fields,name..":"..value.status..(value.value~=nil and "="..tostring(value.value) or "")) end
    end
    for _,scan in ipairs(out.scans) do
        -- Per filter: at most 12 list entries, 12 instance IDs and 8 index
        -- entries. Every examined slot and instance lookup consumes the shared
        -- 128-read budget. Collection getter calls are separately bounded to 8.
        for _,mode in ipairs({"list","instances"}) do
            local path=scan[mode];local raw,status
            if mode=="list" then raw,status=self:Query(namespace,"GetUnitAuras",scan.unit,scan.filter,32)
            else raw,status=self:Query(namespace,"GetUnitAuraInstanceIDs",scan.unit,scan.filter) end
            path.query=status;path.raw=status=="success" and self:DataStatus(raw) or "not-read";path.complete=false
            if path.raw=="readable" then
                for index=1,12 do
                    if not take() then path.limit="snapshot read limit";break end
                    local entry=rawget(raw,index);local state=self.collector:Field(entry)
                    if state.type=="nil" and state.status~="protected" then path.complete=true;break end
                    if mode=="list" then summarize(path,entry,"success",index)
                    else
                        local instance,is=self:ID(entry)
                        if is=="readable" and instance>0 then
                            if not take() then path.limit="snapshot read limit";break end
                            local data,read=self:Query(namespace,"GetAuraDataByAuraInstanceID",scan.unit,instance)
                            summarize(path,data,read,index,instance)
                        else
                            path.entries[#path.entries+1]={index=index,instanceStatus=is=="readable" and "invalid" or is}
                            bump(path.fields,"instanceID:"..(is=="readable" and "invalid" or is))
                        end
                    end
                    if index==12 then path.limit="path entry limit (12)" end
                end
            end
        end
        local path=scan.index;path.query="not-read";path.raw="not-read";path.complete=false
        for index=1,8 do
            if not take() then path.limit="snapshot read limit";break end
            local raw,status=self:Query(namespace,"GetAuraDataByIndex",scan.unit,index,scan.filter)
            path.query=status;path.raw=status=="success" and self:DataStatus(raw) or "not-read"
            if status~="success" then break end
            if path.raw=="missing" then path.complete=true;break end
            summarize(path,raw,status,index)
            if index==8 then path.limit="path entry limit (8)" end
        end
    end
    return out
end
function D:FrameRead(frame,key,call)
    local f=self.collector:Field(frame)
    if f.status=="protected" then return nil,"protected" end
    if f.type=="nil" then return nil,"missing" end
    if f.type~="table" and f.type~="userdata" then return nil,"invalid" end
    local ok,value=pcall(function() return frame[key] end)
    if not ok then return nil,"error" end
    if call then
        local method=self.collector:Field(value)
        if method.status=="protected" then return nil,"protected" end
        if method.type=="nil" then return nil,"missing" end
        if method.type~="function" then return nil,"invalid" end
        ok,value=pcall(value,frame)
        if not ok then return nil,"error" end
    end
    return value,"success"
end
function D:FrameAccess(frame)
    local value,status=self:FrameRead(frame,"CanBeAccessedInContext",true)
    if status~="success" then return status end
    local accessible,read=self:Scalar(value,"boolean")
    if read~="readable" then return read end
    if not accessible then return "protected" end
    value,status=self:FrameRead(frame,"IsForbidden",true)
    if status~="success" then return status end
    local forbidden;forbidden,read=self:Scalar(value,"boolean")
    if read~="readable" then return read end
    return forbidden and "protected" or "readable"
end
-- Read-only discovery mirrors the existing Henni pool/nested search, with hard
-- budgets. No frame is created, activated, refreshed or retained in snapshots.
local viewerIDFields={"cooldownID","cooldownId","cooldownIDOverride","cdID","cdId"}
function D:Viewer(frame,mappings)
    local out={status=self:FrameAccess(frame),children=0,visited=0,slots=0,poolSteps=0,duplicates=0,
        matches=0,active={},activeMethod={},shown={},ids={},observedIDs={},matchedFrames={},traversal={},limits={},truncated=false}
    if out.status~="readable" then return out end
    local queue,seen={{frame=frame,depth=0,source="root"}},{[frame]=true}
    local function limit(name) out.truncated=true;out.limits[name]=1 end
    local function enqueue(child,depth,source)
        if out.slots>=128 then limit("candidate slots (128)");return end
        out.slots=out.slots+1
        local f=self.collector:Field(child)
        if f.status=="protected" then bump(out.traversal,"protected");return end
        if f.type~="table" and f.type~="userdata" then bump(out.traversal,f.type=="nil" and "missing" or "invalid");return end
        if seen[child] then out.duplicates=out.duplicates+1;return end
        if out.children>=64 then limit("unique frames (64)");return end
        seen[child]=true;out.children=out.children+1
        queue[#queue+1]={frame=child,depth=depth,source=source}
    end
    -- Existing frame pool only. Iterators are called under pcall, and their
    -- state/control are classified before being passed back or used as keys.
    local pool,poolRead=self:FrameRead(frame,"itemFramePool")
    local pf=self.collector:Field(pool)
    if poolRead~="success" then out.pool=poolRead
    elseif pf.status=="protected" then out.pool="protected"
    elseif pf.type=="nil" then out.pool="missing"
    elseif pf.type~="table" then out.pool="invalid"
    else
        local fn,read=self:FrameRead(pool,"EnumerateActive")
        local ff=self.collector:Field(fn)
        if read~="success" then out.pool=read
        elseif ff.status=="protected" then out.pool="protected"
        elseif ff.type~="function" then out.pool=ff.type=="nil" and "missing" or "invalid"
        else
            local ok,iter,state,control=pcall(fn,pool)
            if not ok then out.pool="error"
            elseif self.collector:Field(iter).status=="protected" or self.collector:Field(state).status=="protected" or self.collector:Field(control).status=="protected" then out.pool="protected"
            elseif not self:Function(iter) then out.pool="invalid"
            else
                out.pool="readable"
                for _=1,64 do
                    out.poolSteps=out.poolSteps+1
                    local success,child=pcall(iter,state,control)
                    if not success then out.pool="error";break end
                    local field=self.collector:Field(child)
                    if field.status=="protected" then out.pool="protected";break end
                    if field.type=="nil" then out.poolComplete=true;break end
                    if field.type~="table" and field.type~="userdata" then out.pool="invalid";break end
                    control=child;enqueue(child,1,"pool")
                    if out.poolSteps==64 then limit("pool steps (64)") end
                end
            end
        end
    end
    local index=1
    while index<=#queue do
        local item=queue[index];index=index+1
        local child=item.frame;local access=item.source=="root" and "readable" or self:FrameAccess(child)
        if access~="readable" then bump(out.ids,access)
        else
            out.visited=out.visited+1
            local id,idSource,idStatus,conflict=nil,nil,"missing",false
            for _,name in ipairs(viewerIDFields) do
                local raw,read=self:FrameRead(child,name)
                local value,status=self:ID(raw);if read~="success" then status=read end
                if status=="readable" then
                    if id and id~=value then conflict=true end
                    if not id then id=value;idSource=name end
                elseif status~="missing" then idStatus=status end
            end
            if conflict then id=nil;idStatus="conflicting IDs" end
            if id then idStatus="readable";bump(out.observedIDs,tostring(id)) end
            bump(out.ids,idStatus)
            if id and mappings[id] then
                out.matches=out.matches+1
                local matched={cooldownID=id,idSource=idSource,depth=item.depth,source=item.source}
                out.matchedFrames[#out.matchedFrames+1]=matched
                -- Blizzard CooldownViewerItemMixin:IsActive (352-354) only returns isActive.
                for _,field in ipairs({{"active","isActive",false},{"activeMethod","IsActive",true},{"shown","IsShown",true},{"auraInstanceID","auraInstanceID",false}}) do
                    local raw,read=self:FrameRead(child,field[2],field[3])
                    local value,status
                    if field[1]=="auraInstanceID" then value,status=self:ID(raw) else value,status=self:Scalar(raw,"boolean") end
                    if read~="success" then status=read end
                    matched[field[1]]={status=status,value=value}
                    if out[field[1]] then bump(out[field[1]],status=="readable" and tostring(value) or status) end
                end
            end
            local fn,read=self:FrameRead(child,"GetChildren")
            local ff=self.collector:Field(fn)
            if read=="success" then
                if ff.status=="protected" then read="protected"
                elseif ff.type~="function" then read=ff.type=="nil" and "missing" or "invalid" end
            end
            if read~="success" then
                bump(out.traversal,read)
                if item.source=="root" then out.status=read end
            elseif item.depth>=4 then limit("depth (4)")
            elseif out.slots>=128 then limit("candidate slots (128)")
            else
                local ok=pcall(function()
                    local function inspect(...)
                        local count=select("#",...)
                        local take=math.min(count,64,128-out.slots)
                        if take<count then limit("child enumeration slots") end
                        for i=1,take do enqueue(select(i,...),item.depth+1,"children") end
                    end
                    inspect(fn(child))
                end)
                bump(out.traversal,ok and "readable" or "error")
                if not ok and item.source=="root" then out.status="error" end
            end
        end
    end
    return out
end
function D:CDMSnapshot(reason,transition)
    if not self.active then return false,"not running" end
    local now=self.collector:Now()
    if reason~="start" and reason~="stop" then
        local key=transition and "cdmTransitions" or "cdmOrdinary"
        if self[key]>=(transition and 6 or 24) or not transition and (not now or now==self.cdmLastTime or self.cdmLastTime and now-self.cdmLastTime<1) then
            self.cdmSkipped=self.cdmSkipped+1;return false,"snapshot rate or session limit; wait a second or start a new session"
        end
        self[key]=self[key]+1
    end
    self.cdmLastTime=now
    self:Sample()
    local phase="unknown"
    if self:Function(self.api.InCombatLockdown) then
        local ok,value=pcall(self.api.InCombatLockdown)
        local combat,status=self:Scalar(value,"boolean")
        if not ok then status="error" end
        if status=="readable" then phase=combat and "during" or self.cdmSawCombat and "after" or "before" end
    end
    if phase=="during" then self.cdmSawCombat=true end
    local snap={reason=reason,phase=phase,time=now,categories={},fields={},mappings={},info={},restriction=self.restriction,
        targetMappings={},inventories={},linkedSlots=0}
    snap.targetAdapterRows=self:TargetAdapterSnapshot()
    snap.auraPaths=self:AuraPaths()
    for _,request in ipairs(snap.auraPaths.requests) do snap.targetMappings[request.spellID]=snap.targetMappings[request.spellID] or {} end
    local namespace=self.api.C_CooldownViewer;snap.namespace=self:DataStatus(namespace)
    local available,availability=self:Query(namespace,"IsCooldownViewerAvailable")
    if availability=="success" then
        local value,status=self:Scalar(available,"boolean");availability=status=="readable" and tostring(value) or status
    end
    snap.available=availability
    local enumStatus=self:DataStatus(self.api.Enum)
    local enum
    if enumStatus=="readable" then enum=self.api.Enum.CooldownViewerCategory end
    if enumStatus=="readable" then enumStatus=self:DataStatus(enum) end
    local inventorySeen={}
    for _,name in ipairs(categories) do
        local row={name=name,ids={},info={},count=0,truncated=false};snap.categories[#snap.categories+1]=row
        local category,categoryStatus
        if enumStatus=="readable" then category,categoryStatus=self:ID(enum[name]) else categoryStatus=enumStatus end
        if categoryStatus~="readable" then row.status="enum-"..categoryStatus
        else
            local ids,status=self:Query(namespace,"GetCooldownViewerCategorySet",category,false)
            row.status=status=="success" and self:DataStatus(ids) or status
            if row.status=="readable" then
                -- API contract is a sequence. Fixed raw indices avoid foreign keys,
                -- length metamethods, or iteration over arbitrary untrusted maps.
                for index=1,33 do
                    local raw=rawget(ids,index);local id,idStatus=self:ID(raw)
                    if idStatus=="missing" then break end
                    if index==33 then row.truncated=true;break end
                    row.count=row.count+1;bump(row.ids,idStatus)
                    if idStatus=="readable" then
                        local info,infoStatus=self:Query(namespace,"GetCooldownViewerCooldownInfo",id)
                        infoStatus=infoStatus=="success" and self:DataStatus(info) or infoStatus
                        if infoStatus=="readable" and self.collector:Field(next(info)).type=="nil" then infoStatus="empty" end
                        bump(row.info,infoStatus);bump(snap.info,infoStatus)
                        if infoStatus=="readable" and not inventorySeen[id] and #snap.inventories>=64 then snap.inventoryTruncated=true end
                        if infoStatus=="readable" and not inventorySeen[id] and #snap.inventories<64 then
                            inventorySeen[id]=true
                            local targets={};local inventory={category=name,cooldownID=id,linked={},linkedComplete=false}
                            snap.inventories[#snap.inventories+1]=inventory
                            for _,field in ipairs(infoFields) do
                                local f=self.collector:Field(rawget(info,field))
                                snap.fields[field]=snap.fields[field] or {};bump(snap.fields[field],f.status)
                                if field=="spellID" or field=="overrideSpellID" then
                                    local spell,read=self:ID(rawget(info,field));inventory[field]={status=read,value=spell}
                                    if read=="readable" and snap.targetMappings[spell] then targets[spell]=true end
                                elseif field=="selfAura" or field=="hasAura" then
                                    local value,read=self:Scalar(rawget(info,field),"boolean");inventory[field]={status=read,value=value}
                                end
                            end
                            local linked=rawget(info,"linkedSpellIDs");local linkedStatus=self:DataStatus(linked)
                            inventory.linkedStatus=linkedStatus
                            snap.fields.linkedSpellIDs=snap.fields.linkedSpellIDs or {};bump(snap.fields.linkedSpellIDs,linkedStatus)
                            if linkedStatus=="readable" then
                                for j=1,128 do
                                    if snap.linkedSlots>=1024 then inventory.linkedLimit="snapshot slot limit (1024)";break end
                                    snap.linkedSlots=snap.linkedSlots+1
                                    local spell,read=self:ID(rawget(linked,j))
                                    if read=="missing" then inventory.linkedComplete=true;break end
                                    bump(snap.fields.linkedSpellIDs,"item-"..read)
                                    if read=="readable" then inventory.linked[#inventory.linked+1]=spell;if snap.targetMappings[spell] then targets[spell]=true end end
                                    if j==128 then inventory.linkedLimit="entry slot limit (128)" end
                                end
                                if not inventory.linkedComplete then bump(snap.fields.linkedSpellIDs,"truncated") end
                            end
                            for spell in pairs(targets) do snap.mappings[id]=true;snap.targetMappings[spell][id]=true end
                        end
                    end
                end
                if row.count==0 then row.status="empty" end
            end
        end
    end
    snap.icon=self:Viewer(self.api.BuffIconCooldownViewer,snap.mappings)
    snap.bar=self:Viewer(self.api.BuffBarCooldownViewer,snap.mappings)
    self.cdmSnapshots[#self.cdmSnapshots+1]=snap
    return true
end
-- Runtime-only trace: adapters publish already classified scalar decisions.
-- No frame, GUID, aura table or native payload is retained by these four slots.
local targetGates={"cache","context","guid","mapping","unit","selfAura","totemData","editModeIndex","activity","activeField","activeMethod","owner","viewerGUID","initialized","instance","queryAPI","query","returnedInstance","caster","filter","spell","binding"}
function D:BeginTargetAdapter(source,request,observedAt)
    if not self.active then return end
    local function path()
        local out={gates={},outcome="not reached"}
        for _,name in ipairs(targetGates) do out.gates[name]="not reached" end
        return out
    end
    local studio=ns.AuraStudio
    return {unit="target",spellID=request.spellID,filter=request.filter,transport=request.transport==true,
        observedAt=observedAt,captureSerial=source.captureSerial,targetEpoch=source.cdmTargetEpoch or 0,
        targetGeneration=studio and studio.unitGenerations and studio.unitGenerations.target or 0,
        hintPath=path(),detailPath=path(),adapter="not invoked",hint=false}
end
function D:TargetPresence(observation)
    local value=observation.values and observation.values.present
    if A.G.IsSecret(value) then return "Secret" end
    if type(value)=="boolean" then return tostring(value) end
    return ns.GraphValues.StatusLabel(A.G.SignalStatus(nil,observation.fields and observation.fields.present or observation.status))
end
function D:PublishTargetAdapter(row)
    if not self.active then return end
    self.targetAdapterRows=self.targetAdapterRows or {}
    local rows=self.targetAdapterRows
    for index,old in ipairs(rows) do
        if old.spellID==row.spellID and old.filter==row.filter and old.transport==row.transport then table.remove(rows,index);break end
    end
    table.insert(rows,1,row)
    if #rows>4 then table.remove(rows) end
end
function D:TargetAdapterSnapshot()
    local rows=A.G.Copy(self.targetAdapterRows or {})
    local studio=ns.AuraStudio
    local generation=studio and studio.unitGenerations and studio.unitGenerations.target or 0
    for _,row in ipairs(rows) do row.binding=row.targetGeneration==generation and "current generation" or "stale generation" end
    return rows
end
function D:TargetAdapterReport(lines,rows,at,label)
    if not rows or #rows==0 then lines[#lines+1]="  "..label..": no capture";return end
    for _,row in ipairs(rows) do
        local age=at and row.observedAt and at>=row.observedAt and string.format("%.3fs",at-row.observedAt) or "unknown"
        lines[#lines+1]="  "..label.." target spell="..row.spellID.." filter="..row.filter.." transport="..tostring(row.transport)
            .." capture="..row.captureSerial.." time="..(row.observedAt or "unknown").." age="..age.." generation="..row.targetGeneration.." targetEpoch="..row.targetEpoch
            .." binding="..(row.binding or "unknown").." adapter="..row.adapter.." sourceBefore="..row.beforePresent.." hint="..tostring(row.hint).." sourceAfter="..row.afterPresent
        for _,name in ipairs({"hintPath","detailPath"}) do
            local path=row[name];local gates={}
            for _,gate in ipairs(targetGates) do gates[#gates+1]=gate.."="..path.gates[gate] end
            lines[#lines+1]="    "..name.." outcome="..path.outcome.." cooldownID="..(path.cooldownID or "not reached").." candidates="..(path.candidates or 0).." firstReject="..(path.reason or "none").." "..table.concat(gates," ")
        end
    end
end
function D:Sample()
    local api,c=self.api,self.collector
    local log=self:Table(api.C_CombatLog)
    local restricted="unsupported"
    if log and self:Function(log.IsCombatLogRestricted) then
        local ok,value=pcall(log.IsCombatLogRestricted);local f=ok and c:Field(value)
        restricted=f and f.status=="readable" and f.type=="boolean" and (f.value and "restricted" or "unrestricted") or "unavailable"
    end
    self.getter=log and self:Function(log.GetCurrentEventInfo) and log.GetCurrentEventInfo
        or self:Function(api.CombatLogGetCurrentEventInfo) and api.CombatLogGetCurrentEventInfo or nil
    self.restriction=restricted
    local cdm=self:Table(api.C_CooldownViewer)
    c:Publish("capability","combat_log",{getter=self.getter~=nil,restriction=restricted,registration=self.registration or "not attempted"})
    local function exists(value) local f=c:Field(value);return f.status=="protected" and "protected" or f.type=="nil" and "absent" or "present" end
    c:Publish("capability","cdm",{namespace=exists(api.C_CooldownViewer),categoryQuery=cdm and exists(cdm.GetCooldownViewerCategorySet) or "unknown",
        infoQuery=cdm and exists(cdm.GetCooldownViewerCooldownInfo) or "unknown",
        buffIconViewer=exists(api.BuffIconCooldownViewer),buffBarViewer=exists(api.BuffBarCooldownViewer)})
end
local payloadFields={[2]="event",[4]="sourceGUID",[8]="destinationGUID",[12]="spellID"}
function D:Event()
    if not self.active then return end
    self.delivered=self.delivered+1
    -- Count every delivery; classify at most 60 payloads per second, 600 per session.
    local now=self.collector:Now();if not now then self.skipped=self.skipped+1;return end
    local second=math.floor(now)
    if second~=self.second then self.second=second;self.rate=0 end
    if self.sampled>=600 or self.rate>=60 then self.skipped=self.skipped+1;return end
    self.rate=self.rate+1;self.sampled=self.sampled+1
    self:Sample()
    if not self.getter or self.restriction=="restricted" then self.unavailable=self.unavailable+1;return end
    local function read()
        local function inspect(...)
            local out={}
            for index,name in pairs(payloadFields) do
                local field=self.collector:Field(select(index,...))
                out[name]=field.status..":"..field.type
            end
            return out
        end
        return inspect(self.getter())
    end
    local ok,fields=pcall(read)
    if not ok then self.errors=self.errors+1;return end
    for name,status in pairs(fields) do
        local key=name.."="..status;self.readability[key]=(self.readability[key] or 0)+1
    end
end
function D:Start()
    if self.active then return false,"already running" end
    self.delivered,self.sampled,self.skipped,self.unavailable,self.errors,self.rate=0,0,0,0,0,0
    self.readability={};self.active=true;self.finished=nil;self.started=self.collector:Now();self.registration="not attempted";self.collector:SetRecording(true)
    self.frozenReport=nil;self.targetAdapterRows={};self.cdmSnapshots={};self.cdmSkipped=0;self.cdmOrdinary=0;self.cdmTransitions=0;self.cdmSawCombat=false;self.cdmLastTime=nil
    self.identity=self:BuildIdentity()
    self:Sample()
    local ok=pcall(self.events.Subscribe,self.events,self,"COMBAT_LOG_EVENT_UNFILTERED",function()self:Event()end)
    self.registration=ok and "registered" or "failed"
    self.cdmRegistrations={}
    for _,event in ipairs({"PLAYER_REGEN_DISABLED","PLAYER_REGEN_ENABLED","PLAYER_ENTERING_WORLD","UNIT_AURA","COOLDOWN_VIEWER_DATA_LOADED","COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED","COOLDOWN_VIEWER_TABLE_HOTFIXED"}) do
        local name=event
        local subscribed=pcall(self.events.Subscribe,self.events,self,name,function(_,unit)
            if not self.active then return end
            if name=="UNIT_AURA" then local value,status=self:Scalar(unit,"string");if status~="readable" or value~="player" then return end end
            self:CDMSnapshot(name,name=="PLAYER_REGEN_DISABLED" or name=="PLAYER_REGEN_ENABLED")
        end)
        self.cdmRegistrations[name]=subscribed and "registered" or "failed"
    end
    -- Restriction event fires before activation: classify current state on next delivered event or report.
    self:CDMSnapshot("start");return true
end
function D:Stop()
    if not self.active then return false,"not running" end
    self:CDMSnapshot("stop");self.events:Release(self);self.active=false;self.collector:SetRecording(false);self.finished=self.collector:Now()
    self.frozenReport=self:Report();return true
end
local statusLabel=ns.GraphValues.StatusLabel
local function counts(values,frameAccess)
    local keys,out={},{};for key in pairs(values or {}) do keys[#keys+1]=key end;table.sort(keys)
    for _,key in ipairs(keys) do out[#out+1]=(frameAccess and key=="protected" and "access-restricted-or-secret" or type(key)=="string" and statusLabel(key) or key).."="..values[key] end
    return #out>0 and table.concat(out,",") or "none"
end
function D:BuildIdentity()
    local out={version="unknown",build="unknown",interface="unknown",addon="unknown"}
    local function safe(value,kind)
        local parsed,status=self:Scalar(value,kind)
        if status~="readable" then return "unknown" end
        if kind=="number" then return tostring(parsed) end
        if #parsed>64 or not parsed:match("^[%w%.%-%_]+$") then return "unknown" end
        return parsed
    end
    if self:Function(self.api.GetBuildInfo) then
        local ok,version,build,_,interface=pcall(self.api.GetBuildInfo)
        if ok then out.version=safe(version,"string");out.build=safe(build,"string");out.interface=safe(interface,"number") end
    end
    local value,status=self:Query(self.api.C_AddOns,"GetAddOnMetadata","BVAddonSuite_AuraStudio","Version")
    if status=="missing" and self:Function(self.api.GetAddOnMetadata) then
        local ok;ok,value=pcall(self.api.GetAddOnMetadata,"BVAddonSuite_AuraStudio","Version");status=ok and "success" or "error"
    end
    if status=="success" then out.addon=safe(value,"string") end
    return out
end
local function fieldText(field)
    if not field then return "not-read" end
    return statusLabel(field.status)..(field.value~=nil and "="..tostring(field.value) or "")
end
local function auraRow(row)
    local fields={}
    for _,name in ipairs({"issecretvalue","issecrettable","canaccesstable"}) do fields[#fields+1]=name..":"..fieldText(row.access and row.access[name]) end
    for _,name in ipairs({"spellId","spellID","auraInstanceID","isHelpful","isHarmful","applications","duration","expirationTime"}) do
        fields[#fields+1]=name..":"..fieldText(row.fields and row.fields[name])
    end
    return "query="..statusLabel(row.query or "not-read").." raw="..statusLabel(row.raw or "not-read").." "..table.concat(fields," ")
end
function D:AuraReport(lines,paths)
    lines[#lines+1]="  Aura paths: requests="..#paths.requests.." skipped="..paths.skippedRequests.." requestsTruncated="..tostring(paths.requestsTruncated).." reads="..paths.reads.."/128"
    for _,request in ipairs(paths.requests) do
        lines[#lines+1]="    Request "..request.unit.." "..request.filter.." spellID="..request.spellID.." transport="..tostring(request.transport).." origin="..request.origin
        lines[#lines+1]="      C_Secrets.ShouldSpellAuraBeSecret: "..fieldText(request.restriction)
        lines[#lines+1]="      C_UnitAuras.GetPlayerAuraBySpellID: "..auraRow(request.playerGetter)
        lines[#lines+1]="      C_UnitAuras.GetUnitAuraBySpellID: "..auraRow(request.unitGetter)
    end
    for _,scan in ipairs(paths.scans) do
        for _,item in ipairs({{"list","GetUnitAuras"},{"instances","GetUnitAuraInstanceIDs -> GetAuraDataByAuraInstanceID"},{"index","GetAuraDataByIndex"}}) do
            local path=scan[item[1]]
            lines[#lines+1]="    C_UnitAuras."..item[2].."("..scan.unit..","..scan.filter.."): query="..statusLabel(path.query).." raw="..statusLabel(path.raw).." entries="..#path.entries.." complete="..tostring(path.complete).." limit="..(path.limit or "none").." fields["..counts(path.fields).."]"
            lines[#lines+1]="      Columns: index; query/raw (ok=success/readable); spellId/spellID/auraInstanceID/isHelpful/isHarmful (plain values=readable). Optional numeric fields and raw access flags are summarized above."
            for _,row in ipairs(path.entries) do
                local values={}
                for _,name in ipairs({"spellId","spellID","auraInstanceID","isHelpful","isHarmful"}) do
                    local f=row.fields and row.fields[name];values[#values+1]=f and f.status=="readable" and tostring(f.value) or fieldText(f)
                end
                local state=row.query=="success" and row.raw=="readable" and "ok" or statusLabel(row.query or "not-read").."/"..statusLabel(row.raw or "not-read")
                lines[#lines+1]="      ["..row.index.."] "..(row.instanceStatus and "instanceID="..statusLabel(row.instanceStatus) or (row.instance and "instanceID="..row.instance.." " or "")..state.."; "..table.concat(values,"/"))
            end
        end
    end
end
function D:Report()
    if self.frozenReport then return self.frozenReport end
    local identity=self.identity or {}
    local lines={"BV information diagnostics v4","Session only; public APIs; no aura prediction or secret payload retained.",
        "BuildInfo: version="..(identity.version or "unknown").." build="..(identity.build or "unknown").." interface="..(identity.interface or "unknown").." AddOnVersion="..(identity.addon or "unknown"),
        "State: "..(self.active and "running" or self.started and "stopped" or "not started"),
        "Combat log registration: "..(self.registration or "not attempted"),"Combat log restriction: "..statusLabel(self.restriction or "not sampled"),
        "Public getter available: "..tostring(self.getter~=nil),
        "Delivered: "..(self.delivered or 0).."; sampled: "..(self.sampled or 0).."; skipped: "..(self.skipped or 0),
        "Getter unavailable/restricted: "..(self.unavailable or 0).."; getter errors: "..(self.errors or 0),
        "Readability uses conventional CLEU field positions; no payload interpretation or native schema certification."}
    lines[#lines+1]="Target CDM adapter (actual source captures; not node output): latest 4 request slots; no additional native reads; no GUID values."
    self:TargetAdapterReport(lines,self:TargetAdapterSnapshot(),self.active and self.collector:Now() or self.finished or self.collector:Now(),"Latest")
    local targetManual=0
    for _,snap in ipairs(self.cdmSnapshots or {}) do
        if snap.reason=="manual" then targetManual=targetManual+1;self:TargetAdapterReport(lines,snap.targetAdapterRows,snap.time,"Manual sample "..targetManual) end
    end
    local keys={};for key in pairs(self.readability or {}) do keys[#keys+1]=key end;table.sort(keys)
    for _,key in ipairs(keys) do lines[#lines+1]=key..": "..statusLabel(self.readability[key]) end
    local summary=self.collector:Summary()
    lines[#lines+1]="Cached scopes: "..summary.count.."; observation metadata history: "..summary.historyCount.." / 256"
    local sources={};for source in pairs(summary.sources) do sources[#sources+1]=source end;table.sort(sources)
    for _,source in ipairs(sources) do local s=summary.sources[source];lines[#lines+1]="Source "..source..": "..s.count.." scopes; status "..statusLabel(s.lastStatus) end
    local cdm=self.collector:Read("capability","cdm")
    for _,key in ipairs({"namespace","categoryQuery","infoQuery","buffIconViewer","buffBarViewer"}) do
        local f=cdm.fields[key];lines[#lines+1]="CDM "..key..": "..(f and f.status=="readable" and statusLabel(tostring(f.value)) or "unknown")
    end
    lines[#lines+1]="CDM snapshots: "..#(self.cdmSnapshots or {}).." / 32; skipped: "..(self.cdmSkipped or 0).."; learned entries only; max 32 IDs/category, 64 unique inventories, 128 linked slots/entry, 1024 linked slots/snapshot. Limits per viewer: 64 unique frames + root, 128 candidate slots, 64 pool iterator steps, depth 4; existing pool and nested children only."
    lines[#lines+1]="Aura limits/snapshot: 4 requests, 4 unit/filter scans, 12 list entries + 12 instance IDs + 8 index entries/filter; 128 slot/lookup reads total; up to 8 collection queries. Completeness only marks an observed sequence end, never proves aura absence."
    lines[#lines+1]="CDM event registration: "..counts(self.cdmRegistrations)
    -- All explicit samples fit before verbose inventories, even when only the
    -- first 60 kB copy page is supplied. Event snapshots are not manual samples.
    local manual=0
    for i,snap in ipairs(self.cdmSnapshots or {}) do
        if snap.reason=="manual" then
            manual=manual+1
            local values={}
            for _,name in ipairs({"icon","bar"}) do
                for _,row in ipairs(snap[name].matchedFrames) do
                    values[#values+1]=name..":"..row.cooldownID.." active="..fieldText(row.activeMethod).." instance="..fieldText(row.auraInstanceID)
                end
            end
            lines[#lines+1]="Manual sample "..manual.." -> CDM #"..i.." phase="..snap.phase.." time="..(snap.time or "unknown").." "..table.concat(values,"; ")
        end
    end
    for i,snap in ipairs(self.cdmSnapshots or {}) do
        local snapshotStart=#lines+1
        lines[#lines+1]="CDM #"..i.." "..snap.reason.." phase="..snap.phase.." time="..(snap.time or "unknown").." restriction="..statusLabel(snap.restriction or "unknown").." namespace="..statusLabel(snap.namespace).." available="..statusLabel(snap.available)
        -- Put the focused viewer evidence before verbose aura/catalog details so
        -- report truncation cannot discard the reason this diagnostic exists.
        for _,name in ipairs({"icon","bar"}) do
            local v=snap[name];lines[#lines+1]="  "..name.." viewer="..(v.status=="protected" and "access-restricted-or-secret" or statusLabel(v.status)).." children="..v.children.." truncated="..tostring(v.truncated).." matches="..v.matches.." active["..counts(v.active).."] shown["..counts(v.shown).."] childIDs["..counts(v.ids,true).."] pool="..statusLabel(v.pool or "not-read").." poolSteps="..v.poolSteps.." visited="..v.visited.." slots="..v.slots.." duplicates="..v.duplicates.." traversal["..counts(v.traversal,true).."] observedIDs["..counts(v.observedIDs).."] limits["..counts(v.limits).."]"
            for _,row in ipairs(v.matchedFrames) do lines[#lines+1]="    cooldownID="..row.cooldownID.." via="..row.source.." depth="..row.depth.." idSource="..row.idSource.." isActive="..fieldText(row.active).." IsActive()="..fieldText(row.activeMethod).." IsShown="..fieldText(row.shown).." auraInstanceID="..fieldText(row.auraInstanceID) end
        end
        self:AuraReport(lines,snap.auraPaths)
        for _,row in ipairs(snap.categories) do
            lines[#lines+1]="  "..row.name..": "..statusLabel(row.status).." entries="..row.count.." truncated="..tostring(row.truncated).." IDs["..counts(row.ids).."] info["..counts(row.info).."]"
        end
        local spells={};for spell in pairs(snap.targetMappings) do spells[#spells+1]=spell end;table.sort(spells)
        for _,spell in ipairs(spells) do
            local mappings={};for id in pairs(snap.targetMappings[spell]) do mappings[#mappings+1]=id end;table.sort(mappings)
            for j,id in ipairs(mappings) do mappings[j]=tostring(id) end
            lines[#lines+1]="  Spell "..spell.." mapping="..(#mappings>0 and table.concat(mappings,",") or "unknown").." info["..counts(snap.info).."]"
        end
        lines[#lines+1]="  CDM inventory: "..#snap.inventories.."/64 unique entries; truncated="..tostring(snap.inventoryTruncated==true).." linkedSlots="..snap.linkedSlots.."/1024"
        for _,entry in ipairs(snap.inventories) do
            local linked={};for j,id in ipairs(entry.linked) do linked[j]=tostring(id) end
            lines[#lines+1]="    cooldownID="..entry.cooldownID.." category="..entry.category.." spellID="..fieldText(entry.spellID).." overrideSpellID="..fieldText(entry.overrideSpellID).." selfAura="..fieldText(entry.selfAura).." hasAura="..fieldText(entry.hasAura).." linked="..statusLabel(entry.linkedStatus).."["..table.concat(linked,",").."] complete="..tostring(entry.linkedComplete).." limit="..(entry.linkedLimit or "none")
        end
        local names={};for name in pairs(snap.fields) do names[#names+1]=name end;table.sort(names)
        local fields={};for _,name in ipairs(names) do fields[#fields+1]=name.."["..counts(snap.fields[name]).."]" end
        lines[#lines+1]="  Info field readability: "..table.concat(fields," ")
        -- Keep every snapshot visible within the report window's 1.2 MB cap.
        -- This affects presentation only; sampled metadata remains untouched.
        local bytes=0;for line=snapshotStart,#lines do bytes=bytes+#lines[line]+1 end
        if bytes>32000 then
            while bytes>31800 do bytes=bytes-#lines[#lines]-1;lines[#lines]=nil end
            lines[#lines+1]="  REPORT TRUNCATED: snapshot detail limit 32000 bytes; observations retained in session. Some detail rows omitted."
        end
    end
    lines[#lines+1]="Missing mapping is unknown, never buff absence. hasAura is metadata; active/shown are observed viewer fields, not certified player aura state. Events may precede Blizzard refresh; no deferred polling. Stop freezes this report."
    lines[#lines+1]="Registration or zero events alone proves neither accessibility nor absence. No CDM UI loaded, enabled, or changed."
    return table.concat(lines,"\n")
end
function D:Command(command)
    if command=="start" then
        local ok,why=self:Start();if not ok then return false,why end
        ns:Print("Information diagnostics started. Use /bv info sample after an action; then stop and report.")
        return true
    elseif command=="sample" then
        local ok,why=self:CDMSnapshot("manual")
        if not ok then return false,why end
        ns:Print("CDM information snapshot recorded.")
        return true
    elseif command=="stop" then
        local ok,why=self:Stop();if not ok then return false,why end
        ns:Print("Information diagnostics stopped. Use /bv info report to view the results.")
        return true
    elseif command=="clear" then
        self:Stop();self.collector:Clear();self.started=nil;self.registration=nil;self.readability={};self.delivered=0;self.sampled=0;self.skipped=0;self.unavailable=0;self.errors=0
        self.frozenReport=nil;self.targetAdapterRows={};self.cdmSnapshots={};self.cdmSkipped=0;self.cdmRegistrations={};self.getter=nil;self.restriction=nil;self.finished=nil;self.identity=nil
        ns:Print("Information diagnostics cleared.")
        return true
    elseif command~="report" and command~="" then return false,"Use start, sample, stop, report or clear." end
    ns.UI:DiagnosticReport("Information diagnostics",self:Report());return true
end
A.infoDiagnostics=D.New()
