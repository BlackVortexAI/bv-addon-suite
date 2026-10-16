local _,E=...
if not E.ready then return end
-- The level-up card (Florian 2026-10-16): the new level, the values that
-- grew (old, then "-> new +gain" opening left to right), the abilities your
-- trainer now teaches popping in one by one, a new talent point. In combat
-- only the short notification; the card when the fight is over. Shown while
-- the "Level up" notification is on; its time there is how long it stays.
-- /bv levelup <class> <level> shows it for any class and level (screenshots).
local ns=BVAddonSuiteCore
local L={}
E.LevelUp=L
if ns.ExperienceLevelUp then ns.ExperienceLevelUp.LevelUp=L end
L.STATS={{"Strength",1},{"Agility",2},{"Stamina",3},{"Intellect",4},{"Spirit",5}}
L.MAXICONS=8
L.CLASSES={warrior="WARRIOR",paladin="PALADIN",hunter="HUNTER",rogue="ROGUE",priest="PRIEST",shaman="SHAMAN",mage="MAGE",warlock="WARLOCK",druid="DRUID"}
-- Races by the bits of the client's race masks (ChrRaces ids 1..8).
L.RACEBIT={Human=1,Orc=2,Dwarf=3,NightElf=4,Scourge=5,Tauren=6,Gnome=7,Troll=8}

local function call(fn,...) if type(fn)~="function" then return nil end;local ok,a,b,c,d=pcall(fn,...);if ok then return a,b,c,d end end
local function number(v) return type(v)=="number" and v==v end
-- A spell's name, icon and rank number in the player's language.
function L.Spell(id)
    local name,icon,sub
    if C_Spell and C_Spell.GetSpellInfo then
        local info=call(C_Spell.GetSpellInfo,id)
        if type(info)=="table" then name,icon=info.name,info.iconID end
        sub=C_Spell.GetSpellSubtext and call(C_Spell.GetSpellSubtext,id) or nil
    end
    if not name and GetSpellInfo then
        local n,r,i=call(GetSpellInfo,id)
        name,icon,sub=n,i,sub or r
    end
    if not name then return nil end
    return name,icon,type(sub)=="string" and tonumber(sub:match("(%d+)")) or nil
end
local function known(id)
    return (IsSpellKnown and call(IsSpellKnown,id)==true) or (IsPlayerSpell and call(IsPlayerSpell,id)==true) or false
