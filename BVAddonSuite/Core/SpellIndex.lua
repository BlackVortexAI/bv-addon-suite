-- Shared, lazy spell-name index. No native icon or full-info lookup is permitted.
local _,ns=...
local Index={}; Index.__index=Index; ns.SpellIndexModel=Index
local FORMAT,MAX_ID=1,2000000
local function number(v) return type(v)=="number" and v==v and v>=0 and v<math.huge end
local function bound(v,low,high) return math.max(low,math.min(high,v)) end
function Index.New(api,events,options)
    return setmetatable({api=api,events=events,owners={},maxID=options and options.maxID or MAX_ID},Index)
end
function Index:Identity()
    local version,build,_,interface=self.api.GetBuildInfo()
    local locale=self.api.GetLocale()
    local project=tostring(self.api.WOW_PROJECT_ID or "unknown")
    local slot=project.."|"..(version:match("^%d+") or version).."|"..locale
    return {slot=slot,key=table.concat({project,version,tostring(build),tostring(interface),locale,tostring(FORMAT),tostring(self.maxID)},"|"),
        version=version,build=build,interface=interface,locale=locale,project=project,format=FORMAT}
end
function Index:Store()
    local api=self.api
    api.BVSpellIndexDB=api.BVSpellIndexDB or {schema=1,slots={}}
    local db=api.BVSpellIndexDB
    assert(type(db)=="table" and db.schema==1 and type(db.slots)=="table","Unsupported spell-index storage; existing data preserved")
    return db
end
function Index:Current()
    if not self.target then return end
    local slot=self:Store().slots[self.target.slot]
    local current=type(slot)=="table" and slot.current
    if type(current)=="table" and current.complete==true and current.key==self.target.key and current.format==FORMAT
        and current.maxID==self.maxID and number(current.count) and type(current.entries)=="table" and #current.entries==current.count then return current end
end
function Index:Lookup(id)
    -- Reuse persisted identity without starting a scan. Entries are published in
    -- ascending ID order, so selected-object reads cost logarithmic time.
    if not self.target then self.target=self:Identity() end
    local current=self:Current(); if not current then return end
    local first,last=1,#current.entries
    while first<=last do
        local middle=math.floor((first+last)/2); local entry=current.entries[middle]
        if entry.id==id then return {value=id,name=entry.name} end
        if entry.id<id then first=middle+1 else last=middle-1 end
    end
end
function Index:WatchReady(owner,callback)
    self.readyListeners=self.readyListeners or {}; self.readyListeners[owner]=callback
    return function() self.readyListeners[owner]=nil end
end
function Index:Open(owner)
    assert(owner,"Owner required")
    self.owners[owner]=true
    local ok,why=pcall(function()
        local target=self:Identity()
        if self.target and self.target.key~=target.key then self:Cancel(); self.failure=nil; self.searchCache=nil end
        self.target=target
        self:Start()
    end)
    if not ok then self:Cancel(); self.failure="Index unavailable: "..tostring(why) end
    return self:Status()
end
function Index:Close(owner)
    self.owners[owner]=nil
    if not next(self.owners) then self:Cancel(); self.failure=nil; self.searchCache=nil end
end
function Index:Cancel()
    if self.timer then self.timer:Cancel(); self.timer=nil end
    self.events:Release(self)
    self.job=nil
end
function Index:Retry()
    self:Cancel(); self.failure=nil
    if next(self.owners) then
        local ok,why=pcall(self.Start,self)
        if not ok then self:Cancel(); self.failure="Index unavailable: "..tostring(why) end
    end
