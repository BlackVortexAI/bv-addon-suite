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
-- (signal probe 2026-10-07: 3 of 3). Your pet's kills do not count.
function N:Kill(attacker)
    if not L:Config().categories.notice.kills then return nil end
    if not readable(attacker) then L.Sources.Count("kill: attacker secret");return nil end
    local ok,me=pcall(UnitGUID,"player")
    if not ok or not readable(me) or attacker~=me then return nil end
    local text=type(KILLING_BLOW)=="string" and KILLING_BLOW or "Killing Blow"
    return self:Show("notice",join(text,"!"),"killing blow")
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
    pcall(context.Subscribe,context,"PARTY_KILL",function(_,attacker) pcall(N.Kill,N,attacker) end)
    context:Subscribe("PLAYER_REGEN_DISABLED",function() pcall(N.Combat,N,true) end)
    context:Subscribe("PLAYER_REGEN_ENABLED",function() pcall(N.Combat,N,false) end)
end
