-- Event-time observations for a future timeline. No combat analysis or renderer.
local _,A=...
if A.blocked then return end
local ns=BVAddonSuiteCore
local R={};R.__index=R;A.SessionRecorder=R
local castSchemas={}
for _,suffix in ipairs({"START","STOP","SUCCEEDED","FAILED","FAILED_QUIET","DELAYED","CHANNEL_START","CHANNEL_UPDATE","EMPOWER_START","EMPOWER_UPDATE"}) do
    castSchemas["UNIT_SPELLCAST_"..suffix]={"unit","castGUID","spellID","castBarID"}
end
castSchemas.UNIT_SPELLCAST_SENT={"unit","target","castGUID","spellID"}
castSchemas.UNIT_SPELLCAST_CHANNEL_STOP={"unit","castGUID","spellID","interruptedBy","castBarID"}
castSchemas.UNIT_SPELLCAST_INTERRUPTED={"unit","castGUID","spellID","interruptedBy","castBarID"}
castSchemas.UNIT_SPELLCAST_EMPOWER_STOP={"unit","castGUID","spellID","complete","interruptedBy","castBarID"}
castSchemas.UNIT_SPELLCAST_INTERRUPTIBLE={"unit"}
castSchemas.UNIT_SPELLCAST_NOT_INTERRUPTIBLE={"unit"}
castSchemas.UNIT_SPELLCAST_RETICLE_CLEAR={"unit","castGUID","spellID"}
castSchemas.UNIT_SPELLCAST_RETICLE_TARGET={"unit","castGUID","spellID"}
local fixed={player=true,pet=true,target=true,targettarget=true,focus=true,focustarget=true}
local baseEntries={UnitExists=true,UnitName=true,UnitGUID=true,UnitHealth=true,UnitHealthMax=true,UnitPower=true,UnitPowerMax=true}
local castEntries={UnitCastingInfo=true,UnitChannelInfo=true,UnitCastingDuration=true,UnitChannelDuration=true,UnitEmpoweredChannelDuration=true}
local auraEntries={getUnitAuras=true,debuffs=true}
local auraFields={"auraInstanceID","spellId","name","icon","applications","dispelName","duration","expirationTime","sourceUnit","isHelpful","isHarmful","isFromPlayerOrPlayerPet"}
local function errorField(status) return {status=status or "error",type="unknown"} end
function R.New(api,events,printer,options)
    options=options or {}
    return setmetatable({api=api,events=events,print=printer or function()end,
        core=options.recorder or ns.Recorder.New(api),probe=options.probe,
        rateLimit=math.max(1,math.min(60,options.maxEventsPerSecond or 60)),
        auraLimit=math.max(1,math.min(8,options.maxAuraRecords or 8)),epoch=0},R)
end
function R:Field(value) return self.core:Observe(value) end
function R:Read(fn,...)
    if type(fn)~="function" then return errorField("unsupported") end
    local ok,value=pcall(fn,...)
    if not ok then return errorField() end
    return self:Field(value)
end
function R:Table(value)
    local field=self:Field(value)
    if field.status=="protected" then return nil,"protected" end
    if type(value)~="table" then return nil,field.status end
    for _,name in ipairs({"canaccesstable","issecrettable"}) do
        local fn=self.api[name]
        if type(fn)=="function" then
            local ok,result=pcall(fn,value)
            if not ok or type(result)~="boolean" or (name=="canaccesstable" and not result) or (name=="issecrettable" and result) then return nil,"protected" end
        end
    end
    if getmetatable(value) then return nil,"opaque" end
    return value
end
function R:Member(value,key)
    local raw,why=self:Table(value)
    if not raw then return nil,why end
    local ok,result=pcall(function()return raw[key]end)
    if not ok then return nil,"error" end
    return result
end
function R:Unit(raw)
    local field=self:Field(raw)
    if field.status~="readable" or field.type~="string" then return nil,field end
    local unit=field.value
    if fixed[unit] then return unit,field end
    for prefix,max in pairs({party=4,raid=40,nameplate=40,boss=8}) do
        local index=unit:match("^"..prefix.."([1-9]%d*)$")
        if index and tonumber(index)<=max and tostring(tonumber(index))==index then return unit,field end
    end
    return nil,field
