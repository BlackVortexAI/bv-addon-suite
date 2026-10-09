local _,Q=...
if not Q.ready then return end
-- Quest log model on the Retail API of WoW Forever (probe 2026-10-07, docs/ai
-- LEARNINGS "Quest- und Karten-API auf Forever"): C_QuestLog for entries and
-- objectives, GetDistanceSqToQuest for open objectives (none for turn-ins),
-- GetQuestsOnMap(player map) for "current zone". Read only.
local D={quests={},list={},byID={},recent={},zone=nil}
Q.Data=D
local Call,Readable=Q.Call,Q.Readable

local function objectives(questID)
    local out={}
    local list=Call("C_QuestLog.GetQuestObjectives",questID)
    if type(list)~="table" then return out end
    for _,o in ipairs(list) do
        if type(o)=="table" then
            local have,need=o.numFulfilled,o.numRequired
            out[#out+1]={text=Readable(o.text) and o.text or "",type=o.type,finished=o.finished==true,
                have=type(have)=="number" and have or nil,need=type(need)=="number" and need or nil}
        end
    end
    return out
end
-- Progress 0..1: objectives with counts weigh by count, others by done.
local function progress(quest)
    if quest.ready then return 1 end
    local done,total=0,0
    for _,o in ipairs(quest.objectives) do
        total=total+1
        if o.finished then done=done+1 elseif o.have and o.need and o.need>0 then done=done+o.have/o.need end
    end
    return total>0 and done/total or 0
end
local function distance(questID)
    local d,onContinent=Call("C_QuestLog.GetDistanceSqToQuest",questID)
    if type(d)=="number" and Readable(d) and d>=0 then return math.sqrt(d),onContinent==true end
    return nil
end
-- Quests with a point on the player's current map (current zone; probe: IsOnMap
-- follows the map shown on screen, so it is not used for this).
function D:CurrentZone()
    local mapID=Call("C_Map.GetBestMapForUnit","player")
    local onMap={}
    if type(mapID)=="number" and Readable(mapID) then
        local list=Call("C_QuestLog.GetQuestsOnMap",mapID)
        if type(list)=="table" then for _,e in ipairs(list) do if type(e)=="table" and type(e.questID)=="number" then onMap[e.questID]=true end end end
        local info=Call("C_Map.GetMapInfo",mapID)
        self.zoneName=type(info)=="table" and Readable(info.name) and info.name or nil
    end
    self.onMap=onMap
    return onMap
end
-- " E G3 D": elite, suggested group size, dungeon (list and tracker).
function D.Tags(q)
    local tags=""
    if q.elite then tags=tags.." |cffffd200E|r" end
    if q.group and q.group>1 then tags=tags.." |cff66b3ffG"..q.group.."|r" end
    if q.dungeon then tags=tags.." |cffff8040D|r" end
    return tags
end
-- Title colour of a dungeon quest: the style's text colour, a third of the
-- way towards the dungeon tag's orange (a hint, not a signal colour).
function D.DungeonColor(style)
    local r,g,b=style:Color("text")
    return r+(1-r)*.35,g+(.5-g)*.35,b+(.25-b)*.35
