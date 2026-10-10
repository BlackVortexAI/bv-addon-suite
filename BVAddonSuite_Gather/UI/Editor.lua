local _,G=...
if not G.ready then return end
-- Route editor (plan phase 5b, Florian 2026-10-08: its own map window, much
-- lighter than the usual route addons). The map draws the chosen zones
-- itself from the client's map tiles (a plain board where the client gives
-- none); wheel zooms around the cursor, dragging (or the right button)
-- moves. The side bar picks zones of one continent and the herbs and ores
-- to visit, loop, pass-by radius and how high-risk areas count. Brushes
-- paint no-go, preferred and high-risk areas, the eraser takes strokes
-- away, Undo the last one. Calculate plans the route (G.Plan) in slices;
-- its points can be moved (drag), added (click on the map) and removed
-- (right-click). Routes are saved by name, become the Map package's
-- waypoints (a loop starts over) and go out as text.
local ns=G.ns
local UI,M=ns.UI,ns.DesignSystem.Metrics
local Grid=G.Grid
local E={tool="move",brush=25,zoom=1,ox=0,oy=0,zones={},chosen={},history={},pools={}}
G.Editor=E
local DISC="Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local WHITE="Interface\\Buttons\\WHITE8X8"
local SIDE,ROWS,ROW,MAXROWS=300,8,22,20
local MAXZONES=4
E.AREA={nogo={.95,.2,.2,.38},prefer={.3,.9,.45,.32},risk={1,.55,.1,.38}}
E.TOOLS={
    {id="move",icon="hand",title="Move the map",text="Drag to move, wheel to zoom. The right button moves with every tool."},
    {id="nogo",icon="ban",title="No-go",text="Paint where the route must never go."},
    {id="prefer",icon="thumbs-up",title="Preferred",text="Paint roads and safe ground the route should rather take."},
    {id="risk",icon="skull",title="High risk",text="Paint elite camps and the like; the setting below says how the route treats them."},
    {id="erase",icon="eraser",title="Eraser",text="Takes painted strokes away."},
    {id="edit",icon="route",title="Edit the route",text="Drag a point to move it, click on the map to add one to the nearest leg, right-click a point to remove it."},
    {id="link",icon="arrow-right-left",title="Transition",text="A bridge, tunnel or cave entrance: click its start, then its end (Shift on the end: one way only). Right-click an end to remove it."},
}

-- Pools of textures, lines and point buttons on the board.
local function pool(name,make)
    local p=E.pools[name]
    if not p then p={items={},used=0,make=make};E.pools[name]=p end
    return p
end
local function take(p)
    p.used=p.used+1
    local item=p.items[p.used]
    if not item then item=p.make();p.items[p.used]=item end
    item:Show()
    return item
end
local function reset(p) for i=1,#p.items do p.items[i]:Hide() end;p.used=0 end

-- Board geometry: space point (0..1 on the space map) <-> board pixels.
function E:Size() return self.board:GetWidth(),self.board:GetHeight() end
function E:ToBoard(x,y)
    local s=self.space
    local w,h=self:Size()
    return (x-s.minX)/(s.maxX-s.minX)*w,(y-s.minY)/(s.maxY-s.minY)*h
end
function E:PixelsPerYard()
    local s=self.space
    return self.board:GetWidth()/((s.maxX-s.minX)*s.width)
