-- Read-only observation of Deadly Boss Mods and BigWigs (roadmap P2c).
-- Callbacks are copied into fresh scalar packets; mod tables are never kept,
-- mods are never called beyond (un)registration. See
-- docs/research/2026-09-26-bossmod-providers.md for signatures and limits.
local _,A=...
if A.blocked then return end
local G=A.G
local B={bars={},limit=64,owner={},dbm={},bigwigs=false,textLimit=128};A.BossMods=B
B.kinds={"bar_start","bar_update","bar_pause","bar_resume","bar_stop","bars_clear","message","pull_start","pull_stop","engage","win","wipe","stage"}
local function secret(v) return G.IsSecret(v) end
local function now() return GetTime() end
-- Text for matching and output: markup stripped, bounded; secret stays opaque.
local function text(v)
    if secret(v) then return nil,"protected" end
    if type(v)~="string" then return nil,"unavailable" end
    v=v:gsub("|T.-|t",""):gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","")
    return v:sub(1,B.textLimit),"readable"
end
local function number(v,lo,hi)
    if secret(v) then return nil,"protected" end
    if type(v)~="number" or v~=v or v<lo or v>hi then return nil,"unavailable" end
    return v,"readable"
end
local function field(t,read)
    local ok,v=pcall(read,t)
    if ok then return v end
end
-- Packet for the Bossmod event node; values/fields like DataSource:Event.
local function packet(provider,kind)
    local p={kind="bossmod_event",values={event=true,provider=provider,eventType=kind},fields={provider="readable",eventType="readable"}}
    function p.put(key,value,status) p.values[key]=value;p.fields[key]=status or (value~=nil and "readable" or "unavailable") end
    return p
end
local function deliver(p,changed)
    if B.notify then B.notify(p,changed) end
end
-- Bar tracker: key -> {provider,id,text,spellId,icon,duration,start,expiration,paused,remaining,count,barType}
local function soonestExpiry()
    local soonest
    for _,bar in pairs(B.bars) do if not bar.paused and (not soonest or bar.expiration<soonest) then soonest=bar.expiration end end
    return soonest
end
function B:ScheduleExpiry()
    if self.expiryTimer then self.expiryTimer:Cancel();self.expiryTimer=nil end
    local soonest=soonestExpiry();if not soonest then return end
    self.expiryTimer=C_Timer.NewTimer(math.max(.05,soonest-now()+.05),function()
        self.expiryTimer=nil
        local t=now();local removed=false
        for key,bar in pairs(self.bars) do if not bar.paused and bar.expiration<=t then self.bars[key]=nil;removed=true end end
        if removed then deliver(nil,true) end
        self:ScheduleExpiry()
    end)
end
local function track(key,bar)
    if not B.bars[key] then
        local count=0;for _ in pairs(B.bars) do count=count+1 end
        if count>=B.limit then
            local oldest,oldestKey
            for k,b in pairs(B.bars) do if not oldest or b.expiration<oldest then oldest,oldestKey=b.expiration,k end end
            B.bars[oldestKey]=nil
        end
    end
    B.bars[key]=bar
end
local function untrack(provider,match)
    for key,bar in pairs(B.bars) do if bar.provider==provider and match(bar) then B.bars[key]=nil end end
end
-- Common bar start from either provider.
local function barStart(provider,key,id,label,duration,icon,spellId,count,barType,extra)
    local p=packet(provider,"bar_start")
    local d=number(duration,.01,3600)
    local t,ts=text(label)
    p.put("id",id);p.put("text",t,ts);p.put("spellId",number(spellId,1,2147483647));p.put("count",number(count,0,1000))
    p.put("barType",type(barType)=="string" and not secret(barType) and barType or nil)
    if type(icon)=="number" and not secret(icon) then p.put("icon",icon) else p.put("icon",nil,secret(icon) and "protected" or "unavailable") end
    if d then
        local start=now();p.put("duration",d);p.put("expiration",start+d)
        track(key,{provider=provider,id=id,text=t,spellId=p.values.spellId,icon=p.values.icon,duration=d,start=start,expiration=start+d,count=p.values.count,barType=p.values.barType})
        B:ScheduleExpiry()
    end
    for k,v in pairs(extra or {}) do p.put(k,v) end
    return p