end
function R:Context()
    return {playerCombat=self:Read(self.api.InCombatLockdown),inInstance=self:Read(self.api.IsInInstance)}
end
function R:Actor(unit)
    if not unit then return nil end
    return {unit=unit,generation=self.generations[unit] or 0,state=self.presence[unit] or "unobserved"}
end
function R:Append(kind,data)
    if not self.active then return false end
    local ok,reason=self.core:Append(kind,data)
    if not ok then self:Stop(reason or "failed") end
    return ok
end
function R:Snapshot(unit,entries,cause,eventID)
    if not self.active or not unit then return end
    if self.presence[unit]=="removed" then
        self:Append("unit.observation",{actor=self:Actor(unit),cause=cause,eventID=eventID,status="unavailable"});return
    end
    local started=self.core:Now()
    local generation=self.generations[unit] or 0
    local actor=self:Actor(unit)
    local ok,result=pcall(self.probe.Probe,self.probe,unit,{entries=entries,maxEntries=200,
        recordLimit=self.auraLimit,callLimit=32,probe=true})
    local data={actor=actor,cause=cause,eventID=eventID,started=started,context=self:Context()}
    if not ok then data.status="error"
    else
        local valid=self:Table(result)
        if not valid then data.status="invalid"
        else data.status="observed";data.entries=result.entries;data.summary=result.summary end
    end
    data.finished=self.core:Now();data.stale=generation~=(self.generations[unit] or 0)
    self:Append("unit.observation",data)
end
function R:AuraRecord(raw)
    local value,why=self:Table(raw)
    if not value then return {status=why or "opaque"} end
    local fields={}
    for _,key in ipairs(auraFields) do
        local v,state=self:Member(value,key);fields[key]=state and errorField(state) or self:Field(v)
    end
    return {status="observed",fields=fields}