end
-- The cursor in view pixels (from the view's top left) and as a space point.
function E:Cursor()
    local x,y=GetCursorPosition()
    local scale=self.view:GetEffectiveScale()
    local left,top=self.view:GetLeft(),self.view:GetTop()
    if not (left and top) then return nil end
    return x/scale-left,top-y/scale
end
function E:CursorSpace(clamp)
    local cx,cy=self:Cursor()
    if not cx then return nil end
    local w,h=self:Size()
    local fx,fy=(cx-self.ox)/w,(cy-self.oy)/h
    if clamp then fx,fy=math.max(0,math.min(1,fx)),math.max(0,math.min(1,fy)) end
    if fx<0 or fx>1 or fy<0 or fy>1 then return nil end
    local s=self.space
    return s.minX+fx*(s.maxX-s.minX),s.minY+fy*(s.maxY-s.minY)
end

-- Window ---------------------------------------------------------------------------
-- Map on the left with the result bar under it; the side bar keeps zones
-- and the node list at the top (the list takes the height that is left)
-- and the route options, tools and Calculate at the bottom (Florian
-- 2026-10-08: nothing may stand out of the window).
local BAR=44
function E:Build()
    if self.window then return self.window end
    UI:WithStyle(G:Style(),function()
        local w=UI:Window("BVGatherRouteEditor",1180,780,{title="Route editor",minWidth=1060,minHeight=700})
        self.window=w
        local c=w.content
        local view=CreateFrame("Frame",nil,c)
        M.Point(view,"TOPLEFT",c,"TOPLEFT",10,-6);M.Point(view,"BOTTOMRIGHT",c,"BOTTOMRIGHT",-SIDE-26,10+BAR)
        view:SetClipsChildren(true);view:EnableMouse(true);view:EnableMouseWheel(true)
        view.bg=view:CreateTexture(nil,"BACKGROUND");view.bg:SetAllPoints(view);view.bg:SetColorTexture(.05,.05,.07,1)
        view:SetScript("OnMouseWheel",function(_,delta) E:Zoom(delta) end)
        view:SetScript("OnMouseDown",function(_,button) E:Down(button) end)
        view:SetScript("OnMouseUp",function(_,button) E:Up(button) end)
        self.view=view
        self.board=CreateFrame("Frame",nil,view)
        -- While the search area is drawn, a layer over the map takes every
        -- click (Florian 2026-10-09: clicks on points, flight masters or
        -- transitions went to them and the map did not react).
        local catcher=CreateFrame("Frame",nil,view);catcher:SetAllPoints(view);catcher:SetFrameLevel(view:GetFrameLevel()+60)
        catcher:EnableMouse(true);catcher:EnableMouseWheel(true)
        catcher:SetScript("OnMouseWheel",function(_,delta) E:Zoom(delta) end)
        catcher:SetScript("OnMouseDown",function(_,button) E:Down(button) end)
        catcher:SetScript("OnMouseUp",function(_,button) E:Up(button) end)
        -- While drawing (Florian 2026-10-09: not clear whether the mode is on):
        -- an accent frame round the map, a banner at the top and the map a
        -- little darker under the nodes and the area's lines.
        local ar,ag,ab=G:Style():Color("accent")
        catcher.edges={}
        for i,side in ipairs({{"TOPLEFT","TOPRIGHT",nil,2},{"BOTTOMLEFT","BOTTOMRIGHT",nil,2},{"TOPLEFT","BOTTOMLEFT",2,nil},{"TOPRIGHT","BOTTOMRIGHT",2,nil}}) do
            local e=catcher:CreateTexture(nil,"OVERLAY");e:SetColorTexture(ar,ag,ab,.9)
            e:SetPoint(side[1]);e:SetPoint(side[2])
            if side[3] then e:SetWidth(side[3]) else e:SetHeight(side[4]) end
            catcher.edges[i]=e
        end
        local banner=CreateFrame("Frame",nil,catcher);banner:SetPoint("TOP",catcher,"TOP",0,-8);banner:SetSize(560,26)
        banner.bg=banner:CreateTexture(nil,"BACKGROUND");banner.bg:SetAllPoints(banner);banner.bg:SetColorTexture(.05,.05,.07,.85)
        banner.line=banner:CreateTexture(nil,"BORDER");banner.line:SetPoint("BOTTOMLEFT");banner.line:SetPoint("BOTTOMRIGHT");banner.line:SetHeight(2);banner.line:SetColorTexture(ar,ag,ab,1)
        banner.text=UI:Label(banner,"",12,"text",true);banner.text:SetPoint("CENTER",banner,"CENTER",0,1)
        catcher.banner=banner
        self.dim=self.board:CreateTexture(nil,"ARTWORK",nil,-8);self.dim:SetAllPoints(view);self.dim:SetColorTexture(0,0,0,.35);self.dim:Hide()
        catcher:Hide()
        self.catcher=catcher
        w:HookScript("OnHide",function() E:AreaMode(false) end)
        -- A leg without a way (Florian 2026-10-09): a warning over the map
        -- until the route is calculated again.
        local warning=CreateFrame("Frame",nil,view);warning:SetPoint("TOP",view,"TOP",0,-8);warning:SetSize(600,26)
        warning:SetFrameLevel(view:GetFrameLevel()+50)
        warning.bg=warning:CreateTexture(nil,"BACKGROUND");warning.bg:SetAllPoints(warning);warning.bg:SetColorTexture(.05,.05,.07,.88)
        local gr,gg,gb=unpack(G.Follow.GAP)
        warning.line=warning:CreateTexture(nil,"BORDER");warning.line:SetPoint("BOTTOMLEFT");warning.line:SetPoint("BOTTOMRIGHT");warning.line:SetHeight(2);warning.line:SetColorTexture(gr,gg,gb,1)
        warning.text=UI:Label(warning,"",12,"text",true);warning.text:SetPoint("CENTER",warning,"CENTER",0,1)
        warning:Hide()
        self.warning=warning
        self.hint=UI:Label(view,"",11,"muted");M.Point(self.hint,"BOTTOMLEFT",view,"BOTTOMLEFT",8,6);M.Size(self.hint,520,16)
        self:BuildBar(c)
        self:BuildSide(c)
        w:HookScript("OnSizeChanged",function() if w:IsShown() then E:ArrangeSide();E:Fit(true) end end)
        w:Hide()
    end)
    return self.window
end
-- Under the map: name, save, saved routes, delete, export, import, use.
function E:BuildBar(c)
    local x=10
    local function add(widget,width)
        M.Point(widget,"BOTTOMLEFT",c,"BOTTOMLEFT",x,10);x=x+width+6
        return widget
    end
    self.name=add(UI:Input(c,130,function() E:Save() end),130)
    UI:AttachTooltip(self.name,"Route name","Type a name, then Save.")
    self.save=add(UI:Button(c,"Save",64,function() E:Save() end),64)
    self.saved=add(UI:Dropdown(c,160,{},function(value) E:Load(value) end),160)
    self.saved:SetOptionsProvider(function() return E:SavedOptions() end)
    self.saved:SetLabelText("Saved routes...")
    self.delete=add(UI:Button(c,"Delete",64,function() E:Delete() end,"ghost"),64)
    self.export=add(UI:Button(c,"Export",64,function() E:Export() end,"ghost"),64)
    self.import=add(UI:Button(c,"Import",64,function() G.Exchange:Open("routeImport") end,"ghost"),64)
    self.follow=UI:Button(c,"Follow route",130,function() E:Follow() end,true)
    UI:AttachTooltip(self.follow,"Follow route","Shows the route on your map and minimap with small points and arrows; you join at the nearest leg. Your waypoints stay as they are.")
    M.Point(self.follow,"BOTTOMRIGHT",c,"BOTTOMRIGHT",-SIDE-26,10)
end
function E:BuildSide(c)
    local side=CreateFrame("Frame",nil,c)
    M.Point(side,"TOPRIGHT",c,"TOPRIGHT",-12,-6);M.Point(side,"BOTTOMRIGHT",c,"BOTTOMRIGHT",-12,10);M.Width(side,SIDE)
    self.side=side
    -- Top part (placed by ArrangeSide).
    self.zoneHeading=UI:Label(side,"Zones",12,"accent",true)
    self.zoneRows={}
    for i=1,MAXZONES do
        local row=CreateFrame("Frame",nil,side);M.Size(row,SIDE,ROW)
        row.name=UI:Label(row,"",12,"text");M.Point(row.name,"LEFT",row,"LEFT",0,0);M.Size(row.name,SIDE-40,ROW);row.name:SetWordWrap(false)
        row.remove=UI:IconButton(row,"close",function() E:RemoveZone(i) end,"ghost");M.Point(row.remove,"RIGHT",row,"RIGHT",0,0);M.Size(row.remove,ROW,ROW)
        self.zoneRows[i]=row
    end
    self.addZone=UI:Dropdown(side,SIDE,{},function(value) E:AddZone(value) end)
    self.addZone:SetOptionsProvider(function() return E:ZoneOptions() end)
    self.nameHeading=UI:Label(side,"Herbs and ore",12,"accent",true)
    self.nameRows={};self.nameOffset=0;self.rows=ROWS
    self.list=CreateFrame("Frame",nil,side);M.Width(self.list,SIDE)
    self.list:EnableMouseWheel(true);self.list:SetScript("OnMouseWheel",function(_,delta) E:ScrollNames(-delta) end)
    for i=1,MAXROWS do
        local row=CreateFrame("Frame",nil,self.list);M.Size(row,SIDE,ROW);M.Point(row,"TOPLEFT",self.list,"TOPLEFT",0,-(i-1)*ROW)
        row.switch=UI:Switch(row,false,function(value) E:Choose(row.key,value) end);M.Point(row.switch,"LEFT",row,"LEFT",0,0)
        row.name=UI:Label(row,"",12,"text");M.Point(row.name,"LEFT",row,"LEFT",44,0);M.Size(row.name,SIDE-96,ROW);row.name:SetWordWrap(false)
        row.count=UI:Label(row,"",11,"muted");M.Point(row.count,"RIGHT",row,"RIGHT",-4,0);M.Size(row.count,48,ROW);row.count:SetJustifyH("RIGHT")
        self.nameRows[i]=row
    end
    self.all=UI:Button(side,"All",64,function() E:ChooseAll(true) end,"ghost")
    self.none=UI:Button(side,"None",64,function() E:ChooseAll(false) end,"ghost");M.Point(self.none,"LEFT",self.all,"RIGHT",6,0)
    self.areaButton=UI:Button(side,"Area",76,function() E:AreaButton() end,"ghost");M.Point(self.areaButton,"LEFT",self.none,"RIGHT",6,0)
    UI:AttachTooltip(self.areaButton,"Search area","Only nodes inside it join the route (not a no-go area): click Area, click the corners on the map, then Finish. Click again to clear it.")
    self.more=UI:Label(side,"",11,"muted");M.Point(self.more,"LEFT",self.areaButton,"RIGHT",8,0);M.Size(self.more,84,20)
    -- Bottom part, from the bottom up.
    local y=0
    self.status=UI:Label(side,"",11,"muted");M.Point(self.status,"BOTTOMLEFT",side,"BOTTOMLEFT",0,y);M.Size(self.status,SIDE,40);self.status:SetWordWrap(true)
    self.status:SetJustifyV("TOP")
    -- While calculating: a bar over the status line, filling up.
    self.progress=UI:StatusBar(side,SIDE,4);M.Point(self.progress,"BOTTOMLEFT",side,"BOTTOMLEFT",0,y+40);self.progress:SetValue(0);self.progress:Hide()
    y=y+44
    -- While it runs the button cancels it (Florian 2026-10-10).
    self.calculate=UI:Button(side,"Calculate",SIDE,function() if E.job then E:Cancel() else E:Calculate() end end,true);M.Point(self.calculate,"BOTTOMLEFT",side,"BOTTOMLEFT",0,y);y=y+40
    UI:AttachTooltip(self.calculate,"Calculate the route","Plans the route through the chosen nodes. While it runs, the button cancels it; the route you had stays. Warning: the game's performance drops noticeably for a moment at the start, while the terrain is read; after that it runs smoothly in the background.")
    -- Florian 2026-10-09: warn before the first click, the start lags.
    self.lagNote=UI:Label(side,"Warning: performance drops for a moment when calculating starts.",10,"muted");M.Point(self.lagNote,"BOTTOMLEFT",side,"BOTTOMLEFT",0,y-2);M.Size(self.lagNote,SIDE,14)
    self.lagNote:SetTextColor(1,.78,.2);y=y+14
    local function option(title,control,height)
        local l=UI:Label(side,title,12,"text");M.Point(l,"BOTTOMLEFT",side,"BOTTOMLEFT",0,y+4);M.Size(l,110,20)
        self.lastLabel=l
        M.Point(control,"BOTTOMLEFT",side,"BOTTOMLEFT",116,y);y=y+(height or 30)
        return control
    end
    self.brushSize=option("Brush",UI:InlineSlider(side,180,10,120,5,"%d yd",function(value) E.brush=value end))
    self.toolButtons={}
    for i,tool in ipairs(self.TOOLS) do
        local b=UI:IconButton(side,tool.icon,function() E:Tool(tool.id) end,"ghost");M.Size(b,30,30);M.Point(b,"BOTTOMLEFT",side,"BOTTOMLEFT",(i-1)*33,y)
        b.mark=b:CreateTexture(nil,"OVERLAY");M.Point(b.mark,"BOTTOMLEFT",b,"BOTTOMLEFT",4,0);M.Point(b.mark,"BOTTOMRIGHT",b,"BOTTOMRIGHT",-4,0);M.Height(b.mark,2)
        b.mark:SetColorTexture(G:Style():Color("accent"))
        UI:AttachTooltip(b,tool.title,tool.text)
        self.toolButtons[tool.id]=b
    end
    self.terrainButton=UI:IconButton(side,"layers",function(button) E:LayerMenu(button or E.terrainButton) end,"ghost");M.Size(self.terrainButton,30,30);M.Point(self.terrainButton,"BOTTOMLEFT",side,"BOTTOMLEFT",#self.TOOLS*33,y)
    UI:AttachTooltip(self.terrainButton,"Map layers","Terrain (the game's own minimap tiles) or Blizzard's map; zone and area names and flight masters.")
    self.undo=UI:IconButton(side,"undo-2",function() E:Undo() end,"ghost");M.Point(self.undo,"BOTTOMRIGHT",side,"BOTTOMRIGHT",0,y)
    UI:AttachTooltip(self.undo,"Undo","Takes back the last painted or erased stroke.")
    y=y+36
    local paint=UI:Label(side,"Paint and edit",12,"accent",true);M.Point(paint,"BOTTOMLEFT",side,"BOTTOMLEFT",0,y);y=y+24
    self.risk=option("High risk",UI:Dropdown(side,180,{{value="ignore",label="Ignore"},{value="avoid",label="Avoid where possible"},{value="block",label="Treat as no-go"}},
        function(value) G:Config().risk=value;E:Stale() end),38)
    self.worth=option("Way per node",UI:InlineSlider(side,180,0,600,10,"%d yd",function(value) G:Config().worthLimit=value;E:Stale() end))
    UI:AttachTooltip(self.worth,"Worth the way","Nodes that cost more way than this each are left out: a far group with few nodes is not worth the walk. Counted for groups of neighbouring stops together. 0: every node.")
    self.goal=option("Goal",UI:Dropdown(side,180,{{value="visit",label="Every node"},{value="sight",label="Within sight"}},
        function(value) G:Config().routeGoal=value;E:Stale();E:RefreshSide() end),38)
    UI:AttachTooltip(self.goal,"Route goal","Every node: the route leads to each. Within sight: only so close that each lies within the minimap's sight (its Find Herbs dots); you walk over to what you see.")
    self.radius=option("Pass-by radius",UI:InlineSlider(side,180,10,80,5,"%d yd",function(value) G:Config().passRadius=value;E:Stale() end))
    self.radiusLabel=self.lastLabel
    UI:AttachTooltip(self.radius,"Pass-by radius","Nodes closer together than this become one stop: you see and reach them from there.")
    -- The same row is the sight radius when the goal is "within sight".
    self.sight=UI:InlineSlider(side,180,40,230,5,"%d yd",function(value) G:Config().sightRadius=value;E:Stale() end)
    M.Point(self.sight,"BOTTOMLEFT",self.radius,"BOTTOMLEFT",0,0);self.sight:Hide()
    UI:AttachTooltip(self.sight,"Sight radius","Each node comes within this distance of a stop (the minimap shows about 230 yards zoomed out, 150 indoors).")
    self.loop=option("Loop",UI:Switch(side,true,function(value) G:Config().loop=value;E:Stale() end))
    UI:AttachTooltip(self.loop,"Loop","The route ends where it started and starts over; off: one way from the first point to the last.")
    local route=UI:Label(side,"Route",12,"accent",true);M.Point(route,"BOTTOMLEFT",side,"BOTTOMLEFT",0,y)
    -- Wiki and expert settings beside the heading (Florian 2026-10-09: in
    -- the bar under the map they ran into "Follow route").
    self.expert=UI:IconButton(side,"sliders-horizontal",function() G.Expert:Open() end,"ghost");M.Size(self.expert,26,26)
    M.Point(self.expert,"BOTTOMRIGHT",side,"BOTTOMRIGHT",0,y-4)
    UI:AttachTooltip(self.expert,"Expert settings","The fixed values behind route planning: levels, jumps, costs of slopes, water and roads. Apply to the next Calculate.")
    self.wiki=UI:IconButton(side,"book-open",function() G.Wiki:Open("page:editor") end,"ghost");M.Size(self.wiki,26,26)
    M.Point(self.wiki,"RIGHT",self.expert,"LEFT",-4,0)
    UI:AttachTooltip(self.wiki,"Wiki","How the route editor and its settings work, with examples.")
    y=y+24
    self.bottomHeight=y
    self:ArrangeSide()
end
-- The top part follows the number of zones; the node list gets the rows
-- that fit between it and the bottom part.
function E:ArrangeSide()
    local side=self.side
    if not side then return end
    local function place(widget,x,y) widget:ClearAllPoints();M.Point(widget,"TOPLEFT",side,"TOPLEFT",x,y) end
    local y=0
    place(self.zoneHeading,0,y);y=y-22
    for i,row in ipairs(self.zoneRows) do
        if self.zones[i] then place(row,0,y);y=y-ROW end
    end
    place(self.addZone,0,y-2);y=y-42
    place(self.nameHeading,0,y);y=y-22
    place(self.list,0,y)
    local height=M.GetHeight(side)
    local free=(height>0 and height or 700)-self.bottomHeight-(-y)-44
    self.rows=math.max(3,math.min(MAXROWS,math.floor(free/ROW)))
    M.Height(self.list,self.rows*ROW)
    y=y-self.rows*ROW-4
    place(self.all,0,y)
    for i,row in ipairs(self.nameRows) do if i>self.rows then row:Hide() end end
end

function E:LayerMenu(anchor)
    local c=G:Config()
    UI:ContextMenu(anchor,{
        {value="terrain",label=(c.editorTerrain and "Hide" or "Show").." terrain"},
        {value="names",label=(c.editorNames and "Hide" or "Show").." names and flight masters"},
        {value="relief",label=(c.editorRelief and "Hide" or "Show").." slopes, water, roads and entrances"},
        {value="heat",label=(c.editorHeat and "Hide" or "Show").." walked ways"},
        {value="waypoints",label="Send the route to the Map waypoints"},
        {value="areasExport",label="Export areas and transitions"},
        {value="areasImport",label="Import areas and transitions"},
    },function(value)
        if value=="terrain" then E:ToggleTerrain()
        elseif value=="relief" then c.editorRelief=not c.editorRelief;E:DrawRelief()
        elseif value=="heat" then c.editorHeat=not c.editorHeat;E:DrawRelief()
        elseif value=="waypoints" then if E.route then G.Plan:Follow(E.current or "Route",E.route) end
        elseif value=="areasExport" then G.Exchange:Open("areasExport",nil,(G.Plan:ExportAreas(E.zones)))
        elseif value=="areasImport" then G.Exchange:Open("areasImport")
        else E:ToggleNames() end
    end)
end
function E:ToggleNames()
    local c=G:Config()
    c.editorNames=not c.editorNames
    self:DrawPlaces()
end
function E:ToggleTerrain()
    local c=G:Config()
    c.editorTerrain=not c.editorTerrain
    self:Layout();self:RefreshSide()
end
function E:Toggle()
    local w=self:Build()
    if w:IsShown() then w:Hide() else self:Open() end
end
-- Opens with the given zones, else the ones of last time, else where you are.
function E:Open(zones)
    local w=self:Build()
    if zones then self.zones={} for i,zone in ipairs(zones) do self.zones[i]=zone end end
    if #self.zones==0 then
        local mapID=G.Record:Position()
        if not mapID then
            local map=rawget(_G,"WorldMapFrame")
            if map and map.GetMapID then mapID=map:GetMapID() end
        end
        if mapID then self.zones={mapID} end
    end
    w:Show()
    local c=G:Config()
    self.loop:SetValue(c.loop);self.radius:SetValue(c.passRadius);self.risk:SetValue(c.risk);self.brushSize:SetValue(self.brush)
    self.goal:SetValue(c.routeGoal);self.sight:SetValue(c.sightRadius);self.worth:SetValue(c.worthLimit)
    self:SetZones(self.zones)
    self:Tool(self.tool)
    return w
end
function E:ZoneName(mapID)
    local info=G.Call("C_Map.GetMapInfo",mapID)
    return type(info)=="table" and info.name or ("Map "..tostring(mapID))
end
-- Zones that can join: those of the continent of the first zone (or any
-- zone with nodes when none is chosen yet). Zones of another continent
-- follow, named with their continent: choosing one starts over there
-- (Florian 2026-10-10: after loading a Kalimdor route the editor kept to
-- Kalimdor while he stood in the Eastern Kingdoms).
function E:ZoneOptions()
    local pins=ns.MapPins
    local seen,out,other={},{},{}
    local function add(mapID)
        if type(mapID)~="number" or seen[mapID] then return end
        seen[mapID]=true
        for _,zone in ipairs(self.zones) do if zone==mapID then return end end
        if #self.zones>0 and not self:SameContinent(mapID) then
            local continent=pins and pins:Continent(mapID)
            if continent then other[#other+1]={value=mapID,label=self:ZoneName(mapID).." ("..self:ZoneName(continent)..")"} end
            return
        end
        if #self.zones<MAXZONES then out[#out+1]={value=mapID,label=self:ZoneName(mapID)} end
    end
    local function zonesOf(continent)
        local children=continent and G.Call("C_Map.GetMapChildrenInfo",continent,3,true)
        if type(children)=="table" then for _,child in ipairs(children) do if type(child)=="table" then add(child.mapID) end end end
    end
    zonesOf(self.zones[1] and pins and pins:Continent(self.zones[1]))
    for _,t in ipairs(G.TYPES) do for mapID in pairs(G.Data:Maps(t.id)) do add(mapID) end end
    -- Where you are, and the other zones of your continent.
    local here=G.Record:Position()
    add(here)
    zonesOf(here and pins and pins:Continent(here))
    local function byLabel(a,b) return a.label<b.label end
    table.sort(out,byLabel);table.sort(other,byLabel)
    for _,option in ipairs(other) do out[#out+1]=option end
    if #out==0 then out[1]={value=0,label="No other zone of this continent"} end
    return out
end
function E:SameContinent(mapID)
    local pins=ns.MapPins
    local continent=pins and pins:Continent(self.zones[1])
    return continent~=nil and pins:Continent(mapID)==continent
end
function E:AddZone(mapID)
    if type(mapID)~="number" or mapID==0 then return end
    for _,zone in ipairs(self.zones) do if zone==mapID then return end end
    -- Zones of one route lie on one continent: another one starts over
    -- there, without the loaded route (Delete would still name it).
    if #self.zones>0 and not self:SameContinent(mapID) then
        self.current=nil;self.saved:SetLabelText("Saved routes...")
        self:SetZones({mapID})
        return
    end
    if #self.zones>=MAXZONES then return end
    local zones={unpack(self.zones)};zones[#zones+1]=mapID
    self:SetZones(zones)
end
function E:RemoveZone(index)
    if #self.zones<=1 then return end
    local zones={unpack(self.zones)};table.remove(zones,index)
    self:SetZones(zones)
end
-- New zones: a new space, its node names, the view fitted.
function E:SetZones(zones)
    self.zones=zones;self.placed=nil
    if #zones==0 then return end
    self.space=Grid.Space(zones)
    self.namesKey=nil;self:Names()
    -- New names start chosen when nothing of them was chosen before.
    local any=false
    for _,entry in ipairs(self.names) do if self.chosen[entry.key] then any=true end end
    if not any then for _,entry in ipairs(self.names) do self.chosen[entry.key]=true end end
    self.nameOffset=0
    self.nodes={}
    for _,t in ipairs(G.TYPES) do
        for _,zone in ipairs(zones) do
            for _,node in ipairs(G.Data:Nodes(t.id,zone) or {}) do
                local x,y=Grid.ToSpace(self.space,zone,node.x,node.y)
                if x then self.nodes[#self.nodes+1]={x=x,y=y,kind=t.id,key=G.Plan.Key(t.id,node.name or ("Unknown "..t.label:lower())),under=node.under,zone=zone,raw=node} end
            end
        end
    end
    if self.route and not self:RouteFits(self.route) then self.route=nil end
    self:RefreshSide()
    self:Fit(false)
end
function E:RouteFits(route)
    local set={};for _,zone in ipairs(self.zones) do set[zone]=true end
    for _,point in ipairs(route.points) do if not set[point.mapID] then return false end end
    return true
end

-- Side bar.
function E:RefreshSide()
    self:ArrangeSide()
    for i,row in ipairs(self.zoneRows) do
        local zone=self.zones[i]
        row:SetShown(zone~=nil)
        if zone then row.name:SetText(self:ZoneName(zone));row.remove:SetShown(#self.zones>1) end
    end
    self.addZone:SetLabelText(#self.zones<MAXZONES and "Add a zone..." or "Four zones at most")
    local names=self.names or {}
    local rows=self.rows or ROWS
    self.nameOffset=math.max(0,math.min(self.nameOffset,#names-rows))
    for i,row in ipairs(self.nameRows) do
        local entry=i<=rows and names[i+self.nameOffset]
        row:SetShown(entry and true or false)
        if entry then
            row.key=entry.key
            row.switch:SetValue(self.chosen[entry.key]==true)
            row.name:SetText(G.WithSkill(entry.name));row.name:SetTextColor(unpack(G:Color(entry.kind)))
            row.count:SetText(tostring(entry.count))
        end
    end
    self.more:SetText(#names>rows and string.format("%d-%d of %d",self.nameOffset+1,math.min(#names,self.nameOffset+rows),#names) or (#names==0 and "No nodes known here" or ""))
    for id,b in pairs(self.toolButtons) do b.mark:SetShown(id==self.tool) end
    self.areaButton:SetText(self.areaDraw and (#self.areaDraw>=3 and "Finish" or "Cancel") or (self.area and "Clear area" or "Area"))
    local sight=G:Config().routeGoal=="sight"
    self.radius:SetShown(not sight);self.sight:SetShown(sight)
    if self.radiusLabel then self.radiusLabel:SetText(sight and "Sight radius" or "Pass-by radius") end
    if self.space then self:Names() end
    if self.terrainButton.icon then self.terrainButton.icon:SetAlpha(G:Config().editorTerrain and self:TerrainArt() and 1 or .5) end
    self:Status()
end
-- The node names of the zones (inside the search area), worked out again
-- only when zones, area, data or the route settings changed.
function E:Names()
    local c=G:Config()
    local key=table.concat(self.zones,",")..":"..tostring(self.area)..":"..tostring(G.Data.revision)..":"..tostring(c.routeKnown)..":"..tostring(c.routeUnderground)
    if key==self.namesKey and self.names then return self.names end
    self.namesKey=key
    self.names=G.Plan:Names(self.zones,self.area)
    self.inside=nil
    return self.names
end
function E:ScrollNames(delta)
    self.nameOffset=self.nameOffset+delta*2
    self:RefreshSide()
end
function E:Choose(key,value)
    if key then self.chosen[key]=value and true or nil end
    self:Chosen(key)
end
function E:ChooseAll(value)
    for _,entry in ipairs(self.names or {}) do self.chosen[entry.key]=value or nil end
    self:RefreshSide();self:Chosen()
end
-- After a choice: only the dots of that name (or all) change their
-- brightness, nothing moves; the route is drawn again only when it just
-- turned stale.
function E:Chosen(key)
    local fresh=self.route and not self.route.stale
    self:Stale()
    if not (self.window and self.window:IsShown() and self.space and self.base) then return end
    for dotKey,list in pairs(self.dotsByKey or {}) do
        if not key or dotKey==key then
            for _,t in ipairs(list) do self:DotColor(t) end
        end
    end
    if fresh then self:DrawRoute() end
end
function E:DotColor(t)
    local c=G:Color(t.kind)
    t:SetVertexColor(c[1],c[2],c[3],(self.chosen[t.key] and t.inside) and 1 or .25)
end
function E:Tool(id)
    self.tool=id
    if self.toolButtons then for tool,b in pairs(self.toolButtons) do b.mark:SetShown(tool==id) end end
    local hint=({move="Drag to move, wheel to zoom.",nogo="Paint no-go areas.",prefer="Paint preferred ground.",risk="Paint high-risk areas.",
        erase="Drag over strokes to take them away.",edit="Drag points, click to add, right-click to remove.",
        link="Click a transition's start, then its end (Shift: one way)."})[id]
    self.linkStart=nil;self.corners=nil
    if self.hint then self.hint:SetText(hint.."  Right button: move the map.") end
    self:Layout()
end
-- Painted areas or choices changed after the route was calculated.
function E:Stale()
    if self.route then self.route.stale=true end
    self:Status()
end
function E:Status()
    if not self.status then return end
    local r=self.route
    if self.job then
        local p=G.Plan.progress
        self.status:SetText(string.format("Calculating... %d %%  ·  %s",math.floor(p.value*100+.5),p.text or ""))
        if self.progress then self.progress:Show();self.progress:SetValue(p.value) end
        if self.calculate then self.calculate:SetText("Cancel") end
        self:Warn(nil)
        return
    end
    if self.progress then self.progress:Hide() end
    if self.calculate then self.calculate:SetText("Calculate") end
    if not r then self.status:SetText("Choose zones and nodes, paint areas if you like, then Calculate.");self:Warn(nil);return end
    local stops=0;for _,point in ipairs(r.points) do if point.stop then stops=stops+1 end end
    local length=r.length or 0
    local text=string.format("%d stops, %d yards%s%s: about %d min on foot, %d mounted.",stops,math.floor(length+.5),r.loop and " (loop)" or "",
        r.goal=="sight" and ", within sight" or "",
        G.Plan.Minutes(length,G.Plan.FOOT),G.Plan.Minutes(length,G.Plan.MOUNT))
    local notes={}
    if (r.skipped or 0)>0 then notes[#notes+1]=r.skipped.." nodes in no-go areas left out" end
    if (r.enemy or 0)>0 then notes[#notes+1]=r.enemy.." nodes in enemy bases left out" end
    if (r.drops or 0)>0 then notes[#notes+1]=r.drops.." jumps down (orange)" end
    if (r.unworth or 0)>0 then notes[#notes+1]=string.format("%d nodes in %d stops not worth the way (over %d yd each)",r.unworth,r.unworthStops or 0,r.worth or 0) end
    if (r.cutoff or 0)>0 then notes[#notes+1]=string.format("%d nodes in %d stops left out: no way there and back",r.cutoff,r.cutoffStops or 0) end
    if (r.unreachable or 0)>0 then notes[#notes+1]=r.unreachable.." legs without a way found (red): plan them by hand" end
    if r.issues and #r.issues>0 then notes[#notes+1]=#r.issues.." difficult spots (warning signs on the map)" end
    if r.stale then notes[#notes+1]="changed since: Calculate again" end
    if #notes>0 then text=text.."\n"..table.concat(notes,", ").."." end
    self.status:SetText(text)
    self:Warn(r)
end

-- The warning over the map while a leg has no way: what to do about it.
function E:Warn(r)
    if not self.warning then return end
    local n=r and not r.stale and r.unreachable or 0
    if n>0 then
        self.warning.text:SetText(string.format("No way found for %d %s (red): plan %s by hand, with Preferred ground or a transition, then Calculate again.",
            n,n==1 and "leg" or "legs",n==1 and "it" or "them"))
        self.warning:SetWidth(math.max(200,math.min(self.view:GetWidth()-16,self.warning.text:GetUnboundedStringWidth()+32)))
        self.warning:Show()
    else self.warning:Hide() end
end

-- View: fit, zoom, pan ---------------------------------------------------------
function E:Fit(keep)
    if not (self.space and self.view) then return end
    local vw,vh=self.view:GetWidth(),self.view:GetHeight()
    if vw<=0 or vh<=0 then return end
    local s=self.space
    local yw,yh=(s.maxX-s.minX)*s.width,(s.maxY-s.minY)*s.height
    self.base=math.min(vw/yw,vh/yh)
    if not keep then self.zoom=1 end
    local w,h=yw*self.base*self.zoom,yh*self.base*self.zoom
    if not keep then self.ox,self.oy=(vw-w)/2,(vh-h)/2 end
    self:Place()
end
-- Terrain on and a source for it: the map is the whole world, not only the zones.
function E:Roaming() return G:Config().editorTerrain and self:TerrainArt()~=nil end
function E:Place()
    local s=self.space
    local w=(s.maxX-s.minX)*s.width*self.base*self.zoom
    local h=(s.maxY-s.minY)*s.height*self.base*self.zoom
    local vw,vh=self.view:GetWidth(),self.view:GetHeight()
    -- Some of the board always stays in view; with the terrain the view
    -- roams into the neighbouring zones (Florian 2026-10-08), up to three
    -- times the zones' size around them.
    local roam=self:Roaming() and 3 or 0
    self.ox=math.max(math.min(self.ox,vw*.6+w*roam),vw*.4-w*(1+roam))
    self.oy=math.max(math.min(self.oy,vh*.6+h*roam),vh*.4-h*(1+roam))
    if self.zoomTimer then self.zoomTimer:Cancel();self.zoomTimer=nil end
    self.board:SetScale(1)
    self.board:ClearAllPoints();self.board:SetPoint("TOPLEFT",self.view,"TOPLEFT",self.ox,-self.oy)
    -- Only moved: everything on the board moves along; just the terrain
    -- follows the view. A new size lays everything out again.
    local size=w..":"..h
    if self.placed==size then
        if G:Config().editorTerrain then self:Terrain() end
        local at=self.placesAt
        if not at or math.abs(at[1]-self.ox)+math.abs(at[2]-self.oy)>80 then self:DrawPlaces();self:DrawRelief() end
        return
    end
    self.placed=size
    self.laidZoom=self.zoom
    self.board:SetSize(w,h)
    self:Layout()
end
-- Zooming (Florian 2026-10-09: slow with many points): the board is
-- scaled at once, and laid out anew only when the wheel has rested a moment.
E.ZOOMREST=.2
function E:Zoom(delta)
    if not self.base then return end
    local cx,cy=self:Cursor()
    local vw,vh=self.view:GetWidth(),self.view:GetHeight()
    if not cx then cx,cy=vw/2,vh/2 end
    local s=self.space
    local w=(s.maxX-s.minX)*s.width*self.base*self.zoom
    local h=(s.maxY-s.minY)*s.height*self.base*self.zoom
    local fx,fy=(cx-self.ox)/w,(cy-self.oy)/h
    local zoom=math.max(self:Roaming() and .35 or 1,math.min(16,self.zoom*(delta>0 and 1.25 or .8)))
    if zoom==self.zoom then return end
    local factor=zoom/self.zoom
    self.zoom=zoom
    self.ox,self.oy=cx-fx*w*factor,cy-fy*h*factor
    if not self.laidZoom then self:Place();return end
    local scale=zoom/self.laidZoom
    self.board:SetScale(scale)
    self.board:ClearAllPoints();self.board:SetPoint("TOPLEFT",self.view,"TOPLEFT",self.ox/scale,-self.oy/scale)
    if self.zoomTimer then self.zoomTimer:Cancel() end
    self.zoomTimer=C_Timer.NewTimer(E.ZOOMREST,function() E.zoomTimer=nil;E:Place() end)
end

-- Mouse: pan, paint, erase, add points.
function E:Down(button)
    self:StopDrag()
    local cx,cy=self:Cursor()
    if not cx then return end
    -- Drawing the search area: each click a corner, a click on the first
    -- corner closes it; a right click (without moving) takes the last back.
    if self.areaDraw and button=="LeftButton" then
        local x,y=self:CursorSpace(true)
        if not x then return end
        if #self.areaDraw>=3 and self:NearFirst(cx,cy) then self:AreaButton();return end
        self.areaDraw[#self.areaDraw+1]={x,y}
        self:DrawArea();self:AreaHint();self:RefreshSide()
        return
    end
    if self.areaDraw and button=="RightButton" then self.rightDown={cx,cy} end
    if button=="RightButton" or self.tool=="move" then
        local ox,oy=self.ox,self.oy
        self.dragTicker=C_Timer.NewTicker(.02,function()
            local x,y=E:Cursor()
            if x then E.ox,E.oy=ox+x-cx,oy+y-cy;E:Place() end
        end)
    elseif E.AREA[self.tool] and button=="LeftButton" and ((IsShiftKeyDown and IsShiftKeyDown()) or self.corners) then
        -- Polygon: Shift+click sets corners, a click without Shift closes it.
        local x,y=self:CursorSpace()
        if x then self:Corner(x,y,IsShiftKeyDown and IsShiftKeyDown()) end
    elseif E.AREA[self.tool] or self.tool=="erase" then
        self.session={added={},removed={}}
        self:Brush()
        self.dragTicker=C_Timer.NewTicker(.03,function() E:Brush() end)
    elseif self.tool=="edit" and button=="LeftButton" then
        local x,y=self:CursorSpace()
        if x then self:Insert(x,y) end
    elseif self.tool=="link" and button=="LeftButton" then
        local x,y=self:CursorSpace()
        if x then self:LinkClick(x,y,IsShiftKeyDown and IsShiftKeyDown()) end
    end
end
function E:Up(button)
    if self.rightDown and button=="RightButton" then
        local down=self.rightDown;self.rightDown=nil
        local cx,cy=self:Cursor()
        if self.areaDraw and cx and math.abs(cx-down[1])+math.abs(cy-down[2])<5 and #self.areaDraw>0 then
            table.remove(self.areaDraw);self:DrawArea();self:AreaHint();self:RefreshSide()
        end
    end
    local painted=self.session and (#self.session.added>0 or #self.session.removed>0)
    self:StopDrag()
    if painted then self.history[#self.history+1]=self.session;self:Stale() end
    self.session=nil
end
function E:StopDrag()
    if self.dragTicker then self.dragTicker:Cancel();self.dragTicker=nil end
end
-- One brush step at the cursor: a stroke (spaced at 40% of its radius) or
-- erasing the strokes under it.
function E:Brush()
    local x,y=self:CursorSpace()
    if not x then return end
    self:Stroke(x,y)
end
function E:Stroke(x,y)
    local s=self.space
    local session=self.session or {added={},removed={}}
    if self.tool=="erase" then
        for _,zone in ipairs(self.zones) do
            local strokes=G.Plan:Strokes(zone)
            for i=#strokes,1,-1 do
                local stroke=strokes[i]
                local hit
                if stroke.poly then
                    -- A polygon goes when the eraser is inside it.
                    local zx,zy=select(2,Grid.FromSpace(s,x,y))
                    hit=zx and Grid.Inside(stroke.poly,zx,zy)
                else
                    local sx,sy=Grid.ToSpace(s,zone,stroke.x,stroke.y)
                    hit=sx and Grid.Yards(s,x,y,sx,sy)<=self.brush/2+(stroke.r or 0)/2
                end
                if hit then
                    table.remove(strokes,i);session.removed[#session.removed+1]={zone=zone,stroke=stroke,index=i}
                end
            end
        end
    else
        local last=self.lastStroke
        if last and last.session==session and Grid.Yards(s,x,y,last.x,last.y)<self.brush*.4 then return end
        local zone,zx,zy=Grid.FromSpace(s,x,y)
        local inside=false;for _,z in ipairs(self.zones) do if z==zone then inside=true end end
        if not inside then return end
        local stroke={x=zx,y=zy,r=self.brush,kind=self.tool}
        local strokes=G.Plan:Strokes(zone);strokes[#strokes+1]=stroke
        session.added[#session.added+1]={zone=zone,stroke=stroke}
        self.lastStroke={x=x,y=y,session=session}
    end
    self:Layout()
end
function E:Undo()
    local session=table.remove(self.history)
    if not session then return end
    for _,entry in ipairs(session.added) do
        local strokes=G.Plan:Strokes(entry.zone)
        for i=#strokes,1,-1 do if strokes[i]==entry.stroke then table.remove(strokes,i) end end
    end
    for i=#session.removed,1,-1 do
        local entry=session.removed[i]
        local strokes=G.Plan:Strokes(entry.zone)
        table.insert(strokes,math.min(entry.index,#strokes+1),entry.stroke)
    end
    self:Stale();self:Layout()
end

-- Route points by hand.
function E:SpacePoint(point) return Grid.ToSpace(self.space,point.mapID,point.x,point.y) end
function E:Insert(x,y)
    local r=self.route
    if not r or #r.points<2 then return end
    local s=self.space
    local best,bestCost
    local n=#r.points
    for i=1,n do
        local a,b=r.points[i],r.points[i+1] or (r.loop and r.points[1])
        if b then
            local ax,ay=self:SpacePoint(a);local bx,by=self:SpacePoint(b)
            if ax and bx then
                local cost=Grid.Yards(s,ax,ay,x,y)+Grid.Yards(s,x,y,bx,by)-Grid.Yards(s,ax,ay,bx,by)
                if not bestCost or cost<bestCost then best,bestCost=i,cost end
            end
        end
    end
    if not best then return end
    local zone,zx,zy=Grid.FromSpace(s,x,y)
    table.insert(r.points,best+1,{mapID=zone,x=zx,y=zy,stop=true,count=0})
    self:Edited()
end
function E:Remove(index)
    local r=self.route
    if not (r and r.points[index]) or #r.points<=2 then return end
    table.remove(r.points,index)
    self:Edited()
end
function E:Move(index,x,y)
    local r=self.route
    if not (r and r.points[index]) then return end
    local zone,zx,zy=Grid.FromSpace(self.space,x,y)
    local point=r.points[index]
    point.mapID,point.x,point.y=zone,zx,zy
    self:Edited()
end
function E:Edited()
    self.route.length=G.Plan.Measure(self.route.points,self.route.loop)
    self:Status();self:Layout()
end
-- Points take the mouse for their tooltip; outside the edit tool a press
-- on them works like one on the map.
function E:PointDown(button,index)
    if self.tool~="edit" or button~="LeftButton" and button~="RightButton" then return self:Down(button) end
    if button=="RightButton" then self:Remove(index);return end
    self:StopDrag()
    self.dragTicker=C_Timer.NewTicker(.03,function()
        local x,y=E:CursorSpace()
        local pin=E.pools.points and E.pools.points.items[index]
        if x and pin then local bx,by=E:ToBoard(x,y);pin:ClearAllPoints();pin:SetPoint("CENTER",E.board,"TOPLEFT",bx,-by) end
    end)
    self.dragIndex=index
end
function E:PointUp(index)
    if self.dragIndex~=index then return self:Up() end
    self:StopDrag();self.dragIndex=nil
    local x,y=self:CursorSpace()
    if x then self:Move(index,x,y) else self:Layout() end
end

-- Drawing ----------------------------------------------------------------------
local function texture(layer,sub)
    return function() local t=E.board:CreateTexture(nil,layer,nil,sub);return t end
end
-- Rectangles {x0,y0,x1,y1} as pieces that cover their union without
-- overlapping: a grid of all their edges, covered cells joined per row.
function E.Union(rects)
    if #rects<2 then return rects end
    local xs,ys,seenX,seenY={},{},{},{}
    for _,r in ipairs(rects) do
        for _,x in ipairs({r[1],r[3]}) do if not seenX[x] then seenX[x]=true;xs[#xs+1]=x end end
        for _,y in ipairs({r[2],r[4]}) do if not seenY[y] then seenY[y]=true;ys[#ys+1]=y end end
    end
    table.sort(xs);table.sort(ys)
    local out={}
    for j=1,#ys-1 do
        local y0,y1=ys[j],ys[j+1]
        local my=(y0+y1)/2
        local start
        for i=1,#xs do
            local covered=false
            if i<#xs then
                local mx=(xs[i]+xs[i+1])/2
                for _,r in ipairs(rects) do
                    if mx>r[1] and mx<r[3] and my>r[2] and my<r[4] then covered=true;break end
                end
            end
            if covered and not start then start=xs[i]
            elseif not covered and start then out[#out+1]={start,y0,xs[i],y1};start=nil end
        end
    end
    return out
end
-- Rectangles in groups that overlap, each group as its union: a few
-- rectangles per enemy base, never all of them in one grid.
function E.Pieces(rects)
    -- The same rectangle more than once (a place listed by several zones) counts once.
    local unique,seen={},{}
    for _,r in ipairs(rects) do
        local key=string.format("%.0f:%.0f:%.0f:%.0f",r[1],r[2],r[3],r[4])
        if not seen[key] then seen[key]=true;unique[#unique+1]=r end
    end
    rects=unique
    local group={}
    local function root(i) while group[i]~=i do group[i]=group[group[i]];i=group[i] end return i end
    for i=1,#rects do group[i]=i end
    for i=1,#rects do
        local a=rects[i]
        for j=i+1,#rects do
            local b=rects[j]
            if a[1]<b[3] and b[1]<a[3] and a[2]<b[4] and b[2]<a[4] then group[root(i)]=root(j) end
        end
    end
    local sets,out={},{}
    for i=1,#rects do local r=root(i);sets[r]=sets[r] or {};table.insert(sets[r],rects[i]) end
    -- A very large group (should not happen) is drawn as its rectangles.
    for _,set in pairs(sets) do
        local pieces=#set<=24 and E.Union(set) or set
        for _,piece in ipairs(pieces) do out[#out+1]=piece end
    end
    return out
end
-- A map's art (base tiles, then the explored overlays as Blizzard's world
-- map draws them) into a rectangle of the board. Returns the tiles drawn.
function E:Art(mapID,x0,y0,x1,y1)
    local tiles,overlays=pool("tiles",texture("BACKGROUND",1)),pool("overlays",texture("BACKGROUND",2))
    local layers=G.Call("C_Map.GetMapArtLayers",mapID)
    local layer=type(layers)=="table" and layers[1]
    if type(layer)~="table" or (layer.tileWidth or 0)<=0 or (layer.layerWidth or 0)<=0 or (layer.layerHeight or 0)<=0 then return 0 end
    local files=G.Call("C_Map.GetMapArtLayerTextures",mapID,1)
    if type(files)~="table" then return 0 end
    local TW,TH=layer.tileWidth,layer.tileHeight
    local kx,ky=(x1-x0)/layer.layerWidth,(y1-y0)/layer.layerHeight
    local cols=math.ceil(layer.layerWidth/TW)
    local drawn=0
    for i,file in ipairs(files) do
        local col,row=(i-1)%cols,math.floor((i-1)/cols)
        local tw=math.min(TW,layer.layerWidth-col*TW)
        local th=math.min(TH,layer.layerHeight-row*TH)
        if tw>0 and th>0 then
            local t=take(tiles)
            t:SetTexture(file);t:SetTexCoord(0,tw/TW,0,th/TH);t:SetVertexColor(1,1,1,1)
            t:ClearAllPoints();t:SetPoint("TOPLEFT",self.board,"TOPLEFT",x0+col*TW*kx,-(y0+row*TH*ky))
            t:SetSize(tw*kx,th*ky)
            drawn=drawn+1
        end
    end
    -- Overlays over the base parchment, explored or not (Core's overlay
    -- data, Florian 2026-10-08), in pieces of one tile; the last piece is a
    -- power of two in its file.
    local explored=ns.MapOverlays and ns.MapOverlays:All(mapID) or G.Call("C_MapExplorationInfo.GetExploredMapTextures",mapID)
    for _,info in ipairs(type(explored)=="table" and explored or {}) do
        if type(info)=="table" and type(info.fileDataIDs)=="table" and (info.textureWidth or 0)>0 and (info.textureHeight or 0)>0 then
            local wide,tall=math.ceil(info.textureWidth/TW),math.ceil(info.textureHeight/TH)
            for j=1,tall do
                local ph,fh=TH,TH
                if j==tall then
                    ph=info.textureHeight%TH;if ph==0 then ph=TH end
                    fh=16;while fh<ph do fh=fh*2 end
                end
                for k=1,wide do
                    local pw,fw=TW,TW
                    if k==wide then
                        pw=info.textureWidth%TW;if pw==0 then pw=TW end
                        fw=16;while fw<pw do fw=fw*2 end
                    end
                    local file=info.fileDataIDs[(j-1)*wide+k]
                    if file then
                        local t=take(overlays)
                        t:SetTexture(file);t:SetTexCoord(0,pw/fw,0,ph/fh);t:SetVertexColor(1,1,1,1)
                        t:ClearAllPoints()
                        t:SetPoint("TOPLEFT",self.board,"TOPLEFT",x0+((info.offsetX or 0)+TW*(k-1))*kx,-(y0+((info.offsetY or 0)+TH*(j-1))*ky))
                        t:SetSize(pw*kx,ph*ky)
                    end
                end
            end
        end
    end
    return drawn
end
-- Terrain tiles (those under the visible part of the view): the client's
-- minimap tiles, one per ADT tile of 533 1/3 yards, placed by its world corners. The space map's own corners
-- give the line between world and map: the vector part that changes along
-- the map's x is world Y (west), the one along its y is world X (north).
local ADT=1600/3
function E:WorldFrame(mapID) return ns.MapTerrain and ns.MapTerrain:Frame(mapID) end
function E:TerrainArt()
    if not (self.space and ns.MapTerrain) then return nil end
    local frame=self:WorldFrame(self.space.mapID)
    if not frame then return nil end
    local tile,source=ns.MapTerrain:Source(frame.instance)
    if not tile then return nil end
    return tile,frame,source
end
-- Lazy loading (Florian 2026-10-08: don't kill the client, and no flicker).
-- Tiles under the view plus a ring of one are wanted; at most BATCH new
-- textures load per frame, the rest on the next frames. A tile leaves the
-- view only beyond a ring of two (no back and forth at an edge), and then
-- waits hidden in a cache with its texture kept (up to CACHE tiles, the
-- oldest give their texture up), so coming back or zooming shows it again
-- at once. Moving keeps everything in place; a new size only moves the
-- tiles; a new space or source starts over.
local BATCH,CACHE=24,96
E.terrain={shown={},cache={},order={}}
function E:ClearTerrain()
    local T=self.terrain
    for _,list in ipairs({T.shown,T.cache}) do
        for key,tex in pairs(list) do tex:SetTexture(nil);tex:Hide();list[key]=nil;T.spare=T.spare or {};T.spare[#T.spare+1]=tex end
    end
    T.order={};T.source=nil
end
function E:TerrainCount() local n=0;for _ in pairs(self.terrain.shown) do n=n+1 end;return n end
function E:Terrain()
    local tile,frame,source=self:TerrainArt()
    if not tile then self:ClearTerrain();return 0 end
    local T=self.terrain
    local s=self.space
    local id=s.mapID..":"..source
    if T.source~=id then self:ClearTerrain();T.source=id end
    local w,h=self:Size()
    -- Columns from world Y, rows from world X.
    local function col(x) return 32-(frame.a[frame.ix]+x*frame.dx)/ADT end
    local function row(y) return 32-(frame.a[frame.iy]+y*frame.dy)/ADT end
    local function place(t,c,r)
        -- World Y of the tile's west edge, world X of its north edge.
        local wy,wx=(32-c)*ADT,(32-r)*ADT
        local x0=(wy-frame.a[frame.ix])/frame.dx
        local y0=(wx-frame.a[frame.iy])/frame.dy
        local x1=(wy-ADT-frame.a[frame.ix])/frame.dx
        local y1=(wx-ADT-frame.a[frame.iy])/frame.dy
        local px0,py0=(x0-s.minX)/(s.maxX-s.minX)*w,(y0-s.minY)/(s.maxY-s.minY)*h
        local px1,py1=(x1-s.minX)/(s.maxX-s.minX)*w,(y1-s.minY)/(s.maxY-s.minY)*h
        t:ClearAllPoints();t:SetPoint("TOPLEFT",self.board,"TOPLEFT",math.min(px0,px1),-math.min(py0,py1))
        t:SetSize(math.abs(px1-px0),math.abs(py1-py0))
    end
    local size=w..":"..h
    if T.size~=size then
        T.size=size
        for key,tex in pairs(T.shown) do place(tex,math.floor(key/100),key%100) end
    end
    local vw,vh=self.view:GetWidth(),self.view:GetHeight()
    local ax=s.minX+(0-self.ox)/w*(s.maxX-s.minX)
    local bx=s.minX+(vw-self.ox)/w*(s.maxX-s.minX)
    local ay=s.minY+(0-self.oy)/h*(s.maxY-s.minY)
    local by=s.minY+(vh-self.oy)/h*(s.maxY-s.minY)
    -- Half-open view range (a view ending on a tile edge leaves the next one out).
    local c0,c1=math.floor(math.min(col(ax),col(bx))),math.ceil(math.max(col(ax),col(bx)))-1
    local r0,r1=math.floor(math.min(row(ay),row(by))),math.ceil(math.max(row(ay),row(by)))-1
    local function inside(key,ring)
        local c,r=math.floor(key/100),key%100
        return c>=c0-ring and c<=c1+ring and r>=r0-ring and r<=r1+ring
    end
    -- Beyond the ring of two: into the cache, texture kept.
    for key,tex in pairs(T.shown) do
        if not inside(key,2) then
            tex:Hide();T.shown[key]=nil;T.cache[key]=tex;T.order[#T.order+1]=key
        end
    end
    -- Wanted: view plus one, nearest to the view's middle first.
    local wanted={}
    local mc,mr=(c0+c1)/2,(r0+r1)/2
    for c=math.max(0,c0-1),math.min(63,c1+1) do
        for r=math.max(0,r0-1),math.min(63,r1+1) do
            local key=c*100+r
            if not T.shown[key] then wanted[#wanted+1]={key=key,d=(c-mc)^2+(r-mr)^2} end
        end
    end
    table.sort(wanted,function(a,b) return a.d<b.d end)
    local loaded,pending=0,false
    for _,entry in ipairs(wanted) do
        local key=entry.key
        local c,r=math.floor(key/100),key%100
        local cached=T.cache[key]
        if cached then
            -- Back from the cache: shown at once, no loading.
            T.cache[key]=nil
            for i=#T.order,1,-1 do if T.order[i]==key then table.remove(T.order,i) end end
            place(cached,c,r);cached:Show();T.shown[key]=cached
        else
            local file=tile(c,r)
            if file then
                if loaded>=BATCH then pending=true
                else
                    loaded=loaded+1
                    T.spare=T.spare or {}
                    local t=table.remove(T.spare) or self.board:CreateTexture(nil,"BACKGROUND",nil,3)
                    -- A file the client lacks (green placeholder, Florian 2026-10-08): left out.
                    if ns.MapTerrain:Load(t,file) then
                        t:SetTexCoord(0,1,0,1);t:SetVertexColor(1,1,1,1)
                        place(t,c,r);t:Show()
                        T.shown[key]=t
                    else T.spare[#T.spare+1]=t end
                end
            end
        end
    end
    -- The oldest cached tiles give their texture up.
    while #T.order>CACHE do
        local key=table.remove(T.order,1)
        local tex=T.cache[key]
        if tex then tex:SetTexture(nil);T.cache[key]=nil;T.spare=T.spare or {};T.spare[#T.spare+1]=tex end
    end
    if pending and not T.timer then
        T.timer=C_Timer.NewTimer(0,function() T.timer=nil;if E.window and E.window:IsShown() then E:Terrain() end end)
    end
    return self:TerrainCount()
end
-- One zone: its own map. Several zones: their continent's map, so the zone
-- maps (each showing its neighbours too) never overlap (Florian 2026-10-08).
function E:Tiles()
    local frames,labels=pool("zones",texture("BACKGROUND",0)),pool("labels",function() return UI:Label(E.board,"",12,"muted") end)
    reset(pool("tiles",texture("BACKGROUND",1)));reset(pool("overlays",texture("BACKGROUND",2)))
    reset(frames);reset(labels)
    local s=self.space
    local w,h=self:Size()
    local function px(a,c) return (a-s.minX)/(s.maxX-s.minX)*w,(c-s.minY)/(s.maxY-s.minY)*h end
    -- Terrain (Florian 2026-10-08: the client's minimap tiles) replaces
    -- Blizzard's map; that one stays for areas without tiles.
    if G:Config().editorTerrain and self:Terrain()>0 then return end
    self:ClearTerrain()
    local continent=#self.zones>1 and s.mapID~=self.zones[1]
    local drawn=0
    if continent then
        local x0,y0=px(0,0);local x1,y1=px(1,1)
        drawn=self:Art(s.mapID,x0,y0,x1,y1)
    end
    for _,zone in ipairs(self.zones) do
        local a,b,c,d=0,1,0,1
        if zone~=s.mapID then a,b,c,d=G.Call("C_Map.GetMapRectOnMap",zone,s.mapID) end
        if type(a)=="number" then
            local x0,y0=px(a,c);local x1,y1=px(b,d)
            if drawn==0 then
                local ground=take(frames)
                ground:SetColorTexture(.11,.12,.14,1);ground:ClearAllPoints()
                ground:SetPoint("TOPLEFT",self.board,"TOPLEFT",x0,-y0);ground:SetSize(math.max(1,x1-x0),math.max(1,y1-y0))
            end
            local own=not continent and self:Art(zone,x0,y0,x1,y1) or 0
            -- Without any art: the plain ground and the zone's name.
            if drawn==0 and own==0 then
                local l=take(labels);l:SetText(self:ZoneName(zone));l:ClearAllPoints();l:SetPoint("TOPLEFT",self.board,"TOPLEFT",x0+8,-y0-8)
            end
        end
    end
end
function E:Layout()
    if not (self.window and self.window:IsShown() and self.space and self.base) then return end
    self:Tiles()
    local ppy=self:PixelsPerYard()
    -- Painted strokes.
    local strokes=pool("strokes",function() local t=E.board:CreateTexture(nil,"BORDER");t:SetTexture(DISC);return t end)
    reset(strokes)
    local fills=pool("fills",texture("BORDER",1))
    local outlines=pool("outlines",function() local l=E.board:CreateLine(nil,"BORDER",nil,2);l:SetTexture(WHITE);return l end)
    reset(fills);reset(outlines)
    for _,zone in ipairs(self.zones) do
        for _,stroke in ipairs(G.Plan:Strokes(zone)) do
            local x,y
            if stroke.poly then self:DrawPolygon(zone,stroke,fills,outlines)
            else x,y=Grid.ToSpace(self.space,zone,stroke.x,stroke.y) end
            local color=self.AREA[stroke.kind]
            if x and color then
                local t=take(strokes)
                local bx,by=self:ToBoard(x,y)
                local size=math.max(3,(stroke.r or 20)*2*ppy)
                t:SetVertexColor(color[1],color[2],color[3],color[4])
                t:ClearAllPoints();t:SetPoint("CENTER",self.board,"TOPLEFT",bx,-by);t:SetSize(size,size)
            end
        end
    end
    self:DrawNodes()
    self:DrawRoute()
    self:DrawPlaces()
    self:DrawRelief()
    self:DrawLinks()
    self:DrawArea()
end
-- Nodes: chosen ones bright, the others faint. Whether each lies in the
-- search area is worked out once per area, not on every redraw.
function E:DrawNodes()
    local dots=pool("dots",function() local t=E.board:CreateTexture(nil,"ARTWORK");t:SetTexture(DISC);return t end)
    reset(dots)
    if self.area and (not self.inside or self.insideArea~=self.area) then
        self.inside,self.insideArea={},self.area
        for i,node in ipairs(self.nodes or {}) do self.inside[i]=G.Plan.InArea(self.area,node.zone,node.raw) end
    end
    -- Nodes of one name that would cover each other at this zoom share one
    -- dot (Florian 2026-10-09: thousands of dots made the editor lag).
    local dot=math.max(4,math.min(9,3+self.zoom))
    local cell=dot*.6
    local seen={}
    self.dotsByKey={}
    for i,node in ipairs(self.nodes or {}) do
        local bx,by=self:ToBoard(node.x,node.y)
        local inside=not self.area or self.inside[i]
        local cells=seen[node.key];if not cells then cells={};seen[node.key]=cells end
        local spot=math.floor(bx/cell)*65536+math.floor(by/cell)
        local t=cells[spot]
        if t then
            if inside and not t.inside then t.inside=true;self:DotColor(t) end
        elseif dots.used<2000 then
            t=take(dots);cells[spot]=t
            t.key,t.kind,t.inside=node.key,node.kind,inside and true or false
            self:DotColor(t)
            t:ClearAllPoints();t:SetPoint("CENTER",self.board,"TOPLEFT",bx,-by);t:SetSize(dot,dot)
            local list=self.dotsByKey[node.key];if not list then list={};self.dotsByKey[node.key]=list end
            list[#list+1]=t
        end
    end
end
-- A polygon: its outline, and its inside as rows of 8-yard cells.
function E:DrawPolygon(zone,area,fills,outlines)
    local color=self.AREA[area.kind]
    if not color then return end
    local s=self.space
    local points={}
    for i=1,#area.poly-1,2 do
        local x,y=Grid.ToSpace(s,zone,area.poly[i],area.poly[i+1])
        if not x then return end
        points[#points+1]={x,y}
    end
    for i,a in ipairs(points) do
        local b=points[i%#points+1]
        local x1,y1=self:ToBoard(a[1],a[2]);local x2,y2=self:ToBoard(b[1],b[2])
        local l=take(outlines)
        l:SetVertexColor(color[1],color[2],color[3],.9);l:SetThickness(2)
        l:SetStartPoint("TOPLEFT",self.board,x1,-y1);l:SetEndPoint("TOPLEFT",self.board,x2,-y2)
    end
    local minX,minY,maxX,maxY=math.huge,math.huge,-math.huge,-math.huge
    for _,p in ipairs(points) do minX,minY,maxX,maxY=math.min(minX,p[1]),math.min(minY,p[2]),math.max(maxX,p[1]),math.max(maxY,p[2]) end
    local stepX,stepY=Grid.CELL/s.width,Grid.CELL/s.height
    local flat={};for _,p in ipairs(points) do flat[#flat+1]=p[1];flat[#flat+1]=p[2] end
    local y=minY+stepY/2
    while y<maxY do
        local x,from=minX+stepX/2,nil
        while x<maxX+stepX do
            local inside=x<maxX and Grid.Inside(flat,x,y)
            if inside and not from then from=x end
            if not inside and from then
                local px0,py0=self:ToBoard(from-stepX/2,y-stepY/2);local px1,py1=self:ToBoard(x-stepX/2,y+stepY/2)
                local t=take(fills)
                t:SetColorTexture(color[1],color[2],color[3],color[4]*.8)
                t:ClearAllPoints();t:SetPoint("TOPLEFT",self.board,"TOPLEFT",px0,-py0);t:SetSize(math.max(1,px1-px0),math.max(1,py1-py0))
                from=nil
            end
            x=x+stepX
        end
        y=y+stepY
    end
end
-- The search area: Area starts it, clicks set corners, a click on the
-- first corner or Finish closes it (three corners at least; fewer cancel),
-- a click with one set clears it.
E.CLOSEPX=10
function E:NearFirst(cx,cy)
    local first=self.areaDraw and self.areaDraw[1]
    if not first then return false end
    local bx,by=self:ToBoard(first[1],first[2])
    local scale=self.board:GetScale() or 1
    local x,y=self.ox+bx*scale,self.oy+by*scale
    return math.abs(cx-x)<=E.CLOSEPX and math.abs(cy-y)<=E.CLOSEPX
end
function E:AreaHint()
    if not (self.hint and self.areaDraw) then return end
    local n=#self.areaDraw
    if self.catcher and self.catcher.banner then
        self.catcher.banner.text:SetText(n<3 and string.format("SEARCH AREA  ·  click the corners (%d of at least 3)",n)
            or string.format("SEARCH AREA  ·  %d corners  ·  click the first corner or Finish to close",n))
    end
    self.hint:SetText(n<3 and string.format("Search area: click its corners on the map (%d of at least 3). Right-click: take the last back.",n)
        or string.format("Search area: %d corners. Click the first corner or Finish to close it; right-click: take the last back.",n))
end
-- The drawing mode: the catching layer and a line from the last corner to
-- the cursor (and back to the first) while it is on.
function E:AreaMode(on)
    if self.catcher then self.catcher:SetShown(on and true or false) end
    if self.dim then self.dim:SetShown(on and true or false) end
    if on and not self.areaTicker then
        self.areaTicker=C_Timer.NewTicker(.03,function() E:Rubber() end)
    elseif not on then
        if self.areaTicker then self.areaTicker:Cancel();self.areaTicker=nil end
        if self.rubber then for _,l in ipairs(self.rubber) do l:Hide() end end
        self.rightDown=nil
        if not on and self.areaDraw and not (self.window and self.window:IsShown()) then self.areaDraw=nil end
    end
end
function E:Rubber()
    if not (self.areaDraw and self.window and self.window:IsShown()) then return self:AreaMode(false) end
    self.rubber=self.rubber or {}
    for i=1,2 do
        if not self.rubber[i] then local l=self.board:CreateLine(nil,"OVERLAY",nil,5);l:SetTexture(WHITE);self.rubber[i]=l end
    end
    local cx,cy=self:Cursor()
    local last,first=self.areaDraw[#self.areaDraw],self.areaDraw[1]
    local x,y=self:CursorSpace(true)
    local key=x and last and string.format("%.1f:%.1f:%d:%.4f:%.1f:%.1f",cx,cy,#self.areaDraw,self.zoom,self.ox,self.oy) or ""
    if key==self.rubberKey then return end
    self.rubberKey=key
    for _,l in ipairs(self.rubber) do l:Hide() end
    if not (x and last) then return end
    local ar,ag,ab=G:Style():Color("accent")
    local tx,ty=self:ToBoard(x,y)
    local near=#self.areaDraw>=3 and self:NearFirst(cx,cy)
    if near then tx,ty=self:ToBoard(first[1],first[2]) end
    local lx,ly=self:ToBoard(last[1],last[2])
    local a=self.rubber[1]
    a:SetVertexColor(ar,ag,ab,.8);a:SetThickness(2)
    a:SetStartPoint("TOPLEFT",self.board,lx,-ly);a:SetEndPoint("TOPLEFT",self.board,tx,-ty);a:Show()
    if #self.areaDraw>=2 and not near then
        local fx,fy=self:ToBoard(first[1],first[2])
        local b=self.rubber[2]
        b:SetVertexColor(ar,ag,ab,.3);b:SetThickness(1)
        b:SetStartPoint("TOPLEFT",self.board,tx,-ty);b:SetEndPoint("TOPLEFT",self.board,fx,-fy);b:Show()
    end
    if self.areaCornerFirst then self.areaCornerFirst:SetSize(near and 16 or 11,near and 16 or 11) end
end
function E:AreaButton()
    if self.areaDraw then
        if #self.areaDraw>=3 then
            local zone=Grid.FromSpace(self.space,self.areaDraw[1][1],self.areaDraw[1][2])
            local poly={}
            for _,corner in ipairs(self.areaDraw) do
                local z,zx,zy=Grid.FromSpace(self.space,corner[1],corner[2])
                if z~=zone then zx,zy=ns.MapPins:OnMap({mapID=z,x=zx,y=zy},zone) end
                poly[#poly+1]=zx;poly[#poly+1]=zy
            end
            self.area={mapID=zone,poly=poly}
        end
        self.areaDraw=nil
        self:AreaMode(false);self:Tool(self.tool)
    elseif self.area then self.area=nil
    else self.areaDraw={};self:AreaMode(true);self:AreaHint() end
    self:Stale();self:RefreshSide();self:Layout()
end
function E:DrawArea()
    local lines=pool("areaLines",function() local l=E.board:CreateLine(nil,"OVERLAY",nil,4);l:SetTexture(WHITE);return l end)
    reset(lines)
    local points={}
    if self.areaDraw then
        for _,corner in ipairs(self.areaDraw) do points[#points+1]=corner end
    elseif self.area then
        for i=1,#self.area.poly-1,2 do
            local x,y=Grid.ToSpace(self.space,self.area.mapID,self.area.poly[i],self.area.poly[i+1])
            if x then points[#points+1]={x,y} end
        end
    end
    local ar,ag,ab=G:Style():Color("accent")
    local closed=not self.areaDraw
    -- Corners as dots while drawing; the first larger (click it to close).
    local corners=pool("areaCorners",function() local t=E.board:CreateTexture(nil,"OVERLAY",nil,6);t:SetTexture(DISC);return t end)
    reset(corners);self.areaCornerFirst=nil
    if self.areaDraw then
        for i,corner in ipairs(points) do
            local bx,by=self:ToBoard(corner[1],corner[2])
            local t=take(corners)
            local size=i==1 and #points>=3 and 11 or 7
            t:SetSize(size,size);t:SetVertexColor(ar,ag,ab,1)
            t:ClearAllPoints();t:SetPoint("CENTER",self.board,"TOPLEFT",bx,-by)
            if i==1 then self.areaCornerFirst=t end
        end
    end
    self.rubberKey=nil
    for i=1,#points do
        local a,b=points[i],points[i+1] or (closed and #points>2 and points[1])
        if b then
            local x1,y1=self:ToBoard(a[1],a[2]);local x2,y2=self:ToBoard(b[1],b[2])
            local l=take(lines)
            l:SetVertexColor(ar,ag,ab,1);l:SetThickness(2)
            l:SetStartPoint("TOPLEFT",self.board,x1,-y1);l:SetEndPoint("TOPLEFT",self.board,x2,-y2)
        end
    end
end
-- Polygons (Florian 2026-10-08: an area tool besides the brush): corners
-- with Shift+click, closed by a click without Shift (three corners at least);
-- stored with the strokes of the zone of their first corner.
function E:Corner(x,y,more)
    self.corners=self.corners or {}
    if more or #self.corners<3 then
        self.corners[#self.corners+1]={x,y}
        if self.hint then self.hint:SetText(#self.corners.." corners. Shift+click: more; click: close the area.") end
    else
        local zone=Grid.FromSpace(self.space,self.corners[1][1],self.corners[1][2])
        local poly={}
        for _,corner in ipairs(self.corners) do
            local z,zx,zy=Grid.FromSpace(self.space,corner[1],corner[2])
            if z~=zone then zx,zy=ns.MapPins:OnMap({mapID=z,x=zx,y=zy},zone) end
            poly[#poly+1]=zx;poly[#poly+1]=zy
        end
        local area={kind=self.tool,poly=poly}
        local strokes=G.Plan:Strokes(zone);strokes[#strokes+1]=area
        self.history[#self.history+1]={added={{zone=zone,stroke=area}},removed={}}
        self.corners=nil
        self:Stale();self:Tool(self.tool)
    end
    self:Layout()
end
-- Transitions: start, then end; both ends in our zones.
function E:LinkClick(x,y,oneway)
    local zone,zx,zy=Grid.FromSpace(self.space,x,y)
    if not self.linkStart then
        self.linkStart={mapID=zone,x=zx,y=zy}
        if self.hint then self.hint:SetText("Now click the transition's end (Shift: one way).") end
    else
        local link=G.Plan:AddLink(self.linkStart,{mapID=zone,x=zx,y=zy},oneway)
        self.linkStart=nil
        G:Print(link.name..(oneway and " (one way)" or "").." added.")
        self:Stale();self:Tool("link")
    end
    self:DrawLinks()
end
function E:DrawLinks()
    local lines=pool("linkLines",function()
        local l=E.board:CreateLine(nil,"OVERLAY",nil,1);l:SetTexture(WHITE);return l
    end)
    local ends=pool("linkEnds",function()
        local b=CreateFrame("Button",nil,E.board);b:SetFrameLevel(E.board:GetFrameLevel()+4);b:SetSize(12,12)
        b.disc=b:CreateTexture(nil,"ARTWORK");b.disc:SetAllPoints(b);b.disc:SetTexture(DISC)
        b:RegisterForClicks("RightButtonUp")
        b:SetScript("OnClick",function(self) G.Plan:RemoveLink(self.index);E:Stale();E:DrawLinks() end)
        b:SetScript("OnEnter",function(self)
            local link=G.Plan:Links()[self.index]
            if link then UI:ShowTooltip(self,link.name,{tag=link.oneway and "One way" or "Both ways",rows={{"End",self.which}},hint="Right-click: remove"}) end
        end)
        b:SetScript("OnLeave",function(self) UI:HideTooltip(self) end)
        return b
    end)
    reset(lines);reset(ends)
    self.linkArrows=self.linkArrows or {}
    local arrows=0
    for index,link in ipairs(G.Plan:Links()) do
        local ax,ay=Grid.ToSpace(self.space,link.a.mapID,link.a.x,link.a.y)
        local bx,by=Grid.ToSpace(self.space,link.b.mapID,link.b.x,link.b.y)
        if ax and bx then
            local x1,y1=self:ToBoard(ax,ay);local x2,y2=self:ToBoard(bx,by)
            local l=take(lines)
            l:SetVertexColor(.75,.45,1,.95);l:SetThickness(3)
            l:SetStartPoint("TOPLEFT",self.board,x1,-y1);l:SetEndPoint("TOPLEFT",self.board,x2,-y2)
            if link.oneway and ns.MapPins and ns.MapPins.Chevrons then
                arrows=ns.MapPins:Chevrons(self.linkArrows,self.board,self.board,"TOPLEFT",x1,-y1,x2,-y2,5,1.6,26,arrows)
            end
            for which,spot in ipairs({{x1,y1},{x2,y2}}) do
                local b=take(ends)
                b.index,b.which=index,which==1 and "Start" or "End"
                b.disc:SetVertexColor(.75,.45,1,1)
                b:ClearAllPoints();b:SetPoint("CENTER",self.board,"TOPLEFT",spot[1],-spot[2])
            end
        end
    end
    for i=arrows+1,#self.linkArrows do self.linkArrows[i]:Hide() end
end
-- Slopes and water (terrain data): steep and unwalkable ground, swimming
-- water, magma, roads (light) and entrances (holes, violet: caves and
-- buildings, where transitions belong) as tinted areas, in blocks of 4 x 4 cells (33 yards) and
-- merged along each row, only near the view and not zoomed far out.
E.RELIEF={[1]={1,.62,.1,.26},[2]={.92,.15,.1,.36},[3]={.25,.55,1,.34},[4]={1,0,.6,.45},[5]={1,.92,.55,.5},[6]={.85,.3,1,.8}}
-- Which one a block shows: magma, swimming water, road, unwalkable, steep.
E.RANK={[0]=0,[1]=1,[2]=2,[5]=3,[3]=4,[4]=5,[6]=6}
function E:DrawHeat()
    local heat=pool("heat",texture("BORDER",0))
    reset(heat)
    if not G:Config().editorHeat or self.zoom<.6 or not ns.MapTerrain then return end
    local frame=self:WorldFrame(self.space.mapID)
    local walked=frame and G.Trace:Store()[frame.instance]
    if not walked then return end
    local s=self.space
    local w,h=self:Size()
    local vw,vh=self.view:GetWidth(),self.view:GetHeight()
    local ax,bx=s.minX+(0-self.ox)/w*(s.maxX-s.minX),s.minX+(vw-self.ox)/w*(s.maxX-s.minX)
    local ay,by=s.minY+(0-self.oy)/h*(s.maxY-s.minY),s.minY+(vh-self.oy)/h*(s.maxY-s.minY)
    local c0,c1,r0,r1=ns.MapTerrain.Range(frame,ax,ay,bx,by)
    local drawn=0
    for col=c0,c1 do
        for row=r0,r1 do
            local cells=walked[col*100+row]
            if cells then
                local x0,y0,x1,y1=ns.MapTerrain.Rect(frame,col,row)
                local cw,ch=(x1-x0)/64,(y1-y0)/64
                for cell,count in pairs(cells) do
                    if drawn>=4000 then return end
                    drawn=drawn+1
                    local cx,cy=cell%64,math.floor(cell/64)
                    local px0,py0=self:ToBoard(x0+cx*cw,y0+cy*ch)
                    local px1,py1=self:ToBoard(x0+(cx+1)*cw,y0+(cy+1)*ch)
                    local t=take(heat)
                    t:SetColorTexture(.35,1,.45,math.min(.7,.15+count*.1))
                    t:ClearAllPoints();t:SetPoint("TOPLEFT",self.board,"TOPLEFT",px0,-py0)
                    t:SetSize(math.max(1,px1-px0),math.max(1,py1-py0))
                end
            end
        end
    end
end
function E:DrawRelief()
    self:DrawHeat()
    local relief=pool("relief",texture("BORDER",-1))
    reset(relief)
    local c=G:Config()
    if not c.editorRelief or self.zoom<.6 or not ns.MapTerrain then return end
    local frame=self:WorldFrame(self.space.mapID)
    if not (frame and ns.MapTerrain:Data(frame.instance)) then return end
    local s=self.space
    local w,h=self:Size()
    local vw,vh=self.view:GetWidth(),self.view:GetHeight()
    local ax,bx=s.minX+(0-self.ox)/w*(s.maxX-s.minX),s.minX+(vw-self.ox)/w*(s.maxX-s.minX)
    local ay,by=s.minY+(0-self.oy)/h*(s.maxY-s.minY),s.minY+(vh-self.oy)/h*(s.maxY-s.minY)
    local c0,c1,r0,r1=ns.MapTerrain.Range(frame,ax,ay,bx,by)
    local function board(mx,my) return (mx-s.minX)/(s.maxX-s.minX)*w,(my-s.minY)/(s.maxY-s.minY)*h end
    for col=c0,c1 do
        for row=r0,r1 do
            local runs=self:ReliefRuns(frame.instance,col,row)
            if runs then
                local x0,y0,x1,y1=ns.MapTerrain.Rect(frame,col,row)
                local bw,bh=(x1-x0)/16,(y1-y0)/16
                for i=1,#runs,4 do
                    local by4,from,to,value=runs[i],runs[i+1],runs[i+2],runs[i+3]
                    local color=self.RELIEF[value]
                    local px0,py0=board(x0+from*bw,y0+by4*bh)
                    local px1,py1=board(x0+to*bw,y0+(by4+1)*bh)
                    local t=take(relief)
                    t:SetColorTexture(color[1],color[2],color[3],color[4])
                    t:ClearAllPoints();t:SetPoint("TOPLEFT",self.board,"TOPLEFT",px0,-py0)
                    t:SetSize(math.max(1,px1-px0),math.max(1,py1-py0))
                end
            end
        end
    end
end
-- A tile's tinted areas as runs {row, from, to, value, ...} in blocks of 4 x 4
-- cells, worked out once per tile (moving the map only places them).
E.reliefRuns={}
function E:ReliefRuns(instance,col,row)
    local key=instance*10000+col*100+row
    local codes=ns.MapTerrain:Codes(instance,col,row)
    if not codes then return nil end
    -- Kept with the decoded tile it came from (new data: worked out anew).
    local cached=self.reliefRuns[key]
    if cached and cached.codes==codes then return cached.runs end
    local runs={}
    for by4=0,15 do
        local run,from=0,0
        for bx4=0,16 do
            local value=0
            if bx4<16 then
                -- The block's worst: entrance, magma, swimming water, road, unwalkable, steep.
                for dy=0,3 do
                    for dx=0,3 do
                        local code=codes[(by4*4+dy)*64+bx4*4+dx+1] or 0
                        local water,slope=math.floor(code/4)%4,code%4
                        local road=code%64>=32 and water==0
                        local hole=math.floor(code/16)%2==1
                        local v=(hole and 6) or (water==3 and 4) or (water==2 and 3) or (road and 5) or (slope==3 and 2) or (slope==2 and 1) or 0
                        if E.RANK[v]>E.RANK[value] then value=v end
                    end
                end
            end
            if value~=run or bx4==16 then
                if run>0 then runs[#runs+1]=by4;runs[#runs+1]=from;runs[#runs+1]=bx4;runs[#runs+1]=run end
                run,from=value,bx4
            end
        end
    end
    self.reliefRuns[key]={codes=codes,runs=runs}
    return runs
end
-- Names and places (Florian 2026-10-08): zone names when zoomed out, the
-- subzone names Blizzard's map shows on hover (Core's overlay labels) and
-- flight masters, for the chosen zones and, while roaming, their
-- neighbours on the continent. Collected once per space, drawn only near
-- the view; moving the map redraws them after it has moved a bit.
E.ZONECOLOR={1,.82,.3}
E.AREACOLOR={1,.95,.85}
E.FLIGHTCOLOR={.55,.85,1}
function E:PlaceZones()
    local list,seen={},{}
    local function add(zone) if type(zone)=="number" and not seen[zone] then seen[zone]=true;list[#list+1]=zone end end
    for _,zone in ipairs(self.zones) do add(zone) end
    if self:Roaming() then
        local continent=ns.MapPins and ns.MapPins:Continent(self.zones[1])
        local children=continent and G.Call("C_Map.GetMapChildrenInfo",continent,3,true)
        for _,child in ipairs(type(children)=="table" and children or {}) do if type(child)=="table" then add(child.mapID) end end
    end
    return list
end
function E:Places()
    local key=self.space.mapID..":"..tostring(self:Roaming())..":"..table.concat(self.zones,",")..":"..tostring(G:Config().ownFlights)
    if self.placesKey==key then return self.places end
    local s=self.space
    local out,flights={},{}
    for _,zone in ipairs(self:PlaceZones()) do
        local x,y=Grid.ToSpace(s,zone,.5,.5)
        if x then
            out[#out+1]={kind="zone",x=x,y=y,name=self:ZoneName(zone)}
            for _,label in ipairs(ns.MapOverlays and ns.MapOverlays:Labels(zone) or {}) do
                local lx,ly=Grid.ToSpace(s,zone,label.x,label.y)
                if lx and label.name~="" then out[#out+1]={kind="area",x=lx,y=ly,name=label.name} end
            end
            for _,place in ipairs(ns.MapOverlays and ns.MapOverlays.Hostile and ns.MapOverlays:Hostile(zone) or {}) do
                local ex0,ey0=Grid.ToSpace(s,zone,place.left,place.top)
                local ex1,ey1=Grid.ToSpace(s,zone,place.right,place.bottom)
                if ex0 and ex1 then out[#out+1]={kind="enemy",x=(ex0+ex1)/2,y=(ey0+ey1)/2,x0=ex0,y0=ey0,x1=ex1,y1=ey1,name=place.name} end
            end
            local nodes=G.Call("C_TaxiMap.GetTaxiNodesForMap",zone)
            for _,node in ipairs(type(nodes)=="table" and nodes or {}) do
                local position=type(node)=="table" and node.position
                local ok,px,py=false
                if position and position.GetXY then ok,px,py=pcall(position.GetXY,position) end
                local id=node.nodeID or node.name
                local hidden=G:Config().ownFlights and ns.MapOverlays and ns.MapOverlays.HostileNode(node.faction)
                if ok and not hidden and type(px)=="number" and px>=0 and px<=1 and py>=0 and py<=1 and not flights[id] then
                    local fx,fy=Grid.ToSpace(s,zone,px,py)
                    if fx then flights[id]=true;out[#out+1]={kind="flight",x=fx,y=fy,name=node.name} end
                end
            end
        end
    end
    self.places,self.placesKey=out,key
    return out
end
function E:DrawPlaces()
    local names=pool("names",function()
        local l=UI:Label(E.board,"",12,"text",true);l:SetDrawLayer("OVERLAY",6)
        if l.SetShadowOffset then l:SetShadowOffset(1,-1);l:SetShadowColor(0,0,0,1) end
        return l
    end)
    local flights=pool("flights",function()
        local b=CreateFrame("Button",nil,E.board);b:SetFrameLevel(E.board:GetFrameLevel()+3);b:SetSize(16,16)
        b.disc=b:CreateTexture(nil,"BACKGROUND");b.disc:SetAllPoints(b);b.disc:SetTexture(DISC);b.disc:SetVertexColor(.06,.06,.08,.85)
        b.icon=b:CreateTexture(nil,"ARTWORK");b.icon:SetPoint("CENTER");b.icon:SetSize(11,11)
        local path,l,r,t,bt=ns.Symbols:Coords("plane",32)
        if path then b.icon:SetTexture(path);b.icon:SetTexCoord(l,r,t,bt) end
        b.icon:SetVertexColor(E.FLIGHTCOLOR[1],E.FLIGHTCOLOR[2],E.FLIGHTCOLOR[3],1)
        b:SetScript("OnEnter",function(self) UI:ShowTooltip(self,self.name or "Flight master",{tag="Flight master",tagColor=E.FLIGHTCOLOR}) end)
        b:SetScript("OnLeave",function(self) UI:HideTooltip(self) end)
        return b
    end)
    local enemies=pool("enemies",texture("BORDER",-2))
    reset(names);reset(flights);reset(enemies)
    if not G:Config().editorNames then return end
    local w,h=self:Size()
    local vw,vh=self.view:GetWidth(),self.view:GetHeight()
    local zone,area=self.zoom<1.3,self.zoom>=.7
    -- Enemy bases: their rectangles overlap (town, flight master), so the
    -- tint is drawn once over their union, never stacked darker (Florian
    -- 2026-10-09: it looked like a painted no-go area).
    local rects={}
    for _,place in ipairs(self:Places()) do
        if place.kind=="enemy" then
            local px0,py0=self:ToBoard(math.min(place.x0,place.x1),math.min(place.y0,place.y1))
            local px1,py1=self:ToBoard(math.max(place.x0,place.x1),math.max(place.y0,place.y1))
            -- Only near the view, as the other places (the whole roaming
            -- area has hundreds: Florian 2026-10-09, "script ran too long").
            local vx0,vy0,vx1,vy1=px0+self.ox,py0+self.oy,px1+self.ox,py1+self.oy
            if vx1>-vw*.5 and vx0<vw*1.5 and vy1>-vh*.5 and vy0<vh*1.5 then rects[#rects+1]={px0,py0,px1,py1} end
        end
    end
    for _,piece in ipairs(E.Pieces(rects)) do
        local t=take(enemies)
        t:SetColorTexture(.9,.12,.12,.22)
        t:ClearAllPoints();t:SetPoint("TOPLEFT",self.board,"TOPLEFT",piece[1],-piece[2]);t:SetSize(math.max(1,piece[3]-piece[1]),math.max(1,piece[4]-piece[2]))
    end
    for _,place in ipairs(self:Places()) do
        local bx,by=self:ToBoard(place.x,place.y)
        local vx,vy=bx+self.ox,by+self.oy
        if vx>-vw*.5 and vx<vw*1.5 and vy>-vh*.5 and vy<vh*1.5 then
            if place.kind=="flight" then
                local b=take(flights);b.name=place.name
                b:ClearAllPoints();b:SetPoint("CENTER",self.board,"TOPLEFT",bx,-by)
            elseif (place.kind=="zone" and zone) or (place.kind=="area" and area) then
                local l=take(names)
                local c=place.kind=="zone" and self.ZONECOLOR or self.AREACOLOR
                UI:GetStyle():Font(l,place.kind=="zone" and 16 or 11)
                l:SetText(place.kind=="zone" and place.name:upper() or place.name)
                l:SetTextColor(c[1],c[2],c[3],place.kind=="zone" and .95 or .9)
                l:ClearAllPoints();l:SetPoint("CENTER",self.board,"TOPLEFT",bx,-by)
            end
        end
    end
    self.placesAt={self.ox,self.oy}
end
function E:DrawRoute()
    local lines=pool("lines",function()
        local l=E.board:CreateLine(nil,"OVERLAY",nil,2);l:SetTexture(WHITE)
        l.shadow=E.board:CreateLine(nil,"OVERLAY",nil,1);l.shadow:SetTexture(WHITE)
        local show,hide=l.Show,l.Hide
        function l:Show() show(self);self.shadow:Show() end
        function l:Hide() hide(self);self.shadow:Hide() end
        return l
    end)
    local points=pool("points",function()
        local b=CreateFrame("Button",nil,E.board);b:SetFrameLevel(E.board:GetFrameLevel()+5)
        b.disc=b:CreateTexture(nil,"BACKGROUND");b.disc:SetAllPoints(b);b.disc:SetTexture(DISC)
        b.dot=b:CreateTexture(nil,"ARTWORK");b.dot:SetPoint("CENTER");b.dot:SetTexture(DISC)
        b.number=UI:Label(b,"",10,"text",true);b.number:SetPoint("CENTER")
        b:RegisterForClicks("LeftButtonUp","RightButtonUp")
        b:SetScript("OnMouseDown",function(self,button) E:PointDown(button,self.index) end)
        b:SetScript("OnMouseUp",function(self) E:PointUp(self.index) end)
        b:SetScript("OnEnter",function(self) E:PointTooltip(self) end)
        b:SetScript("OnLeave",function(self) UI:HideTooltip(self) end)
        return b
    end)
    reset(lines);reset(points)
    local r=self.route
    if not r then return end
    local ar,ag,ab=G:Style():Color("accent")
    local stale=r.stale and .5 or 1
    -- Ways round closer than 4 pixels to the point drawn before are left
    -- out of the lines (thousands of them on long routes made every redraw
    -- slow); stops and, while editing, every point stay.
    local spots={}
    local keepAll=self.tool=="edit"
    local lastX,lastY
    local n0=#r.points
    for i,point in ipairs(r.points) do
        local x,y=self:SpacePoint(point)
        if x then
            local bx,by=self:ToBoard(x,y)
            if keepAll or point.stop or point.drop or i==1 or i==n0 or not lastX or math.abs(bx-lastX)+math.abs(by-lastY)>=4 then
                spots[#spots+1]={bx,by,i};lastX,lastY=bx,by
            end
        end
    end
    local all={}
    for _,spot in ipairs(spots) do all[spot[3]]=spot end
    local n=#spots
    for i=1,n do
        local a,b=spots[i],spots[i+1] or (r.loop and n>2 and spots[1])
        if a and b then
            local l=take(lines)
            -- A piece that drops down a cliff in its own colour (jump here).
            local to=r.points[b[3]]
            local tint=(to and to.gap and G.Follow.GAP) or (to and to.drop and G.Follow.DROP)
            if tint then l:SetVertexColor(tint[1],tint[2],tint[3],stale) else l:SetVertexColor(ar,ag,ab,stale) end
            l:SetThickness(3)
            l.shadow:SetVertexColor(0,0,0,.6*stale);l.shadow:SetThickness(6)
            for _,line in ipairs({l,l.shadow}) do
                line:SetStartPoint("TOPLEFT",self.board,a[1],-a[2]);line:SetEndPoint("TOPLEFT",self.board,b[1],-b[2])
            end
        end
    end
    local ways=pool("ways",function() local t=E.board:CreateTexture(nil,"OVERLAY",nil,3);t:SetTexture(DISC);return t end)
    reset(ways)
    local number=0
    for i,point in ipairs(r.points) do
        if point.stop then number=number+1 end
        local spot=all[i]
        -- A way round is a small dot (no button), and only zoomed in: many of
        -- them made moving the map slow.
        if spot and not point.stop and self.tool~="edit" then
            if self.zoom>=1.5 then
                local t=take(ways)
                t:SetVertexColor(ar,ag,ab,.9*stale);t:SetSize(5,5)
                t:ClearAllPoints();t:SetPoint("CENTER",self.board,"TOPLEFT",spot[1],-spot[2])
            end
            spot=nil
        end
        if spot then
            local b=take(points)
            b.index,b.number.index=i,number
            local size=point.stop and 16 or 9
            b:SetSize(size,size);b:ClearAllPoints();b:SetPoint("CENTER",self.board,"TOPLEFT",spot[1],-spot[2])
            b.disc:SetVertexColor(.06,.06,.08,.9)
            b.dot:SetSize(size-6,size-6);b.dot:SetVertexColor(ar,ag,ab,1)
            b.number:SetText(point.stop and (number==1 and "1" or "") or "")
            b:EnableMouse(true)
        end
    end
    self:DrawIssues()
end
-- Difficult spots of the route (P.Issues): a warning sign each, with what
-- it is and what may help (Florian 2026-10-09: the player knows the place
-- and paints; the route improves on the next Calculate).
E.ISSUES={
    steep={"Steep ground","The way crosses ground the slope data calls too steep. If it is a cliff, paint No-go here; if there is a path, paint Preferred."},
    swim={"Swimming","The way swims here. Paint No-go to keep out of the water, or Preferred over a bridge or ford."},
    magma={"Magma or slime","The way touches magma or slime. Paint No-go here, or Preferred along a safe edge."},
    enemy={"Enemy base","The way passes an enemy base. Paint No-go to go round it, or a transition for a way past it."},
    risk={"High risk area","The way crosses your high-risk area: no other way was found. Paint Preferred where it is safe to pass."},
    detour={"Long way round","Two stops close together lie far apart on foot. If there is a shortcut (a ramp, a bridge, a tunnel), paint Preferred along it or add a transition."},
    highdrop={"High drop","The way jumps down further than \"Short drops\" allows: no other way was found. If there is a path down, paint Preferred along it; with Slow Fall set \"Down cliffs\" to Always."},
    gap={"No way found","No way between these stops in the terrain data. Plan it by hand: Preferred ground or a transition, then Calculate again."},
    cut={"Left out","The stops here cannot be reached (and left again). If there is a way up, paint Preferred along it or add a transition."},
}
E.ISSUECOLOR={1,.78,.2}
function E:DrawIssues()
    local signs=pool("issues",function()
        local b=CreateFrame("Button",nil,E.board);b:SetFrameLevel(E.board:GetFrameLevel()+7);b:SetSize(20,20)
        b.disc=b:CreateTexture(nil,"BACKGROUND");b.disc:SetAllPoints(b);b.disc:SetTexture(DISC);b.disc:SetVertexColor(.06,.06,.08,.9)
        b.icon=b:CreateTexture(nil,"ARTWORK");b.icon:SetPoint("CENTER",0,1);b.icon:SetSize(14,14)
        local path,l,r,t,bt=ns.Symbols:Coords("triangle-alert",32)
        if path then b.icon:SetTexture(path);b.icon:SetTexCoord(l,r,t,bt) end
        b:SetScript("OnEnter",function(self)
            local issue=self.issue
            local info=issue and E.ISSUES[issue.kind]
            if not info then return end
            local rows={}
            if issue.yards and issue.kind~="cut" then rows[#rows+1]={issue.kind=="detour" and "Extra way" or issue.kind=="highdrop" and "Fall up to" or "Length",issue.yards.." yd"} end
            if issue.kind=="cut" and issue.yards then rows[#rows+1]={"Nodes",tostring(issue.yards)} end
            UI:ShowTooltip(self,info[1],{tag="Difficult spot",tagColor=E.ISSUECOLOR,rows=rows,text=info[2]})
        end)
        b:SetScript("OnLeave",function(self) UI:HideTooltip(self) end)
        return b
    end)
    reset(signs)
    local r=self.route
    if not (r and r.issues) or r.stale then return end
    for _,issue in ipairs(r.issues) do
        local x,y=self:SpacePoint(issue)
        if x then
            local bx,by=self:ToBoard(x,y)
            local b=take(signs)
            b.issue=issue
            local c=issue.kind=="gap" and G.Follow.GAP or E.ISSUECOLOR
            b.icon:SetVertexColor(c[1],c[2],c[3],1)
            b:ClearAllPoints();b:SetPoint("CENTER",self.board,"TOPLEFT",bx,-by)
        end
    end
end
-- /bv gather profile (Florian 2026-10-09: the editor lags in the game):
-- the time of each drawing step, printed after every action over 5 ms with
-- the number of dots, lines and point buttons. Again: off.
E.PROFILED={"SetZones","Names","Layout","DrawNodes","DrawRoute","DrawPlaces","DrawRelief","DrawLinks","DrawArea","DrawHeat","Terrain","Tiles","RefreshSide","Chosen","Place"}
function E:Profile()
    local clock=rawget(_G,"debugprofilestop")
    if not clock then G:Print("No profiling clock in this client.");return end
    if self.unprofiled then
        for name,f in pairs(self.unprofiled) do self[name]=f end
        self.unprofiled=nil;G:Print("Editor profiling off.");return
    end
    self.unprofiled={}
    local depth,spent=0,{}
    for _,name in ipairs(E.PROFILED) do
        local f=self[name];self.unprofiled[name]=f
        self[name]=function(...)
            depth=depth+1
            local start=clock()
            local a,b,c=f(...)
            spent[name]=(spent[name] or 0)+clock()-start
            depth=depth-1
            if depth==0 then
                local total=clock()-start
                if total>5 then
                    local parts={}
                    for key,ms in pairs(spent) do if key~=name and ms>=1 then parts[#parts+1]=string.format("%s %.0f",key,ms) end end
                    table.sort(parts)
                    local p=E.pools
                    G:Print(string.format("%s %.0f ms (%s) dots %d, lines %d, points %d",name,total,table.concat(parts,", "),
                        p.dots and p.dots.used or 0,p.lines and p.lines.used or 0,p.points and p.points.used or 0))
                end
                spent={}
            end
            return a,b,c
        end
    end
    G:Print("Editor profiling on: open, zoom, move and choose, then send the lines. /bv gather profile again ends it.")
end
function E:PointTooltip(button)
    local point=self.route and self.route.points[button.index]
    if not point then return end
    local rows={{"Zone",self:ZoneName(point.mapID)}}
    if point.stop then rows[#rows+1]={"Nodes",tostring(point.count or 0)} end
    UI:ShowTooltip(button,point.stop and ("Stop "..button.number.index) or "Way round",{rows=rows,
        hint=self.tool=="edit" and "Drag to move, right-click to remove." or "Edit the route tool moves and removes points."})
end

-- Calculate, save, load, use --------------------------------------------------
function E:Calculate()
    if self.job or #self.zones==0 then return end
    local chosen={}
    for key,on in pairs(self.chosen) do if on then chosen[key]=true end end
    local c=G:Config()
    local start
    local mapID,x,y=G.Record:Position()
    if mapID then start={mapID=mapID,x=x,y=y} end
    local zones={unpack(self.zones)}
    local area=self.area
    local goal,sight,worth=c.routeGoal,c.sightRadius,c.worthLimit
    G.Plan.Report(0,"Starting")
    if self.progressTicker then self.progressTicker:Cancel() end
    self.progressTicker=C_Timer.NewTicker(.1,function() E:Status() end)
    self.job=Grid.Run(function() return G.Plan:Build(zones,chosen,{loop=c.loop,radius=c.passRadius,start=start,smooth=c.routeSmooth,area=area,goal=goal,sight=sight,worth=worth}) end,function(result)
        E.job=nil
        if E.progressTicker then E.progressTicker:Cancel();E.progressTicker=nil end
        if result then
            result.chosen,result.radius,result.area,result.sight=chosen,c.passRadius,area,sight
            E.route=result
        end
        E:Status();E:Layout()
    end)
    self:Status()
end
-- Stops the calculation; the route calculated before stays.
function E:Cancel()
    if not self.job then return false end
    self.job:Cancel();self.job=nil
    if self.progressTicker then self.progressTicker:Cancel();self.progressTicker=nil end
    G.Plan.Report(0,"")
    G:Print("Calculation cancelled.")
    self:Status()
    return true
end
function E:Save()
    if not self.route then G:Print("Calculate a route first.");return end
    local name=self.name:GetText()
    if not G.Plan:Save(name,self.route) then G:Print("Give the route a name.");return end
    self.current=name:gsub("^%s+",""):gsub("%s+$","")
    self.saved:SetLabelText(self.current)
    G:Print("Route saved: "..self.current..".")
end
function E:SavedOptions()
    local out={}
    for _,name in ipairs(G.Plan:Routes()) do out[#out+1]={value=name,label=G.Plan:Label(name)} end
    if #out==0 then out[1]={value="",label="No saved routes"} end
    return out
end
function E:Load(name)
    local saved=G.Plan:Load(name)
    if not saved then return end
    local route={points={},zones={},chosen={},loop=saved.loop,radius=saved.radius,length=saved.length}
    -- Jumps and legs without a way keep their colours (Florian 2026-10-09:
    -- a loaded route showed neither), and the status line counts them.
    route.drops,route.unreachable=0,0
    for i,point in ipairs(saved.points) do
        route.points[i]={mapID=point.mapID,x=point.x,y=point.y,stop=point.stop,count=point.count,drop=point.drop,gap=point.gap}
        if point.drop and not (saved.points[i-1] and saved.points[i-1].drop) then route.drops=route.drops+1 end
        if point.gap then route.unreachable=route.unreachable+1 end
    end
    for i,zone in ipairs(saved.zones) do route.zones[i]=zone end
    for key in pairs(saved.chosen or {}) do route.chosen[key]=true end
    route.area=saved.area;route.goal=saved.goal;route.sight=saved.sight
    if saved.issues then
        route.issues={}
        for i,issue in ipairs(saved.issues) do route.issues[i]={kind=issue.kind,mapID=issue.mapID,x=issue.x,y=issue.y,yards=issue.yards} end
    end
    if saved.goal then G:Config().routeGoal=saved.goal end
    if saved.sight then G:Config().sightRadius=saved.sight end
    self.area=saved.area;self.areaDraw=nil;self:AreaMode(false)
    self.current=name
    self.route=route
    if next(route.chosen) then self.chosen={} for key in pairs(route.chosen) do self.chosen[key]=true end end
    local c=G:Config()
    c.loop=route.loop and true or false
    if route.radius then c.passRadius=route.radius end
    if self.window and self.window:IsShown() then
        self.name:SetText(name);self.saved:SetLabelText(name)
        self.loop:SetValue(c.loop);self.radius:SetValue(c.passRadius)
    end
    self:SetZones(route.zones)
    self.route=route
    self:Status();self:Layout()
end
function E:Delete()
    if not self.current then return end
    G.Plan:Delete(self.current)
    G:Print("Route deleted: "..self.current..".")
    self.current=nil;self.saved:SetLabelText("Saved routes...")
end
function E:Follow()
    if not self.route then G:Print("Calculate a route first.");return end
    G.Follow:Start(self.current or "Route",self.route)
    if G.Mode then G.Mode:Refresh() end
end
function E:Export()
    if not self.route then G:Print("Calculate a route first.");return end
    G.Exchange:Open("routeExport",nil,G.Plan:Export(self.current or "Route",self.route))
end
-- An imported route (from the exchange dialog): saved under a free name and opened.
function E:Imported(name,route)
    local base,n=name,1
    while G.Plan:Load(name) do n=n+1;name=base.." "..n end
    G.Plan:Save(name,route)
    self:Open(route.zones)
    self:Load(name)
    G:Print("Route imported: "..name..".")
    return name
end
