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
-- Only counts and Blizzard's own event kinds, no names or amounts. Since
-- 0.7.1 also in BVCombatTextDB.stats, counted from login (or /reload), so a
-- fight can be checked after logging out.
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

function S:Kind(unit)
    if type(unit)~="string" then return nil end
    if unit=="player" then return "player" end
    if unit:match("^nameplate%d+$") then return "plate" end
    if unit=="target" then
        -- You as your target: the player event covers it.
        if call(UnitIsUnit,"target","player")==true then return nil end
        -- Covered by its nameplate event when the target has one shown.
        if C_NamePlate and C_NamePlate.GetNamePlateForUnit and call(C_NamePlate.GetNamePlateForUnit,"target") then return nil end
        return "plate"
    end
    return nil
end
-- One UNIT_COMBAT event to a display entry (nil when nothing is shown).
-- enemy: overrides the hostility check (simulation). credit (Log.lua): nil
-- when the Combat Log is not usable, "line"/"tick" for a line of yours,
-- false for none. Who did a hit on an enemy is decided in Origin.lua; here
-- only its answer is applied.
function S:Entry(unit,action,flagText,amount,school,enemy,credit)
    local kind=self:Kind(unit)
    if not kind then count("skip: unit not used");return nil end
    if not readable(action) then count("skip: action secret");return nil end
    -- Units other than you: enemies (damage, avoidance) or friends (heals).
    local friendly=kind=="plate" and not enemy and call(UnitCanAttack,"player",unit)~=true
    if friendly and action~="HEAL" then count("skip: not hostile");return nil end
    if kind=="plate" and not friendly and action=="HEAL" then count("skip: enemy heal");return nil end
    local origin,show,petSpell="mine","full",nil
    if kind=="plate" and not enemy then
        local evidence,relation
        if friendly then origin,evidence,relation=L.Origin:OfHeal(unit,credit)
        else origin,evidence,relation,petSpell=L.Origin:Of(unit,credit,F.School(school)) end
        count("origin "..origin.." ("..evidence..(credit=="tick" and ", tick" or "")..")")
        show=L.Origin:Show(origin,relation)
        if not show then count("skip: "..origin..", "..relation);return nil end
    end
    local crit=readable(flagText) and flagText=="CRITICAL"
    local entry={unit=unit,crit=crit,incoming=kind=="player",origin=origin,foreign=show=="dim"}
    local cfg=L:Config()
    if not readable(amount) then count("amount secret") end
    if action=="WOUND" then
        if readable(amount) and (type(amount)~="number" or amount<=0) then count("skip: no amount");return nil end
        entry.category=kind=="player" and "incoming" or "outgoing"
        entry.number=F.Number(amount,cfg.numbers)
        local r,g,b=F.SchoolColor(school)
        entry.r,entry.g,entry.b=r,g,b
        entry.school=F.School(school)
        if cfg.spellGuess and kind=="plate" and origin=="mine" then entry.spell=L.Attribution:Spell(unit,false,entry.school,credit=="tick" and "tick" or nil) end
        -- Your pet's spell is evidence, not a guess: its icon and {spell} always.
        if origin=="pet" then entry.spell=petSpell end
    elseif action=="HEAL" then
        if readable(amount) and (type(amount)~="number" or amount<=0) then count("skip: no amount");return nil end
        -- On you: incoming heal; on others: outgoing heal at their nameplate.
        entry.category=kind=="player" and "heal" or "outheal"
        entry.number=F.Number(amount,cfg.numbers)
        if cfg.spellGuess and cfg.iconHeals and origin=="mine" then entry.spell=L.Attribution:Spell(kind=="player" and "player" or unit,true) end
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
    -- One hit, two tokens: as a nameplate disappears (an enemy fleeing out of
    -- range), "target" can repeat a nameplate's event in the same frame
    -- (Florian's trace 2026-10-05). Same frame, action, amount and school:
    -- the same hit. Secret values cannot be compared and are kept.
    local action,_,amount,school=...
    if readable(action) and readable(amount) and readable(school) then
        local now=GetTime()
        if type(unit)=="string" and unit:match("^nameplate%d+$") then
            self.lastPlate={time=now,action=action,amount=amount,school=school}
        elseif unit=="target" then
            local p=self.lastPlate
            if p and p.time==now and p.action==action and p.amount==amount and p.school==school then
                count("skip: target repeats nameplate");return nil
            end
        end
    end
    -- Hits on enemies wait for the end of their frame while Combat Log lines
    -- arrive (a tick's line comes right behind it).
    if L.Log:Holds(unit,...) then
        local action,flagText,amount,school=...
        local label=string.format("%s %s s%s%s",unit,readable(amount) and tostring(amount) or "?",readable(school) and tostring(school) or "?",
            readable(flagText) and flagText~="" and " "..flagText or "")
        L.Log:Queue(function(credit) S:Process(unit,action,flagText,amount,school,nil,credit) end,label,unit,school)
        return nil
    end
    return self:Process(unit,...)
end
function S:Process(unit,...)
    local ok,entry=pcall(self.Entry,self,unit,...)
    if not ok then count("error");self.lastError=tostring(entry);return nil end
    if not entry then return nil end
    local shown,item=pcall(L.Display.Show,L.Display,entry)
    if not shown then count("error");self.lastError=tostring(item);return nil end
    count(item and ((item.queued and "staggered " or "shown ")..entry.category..(item.plate and " (nameplate)" or "")..(entry.foreign and " dimmed" or "")) or "skip: category off")
    return entry
end
function S:Report()
    local keys={}
    for key in pairs(self.stats) do keys[#keys+1]=key end
    table.sort(keys)
    local record=L.ns.Modules.records[L.ID]
    L:Print("module "..record.state..", content "..L.ContentType()..", whose numbers "..L:Config().whose[L.ContentType()]
        ..", Blizzard at you "..(L:Config().hideBlizzardSelf and "hidden" or "shown")..", at enemies "..(L:Config().hideBlizzard and "hidden" or "shown")
        ..", texts on screen "..#L.Display.active..", nameplate CVar nameplateShowEnemies="..tostring(C_CVar and C_CVar.GetCVar and select(2,pcall(C_CVar.GetCVar,"nameplateShowEnemies"))))
    L.Log:Report()
    if #keys==0 then L:Print("No UNIT_COMBAT event received yet.") end
    for _,key in ipairs(keys) do L:Print(key..": "..self.stats[key]) end
    if self.lastError then L:Print("last error: "..self.lastError) end
end
function S:Enable(context)
    if not self.saved then
        self.saved=true
        local db=L:DB()
        db.stats=self.stats
        db.statsSince=type(time)=="function" and time() or nil
    end
    context:Subscribe("UNIT_COMBAT",function(_,...) S:Handle(...) end)
end