end
function R:AuraList(raw,mode,unit)
    local value,why=self:Table(raw)
    if not value then return {status=why or "opaque"} end
    local records={};local result={status="observed",records=records,complete=true}
    for i=1,self.auraLimit+1 do
        local item,state=self:Member(value,i)
        if state then result.status=state;result.complete=false;break end
        local field=self:Field(item)
        if field.status=="unavailable" then break end
        if i>self.auraLimit then result.complete=false;result.truncated=true;break end
        if mode=="added" then records[#records+1]=self:AuraRecord(item)
        else
            local row={auraInstanceID=field};records[#records+1]=row
            if mode=="updated" and unit and field.status=="readable" and field.type=="number" and field.value>=1 and field.value==math.floor(field.value) then
                local fn=self.api.C_UnitAuras and self.api.C_UnitAuras.GetAuraDataByAuraInstanceID
                if type(fn)~="function" then row.observation={status="unsupported"}
                else
                    local ok,record=pcall(fn,unit,field.value)
                    row.observation=ok and self:AuraRecord(record) or {status="error"}
                end
            end
        end
    end
    return result
end
function R:AuraDelta(raw,unit)
    local value,why=self:Table(raw)
    if not value then return {status=why or "opaque",interpretation="unknown"} end
    local full,state=self:Member(value,"isFullUpdate")
    local delta={status="observed",isFullUpdate=state and errorField(state) or self:Field(full)}
    for _,pair in ipairs({{"addedAuras","added"},{"updatedAuraInstanceIDs","updated"},{"removedAuraInstanceIDs","removed"}}) do
        local list,whyList=self:Member(value,pair[1])
        delta[pair[1]]=whyList and {status=whyList} or self:AuraList(list,pair[2],unit)
    end
    -- Missing/hidden lists are never interpreted as absence or a removal.
    return delta
end
function R:Invalidate(event,raw)
    local unit=self:Unit(raw);local affected={}
    if event=="PLAYER_TARGET_CHANGED" then affected={target=true,targettarget=true}
    elseif event=="PLAYER_FOCUS_CHANGED" then affected={focus=true,focustarget=true}
    elseif event=="UNIT_TARGET" then affected={targettarget=true,focustarget=true}
    elseif event=="UNIT_PET" then affected={pet=true,focus=true,focustarget=true,targettarget=true}
    elseif event=="NAME_PLATE_UNIT_ADDED" or event=="NAME_PLATE_UNIT_REMOVED" then
        if unit and unit:match("^nameplate") then affected[unit]=true
        else for i=1,40 do affected["nameplate"..i]=true end end
    elseif event=="GROUP_ROSTER_UPDATE" then for i=1,4 do affected["party"..i]=true end;for i=1,40 do affected["raid"..i]=true end
    elseif event=="INSTANCE_ENCOUNTER_ENGAGE_UNIT" then for i=1,8 do affected["boss"..i]=true end
    else for _,token in ipairs(self.tokens) do affected[token]=true end end
    for token in pairs(affected) do
        self.generations[token]=(self.generations[token] or 0)+1
        self.presence[token]=(event=="NAME_PLATE_UNIT_REMOVED" and unit==token) and "removed" or "unknown"
    end
    return affected
end
function R:Queue(unit,cause)
    local job=self.queued[unit]
    if job then job.cause=cause;job.generation=self.generations[unit] or 0
    else
        job={unit=unit,cause=cause,generation=self.generations[unit] or 0}
        self.queued[unit]=job;self.queue[#self.queue+1]=job
    end
end
function R:AcceptRate(now)
    local second=math.floor(now)
    if self.rateSecond~=second then self.rateSecond=second;self.rateCount=0 end
    self.rateCount=self.rateCount+1
    if self.rateCount>self.rateLimit then self.lost=self.lost+1;return false end
    return true
end
function R:OnEvent(event,...)
    if not self.active then return end
    if event=="PLAYER_LOGOUT" then self:Stop("interrupted");return end
    local now=self.core:Now();if not now then self:Stop("invalid_clock");return end
    local args={n=select("#",...),...}
    local schema=castSchemas[event]
    local isBinding=not schema and event~="UNIT_AURA" and event~="ENCOUNTER_START" and event~="ENCOUNTER_END" and event~="BOSS_KILL" and event~="PLAYER_REGEN_DISABLED" and event~="PLAYER_REGEN_ENABLED"
    local changed
    -- Invalidate even if the record rate limit discards the event itself.
    if isBinding then changed=self:Invalidate(event,args[1]) end
    if not self:AcceptRate(now) then return end
    self.eventID=self.eventID+1;local eventID=self.eventID
    local data={event=event,eventID=eventID,eventAt=now,context=self:Context(),fields={}}
    if schema then
        local unit,unitField=self:Unit(args[1])
        if not unit and unitField.status=="readable" and unitField.type=="string" then return end
        for i,key in ipairs(schema) do data.fields[key]=self:Field(args[i]) end
        data.actor=self:Actor(unit)
        if self:Append("cast.event",data) then self:Snapshot(unit,castEntries,event,eventID) end
    elseif event=="UNIT_AURA" then
        local unit,unitField=self:Unit(args[1])
        if not unit and unitField.status=="readable" and unitField.type=="string" then return end
        data.fields.unit=unitField;data.actor=self:Actor(unit)
        -- Sanitize before appending, without retaining the native update table.
        data.delta=self:AuraDelta(args[2],unit)
        if self:Append("aura.event",data) then
            if data.delta.isFullUpdate and data.delta.isFullUpdate.status=="readable" and data.delta.isFullUpdate.value==true then
                self:Snapshot(unit,auraEntries,"full_update_observation",eventID)
            end
        end
    elseif event=="ENCOUNTER_START" or event=="ENCOUNTER_END" or event=="BOSS_KILL" then
        if event=="ENCOUNTER_START" then self.encounter=self.encounter+1 end
        data.encounter=self.encounter
        for i,key in ipairs({"encounterID","encounterName","difficultyID","groupSize","success"}) do
            if (event=="BOSS_KILL" and i<=2) or (event=="ENCOUNTER_START" and i<=4) or event=="ENCOUNTER_END" then data.fields[key]=self:Field(args[i]) end
        end
        if event=="ENCOUNTER_END" then
            local values,state=self:Table(args[6]);data.unitStatus={status=state or "observed",records={}}
            if values then for i=1,9 do
                local value,why=self:Member(values,i)
                if why or self:Field(value).status=="unavailable" then break end
                if i==9 then data.unitStatus.truncated=true;break end
                local row={}
                for _,key in ipairs({"creatureID","creatureName","remainingHealthPercent"}) do
                    local v,s=self:Member(value,key);row[key]=s and errorField(s) or self:Field(v)
                end
                data.unitStatus.records[#data.unitStatus.records+1]=row
            end end
        end
        self:Append("encounter.event",data)
    elseif event=="PLAYER_REGEN_DISABLED" or event=="PLAYER_REGEN_ENABLED" then
        self:Append("combat.event",data)
    else
        data.fields.unit=self:Field(args[1]);data.bindings={}
        for token in pairs(changed or {}) do
            data.bindings[#data.bindings+1]=self:Actor(token)
            if event~="NAME_PLATE_UNIT_REMOVED" then self:Queue(token,event) end
        end
        self:Append("binding.event",data)
    end
end
function R:Tick()
    if not self.active then return end
    local now=self.core:Now();if not now then self:Stop("invalid_clock");return end
    if now>=self.deadline then self:Stop("complete");return end
    if self.lost>0 then
        local lost=self.lost;self.lost=0;local ok,why=self.core:Gap("event_rate",lost)
        if not ok then self:Stop(why);return end
    end
    local started=now
    for _=1,4 do
        if not self.active then return end
        local job=table.remove(self.queue,1);if not job then return end
        self.queued[job.unit]=nil
        if job.generation==(self.generations[job.unit] or 0) and self.presence[job.unit]~="removed" then
            local exists=self:Read(self.api.UnitExists,job.unit)
            self.presence[job.unit]=exists.status=="readable" and exists.type=="boolean" and (exists.value==true and "present" or "absent") or "unknown"
            if not self:Append("unit.binding",{actor=self:Actor(job.unit),exists=exists,cause=job.cause,context=self:Context()}) then return end
            if self.presence[job.unit]~="absent" then
                self:Snapshot(job.unit,baseEntries,"baseline")
                self:Snapshot(job.unit,castEntries,"baseline")
                self:Snapshot(job.unit,auraEntries,"baseline")
            end
        end
        local ended=self.core:Now();if not ended or ended-started>=.002 then return end
    end
end
function R:Start(label,seconds)
    if self.active then return nil,"already_running" end
    if seconds==nil then seconds=900 end
    local duration=self:Field(seconds)
    if duration.status~="readable" or duration.type~="number" or seconds<30 or seconds>1800 or seconds~=math.floor(seconds) then return nil,"duration_30_to_1800" end
    if not self.api.C_Timer or type(self.api.C_Timer.NewTicker)~="function" then return nil,"timer_unavailable" end
    local metadata={addonVersion=ns.version,recorder="unit-events-v1",requestedDuration=seconds,
        limits={eventCallbacksPerSecond=self.rateLimit,auraRecordsPerList=self.auraLimit},context=self:Context(),
        coverage={"cast-events","aura-deltas","unit-bindings","encounter-events","combat-state"},
        semantics="Observed events, not a complete combat log. Secrets are status-only."}
    if type(self.api.GetBuildInfo)=="function" then
        local ok,version,build,date,interface=pcall(self.api.GetBuildInfo)
        if ok then metadata.client={version=self:Field(version),build=self:Field(build),date=self:Field(date),interface=self:Field(interface)} end
    end
    metadata.locale=self:Read(self.api.GetLocale)
    local session,reason=self.core:Start(label,metadata);if not session then return nil,reason end
    self.active=true;self.deadline=session.started+seconds;self.epoch=self.epoch+1
    self.generations={};self.presence={};self.queue={};self.queued={};self.tokens={}
    self.eventID=0;self.encounter=0;self.lost=0;self.rateCount=0;self.rateSecond=nil
    self.probe=self.probe or A.UnitData.New(self.api)
    for _,unit in ipairs({"player","pet","target","targettarget","focus","focustarget"}) do self.tokens[#self.tokens+1]=unit end
    for _,group in ipairs({{"boss",8},{"party",4},{"raid",40},{"nameplate",40}}) do
        for i=1,group[2] do self.tokens[#self.tokens+1]=group[1]..i end
    end
    for _,unit in ipairs(self.tokens) do self:Queue(unit,"session_start") end
    local epoch=self.epoch;local subscriptions={}
    for event in pairs(castSchemas) do subscriptions[#subscriptions+1]=event end
    for _,event in ipairs({"UNIT_AURA","ENCOUNTER_START","ENCOUNTER_END","BOSS_KILL","INSTANCE_ENCOUNTER_ENGAGE_UNIT",
        "PLAYER_REGEN_DISABLED","PLAYER_REGEN_ENABLED","PLAYER_TARGET_CHANGED","PLAYER_FOCUS_CHANGED","UNIT_TARGET","UNIT_PET",
        "NAME_PLATE_UNIT_ADDED","NAME_PLATE_UNIT_REMOVED","GROUP_ROSTER_UPDATE","PLAYER_ENTERING_WORLD","ADDON_RESTRICTION_STATE_CHANGED","PLAYER_LOGOUT"}) do subscriptions[#subscriptions+1]=event end
    for _,event in ipairs(subscriptions) do
        local ok=pcall(self.events.Subscribe,self.events,self,event,function(e,...)
            if self.epoch~=epoch or not self.active then return end
            local handled=pcall(self.OnEvent,self,e,...)
            if not handled then self:Stop("event_error") end
        end)
        if not ok then
            if event=="PLAYER_LOGOUT" then self:Stop("logout_subscription_failed");return nil,"logout_subscription_failed" end
            local recorded,why=self.core:Gap("unsupported:"..event,1)
            if not recorded then self:Stop(why);return nil,why end
        end
    end
    local ok,timer=pcall(self.api.C_Timer.NewTicker,.1,function()
        if self.epoch~=epoch or not self.active then return end
        local handled=pcall(self.Tick,self);if not handled then self:Stop("tick_error") end
    end)
    if not ok or not timer or type(timer.Cancel)~="function" then self:Stop("timer_error");return nil,"timer_error" end
    self.timer=timer;self.print("Recording #"..session.id.." started: "..session.label)
    return session
end
function R:Stop(reason)
    self.epoch=self.epoch+1
    if self.timer then pcall(self.timer.Cancel,self.timer);self.timer=nil end
    self.events:Release(self)
    if not self.active then return end
    self.active=false
    if self.lost>0 then self.core:Gap("event_rate",self.lost);self.lost=0 end
    if #self.queue>0 then self.core:Gap("pending_baseline",#self.queue) end
    self.queue={};self.queued={}
    local session=self.core:Stop(reason or "stopped")
    self.print("Recording stopped: "..(reason or "stopped")..". Saved in BVRecordingDB when the client writes SavedVariables.")
    return session
end
function R:Status()
    local status,reason=self.core:Status()
    if not status then self.print("No recording: "..(reason or "empty"));return end
    self.print("Recording #"..tostring(status.id or "?").." ["..tostring(status.status or "unknown").."] "..
        tostring(status.totals and status.totals.events or 0).." records, "..tostring(status.dropped and status.dropped.count or 0).." dropped.")
    return status
end
function R:Mark(label)
    local value=self:Field(label)
    if value.status~="readable" or value.type~="string" or #value.value>48 or value.value:find("[^%w_.%-]") then return false end
    return self:Append("manual.marker",{label=value.value,context=self:Context()})
end
function R:Command(text)
    local words={};for word in (text or ""):gmatch("%S+") do words[#words+1]=word end
    if words[1]=="start" and #words>=2 and #words<=3 then
        local session,why=self:Start(words[2],words[3] and (tonumber(words[3]) or false))
        if not session then self.print("Recording not started: "..(why or "invalid")) end
    elseif words[1]=="stop" then self:Stop()
    elseif words[1]=="status" then self:Status()
    elseif words[1]=="mark" and #words==2 then if not self:Mark(words[2]) then self.print("Marker requires an active recording and a short label.") end
    elseif words[1]=="clear" and words[2]=="confirm" and #words==2 then
        local ok,why=self.core:Clear();self.print(ok and "Recordings cleared; graphs and unit snapshots unchanged." or "Recordings not cleared: "..(why or "invalid"))
    else self.print("/bvrecord start LABEL [30..1800 seconds] | stop | status | mark LABEL | clear confirm") end
end
local recorder=R.New(_G,ns.Events,function(message)ns:Print(message)end)
A.sessionRecorder=recorder
SLASH_BVSESSIONRECORDER1="/bvrecord"
SlashCmdList.BVSESSIONRECORDER=function(text)
    local ok=pcall(recorder.Command,recorder,text)
    if not ok then recorder:Stop("command_error");ns:Print("Recording command failed; stored sessions retained.") end
end
