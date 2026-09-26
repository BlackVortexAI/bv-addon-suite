-- Opt-in diagnostic only. No scans, events or timers until /bvspelltest start.
-- Data and measurements deliberately live outside profiles and production selectors.
local _,A=...
if A.blocked then return end
local ns=BVAddonSuiteCore
local Bench={}; Bench.__index=Bench; A.SpellIndexTest=Bench
local SCHEMA,MAX_RUNS,MAX_IDS_PER_SLICE=1,5,10000
local function finite(n) return type(n)=="number" and n==n and n>-math.huge and n<math.huge end
local function fresh() return {schema=SCHEMA,runs={},nextID=1} end
local function count(t) local n=0; for _ in pairs(t) do n=n+1 end; return n end
local function sample(stats,value)
    if not finite(value) or value<0 then return end
    stats.count=stats.count+1; stats.sum=stats.sum+value
    stats.min=math.min(stats.min or value,value); stats.max=math.max(stats.max or value,value)
end
local function stats() return {count=0,sum=0} end
function Bench.New(api,events,printMessage)
    return setmetatable({api=api,events=events,print=printMessage},Bench)
end
function Bench:Store()
    local api=self.api
    api.BVSpellIndexTestDB=api.BVSpellIndexTestDB or fresh()
    api.BVSpellIndexTestMetrics=api.BVSpellIndexTestMetrics or fresh()
    local indices,metrics=api.BVSpellIndexTestDB,api.BVSpellIndexTestMetrics
    assert(indices.schema==SCHEMA and metrics.schema==SCHEMA,"Unsupported diagnostic schema; export/reset diagnostic data first")
    if not self.recovered then
        for id,run in pairs(metrics.runs) do
            if run.status=="running" then
                run.status="interrupted"; run.reason="Previous session ended; timing is the last checkpoint"
                if indices.runs[id] then indices.runs[id].status="interrupted" end
            end
        end
        self.recovered=true
    end
    return indices,metrics
end
function Bench:Readable(value)
    return not (self.api.issecretvalue and self.api.issecretvalue(value))
end
function Bench:Read(id)
    -- Build 69913 asserted natively in GetSpellTexture(1251535). pcall cannot
    -- contain native assertions. Bulk lookups must not resolve icons or use
    -- unverified full-info fallbacks; see docs/spell-index-test.md.
    local name=self.api.C_Spell.GetSpellName(id)
    if not self:Readable(name) then return nil,nil,"protected" end
    if type(name)~="string" or name=="" then return end
    return name,nil,"iconDeferred"
end
function Bench:Heap()
    if not self.api.collectgarbage then return end
    local ok,value=pcall(self.api.collectgarbage,"count")
    if ok and finite(value) then return value end
end
function Bench:Checkpoint()
    local r=self.run; local now=self.api.GetTimePreciseSec()
    r.wallSeconds=now-self.started
    r.scanWallSeconds=self.scanStarted and now-self.scanStarted or 0
    r.pausedSeconds=self.pausedTotal+(self.pauseStarted and now-self.pauseStarted or 0)
    r.lastID=self.nextID-1
    local heap=self:Heap()
    if heap then r.luaHeapEndKB=heap; r.luaHeapPeakKB=math.max(r.luaHeapPeakKB or heap,heap) end
    self.index.lastID=r.lastID
    return now
end
function Bench:Status()
    local _,db=self:Store(); local r=self.run or db.runs[db.latest]
    if not r then self.print("No spell-index test yet. /bvspelltest start"); return end
    if self.run then self:Checkpoint() end
    self.print(string.format("Spell test #%d %s [%s]: %d/%d IDs, %d spells; wall %.2fs, work %.2fms, max slice %.3fms%s",
        r.id,r.status,r.api,r.lastID,r.maxID,r.found,r.wallSeconds,r.workMs,r.maxSliceMs,self.pauseStarted and " (combat pause)" or ""))
end
function Bench:Stop(status,reason,quiet)
    if not self.run then return end
    self:Checkpoint()
    if self.timer then self.timer:Cancel(); self.timer=nil end
    self.events:Release(self)
    local r=self.run
    r.status=status or "cancelled"; r.reason=reason; self.index.status=r.status
    r.finishedAt=self.api.time and self.api.time() or nil
    r.meanSliceMs=r.slices>0 and r.workMs/r.slices or 0
    r.luaHeapDeltaKB=r.luaHeapEndKB and r.luaHeapStartKB and r.luaHeapEndKB-r.luaHeapStartKB or nil
    self.run=nil; self.index=nil; self.pauseStarted=nil
    if not quiet then self:Status(); self.print("Index + separate metrics retained. /reload or log out normally to write SavedVariables.") end
