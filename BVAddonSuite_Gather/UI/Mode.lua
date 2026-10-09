local _,G=...
if not G.ready then return end
-- Gather mode (Florian 2026-10-09): one switch for everything you use while
-- gathering, and a small window to run it (like AuraStudio's quick access).
-- Off: the route you follow leaves the map and the minimap (it stays chosen
-- and comes back when the mode is on). The window picks and starts a route,
-- switches the node kinds and the route lines, opens the route editor.
local ns=G.ns
local UI,M=ns.UI,ns.DesignSystem.Metrics
local H={}
G.Mode=H
local WIDTH=270
local HEIGHT=410

function H:On() return G:Active() and G:Config().mode==true end
function H:Set(on)
    G:Config().mode=on and true or false
    if not on and G.Hud then G.Hud:Hide() end
    if on and G.Follow:Active() then G.Follow:Watch(true) else G.Follow:Watch(false) end
    if G.Sight then G.Sight:Update() end
    G:Changed()
    if ns.Launcher and ns.Launcher.Refresh then ns.Launcher:Refresh() end
    self:Refresh()
end
function H:Toggle() self:Set(not self:On()) end

function H:Build()
    if self.window then return self.window end
    UI:WithStyle(G:Style(),function()
        local w=UI:Window("BVGatherMode",WIDTH,HEIGHT,{title="Gather mode",minWidth=WIDTH,minHeight=HEIGHT,compact=true})
        -- A fixed size (Florian 2026-10-09: resizing made no sense here).
        w:SetResizable(false);if w.resizeGrip then w.resizeGrip:Hide() end;if w.maximize then w.maximize:Hide() end
        -- Escape does not close it: it is a tool you keep open while playing.
        for i=#UISpecialFrames,1,-1 do if UISpecialFrames[i]=="BVGatherMode" then table.remove(UISpecialFrames,i) end end
        self.window=w
        local c=w.content
        local y=-8
        local function row(title,control,help)
            local l=UI:Label(c,title,12,"text");M.Point(l,"TOPLEFT",c,"TOPLEFT",12,y-2);M.Size(l,150,20)
            M.Point(control,"TOPRIGHT",c,"TOPRIGHT",-12,y)
            if help then UI:AttachTooltip(control,title,help) end
            y=y-28
            return control
        end
        self.mode=row("Gather mode",UI:Switch(c,false,function(value) H:Set(value) end),
            "Off: the route leaves the map and the minimap; it comes back when you switch the mode on.")
        y=y-4
        local heading=UI:Label(c,"Route",12,"accent",true);M.Point(heading,"TOPLEFT",c,"TOPLEFT",12,y);y=y-22
        self.route=UI:Dropdown(c,WIDTH-24,{},function(value) H.chosen=value end);M.Point(self.route,"TOPLEFT",c,"TOPLEFT",12,y);y=y-38
        self.route:SetOptionsProvider(function() return H:RouteOptions() end)
        self.start=UI:Button(c,"Follow",(WIDTH-30)/2,function() H:Follow() end,true);M.Point(self.start,"TOPLEFT",c,"TOPLEFT",12,y)
        self.stop=UI:Button(c,"Stop",(WIDTH-30)/2,function() G.Follow:Stop();H:Refresh() end,"ghost");M.Point(self.stop,"TOPRIGHT",c,"TOPRIGHT",-12,y)
        y=y-38
        self.status=UI:Label(c,"",11,"muted");M.Point(self.status,"TOPLEFT",c,"TOPLEFT",12,y);M.Size(self.status,WIDTH-24,30);self.status:SetWordWrap(true)
        y=y-32
        local show=UI:Label(c,"Show",12,"accent",true);M.Point(show,"TOPLEFT",c,"TOPLEFT",12,y);y=y-22
        self.kinds={}
        for i,t in ipairs(G.TYPES) do
            local col=(i-1)%2
            local box=CreateFrame("Frame",nil,c);M.Size(box,(WIDTH-24)/2,24)
            M.Point(box,"TOPLEFT",c,"TOPLEFT",12+col*((WIDTH-24)/2),y-math.floor((i-1)/2)*26)
            box.switch=UI:Switch(box,false,function(value) G:Config()[t.id]=value;G:Changed();H:Refresh() end);M.Point(box.switch,"LEFT",box,"LEFT",0,0)
            box.label=UI:Label(box,t.label,11,"text");M.Point(box.label,"LEFT",box,"LEFT",42,0);M.Size(box.label,(WIDTH-24)/2-44,24)
            box.label:SetTextColor(unpack(G:Color(t.id)))
            self.kinds[t.id]=box
        end
        y=y-56
        self.lines=row("Route lines",UI:Switch(c,true,function(value) G:Config().routeLines=value;G:Changed();H:Refresh() end),
            "The route's lines and arrows; off: only its points.")
        self.hud=row("HUD",UI:Switch(c,false,function(value) if value then G.Hud:Show() else G.Hud:Hide() end;H:Refresh() end),
            "The minimap large and see-through in the middle of the screen, with the yellow dots of Find Herbs and Find Minerals; the mouse passes through.")
        self.editor=UI:Button(c,"Route editor",(WIDTH-30)/2,function() G.Editor:Toggle() end,"ghost");M.Point(self.editor,"TOPLEFT",c,"TOPLEFT",12,y)
        self.tracker=UI:Button(c,"Tracker",(WIDTH-30)/2,function() G.TrackerWindow:Show() end,"ghost");M.Point(self.tracker,"TOPRIGHT",c,"TOPRIGHT",-12,y)
        w.drag:HookScript("OnDragStop",function() UI:SaveWindowPosition(w) end)
        w:HookScript("OnShow",function() H:Refresh() end)
        if not UI:RestoreWindowPosition(w) then w:ClearAllPoints();w:SetPoint("RIGHT",UIParent,"RIGHT",-120,60) end
        w:Hide()
    end)
    return self.window
end
function H:Show(on)
    local w=self:Build()
    if on==nil then on=not w:IsShown() end
    G:Config().modeWindow=on and true or false
    w:SetShown(on)
end
function H:RouteOptions()
    local out={}
    for _,name in ipairs(G.Plan:Routes()) do out[#out+1]={value=name,label=G.Plan:Label(name)} end
    if #out==0 then out[1]={value="",label="No saved routes (route editor)"} end
    return out
end
function H:Follow()
    local name=self.chosen
    local route=name and name~="" and G.Plan:Load(name)
    if not route then G:Print("Choose a saved route first (or build one in the route editor).");return end
    G.Follow:Start(name,route)
    self:Refresh()
end
function H:Refresh()
    local w=self.window
    if not (w and w:IsShown()) then return end
    local c=G:Config()
    self.mode:SetValue(c.mode)
    self.lines:SetValue(c.routeLines)
    self.hud:SetValue(G.Hud:On())
    for id,box in pairs(self.kinds) do box.switch:SetValue(c[id]) end
    local state=G.Follow:State()
    if state then
        self.chosen=self.chosen or state.name
        local count=0;for _,point in ipairs(state.points) do if point.stop then count=count+1 end end
        self.status:SetText(string.format("Following %s: %d stops%s.%s",state.name,count,state.loop and ", loop" or "",c.mode and "" or " Hidden while the mode is off."))
    else self.status:SetText("No route followed.") end
    self.route:SetLabelText(self.chosen and self.chosen~="" and G.Plan:Label(self.chosen) or "Choose a route...")
    if state then self.stop:Enable() else self.stop:Disable() end
end
-- Quick menu of the minimap launcher (Core): gather mode, its window, the editor.
if ns.Launcher and ns.Launcher.AddEntry then
    ns.Launcher:AddEntry({id="gathermode",label="Gather mode",order=30,shown=function() return G:Active() end,
        state=function() return G:Config().mode==true end,onClick=function() H:Toggle() end})
    ns.Launcher:AddEntry({id="gatherwindow",label="Gather window",order=31,shown=function() return G:Active() end,onClick=function() H:Show() end})
    ns.Launcher:AddEntry({id="routeeditor",label="Route editor",order=32,shown=function() return G:Active() end,onClick=function() G.Editor:Toggle() end})
    ns.Launcher:AddEntry({id="gathertracker",label="Gather tracker",order=33,shown=function() return G:Active() end,onClick=function() G.TrackerWindow:Show() end})
    ns.Launcher:AddEntry({id="gatherwiki",label="Gather wiki",order=35,shown=function() return G:Active() end,onClick=function() G.Wiki:Open() end})
    ns.Launcher:AddEntry({id="gatherhud",label="Gather HUD",order=34,shown=function() return G:Active() end,state=function() return G.Hud:On() end,onClick=function() G.Hud:Toggle() end})
end
function H:Enable(context)
    if G:Config().modeWindow then self:Show(true) end
    context:Defer(function() if H.window then H.window:Hide() end end)
end