end
-- Abilities the trainer teaches at a level; for yourself only those you may
-- learn (race, the rank before known) and do not know yet.
function L:Abilities(class,level,yours)
    local data=E.LevelSpells
    local list=data and data.classes[class] and data.classes[class][level] or {}
    local race
    if yours and UnitRace then local _,file=UnitRace("player");race=L.RACEBIT[file] end
    local out={}
    for _,id in ipairs(list) do
        local ok=true
        local mask=data.race[id]
        if yours and mask and race and math.floor(mask/2^(race-1))%2==0 then ok=false end
        if yours and ok and (known(id) or (data.prev[id] and not known(data.prev[id]))) then ok=false end
        if ok then
            local name,icon,rank=L.Spell(id)
            if name then out[#out+1]={id=id,name=name,icon=icon,rank=rank} end
        end
    end
    table.sort(out,function(a,b) return a.name<b.name end)
    return out
end

-- The card's content from the level-up event: deltas of the event, today's
-- values for "new" (the old ones are new minus the gain).
function L:FromEvent(level,health,power,talents,str,agi,sta,int,spi)
    local stats={}
    local hp=call(UnitHealthMax,"player")
    if number(health) and health>0 and number(hp) then stats[#stats+1]={"Health",hp-health,hp} end
    local powerType,token=call(UnitPowerType,"player")
    local mana=call(UnitPowerMax,"player",0)
    if number(power) and power>0 and powerType==0 and number(mana) then stats[#stats+1]={token=="MANA" and "Mana" or "Mana",mana-power,mana} end
    local gains={str,agi,sta,int,spi}
    for i,def in ipairs(L.STATS) do
        local gain=gains[i]
        local _,now=call(UnitStat,"player",def[2])
        if number(gain) and gain>0 and number(now) then stats[#stats+1]={def[1],now-gain,now} end
    end
    local _,class=call(UnitClass,"player")
    return {level=level,stats=stats,abilities=class and self:Abilities(class,level,true) or {},talents=number(talents) and talents or 0,
        quests=class and self.Quests and self:Quests(class,level,true) or {}}
end
-- A made-up level-up of any class and level (for screenshots): plausible
-- values grown by typical gains, every ability of that level.
L.PRIMARY={WARRIOR={2,1,2,0,0},PALADIN={2,0,2,1,1},HUNTER={0,2,1,1,1},ROGUE={1,2,1,0,0},PRIEST={0,0,1,2,2},
    SHAMAN={1,0,1,1,2},MAGE={0,0,1,2,2},WARLOCK={0,0,2,2,1},DRUID={1,1,1,1,1}}
function L:Sample(class,level)
    local gains=L.PRIMARY[class] or {1,1,1,1,1}
    local stats={}
    local hp=math.floor(40+level*level*.55+level*14)
    stats[#stats+1]={"Health",hp-math.floor(10+level*1.3),hp}
    if class~="WARRIOR" and class~="ROGUE" then local mana=math.floor(60+level*level*.45+level*12);stats[#stats+1]={"Mana",mana-math.floor(12+level*1.1),mana} end
    for i,def in ipairs(L.STATS) do
        local base=math.floor(18+level*(.4+gains[i]*.35))
        local gain=math.max(gains[i],(level%3==0) and 1 or 0)
        if gain>0 then stats[#stats+1]={def[1],base-gain,base} end
    end
    return {level=level,stats=stats,abilities=self:Abilities(class,level,false),talents=level>=10 and 1 or 0,took="1h 12m",
        quests=self.Quests and self:Quests(class,level,false) or {}}
end

-- What the settings leave on the card (Experience's "Level up" switches).
function L:Filter(data)
    local cfg=ns.ProgressOptions and ns.ProgressOptions:Get("experience") or {}
    if cfg.levelupStats==false then data.stats={} end
    if cfg.levelupAbilities==false then data.abilities={} end
    if cfg.levelupQuests==false then data.quests={} end
    return data
end
-- A level-up: the card now, or in combat the short notification and the
-- card after the fight.
function L:Show(data,subtitle)
    data.took=data.took or subtitle
    self:Filter(data)
    self:Remember(data)
    local Stage=ns.Stage
    if Stage and not (Stage.types.levelup and Stage:TypeConfig("levelup").enabled) then return end
    local combat=UnitAffectingCombat and call(UnitAffectingCombat,"player")==true
    if combat or not E.LevelCard then
        if Stage then pcall(Stage.Show,Stage,"levelup",{title="Level "..data.level,subtitle=E.LevelCard and "Stats and new abilities after the fight" or subtitle}) end
        if E.LevelCard and combat then self:After(data) end
        return
    end
    E.LevelCard:Play(data,Stage and Stage:TypeConfig("levelup").hold or 8)
end
-- A real level-up that opens a class quest: it waits in the tracker.
function L:Remember(data)
    local q=data and data.quests and data.quests[1]
    if q and q.start and E.ClassQuest then E.ClassQuest:Set(q) end
end
-- The card once the fight is over (listening only while one waits).
function L:After(data)
    self.waiting=data
    if self.listening or not ns.Events then return end
    self.listening=true
    ns.Events:Subscribe(L,"PLAYER_REGEN_ENABLED",function()
        ns.Events:Release(L);L.listening=nil
        local waiting=L.waiting;L.waiting=nil
        if waiting and E.LevelCard then E.LevelCard:Play(waiting,ns.Stage and ns.Stage:TypeConfig("levelup").hold or 8) end
    end)
end

-- /bv levelup [class] [level] [track]: the card as it would show (yours by
-- default); track: its class quest also waits in BV Quest's tracker.
ns.Commands:RegisterAction("levelup",function(text)
    text=type(text)=="string" and text:lower() or ""
    local word,num=text:match("^(%a*)%s*(%d*)")
    local track=text:find("track",1,true)~=nil
    local _,mine=call(UnitClass,"player")
    local class=L.CLASSES[word or ""] or (word=="" and mine) or nil
    if not class then ns:Print("/bv levelup [warrior|paladin|hunter|rogue|priest|shaman|mage|warlock|druid] [level] [track]");return end
    local level=tonumber(num) or ((call(UnitLevel,"player") or 1)+1)
    level=math.max(2,math.min(60,level))
    local data=L:Filter(L:Sample(class,level))
    if track then L:Remember(data) end
    if E.LevelCard then E.LevelCard:Play(data,ns.Stage and ns.Stage.types.levelup and ns.Stage:TypeConfig("levelup").hold or 8) end
end)
