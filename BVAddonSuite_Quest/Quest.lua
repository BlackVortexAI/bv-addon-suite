local package,Q=...
local ns=BVAddonSuiteCore
if not ns or not ns.RequireCore then
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(package.." requires BV Addon Suite - Core 0.8.95 or newer. Update Core; saved data is preserved.") end
    return
end
-- Own version, oldest compatible Core, Core interface generation.
if not ns:RequireCore(package,"0.1.2","0.8.96",1) then return end
-- Quest package (docs/map-quest-concept.md): the quest log beside the world
-- map. Files fill Q (package-private): Data (quest log model, sorting),
-- Panes (docking beside the map, splitters), List, Details, Options.
Q.ns=ns
ns.Quest=Q
Q.ready=true
Q.ID="quest"

-- Display switches (Florian: every element its own switch), look, sorting.
Q.DEFAULTS={enabled=false,
    -- Order of the three panes, left to right; widths of the own panes.
    -- Default Map · List · Details (Florian 2026-10-07).
    order="map,list,details",listWidth=300,detailsWidth=320,
    -- Blizzard's own quest list beside the map: hidden while ours is shown.
    hideBlizzard=true,
    -- Grouping and sorting are separate settings.
    groupBy="currentzone",sortBy="distance",
    -- List elements.
    levelMode="badge",progressMode="text",showDistance=true,showHeaders=true,showTags=true,showFooter=true,
    -- Look.
    density="compact",fontSize=12,opacity=92,styleFamily="inherit",
    -- Details sections.
    detailsText=true,detailsRewards=true,
    -- Tracker on screen (modelled on Horizon Focus; Florian 2026-10-08): which
    -- quests (tracked plus current zone, tracked only, the N nearest), layout,
    -- progress, behaviour in combat and instances, clicks, auto-focus.
    tracker=true,trackerMode="watchedzone",trackerCount=6,trackerLayout="full",trackerProgress="bar",
    trackerCombat="show",trackerInstance="show",trackerMouseover=false,trackerBackground=false,trackerOpacity=60,
    trackerLeft="focus",trackerHideBlizzard=true,trackerMaxHeight=480,trackerUnlocked=false,autoFocus=false,
    -- Dungeon run banner: time, XP and gold per hour in party dungeons.
    banner=true,
    -- Dungeon quests (Florian 2026-10-08): their own sections in the tracker,
    -- one per dungeon, and a slightly warmer title colour in tracker and list.
    trackerGroupDungeons=true,dungeonColor=true,
    pins={}}
local CHOICES={order={["list,map,details"]=true,["details,map,list"]=true,["map,list,details"]=true,["map,details,list"]=true,["list,details,map"]=true,["details,list,map"]=true},
    groupBy={currentzone=true,zone=true,status=true,none=true},sortBy={distance=true,progress=true,ready=true,level=true,recent=true,title=true},
    levelMode={badge=true,color=true,off=true},progressMode={text=true,bar=true,off=true},density={compact=true,normal=true,comfortable=true},
    trackerMode={watchedzone=true,watched=true,nearest=true},trackerLayout={full=true,compact=true,minimal=true},
    trackerProgress={bar=true,text=true,percent=true,off=true},trackerCombat={show=true,fade=true,hide=true},
    trackerInstance={show=true,hide=true},trackerLeft={focus=true,map=true}}
local function num(value,default,low,high)
    if type(value)~="number" or value~=value then value=default end
    return math.max(low,math.min(high,math.floor(value+.5)))