end
-- Deadly Boss Mods ---------------------------------------------------------
local dbmEvents={"DBM_TimerBegin","DBM_TimerUpdate","DBM_TimerStop","DBM_TimerPause","DBM_TimerResume","DBM_Announce","DBM_Pull","DBM_Kill","DBM_Wipe","DBM_SetStage"}
local function modInfo(p,mod)
    if type(mod)~="table" or secret(mod) then return end
    p.put("encounterId",number(field(mod,function(m) return m.encounterId end),1,2147483647))
    local name=field(mod,function(m) return m.localization and m.localization.general and m.localization.general.name end)
    p.put("encounterName",(text(name)))
end
function B:DBM(event,a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,q,r,s,t)
    local p
    if event=="DBM_TimerBegin" then
        -- id,msg,timer,icon,simpleType,spellId,colorId,modId,keep,fade,spellName,guid,timerCount,...,isBarEnabled(18)
        if secret(a) or type(a)~="string" then return end
        p=barStart("dbm","dbm|"..a,a,b,c,d,f,m,e,{modId=type(h)=="string" and not secret(h) and h or nil})
        p.put("barEnabled",s~=false)
        deliver(p,true)
        if e=="pull" then local pull=packet("dbm","pull_start");pull.put("duration",p.values.duration);pull.put("expiration",p.values.expiration);deliver(pull) end
        return
    elseif event=="DBM_TimerUpdate" then
        local bar=type(a)=="string" and not secret(a) and self.bars["dbm|"..a]
        local elapsed,total=number(b,0,3600),number(c,.01,3600)
        p=packet("dbm","bar_update");p.put("id",type(a)=="string" and not secret(a) and a or nil)
        if bar and elapsed and total then bar.duration=total;bar.start=now()-elapsed;bar.expiration=bar.start+total;self:ScheduleExpiry()
            p.put("duration",total);p.put("expiration",bar.expiration) end
        deliver(p,bar~=nil);return
    elseif event=="DBM_TimerStop" or event=="DBM_TimerPause" or event=="DBM_TimerResume" then
        local key=type(a)=="string" and not secret(a) and "dbm|"..a;local bar=key and self.bars[key]
        local kind=event=="DBM_TimerStop" and "bar_stop" or event=="DBM_TimerPause" and "bar_pause" or "bar_resume"
        p=packet("dbm",kind);p.put("id",key and a or nil)
        if bar then
            if kind=="bar_stop" then self.bars[key]=nil
            elseif kind=="bar_pause" and not bar.paused then bar.paused=true;bar.remaining=math.max(0,bar.expiration-now())
            elseif kind=="bar_resume" and bar.paused then bar.paused=nil;bar.expiration=now()+(bar.remaining or 0);bar.remaining=nil end
            self:ScheduleExpiry()
        end
        if kind=="bar_stop" and bar and bar.barType=="pull" then deliver(packet("dbm","pull_stop")) end
        deliver(p,bar~=nil);return
    elseif event=="DBM_Announce" then
        -- message,icon,type,spellId,modId,isSpecialWarning,announceCount
        p=packet("dbm","message");p.put("text",text(a));p.put("messageType",type(c)=="string" and not secret(c) and c or nil)
        p.put("spellId",number(d,1,2147483647));p.put("emphasized",f==true);p.put("count",number(g,0,1000))
        if type(b)=="number" and not secret(b) then p.put("icon",b) end
    elseif event=="DBM_Pull" or event=="DBM_Kill" or event=="DBM_Wipe" then
        p=packet("dbm",event=="DBM_Pull" and "engage" or event=="DBM_Kill" and "win" or "wipe");modInfo(p,a)
        if event~="DBM_Pull" then untrack("dbm",function(bar) return bar.barType~="break" end);deliver(p,true);return end
    elseif event=="DBM_SetStage" then
        p=packet("dbm","stage");modInfo(p,a);p.put("stage",number(c,0,100));p.put("encounterId",number(d,1,2147483647))
    else return end
    deliver(p)
