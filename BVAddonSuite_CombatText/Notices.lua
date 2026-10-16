local _,L=...
if not L.ready then return end
-- Aura and status messages from COMBAT_TEXT_UPDATE, the event Blizzard's own
-- text at your character is built from (Blizzard_CombatText, read 2026-10-02):
-- C_CombatText.GetCurrentEventInfo() gives data, arg3, arg4 per message type.
-- On Forever the values are secret but displayable (probe 2026-10-01), so they
-- are only joined and formatted, never compared. Damage, heals and misses are
-- skipped here: UNIT_COMBAT covers them. Combat start and end come from
-- PLAYER_REGEN_DISABLED/ENABLED, as in Blizzard's code.
local F=L.Format
local N={}
L.Notices=N

local function readable(v) return v~=nil and not L.Secret(v) end
-- Joins parts; a part that cannot be joined (secret in a test double) is
-- left out rather than failing the whole message.
local function join(...)
    local out=""
    for i=1,select("#",...) do
        local part=select(i,...)
        if part~=nil then
            local ok,text=pcall(function() return out..part end)
            if ok then out=text end
        end
    end
    return out
end
N.Join=join
local function info()
    local f=C_CombatText and C_CombatText.GetCurrentEventInfo or GetCurrentCombatTextEventInfo
    if type(f)~="function" then return nil end
    local ok,data,arg3,arg4=pcall(f)
    if ok then return data,arg3,arg4 end
end
-- Localized power name for a readable power token ("MANA" -> "Mana").
local function powerName(token)
    if not readable(token) or type(token)~="string" then return nil end
    local name=_G[token]
    if type(name)=="string" and not L.Secret(name) then return name end
end

-- One message type to {category, core text, kind} or nil (not ours / off).
function N:Message(messageType,data,arg3)
    local cfg=L:Config()
    local cat=cfg.categories
    if messageType=="SPELL_AURA_START" or messageType=="SPELL_AURA_START_HARMFUL" then
        local name=messageType=="SPELL_AURA_START" and "buff" or "debuff"
        if data==nil or not cat[name].gains then return nil end
        return name,join("+",data),"gain"
    elseif messageType=="SPELL_AURA_END" or messageType=="SPELL_AURA_END_HARMFUL" then
        local name=messageType=="SPELL_AURA_END" and "buff" or "debuff"
        if data==nil or not cat[name].fades then return nil end
        return name,join("-",data),"fade"
    elseif messageType=="ENERGIZE" or messageType=="PERIODIC_ENERGIZE" then
        if data==nil then return nil end
        if readable(data) and (type(data)~="number" or data<=0) then return nil end
        local power=powerName(arg3)
        return "power",join("+",F.Number(data,cfg.numbers),power and " " or nil,power),"power"
    elseif messageType=="FACTION" then
        if data==nil or not cat.notice.reputation then return nil end
        local amount=arg3
        if readable(amount) and type(amount)=="number" then
            amount=(amount>0 and "+" or "")..F.Number(amount,"full")
        end
        return "notice",join(data," ",amount),"reputation"
    elseif messageType=="HONOR_GAINED" then
        if data==nil or not cat.notice.honor then return nil end
        if readable(data) and (type(data)~="number" or data<1) then return nil end
        local label=type(HONOR)=="string" and HONOR or "Honor"
        return "notice",join("+",F.Number(data,"plain")," ",label),"honor"
    elseif messageType=="SPELL_ACTIVE" then
        if data==nil or not cat.notice.procs then return nil end
        return "notice",join(data,"!"),"proc"
    end
    return nil
end
function N:Show(category,core,kind)
    local cfg=L:Config()
    local style=cfg.categories[category]
    local entry={category=category,kind=kind,unit="player",incoming=true}
    entry.text=F.Text(style,core,{},false)
    L.Sources.Count("shown "..category.." ("..kind..")")
    return L.Display:Show(entry)
end
function N:Update(messageType)
    if not readable(messageType) then L.Sources.Count("notice: type secret");return nil end
    L.Sources.Count("notice event "..tostring(messageType))
    local data,arg3=info()
    local category,core,kind=self:Message(messageType,data,arg3)
    if not category then return nil end
    return self:Show(category,core,kind)
end
-- Your killing blow (0.7.2): PARTY_KILL names the attacker, readable for you
-- (signal probe 2026-10-07: 3 of 3). Own category "kill" since 0.7.7. 0.7.9
-- (CurseForge wish 2026-10-16): players (PvP) and NPCs apart by the target's
-- GUID, each with or without a sound; a target the game hides counts as an NPC.
-- 0.7.10 (CurseForge report 2026-10-16: no killing blow in PvP, another addon
-- shows them; research of KillingBlow_Enhanced and HeadHunter): your pet's
-- kills count when switched on, every step is counted (/bv sct kills), and a
-- second way for players: the statistic "Total Killing Blows" (1487) rising
-- when the game says your PvP kills changed (PLAYER_PVP_KILLS_CHANGED); in
-- battlegrounds and arenas PARTY_KILL may not come at all.
N.STAT_KILLS=1487
N.CREDIT_TIME=10   -- seconds a shown player kill waits to be found in the statistic
N.RECHECK={.5,1.5} -- the statistic asked again this many seconds later
-- A rise after a hidden kill counts only with honor or a PvP kill this close
-- (CurseForge tester 2026-10-16: battlegrounds showed kills that were not
-- theirs; the statistic counts creatures, pets and totems too).
N.EVIDENCE=3
local function where()
    local ok,inside,kind=pcall(IsInInstance)
    if not ok then return "unknown" end
    if readable(kind) and (kind=="pvp" or kind=="arena") then return kind end
    return inside and "instance" or "world"