end
function D:Read()
    local count=Call("C_QuestLog.GetNumQuestLogEntries")
    local quests,byID,zone={},{},nil
    local onMap=self:CurrentZone()
    for index=1,(type(count)=="number" and count or 0) do
        local info=Call("C_QuestLog.GetInfo",index)
        if type(info)=="table" then
            if info.isHeader then zone=Readable(info.title) and info.title or zone
            elseif type(info.questID)=="number" and not info.isHidden then
                local id=info.questID
                local quest={id=id,index=index,title=Readable(info.title) and info.title or ("Quest "..id),level=info.level,
                    difficulty=info.difficultyLevel or info.level,zone=zone or "Other",group=info.suggestedGroup,
                    complete=Call("C_QuestLog.IsComplete",id)==true,ready=Call("C_QuestLog.ReadyForTurnIn",id)==true,
                    failed=info.isFailed==true or Call("C_QuestLog.IsFailed",id)==true,
                    objectives=objectives(id),watched=Call("C_QuestLog.GetQuestWatchType",id)~=nil,
                    current=onMap[id]==true}
                quest.ready=quest.ready or quest.complete
                quest.distance,quest.onContinent=distance(id)
                local tag=Call("C_QuestLog.GetQuestTagInfo",id)
                if type(tag)=="table" then quest.elite=tag.isElite==true;quest.tag=Readable(tag.tagName) and tag.tagName or nil end
                quest.dungeon=quest.tag and (quest.tag:find("Dungeon") or quest.tag:find("Raid")) and true or false
                quest.progress=progress(quest)
                quest.xp=Call("GetQuestLogRewardXP",id)
                quests[#quests+1]=quest;byID[id]=quest
            end
        end
    end
    self.quests,self.byID=quests,byID
    self:Sort()
    return quests
end
-- fresh: objectives straight from the client (the watch update's old state).
function D:Quest(questID,fresh)
    local quest=self.byID[questID]
    if quest and fresh then
        quest.objectives=objectives(questID)
        quest.ready=Call("C_QuestLog.ReadyForTurnIn",questID)==true or Call("C_QuestLog.IsComplete",questID)==true
        quest.progress=progress(quest)
    end
    return quest
end

-- Difficulty colour like Blizzard's (GetQuestDifficultyColor when present).
function D.Color(level)
    local c=Call("GetQuestDifficultyColor",level or 0)
    if type(c)=="table" and type(c.r)=="number" then return c.r,c.g,c.b end
    local diff=(level or 0)-(Call("UnitLevel","player") or 0)
    if diff>=5 then return 1,.1,.1 elseif diff>=3 then return 1,.5,.25 elseif diff>=-2 then return 1,1,0
    elseif diff>=-8 then return .25,.75,.25 end
    return .5,.5,.5
end

-- Grouping and sorting (separate settings), pins first within a group.
local GROUPS={
    currentzone=function(q) return q.current and 1 or 2,q.current and (D.zoneName or "Current zone") or "Other zones" end,
    zone=function(q) return q.current and 0 or 1,q.zone end,
    status=function(q)
        if q.failed then return 3,"Failed" elseif q.ready then return 1,"Ready to turn in" end
        return 2,"In progress"
    end,
    none=function() return 1,nil end,
}
local function value(sortBy,q)
    if sortBy=="distance" then return q.ready and 1e9-1 or q.distance or 1e9 end
    if sortBy=="progress" then return -q.progress end
    if sortBy=="ready" then return q.ready and 0 or 1 end
    if sortBy=="level" then return q.level or 0 end
    if sortBy=="recent" then return -(D.recent[q.id] or 0) end
    return 0
end
function D:Sort()
    local cfg=Q:Config()
    local group,sortBy,pins=GROUPS[cfg.groupBy],cfg.sortBy,cfg.pins
    local search=self.search and self.search:lower() or nil
    local rows={}
    for _,q in ipairs(self.quests) do
        local match=not search or search=="" or q.title:lower():find(search,1,true) or (q.zone or ""):lower():find(search,1,true)
        if match then
            local order,name=group(q)
            q.groupOrder,q.groupName,q.pinned=order,name,pins[q.id]==true
            rows[#rows+1]=q
        end
    end
    table.sort(rows,function(a,b)
        if a.groupOrder~=b.groupOrder then return a.groupOrder<b.groupOrder end
        if (a.groupName or "")~=(b.groupName or "") then return (a.groupName or "")<(b.groupName or "") end
        if a.pinned~=b.pinned then return a.pinned end
        local va,vb=value(sortBy,a),value(sortBy,b)
        if va~=vb then return va<vb end
        if a.title~=b.title then return a.title<b.title end
        return a.id<b.id
    end)
    -- Flat list for the view: headers where the group changes.
    local list,last={},false
    for _,q in ipairs(rows) do
        if cfg.showHeaders and q.groupName and q.groupName~=last then list[#list+1]={header=q.groupName};last=q.groupName end
        list[#list+1]={quest=q}
    end
    self.list=list
    return list
end
-- Footer summary: quests in the log, at most, XP of the ready ones.
function D:Summary()
    local ready,xp=0,0
    for _,q in ipairs(self.quests) do
        if q.ready then ready=ready+1;if type(q.xp)=="number" then xp=xp+q.xp end end
    end
    local max=Call("C_QuestLog.GetMaxNumQuestsCanAccept") or 20
    return #self.quests,max,ready,xp
end

-- Details: text and rewards need the quest selected in the client's log.
function D:Details(questID)
    local quest=self.byID[questID]
    if not quest then return nil end
    Call("C_QuestLog.SetSelectedQuest",questID)
    local description,objectiveText=Call("GetQuestLogQuestText",quest.index)
    local d={quest=quest,description=Readable(description) and description or "",objectives=Readable(objectiveText) and objectiveText or "",
        xp=Call("GetQuestLogRewardXP",questID),money=Call("GetQuestLogRewardMoney",questID),rewards={},choices={}}
    for i=1,(Call("GetNumQuestLogRewards",questID) or 0) do
        local name,texture,count,quality,_,itemID=Call("GetQuestLogRewardInfo",i,questID)
        if name then d.rewards[#d.rewards+1]={name=name,texture=texture,count=count,quality=quality,itemID=itemID,kind="reward",index=i} end
    end
    for i=1,(Call("GetNumQuestLogChoices",questID) or 0) do
        local name,texture,count,quality,_,itemID=Call("GetQuestLogChoiceInfo",i)
        if name then d.choices[#d.choices+1]={name=name,texture=texture,count=count,quality=quality,itemID=itemID,kind="choice",index=i} end
    end
    d.pushable=Call("C_QuestLog.IsPushableQuest",questID)==true
    return d
end
-- An upgrade over what is worn in that slot (item level, same equip slot).
local SLOTS={INVTYPE_HEAD=1,INVTYPE_NECK=2,INVTYPE_SHOULDER=3,INVTYPE_CHEST=5,INVTYPE_ROBE=5,INVTYPE_WAIST=6,INVTYPE_LEGS=7,
    INVTYPE_FEET=8,INVTYPE_WRIST=9,INVTYPE_HAND=10,INVTYPE_FINGER=11,INVTYPE_TRINKET=13,INVTYPE_CLOAK=15,INVTYPE_WEAPON=16,
    INVTYPE_2HWEAPON=16,INVTYPE_WEAPONMAINHAND=16,INVTYPE_SHIELD=17,INVTYPE_WEAPONOFFHAND=17,INVTYPE_HOLDABLE=17,INVTYPE_RANGED=18}
function D.Upgrade(itemID)
    if type(itemID)~="number" then return false end
    local _,_,_,level,_,_,_,_,equip=Call("GetItemInfo",itemID)
    local slot=SLOTS[equip]
    if not slot or type(level)~="number" then return false end
    local worn=Call("GetInventoryItemLink","player",slot)
    if not worn then return true end
    local _,_,_,wornLevel=Call("GetItemInfo",worn)
    return type(wornLevel)=="number" and level>wornLevel
end