end
-- BigWigs -----------------------------------------------------------------
local bwMessages={"BigWigs_Timer","BigWigs_TargetTimer","BigWigs_CastTimer","BigWigs_StartBar","BigWigs_StopBar","BigWigs_PauseBar","BigWigs_ResumeBar","BigWigs_StopBars",
    "BigWigs_Message","BigWigs_OnBossEngage","BigWigs_OnBossWin","BigWigs_OnBossWipe","BigWigs_SetStage","BigWigs_StartPull","BigWigs_StopPull"}
local function moduleName(module)
    if type(module)~="table" or secret(module) then return "plugin" end
    local name=field(module,function(m) return m.moduleName end)
    return type(name)=="string" and not secret(name) and name or "plugin"
end
local function bwInfo(p,module)
    if type(module)~="table" or secret(module) then return end
    p.put("encounterName",(text(field(module,function(m) return m.displayName end))))
    p.put("encounterId",number(field(module,function(m) return m:GetEncounterID() end),1,2147483647))
end
function B:BigWigs(msg,module,a,b,c,d,e,f,g,h)
    local p
    if msg=="BigWigs_Timer" or msg=="BigWigs_TargetTimer" or msg=="BigWigs_CastTimer" then
        -- module,key,time,maxTime,text,count,icon,...
        local label,ts=text(d);if ts=="protected" then return end
        local id=moduleName(module).."|"..tostring(label)
        local barType=msg=="BigWigs_CastTimer" and "cast" or msg=="BigWigs_TargetTimer" and "target" or (g and "cd" or "timer")
        p=barStart("bigwigs","bigwigs|"..id,id,label,b,f,a,e,barType)
        -- StartBar and *_Timer describe the same bar in the same frame: one event only.
        self.recent=self.recent or {}
        if self.recent[id]==now() then deliver(nil,true);return end
        self.recent[id]=now();deliver(p,true);return
    elseif msg=="BigWigs_StartBar" then
        -- module,key,text,time,icon: only plugin bars (pull, break, custom); boss bars come via *_Timer.
        local label,ts=text(b);if ts=="protected" then return end
        local id=moduleName(module).."|"..tostring(label)
        self.recent=self.recent or {}
        if self.recent[id]==now() then return end
        p=barStart("bigwigs","bigwigs|"..id,id,label,c,d,a,nil,"bar")
        self.recent[id]=now();deliver(p,true);return
    elseif msg=="BigWigs_StopBar" or msg=="BigWigs_PauseBar" or msg=="BigWigs_ResumeBar" then
        local label=text(a);local id=moduleName(module).."|"..tostring(label);local key="bigwigs|"..id;local bar=self.bars[key]
        local kind=msg=="BigWigs_StopBar" and "bar_stop" or msg=="BigWigs_PauseBar" and "bar_pause" or "bar_resume"
        p=packet("bigwigs",kind);p.put("id",id);p.put("text",label)
        if bar then
            if kind=="bar_stop" then self.bars[key]=nil
            elseif kind=="bar_pause" and not bar.paused then bar.paused=true;bar.remaining=math.max(0,bar.expiration-now())
            elseif kind=="bar_resume" and bar.paused then bar.paused=nil;bar.expiration=now()+(bar.remaining or 0);bar.remaining=nil end
            self:ScheduleExpiry()
        end
        deliver(p,bar~=nil);return
    elseif msg=="BigWigs_StopBars" then
        local name=moduleName(module);untrack("bigwigs",function(bar) return bar.id:sub(1,#name+1)==name.."|" end)
        p=packet("bigwigs","bars_clear");deliver(p,true);return
    elseif msg=="BigWigs_Message" then
        -- module,key,text,color,icon,emphasized
        p=packet("bigwigs","message");p.put("text",text(b));p.put("spellId",number(a,1,2147483647))
        p.put("messageType",type(c)=="string" and not secret(c) and c or nil);p.put("emphasized",e==true)
        if type(d)=="number" and not secret(d) then p.put("icon",d) end
    elseif msg=="BigWigs_OnBossEngage" or msg=="BigWigs_OnBossWin" or msg=="BigWigs_OnBossWipe" then
        p=packet("bigwigs",msg=="BigWigs_OnBossEngage" and "engage" or msg=="BigWigs_OnBossWin" and "win" or "wipe");bwInfo(p,module)
        if msg~="BigWigs_OnBossEngage" then
            local name=moduleName(module);untrack("bigwigs",function(bar) return bar.id:sub(1,#name+1)==name.."|" end);deliver(p,true);return
        end
    elseif msg=="BigWigs_SetStage" then p=packet("bigwigs","stage");bwInfo(p,module);p.put("stage",number(a,0,100))
    elseif msg=="BigWigs_StartPull" then p=packet("bigwigs","pull_start");local d=number(a,.01,3600);p.put("duration",d);if d then p.put("expiration",now()+d) end;p.put("initiator",(text(b)))
    elseif msg=="BigWigs_StopPull" then p=packet("bigwigs","pull_stop");p.put("initiator",(text(a)))
    else return end
    deliver(p)
end
-- Binding -----------------------------------------------------------------
local function dbmAvailable() return type(DBM)=="table" and not secret(DBM) and type(DBM.RegisterCallback)=="function" end
local function bigwigsAvailable() return type(BigWigsLoader)=="table" and not secret(BigWigsLoader) and type(BigWigsLoader.RegisterMessage)=="function" end
function B:Bind()
    if dbmAvailable() and not next(self.dbm) then
        for _,event in ipairs(dbmEvents) do
            local handler=function(ev,...) local ok=pcall(B.DBM,B,ev,...);return ok end
            if pcall(DBM.RegisterCallback,DBM,event,handler) then self.dbm[event]=handler end
        end
    end
    if bigwigsAvailable() and not self.bigwigs then
        self.bigwigs=true
        for _,msg in ipairs(bwMessages) do pcall(BigWigsLoader.RegisterMessage,self.owner,msg,function(m,...) pcall(B.BigWigs,B,m,...) end) end
    end
end
function B:Status()
    local dbm,bw=next(self.dbm)~=nil,self.bigwigs==true
    if dbm and bw then return "DBM and BigWigs" elseif dbm then return "DBM" elseif bw then return "BigWigs" end
    return "no boss mod loaded"
end
-- notify(packet,changed): packet for event nodes, changed=true when the bar list changed.
function B:Start(notify)
    self.notify=notify;self:Bind()
    if not self.listening then
        self.listening=true
        BVAddonSuiteCore.Events:Subscribe(self,"ADDON_LOADED",function() self:Bind() end)
        BVAddonSuiteCore.Events:Subscribe(self,"PLAYER_ENTERING_WORLD",function() self.bars={};self:ScheduleExpiry();deliver(nil,true) end)
    end
end
function B:Stop()
    self.notify=nil
    if self.listening then BVAddonSuiteCore.Events:Release(self);self.listening=nil end
    for event,handler in pairs(self.dbm) do if dbmAvailable() then pcall(DBM.UnregisterCallback,DBM,event,handler) end end
    self.dbm={}
    if self.bigwigs and bigwigsAvailable() then for _,msg in ipairs(bwMessages) do pcall(BigWigsLoader.UnregisterMessage,self.owner,msg) end end
    self.bigwigs=false;self.bars={};self.recent=nil
    if self.expiryTimer then self.expiryTimer:Cancel();self.expiryTimer=nil end
end
-- Best matching bar for the Bossmod timer node.
function B:Find(config)
    local best
    local needle=config.text~="" and A.TextOps.Fold(config.text) or nil
    for _,bar in pairs(self.bars) do
        local ok=(config.provider=="any" or bar.provider==config.provider)
            and (config.spellID==0 or bar.spellId==config.spellID)
            and (not needle or (bar.text and A.TextOps.Fold(bar.text):find(needle,1,true)~=nil))
            and (config.includePaused or not bar.paused)
        if ok then
            local e=bar.paused and (now()+(bar.remaining or 0)) or bar.expiration
            if not best or (config.pick=="latest" and e>best.e) or (config.pick~="latest" and e<best.e) then best={bar=bar,e=e} end
        end
    end
    return best and best.bar
end
-- Nodes -------------------------------------------------------------------
local function port(label,kind,order) return {label=label,type=kind,order=order,optional=true} end
local providers={"any","dbm","bigwigs"}
local providerLabels={any="Any",dbm="Deadly Boss Mods",bigwigs="BigWigs"}
local event={label="Bossmod event",nativeEvent=true,category="triggers",inputs={active={label="Active",type="boolean",default=true,order=1}},outputs={},
    defaults={provider="any",eventType="any",spellID=0,text=""},
    help="Fires on events from Deadly Boss Mods or BigWigs, whichever is installed; nothing happens without them. Types: bar start/update/pause/resume/stop, bars cleared, message, pull start/stop, engage, win, wipe, stage. Filter by provider, type, spell ID (0 = any) and text (contains, ignoring case). Read-only: the node never changes boss mod settings. On WoW Forever both boss mods ship few boss modules, so mainly pull, break and custom timers plus engage/win/wipe arrive; check natively."}
event.resolve=function(c)
    local types={any=true};for _,k in ipairs(B.kinds) do types[k]=true end
    if not providerLabels[c.provider] or not types[c.eventType] or not G.Number(c.spellID) or c.spellID<0 or c.spellID~=math.floor(c.spellID) or type(c.text)~="string" or #c.text>64 then return nil,"Choose provider, type and filters" end
    local d=G.Copy(event);d.resolve=nil
    local typeChoices={"any"};for _,k in ipairs(B.kinds) do typeChoices[#typeChoices+1]=k end
    d.fields={{key="eventType",label="Event type",choices=typeChoices,primary=true},{key="provider",label="Boss mod",choices=providers,choiceLabels=providerLabels},
        {key="spellID",label="Spell ID (0 = any)",type="integer",picker="aura"},{key="text",label="Text contains",type="string"}}
    d.outputs={event=port("Trigger","event",1),eventType=port("Type","string",2),provider=port("Boss mod","string",3),text=port("Text","string",4),spellId=port("Spell ID","integer",5),
        duration=port("Duration (s)","float",6),expiration=port("Expiration","float",7),count=port("Count","integer",8),stage=port("Stage","integer",9),
        encounterId=port("Encounter ID","integer",10),encounterName=port("Encounter","string",11),emphasized=port("Emphasized","boolean",12),icon=port("Icon","integer",13),id=port("Bar ID","string",14)}
    for _,p in pairs(d.outputs) do if p.type~="event" then p.maySecret=true end end
    return d
end
A.catalog.bossmod_event=event;A.order[#A.order+1]="bossmod_event"
local timer={label="Bossmod timer",flowOperation="bossmod_timer",source=true,bossmodTimer=true,inputs={},outputs={},
    defaults={provider="any",spellID=0,text="",pick="soonest",includePaused=false},
    help="The running Deadly Boss Mods or BigWigs timer that matches the spell ID or text (contains, ignoring case), e.g. a pull or break timer. Soonest picks the timer that ends first. Updated only when timers change and when the chosen timer ends; Remaining is sampled then, so use Expiration with Remaining Estimate for a live countdown. Active=false when no timer matches or no boss mod is installed."}
timer.resolve=function(c)
    if not providerLabels[c.provider] or not G.Number(c.spellID) or c.spellID<0 or c.spellID~=math.floor(c.spellID) or type(c.text)~="string" or #c.text>64
        or (c.pick~="soonest" and c.pick~="latest") or type(c.includePaused)~="boolean" then return nil,"Choose provider and filters" end
    local d=G.Copy(timer);d.resolve=nil
    d.fields={{key="provider",label="Boss mod",choices=providers,choiceLabels=providerLabels,primary=true},{key="spellID",label="Spell ID (0 = any)",type="integer",picker="aura"},
        {key="text",label="Text contains",type="string"},{key="pick",label="Several match",choices={"soonest","latest"},choiceLabels={soonest="Soonest",latest="Latest"}},
        {key="includePaused",label="Include paused",type="boolean"}}
    d.outputs={active=port("Active","boolean",1),remaining=port("Remaining (s)","float",2),duration=port("Duration (s)","float",3),expiration=port("Expiration","float",4),
        startTime=port("Start time","float",5),paused=port("Paused","boolean",6),text=port("Text","string",7),spellId=port("Spell ID","integer",8),count=port("Count","integer",9),provider=port("Boss mod","string",10)}
    return d
end
A.catalog.bossmod_timer=timer;A.order[#A.order+1]="bossmod_timer"
