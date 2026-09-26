-- All client data stops here. Only plain, checked values leave this adapter.
local _,A=...
if A.blocked then return end
local G=A.G
local Source={}; Source.__index=Source; A.AuraSource=Source
function Source.New(api) return setmetatable({api=api or _G},Source) end
function Source.Key(id,filter,unit) return (unit and unit~="player" and unit..":" or "")..filter..":"..id end
function Source:Secret(v)
    if self.api.issecretvalue then local ok,value=pcall(self.api.issecretvalue,v);if not ok or value then return true end end
    if type(v)=="table" then
        if self.api.issecrettable then local ok,value=pcall(self.api.issecrettable,v);if not ok or value then return true end end
        if self.api.canaccesstable then local ok,value=pcall(self.api.canaccesstable,v);if not ok or not value then return true end end
    end
    local classified,hidden=pcall(G.IsSecret,v);if not classified or hidden then return true end
    return false
end
function Source:ReadableTable(v)
    return not self:Secret(v) and type(v)=="table" and getmetatable(v)==nil
end
function Source:Number(v)
    if self:Secret(v) then return nil,"protected" end
    if G.Number(v) and v>=0 then return v,"readable" end
    return nil,"unavailable"
end
function Source:Text(v)
    if self:Secret(v) or type(v)~="string" then return nil end
    return v:sub(1,256)
end
function Source:Data(raw,filter,transport,expectedID)
    if not self:ReadableTable(raw) then return nil,"protected" end
    local id=self:Number(raw.spellId)
    if not id or id<1 or id~=math.floor(id) then
        if transport and expectedID then id=expectedID else return nil,"protected identity" end
    end
    local out={spellID=id,name=self:Text(raw.name),filter=filter,fields={}}
    local instance=self:Number(raw.auraInstanceID)
    if instance and instance>0 and instance==math.floor(instance) then out.auraInstanceID=instance end
    -- Reuse metadata already returned by the aura observation; never resolve a
    -- spell texture here. Arbitrary spell-icon queries can assert in the client.
    local icon=self:Number(raw.icon)
    if icon and icon>0 and icon==math.floor(icon) then out.icon=icon end
    if not filter then
        if not self:Secret(raw.isHelpful) and raw.isHelpful==true then out.filter="HELPFUL"
        elseif not self:Secret(raw.isHarmful) and raw.isHarmful==true then out.filter="HARMFUL" end
    end
    out.stacks,out.fields.stacks=self:Number(raw.applications)
    if out.stacks and out.stacks~=math.floor(out.stacks) then out.stacks=nil; out.fields.stacks="invalid" end
    out.duration,out.fields.duration=self:Number(raw.duration)
    out.expirationTime,out.fields.remaining=self:Number(raw.expirationTime)
    out.fields.hasExpiration=out.fields.remaining
    if out.expirationTime then
        out.hasExpiration=out.expirationTime>0
        if not out.hasExpiration then out.fields.remaining="permanent" end
    end
    if transport then
        for key,field in pairs({stacks="applications",duration="duration",texture="icon"}) do
            local value=raw[field]
            if self:Secret(value) then out[key]=G.Capture(value,key=="duration" and "float" or "integer",function()return true end);out.fields[key]="protected"
            elseif key=="texture" then out[key],out.fields[key]=self:Number(value) end
        end
    end
    return out
