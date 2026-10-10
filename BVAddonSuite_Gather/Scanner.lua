local _,G=...
if not G.ready then return end
-- Minimap scanner (Florian 2026-10-10): warns when a herb or ore of your
-- list shows on the minimap, with a sound per entry and an on-screen
-- message, and keeps the last finds for the Minimap finds window.
-- No API lists the minimap's dots, but C_TooltipInfo.GetMinimapMouseover
-- names what lies under Minimap:UpdateMouseoverAtPoint(x, y) (WoW: Forever).
-- Measured with /bv map minimapprobe (Florian's runs 2026-10-10, see
-- docs/handoffs/2026-10-09-gather-spawn-data.md): it answers only while the
-- minimap lies under the cursor and takes mouse events since the frame
-- before. So the scanner works in the HUD (its large minimap lies under the
-- cursor anyway): the minimap's mouse is switched on, the next frame a grid
-- every 12 units is asked in one go (a dot answers about 10 units around
-- it; about 2800 points, 27 ms at 720 units), then the mouse is off again.
-- Never in combat, never while a mouse button is down.
-- One warning per node: a find within SAME yards of a known one of the same
-- name is that node; it warns again only after it was gone for the chosen
-- minutes (respawn, or you came back). Gathering it counts as seen.
local ns=G.ns
local S={recent={},seen={},played={},status="off"}
G.Scanner=S
S.STEP=12      -- minimap units between grid points
S.EVERY=2      -- seconds between scans
S.TICK=.25     -- seconds between status checks (the HUD's text)
S.SAME=40      -- yards: the same node (the distance read wobbles 10-20 %)
S.RECENT=20    -- finds kept for the window
S.QUIET=10     -- seconds before one name may sound again
S.DEFAULT_SOUND={source="soundkit",soundKit=8959} -- SOUNDKIT.RAID_WARNING
S.CHANNELS={"Master","SFX","Ambience","Dialog","Music"}
S.TARGET_COLOR={.72,.42,1}  -- the find you go to: purple (the route's next point is green)
S.ARRIVE=15    -- yards to the target that count as reached
S.GONE=3       -- scans in a row without it, while it lies in view: gone
S.FAR=2        -- times the view radius at the find: walked away, the line ends

-- Names offered for the list: the herbs and ores Gather knows (skill table
-- and the database), English as the nodes are named.
local ORE={"Vein","Deposit","Chunk"}
local function oreName(name) for _,word in ipairs(ORE) do if name:find(word,1,true) then return true end end return false end
function S:Names(kind)
    local seen,out={},{}
    local function add(name) if type(name)=="string" and name~="" and not seen[name] then seen[name]=true;out[#out+1]=name end end
    for name in pairs(G.SKILL) do if (kind=="ore")==oreName(name) then add(name) end end
    for _,name in ipairs(G.Data.db and G.Data:Names(kind) or {}) do add(name) end
    table.sort(out)
    return out
end
-- "herb", "ore" or nil (NPCs, mailboxes, quest targets on the minimap).
function S:Kind(name)
    local revision=G.Data.revision or 0
    if not self.kinds or self.kindsRevision~=revision then
        self.kinds,self.kindsRevision={},revision
        for _,kind in ipairs({"herb","ore"}) do for _,n in ipairs(self:Names(kind)) do self.kinds[n]=self.kinds[n] or kind end end
    end
    return self.kinds[name]
end

-- The list: {name=, sound=nil (default) | false (none) | {source, soundKit|sound}}.
function S:List() return G:Config().scanWatch end
function S:Watched(name)
    for i,entry in ipairs(self:List()) do if entry.name==name then return entry,i end end
end
function S:Add(name)
    if type(name)~="string" or name=="" or self:Watched(name) then return false end
    table.insert(self:List(),{name=name})
    return true
end
function S:Remove(name)
    local _,i=self:Watched(name)
    if i then table.remove(self:List(),i) end
end
-- The sound to play for an entry (nil: none), with the chosen channel.
function S:Sound(entry)
    local c=G:Config()
    local sound=entry and entry.sound
    if sound==false then return nil end
    if type(sound)~="table" then sound=c.scanSound end
    if type(sound)~="table" then return nil end
    return {source=sound.source,soundKit=sound.soundKit,sound=sound.sound,channel=c.scanChannel,volume=100}
end
function S:Play(entry)
    local sound=self:Sound(entry)
    if not sound then return false end
    return ns.Sound:Play(S,"alert",sound)
end

-- Names in the minimap's mouseover tooltip: names separated by "\n",
-- textures (the above/below arrows) and colour codes stripped, titles
-- ("<Innkeeper>") skipped.
function S.Parse(data)
    local names={}
    if type(data)~="table" or type(data.lines)~="table" then return names end
    for _,line in ipairs(data.lines) do
        local text=line.leftText
        if type(text)=="string" and not G.Secret(text) then
            for part in (text.."\n"):gmatch("(.-)\n") do
                local name=part:gsub("|T.-|t",""):gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","")
                name=name:match("^%s*(.-)%s*$")
                if name~="" and not part:match("^%s+<") then names[#names+1]=name end
            end
        end
    end
    return names
end
-- Grid points within the minimap's circle (cached per size).
function S:Cells(radius)
    local key=math.floor(radius)
    if self.cells and self.cellsKey==key then return self.cells end
    local cells,n=({}),math.floor(radius/self.STEP)
    for ix=-n,n do for iy=-n,n do
        local x,y=ix*self.STEP,iy*self.STEP
        if x*x+y*y<=radius*radius then cells[#cells+1]={x,y} end
    end end
    self.cells,self.cellsKey=cells,key
    return cells
end
-- Hits of one name -> groups of neighbouring grid points with their centre.
function S.Groups(hits,step)
    local groups,left={},{}
    for i,hit in ipairs(hits) do left[i]=hit end
    while next(left) do
        local i,first=next(left);left[i]=nil
        local group,queue={first},{first}
        while #queue>0 do
            local a=table.remove(queue)
            for j,b in pairs(left) do
                if math.abs(a[1]-b[1])<=step*1.01 and math.abs(a[2]-b[2])<=step*1.01 then left[j]=nil;group[#group+1]=b;queue[#queue+1]=b end
            end
        end
        local sx,sy=0,0
        for _,p in ipairs(group) do sx,sy=sx+p[1],sy+p[2] end
        groups[#groups+1]={x=sx/#group,y=sy/#group}
    end
    return groups
end
-- Minimap offset -> yards north and east of you; up is north, or your
-- facing when the minimap turns (radians, counter-clockwise from north).
function S.Yards(ox,oy,yardsPerUnit,facing)
    local a=facing or 0
    return (oy*math.cos(a)+ox*math.sin(a))*yardsPerUnit,(ox*math.cos(a)-oy*math.sin(a))*yardsPerUnit
end
local POINTS={"N","NE","E","SE","S","SW","W","NW"}
function S.Direction(north,east)
    local angle=math.deg(math.atan2(east,north))%360
    return POINTS[math.floor((angle+22.5)/45)%8+1]
end

-- Status for the HUD: "off", "combat", "mouse" (cursor not on the minimap)
-- or "active".
local function minimap() return rawget(_G,"Minimap") end
function S:CursorOn(m)
    local x,y=G.Call("GetCursorPosition")
    local cx,cy=m:GetCenter()
    if type(x)~="number" or not cx then return false end
    local s=m:GetEffectiveScale()
    local r=m:GetWidth()/2*s
    return (x-cx*s)^2+(y-cy*s)^2<=r*r
end
function S:Available()
    local m=minimap()
    return m~=nil and type(m.UpdateMouseoverAtPoint)=="function" and C_TooltipInfo~=nil and type(C_TooltipInfo.GetMinimapMouseover)=="function"
end
function S:Check()
    local m=minimap()
    local status
    if not (G:Config().scanner and G:Active()) then status="off"
    elseif not self:Available() then status="missing"
    elseif G.Call("InCombatLockdown") then status="combat"
    elseif not (m and self:CursorOn(m)) then status="mouse"
    else status="active" end
    if status~=self.status then
        self.status=status
        if G.Hud.ScanStatus then G.Hud:ScanStatus() end
        if G.Finds then G.Finds:Refresh() end
    end
    return status
end

-- Runs while the HUD is open.
function S:Update()
    local want=G:Active() and G.Hud:On()
    if want and not self.ticker then
        self.next=0
        self.ticker=C_Timer.NewTicker(self.TICK,function() S:Tick() end)
    elseif not want and self.ticker then
        self.ticker:Cancel();self.ticker=nil
        self:Disarm()
    end
    self:Check()
end
-- A click in progress must reach the world, not the minimap.
function S:ButtonDown()
    for _,button in ipairs({"LeftButton","RightButton","MiddleButton"}) do
        if G.Call("IsMouseButtonDown",button) then return true end
    end
    return false
end
function S:Tick()
    if self:Check()~="active" or self.armed then return end
    local now=GetTime()
    if now<(self.next or 0) or self:ButtonDown() then return end
    self.next=now+self.EVERY
    -- Mouse on now, the grid next frame (the minimap answers only then).
    local m=minimap()
    if not pcall(m.EnableMouse,m,true) then return end
    self.armed=true
    self.scanTimer=C_Timer.NewTimer(0,function() S.scanTimer=nil;S:Scan() end)
end
-- The minimap's mouse back off (the HUD keeps it off; closed, the HUD has
-- put back your own setting already).
function S:Disarm()
    if self.scanTimer then self.scanTimer:Cancel();self.scanTimer=nil end
    if not self.armed then return end
    self.armed=nil
    local m=minimap()
    if m and G.Hud:On() then pcall(m.EnableMouse,m,false) end
end
function S:Scan()
    local ok,hits=pcall(self.Read,self)
    self:Disarm()
    if ok and hits then self:Found(hits) end
end
-- Names on the grid, only herbs and ores: name -> grid points.
function S:Read()
    if not (self.armed and self:Check()=="active") then return nil end
    local m=minimap()
    local cx,cy=m:GetCenter()
    local s=m:GetEffectiveScale()
    local hits={}
    for _,cell in ipairs(self:Cells(m:GetWidth()/2)) do
        if pcall(m.UpdateMouseoverAtPoint,m,(cx+cell[1])*s,(cy+cell[2])*s) then
            local ok,data=pcall(C_TooltipInfo.GetMinimapMouseover)
            if ok then
                for _,name in ipairs(S.Parse(data)) do
                    if self:Kind(name) then hits[name]=hits[name] or {};table.insert(hits[name],cell) end
                end
            end
        end
    end
    return hits
end

-- The node seen before: same name, same map, within SAME yards (without a
-- position: the same name).
function S:Match(name,mapID,x,y)
    for _,entry in ipairs(self.seen) do
        if entry.name==name and entry.mapID==mapID then
            if not (x and entry.x) then return entry end
            local d=G.Data.Yards(mapID,entry.x,entry.y,x,y)
            if d and d<=self.SAME then return entry end
        end
    end
end
function S:Found(hits)
    local m=minimap()
    local c=G:Config()
    local now=GetTime()
    local mapID,px,py=G.Record:Position()
    local w,h
    if mapID then w,h=G.Call("C_Map.GetMapWorldSize",mapID) end
    local view=G.Call("C_Minimap.GetViewRadius")
    local yardsPerUnit=type(view)=="number" and not G.Secret(view) and view/(m:GetWidth()/2) or 1
    local facing=0
    if G.Call("GetCVar","rotateMinimap")=="1" then
        local value=G.Call("GetPlayerFacing")
        if type(value)=="number" and not G.Secret(value) then facing=value end
    end
    local fresh={}
    for name,list in pairs(hits) do
        for _,group in ipairs(S.Groups(list,self.STEP)) do
            local north,east=S.Yards(group.x,group.y,yardsPerUnit,facing)
            local x,y
            if px and type(w)=="number" and w>0 and type(h)=="number" and h>0 then x,y=px+east/w,py-north/h end
            local entry=self:Match(name,mapID,x,y)
            local again=entry and now-entry.last>=c.scanRepeat*60
            if not entry then
                entry={name=name,kind=self:Kind(name),mapID=mapID};table.insert(self.seen,entry)
            end
            entry.view=type(view)=="number" and not G.Secret(view) and view or entry.view
            if not entry.last or again then
                entry.yards=math.floor(math.sqrt(north*north+east*east)+.5);entry.direction=S.Direction(north,east)
                entry.time=time()
                fresh[#fresh+1]=entry
            end
            entry.last=now
            if x then entry.x,entry.y=x,y end
        end
    end
    self:Missing(now)
    -- Forget nodes long gone (the list stays small).
    for i=#self.seen,1,-1 do if now-self.seen[i].last>c.scanRepeat*120 then table.remove(self.seen,i) end end
    if #fresh==0 then return end
    for _,entry in ipairs(fresh) do
        table.insert(self.recent,1,{name=entry.name,kind=entry.kind,yards=entry.yards,direction=entry.direction,time=entry.time,watched=self:Watched(entry.name)~=nil,node=entry})
    end
    while #self.recent>self.RECENT do table.remove(self.recent) end
    self:Alert(fresh)
    if G.Finds then G.Finds:Refresh() end
end
-- One message and one sound per scan: the entry highest in your list.
function S:Alert(fresh)
    local c=G:Config()
    local watched={}
    for _,entry in ipairs(fresh) do
        local item,index=self:Watched(entry.name)
        if item then watched[#watched+1]={entry=entry,item=item,index=index} end
    end
    if #watched==0 then return end
    table.sort(watched,function(a,b) return a.index<b.index end)
    local top=watched[1]
    if c.scanStage and ns.Stage and ns.Stage.types.gatherfind then
        local title=top.entry.name..(#watched>1 and (" +"..(#watched-1)) or "")
        pcall(ns.Stage.Show,ns.Stage,"gatherfind",{title=title,subtitle=string.format("On the minimap · %d yd %s",top.entry.yards,top.entry.direction),
            color=top.entry.kind and G:Color(top.entry.kind),key="find"})
    end
    local now=GetTime()
    if now-(self.played[top.item.name] or -math.huge)>=self.QUIET then
        if self:Play(top.item) then self.played[top.item.name]=now end
    end
end
-- You gathered it: counts as seen now (no warning until it was gone long enough).
function S:Gathered(name,mapID,x,y)
    local entry=self:Match(name,mapID,x,y)
    if entry then entry.last=GetTime() end
    if entry and entry==self.target then self:Target(nil) end
end
function S:Clear() self.recent={};self:Target(nil);if G.Finds then G.Finds:Refresh() end end

-- Distance and direction from where you stand now (Florian 2026-10-10: the
-- finds window follows you); the values at the find without a position.
function S:Relative(find)
    local node=find.node
    local mapID,px,py=G.Record:Position()
    if node and node.x and mapID and node.mapID==mapID then
        local w,h=G.Call("C_Map.GetMapWorldSize",mapID)
        if type(w)=="number" and w>0 and type(h)=="number" and h>0 then
            local north,east=(py-node.y)*h,(node.x-px)*w
            return math.floor(math.sqrt(north*north+east*east)+.5),S.Direction(north,east)
        end
    end
    return find.yards,find.direction
end

-- The find you go to (a click in the finds window): a purple ring with a
-- line from you to it on the minimap and the map, like the route's next
-- point. Ends when you get there, gather it, or click it again.
function S:Target(find)
    local node=find and find.node
    if node and not node.x then G:Print("No position for "..find.name.." (inside an instance).");return end
    if node and self.target==node then node=nil end
    if node then node.misses=0 end
    self.target=node
    if node and not self.targetTicker then
        self.targetTicker=C_Timer.NewTicker(1,function() S:Arrived() end)
    elseif not node and self.targetTicker then self.targetTicker:Cancel();self.targetTicker=nil end
    self:RegisterTarget()
    if ns.MapPins then ns.MapPins:Refresh() end
    if G.Finds then G.Finds:Refresh() end
end
-- Yards from you to the target, on your map (the target moved onto it when
-- you are on another one: a town or cave map); nil when unknown.
function S:Distance(node)
    local mapID,px,py=G.Record:Position()
    if not mapID then return nil end
    local x,y=node.x,node.y
    if node.mapID~=mapID then
        if not ns.MapPins then return nil end
        x,y=ns.MapPins:OnMap(node,mapID)
        if not x then return nil end
    end
    return G.Data.Yards(mapID,px,py,x,y)
end
-- Reached, or walked far away (Florian 2026-10-10: twice the view radius).
function S:Arrived()
    local node=self.target
    if not node then return end
    local d=self:Distance(node)
    if not d then return end
    if d<=self.ARRIVE then self:Target(nil)
    elseif d>self.FAR*(node.view or 233) then
        G:Print(node.name.." left behind: the line to it ends.")
        self:Target(nil)
    end
end
-- The scanner looks at the target's place: in view (with a margin for the
-- read's error) and its tracking on, but not seen in GONE scans in a row,
-- someone else took it.
function S:Missing(now)
    local node=self.target
    if not node then return end
    if node.last==now then node.misses=0;return end
    local d=self:Distance(node)
    if not d or d>.8*(node.view or 233) or (node.kind and self:Hint(node.kind)) then return end
    node.misses=(node.misses or 0)+1
    if node.misses>=self.GONE then
        G:Print(node.name.." is gone: the line to it ends.")
        node.misses=0
        self:Target(nil)
    end
end
function S:TargetPoints()
    local node=self.target
    if not (node and G:Active()) then return {} end
    local color=self.TARGET_COLOR
    return {{mapID=node.mapID,x=node.x,y=node.y,key="scan:"..node.name,dot=true,size=14,hollow=true,color=color,alpha=1,
        lead=true,leadColor=color,lineAlpha=1}}
end
function S:RegisterTarget()
    if self.registered or not ns.MapPins then return end
    self.registered=true
    ns.MapPins:Register("gather:scantarget",{points=function() return S:TargetPoints() end,minimap=true,arrows=true,
        tooltip=function() local node=S.target;return node and node.name,{tag="Minimap find",hint="Click it again in Minimap finds to clear the line."} end})
end
-- "needs Find Herbs": a kind whose tracking is off shows no dots.
function S:Hint(kind)
    if not (G.Visibility and G.Visibility.Tracking) then return nil end
    if G.Visibility:Tracking(kind) then return nil end
    return kind=="ore" and "needs Find Minerals" or "needs Find Herbs"
end

if ns.Stage then
    ns.Stage:Register({id="gatherfind",label="Gather: minimap find",priority=3,hold=4,
        description="A herb or ore of the scanner's list showed on the minimap (Gather, Scanner tab). Shown while the Gather module is on.",
        sample={title="Black Lotus",subtitle="On the minimap · 140 yd NE"}})
end
function S:Enable(context)
    context:Defer(function()
        if S.ticker then S.ticker:Cancel();S.ticker=nil end
        if S.targetTicker then S.targetTicker:Cancel();S.targetTicker=nil end
        S.target=nil
        S:Disarm();S.status="off"
    end)
    self:RegisterTarget()
    self:Update()
end