end
function Index:Start()
    if self.job or self.failure or self:Current() then return end
    local api=self.api
    if not (api.C_Spell and type(api.C_Spell.GetSpellName)=="function" and api.GetTimePreciseSec and api.GetTime and api.C_Timer and api.C_Timer.NewTicker) then
        self.failure="This client lacks the tested name-only lookup or timing API. No unsafe fallback is used."; return
    end
    local now=api.GetTimePreciseSec()
    self.job={nextID=1,entries={},count=0,budgetMs=.5,lastWorkMs=0,baselineUntil=now+.5,baselineTotal=0,baselineCount=0,
        started=now,workMs=0,maxSliceMs=0,slices=0,adjustFrames=0,minBudgetMs=.5,maxBudgetMs=.5}
    self.events:Subscribe(self,"PLAYER_LOGOUT",function() self:Cancel() end)
    self.timer=api.C_Timer.NewTicker(.001,function()
        local ok=pcall(self.Tick,self)
        if not ok then self:Cancel(); self.failure="Spell-name scan failed. Previous index preserved; no partial results selectable." end
    end)
end
function Index:Read(id)
    local name=self.api.C_Spell.GetSpellName(id)
    if self.api.issecretvalue and self.api.issecretvalue(name) then error("Unreadable spell name") end
    if name==nil then return end
    assert(type(name)=="string","Invalid spell name")
    if name~="" then return name end
end
function Index:Tick()
    local j=self.job; if not j then return end
    local api=self.api; local frame=api.GetTime()
    if frame==j.lastFrame then return end
    j.lastFrame=frame
    local now=api.GetTimePreciseSec()
    if api.InCombatLockdown and api.InCombatLockdown() then
        j.paused=true; j.pauseStart=j.pauseStart or now; j.lastTick=nil; return
    end
    if j.paused then
        if not j.baselineMs then j.baselineUntil=j.baselineUntil+(now-j.pauseStart) end
        j.paused=false; j.pauseStart=nil
    end
    local gap=j.lastTick and (now-j.lastTick)*1000
    j.lastTick=now
    if now<j.baselineUntil then
        if gap and gap>0 then j.baselineTotal=j.baselineTotal+gap; j.baselineCount=j.baselineCount+1 end
        return
    end
    j.baselineMs=j.baselineMs or bound(j.baselineCount>0 and j.baselineTotal/j.baselineCount or 16.67,8,50)
    if gap and (gap>j.baselineMs*1.25 or j.lastWorkMs>j.budgetMs+1) then
        j.budgetMs=math.max(.25,j.budgetMs*.5); j.adjustFrames=0
    else
        j.adjustFrames=j.adjustFrames+1
        if j.adjustFrames>=15 then j.budgetMs=math.min(6,j.baselineMs*.3,j.budgetMs+.25); j.adjustFrames=0 end
    end
    j.minBudgetMs=math.min(j.minBudgetMs,j.budgetMs); j.maxBudgetMs=math.max(j.maxBudgetMs,j.budgetMs)
    local started=api.GetTimePreciseSec(); local processed=0
    repeat
        local id=j.nextID; local name=self:Read(id)
        if name then j.count=j.count+1; j.entries[j.count]={id=id,name=name,lower=name:lower()} end
        j.nextID=id+1; processed=processed+1
    until j.nextID>self.maxID or processed>=10000 or (api.GetTimePreciseSec()-started)*1000>=j.budgetMs
    local elapsed=(api.GetTimePreciseSec()-started)*1000
    j.lastWorkMs=elapsed; j.workMs=j.workMs+elapsed; j.maxSliceMs=math.max(j.maxSliceMs,elapsed); j.slices=j.slices+1
    if j.nextID>self.maxID then
        assert(j.count>0,"No spell names found")
        local current={complete=true,key=self.target.key,identity=self.target,format=FORMAT,maxID=self.maxID,entries=j.entries,count=j.count,
            iconPolicy="active-aura-only",metrics={wallSeconds=api.GetTimePreciseSec()-j.started,workMs=j.workMs,maxSliceMs=j.maxSliceMs,
                slices=j.slices,minBudgetMs=j.minBudgetMs,maxBudgetMs=j.maxBudgetMs,baselineFrameMs=j.baselineMs}}
        -- One atomic publication. An old build stays stored until this point.
        self:Store().slots[self.target.slot]={current=current}
        self.searchCache=nil; self:Cancel()
        for _,callback in pairs(self.readyListeners or {}) do callback() end
    end
