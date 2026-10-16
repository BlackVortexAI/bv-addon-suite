local _,E=...
if not E.ready then return end
-- Class quests that open with a level (Florian 2026-10-16: our own list, not
-- from Questie; the big ones only, list approved by Florian): kind, the text
-- of the card, the spell it leads to (its icon; the game's name), faction
-- when only one side has it.
-- start: the titles its chain begins with (per race and side several; BV
-- Codex finds their givers in BV Map Data, those of your side).
E.ClassQuests={
    WARLOCK={[10]={kind="pet",text="Voidwalker quest",spell=697,start={"Creature of the Void","Gakin's Summons","Gan'rul's Summons","Halgar's Summons","Surena Caledon","The Slaughtered Lamb"}},
        [20]={kind="pet",text="Succubus quest",spell=712,start={"Devourer of Souls","Gakin's Summons"}},
        [30]={kind="pet",text="Felhunter quest",spell=691,start={"Seeking Strahad","Tome of the Cabal"}},
        [40]={kind="mount",text="Mount quest: Felsteed",spell=5784,start={"Summon Felsteed"}},
        [50]={kind="pet",text="Infernal quest",spell=1122,start={"What Niby Commands","An Imp's Request"}},
        [60]={kind="mount",text="Epic mount quest: Dreadsteed",spell=23161,start={"Mor'zul Bloodbringer"}}},
    PALADIN={[12]={kind="ability",text="Redemption quest",spell=7328,start={"The Tome of Divinity","Tome of Divinity"}},
        [20]={kind="weapon",text="Verigan's Fist quest",faction="Alliance",start={"The Tome of Valor"}},
        [40]={kind="mount",text="Mount quest: Warhorse",spell=13819,start={"The Tome of Nobility"}},
        [60]={kind="mount",text="Epic mount quest: Charger",spell=23214,start={"Lord Grayson Shadowbreaker"}}},
    SHAMAN={[4]={kind="totem",text="Earth totem quest",spell=8071,start={"Call of Earth"}},[10]={kind="totem",text="Fire totem quest",spell=3599,start={"Call of Fire"}},
        [20]={kind="totem",text="Water totem quest",spell=5394,start={"Call of Water"}},[30]={kind="totem",text="Air totem quest",spell=8177,start={"Call of Air"}}},
    WARRIOR={[10]={kind="stance",text="Defensive Stance quest",spell=71,start={"A Warrior's Training","Speak with Dillinger","Veteran Uzzek","Vorlus Vilehoof","Ulag the Cleaver","Elanaria","Muren Stormpike","Bartleby the Drunk"}},
        [30]={kind="stance",text="Berserker Stance quest",spell=2458,start={"The Islander","Speak with Ruga","Yorus Barleybrew"}}},
    DRUID={[10]={kind="form",text="Bear Form quest",spell=5487,start={"Heeding the Call"}},[14]={kind="ability",text="Cure Poison quest",spell=8946,start={"Lessons Anew"}},
        [16]={kind="form",text="Aquatic Form quest",spell=1066,start={"A Lesson to Learn"}}},
    HUNTER={[10]={kind="pet",text="Pet taming quest",spell=1515,start={"Taming the Beast"}}},
    ROGUE={[20]={kind="ability",text="Poisons quest",spell=2842,start={"Mathias and the Defias","The Shattered Salute"}}},
}
-- Without a spell icon: a symbol of its kind.
E.ClassQuestSymbol={pet="paw-print",mount="crown",totem="flame",stance="shield",form="leaf",weapon="swords",ability="sparkles"}
-- The quests of a class at a level (your faction; any for a made-up one).
function E.LevelUp:Quests(class,level,yours)
    local q=E.ClassQuests[class] and E.ClassQuests[class][level]
    if not q then return {} end
    if yours and q.faction and UnitFactionGroup then
        local ok,faction=pcall(UnitFactionGroup,"player")
        if ok and faction~=q.faction then return {} end
    end
    local icon=q.spell and select(2,E.LevelUp.Spell(q.spell)) or nil
    return {{kind=q.kind,text=q.text,icon=icon,symbol=E.ClassQuestSymbol[q.kind],start=q.start,level=level}}
end

-- The class quest waiting for you (Florian 2026-10-16): after a real level
-- up that opens one, a line in BV Quest's tracker with the arrow to its
-- giver, unless only your class trainers give it (the trainer line leads
-- there). Gone when you take it (one of its starting titles) or by its menu.
local ns=BVAddonSuiteCore
local W={}
E.ClassQuest=W
if ns.ExperienceLevelUp then ns.ExperienceLevelUp.ClassQuest=W end
local function cfg() return ns.Settings:Module("experience_bar") end
function W:Pending()
    local all=cfg().classQuest
    return type(all)=="table" and all[E.Trainer:Who()] or nil
end
function W:Set(q)
    local c=cfg()
    c.classQuest=type(c.classQuest)=="table" and c.classQuest or {}
    c.classQuest[E.Trainer:Who()]=q and {text=q.text,start=q.start,level=q.level} or nil
    local Q=ns.Quest
    if Q and Q.Dirty then Q:Dirty() end
end
-- Codex's quest entries of the titles (your side) and its class trainers.
function W:Entries(titles)
    local C=ns.Codex
    local out={}
    local list=C and type(C.Entries)=="function" and C:Entries() or nil
    if not (list and titles) then return out end
    local wanted={}
    for _,t in ipairs(titles) do wanted[t]=true end
    for _,e in ipairs(list) do if e.kind=="quest" and wanted[e.name] then out[#out+1]=e end end
    return out
end
function W:TrainerNames()
    local C=ns.Codex
    local names={}
    for _,e in ipairs(C and type(C.Entries)=="function" and C:Entries() or {}) do
        if e.key=="mine:classtrainer" or e.name=="My Class Trainer" then for _,p in ipairs(e.places or {}) do names[p.name]=true end end
    end
    return names
end
-- A line of its own: someone else than your class trainers gives it.
function W:OwnLine(entries)
    local trainers=self:TrainerNames()
    for _,e in ipairs(entries) do
        for _,p in ipairs(e.places or {}) do if not trainers[p.name] then return true end end
    end
    return false
end
function W:Lead()
    local p=self:Pending()
    local C=ns.Codex
    if not (p and C and C.Tour) then return false end
    local cont,x,y=C:Here()
    local best,bestD
    for _,e in ipairs(self:Entries(p.start)) do
        local _,d=C.Nearest(e,cont,x,y)
        if not bestD or (d and d<bestD) then best,bestD=e,d or 1e9 end
    end
    return best~=nil and C.Tour:GoNow(best)
end
-- QUEST_ACCEPTED: one of its starting titles taken, it is done here.
function W:Accepted(questID)
    local p=self:Pending()
    if not p then return end
    local title
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then local ok,t=pcall(C_QuestLog.GetTitleForQuestID,questID);if ok then title=t end end
    for _,t in ipairs(p.start or {}) do if t==title then self:Set(nil);return end end
end
local Q=ns.Quest
if Q and Q.AddTrackerExtra then
    Q:AddTrackerExtra("experience_classquest",{items=function()
        local p=W:Pending()
        if not p then return {} end
        local entries=W:Entries(p.start)
        if #entries==0 or not W:OwnLine(entries) then return {} end
        local from={}
        for i,e in ipairs(entries) do if i<=3 and e.from then from[#from+1]=e.from end end
        return {{title="Class quest",text=p.text,go=function() W:Lead() end,dismiss=function() W:Set(nil) end,
            tip="BV Routing leads you to who gives it"..(#from>0 and (": "..table.concat(from,", ")) or "")..".\nRight-click: forget it."}}
    end})
end