end
N.Where=where
function N:ShowKill(player)
    local c=L:Config().categories.kill
    if (player and c.soundPlayers) or (not player and c.soundNpcs) then L.PlayKillSound(c.sound) end
    if (player and not c.players) or (not player and not c.npcs) then return nil end
    local text=type(KILLING_BLOW)=="string" and KILLING_BLOW or "Killing Blow"
    return self:Show("kill",join(text,"!"),"killing blow")
end
function N:Kill(attacker,target)
    local count=L.Sources.Count
    count("kill: event");count("kill: event ("..where()..")")
    local c=L:Config().categories.kill
    if not c.enabled then return nil end
    if not readable(attacker) then
        count("kill: attacker secret")
        -- In battlegrounds and arenas hidden kills are asked of the statistic
        -- (as MiniKillingBlow does on Forever); elsewhere it is only read again
        -- (a hidden creature's kill must not count as a player's later).
        local here=where()
        if here=="pvp" or here=="arena" then self:KillsChanged(nil,"hidden kill") else self:Rebase() end
        return nil
    end
    local ok,me=pcall(UnitGUID,"player")
    if not ok or not readable(me) then count("kill: you unknown");return nil end
    local pet=false
    if attacker~=me then
        local okPet,guid=pcall(UnitGUID,"pet")
        pet=okPet and readable(guid) and guid==attacker
        if not pet then count("kill: not you");return nil end
        count("kill: pet")
        if not c.pets then return nil end
    end
    if not readable(target) then count("kill: target secret") end
    local player=readable(target) and type(target)=="string" and target:match("^Player%-")~=nil
    count(player and "kill: player" or "kill: npc")
    if player then
        -- Shown now; the statistic rising for it later is not shown again.
        if not pet then self.credit=(self.credit or 0)+1;self.creditAt=GetTime() end
    else self:Rebase() end
    return self:ShowKill(player)
end
-- The statistic "Total Killing Blows" as a number, or nil (no such API, a
-- secret, or "--" before the first).
function N:KillStat()
    local why="no API"
    if type(GetStatistic)=="function" then
        local ok,value=pcall(GetStatistic,self.STAT_KILLS)
        if not ok then why="refused"
        elseif not readable(value) then why="secret"
        else
            local n=tonumber(value) or (value=="--" and 0) or nil
            if n then return n,"read" end
        end
    end
    -- The achievement criterion of the same statistic (MiniKillingBlow on
    -- Forever): its count, the 9th value as text or the 4th as a number.
    if type(GetAchievementCriteriaInfoByID)=="function" then
        local ok,_,_,_,quantity,_,_,_,_,text=pcall(GetAchievementCriteriaInfoByID,self.STAT_KILLS,0)
        if ok then
            local n=readable(text) and tonumber(text) or (readable(quantity) and tonumber(quantity)) or nil
            if n then return n,"read (criterion)" end
        end
    end
    return nil,why
end
function N:ReadKillStat()
    local value,why=self:KillStat()
    if value then self.killStat=value end
    return value,why
end
-- The statistic may count creatures too (Florian's client 2026-10-16: 442 at
-- level 14): after a creature's kill it is read again as the new start, now
-- and a moment later (it may follow the kill), so only a player's raises it.
function N:Rebase()
    if self.KillStat and not select(1,self:KillStat()) then return end
    self:ReadKillStat()
    if C_Timer and C_Timer.NewTimer then
        for _,delay in ipairs(self.RECHECK) do C_Timer.NewTimer(delay,function() if not self.inPvPCheck then self:ReadKillStat() end end) end
    end
