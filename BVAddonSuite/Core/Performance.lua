-- Opt-in, bounded, session-only measurements. No unit data or payload capture.
local _,ns=...
local P={serial=0}
ns.Performance=P
local limits={1,2,4,8,12,16.7,25,33.4,50,75,100,150,250,500,1000,math.huge}
local function number(value)
    return not ns.GraphValues.IsSecret(value) and type(value)=="number" and value==value and value>=0 and value<math.huge
end
local function graphBudget()
    if not ns.AuraStudio then return end
    local profile=ns.Settings.db and ns.Settings:Profile()
    local data=profile and profile.modules and profile.modules.aura_studio
    local budget=data and data.budget
    return number(budget) and math.max(.25,math.min(8,budget)) or 1
end
local function add(session,key,value)
    if not number(value) then return end
    local stat=session.stats[key]
    if not stat then stat={n=0,sum=0,max=0,bins={}};session.stats[key]=stat end
    stat.n=stat.n+1;stat.sum=stat.sum+value;stat.max=math.max(stat.max,value)
    for i,limit in ipairs(limits) do if value<=limit then stat.bins[i]=(stat.bins[i] or 0)+1;break end end
end
function P:Count(key)
    local s=self.active;if s then s.counts[key]=(s.counts[key] or 0)+1 end
end
function P:Begin()
    if self.active and debugprofilestop then return debugprofilestop() end
end
function P:Finish(key,started)
    if self.active and started and debugprofilestop then add(self.active,key,debugprofilestop()-started) end
end
function P:Queued(item)
    local s=self.active;if not s then return end
    if item.perfSession~=s.id then item.perfSession=s.id;item.perfQueued=GetTime() end
end
function P:Wait(item,key)
    local s=self.active
    if s and item.perfSession==s.id then add(s,key,(GetTime()-item.perfQueued)*1000) end
end
local function gauge(s,key,value)
    local g=s.gauges[key] or {n=0,sum=0,max=0};s.gauges[key]=g
    g.n=g.n+1;g.sum=g.sum+value;g.max=math.max(g.max,value);g.last=value
