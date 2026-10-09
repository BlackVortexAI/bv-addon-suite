local _,Q=...
if not Q.ready then return end
-- The panes: our rail, list and details beside Blizzard's world map. The map
-- itself is never replaced or resized (Questie, HereBeDragons pins and other
-- map addons keep working); our panes are frames parented to WorldMapFrame,
-- docked flush outside its left or right edge in the configured order
-- (default Map · List · Details, Florian 2026-10-07). A full-height rail sits
-- directly at the map on the list's side and carries the switches that were
-- Blizzard's tabs (quest log, events, map legend), so no gap shows.
-- Splitters between neighbours change the width of our panes. Details appear
-- only for a selected quest and widen the whole (the map does not move).
local ns=Q.ns
local UI,M=ns.UI,ns.DesignSystem.Metrics
local P={}
Q.Panes=P
local RAIL=34

function P:Map() return rawget(_G,"WorldMapFrame") end
function P:Panel() return rawget(_G,"QuestMapFrame") end
function P:Visible() local map=self:Map();return self.frame~=nil and map~=nil and map:IsShown() and self.frame:IsShown() end
function P:Order()
    local order={}
    for id in Q:Config().order:gmatch("[^,]+") do order[#order+1]=id end
    return order
end

-- Blizzard's side panel (QuestMapFrame: its quest list, events, map legend).
-- Opened and closed only through the map's own controls: the Retail method
-- when present, else WoW Forever's toggle buttons (SidePanelToggle.Open/CloseButton).
local function toggleSide(map,open)
    if type(map.HandleUserActionToggleSidePanel)=="function" then return pcall(map.HandleUserActionToggleSidePanel,map) end
    local toggle=map.SidePanelToggle
    local button=toggle and (open and toggle.OpenButton or toggle.CloseButton)
    if button and button.Click then return pcall(button.Click,button) end
    return false
end
-- Closes Blizzard's list while ours is shown (option, default on). Blizzard
-- opens its panel after the map's OnShow, so this also runs when the panel
-- appears; a panel the player opened for events or the legend stays.
function P:CloseBlizzard()
    local map,panel=self:Map(),self:Panel()
    if not (map and panel) or self.blizzardMode or not Q:Config().hideBlizzard or not self:Visible() then return end
    if panel:IsShown() and toggleSide(map,false) then self.closedBlizzard=true end
end
function P:RestoreBlizzard()
    local map,panel=self:Map(),self:Panel()
    if map and panel and self.closedBlizzard and not panel:IsShown() then toggleSide(map,true) end
    self.closedBlizzard=nil
end
-- Rail button "Blizzard's side panel": opens it as it is, with all its tabs
-- (Blizzard's and other addons', e.g. a search tab); our list makes room.
-- Which tabs exist on WoW Forever is not known in advance (Florian's
-- screenshot 2026-10-07), so none is rebuilt here.
function P:OpenBlizzard()
    local map,panel=self:Map(),self:Panel()
    if not (map and panel) then return end
    self.blizzardMode="panel"
    if not panel:IsShown() then toggleSide(map,true) end
    self:Layout()
end
-- Blizzard's panel tabs (and those other addons add, e.g. a search tab) sit
-- outside the map's right edge, where our rail is. While the panel is shown
-- they move into our rail below its own buttons, scaled to its width, and
-- keep working; when it closes, or the module turns off, every tab goes back
-- to its own place (Florian's screenshots 2026-10-07: floating tabs, a gap).
local function points(frame)
    local out={}
    local count=type(frame.GetNumPoints)=="function" and frame:GetNumPoints() or #(frame.points or {})
    for i=1,count do out[i]={frame:GetPoint(i)} end
    return out
end
function P:Tabs()
    local map,panel=self:Map(),self:Panel()
    local found={}
    if not (map and panel and panel:IsShown()) or type(map.GetRight)~="function" then return found end
    local right=map:GetRight()
    if type(right)~="number" then return found end
    local function scan(frame)
        for _,child in ipairs({frame:GetChildren()}) do
            if child~=self.frame and child:IsShown() and not (self.adopted and self.adopted[child]) and type(child.GetRight)=="function" then
                local ok,r=pcall(child.GetRight,child)
                if ok and type(r)=="number" and r>right+2 and r<right+200 then found[#found+1]=child end
            end
        end
    end
    scan(panel);scan(map)
    return found
end
function P:AdoptTabs()
    self.adopted=self.adopted or {}
    self.adoptedOrder=self.adoptedOrder or {}
    for _,tab in ipairs(self:Tabs()) do
        self.adopted[tab]={points=points(tab),scale=tab:GetScale(),level=tab:GetFrameLevel()}
        self.adoptedOrder[#self.adoptedOrder+1]=tab
    end
    local y=6+#self.railButtons*(RAIL-2)+6
    for _,tab in ipairs(self.adoptedOrder) do
        if self.adopted[tab] then
            local width=M.GetWidth(tab)
            local scale=width>0 and math.min(1,(RAIL-4)/width) or 1
            tab:SetScale(scale)
            tab:ClearAllPoints();tab:SetPoint("TOP",self.rail,"TOP",0,-M.ToNative(y)/scale)
            tab:SetFrameLevel(self.rail:GetFrameLevel()+3)
            y=y+M.GetHeight(tab)*scale+4
        end
    end
end
function P:ReleaseTabs()
    for _,tab in ipairs(self.adoptedOrder or {}) do
        local saved=self.adopted[tab]
        if saved then
            tab:ClearAllPoints()
            for _,point in ipairs(saved.points) do tab:SetPoint(unpack(point)) end
            tab:SetScale(saved.scale or 1);tab:SetFrameLevel(saved.level or tab:GetFrameLevel())
        end
    end
    self.adopted,self.adoptedOrder=nil,nil
end
function P:Build()
    if self.frame then return self.frame end
    local map=self:Map()
    if not map then return nil end
    -- Built in the module's in-game style: panes, controls and lists follow it.
    return UI:WithStyle(Q:Style(),function()
        local f=CreateFrame("Frame",nil,map);f:SetAllPoints(map);f:EnableMouse(false)
        if ns.ExternalFrames then ns.ExternalFrames:MarkOwned(f) end
        self.frame=f
        local function opacity() return Q:Config().opacity/100 end
        self.rail=UI:GamePanel(Q.ID,f,RAIL,400,"bg",2,opacity);self.rail:EnableMouse(true)
        self.railButtons={
            self:RailButton("quests","scroll-text","Quest log","Shows or hides the quest list; from Blizzard's side panel back to ours."),
            self:RailButton("blizzard","book-open","Blizzard's side panel","Blizzard's panel beside the map with its own tabs (map legend and others); our list makes room."),
        }
        self.list=UI:GamePanel(Q.ID,f,300,400,"bg",2,opacity);self.list:EnableMouse(true)
        self.details=UI:GamePanel(Q.ID,f,320,400,"bg",2,opacity);self.details:EnableMouse(true);self.details:Hide()
        self.splitters={}
        for i=1,2 do self.splitters[i]=self:Splitter() end
        Q.List:Build(self.list)
        Q.Details:Build(self.details)
        map:HookScript("OnShow",function() if Q:Active() then P:Show() end end)
        map:HookScript("OnHide",function() P:Hide() end)
        local panel=self:Panel()
        if panel then
            -- Closed again unless opened from the rail; the rail moves with its tabs.
            panel:HookScript("OnShow",function() if Q:Active() then C_Timer.NewTimer(0,function() P:CloseBlizzard();if P:Visible() then P:Layout() end end) end end)
            panel:HookScript("OnHide",function() P.blizzardMode=nil;P:ReleaseTabs();if P:Visible() then P:Layout() end end)
            -- Blizzard may place its tabs again when its panel switches mode: back into the rail.
            if type(panel.SetDisplayMode)=="function" and hooksecurefunc then
                hooksecurefunc(panel,"SetDisplayMode",function() if P:Visible() and P.adopted then P:Layout() end end)
            end
        end
        return f
    end)
end
function P:RailButton(id,symbol,title,help)
    local b=CreateFrame("Button",nil,self.rail);M.Size(b,RAIL-6,RAIL-6)
    b.band=b:CreateTexture(nil,"BACKGROUND");b.band:SetAllPoints(b);b.band:SetTexture("Interface\\Buttons\\WHITE8X8")
    b.icon=b:CreateTexture(nil,"ARTWORK");b.icon:SetPoint("CENTER");M.Size(b.icon,18,18)
    local path,l,r,t,bb=ns.Symbols:Coords(symbol,64)
    if path then b.icon:SetTexture(path);b.icon:SetTexCoord(l,r,t,bb) end
    b.id=id
    b:SetScript("OnClick",function() P:Rail(id) end)
    b:SetScript("OnEnter",function() b.hovered=true;P:PaintRail();UI:ShowTooltip(b,title,help) end)
    b:SetScript("OnLeave",function() b.hovered=false;P:PaintRail();UI:HideTooltip(b) end)
    return b
end
function P:Rail(id)
    if id=="quests" then
        -- Back from Blizzard's events or legend to our list, or our list on/off.
        if self.blizzardMode then self.blizzardMode=nil;self.listHidden=false;self:CloseBlizzard()
        else self.listHidden=not self.listHidden end
        self:Layout()
    else self:OpenBlizzard(id) end
end
function P:PaintRail()
    local s=Q:Style()
    local ar,ag,ab=s:Color("accent")
    for _,b in ipairs(self.railButtons or {}) do
        local active=(b.id=="quests" and not self.listHidden and not self.blizzardMode) or (b.id=="blizzard" and self.blizzardMode~=nil)
        b.band:SetVertexColor(ar,ag,ab,active and .22 or b.hovered and .1 or 0)
        local r,g,bl=s:Color(active and "accent" or "muted")
        b.icon:SetVertexColor(r,g,bl,1)
    end
end
-- A grip between two neighbouring panes: dragging changes the own pane's width.
-- Mouse tracking: a short ticker only while dragging (the project uses no
-- frame-update scripts). It also ends when the button is no longer held: a
-- release outside the thin grip never reaches its OnMouseUp (Florian 2026-10-07).
function P:Splitter()
    local s=CreateFrame("Button",nil,self.frame);s:SetFrameLevel(self.frame:GetFrameLevel()+5)
    M.Width(s,6);s:EnableMouse(true)
    s.line=s:CreateTexture(nil,"OVERLAY");s.line:SetPoint("TOP");s.line:SetPoint("BOTTOM");M.Width(s.line,2)
    s.line:SetTexture("Interface\\Buttons\\WHITE8X8");s.line:SetVertexColor(1,1,1,0)
    s:SetScript("OnEnter",function() local r,g,b=Q:Style():Color("accent");s.line:SetVertexColor(r,g,b,.8) end)
    s:SetScript("OnLeave",function() if not s.dragging then s.line:SetVertexColor(1,1,1,0) end end)
    s:SetScript("OnMouseDown",function(_,button)
        if button~="LeftButton" or not s.pane then return end
        local x=GetCursorPosition()
        s.dragging={x=x/s:GetEffectiveScale(),width=Q:Config()[s.key]}
        if s.ticker then s.ticker:Cancel() end
        s.ticker=C_Timer.NewTicker(.02,function() P:Drag(s) end)
    end)
    s:SetScript("OnMouseUp",function() P:EndDrag(s) end)
    -- Double-click: the pane's default width.
    s:SetScript("OnDoubleClick",function() if s.key then Q:Config()[s.key]=Q.DEFAULTS[s.key];P:Layout() end end)
    return s
end
function P:Drag(s)
    local d=s.dragging
    if not d then return end
    if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then self:EndDrag(s);return end
    local x=GetCursorPosition()/s:GetEffectiveScale()
    -- A pane left of the map grows when dragged left, one right of it when dragged right.
    local delta=M.ToDesign(x-d.x)*(s.side=="left" and -1 or 1)
    Q:Config()[s.key]=math.max(200,math.min(600,math.floor(d.width+delta+.5)))
    self:Layout()
end
function P:EndDrag(s)
    s.dragging=nil;if s.ticker then s.ticker:Cancel();s.ticker=nil end;s.line:SetVertexColor(1,1,1,0)
end
-- Places rail and panes in order around the map, flush (no gap); hidden
-- panes take no room. The rail sits at the map on the list's side.
function P:Layout()
    if not self.frame then return end
    local cfg,map=Q:Config(),self:Map()
    local order=self:Order()
    local mapAt,listAt
    for i,id in ipairs(order) do if id=="map" then mapAt=i elseif id=="list" then listAt=i end end
    local railSide=listAt<mapAt and "left" or "right"
    local panes={list=self.list,details=self.details}
    local widths={list=cfg.listWidth,details=cfg.detailsWidth}
    local shown={list=not self.listHidden and not self.blizzardMode,details=Q.Details.questID~=nil}
    for _,s in ipairs(self.splitters) do s:Hide();s.pane=nil end
    local used=0
    local function attach(frame,side,previous)
        frame:ClearAllPoints()
        if side=="left" then M.Point(frame,"TOPRIGHT",previous,"TOPLEFT",0,0);M.Point(frame,"BOTTOMRIGHT",previous,"BOTTOMLEFT",0,0)
        else M.Point(frame,"TOPLEFT",previous,"TOPRIGHT",0,0);M.Point(frame,"BOTTOMLEFT",previous,"BOTTOMRIGHT",0,0) end
    end
    local function place(id,side,previous)
        local pane=panes[id]
        attach(pane,side,previous);M.Width(pane,widths[id])
        used=used+1
        local s=self.splitters[used]
        if s then
            s:ClearAllPoints();s.pane,s.key,s.side=pane,id.."Width",side
            -- On the pane's outer edge, where dragging makes it wider or narrower.
            if side=="left" then M.Point(s,"TOPLEFT",pane,"TOPLEFT",-3,0);M.Point(s,"BOTTOMLEFT",pane,"BOTTOMLEFT",-3,0)
            else M.Point(s,"TOPRIGHT",pane,"TOPRIGHT",3,0);M.Point(s,"BOTTOMRIGHT",pane,"BOTTOMRIGHT",3,0) end
            s:Show()
        end
        return pane
    end
    attach(self.rail,railSide,map);M.Width(self.rail,RAIL)
    -- Blizzard's panel open: its tabs into the rail (right of the map, where they sit).
    local panel=self:Panel()
    if railSide=="right" and panel and panel:IsShown() then self:AdoptTabs() elseif self.adopted then self:ReleaseTabs() end
    for i,b in ipairs(self.railButtons) do b:ClearAllPoints();M.Point(b,"TOP",self.rail,"TOP",0,-6-(i-1)*(RAIL-2)) end
    self:PaintRail()
    -- Each side walks outwards from the map; the rail comes first on its side.
    local previous=railSide=="left" and self.rail or map
    for i=mapAt-1,1,-1 do local id=order[i];if shown[id] then previous=place(id,"left",previous) else panes[id]:Hide() end end
    previous=railSide=="right" and self.rail or map
    for i=mapAt+1,#order do local id=order[i];if shown[id] then previous=place(id,"right",previous) else panes[id]:Hide() end end
    self.list:SetShown(shown.list);self.details:SetShown(shown.details)
    Q.List:Layout();Q.Details:Layout()
end
function P:Show()
    local f=self:Build()
    if not f then return end
    f:Show()
    self:Layout()
    Q:Refresh()
    -- Blizzard opens its panel after the map's OnShow: close it a moment later.
    C_Timer.NewTimer(0,function() P:CloseBlizzard() end)
    -- Distances change while you walk: re-read every 2 s, only while shown.
    if not self.clock then self.clock=C_Timer.NewTicker(2,function() if P:Visible() then Q:Dirty() end end) end
end
function P:Hide()
    self:ReleaseTabs()
    if self.frame then self.frame:Hide() end
    self.blizzardMode=nil
    if self.clock then self.clock:Cancel();self.clock=nil end
end
function P:Enable(context)
    local map=self:Map()
    if not map then Q:Print("No world map frame found; the quest log stays off.");return end
    self:Build()
    Q:On("Changed",self,function() if P:Visible() then Q.List:Refresh();Q.Details:Refresh() end end)
    context:Defer(function()
        Q.Details:Select(nil)
        P:ReleaseTabs();P:Hide();P:RestoreBlizzard()
    end)
    if map:IsShown() then self:Show() end
end