end
-- Your PvP kills changed: a player killed with your part in it. A killing
-- blow only when the statistic rose (and not already shown by PARTY_KILL).
function N:KillsChanged(unit,source)
    local count=L.Sources.Count
    -- Only yours (the event names a unit; Forever's documentation 2026-10-16).
    if unit~=nil and readable(unit) and unit~="player" then count("kill: pvp kills changed (not you)");return end
    source=source or "pvp kills changed"
    count("kill: "..source);count("kill: "..source.." ("..where()..")")
    local hidden=source=="hidden kill"
    -- Honor or a PvP kill: a player died with your part in it. A rise seen
    -- just before (after a hidden kill) is shown now.
    if not hidden then
        self.evidenceAt=GetTime()
        if (self.pending or 0)>0 and GetTime()-(self.pendingAt or 0)<=self.EVIDENCE then
            self.pending=0
            count("kill: player (statistic, honor after)")
            if L:Config().categories.kill.enabled then self:ShowKill(true) end
        end
    end
    self.inPvPCheck=true
    local function check()
        local before=self.killStat
        local value,why=self:KillStat()
        if not value then count("kill: statistic "..why);return true end
        self.killStat=value
        if not before or value<=before then return false end
        if (self.credit or 0)>0 and GetTime()-(self.creditAt or 0)>self.CREDIT_TIME then self.credit=0 end
        local rose=value-before
        local shown=math.min(rose,self.credit or 0)
        self.credit=(self.credit or 0)-shown
        if rose>shown then
            if hidden and GetTime()-(self.evidenceAt or -1e9)>self.EVIDENCE then
                -- No honor yet: maybe a creature, pet or totem. Kept a moment for honor.
                self.pending=(self.pending or 0)+(rose-shown);self.pendingAt=GetTime()
                count("kill: statistic rose, waiting for honor")
            else
                count("kill: player (statistic)")
                local c=L:Config().categories.kill
                if c.enabled then self:ShowKill(true) end
            end
        else count("kill: statistic matched") end
        return true
    end
    if check() then self.inPvPCheck=false;return end
    -- The statistic may follow the event a moment later.
    if C_Timer and C_Timer.NewTimer then
        for _,delay in ipairs(self.RECHECK) do
            C_Timer.NewTimer(delay,function()
                if not self.recheckDone then self.recheckDone=check() end
                if delay==self.RECHECK[#self.RECHECK] then self.inPvPCheck=false end
            end)
        end
        self.recheckDone=false
    end
end
-- Combat start and end (Blizzard: ENTERING_COMBAT / LEAVING_COMBAT texts).
function N:Combat(entering)
    if not L:Config().categories.notice.combat then return nil end
    local text=entering and (type(ENTERING_COMBAT)=="string" and ENTERING_COMBAT or "+Combat")
        or (type(LEAVING_COMBAT)=="string" and LEAVING_COMBAT or "-Combat")
    return self:Show("notice",text,entering and "combat start" or "combat end")
end
-- The client sends COMBAT_TEXT_UPDATE for its "active unit" only. Blizzard's
-- combat text sets it (C_CombatText.SetActiveUnit) when it loads, and it
-- loads only while enableFloatingCombatText is on, which "Hide Blizzard text
-- at you" turns off: then no message ever came (Florian 2026-10-05; Blizzard
-- code: CombatTextMixin:UpdateDisplayedMessages). So set it here: you, or
-- your vehicle while you are in one (as Blizzard does). Allowed for addons.
function N:SetActiveUnit()
    local f=C_CombatText and C_CombatText.SetActiveUnit or CombatTextSetActiveUnit
    if type(f)~="function" then L.Sources.Count("notice: no active unit API");return end
    local vehicle=UnitHasVehicleUI and select(2,pcall(UnitHasVehicleUI,"player"))==true
    local ok=pcall(f,vehicle and "vehicle" or "player")
    L.Sources.Count(ok and "notice: active unit set" or "notice: active unit refused")
end
function N:Enable(context)
    -- An unknown event on this client must not fault the module.
    pcall(context.Subscribe,context,"COMBAT_TEXT_UPDATE",function(_,messageType)
        local ok,err=pcall(N.Update,N,messageType)
        if not ok then L.Sources.Count("error");L.Sources.lastError=tostring(err) end
    end)
    self:SetActiveUnit()
    for _,event in ipairs({"UNIT_ENTERED_VEHICLE","UNIT_EXITED_VEHICLE"}) do
        pcall(context.Subscribe,context,event,function(_,unit) if unit=="player" then N:SetActiveUnit() end end)
    end
    pcall(context.Subscribe,context,"PARTY_KILL",function(_,attacker,target) pcall(N.Kill,N,attacker,target) end)
    pcall(N.ReadKillStat,N)
    pcall(context.Subscribe,context,"PLAYER_PVP_KILLS_CHANGED",function(_,unit) pcall(N.KillsChanged,N,unit) end)
    pcall(context.Subscribe,context,"PLAYER_ENTERING_WORLD",function() pcall(N.ReadKillStat,N) end)
    -- Only counted (/bv sct kills): whether deaths and honor come where the kills do not.
    pcall(context.Subscribe,context,"UNIT_DIED",function() L.Sources.Count("kill: unit died ("..where()..")") end)
    -- Honor (Florian 2026-10-16): every one taking part gets it, but the
    -- statistic rises only for the killing blow; together a player's killing blow.
    pcall(context.Subscribe,context,"CHAT_MSG_COMBAT_HONOR_GAIN",function() pcall(N.KillsChanged,N,nil,"honor") end)
    -- A fight starting also reads the statistic as it stands (earlier creatures do not count).
    context:Subscribe("PLAYER_REGEN_DISABLED",function() pcall(N.Combat,N,true);if not N.inPvPCheck then pcall(N.ReadKillStat,N) end end)
    context:Subscribe("PLAYER_REGEN_ENABLED",function() pcall(N.Combat,N,false) end)
end
