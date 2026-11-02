local _,R=...
if not R.ready then return end
local ns=R.ns
local UI,M=ns.UI,ns.DesignSystem.Metrics
local W={rows={},page=1}
R.Arrivals=W
local WIDTH,HEIGHT,COUNT=570,450,6
local PEEKWIDTH=300
local function portID(port)
    if not port then return nil end
    local stop=port.route[port.side]
    return tostring(stop[1])..":"..stop[4]
end
function W:Dismiss()
    self.dismissed=self.near or self.port
    self.compactManual=nil
    self.outsideSince=nil
    if self.peek then self.peek:Hide() end
end
-- The automatic view is a compact, nonmodal card with its own saved anchor.
-- It must never inherit the manually opened full timetable's centre position.
function W:BuildPeek()
    if self.peek then return self.peek end
    local style=UI:InterfaceStyle();if not style then return nil end
    UI:WithStyle(style,function()
        local f=UI:Panel(UIParent,PEEKWIDTH,100,"panel",8,.86)
        f.bvStyle=style;f.bvTooltipStyle=style;f:SetFrameStrata("MEDIUM");f:EnableMouse(false)
        if ns.ExternalFrames then ns.ExternalFrames:MarkOwned(f) end
        f.drag=CreateFrame("Button",nil,f);M.Point(f.drag,"TOPLEFT",f,"TOPLEFT",0,0);M.Size(f.drag,PEEKWIDTH-60,32)
        UI:MakeMovable(f,f.drag,"BVRoutingPortCard")
        local function reset()
            f:ClearAllPoints();M.Point(f,"TOPLEFT",UIParent,"TOPLEFT",22,-170)
        end
        f.drag:SetScript("OnDoubleClick",function() reset();UI:SaveWindowPosition(f) end)
        if not UI:RestoreWindowPosition(f) then reset() end
        f.symbol=UI:Icon(f,"anchor",16,"accentText");M.Point(f.symbol,"TOPLEFT",f,"TOPLEFT",12,-9)
        f.title=UI:Label(f,"",12,"text",true);M.Point(f.title,"LEFT",f.symbol,"RIGHT",8,0);M.Size(f.title,PEEKWIDTH-104,20);f.title:SetWordWrap(false)
        f.expand=UI:IconButton(f,"book-open",function() W:Show() end,"icon-only");M.Size(f.expand,26,26);M.Point(f.expand,"TOPRIGHT",f,"TOPRIGHT",-30,-3)
        UI:AttachTooltip(f.expand,"Full timetable","Open all ports and both directions.")
        f.close=UI:IconButton(f,"x",function() W:Dismiss() end,"icon-only");M.Size(f.close,26,26);M.Point(f.close,"TOPRIGHT",f,"TOPRIGHT",-3,-3)
        UI:AttachTooltip(f.close,"Hide for this visit","Stays hidden until you leave this port. Drag the header to move the card.")
        f.rows={}
        for i=1,COUNT do
            local row=CreateFrame("Frame",nil,f);M.Point(row,"TOPLEFT",f,"TOPLEFT",12,-36-(i-1)*43);M.Size(row,PEEKWIDTH-24,40)
            row.ship=UI:Icon(row,"ship",18,"accentText");M.Point(row.ship,"TOPLEFT",row,"TOPLEFT",0,-2)
            row.zeppelin=UI:Icon(row,"plane",18,"accentText");row.zeppelin:SetAllPoints(row.ship)
            row.title=UI:Label(row,"",12,"text",true);M.Point(row.title,"TOPLEFT",row,"TOPLEFT",28,0);M.Size(row.title,PEEKWIDTH-52,18);row.title:SetWordWrap(false)
            row.time=UI:Label(row,"",11,"muted");M.Point(row.time,"TOPLEFT",row,"TOPLEFT",28,-19);M.Size(row.time,PEEKWIDTH-52,18);row.time:SetWordWrap(false)
            f.rows[i]=row
        end
        self.peek=f;f:Hide()
        if ns.InterfaceSurfaces and ns.InterfaceSurfaces.AttachHUD then ns.InterfaceSurfaces:AttachHUD(style,f) end
    end)
    return self.peek
end
function W:VisibleRoute(route)
    local faction=R.Navigate.Faction()
    return self.showAllFactions or faction==3 or not route.faction or route.faction==3 or route.faction==faction
