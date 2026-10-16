local _,N=...
if not N.ready then return end
-- Leading on (Florian 2026-10-16): when the objective you are led to is done,
-- on to the next open one or the turn-in; the spots of the round on the maps;
-- a word when you reach a spot. Own settings page; /bv questnav test plays it
-- all through with a quest around you (no matching quest needed); it reads
-- like a real one, for screenshots (Florian 2026-10-16: no "test" texts).
local ns=N.ns
local QB=N.Questie
local G={}
N.Guide=G
G.DEFAULTS={autoNext=true,showSpots=true,announce=true}
G.TESTID=-1
G.EVENTS={"QUEST_LOG_UPDATE","QUEST_REMOVED","QUEST_TURNED_IN","UNIT_QUEST_LOG_CHANGED"}
G.SPOT={1,.82,.2}
-- Passing another spot of the round on the way (Florian 2026-10-16: the
-- round is planned by the straight line; a detour leads past later spots):
-- within this many yards it becomes the spot you are at.
G.PASSBY=30
G.TICK=1

function G:Config()
    local c=ns.Settings:Module("questnav")
    for key,value in pairs(self.DEFAULTS) do if c[key]==nil then c[key]=value end;c[key]=c[key]==true end
    return c
end
local function routing() local R=ns.Routing;return R and R.ready and R.Navigate and R or nil end
local function say(title,text)
    if ns.Stage then pcall(ns.Stage.Show,ns.Stage,"questnav",{title=title,subtitle=text}) end
    N:Print(title..(text and (": "..text) or ""))
end

-- The quest led to now: QB.active {questID, key, walkKey, title, arrived}.
-- Ours while Routing leads its way, or after you arrived there; another
-- way or stopping it yourself ends it.
function G:Leading()
    local a,R=QB.active,routing()
    if not (a and R) then return nil end
    local goal=R.Navigate.goal
    if goal then return goal.questWalk==a.walkKey and a or nil end
    return a.arrived and a or nil
end
-- A quest's state (the test quest, else the log's).
function G:Quest(questID)
    if self.test and questID==self.TESTID then return self.test end
    local Q=ns.Quest
    return Q and Q.Data and Q.Data:Quest(questID,true) or nil
end
function G:Targets(q) return q.testTargets or N:Targets(q) end
-- The next step of a quest, as the tracker picks it: the first open
-- objective with a place, else the turn-in.
function G:Target(q)
    local targets=q and self:Targets(q)
    if not targets then return nil end
    if not q.ready then
        for index,o in ipairs(q.objectives or {}) do
            if not o.finished and targets.objectives[index] then return "objective"..index,targets.objectives[index] end
        end
    end
    if targets.turnin then return "turnin",targets.turnin end
end

-- QB:Lead started a walk: remember it, listen while it runs, show its spots.
function G:Started(q,key,walkKey)
    QB.active={questID=q.id,key=key,walkKey=walkKey,title=q.title}
    local R=routing()
    if R then R.Navigate.onArrive=function(goal) if goal and goal.questWalk then G:Arrived(goal) end end end
    self:Watch(true)
    if not self.ticker and C_Timer and C_Timer.NewTicker then self.ticker=C_Timer.NewTicker(self.TICK,function() G:Tick() end) end
    self:Refresh()
end
function G:Clear()
    QB.active=nil
    self:Watch(false)
    if self.ticker then self.ticker:Cancel();self.ticker=nil end
    self:Refresh()