end
function Bench:Start(budget,maxID)
    if self.run then self.print("Already running. Use /bvspelltest status or stop."); return false end
    if budget==nil then budget=1 end
    if maxID==nil then maxID=2000000 end
    if not finite(budget) or budget<0.1 or budget>5 or not finite(maxID) or maxID<1 or maxID>5000000 or maxID~=math.floor(maxID) then
        self.print("Use /bvspelltest start [0.1..5 ms] [max Spell ID 1..5000000]. Defaults: 1 ms, 2000000."); return false
    end
    local api=self.api
    if not (api.GetTimePreciseSec and api.GetTime and api.GetBuildInfo and api.GetLocale and api.C_Timer and api.C_Timer.NewTicker) then
        self.print("Required clock, client metadata or timer API missing; no test started."); return false
    end
    if api.InCombatLockdown and api.InCombatLockdown() then self.print("Start outside combat."); return false end
    local spell=api.C_Spell
    if spell and type(spell.GetSpellName)=="function" then self.mode="C_Spell name-only"
    else self.print("C_Spell.GetSpellName missing. Full-info/icon scan fallbacks disabled after native client assertion; no test started."); return false end
    local indices,metrics=self:Store()
    if count(metrics.runs)>=MAX_RUNS or count(indices.runs)>=MAX_RUNS then
        self.print("Five diagnostic runs retained. Export SavedVariables, then /bvspelltest clear confirm to free them."); return false
    end
    local version,build,buildDate,interface=api.GetBuildInfo()
    local identity={version=version,build=build,buildDate=buildDate,interface=interface,locale=api.GetLocale(),projectID=api.WOW_PROJECT_ID or "unknown",schema=SCHEMA}
    local key=table.concat({tostring(identity.projectID),tostring(version),tostring(build),tostring(interface),identity.locale,tostring(SCHEMA)},"|")
    local id=metrics.nextID
    while metrics.runs[id] or indices.runs[id] do id=id+1 end
    metrics.nextID=id+1; metrics.latest=id
    self.started=api.GetTimePreciseSec(); self.scanStarted=nil; self.pauseStarted=nil; self.pausedTotal=0
    self.nextID=1; self.lastFrame=nil; self.lastCheckpoint=self.started; self.baselineUntil=self.started+2
    local heap=self:Heap()
    self.run={id=id,identity=identity,namespace=key,status="running",startedAt=api.time and api.time() or nil,
        implementation="bv-spell-bench-v2-name-only",addonVersion=ns.version,api=self.mode,iconPolicy="deferred-native-assertion",cache="empty BV index; native client caches not flushed",
        budgetMs=budget,maxID=maxID,maxIDsPerSlice=MAX_IDS_PER_SLICE,timerSeconds=.001,baselineSeconds=2,
        lastID=0,found=0,uniqueNames=0,missing=0,missingIcons=0,iconsDeferred=0,protected=0,errors=0,errorSamples={},milestones={},
        slices=0,workMs=0,maxSliceMs=0,overBudgetSlices=0,idCapSlices=0,wallSeconds=0,scanWallSeconds=0,pausedSeconds=0,
        baselineFPS=stats(),scanFPS=stats(),callbackGapMs=stats(),callbackWorkMs=stats(),sliceHistogram={0,0,0,0,0,0,0},
        luaHeapStartKB=heap,luaHeapPeakKB=heap}
    self.index={id=id,namespace=key,identity=identity,status="running",lastID=0,iconPolicy="deferred-native-assertion",spells={},byName={}}
    metrics.runs[id]=self.run; indices.runs[id]=self.index
    self.events:Subscribe(self,"PLAYER_LOGOUT",function() self:Stop("interrupted","Logout/reload during scan",true) end)
    self.timer=api.C_Timer.NewTicker(.001,function()
        local r=self.run; local callbackStart=api.GetTimePreciseSec()
        local ok=pcall(self.Tick,self)
        if not ok and self.run then self:Stop("failed","Unexpected diagnostic error; stopped safely") end
        if r then sample(r.callbackWorkMs,(api.GetTimePreciseSec()-callbackStart)*1000) end
    end)
    self.print("Spell test #"..id.." NAME-ONLY (icons deferred): 2s baseline, fresh scan 1.."..maxID.." at "..budget.."ms/frame. /bvspelltest stop cancels.")
    return true
