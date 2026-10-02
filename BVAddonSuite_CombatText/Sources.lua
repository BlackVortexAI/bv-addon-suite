local _,L=...
if not L.ready then return end
-- Data source: UNIT_COMBAT (probe 2026-10-01: all arguments readable in the
-- open world; amount may turn secret elsewhere, so it is only formatted, never
-- compared when secret). The event names the unit that was hit, not who hit
-- it: damage on an enemy includes the damage of group members.
-- Units: player (incoming), nameplateN (enemies), target only when it has no
-- nameplate (otherwise the nameplate event already covers it). party, pets,
-- targettarget and softenemy repeat units already covered and are skipped.
local F=L.Format
local S={}
L.Sources=S
-- Diagnosis (/bv sct debug): what arrived and why something was not shown.
-- Only counts and Blizzard's own event kinds, no names or amounts.
S.stats={}
local function count(key) S.stats[key]=(S.stats[key] or 0)+1 end
S.Count=count

local AVOID={MISS="Miss",DODGE="Dodge",PARRY="Parry",BLOCK="Block",RESIST="Resist",IMMUNE="Immune",ABSORB="Absorb",EVADE="Evade",DEFLECT="Deflect",REFLECT="Reflect"}
S.AVOID=AVOID
local function readable(v) return v~=nil and not L.Secret(v) end
-- Values for {school} {spell} {name}; names and spells may be secret strings.
local function spellName(id)
    if not id then return nil end
    local f=C_Spell and C_Spell.GetSpellName
    if f then local ok,name=pcall(f,id);if ok and name~=nil then return name end end
    if GetSpellInfo then local ok,name=pcall(GetSpellInfo,id);if ok and name~=nil then return name end end
end
function S:Values(entry)
    local values={school=F.SchoolName(entry.school),spell=spellName(entry.spell)}
    if entry.unit and entry.unit~="player" and UnitName then
        local ok,name=pcall(UnitName,entry.unit)
        if ok and name~=nil then values.name=name end
    end
    return values
end
local function call(f,...) if type(f)~="function" then return nil end;local ok,v=pcall(f,...);if ok and readable(v) then return v end end

-- Whose numbers (per content type). UNIT_COMBAT names no attacker, so "own"
-- can only mean "on enemies fighting you": you are on their threat list, they
-- target you, or they are your target. Group: the same for any group member.
-- Unreadable answers count as fighting (shown rather than lost).
local function check(f,...)
    if type(f)~="function" then return nil end
    local ok,v=pcall(f,...)
    if not ok or L.Secret(v) then return "unknown" end
    return v
