local _,L=...
if not L.ready then return end
-- "Your actions" from Blizzard's Combat Log (research 2026-10-04,
-- docs/research/2026-10-04-battletext-forever.md; idea from BattleText
-- Forever, MIT, own code). COMBAT_LOG_MESSAGE delivers each line the Combat
-- Log window would show. On Forever the text is hidden (|K token), but when
-- the window's filter only takes lines whose source is you ("Done By: Me",
-- as in WoW's default "My actions"), each line says "you did something now",
-- and a hit on an enemy without one is someone else's (pet, group, Thorns).
-- There is one Combat Log with one active filter, chosen by the player;
-- addons cannot set it (C_CombatLogSecure is SecureOnly). So the filter is
-- read (Blizzard_CombatLog_CurrentSettings) and the signal is used only while
-- it takes your own actions and nothing else. Otherwise, and before the
-- first line, numbers are shown as without the signal: never worse.
-- Lines only flow after the Combat Log window was shown by a real click
-- (Blizzard loads its filter in the window's OnShow; Blizzard's code and
-- Florian's test 2026-10-05). Never call C_CombatLog.ApplyFilterSettings:
-- Blizzard-only. Afterwards an addon may keep them on with
-- C_CombatLog.SetFilteredEventsEnabled(true).
-- Matching, independent of spells and of the event types in the filter
-- (Florian's trace 2026-10-05, default filter): a spell hit or tick and its
-- line share one frame (tick: hit, then line); one action can bring several
-- lines (Drain Life: damage and heal). So a line vouches for a hit of its
-- own frame only, and lines left over in a frame (heals, kills, ...) lapse.
-- The one exception is your auto attack: its line comes 0.2-1.2 s before the
-- hit (the hit waits for the animation; BattleText Forever's recordings).
local ns=L.ns
local G={CREDIT=1.2,QUIET=30,KEEP=3,CHECK=2,lines={},hits={},seq=0}
L.Log=G
G.BUTTON="BVCombatTextLogStart"
G.TAB="ChatFrame2"

local function readable(v) return v~=nil and not L.Secret(v) end
local function count(key) L.Sources.Count(key) end
local function now() return GetTime() end
local function locked() return InCombatLockdown and InCombatLockdown() end
local function refresh() if ns.Config and ns.Config.Refresh then pcall(ns.Config.Refresh,ns.Config) end end

-- The filter, read the way Blizzard applies it (Blizzard_CombatLogProcessor:
-- ApplyFilterSettings): each part of the filter adds lines for its source
-- and target flags; a part whose flags are all off adds nothing (Blizzard's
-- "HACK" branch), a part without source flags takes any source. Fine only
-- when every part that adds lines is limited to sources within "Me"
-- (COMBATLOG_FILTER_MINE) and, if the player wants, "Pet"
-- (COMBATLOG_FILTER_MY_PET): then your pet's hits count as yours. Done By
-- with Friends, Enemy Units, ... adds other bits.
local function flagKind(t,mine,pet)
    if t==nil then return "any" end
    if type(t)~="table" then return "unknown" end
    local kind="zero"
    for k,v in pairs(t) do
        if type(k)=="string" then return "guid" end
        if v and type(k)=="number" then
            if bit.band(k,mine)==k then
                if kind=="zero" then kind="mine" end
            elseif pet and bit.band(k,pet)==k then kind="minepet"
            else return "other" end
        end
    end
    return kind
end
-- "mine" (only yours), "minepet" (yours and your pet's), "others" (lines
-- of someone else too), "empty" or "unknown"; plus the filter's name.
function G:FilterState()
    local settings=_G.Blizzard_CombatLog_CurrentSettings
    local mine,pet=_G.COMBATLOG_FILTER_MINE,_G.COMBATLOG_FILTER_MY_PET
    if type(settings)~="table" or type(settings.filters)~="table" or type(mine)~="number" or not (bit and bit.band) then return "unknown" end
    if type(pet)~="number" then pet=nil end
    local name=type(settings.name)=="string" and settings.name or nil
    local state="empty"
    for _,part in pairs(settings.filters) do
        if type(part)~="table" then return "unknown",name end
        local s,d=flagKind(part.sourceFlags,mine,pet),flagKind(part.destFlags,mine,pet)
        if s=="unknown" or d=="unknown" then return "unknown",name end
        -- Blizzard: a GUID on one side with nothing on the other is that unit alone.
        if s=="guid" and d=="zero" then d="any" end
        if d=="guid" and s=="zero" then s="any" end
        if s~="zero" and d~="zero" then
            if s~="mine" and s~="minepet" then return "others",name end
            if s=="minepet" or state=="empty" then state=s end
        end
    end
    return state,name
end
G.USABLE={mine=true,minepet=true}
-- Checked at most every 2 s (the player may change it at any time).
function G:FilterOK()
    local t=now()
    if not self.checked or t-self.checked>=self.CHECK then
        self.checked=t
        local ok,state,name=pcall(self.FilterState,self)
        if not ok then state,name="unknown",nil end
        if state~=self.filter then
            self.filter,self.filterName=state,name
            self:Trace("filter "..state..(name and " ("..name..")" or ""))
            refresh()
        end
    end
    return self.USABLE[self.filter]==true
end

-- In use: option on, the Combat Log was shown since login (its filter is
-- loaded), the filter takes only yours and the game delivers lines. Then a
-- fight where only your pet hits is told apart too (Florian 2026-10-05: with
-- "a line in the last 30 s" as the test it was not). Without
-- AreFilteredEventsEnabled: a line in the last 30 s.
function G:Flowing()
    if not (L:Active() and L:Config().logSignal) then return false end
    if not self.started or not self:FilterOK() then return false end
    local f=C_CombatLog and C_CombatLog.AreFilteredEventsEnabled
    if type(f)=="function" then
        local ok,on=pcall(f)
        if ok and readable(on) then return on==true end
    end
    return self.last~=nil and now()-self.last<=self.QUIET
end
-- Hits that wait for the end of their frame: damage on enemies and heals on
-- others (misses may have no line); not the simulation.
function G:Holds(unit,action,_,_,_,enemy)
    if enemy or not self:Flowing() then return false end
    if not readable(action) or (action~="WOUND" and action~="HEAL") then return false end
    return L.Sources:Kind(unit)=="plate"
end

-- Diagnosis: the last lines and hits with their decision in
-- BVCombatTextDB.logTrace (time, unit token, amount, school; no names).
G.TRACE_MAX=300
function G:Trace(text)
    local db=L:DB()
    if type(db.logTrace)~="table" then db.logTrace={} end
    local list=db.logTrace
    list[#list+1]=string.format("%.2f %s",now(),text)
    while #list>self.TRACE_MAX do table.remove(list,1) end
end

function G:Line(_,_,_,_,order)
    -- History replayed when the window refills (also at login) is not new.
    local oldest=Enum and Enum.CombatLogMessageOrder and Enum.CombatLogMessageOrder.Oldest
    if oldest~=nil and readable(order) and order==oldest then count("log: history line");return end
    self.seq=self.seq+1
    local t=now()
    self.lines[#self.lines+1]={time=t,seq=self.seq}
    self.last=t
    count("log: line")
    self:Trace("line #"..self.seq)
    if not self.started then self.started=true;self:Keep();self:Update();refresh() end
    self:Trim(t)
end
function G:Trim(t)
    local list=self.lines
    while list[1] and (list[1].used or t-list[1].time>self.CREDIT) do table.remove(list,1) end
end
-- A hit waits until its frame is over, so a line right behind it counts.
-- swing: a swing's line runs ahead of its hit (its animation): you were auto
-- attacking (melee, wand, auto shot), or the filter takes your pet and you
-- have one: a pet's line runs ahead of its hit (Florian's traces 2026-10-05:
-- voidwalker swing 0.55 s, imp Firebolt 0.01-0.1 s and up to 1.04 s at a
-- distance). UnitIsUnit("pettarget",unit) never answered yes in combat (unit
-- comparison is protected), so the pet's target cannot narrow it down.
function G:Queue(run,label,unit,school)
    self.seq=self.seq+1
    local swing=L.Attribution.AutoAttacking()~=nil and "auto" or nil
    if not swing and self.filter=="minepet" then
        local ok,pet=pcall(UnitExists,"pet")
        if ok and pet==true and not L.Secret(pet) then swing="pet" end
    end
    self.hits[#self.hits+1]={time=now(),seq=self.seq,run=run,label=label,auto=swing~=nil,swing=swing}
    if not self.flush then self.flush=C_Timer.NewTimer(0,function() G:Flush() end) end
end
-- One line, one hit. First a line right behind the hit in its frame (a
-- tick), then one before it in its frame (a direct hit); from an earlier
-- frame only while auto attacking (a swing's line runs ahead of its hit).
function G:Claim(hit)
    local after,same,earlier
    for _,line in ipairs(self.lines) do
        if not line.used then
            if line.time==hit.time then
                if line.seq>hit.seq then after=after or line else same=same or line end
            elseif hit.auto and line.seq<hit.seq and hit.time-line.time<=self.CREDIT then earlier=earlier or line end
        end
    end
    local line=after or same or earlier
    if not line then return false end
    line.used=true
    -- A line ahead of the hit taken for your pet's swing (Origin: pet melee).
    if line==earlier and hit.swing=="pet" then return "petswing",line end
    return after and "tick" or "line",line
end
function G:Flush()
    self.flush=nil
    local hits=self.hits
    self.hits={}
    for _,hit in ipairs(hits) do
        local credit,line=self:Claim(hit)
        self:Trace(string.format("hit #%d %s%s -> %s",hit.seq,tostring(hit.label or "?"),hit.swing and " "..hit.swing or "",
            credit and string.format("%s #%d (%.2f s)",credit,line.seq,hit.time-line.time) or "no line"))
        local ok,err=pcall(hit.run,credit)
        if not ok then count("error");L.Sources.lastError=tostring(err) end
    end
    self:Trim(now())
end

-- Keep the lines on after Blizzard turns them off (window hidden).
function G:Keep()
    if not ((self.started or self.forced) and L:Active() and L:Config().logSignal) then return end
    local f=C_CombatLog and C_CombatLog.SetFilteredEventsEnabled
    if type(f)=="function" then pcall(f,true) end
end
-- Back to the game's own state: lines only while the window is shown.
function G:Release()
    if not (self.started or self.forced) then return end
    local f=C_CombatLog and C_CombatLog.SetFilteredEventsEnabled
    local window=_G[self.TAB]
    local shown=false
    if window and window.IsShown then local ok,v=pcall(window.IsShown,window);shown=ok and v==true end
    if type(f)=="function" then pcall(f,shown) end
end

-- Start button: a secure macro button clicks the Combat Log tab and back to
-- the tab you were on, so Blizzard's own code shows the window untainted.
-- AnyUp and AnyDown: the game runs a macro button on one of them (setting
-- ActionButtonUseKeyDown). Protected: created, changed and hidden only out
-- of combat. Named, so a macro can do the same: /click BVCombatTextLogStart.
function G:Macro()
    local current=SELECTED_CHAT_FRAME
    local name
    if current and current.GetName then local ok,v=pcall(current.GetName,current);if ok and readable(v) then name=v end end
    if name==self.TAB then return "/click ChatFrame1Tab\n/click "..self.TAB.."Tab" end
    return "/click "..self.TAB.."Tab\n/click "..(name or "ChatFrame1").."Tab"
end
function G:Wanted()
    if self.stopped or not (L:Active() and L:Config().logSignal and L:Config().logButton) then return false end
    return not self.started and _G[self.TAB.."Tab"]~=nil
end
function G:CreateButton()
    self.button=L.LogButton.Create(self.BUTTON)
    return self.button
end
-- Shows or hides the button and refreshes its macro (out of combat only).
function G:Update()
    if locked() then self.pending=true;return end
    self.pending=nil
    local want=self:Wanted()
    local b=self.button
    if want and not b then b=self:CreateButton() end
    if not b then return end
    if want then b:SetAttribute("macrotext",self:Macro());b:Show() else b:Hide() end
end

function G:Hook()
    if self.hooked then return end
    local window=_G[self.TAB]
    if not (window and window.HookScript) then return end
    self.hooked=true
    -- Shown by a click: Blizzard loaded its filter, lines will come.
    window:HookScript("OnShow",function()
        if not L:Active() then return end
        if not G.started then G.started=true;G:Update() end
        G:Keep()
    end)
    -- Blizzard turns the lines off as the window hides; turn them back on.
    window:HookScript("OnHide",function() if L:Active() then G:Keep() end end)
end

-- What the player sees (settings page, /bv sct debug): the overall state and
-- the two setup steps, each with its reason.
G.FILTER_TEXT={
    mine="takes only your own actions",
    minepet="takes yours and your pet's: your pet counts as yours",
    others="also takes others (\"Done By\" has more than \"Me\" and \"Pet\"): not used",
    empty="takes nothing: not used",
    unknown="not readable yet (open the Combat Log once)",
}
function G:Status()
    self.checked=nil
    self:FilterOK()
    local cfg=L:Config()
    local opened=self.started==true
    local filter=self.filter or "unknown"
    local state
    if not cfg.logSignal then state="off"
    elseif not opened then state="setup"
    elseif not self.USABLE[filter] then state="filter"
    elseif self:Flowing() then state="active"
    else state="waiting" end
    return {state=state,opened=opened,filter=filter,filterName=self.filterName,forced=self.forced}
end
G.STATE_TEXT={
    off="off",
    setup="not set up: open the Combat Log tab once (or click the Start button)",
    filter="off: the Combat Log filter does not fit",
    active="active: your hits are told apart from others'",
    waiting="paused: the game does not deliver Combat Log lines right now",
}
function G:Report()
    local s=self:Status()
    L:Print("combat log signal: "..self.STATE_TEXT[s.state]..(s.forced and " (forced)" or ""))
    L:Print("combat log filter"..(s.filterName and " \""..s.filterName.."\"" or "")..": "..self.FILTER_TEXT[s.filter])
end
-- Test (2026-10-05): do lines come with SetFilteredEventsEnabled(true) alone,
-- without the window ever shown? BattleText Forever says the filter needs a
-- real click; unconfirmed. ApplyFilterSettings is never called.
function G:Force()
    if not L:Active() then L:Print("Turn the module on first.");return end
    local f=C_CombatLog and C_CombatLog.SetFilteredEventsEnabled
    if type(f)~="function" then L:Print("C_CombatLog.SetFilteredEventsEnabled is missing.");return end
    local ok,err=pcall(f,true)
    self.forced=ok or nil
    self:Trace("force "..(ok and "ok" or "error"))
    L:Print(ok and "Combat log lines switched on without the Combat Log tab (test). Fight, then /bv sct debug." or "Failed: "..tostring(err))
end
L.commands.log=function(rest)
    if rest=="force" then G:Force() else G:Report() end
end

function G:Enable(context)
    -- started survives off/on: the filter stays loaded until /reload. A
    -- window already shown at login does not count (no real click).
    self.lines,self.hits,self.last,self.flush,self.stopped,self.checked={},{},nil,nil,nil,nil
    local ok=pcall(context.Subscribe,context,"COMBAT_LOG_MESSAGE",function(_,...) G:Line(...) end)
    if not ok then count("log: event missing") end
    -- The macro can change only out of combat: refreshed as a fight starts
    -- (still unlocked) and after it.
    context:Subscribe("PLAYER_REGEN_DISABLED",function() if G.button or G:Wanted() then G:Update() end end)
    context:Subscribe("PLAYER_REGEN_ENABLED",function() if G.pending or G.button then G:Update() end end)
    self:Hook()
    self.ticker=C_Timer.NewTicker(self.KEEP,function() G:Keep() end)
    self:Update()
    context:Defer(function()
        G.stopped=true
        if G.ticker then G.ticker:Cancel();G.ticker=nil end
        if G.flush then G.flush:Cancel();G.flush=nil end
        G.hits,G.lines={},{}
        G:Release()
        -- Hidden now or after combat.
        if G.button then G:Update() end
        if G.pending then ns.Events:Subscribe(G,"PLAYER_REGEN_ENABLED",function() ns.Events:Release(G);G:Update() end) end
    end)
end
