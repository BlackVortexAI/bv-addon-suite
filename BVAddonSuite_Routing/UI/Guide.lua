local _,Routing=...
if not Routing.ready then return end
-- The guide while a way is followed (Florian 2026-10-12): an arrow to the
-- next point of the way in a round medallion; what to do now in large (the
-- yards left of a walk, or the transition by its kind and name: "Take the
-- lift", "Lift 2 - to Lower Hall"), under a line what comes after it and
-- the time left to the goal. Beside the tour window when that is open
-- (right or left), or undocked where you drag it; the background may be
-- hidden. Right-click for these; /bv route guide left|right|free|off.
-- Built when first needed; its ticker runs only while it is shown.
local ns=Routing.ns
local UI,M=ns.UI,ns.DesignSystem.Metrics
local G={}
Routing.Guide=G
G.WIDTH,G.HEIGHT=320,134
G.EVERY=.05
G.GAP=8
local MEDIA="Interface\\AddOns\\BVAddonSuite\\Media\\DesignLab\\"

local function style() return UI:GameStyle(nil) end
local function color(key,alpha)
    local r,g,b=style():Color(key)
    return r,g,b,alpha or 1
end
-- A Lucide symbol on a texture (changed as the step changes).
local function symbol(texture,name,size)
    local path,l,r,t,b=ns.Symbols:Coords(name,size or 32)
    if path then texture:SetTexture(path);texture:SetTexCoord(l,r,t,b) end
end
function G:Build()
    if self.frame then return self.frame end
    UI:WithStyle(style(),function()
        local f=UI:Panel(UIParent,G.WIDTH,G.HEIGHT,"panel",12,.95)
        f:Hide();f:SetFrameStrata("DIALOG");f:SetClampedToScreen(true)
        f:SetMovable(true);f:EnableMouse(true);f:RegisterForDrag("LeftButton")
        if ns.ExternalFrames then ns.ExternalFrames:MarkOwned(f) end
        f:SetScript("OnDragStart",function(self) G:Undock();self:StartMoving() end)
        f:SetScript("OnDragStop",function(self) self:StopMovingOrSizing();G:Keep() end)
        f:SetScript("OnMouseUp",function(self,button) if button=="RightButton" then G:Menu(self) end end)
        -- The medallion: a faint disc, a ring, the arrow.
        f.medal=CreateFrame("Frame",nil,f);M.Size(f.medal,64,64);M.Point(f.medal,"TOPLEFT",f,"TOPLEFT",16,-16)
        f.disc=f.medal:CreateTexture(nil,"BACKGROUND");f.disc:SetTexture(MEDIA.."radio-dot.tga");f.disc:SetAllPoints(f.medal)
        f.ring=f.medal:CreateTexture(nil,"BORDER");f.ring:SetTexture(MEDIA.."radio-ring.tga");f.ring:SetAllPoints(f.medal)
        f.arrow=f.medal:CreateTexture(nil,"OVERLAY");symbol(f.arrow,"navigation",64)
        M.Size(f.arrow,32,32);M.Point(f.arrow,"CENTER",f.medal,"CENTER",0,0)
        -- Now: what kind of step, the step count, what to do, where to.
        local x=96
        f.kind=f:CreateTexture(nil,"OVERLAY");M.Size(f.kind,12,12);M.Point(f.kind,"TOPLEFT",f,"TOPLEFT",x,-17)
        f.head=UI:Label(f,"",10,"muted",true);M.Point(f.head,"LEFT",f.kind,"RIGHT",5,0)
        -- Two small quiet buttons top right (Florian 2026-10-14): end the
        -- way, and search it anew from here (far off the way); the count
        -- beside them.
        f.stop=UI:IconButton(f,"x",function() Routing.Navigate:Stop() end,"ghost")
        M.Size(f.stop,20,20);M.Point(f.stop,"TOPRIGHT",f,"TOPRIGHT",-10,-10)
        UI:AttachTooltip(f.stop,"End the way","Ends the way and the guide (/bv route stop).")
        f.restart=UI:IconButton(f,"rotate-cw",function() Routing.Navigate:Restart() end,"ghost")
        M.Size(f.restart,20,20);M.Point(f.restart,"RIGHT",f.stop,"LEFT",-4,0)
        UI:AttachTooltip(f.restart,"Search anew","The way to the same goal searched again from where you are now.")
        -- The log and the whole way as text (Florian 2026-10-14).
        f.export=UI:IconButton(f,"clipboard",function() ns.UI:DiagnosticReport("Routing: the way",Routing.Navigate:ExportText()) end,"ghost")
        M.Size(f.export,20,20);M.Point(f.export,"RIGHT",f.restart,"LEFT",-4,0)
        UI:AttachTooltip(f.export,"Export the way","The whole way as text to copy for a bug report: versions, start and goal, settings, data sets, every step with its points, the log (/bv route export).")
        f.log=UI:IconButton(f,"scroll-text",function() ns.UI:DiagnosticReport("Routing log",Routing:LogText()) end,"ghost")
        M.Size(f.log,20,20);M.Point(f.log,"RIGHT",f.export,"LEFT",-4,0)
        UI:AttachTooltip(f.log,"Log","What Routing did for this way: the plan, its steps, levels, new searches (/bv route log).")
        -- Safe or normal for this way (Florian 2026-10-16), the setting the default.
        f.safe=UI:IconButton(f,"shield",function() Routing.Navigate:ToggleSafe() end,"ghost")
        M.Size(f.safe,20,20);M.Point(f.safe,"RIGHT",f.log,"LEFT",-4,0)
        UI:AttachTooltip(f.safe,"Safe way","Switches this way between safe (keeps to roads, swims little, goes round zones above your level) and normal, and searches it again. New ways start as set on Routing's settings page (Route mode).")
        f.count=UI:Label(f,"",10,"muted");M.Point(f.count,"RIGHT",f.safe,"LEFT",-6,0);f.count:SetJustifyH("RIGHT")
        f.now=UI:Label(f,"",21,"text",true);M.Point(f.now,"TOPLEFT",f,"TOPLEFT",x,-31);M.Size(f.now,G.WIDTH-x-16,26)
        -- Two lines: a transition's own name may be long ("Trade Quarter
        -- Exit (Southeast) - to the lower city").
        f.target=UI:Label(f,"",13,"text");M.Point(f.target,"TOPLEFT",f,"TOPLEFT",x,-58);M.Size(f.target,G.WIDTH-x-16,32);f.target:SetJustifyV("TOP")
        -- A hair line, then what comes after and the time left.
        f.rule=f:CreateTexture(nil,"ARTWORK");f.rule:SetColorTexture(color("text",.08))
        M.Point(f.rule,"TOPLEFT",f,"TOPLEFT",16,-102);M.Point(f.rule,"TOPRIGHT",f,"TOPRIGHT",-16,-102);M.Height(f.rule,1)
        f.thenLabel=UI:Label(f,"THEN",10,"muted",true);M.Point(f.thenLabel,"TOPLEFT",f,"TOPLEFT",16,-111)
        f.next=UI:Label(f,"",11,"muted");M.Point(f.next,"LEFT",f.thenLabel,"RIGHT",8,0);M.Size(f.next,G.WIDTH-180,14)
        f.time=UI:Label(f,"",12,"accent",true);M.Point(f.time,"TOPRIGHT",f,"TOPRIGHT",-16,-110);f.time:SetJustifyH("RIGHT")
        f.clock=f:CreateTexture(nil,"OVERLAY");symbol(f.clock,"clock",32);M.Size(f.clock,12,12);M.Point(f.clock,"RIGHT",f.time,"LEFT",-5,0)
        -- Flights left out where your flight points are not known (Florian
        -- 2026-10-15): a line of its own under the rest.
        f.flightIcon=f:CreateTexture(nil,"OVERLAY");symbol(f.flightIcon,"plane",32);M.Size(f.flightIcon,12,12)
        M.Point(f.flightIcon,"TOPLEFT",f,"TOPLEFT",16,-134);f.flightIcon:SetVertexColor(color("warning"));f.flightIcon:Hide()
        f.flight=UI:Label(f,"",11,"text");M.Point(f.flight,"LEFT",f.flightIcon,"RIGHT",6,0);M.Size(f.flight,G.WIDTH-50,14)
        f.flight:SetTextColor(color("warning"));f.flight:Hide()
        f.flightTip=CreateFrame("Frame",nil,f);f.flightTip:SetPoint("TOPLEFT",f.flightIcon,"TOPLEFT",-2,2);M.Size(f.flightTip,G.WIDTH-32,16)
        UI:AttachTooltip(f.flightTip,"Flight points not known","A flight map shows only its own continent. Talk to a flight master there and open the flight map once: Routing learns which flight points you have and plans the way anew with them.")
        f.flightTip:EnableMouse(true);f.flightTip:Hide()
        for _,label in ipairs({f.head,f.now,f.target,f.next,f.flight}) do label:SetJustifyH("LEFT");label:SetWordWrap(label==f.target) end
        UI:AttachTooltip(f,"Guide","The arrow points to the next point of the way. Drag it to undock it; right-click: beside the tour window right or left, undocked, the background, or hide it.")
        f:SetScript("OnShow",function() G:Tick(true) end)
        f:SetScript("OnHide",function() G:Tick(false) end)
        self.frame=f
    end)
    self:Look()
    return self.frame
end
-- Colours, and the background shown or hidden (then the words get a shadow
-- to stand on the world).
function G:Look()
    local f=self.frame
    if not f then return end
    local bare=Routing:Config().guideGround~=true
    f.disc:SetVertexColor(color("accent",bare and .22 or .12))
    f.ring:SetVertexColor(color("accent",.45))
    f.kind:SetVertexColor(color("muted"))
    f.clock:SetVertexColor(color("accent"))
    if bare then UI:HideSurface(f)
    elseif f.surfaceHidden then
        f.surfaceHidden=false
        if f.fill then f.fill:Show() end
        for _,edge in ipairs(f.edges or {}) do edge:Show() end
        if f.sheen then f.sheen:Show() end
    end
    f.rule:SetShown(not bare)
    for _,label in ipairs({f.head,f.count,f.now,f.target,f.thenLabel,f.next,f.time}) do
        if label.SetShadowOffset then
            label:SetShadowOffset(bare and 1 or 0,bare and -1 or 0)
            label:SetShadowColor(0,0,0,bare and .9 or 0)
        end
    end
end
-- Where it stands: beside the tour window when that is open and the guide
-- is docked, else where you put it last (the top of the screen at first).
function G:Place()
    local f=self.frame
    local side=Routing:Config().guide
    local tour=rawget(_G,"BVCodexTour")
    f:ClearAllPoints()
    if (side=="left" or side=="right") and tour and tour.IsShown and tour:IsShown() then
        self.docked=true
        if side=="left" then M.Point(f,"TOPRIGHT",tour,"TOPLEFT",-G.GAP,0)
        else M.Point(f,"TOPLEFT",tour,"TOPRIGHT",G.GAP,0) end
        return
    end
    self.docked=false
    local at=Routing:Config().guideAt
    if type(at)=="table" and type(at.x)=="number" and type(at.y)=="number" then f:SetPoint("CENTER",UIParent,"BOTTOMLEFT",at.x,at.y)
    else f:SetPoint("TOP",UIParent,"TOP",0,-M.ToNative(140)) end
end
-- Dragged while beside the tour: undocked, where it stands now.
function G:Undock()
    if not self.docked then return end
    local f=self.frame
    self.docked=false
    Routing:Config().guide="free"
    local x,y=f:GetCenter()
    if x and y then f:ClearAllPoints();f:SetPoint("CENTER",UIParent,"BOTTOMLEFT",x,y) end
end
function G:Keep()
    local f=self.frame
    if not f or self.docked then return end
    local x,y=f:GetCenter()
    if x and y then Routing:Config().guideAt={x=x,y=y} end
end
function G:Wanted()
    local N=Routing.Navigate
    if self.preview then return true end
    return Routing:Config().guide~="off" and (N.steps~=nil or N.busy~=nil)
end
-- A look at it without a way (/bv route guide preview): a lift into the
-- Trade Quarter, the arrow turning slowly; ends with the command again or
-- when a way begins.
function G:Preview(on)
    if on==nil then on=not self.preview end
    self.preview=on and {at=GetTime()} or nil
    self:Update()
    return self.preview~=nil
end
-- Called whenever the way changes (Navigate:Show) and by the tour window.
function G:Update()
    if not self:Wanted() then
        if self.frame then self.frame:Hide() end
        return
    end
    local f=self:Build()
    self:Place()
    f:Show()
    self:Paint()
end
-- The point the arrow points to: on a walk a point a little ahead along its
-- way (Navigate:Carrot), before you are placed on it the next point of its
-- way, else the step's end (before a ride: where it starts).
function G:Target(step)
    local N=Routing.Navigate
    -- On a walk, and along a drawn stair or ramp (Florian 2026-10-14: on
    -- the spiral into the Slaughtered Lamb's cellar the arrow pointed at its
    -- end, right below you).
    if step.kind=="walk" or (step.kind=="transition" and not N.Teleport(step) and type(step.path)=="table" and #step.path>=3) then
        local cont,x,y=N:Carrot()
        if cont then return cont,x,y end
    end
    if step.kind=="walk" and type(step.path)=="table" and #step.path>=2 then
        local j=math.min(#step.path,math.max(2,N.ahead or 2))
        return step.from.cont,step.path[j][1],step.path[j][2]
    end
    local to=step.to
    -- A teleport: to where it starts, not across to where it lands.
    if N.Teleport(step) then return step.from.cont,step.from.x,step.from.y end
    if step.kind=="flight" or step.kind=="transport" then
        local cont,px,py=N:Here()
        if cont==step.from.cont and px and N.Yards(cont,px,py,step.from.x,step.from.y)>N.REACH then to=step.from end
    end
    return to.cont,to.x,to.y
end
-- Turned from your facing: radians, and yards; nil where it cannot tell.
function G:Vector(cont,tx,ty)
    -- Only where you are (Florian/Codex 2026-10-14: N:Here also works out
    -- your level, 20 times a second while led).
    local mapID,x,y=Routing:Position()
    if not mapID then return nil end
    local here,px,py=Routing:OnContinent(mapID,x,y)
    if not here or here~=cont then return nil end
    local width,height=Routing.Call("C_Map.GetMapWorldSize",cont)
    if type(width)~="number" or width<=0 then return nil end
    local east,south=(tx-px)*width,(ty-py)*height
    local distance=math.sqrt(east*east+south*south)
    local facing=Routing.Call("GetPlayerFacing")
    if type(facing)~="number" or (Routing.Secret and Routing.Secret(facing)) then return nil,distance end
    -- Bearing counter-clockwise from north: north is -south, west is -east.
    return (math.atan2(-east,-south)-facing)%(2*math.pi),distance
end
-- What shows instead of the arrow while you fly or ride.
G.RIDESYMBOL={flight="plane",ship="ship",zeppelin="plane",tram="cable-car",ride="ship"}
function G:Paint()
    local f=self.frame
    if not (f and f:IsShown()) then return end
    local N=Routing.Navigate
    if self.preview and (N.steps or N.busy) then self.preview=nil end
    if self.preview then
        symbol(f.kind,"arrow-up-down",32);f.head:SetText("LIFT");f.count:SetText("Step 2 of 4")
        f.now:SetText("Take the lift down");f.target:SetText("East Lift  -  to the Trade Quarter")
        f.next:SetText("Go through to the lower city");f.time:SetText("3:12");f.clock:Show()
        f.arrow:SetRotation(((GetTime()-self.preview.at)*.6)%(2*math.pi)+math.pi/4);f.arrow:SetVertexColor(color("accent"))
        return
    end
    if N.busy and not N.steps then
        symbol(f.kind,"route",32);f.head:SetText("FINDING THE WAY");f.count:SetText("")
        f.now:SetText(N.goal and N.goal.name or "...");f.target:SetText("")
        f.next:SetText("");f.time:SetText("");f.clock:Hide()
        f.arrow:SetRotation(0);f.arrow:SetVertexColor(color("muted"))
        return
    end
    local i=N.current or 1
    local step=N.steps and N.steps[i]
    if not step then return end
    local parts=N:Parts(step)
    symbol(f.kind,parts.icon,32)
    f.head:SetText(parts.head:upper())
    f.count:SetText(#N.steps>1 and string.format("Step %d of %d",i,#N.steps) or "")
    -- The shield shows the mode of this way: checked when safe, lit up.
    local safe=Routing:RouteMode()=="safe"
    -- (The button's icon is Core's symbol frame: its glyph texture and colour role.)
    local icon=f.safe.icon
    if icon and icon.glyph then
        symbol(icon.glyph,safe and "shield-check" or "shield",32)
        icon.colorRole=safe and "accent" or "muted";icon:SetColor(color(icon.colorRole))
    end
    if step.kind=="walk" then
        local yards=N.left or step.yards
        f.now:SetText(yards and (math.floor(yards+.5).." yd") or "Walk")
        f.target:SetText(parts.target)
    elseif step.kind=="flight" then
        f.now:SetText("Fly "..parts.target)
        f.target:SetText("Talk to the flight master. Wait here until you land.")
    elseif step.kind=="transport" then
        f.now:SetText(parts.verb.." "..parts.target)
        f.target:SetText("Wait for it here and ride along until you are there.")
    else
        f.now:SetText(parts.verb)
        f.target:SetText(parts.name and (parts.name.."  -  "..parts.target) or parts.target)
    end
    local after=N.steps[i+1]
    -- Short: what and where, its own name once it is the step you are on.
    f.next:SetText(after and N:Say(after,nil,true) or ("there: "..N.goal.name))
    local seconds=N:SecondsLeft()
    f.time:SetText(seconds and N.Clock(seconds) or "");f.clock:SetShown(seconds~=nil)
    local note=N.flightNote
    f.flight:SetText(note or "");f.flight:SetShown(note~=nil);f.flightIcon:SetShown(note~=nil);f.flightTip:SetShown(note~=nil)
    M.Height(f,note and G.HEIGHT+22 or G.HEIGHT)
    -- A flight or a ride (Florian 2026-10-15: the arrow went on pointing at
    -- the goal and led you away from the flight master or the dock): its
    -- symbol instead, still, until you are there.
    local ride=step.kind=="flight" or step.kind=="transport"
    local want=ride and G.RIDESYMBOL[step.kind=="flight" and "flight" or tostring(step.by and step.by.kind)] or "navigation"
    if f.arrowSymbol~=want then symbol(f.arrow,want,64);f.arrowSymbol=want end
    if ride then
        f.arrow:SetRotation(0);f.arrow:SetVertexColor(color("accent"))
        f.arrow:SetAlpha(.75+.25*math.sin(GetTime()*3))
        return
    end
    f.arrow:SetAlpha(1)
    local angle=self:Vector(self:Target(step))
    if not angle then
        f.arrow:SetRotation(0);f.arrow:SetVertexColor(color("muted"))
        return
    end
    -- The symbol points to the upper right: a quarter turn back first.
    f.arrow:SetRotation(angle+math.pi/4)
    f.arrow:SetVertexColor(color("accent"))
end
function G:Tick(on)
    if on and not self.ticker then self.ticker=C_Timer.NewTicker(G.EVERY,function() G:Paint() end)
    elseif not on and self.ticker then self.ticker:Cancel();self.ticker=nil end
end
function G:SetSide(side)
    if not (side=="left" or side=="right" or side=="free" or side=="off") then return false end
    Routing:Config().guide=side
    self:Update()
    return true
end
function G:SetBare(bare)
    Routing:Config().guideGround=bare~=true
    self:Look()
end
function G:Menu(owner)
    owner.bvMenuStyle=style()
    local cfg=Routing:Config()
    local side=cfg.guide
    UI:ContextMenu(owner,{
        {value="right",label="Beside the tour: right",checked=side=="right"},
        {value="left",label="Beside the tour: left",checked=side=="left"},
        {value="free",label="Undocked (drag it anywhere)",checked=side=="free"},
        {value="ground",label="Show background",checked=cfg.guideGround==true},
        {value="off",label="Hide the guide"},
    },function(value)
        if value=="ground" then G:SetBare(cfg.guideGround==true);return end
        G:SetSide(value)
        if value=="off" then Routing:Print("The guide is hidden: /bv route guide right (left, free) shows it again.") end
    end)
end
-- In the minimap launcher's menu while led (Florian 2026-10-15).
if ns.Launcher and ns.Launcher.AddEntry then
    ns.Launcher:AddEntry({id="routestop",label="End the way",order=45,group="navigation",icon="circle-x",
        shown=function() local N=Routing.Navigate;return N and (N.steps~=nil or N.busy==true) end,onClick=function() Routing.Navigate:Stop() end})
end