end
function Index:Status()
    if self.failure then return {ready=false,state="failed",message=self.failure,progress=0} end
    local j=self.job
    if j then
        local state=j.paused and "paused" or (j.baselineMs and "building" or "baseline")
        return {ready=false,state=state,progress=(j.nextID-1)/self.maxID,count=j.count,budgetMs=j.budgetMs,
            message=j.paused and "Index paused during combat." or string.format("Building spell index: %.1f%% | %d names | %.2f ms/frame",(j.nextID-1)/self.maxID*100,j.count,j.budgetMs)}
    end
    local current=self.target and self:Current()
    if current then return {ready=true,state="ready",progress=1,count=current.count,key=current.key,message=current.count.." spell IDs indexed. Icons only from readable active auras."} end
    return {ready=false,state="idle",progress=0,message="Open the selector to build this client's spell index."}
end
local function nameRank(name,query)
    if name==query then return 1 end
    local position=name:find(query,1,true)
    if not position then return end
    if position==1 then return 2 end
    repeat
        -- ASCII punctuation/space boundaries do not mistake UTF-8 continuation
        -- bytes for separators. A later word match beats an earlier infix.
        local previous=name:byte(position-1)
        if previous<=32 or (previous>=33 and previous<=47) or (previous>=58 and previous<=64)
            or (previous>=91 and previous<=96) or (previous>=123 and previous<=126) then return 3 end
        position=name:find(query,position+1,true)
    until not position
    return 4
end
local function before(rank,length,key,id,other)
    if rank~=other.rank then return rank<other.rank end
    if length~=other.length then return length<other.length end
    if key~=other.key then return key<other.key end
    return id<other.entry.id
end
function Index:Search(query)
    if not self:Status().ready then return {},false end
    query=(query or ""):sub(1,100):match("^%s*(.-)%s*$"):lower()
    if self.searchCache and self.searchCache.query==query then return self.searchCache.rows,self.searchCache.truncated end
    local rows,top={},{}; local truncated=false; local matches=0
    local numeric=query:match("^%d+$") and tonumber(query)
    local entries=self:Current().entries
    if query=="" then
        for i=1,math.min(200,#entries) do rows[i]={value=entries[i].id,name=entries[i].name} end
        truncated=#entries>200
    else
        for _,entry in ipairs(entries) do
            local key=numeric and tostring(entry.id) or entry.lower
            local rank
            if numeric then
                local position=key:find(query,1,true)
                if entry.id==numeric then rank=1 elseif position then rank=position==1 and 2 or 3 end
            else rank=nameRank(key,query) end
            if rank then
                matches=matches+1
                -- Keep only the best 200 candidates, but inspect the whole saved
                -- index so a late exact match can displace an early weak match.
                local length=#key
                if #top<200 or before(rank,length,key,entry.id,top[#top]) then
                    local first,last=1,#top
                    while first<=last do
                        local middle=math.floor((first+last)/2)
                        if before(rank,length,key,entry.id,top[middle]) then last=middle-1 else first=middle+1 end
                    end
                    table.insert(top,first,{entry=entry,rank=rank,length=length,key=key})
                    if #top>200 then table.remove(top) end
                end
            end
        end
        truncated=matches>200
        for i,item in ipairs(top) do rows[i]={value=item.entry.id,name=item.entry.name} end
    end
    if numeric and #rows==0 and number(numeric) and numeric>0 and numeric<=2147483647 and numeric==math.floor(numeric) then
        rows[1]={value=numeric,name="Unverified ID",unverified=true}
    end
    self.searchCache={query=query,rows=rows,truncated=truncated}
    return rows,truncated
end
ns.SpellIndex=Index.New(_G,ns.Events)