end
function Q:Config()
    local cfg=ns.Settings:Module(self.ID)
    for key,value in pairs(self.DEFAULTS) do if cfg[key]==nil then cfg[key]=type(value)=="table" and {} or value end end
    -- 0.1.0 started with List · Map · Details; the old default moves over once.
    if cfg.orderDefault~=2 then if cfg.order=="list,map,details" then cfg.order="map,list,details" end;cfg.orderDefault=2 end
    for key,valid in pairs(CHOICES) do if not valid[cfg[key]] then cfg[key]=self.DEFAULTS[key] end end
    for _,key in ipairs({"hideBlizzard","showDistance","showHeaders","showTags","showFooter","detailsText","detailsRewards",
        "tracker","trackerMouseover","trackerBackground","trackerHideBlizzard","trackerUnlocked","autoFocus","banner","trackerGroupDungeons","dungeonColor"}) do cfg[key]=cfg[key]==true end
    cfg.trackerCount=num(cfg.trackerCount,6,1,20);cfg.trackerOpacity=num(cfg.trackerOpacity,60,0,100);cfg.trackerMaxHeight=num(cfg.trackerMaxHeight,480,120,1000)
    cfg.listWidth=num(cfg.listWidth,300,200,600);cfg.detailsWidth=num(cfg.detailsWidth,320,220,600)
    cfg.fontSize=num(cfg.fontSize,12,9,18);cfg.opacity=num(cfg.opacity,92,30,100)
    if cfg.styleFamily~="inherit" and not ns.Styles.families[cfg.styleFamily] then cfg.styleFamily="inherit" end
    if type(cfg.pins)~="table" then cfg.pins={} end
    return cfg
end
function Q:Active() return self.context~=nil end
function Q:Style() return ns.UI:GameStyle(self.ID) end
function Q:Family() return ns.Styles:Family(self.ID) end
function Q:Print(text) ns:Print(text,"Quest") end
-- Client calls through one place so tests and missing APIs never fault.
function Q.Call(path,...)
    local f=_G
    for part in path:gmatch("[^%.]+") do if type(f)~="table" then return nil end;f=f[part] end
    if type(f)~="function" then return nil end
    local result={pcall(f,...)}
    if not result[1] then return nil end
    return unpack(result,2)
end
-- The Map package's waypoints, when it is loaded and on (quest objective menus).
function Q.MapWaypoints()
    local map=ns.Map
    if map and map.Active and map:Active() and map.Waypoints then return map.Waypoints end
    return nil
end
function Q.Secret(value) return issecretvalue and issecretvalue(value) or false end
function Q.Readable(value) return value~=nil and not Q.Secret(value) end
-- Row height per density (design units).
Q.DENSITY={compact=18,normal=22,comfortable=26}

-- Events: the log is read again shortly after a change, only while shown.
-- Quest progress (QUEST_WATCH_UPDATE arrives with the old state, the next
-- log update has the new one; probe 2026-10-07) marks "recent" and feeds the
-- notification stage.
local callbacks={}
function Q:On(event,owner,fn) callbacks[event]=callbacks[event] or {};callbacks[event][owner]=fn end
function Q:Emit(event,...) for _,fn in pairs(callbacks[event] or {}) do fn(...) end end
function Q:Dirty()
    self.dirty=true
    if self.refreshTimer or not self:Visible() then return end
    -- The map may close before the timer fires: then it stays dirty for the next show.
    self.refreshTimer=C_Timer.NewTimer(.1,function() Q.refreshTimer=nil;if Q:Visible() then Q:Refresh() end end)
end
-- The log is read while the quest log beside the map or the tracker is shown.
function Q:Visible() return (self.Panes and self.Panes:Visible()) or (self.Tracker and self.Tracker:Shown()) or false end
function Q:Refresh()
    if not self:Active() then return end
    self.dirty=false
    self.Data:Read()
    self:Emit("Changed")
end
-- Objective counts after a watch update: progress notifications and "recent".
function Q:Progress()
    local before=self.watched
    self.watched=nil
    if not before then return end
    for questID,old in pairs(before) do
        local quest=self.Data:Quest(questID,true)
        if quest then
            for index,objective in ipairs(quest.objectives) do
                local was=old[index]
                if was and objective.have and was<objective.have then
                    self.Data.recent[questID]=GetTime()
                    if ns.Stage and not quest.ready then
                        pcall(ns.Stage.Show,ns.Stage,"questprogress",{title=objective.text,subtitle=quest.title,key=questID})
                    end
                end
            end
            if quest.ready and not old.ready and ns.Stage then
                pcall(ns.Stage.Show,ns.Stage,"questready",{title=quest.title,subtitle="Ready to turn in",key=questID})
            end
        end
    end