end
function S:Involved(unit,who)
    -- Cast on within the last 10 seconds counts as fighting you.
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
function S:GroupUnits()
    local list={}
    local raid=check(IsInRaid)==true
    local n=check(raid and GetNumGroupMembers or GetNumSubgroupMembers)
    if type(n)~="number" then return list end
    for i=1,math.min(n,40) do list[#list+1]=(raid and "raid" or "party")..i end
    return list
end
-- "mine": fights you; "group": fights you or the group (fighting the group but
-- not you is foreign); "all": everything, foreign when not fighting you.
function S:Scope(unit)
    local scope=L:Config().scope[L.ContentType()]
    local mine=self:Involved(unit,"player")
    if mine~=false then
        if mine==nil then count("involvement unknown") end
        return true,false
    end
    if scope=="mine" then count("skip: not fighting you");return false end
    if scope=="group" then
        local any=false
        for _,member in ipairs(self:GroupUnits()) do
            if self:Involved(unit,member)~=false then any=true;break end
        end
        if not any then count("skip: not fighting your group");return false end
    end
    return true,true
end

function S:Kind(unit)
    if type(unit)~="string" then return nil end
    if unit=="player" then return "player" end
    if unit:match("^nameplate%d+$") then return "plate" end
    if unit=="target" then
        -- Covered by its nameplate event when the target has one shown.
        if C_NamePlate and C_NamePlate.GetNamePlateForUnit and call(C_NamePlate.GetNamePlateForUnit,"target") then return nil end
        return "plate"
    end
    return nil
end
-- One UNIT_COMBAT event to a display entry (nil when nothing is shown).
-- enemy: overrides the hostility check (simulation).
function S:Entry(unit,action,flagText,amount,school,enemy)
    local kind=self:Kind(unit)
    if not kind then count("skip: unit not used");return nil end
    if not readable(action) then count("skip: action secret");return nil end
    if kind=="plate" and not enemy and call(UnitCanAttack,"player",unit)~=true then count("skip: not hostile");return nil end
    local foreign=false
    if kind=="plate" and not enemy then
        local show
        show,foreign=self:Scope(unit)
        if not show then return nil end
    end
    local crit=readable(flagText) and flagText=="CRITICAL"
    local entry={unit=unit,crit=crit,incoming=kind=="player",foreign=foreign}
    local cfg=L:Config()
    if not readable(amount) then count("amount secret") end
    if action=="WOUND" then
        if readable(amount) and (type(amount)~="number" or amount<=0) then count("skip: no amount");return nil end
        entry.category=kind=="player" and "incoming" or "outgoing"
        entry.number=F.Number(amount,cfg.numbers)
        local r,g,b=F.SchoolColor(school)
        entry.r,entry.g,entry.b=r,g,b
        entry.school=F.School(school)
        if cfg.spellGuess and kind=="plate" and not entry.foreign then entry.spell=L.Attribution:Spell(unit,false,entry.school) end
    elseif action=="HEAL" then
        if kind~="player" then count("skip: enemy heal");return nil end
        if readable(amount) and (type(amount)~="number" or amount<=0) then count("skip: no amount");return nil end
        entry.category="heal"
        entry.number=F.Number(amount,cfg.numbers)
        if cfg.spellGuess and cfg.iconHeals then entry.spell=L.Attribution:Spell("player",true) end
    elseif AVOID[action] then
        entry.category="miss"
        entry.word=AVOID[action]
    else count("skip: action "..action);return nil end
    entry.text=F.Text(cfg.categories[entry.category],entry.number or entry.word,self:Values(entry),entry.crit)
    if entry.school and cfg.categories[entry.category].label then entry.text=F.Label(entry.text,entry.school) end
    if readable(flagText) and flagText=="BLOCK_REDUCED" and entry.category=="incoming" then
        local ok,text=pcall(function() return entry.text.." (Block)" end)
        if ok then entry.text=text end
    end
    return entry
end
-- One faulty event is counted and dropped; it must not stop the module.
function S:Handle(unit,...)
    count("events")
    if type(unit)=="string" and not L.Secret(unit) then count("unit "..(unit:match("^(nameplate)%d+$") or unit)) end
    local ok,entry=pcall(self.Entry,self,unit,...)
    if not ok then count("error");self.lastError=tostring(entry);return nil end
    if not entry then return nil end
    local shown,item=pcall(L.Display.Show,L.Display,entry)
    if not shown then count("error");self.lastError=tostring(item);return nil end
    count(item and ("shown "..entry.category..(item.plate and " (nameplate)" or "")..(entry.foreign and " foreign" or "")) or "skip: category off")
    return entry
end
function S:Report()
    local keys={}
    for key in pairs(self.stats) do keys[#keys+1]=key end
    table.sort(keys)
    local record=L.ns.Modules.records[L.ID]
    L:Print("module "..record.state..", content "..L.ContentType()..", scope "..L:Config().scope[L.ContentType()]
        ..", Blizzard at you "..(L:Config().hideBlizzardSelf and "hidden" or "shown")..", at enemies "..(L:Config().hideBlizzard and "hidden" or "shown")
        ..", texts on screen "..#L.Display.active..", nameplate CVar nameplateShowEnemies="..tostring(C_CVar and C_CVar.GetCVar and select(2,pcall(C_CVar.GetCVar,"nameplateShowEnemies"))))
    if #keys==0 then L:Print("No UNIT_COMBAT event received yet.") end
    for _,key in ipairs(keys) do L:Print(key..": "..self.stats[key]) end
    if self.lastError then L:Print("last error: "..self.lastError) end
end
function S:Enable(context)
    context:Subscribe("UNIT_COMBAT",function(_,...) S:Handle(...) end)
end
