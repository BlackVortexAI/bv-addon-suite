local _,L=...
if not L.ready then return end
-- Who did a hit on an enemy: the one place that decides it. Every source of
-- evidence flows in here, one answer flows out; the display only applies the
-- player's choice to that answer (Whose).
--   origin   "mine" (you; with a Combat Log filter that also takes your pet
--            and no pet spell to tell: you or your pet), "pet" (your pet's
--            spell, see Of) or "others"
--   evidence "log" (a Combat Log line of yours, Log.lua: certain) or "fight"
--            (the enemy fights you: an estimate, UNIT_COMBAT names no attacker)
--   relation "you", "group" or "none": whom the enemy fights. Decides whether
--            the hit of others belongs to your fight or to strangers'.
local O={}
L.Origin=O

local function readable(v) return v~=nil and not L.Secret(v) end
-- Unreadable answers count as fighting (shown rather than lost).
local function check(f,...)
    if type(f)~="function" then return nil end
    local ok,v=pcall(f,...)
    if not ok or L.Secret(v) then return "unknown" end
    return v
end
-- Fights who: on their threat list, targets them, or (you) your target or
-- cast on within the last 10 seconds. nil: unknown.
function O:Involved(unit,who)
    if who=="player" and L.Attribution:Recent(unit) then return true end
    local threat=check(UnitThreatSituation,who,unit)
    if threat=="unknown" then return nil end
    if threat~=nil then return true end
    local targets=check(UnitIsUnit,unit.."target",who)
    if targets=="unknown" then return nil end
    if targets==true then return true end
    if who=="player" and check(UnitIsUnit,unit,"target")==true then return true end
    return false
end
function O:GroupUnits()
    local list={}
    local raid=check(IsInRaid)==true
    local n=check(raid and GetNumGroupMembers or GetNumSubgroupMembers)
    if type(n)~="number" then return list end
    for i=1,math.min(n,40) do list[#list+1]=(raid and "raid" or "party")..i end
    return list
end
function O:Relation(unit)
    local you=self:Involved(unit,"player")
    if you~=false then
        if you==nil then L.Sources.Count("involvement unknown") end
        return "you"
    end
    for _,member in ipairs(self:GroupUnits()) do
        if self:Involved(unit,member)~=false then return "group" end
    end
    return "none"
end
-- credit (Log.lua): nil when the Combat Log is not usable, else "line" /
-- "tick" (a line of yours) or false (none). school: the hit's main school.
-- Your pet's spell (Attribution: its cast in the last 2 s, same school) makes
-- the hit the pet's: "pet", evidence "petcast", 4th value the spell. With the
-- default filter a pet hit has no line of yours; with "Pet" in the filter it
-- has one, so a line does not rule the pet out there.
-- Your pet's melee (4th value: the melee spell, for its icon): with "Pet"
-- in the filter a swing line credited for the pet (credit "petswing"); with
-- the default filter a physical hit without a line of yours; without the
-- Combat Log a physical hit on an enemy fighting you while you do not auto
-- attack. In a group the pet's swing beat must fit too (Attribution).
-- Without the Combat Log a hit counts as yours only with evidence of your
-- own: you cast on the enemy in the last 10 s, a DoT of yours still runs on
-- it, it is your target while you channel or auto attack, or a physical hit
-- on your target right after your own swing (PLAYER_SWING, 0.7.2). Threat and unit
-- comparisons may be secret on Forever (ShouldUnitThreatStateBeSecret,
-- ShouldUnitComparisonBeSecret); such an "unknown" made NPCs' hits on a mob
-- show as yours in full (Florian 2026-10-06). Now they are others' in your
-- fight: dimmed.
function O:Yours(unit,school)
    local A=L.Attribution
    if A:Recent(unit) or A:Running(unit) then return true end
    if school==1 and A:IsTarget(unit) and A:SwingFits(true) then L.Sources.Count("evidence: your swing");return true end
    return (A.channel~=nil or A.AutoAttacking()~=nil) and A:IsTarget(unit)
end
function O:Of(unit,credit,school)
    local relation=self:Relation(unit)
    local A=L.Attribution
    local function pet() local id=A:PetSpell(school,true);return "pet","petcast",relation,id end
    local function melee(evidence) return "pet",evidence,relation,A:PetMelee() end
    local grouped=#self:GroupUnits()>0
    local physical=school==1 and A:PetExists()
    if credit~=nil then
        -- A pet line: its spell if one fits (imp Firebolt), else its swing
        -- (physical), else the pet's without a spell.
        if credit=="petswing" then
            if A:PetSpell(school) then return pet() end
            if school==1 then return melee("petswing") end
            return "pet","petswing",relation,nil
        end
        if credit then
            if L.Log.filter=="minepet" and A:PetSpell(school) then return pet() end
            return "mine","log",relation
        end
        if A:PetSpell(school) then return pet() end
        if physical and L.Log.filter=="mine" and A:PetMeleeFits(grouped) then return melee("no line") end
        return "others","log",relation
    end
    if A:PetSpell(school) then return pet() end
    if physical and relation=="you" and not A.AutoAttacking() and A:PetMeleeFits(grouped) then return melee("fight") end
    if relation=="you" and self:Yours(unit,school) then return "mine","fight",relation end
    if relation=="you" then L.Sources.Count("origin unsure: not yours without evidence") end
    return "others","fight",relation
end

-- A heal on a friendly unit other than you. Evidence: a Combat Log line of
-- yours in its frame ("My actions" has your heals), else your own cast in the
-- last 4 seconds (estimate: someone else may have healed at the same time).
-- relation: "group" for a group member or your target, else "none".
function O:OfHeal(unit,credit)
    local relation="none"
    local raid=check(UnitInRaid,unit)
    if check(UnitIsUnit,unit,"target")==true or check(UnitInParty,unit)==true or (raid~=nil and raid~=false and raid~="unknown") then relation="group" end
    if credit~=nil then return credit and "mine" or "others","log",relation end
    local A=L.Attribution
    -- A cast that cannot heal someone else (Immolate, Drain Life) is no evidence.
    local recent=A.lastTime~=nil and GetTime()-A.lastTime<=A.castWindow and A:CanHeal(A.lastSpell,false)~=false
    return recent and "mine" or "others","cast",relation
end

-- The player's choice per content type (option "Whose numbers"):
--   "mine"   only yours
--   "dimmed" yours, and others' in your or your group's fight dimmed
--   "all"    everything in full
-- Returns "full", "dim" or nil (not shown).
function O:Show(origin,relation)
    local cfg=L:Config()
    -- Your pet (option "Your pet"): as yours, dimmed or hidden, everywhere.
    if origin=="pet" then return cfg.pet=="mine" and "full" or cfg.pet=="dimmed" and "dim" or nil end
    local whose=cfg.whose[L.ContentType()]
    if whose=="all" then return "full" end
    if origin=="mine" then return "full" end
    if whose=="dimmed" and relation~="none" then return "dim" end
    return nil
end