end
function P:Sample()
    local s=self.active;if not s then return end
    local started=self:Begin()
    local D,S=ns.DisplayAnchors,ns.AuraStudio
    if s.graphBudget~=graphBudget() or s.stackBudget~=D.stackSliceBudget or s.stackLimit~=D.stackSliceLimit then s.budgetsChanged=true end
    local entries,views,plates=0,0,{}
    for _,groups in pairs(D.stacks) do for _,group in pairs(groups) do
        for _,entry in pairs(group.entries) do
            entries=entries+1
            for _,rec in pairs(entry.views) do
                local visible=rec.view and rec.view:IsVisible()
                if not ns.GraphValues.IsSecret(visible) and visible==true then
                views=views+1
                if group.anchor==ns.Layout.NAMEPLATE_TARGET then plates[entry.unit]=true end
                end
            end
        end
    end end
    local plateCount=0;for _ in pairs(plates) do plateCount=plateCount+1 end
    gauge(s,"attached_nameplates",plateCount);gauge(s,"stack_entries",entries);gauge(s,"stack_views",views)
    local live,age=0,0
    for i=D.stackHead,#D.stackQueue do
        local item=D.stackQueue[i];local group,entry=item.group,item.entry
        if (entry or group).stackPending==item and D:StackCurrent(group) and not group.failed and (not entry or group.entries[entry.id]==entry) then
            live=live+1
            if item.perfSession==s.id then age=math.max(age,(GetTime()-item.perfQueued)*1000) end
        end
    end
    gauge(s,"visual_queue",live);gauge(s,"visual_oldest_ms",age)
    age=0
    for _,item in ipairs(S and S.queue or {}) do
        if item.perfSession==s.id then age=math.max(age,(GetTime()-item.perfQueued)*1000) end
    end
    gauge(s,"graph_queue",S and #S.queue or 0);gauge(s,"graph_oldest_ms",age)
    self:Finish("measurement_sample_ms",started)
end
function P:Frame(elapsed)
    local s=self.active;if not s or not number(elapsed) or elapsed==0 then return end
    -- The first callback can include time before the test started.
    if not s.primed then s.primed=true;return end
    add(s,"frame_ms",elapsed*1000)
    if elapsed>.05 then s.slowFrames=s.slowFrames+1 end
end
function P:Stop(quiet)
    local s=self.active;if not s then return false end
    self:Sample();s.ended=GetTime();self.active=nil;self.last=s
    if self.timer then self.timer:Cancel();self.timer=nil end
    if self.sampler then self.sampler:Cancel();self.sampler=nil end
    ns.UI:SetPerformanceSampling(false);ns.Events:Release(self)
    if not quiet then ns:Print("Performance test finished. Use /bv perf report to copy the results.") end
    return true
end
function P:Start(seconds)
    if not number(seconds) or seconds<5 or seconds>300 or seconds%1~=0 then return false end
    if self.active then ns:Print("Performance test already running. Use /bv perf stop first.");return false end
    self.serial=self.serial+1
    local D,S=ns.DisplayAnchors,ns.AuraStudio
    local s={id=self.serial,started=GetTime(),seconds=seconds,stats={},counts={},gauges={},slowFrames=0,
        version=ns.version,cpuClock=type(debugprofilestop)=="function",preexisting=0,
        stackBudget=D.stackSliceBudget,stackLimit=D.stackSliceLimit,graphBudget=graphBudget()}
    if GetBuildInfo then
        local version,build,_,interface=GetBuildInfo()
        if not ns.GraphValues.IsSecret(version) and type(version)=="string" and version:match("^[%d.]+$") then s.client=version end
        if not ns.GraphValues.IsSecret(build) and type(build)=="string" and build:match("^%d+$") then s.build=build end
        if number(interface) then s.interface=interface end
    end
    self.active=s
    -- Existing work has only a lower-bound age measured from test start.
    for i=D.stackHead,#D.stackQueue do self:Queued(D.stackQueue[i]);s.preexisting=s.preexisting+1 end
    for _,item in ipairs(S and S.queue or {}) do self:Queued(item);s.preexisting=s.preexisting+1 end
    self:Sample();ns.UI:SetPerformanceSampling(true)
    self.sampler=C_Timer.NewTicker(.25,function() self:Sample() end)
    self.timer=C_Timer.NewTimer(seconds,function() self:Stop() end)
    ns.Events:Subscribe(self,"PLAYER_LOGOUT",function() self:Stop(true) end)
    ns:Print("Performance test started for "..seconds.."s. Update cadence is unchanged.")
    return true
end
local function percentile(stat)
    local count=0
    for i,limit in ipairs(limits) do
        count=count+(stat.bins[i] or 0)
        if count>=math.ceil(stat.n*.95) then return limit==math.huge and ">1000" or "<="..limit end
    end
    return "n/a"
end
function P:Report()
    local s=self.active or self.last;if not s then return "No performance test recorded. Use /bv perf start 60." end
    local duration=math.max(0,(s.ended or GetTime())-s.started)
    local out={"BV performance report v2 | addon "..s.version,"Client: "..(s.client or "unknown").." build="..(s.build or "unknown").." interface="..tostring(s.interface or "unknown"),
        "State: "..(s.ended and "finished" or "running").." | seconds: "..string.format("%.2f",duration),
        "Unchanged cadence: visual 16ms, graph continuation 16ms; start soft budgets (ms): visual="..s.stackBudget..", graph="..tostring(s.graphBudget or "unavailable").."; visual slice limit="..s.stackLimit,
        "Budget changes observed: "..(s.budgetsChanged and "yes" or "no"),
        "CPU clock: "..(s.cpuClock and "available" or "unavailable").." | existing queue items at start: "..s.preexisting,
        "Phase times are inclusive wall times and overlap: do not sum them or infer GPU/addon CPU usage.",
        "Graph detail: store/bindings/begin/step/clock/notify are inside graph_slice; clock/notify run after its budget check.",
        "Instance and node phases nest inside graph work and can also run outside the pump. schedule_prepare is outside the pump.",
        "Incremental initialization: instance_snapshot is inside graph_step; instance_prepare excludes these snapshot slices.",
        "Detailed probes add overhead; compare v2 runs with v2. Labels are fixed phase names; no per-node payloads recorded.",
        "p95 is a histogram upper bound. Queue/load gauges sampled every 250ms (brief peaks may be missed).",
        "Existing queue ages are lower bounds. Click completion means graph processed, not screen presented.",
        "Nameplates counts only visible BV attachments. Other addons and the game affect frame times."}
    local frame=s.stats.frame_ms
    out[#out+1]=frame and string.format("Measured FPS: %.1f | frames >50ms: %d | sampled frame seconds: %.2f",1000*frame.n/frame.sum,s.slowFrames,frame.sum/1000) or "Measured FPS: unavailable (no frame samples)"
    local keys={};for key in pairs(s.stats) do keys[#keys+1]=key end;table.sort(keys)
    for _,key in ipairs(keys) do local stat=s.stats[key]
        out[#out+1]=string.format("%s: count=%d, total=%.3fms, avg=%.3fms, max=%.3fms, p95 %sms",key,stat.n,stat.sum,stat.sum/stat.n,stat.max,percentile(stat))
    end
    keys={};for key in pairs(s.gauges) do keys[#keys+1]=key end;table.sort(keys)
    for _,key in ipairs(keys) do local g=s.gauges[key]
        out[#out+1]=string.format("%s: avg=%.2f, max=%.2f, last=%.2f",key,g.sum/g.n,g.max,g.last)
    end
    keys={};for key in pairs(s.counts) do keys[#keys+1]=key end;table.sort(keys)
    for _,key in ipairs(keys) do out[#out+1]=string.format("%s: %d (%.2f/s)",key,s.counts[key],duration>0 and s.counts[key]/duration or 0) end
    out[#out+1]="Click stages: down/up/click/queued/processed/cancelled/full. Missing counters mean zero. Work still pending at stop is not a lost click."
    out[#out+1]="Session only; no names, payloads, saved settings or global script profiling captured. Measurement has overhead."
    return table.concat(out,"\n")
end
ns.Commands:RegisterAction("perf",function(action)
    local verb,arg=action:match("^(%S*)%s*(.-)$")
    if verb=="start" then
        local seconds=arg=="" and 60 or tonumber(arg)
        if not P:Start(seconds) and not P.active then ns:Print("Use /bv perf start [5-300 whole seconds]") end
    elseif verb=="stop" and arg=="" then if not P:Stop() then ns:Print("No performance test running.") end
    elseif verb=="status" and arg=="" then ns:Print(P.active and string.format("Performance test: %.1f / %ds",GetTime()-P.active.started,P.active.seconds) or "Performance test idle. Use /bv perf report for the last result.")
    elseif verb=="report" and arg=="" then ns.UI:DiagnosticReport("Performance test",P:Report())
    else ns:Print("/bv perf start [seconds] | stop | status | report") end
end)