end
function Bench:Tick()
    local r=self.run; if not r then return end
    local api=self.api; local frameTime=api.GetTime()
    if frameTime==self.lastFrame then return end -- Ticker catch-up cannot multiply the frame budget.
    self.lastFrame=frameTime
    local now=api.GetTimePreciseSec()
    if api.InCombatLockdown and api.InCombatLockdown() then
        self.pauseStarted=self.pauseStarted or now; self.lastWorkFrame=nil
        if now-self.lastCheckpoint>=1 then self:Checkpoint(); self.lastCheckpoint=now end
        return
    end
    if self.pauseStarted then
        local pause=now-self.pauseStarted
        self.pausedTotal=self.pausedTotal+pause
        if not self.scanStarted then self.baselineUntil=self.baselineUntil+pause end
        self.pauseStarted=nil
    end
    local fps=api.GetFramerate and api.GetFramerate()
    if now<self.baselineUntil then sample(r.baselineFPS,fps); return end
    self.scanStarted=self.scanStarted or now
    sample(r.scanFPS,fps)
    if self.lastWorkFrame then sample(r.callbackGapMs,(now-self.lastWorkFrame)*1000) end
    self.lastWorkFrame=now
    local begin=api.GetTimePreciseSec(); local processed=0
    repeat
        local id=self.nextID
        local ok,name,icon,reason=pcall(self.Read,self,id)
        processed=processed+1; self.nextID=id+1
        if not ok then
            r.errors=r.errors+1
            -- Never serialize arbitrary client error/secret values.
            if #r.errorSamples<8 then r.errorSamples[#r.errorSamples+1]={spellID=id,reason="metadata read failed"} end
        elseif name then
            self.index.spells[id]={name=name,icon=icon}
            local ids=self.index.byName[name]
            if not ids then ids={}; self.index.byName[name]=ids; r.uniqueNames=r.uniqueNames+1 end
            ids[#ids+1]=id; r.found=r.found+1
            if reason=="iconDeferred" then r.iconsDeferred=r.iconsDeferred+1
            elseif not icon then r.missingIcons=r.missingIcons+1 end
            if r.found==1 or r.found==100 or r.found==1000 or r.found==10000 then
                r.milestones[r.found]={spellID=id,scanSeconds=api.GetTimePreciseSec()-self.scanStarted}
            end
        elseif reason=="protected" then r.protected=r.protected+1
        else r.missing=r.missing+1 end
    until self.nextID>r.maxID or processed>=MAX_IDS_PER_SLICE or r.errors>=100 or (api.GetTimePreciseSec()-begin)*1000>=r.budgetMs
    local elapsed=(api.GetTimePreciseSec()-begin)*1000
    r.slices=r.slices+1; r.workMs=r.workMs+elapsed; r.maxSliceMs=math.max(r.maxSliceMs,elapsed)
    if elapsed>r.budgetMs then r.overBudgetSlices=r.overBudgetSlices+1 end
    if processed>=MAX_IDS_PER_SLICE then r.idCapSlices=r.idCapSlices+1 end
    local bucket=7
    for i,limit in ipairs({.25,.5,1,2,5,10}) do if elapsed<=limit then bucket=i; break end end
    r.sliceHistogram[bucket]=r.sliceHistogram[bucket]+1
    r.lastID=self.nextID-1; self.index.lastID=r.lastID
    if r.errors>=100 then self:Stop("failed","100 metadata errors; API compatibility needs inspection")
    elseif self.nextID>r.maxID then self:Stop("complete","Requested ID range scanned; not proof of all client spells")
    elseif now-self.lastCheckpoint>=1 then self:Checkpoint(); self.lastCheckpoint=now end
end
function Bench:Command(message)
    local words={}; for word in (message or ""):lower():gmatch("%S+") do words[#words+1]=word end
    if words[1]=="start" and #words<=3 then
        self:Start(words[2] and (tonumber(words[2]) or false),words[3] and (tonumber(words[3]) or false))
    elseif words[1]=="stop" and #words==1 then
        if self.run then self:Stop("cancelled","Stopped by user") else self.print("No scan running.") end
    elseif words[1]=="status" and #words==1 then self:Status()
    elseif words[1]=="clear" and words[2]=="confirm" and #words==2 then
        if self.run then self.print("Stop the scan first."); return end
        self.api.BVSpellIndexTestDB=fresh(); self.api.BVSpellIndexTestMetrics=fresh(); self.recovered=true
        self.print("Only diagnostic indices and measurements cleared; graphs untouched. /reload persists this deletion.")
    else self.print("/bvspelltest start [ms] [maxID] | status | stop | clear confirm. NAME-ONLY: icons deferred. Defaults: 1ms, 2000000 IDs; retains 5 runs.") end
end
local instance=Bench.New(_G,ns.Events,function(message) ns:Print(message) end)
A.spellIndexTest=instance
SLASH_BVSPELLINDEXTEST1="/bvspelltest"
SlashCmdList.BVSPELLINDEXTEST=function(message)
    local ok=pcall(instance.Command,instance,message)
    if not ok then
        if instance.run then instance:Stop("failed","Diagnostic setup/command failed",true) end
        ns:Print("Spell test command failed. Diagnostic data retained; check schema/API compatibility.")
    end
end