end
function W:Entries(port,unfiltered)
    local entries={}
    for _,r in ipairs(R.TRANSPORTS or {}) do if r.kind~="tram" and (unfiltered or self:VisibleRoute(r)) then
        for _,side in ipairs({"a","b"}) do
            if not port or portID({route=r,side=side})==portID(port) then entries[#entries+1]={r,side} end
        end
    end end
    return entries
end
function W:Connections(port)
    local out,seen={},{}
    for _,entry in ipairs(self:Entries(port)) do
        local route=entry[1]
        if not seen[route] then seen[route]=true;out[#out+1]=route end
    end
    return out
end
function W:PortTime(route,side,now)
    local clock=R.Navigate.Clock
    local q=R.Timetable:Quote(route,side,now,nil,0)
    local incoming,approx,docked=R.Timetable:Incoming(route,side,now)
    local arrival=docked and "At dock" or incoming and ("Arr "..(approx and "~" or "")..clock(math.max(0,incoming-now))) or "Arr —"
    local departure=q.state=="scheduled" and ((q.approximate and "~" or "")..clock(q.wait)) or "—"
    return arrival.." · Dep "..departure
end
function W:PaintPeek(port)
    local f=self:BuildPeek();if not f then return end
    self.port=port
    f.title:SetText(port.route[port.side][4])
    local entries=self:Entries(port);local now=R.Timetable:Now();local clock=R.Navigate.Clock
    for i,row in ipairs(f.rows) do
        local item=entries[i];row:SetShown(item~=nil)
        if item then
            local r,side=item[1],item[2]
            row.ship:SetShown(r.kind=="ship");row.zeppelin:SetShown(r.kind=="zeppelin")
            row.title:SetText(r[side=="a" and "b" or "a"][4])
            local q=R.Timetable:Quote(r,side,now,nil,0)
            local arrival,approx,docked=R.Timetable:Incoming(r,side,now)
            local text
            if not arrival and q.state~="scheduled" then text="Times not known yet"
            else
                local a=docked and "At dock" or arrival and ("Arr "..(approx and "~" or "")..clock(math.max(0,arrival-now))) or "Arr —"
                local d=q.state=="scheduled" and ((q.approximate and "~" or "")..clock(q.wait)) or "—"
                text=a.."   ·   Dep "..d
            end
            row.time:SetText(text)
        end
    end
    M.Height(f,40+math.min(COUNT,#entries)*43)
    f:Show()
end
function W:Build()
    if self.window then return self.window end
    local style=UI:InterfaceStyle();if not style then return nil end
    UI:WithStyle(style,function()
        local w=UI:Window("BVRoutingArrivals",WIDTH,HEIGHT,{title="Ships & zeppelins",minWidth=WIDTH,minHeight=230,compact=true,gameplaySurface=true})
        self.window=w;w.bvStyle=style
        w:SetResizable(false);if w.resizeGrip then w.resizeGrip:Hide() end;if w.maximize then w.maximize:Hide() end
        local c=w.content
        self.heading=UI:Label(c,"",13,"text",true);M.Point(self.heading,"TOPLEFT",c,"TOPLEFT",14,-10);M.Size(self.heading,WIDTH-190,24)
        self.factions=UI:Button(c,"All factions",145,function()
            W.showAllFactions=not W.showAllFactions;W.page=1
            if W.near and not W:VisibleRoute(W.near.route) then W.near=nil end
            W:Refresh()
        end,"ghost");M.Point(self.factions,"TOPRIGHT",c,"TOPRIGHT",-14,-7);M.Height(self.factions,26)
        UI:AttachTooltip(self.factions,"Faction filter","Show your faction's connections and neutral services, or include the other faction. Observations are kept in either view.")
        self.note=UI:Label(c,"",11,"muted");M.Point(self.note,"TOPLEFT",c,"TOPLEFT",14,-36);M.Size(self.note,WIDTH-28,32);self.note:SetWordWrap(true)
        for i=1,COUNT do
            local row=CreateFrame("Frame",nil,c);M.Point(row,"TOPLEFT",c,"TOPLEFT",14,-78-(i-1)*44);M.Size(row,WIDTH-28,40)
            row.a=UI:Label(row,"",12,"text",true);M.Point(row.a,"TOPLEFT",row,"TOPLEFT",0,0);M.Size(row.a,190,20);row.a:SetWordWrap(false)
            row.b=UI:Label(row,"",12,"text",true);M.Point(row.b,"TOPRIGHT",row,"TOPRIGHT",0,0);M.Size(row.b,190,20);row.b:SetJustifyH("RIGHT");row.b:SetWordWrap(false)
            row.ship=UI:Icon(row,"ship",18,"accentText");M.Point(row.ship,"TOP",row,"TOP",0,-1)
            row.zeppelin=UI:Icon(row,"plane",18,"accentText");row.zeppelin:SetAllPoints(row.ship)
            row.left=UI:Label(row,"—",13,"accentText",true);M.Point(row.left,"TOP",row,"TOP",-37,0);M.Size(row.left,32,20);row.left:SetJustifyH("RIGHT")
            row.right=UI:Label(row,"—",13,"accentText",true);M.Point(row.right,"TOP",row,"TOP",37,0);M.Size(row.right,32,20)
            row.status=UI:Label(row,"",10,"muted");M.Point(row.status,"TOP",row,"TOP",0,-21);M.Size(row.status,90,17);row.status:SetJustifyH("CENTER")
            row.timeA=UI:Label(row,"",11,"muted");M.Point(row.timeA,"TOPLEFT",row,"TOPLEFT",0,-21);M.Size(row.timeA,220,18);row.timeA:SetWordWrap(false)
            row.timeB=UI:Label(row,"",11,"muted");M.Point(row.timeB,"TOPRIGHT",row,"TOPRIGHT",0,-21);M.Size(row.timeB,220,18);row.timeB:SetJustifyH("RIGHT");row.timeB:SetWordWrap(false)
            self.rows[i]=row
        end
        self.prev=UI:Button(c,"Previous",95,function() W.page=math.max(1,W.page-1);W:Refresh() end,"ghost");M.Point(self.prev,"BOTTOMLEFT",c,"BOTTOMLEFT",14,12)
        self.next=UI:Button(c,"Next",95,function() W.page=W.page+1;W:Refresh() end,"ghost");M.Point(self.next,"LEFT",self.prev,"RIGHT",8,0)
        self.compact=UI:Button(c,"Compact view",135,function() W:ShowCompact() end,"ghost");M.Point(self.compact,"LEFT",self.next,"RIGHT",8,0)
        UI:AttachTooltip(self.compact,"Compact view","Return to the small card for the nearby port. Available near a dock or zeppelin tower.")
        self.all=UI:Button(c,"All ports",120,function() W.manual=true;W.port=nil;W.page=1;W:Refresh() end);M.Point(self.all,"BOTTOMRIGHT",c,"BOTTOMRIGHT",-14,12)
        w.drag:HookScript("OnDragStop",function() UI:SaveWindowPosition(w) end)
        w:HookScript("OnHide",function() W:Dismiss();W.manual=nil end)
        if not UI:RestoreWindowPosition(w) then w:ClearAllPoints();w:SetPoint("CENTER",UIParent,"CENTER",0,40) end
        w:Hide()
    end)
    return self.window
end
function W:Show()
    local w=self:Build();if not w then return end
    self.compactManual=nil
    self.manual=true;self.port=nil;self.page=1
    if self.peek then self.peek:Hide() end
    w:Show();self:Refresh()
end
function W:ShowCompact()
    local port=self.near
    if not port then return end
    if self.window then self.window:Hide() end
    -- This is an explicit view switch, not dismissal of the harbour card.
    self.manual=nil;self.dismissed=nil;self.outsideSince=nil
    self.compactManual=portID(port)
    self:PaintPeek(port)
end
function W:Refresh()
    if not (self.window and self.window:IsShown()) then return end
    if self.near then self.compact:Enable() else self.compact:Disable() end
    local port=self.port;local entries=self:Connections(port)
    local pages=math.max(1,math.ceil(#entries/COUNT));self.page=math.max(1,math.min(pages,self.page))
    local visible=math.min(COUNT,math.max(1,#entries-(self.page-1)*COUNT))
    local paged=pages>1
    -- Keep the existing row spacing, but remove empty row slots and redundant
    -- page controls. Reflow only when content changes, not on each countdown.
    if self.layoutRows~=visible or self.layoutPaged~=paged then
        self.layoutRows,self.layoutPaged=visible,paged
        M.Height(self.window,HEIGHT-(COUNT-visible)*44)
        self.prev:SetShown(paged);self.next:SetShown(paged)
        self.compact:ClearAllPoints()
        if paged then M.Point(self.compact,"LEFT",self.next,"RIGHT",8,0)
        else M.Point(self.compact,"BOTTOMLEFT",self.window.content,"BOTTOMLEFT",14,12) end
    end
    self.all:SetShown(port~=nil)
    local faction=R.Navigate.Faction()
    local scope=self.showAllFactions or faction==3
    if faction==3 then self.factions:Disable() else self.factions:Enable() end
    self.factions:SetText(self.showAllFactions and "My faction" or "All factions")
    self.heading:SetText((port and ("Near "..port.route[port.side][4]) or "All ports").." · "..(scope and "All factions" or faction==1 and "Horde + neutral" or "Alliance + neutral")..(paged and (" · "..self.page.."/"..pages) or ""))
    self.note:SetText("One row per connection. Arrows show estimated travel direction. ~ = estimate; — = no timing reference. Times learn while you ride.")
    local now=R.Timetable:Now()
    for i,row in ipairs(self.rows) do
        local item=entries[(self.page-1)*COUNT+i]
        row:SetShown(item~=nil)
        if item then
            local r=item;local journey=R.Timetable:Journey(r,now)
            row.a:SetText(r.a[4]);row.b:SetText(r.b[4])
            row.a:SetTextColor(self.window.bvStyle:Color(journey.state=="docked" and journey.side=="a" and "accentText" or "text"))
            row.b:SetTextColor(self.window.bvStyle:Color(journey.state=="docked" and journey.side=="b" and "accentText" or "text"))
            row.ship:SetShown(r.kind=="ship");row.zeppelin:SetShown(r.kind=="zeppelin")
            row.left:SetText(journey.state=="underway" and journey.side=="b" and "←" or "—")
            row.right:SetText(journey.state=="underway" and journey.side=="a" and "→" or "—")
            row.status:SetText(journey.state=="underway" and "Underway ~" or journey.state=="docked" and "Docked ~" or "Unknown")
            row.timeA:SetText(self:PortTime(r,"a",now));row.timeB:SetText(self:PortTime(r,"b",now))
        end
    end
    if self.page>1 then self.prev:Enable() else self.prev:Disable() end
    if self.page<pages then self.next:Enable() else self.next:Disable() end
end
function W:StillInPort(port,cont,x,y)
    for _,entry in ipairs(self:Entries(port,true)) do
        local r,side=entry[1],entry[2];local p=r[side]
        local boarding=side=="a" and r.boardingA or r.boardingB
        if p[1]==cont and R.Navigate.Yards(cont,x,y,boarding and boarding[1] or p[2],boarding and boarding[2] or p[3])<=110 then return true end
    end
    return false
end
function W:Tick(cont,x,y,now)
    now=now or R.Timetable:Now()
    -- Missing coordinates are not evidence of leaving a harbour.
    if not cont or not (R.Timetable.Number(x) and R.Timetable.Number(y)) then
        self.outsideSince=nil
        if self.peek then self.peek:Hide() end
        self:Refresh();return
    end
    local near=R.Timetable:Nearest(cont,x,y,self.near and 110 or 75,function(route) return W:VisibleRoute(route) end)
    self.near=near
    if self.compactManual~=portID(near) then self.compactManual=nil end
    if self.dismissed then
        if self:StillInPort(self.dismissed,cont,x,y) then self.outsideSince=nil
        else
            self.outsideSince=self.outsideSince or now
            if now-self.outsideSince>=3 then self.dismissed=nil;self.outsideSince=nil end
        end
    end
    if not self.manual then
        local show=(self.compactManual or R:Config().transportAutoShow==true) and near and portID(self.dismissed)~=portID(near)
        if show then self:PaintPeek(near)
        elseif self.peek then self.peek:Hide() end
    end
    self:Refresh()
end
if ns.Launcher and ns.Launcher.AddEntry then
    ns.Launcher:AddEntry({id="arrivals",label="Ships & zeppelins",order=46,group="navigation",icon="ship",onClick=function() W:Show() end})
end
