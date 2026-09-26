-- Opt-in observations only. Secrets are classified, never converted or saved.
local _,A=...
if A.blocked then return end
local ns=BVAddonSuiteCore
local D={};D.__index=D;A.UnitDiagnostics=D
local MAX_RUNS,MAX_RECORDS,MAX_BYTES=5,60000,2000000
local states={readable=true,protected=true,opaque=true,unavailable=true,unsupported=true,error=true,
    absent=true,invalid=true,truncated=true,restricted=true,unconfigured=true,["nil"]=true,present=true,partial=true,ready=true}
local function fresh() return {schema=1,nextID=1,runs={}} end
function D.New(api,events,printer,probe)
    return setmetatable({api=api,events=events,print=printer or function()end,probe=probe,epoch=0,generations={}},D)
end
function D:Secret(v)
    if ns.GraphValues.IsSecret(v) then return true end
    if not self.api.issecretvalue then return false end
    local ok,result=pcall(self.api.issecretvalue,v)
    return not ok or result~=false
end
function D:Scalar(v,limit)
    if self:Secret(v) then return nil,"protected" end
    local kind=type(v)
    if kind=="boolean" then return v,"readable" end
    if kind=="number" and v==v and v~=math.huge and v~=-math.huge then return v,"readable" end
    if kind=="string" then
        local length=limit or 160
        local last=math.min(#v,length)
        if #v>last then while last>0 and v:byte(last+1)>=128 and v:byte(last+1)<192 do last=last-1 end end
        return v:sub(1,last),"readable"
    end
    return nil,kind=="nil" and "unavailable" or "opaque"
end
function D:Read(fn,...)
    if type(fn)~="function" then return nil,"unsupported" end
    local ok,value=pcall(fn,...)
    if not ok then return nil,"error" end
    return self:Scalar(value)
end
function D:Now()
    local value=self:Read(self.api.GetTimePreciseSec or self.api.GetTime)
    return type(value)=="number" and value or 0
end
-- Loaded diagnostics must also be plain and bounded. Never adopt runtime objects
-- or an arbitrary metatable from another addon as diagnostic storage.
function D:Store()
    local db=self.api.BVUnitDiagnosticsDB
    if db==nil then db=fresh();self.api.BVUnitDiagnosticsDB=db end
    if self.checkedDB==db then return db end
    local budget={nodes=0,bytes=0}
    local seen={}
    local function valid(v,depth)
        budget.nodes=budget.nodes+1
        if budget.nodes>2000000 or depth>14 or self:Secret(v) then return false end
        if type(v)~="table" then
            local _,status=self:Scalar(v,512)
            if type(v)=="string" then budget.bytes=budget.bytes+#v;return #v<=512 and budget.bytes<=32000000 end
            return status=="readable" or v==nil
        end
        if getmetatable(v) or seen[v] then return false end
        seen[v]=true
        for k,item in pairs(v) do
            if self:Secret(k) or (type(k)~="number" and type(k)~="string") or not valid(k,depth+1) or not valid(item,depth+1) then return false end
        end
        seen[v]=nil;return true
    end
    assert(valid(db,0) and db.schema==1 and type(db.runs)=="table" and #db.runs<=MAX_RUNS
        and type(db.nextID)=="number" and db.nextID>=1 and db.nextID==math.floor(db.nextID),"Invalid unit diagnostic storage")
    for _,run in ipairs(db.runs) do
        assert(type(run)=="table" and type(run.id)=="number" and type(run.samples)=="table"
            and type(run.records)=="number" and type(run.textBytes)=="number" and type(run.label)=="string"
            and type(run.status)=="string","Invalid unit diagnostic run")
        if run.status=="running" then run.status="interrupted" end
    end
    self.checkedDB=db;return db
end
function D:Context()
    local combat,combatStatus=self:Read(self.api.InCombatLockdown)
    local instance,instanceStatus=self:Read(self.api.IsInInstance)
    return {at=self:Now(),combat=combat,combatStatus=combatStatus,inInstance=instance,instanceStatus=instanceStatus}
end
function D:Tokens()
    local tokens={"player","pet","target","targettarget","focus","focustarget"}
    local excluded={}
    for _,group in ipairs({{"party",4},{"raid",40},{"nameplate",40}}) do
        for i=1,group[2] do
            local token=group[1]..i
            local exists,status=self:Read(self.api.UnitExists,token)
            if status=="readable" and exists==false then excluded[#excluded+1]=token
            else tokens[#tokens+1]=token end
        end
    end
    return tokens,excluded
end
function D:BeginSample()
    local run=self.run
    if #run.samples>=12 then self:Stop("complete");return end
    local tokens,excluded=self:Tokens()
    local sample={number=#run.samples+1,started=self:Now(),context=self:Context(),units={},absentTokens=excluded,status="sampling"}
    run.samples[#run.samples+1]=sample
    self.sample=sample;self.tokens=tokens;self.tokenIndex=1;self.nextEntry=1;self.unitSample=nil
end
function D:Append(result,started,finished,context)
    local run,unit=self.run,self.unitSample
    if self:Secret(result) or type(result)~="table" or getmetatable(result) then return false end
    local entries=result.entries
    if self:Secret(entries) or type(entries)~="table" or getmetatable(entries) then return false end
    local used=0
    for _,raw in ipairs(entries) do
        if used>=8 then break end;used=used+1
        if self:Secret(raw) or type(raw)~="table" or getmetatable(raw) then return false end
        local id=self:Scalar(raw.id,100);local api=self:Scalar(raw.api,100)
        local status=self:Scalar(raw.status,32)
        if type(id)~="string" or type(api)~="string" then return false end
        local entry={id=id,api=api,status=states[status] and status or "unavailable",at=started,finished=finished,
            generation=self.generations[unit.token] or 0,context=context or self:Context(),fields={}}
        local fields=raw.fields
        if self:Secret(fields) or type(fields)~="table" or getmetatable(fields) then return false end
        local count=0
        for key,field in pairs(fields) do
            count=count+1;if count>2048 then entry.truncated=true;break end
            if self:Secret(key) or type(key)~="string" or #key>160 or self:Secret(field) or type(field)~="table" or getmetatable(field) then return false end
            if run.records>=self.recordLimit or run.textBytes>=self.byteLimit then return false end
            local fieldStatus=self:Scalar(field.status,32);local kind=self:Scalar(field.type,32)
            local row={status=states[fieldStatus] and fieldStatus or "unavailable",type=type(kind)=="string" and kind or "unknown"}
            if row.status=="readable" then
                local value,valueStatus=self:Scalar(field.value,160)
                row.status=valueStatus;row.value=value
                if type(value)=="string" then run.textBytes=run.textBytes+#value end
            end
            entry.fields[key]=row;run.records=run.records+1
            run.counts[row.status]=(run.counts[row.status] or 0)+1
        end
        run.entryCount=run.entryCount+1
        if run.entryCount>self.entryLimit then return false end
        unit.entries[#unit.entries+1]=entry
    end
    return true
end
function D:Tick()
    if not self.run then return end
    local clock,clockStatus=self:Read(self.api.GetTimePreciseSec or self.api.GetTime)
    if clockStatus~="readable" or type(clock)~="number" then self:Stop("failed");return end
    local now=self:Now()
    if self.mode=="watch" and now>=self.deadline then self:Stop("complete");return end
    if not self.sample then
        if now<self.nextSample then return end
        self:BeginSample();if not self.run then return end
    end
    local sliceStart=self:Now()
    for _=1,8 do
        local token=self.tokens[self.tokenIndex]
        if not token then
            self.sample.finished=self:Now();self.sample.endContext=self:Context();self.sample.status="complete"
            self.sample=nil;self.nextSample=self:Now()+5
            if self.mode=="snapshot" then self:Stop("complete") end
            return
        end
        if not self.unitSample then
            self.unitSample={token=token,started=self:Now(),generation=self.generations[token] or 0,entries={}}
            self.sample.units[#self.sample.units+1]=self.unitSample
        end
        local started=self:Now()
        local context=self:Context()
        local ok,result=pcall(self.probe.Probe,self.probe,token,{startEntry=self.nextEntry,maxEntries=4,
            callLimit=32,recordLimit=256,spellID=self.spellID,probe=true,allApis=true})
        if not ok or not self:Append(result,started,self:Now(),context) then self:Stop("limited");return end
        local cursor=self:Scalar(result.nextEntry)
        local done=self:Scalar(result.done)
        if done==true or cursor==nil then
            self.unitSample.finished=self:Now()
            self.unitSample.stale=self.unitSample.generation~=(self.generations[token] or 0)
            self.unitSample=nil;self.tokenIndex=self.tokenIndex+1;self.nextEntry=1
        elseif type(cursor)=="number" and cursor>self.nextEntry and cursor<2000 and cursor==math.floor(cursor) then self.nextEntry=cursor
        else self:Stop("failed");return end
        if self:Now()-sliceStart>=.002 then break end
    end
end
function D:Invalidate(event,token)
    local affected={}
    if event=="NAME_PLATE_UNIT_ADDED" or event=="NAME_PLATE_UNIT_REMOVED" then
        if self:Secret(token) then
            for index=1,40 do affected["nameplate"..index]=true end
        else
            local slot=type(token)=="string" and token:match("^nameplate([1-9]%d*)$")
            if slot and tonumber(slot)<=40 then affected[token]=true end
        end
    elseif event=="PLAYER_TARGET_CHANGED" then affected.target=true;affected.targettarget=true
    elseif event=="PLAYER_FOCUS_CHANGED" then affected.focus=true;affected.focustarget=true
    elseif event=="UNIT_TARGET" then affected.targettarget=true;affected.focustarget=true
    elseif event=="UNIT_PET" then affected.pet=true
    else for _,unit in ipairs(self.tokens or {}) do affected[unit]=true end end
    for unit in pairs(affected) do self.generations[unit]=(self.generations[unit] or 0)+1 end
end
function D:Start(mode,label,seconds,spellID)
    if self.run then self.print("Unit capture already running. /bvunits stop");return false end
    if mode~="snapshot" and mode~="watch" then return false end
    if type(label)~="string" or #label<1 or #label>48 or label:find("[^%w_.%-]") then self.print("Use a label of 1..48 letters/digits, _, . or -.");return false end
    if seconds==nil then seconds=60 end
    if type(seconds)~="number" or seconds<5 or seconds>120 or seconds~=math.floor(seconds) then self.print("Watch duration: 5..120 seconds.");return false end
    if spellID~=nil and (type(spellID)~="number" or spellID<1 or spellID>2147483647 or spellID~=math.floor(spellID)) then return false end
    local db=self:Store()
    if #db.runs>=MAX_RUNS then self.print("Five unit captures retained. Export first; /bvunits clear confirm frees diagnostics.");return false end
    if not (self.api.C_Timer and self.api.C_Timer.NewTicker and (self.api.GetTimePreciseSec or self.api.GetTime)) then self.print("Diagnostic timer/clock unavailable.");return false end
    local clock,clockStatus=self:Read(self.api.GetTimePreciseSec or self.api.GetTime)
    if clockStatus~="readable" or type(clock)~="number" then self.print("Readable diagnostic clock unavailable.");return false end
    local records,bytes,entries=0,0,0
    for _,run in ipairs(db.runs) do records=records+run.records;bytes=bytes+run.textBytes;entries=entries+(run.entryCount or 0) end
    self.recordLimit=MAX_RECORDS-records;self.byteLimit=MAX_BYTES-bytes;self.entryLimit=40000-entries
    if self.recordLimit<1 or self.byteLimit<160 or self.entryLimit<1 then self.print("Diagnostic storage limit reached; export, then /bvunits clear confirm.");return false end
    self.probe=self.probe or A.UnitData.New(self.api)
    local identity={}
    if type(self.api.GetBuildInfo)=="function" then
        local ok,version,build,buildDate,interface=pcall(self.api.GetBuildInfo)
        if ok then identity.version=self:Scalar(version);identity.build=self:Scalar(build);identity.buildDate=self:Scalar(buildDate);identity.interface=self:Scalar(interface) end
    end
    identity.locale=self:Read(self.api.GetLocale)
    self.run={id=db.nextID,label=label,mode=mode,status="running",started=self:Now(),samples={},records=0,textBytes=0,counts={},
        identity=identity,entryCount=0,addonVersion=ns.version,context=self:Context(),spellID=spellID}
    db.runs[#db.runs+1]=self.run;db.nextID=db.nextID+1
    self.mode=mode;self.deadline=self:Now()+seconds;self.nextSample=0;self.spellID=spellID
    self.epoch=self.epoch+1;local epoch=self.epoch
    for _,event in ipairs({"NAME_PLATE_UNIT_ADDED","NAME_PLATE_UNIT_REMOVED","PLAYER_TARGET_CHANGED","PLAYER_FOCUS_CHANGED",
        "UNIT_TARGET","UNIT_PET","GROUP_ROSTER_UPDATE","PLAYER_ENTERING_WORLD","ADDON_RESTRICTION_STATE_CHANGED"}) do
        pcall(self.events.Subscribe,self.events,self,event,function(e,unit) self:Invalidate(e,unit) end)
    end
    self.events:Subscribe(self,"PLAYER_LOGOUT",function()self:Stop("interrupted",true)end)
    self.timer=self.api.C_Timer.NewTicker(.03,function()
        if self.epoch~=epoch or not self.run then return end
        local ok=pcall(self.Tick,self)
        if not ok then self:Stop("failed") end
    end)
    self.print("Unit "..mode.." #"..self.run.id.." started: "..label..". Staggered samples; secrets are status-only.")
    return true
end
function D:Stop(status,quiet)
    self.epoch=self.epoch+1
    if self.timer then self.timer:Cancel();self.timer=nil end
    self.events:Release(self)
    if not self.run then return end
    if self.sample then self.sample.status="partial";self.sample.finished=self:Now() end
    self.run.status=status or "stopped";self.run.finished=self:Now()
    self.run=nil;self.sample=nil;self.unitSample=nil;self.tokens=nil
    if not quiet then self:Status();self.print("Use /bvunits report. Normal logout or your own /reload writes BVUnitDiagnosticsDB to SavedVariables.") end
end
function D:Select(id)
    local db=self:Store()
    if id then for _,run in ipairs(db.runs) do if run.id==id then return run end end
    else return db.runs[#db.runs] end
end
function D:Status()
    local run=self.run or self:Select()
    if not run then self.print("No unit capture. /bvunits snapshot open-world");return end
    self.print(string.format("Unit #%d %s [%s]: %d samples, %d fields; %d readable / %d secret / %d errors.",
        run.id,run.label,run.status,#run.samples,run.records,run.counts.readable or 0,run.counts.protected or 0,run.counts.error or 0))
end
function D:Report(id)
    local run=self:Select(id)
    if not run then return "No matching unit capture." end
    local lines={"BV unit diagnostics v1",string.format("Run %d | %s | %s | addon %s",run.id,run.label,run.status,run.addonVersion or "?"),
        "Staggered observations, not an atomic world snapshot. Secrets are status-only.","sample\tunit\tgeneration\tat\tcombat\tinInstance\tapi\tfield\ttype\tstatus\tvalue"}
    local bytes=0
    local function cell(v)
        local value,status=self:Scalar(v,160)
        if status~="readable" then return "" end
        return tostring(value):gsub("[\t\r\n]"," "):gsub("|","||")
    end
    for _,sample in ipairs(run.samples) do
        lines[#lines+1]="Context "..sample.number..": combat="..cell(sample.context.combat).." ("..cell(ns.GraphValues.StatusLabel(sample.context.combatStatus))..") inInstance="..cell(sample.context.inInstance).."; "..cell(sample.status)
        for _,unit in ipairs(sample.units) do
            if unit.stale then lines[#lines+1]="Binding changed during capture: "..unit.token end
            for _,entry in ipairs(unit.entries) do
                local keys={};for key in pairs(entry.fields) do keys[#keys+1]=key end;table.sort(keys)
                if #keys==0 then keys[1]="(call)" end
                for _,key in ipairs(keys) do
                    local field=entry.fields[key] or {status=entry.status}
                    local context=entry.context or sample.context
                    local line=table.concat({cell(sample.number),cell(unit.token),cell(entry.generation),cell(entry.at),cell(context.combat),cell(context.inInstance),cell(entry.api),cell(key),cell(field.type),cell(ns.GraphValues.StatusLabel(field.status)),cell(field.value)},"\t")
                    bytes=bytes+#line+1
                    if bytes>1100000 then lines[#lines+1]="REPORT TRUNCATED; full retained data remains in BVUnitDiagnosticsDB.";return table.concat(lines,"\n") end
                    lines[#lines+1]=line
                end
            end
        end
    end
    return table.concat(lines,"\n")
end
function D:Command(message)
    local words={};for word in (message or ""):gmatch("%S+") do words[#words+1]=word end
    local command=words[1] and words[1]:lower()
    if command=="snapshot" and #words>=2 and #words<=3 then self:Start("snapshot",words[2],nil,words[3] and (tonumber(words[3]) or false))
    elseif command=="watch" and #words>=2 and #words<=4 then self:Start("watch",words[2],words[3] and (tonumber(words[3]) or false),words[4] and (tonumber(words[4]) or false))
    elseif command=="stop" then self:Stop()
    elseif command=="status" then self:Status()
    elseif command=="report" or command=="matrix" then
        if self.api.InCombatLockdown then local combat=self:Read(self.api.InCombatLockdown);if combat==true then self.print("Capture continues in combat; open the report after combat.");return end end
        local id=words[2] and tonumber(words[2])
        ns.UI:DiagnosticReport("Unit observations",command=="matrix" and self:Matrix(id) or self:Report(id))
    elseif command=="clear" and words[2]=="confirm" then
        self:Stop("stopped",true);self.api.BVUnitDiagnosticsDB=fresh();self.checkedDB=nil;self.print("Unit diagnostics cleared; profiles unchanged.")
    else self.print("/bvunits snapshot LABEL [spellID] | watch LABEL [5..120 seconds] [spellID] | stop | status | report [runID] | matrix [runID] | clear confirm") end
end
function D:Matrix(id)
    local db=self:Store();local rows={};local keys={}
    for _,run in ipairs(db.runs) do if not id or run.id==id then
        for _,sample in ipairs(run.samples) do for _,unit in ipairs(sample.units) do for _,entry in ipairs(unit.entries) do
            local context=entry.context or sample.context
            local combat=context.combatStatus=="readable" and (context.combat and "combat" or "peace") or "combat-unknown"
            for field,observation in pairs(entry.fields) do
                local key=table.concat({run.label,combat,unit.token,entry.api,field},"\t")
                if not rows[key] then rows[key]={};keys[#keys+1]=key end
                rows[key][observation.status]=(rows[key][observation.status] or 0)+1
            end
        end end end
    end end
    table.sort(keys)
    local lines={"Observed availability only; not a universal restriction rule.","label\tcontext\tunit\tapi\tfield\treadable\tsecret\topaque\terror\tunsupported\tmissing\tunconfigured\ttruncated"}
    local bytes=0
    for _,key in ipairs(keys) do
        local row=rows[key]
        local line=key.."\t"..table.concat({row.readable or 0,row.protected or 0,row.opaque or 0,row.error or 0,row.unsupported or 0,
            (row.unavailable or 0)+(row.absent or 0)+(row["nil"] or 0)+(row.invalid or 0)+(row.restricted or 0),row.unconfigured or 0,row.truncated or 0},"\t")
        bytes=bytes+#line
        if bytes>1100000 then lines[#lines+1]="MATRIX TRUNCATED; all retained records remain in SavedVariables.";break end
        lines[#lines+1]=line
    end
    return table.concat(lines,"\n"):gsub("|","||")
end
local instance=D.New(_G,ns.Events,function(message)ns:Print(message)end)
A.unitDiagnostics=instance
SLASH_BVUNITDIAGNOSTICS1="/bvunits"
SlashCmdList.BVUNITDIAGNOSTICS=function(message)
    local ok=pcall(instance.Command,instance,message)
    if not ok then instance:Stop("failed",true);ns:Print("Unit diagnostic command failed. Existing captures retained; check API/schema compatibility.") end
end