end
-- While led: another not yet visited spot of the round within PASSBY yards
-- is where you are; the one you were led to stays for later.
function G:Tick()
    local a,R=self:Leading(),routing()
    if not (a and R and R.Navigate.goal) then return end
    local walk=QB.walks[a.walkKey]
    if not (walk and #walk.spots>1) then return end
    local mapID,x,y=R:Position()
    local cont,cx,cy
    if mapID then cont,cx,cy=R:OnContinent(mapID,x,y) end
    if not cont then return end
    walk.visited=walk.visited or {}
    local best,bestD
    for i,s in ipairs(walk.spots) do
        if i~=walk.index and not walk.visited[i] and s.cont==cont then
            local d=R.Navigate.Yards(cont,cx,cy,s.x,s.y)
            if d<=self.PASSBY and (not bestD or d<bestD) then best,bestD=i,d end
        end
    end
    if not best then return end
    self:GoSpot(best)
    if self:Config().announce then say(string.format("Spot %d of %d is right here",best,#walk.spots),"passed on the way") end
end
-- Ends the walk: Routing's way (when it is ours), the spots, the bar.
function G:Stop()
    local a,R=QB.active,routing()
    if a and R and R.Navigate.goal and R.Navigate.goal.questWalk==a.walkKey then R.Navigate:Stop(true) end
    if a and QB.walks[a.walkKey] then QB.walks[a.walkKey].active=false end
    self:Clear()
end
-- To spot i of the walk (the bar's arrows, a click on a spot on the map).
function G:GoSpot(i)
    local a=self:Leading()
    local walk=a and QB.walks[a.walkKey]
    if not (walk and #walk.spots>0) then return end
    walk.index=(i-1)%#walk.spots+1
    a.arrived=nil
    QB:Go(walk,a.walkKey)
    self:Refresh()
end
function G:Step(delta)
    local a=self:Leading()
    local walk=a and QB.walks[a.walkKey]
    -- On: past the spots you have been at; back: the one before, visited or not.
    if walk then self:GoSpot(delta>0 and QB:NextIndex(walk,delta) or walk.index+delta) end
end
-- Quest events only while a walk runs (no lasting subscriptions).
function G:Watch(on)
    if on==(self.watching==true) or not ns.Events then return end
    self.watching=on or nil
    if not on then ns.Events:Release(G);return end
    for _,event in ipairs(self.EVENTS) do
        ns.Events:Subscribe(G,event,function(_,unit)
            if event=="UNIT_QUEST_LOG_CHANGED" and unit~="player" then return end
            G:Soon()
        end)
    end
end
-- Many quest events come at once: one look shortly after.
function G:Soon()
    if self.timer or not (C_Timer and C_Timer.NewTimer) then return end
    self.timer=C_Timer.NewTimer(.3,function() G.timer=nil;G:Check() end)
end

-- Arrived at a spot: say so (which spot, how to go on).
function G:Arrived(goal)
    local a=QB.active
    if not (a and goal and goal.questWalk==a.walkKey) then return end
    a.arrived=true
    local walk=QB.walks[a.walkKey]
    if walk then walk.visited=walk.visited or {};walk.visited[walk.index]=true end
    self:Refresh()
    if not self:Config().announce then return end
    local index,count=QB:Walk({id=a.questID},a.key)
    if count and count>1 then
        say(string.format("Spot %d of %d reached",index,count),"click the objective's button again for the next spot")
    else say("You are there",goal.label or goal.name) end
end

-- The objective led to is done: on to the next step; the quest gone (turned
-- in or abandoned): the walk ends.
function G:Check()
    local a=self:Leading()
    if not a then if QB.active then self:Clear() end;return end
    local q=self:Quest(a.questID)
    local R=routing()
    if not q then
        local ours=R and R.Navigate.goal and R.Navigate.goal.questWalk==a.walkKey
        self:Clear()
        if ours then R.Navigate:Stop(true) end
        if self:Config().announce then say("Quest done",a.title) end
        return
    end
    if not self:Config().autoNext or a.key=="turnin" then return end
    local index=tonumber(a.key:match("^objective(%d+)$"))
    local o=index and q.objectives and q.objectives[index]
    if o and not o.finished and not q.ready then return end
    local key,target=self:Target(q)
    if not target or key==a.key then return end
    if self:Config().announce then say(key=="turnin" and "Quest ready" or "Objective done","on to "..target.label) end
    QB:Lead(q,key,target)
end

-- The spots of the walk on the world map and the minimap: the one you go
-- to large, the others small; number and count in the tooltip.
function G:Points()
    local out={}
    local a=QB.active
    if not (a and self:Config().showSpots and self:Leading()) then return out end
    local walk=QB.walks[a.walkKey]
    if not (walk and #walk.spots>1) then return out end
    for i,s in ipairs(walk.spots) do
        local now=i==walk.index
        out[#out+1]={mapID=s.cont,x=s.x,y=s.y,dot=true,size=now and 12 or 7,hollow=not now or nil,color=self.SPOT,
            alpha=now and 1 or .75,lineAlpha=0,noLine=true,key="questnav"..i,
            title=string.format("Spot %d of %d",i,#walk.spots),text=s.name}
    end
    return out
end
function G:Refresh()
    if ns.MapPins then ns.MapPins:Refresh() end
    self:Bar()
end
if ns.MapPins then
    ns.MapPins:Register("questnav:spots",{points=function() return G:Points() end,minimap=true,
        tooltip=function(p) return p.title,(p.text and (p.text.."\n") or "").."Click: go there. Right-click: end the walk." end,
        onClick=function(p,button)
            if button=="RightButton" then G:Stop() return end
            local i=tonumber(p.key and p.key:match("^questnav(%d+)$"))
            if i then G:GoSpot(i) end
        end})
end

-- The walk's bar (Florian 2026-10-16: after arriving the guide is gone and
-- nothing let you go on or end the walk): quest, objective, "Spot 2 of 5",
-- the previous and the next spot, end. Under Routing's guide while it shows,
-- in its place after you arrived.
G.BARW,G.BARH=320,58
function G:BarFrame()
    if self.bar then return self.bar end
    local UI,M=ns.UI,ns.DesignSystem.Metrics
    UI:WithStyle(UI:GameStyle(nil),function()
        local f=UI:Panel(UIParent,G.BARW,G.BARH,"panel",12,.95)
        f:Hide();f:SetFrameStrata("DIALOG");f:SetClampedToScreen(true)
        if ns.ExternalFrames then ns.ExternalFrames:MarkOwned(f) end
        f.title=UI:Label(f,"",10,"muted",true);M.Point(f.title,"TOPLEFT",f,"TOPLEFT",14,-10);M.Size(f.title,G.BARW-120,14)
        f.label=UI:Label(f,"",13,"text");M.Point(f.label,"TOPLEFT",f,"TOPLEFT",14,-27);M.Size(f.label,G.BARW-120,18)
        f.stop=UI:IconButton(f,"x",function() G:Stop() end,"ghost")
        M.Size(f.stop,20,20);M.Point(f.stop,"TOPRIGHT",f,"TOPRIGHT",-10,-10)
        UI:AttachTooltip(f.stop,"End the walk","Ends the way to this objective and takes its spots off the maps.")
        f.next=UI:IconButton(f,"chevron-right",function() G:Step(1) end,"ghost")
        M.Size(f.next,20,20);M.Point(f.next,"TOPRIGHT",f,"TOPRIGHT",-10,-32)
        UI:AttachTooltip(f.next,"Next spot","On to the next spot of the round.")
        f.spot=UI:Label(f,"",11,"muted");M.Point(f.spot,"RIGHT",f.next,"LEFT",-4,0);f.spot:SetJustifyH("CENTER");M.Size(f.spot,44,14)
        -- Back: the "chevron-right" symbol mirrored (the suite's symbol pages
        -- hold no "chevron-left"; their selection stays at two pages).
        f.prev=UI:IconButton(f,"chevron-right",function() G:Step(-1) end,"ghost")
        local glyph=f.prev.icon and f.prev.icon.glyph
        if glyph and glyph.GetTexCoord then
            local ul,ut,ll,lb,ur,urt,lr,lrb=glyph:GetTexCoord()
            if type(ul)=="number" and type(lr)=="number" then glyph:SetTexCoord(ur,urt,lr,lrb,ul,ut,ll,lb) end
        end
        M.Size(f.prev,20,20);M.Point(f.prev,"RIGHT",f.spot,"LEFT",-4,0)
        UI:AttachTooltip(f.prev,"Previous spot","Back to the spot before.")
        self.bar=f
    end)
    return self.bar
end
function G:Bar()
    local a=self:Leading()
    if not a then if self.bar then self.bar:Hide() end;return end
    local f=self:BarFrame()
    local walk=QB.walks[a.walkKey]
    local count=walk and #walk.spots or 0
    f.title:SetText(a.title or "")
    local text=walk and walk.label or ""
    if a.arrived then text=(count>1 and "At this spot: " or "Arrived: ")..text end
    f.label:SetText(text)
    f.spot:SetText(count>1 and string.format("%d / %d",walk.index,count) or "")
    f.prev:SetShown(count>1);f.next:SetShown(count>1);f.spot:SetShown(count>1)
    -- Under the guide while it shows; else where the guide stands.
    local M=ns.DesignSystem.Metrics
    local guide=ns.Routing and ns.Routing.Guide and ns.Routing.Guide.frame
    f:ClearAllPoints()
    if guide and guide:IsShown() then M.Point(f,"TOP",guide,"BOTTOM",0,-6)
    else
        local at=ns.Routing and ns.Routing:Config().guideAt
        if type(at)=="table" and type(at.x)=="number" and type(at.y)=="number" then f:SetPoint("CENTER",UIParent,"BOTTOMLEFT",at.x,at.y)
        else f:SetPoint("TOP",UIParent,"TOP",0,-M.ToNative(140)) end
    end
    f:Show()
end
-- The guide comes and goes with Routing's way: the bar follows it.
if ns.Routing and ns.Routing.Guide and hooksecurefunc then
    hooksecurefunc(ns.Routing.Guide,"Update",function() G:Bar() end)
end
if ns.Stage then
    ns.Stage:Register({id="questnav",label="Quest navigation",priority=1,hold=4,
        description="Quest Navigation: a spot reached, an objective done and on to the next one.",
        sample={title="Spot 2 of 5 reached",subtitle="click the objective's button again for the next spot"}})
end

-- /bv questnav test [next|arrive|done|stop]: a quest around you with five
-- spots, a second objective and a turn-in at your place; nothing in the game
-- says "test" (screenshots).
function G:Test(action)
    local R=routing()
    if not R then N:Print("BV Routing is needed for the test.");return end
    action=action~="" and action or "start"
    local a=QB.active and QB.active.questID==self.TESTID and QB.active or nil
    if action=="start" then
        local mapID,x,y=R:Position()
        local cont,cx,cy
        if mapID then cont,cx,cy=R:OnContinent(mapID,x,y) end
        if not cont then N:Print("Your position is not known here; try it outdoors or in a city.");return end
        local yx=R.Navigate.Yards(cont,cx,cy,cx+.001,cy)/.001
        local yy=R.Navigate.Yards(cont,cx,cy,cx,cy+.001)/.001
        local function ring(n,near,far,name)
            local places={}
            for i=1,n do
                local angle,r=2*math.pi*i/n,(i%2==0) and far or near
                places[#places+1]={cont=cont,x=cx+math.cos(angle)*r/yx,y=cy+math.sin(angle)*r/yy,name=name}
            end
            return places
        end
        local wolves,supplies="Timber Wolf slain: 0/8","Wolf Den Supplies: 0/1"
        self.test={id=self.TESTID,title="Thinning the Pack",ready=false,
            objectives={{text=wolves,type="monster",finished=false},{text=supplies,type="object",finished=false}}}
        self.test.testTargets={objectives={{label=wolves,places=ring(5,60,110,"Timber Wolf")},
            {label=supplies,places=ring(1,90,90,"Wolf Den Supplies")}},
            turnin={label="Turn in: Scout Tharr",places={{cont=cont,x=cx,y=cy,name="Scout Tharr"}}}}
        QB.walks[self.TESTID..":objective1"]=nil
        QB:Lead(self.test,"objective1",self.test.testTargets.objectives[1])
        return
    end
    if not (self.test and a) then N:Print("Nothing started: /bv questnav test");return end
    local q=self.test
    if action=="next" then
        local index=tonumber(a.key:match("^objective(%d+)$"))
        local target=index and q.testTargets.objectives[index] or q.testTargets.turnin
        QB:Lead(q,a.key,target)
    elseif action=="arrive" then
        self:Arrived(R.Navigate.goal or {questWalk=a.walkKey,label=a.key})
    elseif action=="done" then
        if a.key=="turnin" then self.test=nil
        else
            local index=tonumber(a.key:match("^objective(%d+)$"))
            if index and q.objectives[index] then q.objectives[index].finished=true end
            local open=false
            for _,o in ipairs(q.objectives) do if not o.finished then open=true end end
            q.ready=not open
        end
        self:Check()
    elseif action=="stop" then
        self.test=nil
        self:Stop()
    else N:Print("/bv questnav test [next|arrive|done|stop]") end
end

-- Settings page (Florian 2026-10-16; laid out by Config through Arrange).
local page
local function build(parent)
    local UI,M=ns.UI,ns.DesignSystem.Metrics
    page=UI:Panel(parent,880,600,"surface");UI:HideSurface(page)
    local g=UI:SettingsGrid(page);page.grid=g
    local controls={}
    page.controls=controls
    local function switch(key,title,help)
        controls[key]=g:Row(title,UI:Switch(g,false,function(value) G:Config()[key]=value==true;G:Refresh() end),{help=help})
    end
    g:Section("status","Quest Navigation")
    page.status=g:Row("Status",UI:Label(g,"",11,"muted"),{width=420,help="Quest Navigation reads where objectives are from Questie's database; BV Routing leads you there."})
    g:Section("lead","Leading")
    switch("autoNext","On to the next step","When the objective you are led to is done, lead on to the next open objective, or to the turn-in when the quest is ready.")
    switch("showSpots","Spots on the maps","The spots of the round you walk on the world map and the minimap; the one you go to is large.")
    switch("announce","Tell me","A notification when you reach a spot, finish an objective or the quest.")
    function page:Arrange(width)
        UI:Place(g,self,0,0)
        local height=g:Arrange(width)+8
        M.Height(self,height);return height
    end
    function page:Refresh()
        local c=G:Config()
        for key in pairs(G.DEFAULTS) do controls[key]:SetValue(c[key]) end
        local missing=QB:Missing()
        if self.status.SetText then self.status:SetText(missing or "Ready: Questie's database and BV Routing are there.") end
    end
    page:Refresh()
    return page
end
ns.Config:RegisterPage("questnav",{title="Quest Navigation",category="questmap",description="Leading to quest objectives: on to the next step, spots on the maps and notifications.",
    build=function(parent) return page or build(parent) end,
    refresh=function() if page then page:Refresh() end end})