end
function Q:Remember(questID)
    if type(questID)~="number" or Q.Secret(questID) then return end
    local quest=self.Data:Quest(questID,true)
    if not quest then return end
    self.watched=self.watched or {}
    local counts={ready=quest.ready}
    for index,objective in ipairs(quest.objectives) do counts[index]=objective.have end
    self.watched[questID]=self.watched[questID] or counts
end

if ns.Stage then
    ns.Stage:Register({id="questprogress",label="Quest progress",priority=1,hold=3,
        description="An objective moved on, e.g. \"Silithid Egg: 7/12\". Shown while the Quest module is on.",
        sample={title="7/12 Silithid Egg",subtitle="Egg Hunt"}})
    ns.Stage:Register({id="questready",label="Quest ready",priority=2,hold=4,
        description="All objectives of a quest are done.",sample={title="Egg Hunt",subtitle="Ready to turn in"}})
end

-- Blizzard's own progress line ("Silithid Egg: 7/12", UI_INFO_MESSAGE, type 317
-- in the probe of 2026-10-07) shows next to ours. While the module runs it
-- takes that one event from UIErrorsFrame and hands every message on to
-- Blizzard's own handler, except quest progress while our "Quest progress"
-- notification is on (Florian 2026-10-07). Off: the frame gets its event back.
local PROGRESS_TYPES={"LE_GAME_ERR_QUEST_ADD_ITEM_SII","LE_GAME_ERR_QUEST_ADD_KILL_SII","LE_GAME_ERR_QUEST_ADD_FOUND_SII",
    "LE_GAME_ERR_QUEST_ADD_PLAYER_KILL_SII","LE_GAME_ERR_QUEST_OBJECTIVE_COMPLETE_S"}
function Q.QuestProgressMessage(messageType,message)
    if Q.Secret(messageType) or Q.Secret(message) then return false end
    for _,name in ipairs(PROGRESS_TYPES) do
        local value=rawget(_G,name)
        if value~=nil and value==messageType then return true end
    end
    return type(message)=="string" and message:find(": %d+/%d+$")~=nil
end
-- Core's shared info line (Core/InfoMessages.lua; the Map package filters
-- "Discovered" there too).
function Q:TakeInfoMessages(context)
    if not ns.InfoMessages then return end
    ns.InfoMessages:Filter("quest",function(messageType,message)
        local ours=ns.Stage and ns.Stage.types.questprogress and ns.Stage:TypeConfig("questprogress").enabled
        return ours and Q.QuestProgressMessage(messageType,message) or false
    end)
    context:Defer(function() ns.InfoMessages:Release("quest") end)
end

ns.Modules:Register({id=Q.ID,OnEnable=function(context)
    Q.context=context
    context:Defer(function() Q.context=nil;if Q.refreshTimer then Q.refreshTimer:Cancel();Q.refreshTimer=nil end end)
    Q:Config()
    local function dirty() Q:Dirty() end
    for _,event in ipairs({"QUEST_LOG_UPDATE","QUEST_ACCEPTED","QUEST_REMOVED","QUEST_TURNED_IN","QUEST_WATCH_LIST_CHANGED",
        "SUPER_TRACKING_CHANGED","ZONE_CHANGED_NEW_AREA","ZONE_CHANGED"}) do
        pcall(context.Subscribe,context,event,dirty)
    end
    pcall(context.Subscribe,context,"QUEST_WATCH_UPDATE",function(_,questID) Q:Remember(questID);Q:Dirty() end)
    pcall(context.Subscribe,context,"UNIT_QUEST_LOG_CHANGED",function(_,unit) if unit=="player" then Q.Data:Read();Q:Progress();Q:Dirty() end end)
    Q:TakeInfoMessages(context)
    Q.Data:Read()
    Q.Panes:Enable(context)
    Q.Run:Enable(context)
    Q.Tracker:Enable(context)
end})
