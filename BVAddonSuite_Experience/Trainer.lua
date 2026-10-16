local _,E=...
if not E.ready then return end
-- Your class trainer has something for you (Florian 2026-10-16): the
-- abilities up to your level you may learn and do not know yet. A badge at
-- the experience bar (tooltip: the list; click: BV Codex leads you to the
-- nearest class trainer; right-click: hidden until your next level) and,
-- with BV Quest, a line at the top of its tracker with the same arrow.
-- Counted again when your spells change; gone once you learned them.
local ns=BVAddonSuiteCore
local L=E.LevelUp
local T={list={}}
E.Trainer=T
if ns.ExperienceLevelUp then ns.ExperienceLevelUp.Trainer=T end
T.SHOWN=12   -- names in the tooltip at most

local function call(fn,...) if type(fn)~="function" then return nil end;local ok,a,b=pcall(fn,...);if ok then return a,b end end
local function cfg() return ns.Settings:Module("experience_bar") end
local function who()
    local name,realm=call(UnitName,"player"),call(GetRealmName)
    return tostring(name or "?").."-"..tostring(realm or "?")
end
function T:Who() return who() end
-- All you may learn now: every level up to yours.
function T:Count()
    local _,class=call(UnitClass,"player")
    local level=call(UnitLevel,"player") or 1
    local out={}
    if class and E.LevelSpells then
        for lv=2,level do
            for _,a in ipairs(L:Abilities(class,lv,true)) do out[#out+1]=a end
        end
    end
    self.list=out
    return out
end
-- Hidden until the next level (right-click on the badge).
function T:Hidden()
    local d=cfg().trainerHidden
    return type(d)=="table" and d[who()]==(call(UnitLevel,"player") or 0)
end
function T:Hide()
    local c=cfg()
    c.trainerHidden=type(c.trainerHidden)=="table" and c.trainerHidden or {}
    c.trainerHidden[who()]=call(UnitLevel,"player") or 0
    self:Changed()
end
function T:Shown()
    local on=not (ns.ProgressOptions and ns.ProgressOptions:Get("experience").trainerReminder==false)
    return on and self.enabled==true and #self.list>0 and not self:Hidden()
end

-- BV Codex knows the trainers (BV Map Data) and leads there with BV Routing.
function T:CanLead() local C=ns.Codex;return C~=nil and type(C.Search)=="function" and C.Tour~=nil end
function T:Lead()
    local C=ns.Codex
    if not self:CanLead() then return false end
    -- Codex's "My Class Trainer" (your class's trainers), else the title.
    local class=call(UnitClass,"player")
    for _,wanted in ipairs({"my class trainer",(tostring(class or "").." trainer"):lower()}) do
        for _,f in ipairs(C:Search(wanted,8) or {}) do
            if f.entry and f.entry.name and f.entry.name:lower()==wanted then return C.Tour:GoNow(f.entry) end
        end
    end
    return false
end
function T:Text()
    local n=#self.list
    return n==1 and "1 new ability" or (n.." new abilities")
end
function T:Tip()
    local lines={}
    for i,a in ipairs(self.list) do
        if i>T.SHOWN then lines[#lines+1]="+"..(#self.list-T.SHOWN).." more";break end
        lines[#lines+1]=a.name..(a.rank and (" (Rank "..a.rank..")") or "")
    end
    return table.concat(lines,"\n")
end

-- Counted again, the badge and the tracker line follow.
function T:Changed()
    if self.enabled then self:Count() else self.list={} end
    if E.TrainerBadge then E.TrainerBadge:Update() end
    local Q=ns.Quest
    if Q and Q.Dirty then Q:Dirty() end
end
function T:Enable(context)
    self.enabled=true
    for _,event in ipairs({"SPELLS_CHANGED","LEARNED_SPELL_IN_TAB","PLAYER_LEVEL_UP"}) do
        pcall(context.Subscribe,context,event,function() T:Soon() end)
    end
    pcall(context.Subscribe,context,"QUEST_ACCEPTED",function(_,a,b)
        -- Classic passes (logIndex, questID), later clients (questID).
        if E.ClassQuest then E.ClassQuest:Accepted(type(b)=="number" and b or a) end
    end)
    context:Defer(function() T.enabled=nil;T:Changed() end)
    self:Changed()
end
-- Spells change in bursts (a trainer visit): one count shortly after.
function T:Soon()
    if self.timer then return end
    self.timer=C_Timer.NewTimer(.5,function() T.timer=nil;T:Changed() end)
end

-- BV Quest's tracker: "Class trainer - 4 new abilities" with the arrow.
local Q=ns.Quest
if Q and Q.AddTrackerExtra then
    Q:AddTrackerExtra("experience_trainer",{items=function()
        if not T:Shown() then return {} end
        return {{title="Class trainer",text=T:Text(),go=T:CanLead() and function() T:Lead() end or nil,
            tip="BV Routing leads you to the nearest class trainer.\n"..T:Tip()}}
    end})
end