end
function Source:Browse(unit,transport,budget)
    unit=unit or "player"
    local out={items={},complete={},status={}}
    if not A.UnitSource.ValidToken(unit) then return out end
    local api=self.api.C_UnitAuras
    local query=api and api.GetAuraDataByIndex
    for _,filter in ipairs({"HELPFUL","HARMFUL"}) do
        out.status[filter]="API missing"
        if query then
            out.status[filter]="scan limit (128)"
            local hidden=false
            for index=1,128 do
                if budget and budget.remaining<=0 then out.status[filter]="source scan limit";break end
                if budget then budget.remaining=budget.remaining-1 end
                local ok,raw=pcall(query,unit,index,filter)
                if not ok then out.status[filter]="API error / access denied"; break end
                if self:Secret(raw) then hidden=true
                elseif raw==nil then
                    out.complete[filter]=not hidden
                    out.status[filter]=hidden and "protected identities" or "readable scan"
                    break
                else
                    local parsed,data=pcall(self.Data,self,raw,filter,transport)
                    if parsed and data then data.unit=unit; data.index=index; out.items[#out.items+1]=data else hidden=true end
                end
            end
        end
    end
    return out
end
-- Public collection APIs can expose a readable identity even when the direct
-- spell lookup does not. Never infer a spell from a secret instance or icon.
-- One capture shares this bounded scan across all requested spells on a unit.
function Source:PublicBrowse(unit,transport,budget)
    local out={items={},complete={},status={}}
    local api=self.api.C_UnitAuras or {}
    local list=type(api.GetUnitAuras)=="function" and api.GetUnitAuras
    local ids=type(api.GetUnitAuraInstanceIDs)=="function" and type(api.GetAuraDataByAuraInstanceID)=="function" and api.GetUnitAuraInstanceIDs
    out.available=not not (list or ids)
    if not out.available or not A.UnitSource.ValidToken(unit) then return out end
    local function take()
        if budget.remaining<=0 then return false end
        budget.remaining=budget.remaining-1;return true
    end
    for _,filter in ipairs({"HELPFUL","HARMFUL"}) do
        for mode=1,2 do
            local query
            if mode==1 then query=list else query=ids end
            if query then
                out.status[filter]="source scan limit"
                if take() then
                    local ok,values
                    if mode==1 then ok,values=pcall(query,unit,filter,128)
                    else ok,values=pcall(query,unit,filter) end
                    if not ok then out.status[filter]="API error / access denied"
                    elseif not self:ReadableTable(values) then out.status[filter]="protected collection"
                    else
                        local hidden=false
                        out.status[filter]="scan limit (128)"
                        for index=1,128 do
                            if not take() then out.status[filter]="source scan limit";break end
                            local raw=rawget(values,index)
                            if self:Secret(raw) then hidden=true
                            elseif raw==nil then
                                out.complete[filter]=out.complete[filter] or not hidden
                                out.status[filter]=hidden and "protected identities" or "readable scan"
                                break
                            else
                                local readable=true
                                local instance
                                if mode==2 then
                                    instance=self:Number(raw)
                                    if instance and instance>0 and instance==math.floor(instance) then
                                        if take() then readable,raw=pcall(api.GetAuraDataByAuraInstanceID,unit,instance)
                                        else readable=false;out.status[filter]="source scan limit" end
                                    else readable=false end
                                end
                                local parsed,data
                                if readable then parsed,data=pcall(self.Data,self,raw,filter,transport) end
                                if parsed and data and (not instance or data.auraInstanceID==instance) then
                                    data.unit=unit;out.items[#out.items+1]=data
                                else hidden=true end
                            end
                        end
                    end
                end
            end
        end
    end
    return out
end
function Source:Inspect(observed)
    if not observed or not A.UnitSource.ValidToken(observed.unit) then return end
    local unit=observed.unit
    local api=self.api.C_UnitAuras or {}; local raw,ok
    local byInstance=observed.auraInstanceID and type(api.GetAuraDataByAuraInstanceID)=="function"
    if byInstance then ok,raw=pcall(api.GetAuraDataByAuraInstanceID,unit,observed.auraInstanceID)
    elseif observed.index and type(api.GetAuraDataByIndex)=="function" then ok,raw=pcall(api.GetAuraDataByIndex,unit,observed.index,observed.filter) end
    if not ok then return end
    local parsed,data=pcall(self.Data,self,raw,observed.filter)
    if not parsed or not data or data.spellID~=observed.spellID then return end
    if observed.auraInstanceID and data.auraInstanceID~=observed.auraInstanceID then return end
    data.unit=unit; if not byInstance then data.index=observed.index end
    return data
end
function Source:Restriction(id)
    local api=self.api.C_Secrets
    if api and api.ShouldSpellAuraBeSecret then
        local ok,value=pcall(api.ShouldSpellAuraBeSecret,id)
        if ok and not self:Secret(value) and type(value)=="boolean" then return value end
    end
    -- Older clients without the secret-value system still have readable scans.
    if not self.api.issecretvalue then return false end
    return nil
end
function Source:ResetTargetEstimates()
    self.targetEstimateMemory=nil;self.targetEstimateOrder=nil;self.targetEstimateGUID=nil
end
function Source:TargetEstimateCombat()
    local fn=self.api.InCombatLockdown
    if self:Secret(fn) or type(fn)~="function" then return end
    local ok,value=pcall(fn)
    if not ok or self:Secret(value) or type(value)~="boolean" then return end
    if self.targetEstimateCombat==true and not value then self:ResetTargetEstimates() end
    self.targetEstimateCombat=value
    return value
end
function Source:ApplyTargetEstimate(result,request,guid,at,combat)
    if not guid or combat==nil or result.status=="binding changed" then return end
    if not combat and self.targetEstimateGUID~=guid then self:ResetTargetEstimates() end
    self.targetEstimateGUID=guid
    local key=guid..":"..request.spellID..":"..request.filter
    local memory=self.targetEstimateMemory or {};local order=self.targetEstimateOrder or {}
    self.targetEstimateMemory=memory;self.targetEstimateOrder=order
    local old=memory[key]
    local values=result.values or {};local present=values.present
    if G.IsSecret(present) or type(present)~="boolean" then present=result.cdmTargetObservation end
    local entry=old and G.Copy(old) or nil
    if type(present)=="boolean" then
        entry=entry or {};entry.present=present;entry.presenceAt=at
        if not present then
            if values.present==false then entry.duration=nil;entry.instance=nil end
            entry.deadline=nil;entry.observedAt=nil
        else
            local instance=result.auraInstanceID
            if instance and entry.instance and instance~=entry.instance then entry.duration=nil;entry.deadline=nil;entry.observedAt=nil end
            if instance then entry.instance=instance end
            local permanent=not G.IsSecret(values.hasExpiration) and values.hasExpiration==false
            if permanent then entry.duration=nil;entry.deadline=nil;entry.observedAt=nil end
            local duration=self:Number(values.duration)
            if duration then entry.duration=duration end
            local expiry=self:Number(result.expirationTime)
            local remaining=self:Number(values.remaining)
            if expiry and expiry>0 then entry.deadline=expiry;entry.observedAt=at
            elseif not permanent and remaining and at then entry.deadline=at+remaining;entry.observedAt=at end
        end
    end
    if not entry then return end
    -- Retain an expired deadline as a tombstone. A current public true may
    -- outlive it, but a later memory-only read must still know time ran out.
    if entry.deadline and at and entry.deadline<=at and present~=true then entry.present=false end
    if not old then
        if #order>=256 then memory[table.remove(order,1)]=nil end
        order[#order+1]=key
    end
    memory[key]=entry
    result.targetEstimate={present=entry.present,duration=entry.duration,deadline=entry.deadline,
        observedAt=entry.observedAt,memoryOnly=present==nil}
end
-- Display-only timing. Secret arguments are forwarded unchanged to native APIs;
-- no time/instance comparison, string conversion, arithmetic or persistence.
function Source:RealTime(unit,instance,raw)
    local api=self.api.C_UnitAuras or {}
    local hidden=self:Secret(instance)
    if (hidden or self:Number(instance)) and type(api.GetAuraDuration)=="function" then
        local ok,value=pcall(api.GetAuraDuration,unit,instance)
        if ok and not self:Secret(value) and (type(value)=="table" or type(value)=="userdata") then
            return G.CaptureObject(value,"duration")
        end
    end
    if not self:ReadableTable(raw) then return end
    return self:RealTimeFromTimes(raw.expirationTime,raw.duration,raw.timeMod)
end
function Source:RealTimeFromTimes(expiration,duration,rate)
    local function number(value) return self:Secret(value) or self:Number(value)~=nil end
    if not number(expiration) or not number(duration) then return end
    if not self:Secret(rate) and rate==nil then rate=1 end
    if not number(rate) then return end
    local api=self.api.C_DurationUtil
    if not api or type(api.CreateDuration)~="function" then return end
    local ok,value=pcall(function()
        local object=api.CreateDuration()
        object:SetTimeFromEnd(expiration,duration,rate)
        return object
    end)
    if ok and not self:Secret(value) and (type(value)=="table" or type(value)=="userdata") then
        return G.CaptureObject(value,"duration")
    end
end
function Source:Capture(requests)
    local out={}; if not next(requests) then return out end
    -- Stable capture metadata survives cached snapshots; clock/UI work must not
    -- turn an old remaining-time sample into a new countdown baseline.
    self.captureSerial=(self.captureSerial or 0)+1
    local observedAt
    if type(self.api.GetTime)=="function" then
        local ok,value=pcall(self.api.GetTime)
        if ok then observedAt=self:Number(value) end
    end
    local api=self.api.C_UnitAuras
    local scans,publicScans={},{};local scanBudget={remaining=256}
    -- One lazy, bounded viewer snapshot per capture is shared by every aura.
    local cdm=A.CDMSource and A.CDMSource.New(self)
    local diagnostics=A.infoDiagnostics
    local traceRows=diagnostics and diagnostics.active and {} or nil
    local traceCount=0
    local targetCombat,targetCombatRead
    -- Deduplicate both direct reads and fallback scans across nodes/graphs.
    local reads={}; local count=0; local keys={}
    for key in pairs(requests) do keys[#keys+1]=key end
    table.sort(keys)
    for _,key in ipairs(keys) do
        local request=requests[key]
        local id,filter=request.spellID,request.filter
        local unit=request.unit or "player";local transport=request.transport==true
        local direct=api and (unit=="player" and api.GetPlayerAuraBySpellID or api.GetUnitAuraBySpellID)
        local result={status="unavailable"}; out[key]=result
        local trace
        if traceRows and unit=="target" and traceCount<4 then
            trace=diagnostics:BeginTargetAdapter(self,request,observedAt)
            traceRows[key]=trace;traceCount=traceCount+1
        end
        if cdm then
            cdm.trace=trace
            if unit=="target" then
                if not targetCombatRead then targetCombatRead=true;targetCombat=self:TargetEstimateCombat() end
                cdm:TargetContextCurrent()
            end
        end
        local readKey=unit..":"..id..":"..tostring(transport)
        local read=reads[readKey]
        if not read then
            count=count+1
            if not A.UnitSource.ValidToken(unit) then out[key]={status="invalid unit"}
            elseif count>128 then
                out[key]={status="source limit (128 IDs)"}
            else
                read={}; reads[readKey]=read
                if direct then
                    local ok,raw
                    if unit=="player" and direct==api.GetPlayerAuraBySpellID then ok,raw=pcall(direct,id)else ok,raw=pcall(direct,unit,id)end
                    if not ok then read.reason="API error / access denied"
                    elseif self:Secret(raw) then read.reason="protected"
                    elseif raw==nil then read.empty=true
                    else
                        local parsed,data=pcall(self.Data,self,raw,nil,transport,id)
                        if parsed and data then read.data=data;read.raw=raw else read.reason="protected identity" end
                    end
                end
            end
        end
        if read then
            local scanKey=unit..":"..tostring(transport);local scan=scans[scanKey]
            local data=read.data
            if data and (data.spellID~=id or data.filter~=filter) then data=nil end
            -- The player-specific getter and the unit getter are independent
            -- public entry points. An unusable first reply must not suppress
            -- readable positive evidence from GetUnitAuraBySpellID("player").
            -- Cache this reply separately: another requested filter may still
            -- use the primary reply. A nil alternative never proves absence.
            if not data and unit=="player" and api and type(api.GetUnitAuraBySpellID)=="function" and direct~=api.GetUnitAuraBySpellID then
                if not read.alternativeRead then
                    read.alternativeRead=true
                    local ok,raw=pcall(api.GetUnitAuraBySpellID,unit,id)
                    if ok and not self:Secret(raw) and raw~=nil then
                        local parsed,alternative=pcall(self.Data,self,raw,nil,transport,id)
                        if parsed and alternative then read.alternativeData=alternative;read.alternativeRaw=raw end
                    end
                end
                local alternative=read.alternativeData
                if alternative and alternative.spellID==id and alternative.filter==filter then data=alternative end
            end
            local public=publicScans[scanKey]
            if not data then
                public=public or self:PublicBrowse(unit,transport,scanBudget);publicScans[scanKey]=public
                for _,item in ipairs(public.items) do
                    if item.spellID==id and item.filter==filter then data=item;break end
                end
            end
            if not data then
                scan=scan or self:Browse(unit,transport,scanBudget);scans[scanKey]=scan
                for _,item in ipairs(scan.items) do
                    if item.spellID==id and item.filter==filter then data=item; break end
                end
            end
            if data then
                result.values={present=true,stacks=data.stacks,duration=data.duration,hasExpiration=data.hasExpiration,texture=data.texture}
                result.expirationTime=data.expirationTime
                result.auraInstanceID=data.auraInstanceID;result.unit=unit
                result.fields=data.fields
                result.status=(data.stacks==nil or data.duration==nil) and "present / partial" or "present"
                if request.realTime then
                    local raw=data==read.data and read.raw or data==read.alternativeData and read.alternativeRaw or nil
                    local instance=data.auraInstanceID
                    if raw then instance=raw.auraInstanceID end
                    result.values.realTime=self:RealTime(unit,instance,raw)
                end
            else
                local restricted=self:Restriction(id)
                -- Foreign-unit direct queries may return nil for blocked or
                -- invisible auras; only a completed readable scan proves absence.
                local complete=(unit=="player" and api and direct==api.GetPlayerAuraBySpellID and direct and read.empty and not (public and public.available))
                    or (public and public.complete[filter]) or (scan and scan.complete[filter])
                if restricted==false and complete then
                    result.values={present=false}; result.status="absent"
                elseif restricted==true then result.status="protected"
                else
                    local scanStatus=scan and scan.status[filter]
                    if direct and read.empty and scanStatus=="API missing" then scanStatus=nil end
                    result.status=read.reason or (public and public.status[filter]) or scanStatus or "absence unverified"
                end
                if not result.values and result.status=="readable scan" then result.status="absence unverified" end
                if result.values then result.fields={stacks="absent",duration="absent",remaining="absent",hasExpiration="absent"} end
            end
            if trace then trace.beforePresent=diagnostics:TargetPresence(result) end
            if cdm and (unit=="player" or unit=="target") then
                local values=result.values
                local needs=not values or values.present==nil
                if values and values.present==true then
                    for _,field in ipairs({"stacks","duration","texture","hasExpiration"}) do
                        if values[field]==nil or G.IsSecret(values[field]) then needs=true end
                    end
                    if result.expirationTime==nil and values.remaining==nil then needs=true end
                end
                if needs then
                    if trace then trace.adapter="invoked" end
                    cdm:Fill(result,id,filter,transport,unit)
                end
                if request.realTime and (not result.values or result.values.present~=false) then
                    result.values=result.values or {};result.fields=result.fields or {}
                    result.values.realTime=result.values.realTime or cdm:RealTime(id,filter,unit)
                    result.fields.realTime=result.values.realTime and "protected" or "unavailable"
                end
            end
        end
    end
    -- A reentrant public API can replace the target after an earlier request
    -- already produced evidence. Revoke that whole target batch before Studio
    -- caches it; later-request checks alone would leave the earlier result stale.
    if cdm and cdm:TargetContextChanged() then
        for key,request in pairs(requests) do
            if request.unit=="target" then out[key]={status="binding changed"} end
        end
    end
    if cdm and cdm.targetContext then
        for _,key in ipairs(keys) do
            local request=requests[key]
            if request.unit=="target" then
                out[key].targetEstimateManaged=true
                self:ApplyTargetEstimate(out[key],request,cdm.targetContext.guid,observedAt,targetCombat)
            end
        end
    end
    if traceRows then
        for _,key in ipairs(keys) do
            local trace=traceRows[key]
            if trace then
                local observation=out[key]
                trace.beforePresent=trace.beforePresent or diagnostics:TargetPresence(observation)
                trace.afterPresent=diagnostics:TargetPresence(observation);trace.hint=observation.cdmPresence==true
                if observation.status=="binding changed" then trace.adapter="binding changed" end
                diagnostics:PublishTargetAdapter(trace)
            end
        end
    end
    for _,observation in pairs(out) do
        observation.observedAt=observedAt
        observation.captureSerial=self.captureSerial
    end
    return out
end
