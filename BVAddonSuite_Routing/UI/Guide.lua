local _,Routing=...
if not Routing.ready then return end
-- The guide while a way is followed (Florian 2026-10-12): an arrow to the
-- forward route course (or the guidance target when no local course is
-- confirmed) plus a hollow guidance-target point in a round
-- medallion (GuideSnapshot v1); what to do now in large (the
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
local GUIDE_MEDIA="Interface\\AddOns\\BVAddonSuite_Routing\\Media\\"

local function style() return G.style end
local function foreground(key)
    return key=="accent" and style().materialProfile=="interface" and "accentText" or key
end
local function color(key,alpha,pigment)
    local r,g,b=style():Color(pigment and key or foreground(key))
    return r,g,b,alpha or 1
end
-- A Lucide symbol on a texture (changed as the step changes).
local function symbol(texture,name,size)
    local path,l,r,t,b=ns.Symbols:Coords(name,size or 32)
    if path then texture:SetTexture(path);texture:SetTexCoord(l,r,t,b) end
end
function G:Build()
    if self.frame then return self.frame end
    local captured=UI:InterfaceStyle();if not captured then return nil end
    self.style=captured
    UI:WithStyle(style(),function()
        local f=UI:Panel(UIParent,G.WIDTH,G.HEIGHT,"panel",12,.95)
        f.bvStyle=self.style;f.bvTooltipStyle=self.style
        f:Hide();f:SetFrameStrata("DIALOG");f:SetClampedToScreen(true)
        f:SetMovable(true);f:EnableMouse(true);f:RegisterForDrag("LeftButton")
        if ns.ExternalFrames then ns.ExternalFrames:MarkOwned(f) end
        f:SetScript("OnDragStart",function(self) G:Undock();self:StartMoving() end)
        f:SetScript("OnDragStop",function(self) self:StopMovingOrSizing();G:Keep() end)
        f:SetScript("OnMouseUp",function(self,button) if button=="RightButton" then G:Menu(self) end end)
        -- The medallion: a faint disc, a ring, the arrow.
        f.medal=CreateFrame("Frame",nil,f);M.Size(f.medal,64,64);M.Point(f.medal,"TOPLEFT",f,"TOPLEFT",16,-31)
        f.disc=f.medal:CreateTexture(nil,"BACKGROUND");f.disc:SetTexture(GUIDE_MEDIA.."guide-disc.tga");f.disc:SetAllPoints(f.medal)
        f.ring=f.medal:CreateTexture(nil,"BORDER");f.ring:SetTexture(GUIDE_MEDIA.."guide-ring.tga");f.ring:SetAllPoints(f.medal)
        f.arrow=f.medal:CreateTexture(nil,"OVERLAY");symbol(f.arrow,"navigation",64)
        M.Size(f.arrow,32,32);M.Point(f.arrow,"CENTER",f.medal,"CENTER",0,0)
        -- Separate shapes: the filled route course and the hollow target point.
        f.course=f.medal:CreateTexture(nil,"OVERLAY");f.course:SetTexture(GUIDE_MEDIA.."guide-course.tga")
        M.Size(f.course,64,64);M.Point(f.course,"CENTER",f.medal,"CENTER",0,0);f.course:Hide()
        f.point=f.medal:CreateTexture(nil,"OVERLAY");f.point:SetTexture(GUIDE_MEDIA.."guide-point.tga")
        M.Size(f.point,16,16);f.point:Hide()
        f.forward=f.medal:CreateTexture(nil,"ARTWORK");f.forward:SetColorTexture(color("text",.7))
        M.Size(f.forward,1,4);M.Point(f.forward,"TOP",f.medal,"TOP",0,-1)
        -- Now: what kind of step, the step count, what to do, where to.
        local x=96
        f.head=UI:Label(f,"",10,"muted",true);M.Point(f.head,"LEFT",f,"TOPLEFT",14,-18);M.Size(f.head,172,16)
        -- Two small quiet buttons top right (Florian 2026-10-14): end the
        -- way, and search it anew from here (far off the way); the count
        -- beside them.
        f.stop=UI:IconButton(f,"x",function() Routing.Navigate:Stop() end,self.style.materialProfile=="interface" and "icon-only" or "ghost")
        M.Size(f.stop,20,20);M.Point(f.stop,"TOPRIGHT",f,"TOPRIGHT",-12,-8)
        UI:AttachTooltip(f.stop,"End the way","Ends the way and the guide (/bv route stop).")
        f.restart=UI:IconButton(f,"rotate-cw",function() Routing.Navigate:Restart() end,self.style.materialProfile=="interface" and "icon-only" or "ghost")
        M.Size(f.restart,20,20);M.Point(f.restart,"RIGHT",f.stop,"LEFT",-4,0)
        UI:AttachTooltip(f.restart,"Search anew","The way to the same goal searched again from where you are now.")
        -- The log and the whole way as text (Florian 2026-10-14).
        f.export=UI:IconButton(f,"clipboard",function() ns.UI:DiagnosticReport("Routing: the way",Routing.Navigate:ExportText()) end,self.style.materialProfile=="interface" and "icon-only" or "ghost")
        M.Size(f.export,20,20);M.Point(f.export,"RIGHT",f.restart,"LEFT",-4,0)
        UI:AttachTooltip(f.export,"Export the way","The whole way as text to copy for a bug report: versions, start and goal, settings, data sets, every step with its points, the log (/bv route export).")
        f.log=UI:IconButton(f,"scroll-text",function() ns.UI:DiagnosticReport("Routing log",Routing:LogText()) end,self.style.materialProfile=="interface" and "icon-only" or "ghost")
        M.Size(f.log,20,20);M.Point(f.log,"RIGHT",f.export,"LEFT",-4,0)
        UI:AttachTooltip(f.log,"Log","What Routing did for this way: the plan, its steps, levels, new searches (/bv route log).")
        -- Safe or normal for this way (Florian 2026-10-16), the setting the default.
        f.safe=UI:IconButton(f,"shield",function() Routing.Navigate:ToggleSafe() end,self.style.materialProfile=="interface" and "icon-only" or "ghost")
        M.Size(f.safe,20,20);M.Point(f.safe,"RIGHT",f.log,"LEFT",-4,0)
        UI:AttachTooltip(f.safe,"Safe way","Switches this way between safe (keeps to roads, swims little, goes round zones above your level) and normal, and searches it again. New ways start as set on Routing's settings page (Route mode).")
        f.count=UI:Label(f,"",10,"muted");M.Point(f.count,"RIGHT",f.safe,"LEFT",-6,0);f.count:SetJustifyH("RIGHT")
        f.now=UI:Label(f,"",21,"text",true);M.Point(f.now,"TOPLEFT",f,"TOPLEFT",x,-31);M.Size(f.now,G.WIDTH-x-16,26)
        -- Two lines: a transition's own name may be long ("Trade Quarter
        -- Exit (Southeast) - to the lower city").
        f.target=UI:Label(f,"",13,"text");M.Point(f.target,"TOPLEFT",f,"TOPLEFT",x,-58);M.Size(f.target,G.WIDTH-x-16,32);f.target:SetJustifyV("TOP")
        -- A hair line, then what comes after and the time left.
        f.rule=f:CreateTexture(nil,"ARTWORK");f.rule:SetColorTexture(color("text",.08))
        M.Point(f.rule,"TOPLEFT",f,"TOPLEFT",16,-104);M.Point(f.rule,"TOPRIGHT",f,"TOPRIGHT",-16,-104);M.Height(f.rule,1)
        f.thenLabel=UI:Label(f,"THEN",10,"muted",true);M.Point(f.thenLabel,"TOPLEFT",f,"TOPLEFT",16,-111)
        f.next=UI:Label(f,"",11,"muted");M.Point(f.next,"LEFT",f.thenLabel,"RIGHT",8,0);M.Size(f.next,G.WIDTH-180,14)
        f.time=UI:Label(f,"",12,foreground("accent"),true);M.Point(f.time,"TOPRIGHT",f,"TOPRIGHT",-16,-110);f.time:SetJustifyH("RIGHT")
        f.clock=f:CreateTexture(nil,"OVERLAY");symbol(f.clock,"clock",32);M.Size(f.clock,12,12);M.Point(f.clock,"RIGHT",f.time,"LEFT",-5,0)
        -- Flights left out where your flight points are not known (Florian
        -- 2026-10-15): a line of its own under the rest.
        f.flightIcon=f:CreateTexture(nil,"OVERLAY");symbol(f.flightIcon,"plane",32);M.Size(f.flightIcon,12,12)
        M.Point(f.flightIcon,"TOPLEFT",f,"TOPLEFT",16,-134);f.flightIcon:SetVertexColor(color("warning"));f.flightIcon:Hide()
        f.flight=UI:Label(f,"",11,self.style.materialProfile=="interface" and "warning" or "text");M.Point(f.flight,"LEFT",f.flightIcon,"RIGHT",6,0);M.Size(f.flight,G.WIDTH-50,14)
        f.flight:SetTextColor(color("warning"));f.flight:Hide()
        f.flightTip=CreateFrame("Frame",nil,f);f.flightTip:SetPoint("TOPLEFT",f.flightIcon,"TOPLEFT",-2,2);M.Size(f.flightTip,G.WIDTH-32,16)
        UI:AttachTooltip(f.flightTip,"Flight points not known","A flight map shows only its own continent. Talk to a flight master there and open the flight map once: Routing learns which flight points you have and plans the way anew with them.")
        f.flightTip:EnableMouse(true);f.flightTip:Hide()
        for _,label in ipairs({f.head,f.now,f.target,f.next,f.flight}) do label:SetJustifyH("LEFT");label:SetWordWrap(label==f.target) end
        UI:AttachTooltip(f,"Guide","The filled arrow follows the local route course. When that course is unconfirmed, it points toward the guidance target instead. The hollow point always marks that target's bearing. Neither guarantees a walkable shortcut. Drag it to undock it; right-click: beside the tour window right or left, undocked, the background, or hide it.")
        f.guideHelp=f.tooltipBody
        f:SetScript("OnShow",function() G:Tick(true) end)
        f:SetScript("OnHide",function() G:Tick(false) end)
        self.frame=f
        if ns.InterfaceSurfaces and ns.InterfaceSurfaces.AttachHUD then ns.InterfaceSurfaces:AttachHUD(self.style,f) end
        if self.style.materialProfile=="interface" then
            -- Passive repaint only: no navigation sample, ticker or position update.
            self.style:Bind(function() G:Look() end,f)
            f.safe:SetIconRole("muted")
            for _,label in ipairs({f.head,f.count,f.now,f.target,f.thenLabel,f.next,f.time}) do
                label.bvAfterFont=function()
                    if (label==f.head or label==f.count) and f.headFull then G:SetHead(f.headFull,f.countFull) end
                    if label==f.now and f.fullLabel then G:SetNow(f.fullLabel) end
                    local bare=Routing:Config().guideGround~=true
                    label:SetShadowOffset(bare and 1 or 0,bare and -1 or 0)
                    label:SetShadowColor(0,0,0,bare and .9 or 0)
                end
            end
        end
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
    f.disc:SetVertexColor(color("accent",bare and .14 or .07,true))
    f.ring:SetVertexColor(color("accent",.28,true))
    f.clock:SetVertexColor(color("accent"))
    f.forward:SetColorTexture(color("text",.7))
    if self.style.materialProfile=="interface" then
        f.surfaceHidden=bare
        -- Reuse the existing skin, including every material slice on restore.
        f:PaintSurface()
        if f.hudSurface then f.hudSurface:Refresh() end
    elseif bare then UI:HideSurface(f)
    elseif f.surfaceHidden then
        f.surfaceHidden=false
        if f.fill then f.fill:Show() end
        for _,edge in ipairs(f.edges or {}) do edge:Show() end
        if f.sheen then f.sheen:Show() end
    end
    f.rule:SetColorTexture(color("text",.08))
    f.rule:SetShown(not bare)
    f.flightIcon:SetVertexColor(color("warning"))
    f.course:SetVertexColor(color("accent"))
    f.point:SetVertexColor(color("text"))
    f.arrow:SetVertexColor(color(f.arrowRole or "muted",f.arrow:GetAlpha()))
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
-- A look at it without a way (/bv route guide preview): an explicitly
-- illustrative route course and guidance point; ends with the command again or
-- when a way begins.
function G:Preview(on)
    if on==nil then on=not self.preview end
    self.preview=on and {at=GetTime()} or nil
    self:Update()
    return self.preview~=nil
end
-- Called whenever the way changes (Navigate:Show) and by the tour window.
function G:Update()
    if not self.frame and not UI:InterfaceStyle() then return nil end
    if not self:Wanted() then
        if self.frame then self.frame:Hide() end
        return
    end
    local f=self:Build();if not f then return nil end
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
-- Bounded A header: the type starts at x14; five actions start at x192.
-- Count retains its own measured slot; a long type cannot enter that slot.
function G:SetHead(text,count)
    local f=self.frame;local skin=style();count=count or ""
    f.headFull=text;f.countFull=count;f.count:SetText(count)
    f.tooltipBody=text..(count~="" and " · "..count or "").."\n\n"..f.guideHelp;f.tooltipText=f.tooltipBody
    local countWidth=math.min(M.ToNative(48),f.count:GetUnboundedStringWidth())
    skin:FitCaption(f.count,count,math.max(1,countWidth))
    skin:FitCaption(f.head,text,M.ToNative(172)-(count~="" and countWidth+M.ToNative(8) or 0))
end
-- A long transport or search title must remain inside its single-line slot.
-- Native font measurement chooses the size; the existing caption helper handles
-- UTF-8-safe ellipsis at the minimum, and the guide tooltip retains full text.
function G:SetNow(text)
    local f=self.frame;local label=f.now;local skin=style()
    f.fullLabel=text;label:SetText(text);skin:Font(label,21,"bold")
    local width=label:GetWidth();local natural=label:GetUnboundedStringWidth()
    if natural>width then skin:Font(label,math.max(14,math.floor(21*width/natural)),"bold") end
    skin:FitCaption(label,text,width)
    if self.style.materialProfile=="interface" then
        -- Font() softens its shadow; restore the bare-guide contract last,
        -- both for normal Paint ticks and the font-refresh refit.
        local bare=Routing:Config().guideGround~=true
        label:SetShadowOffset(bare and 1 or 0,bare and -1 or 0)
        label:SetShadowColor(0,0,0,bare and .9 or 0)
    end
end
-- Direction data belongs to Navigate. This view neither projects onto a route
-- nor keeps a snapshot across paints. Missing data must never look like north.
local function finite(value)
    return type(value)=="number" and not (Routing.Secret and Routing.Secret(value))
        and value==value and value~=math.huge and value~=-math.huge
end
function G:NeutralDirection(name,role)
    local f=self.frame
    f.course:Hide();f.point:Hide();f.arrow:Show()
    symbol(f.arrow,name or "circle-help",64);f.arrowSymbol=name or "circle-help"
    f.arrowRole=role or "muted"
    f.arrow:SetRotation(0);f.arrow:SetVertexColor(color(f.arrowRole));f.arrow:SetAlpha(1)
end
function G:PaintDirections(snapshot,facing)
    local f=self.frame
    self:NeutralDirection("circle-help")
    local N=Routing.Navigate
    if type(snapshot)~="table" or snapshot.version~=1 or snapshot.route~=N.steps
        or snapshot.stepIndex~=N.current or not finite(facing) then return end
    if snapshot.phase~="walk" and snapshot.phase~="transition" then return end
    if self.style.materialProfile=="interface" and snapshot.phase=="transition" and snapshot.transitionKind=="lift" then
        -- Snapshot v1 has no vertical direction; a valid horizontal target must not hide the lift.
        self:NeutralDirection("arrow-up-down","accent");return
    end
    local course,target=snapshot.course,snapshot.target
    local haveCourse=type(course)=="table" and course.valid==true and finite(course.bearingWorldRad)
        and snapshot.routeRelation=="projected" and (course.mode=="tangent" or course.mode=="routeWindow")
    local havePoint=type(target)=="table" and target.valid==true and finite(target.bearingWorldRad)
    -- Progress remains monotone when walking back, so the provider may no
    -- longer confirm a local tangent. Its target bearing is still valid:
    -- retain a filled direction toward it instead of leaving only the dot.
    -- Never invent a course or change the tracker's anchor/progress here.
    local direction=haveCourse and course.bearingWorldRad or (havePoint and target.bearingWorldRad)
    if direction then
        f.course:SetRotation((direction-facing)%(2*math.pi))
        f.course:SetVertexColor(color("accent"));f.course:Show();f.arrow:Hide()
    end
    if havePoint then
        local angle=(target.bearingWorldRad-facing)%(2*math.pi)
        f.point:ClearAllPoints();M.Point(f.point,"CENTER",f.medal,"CENTER",-math.sin(angle)*27,math.cos(angle)*27)
        f.point:SetVertexColor(color("text"));f.point:Show();f.arrow:Hide()
    end
end
-- What shows instead of the arrow while you fly or ride.
G.RIDESYMBOL={flight="plane",ship="ship",zeppelin="plane",tram="cable-car",ride="ship"}
function G:Paint()
    local f=self.frame
    if not (f and f:IsShown()) then return end
    local N=Routing.Navigate
    if self.preview and (N.steps or N.busy) then self.preview=nil end
    f.course:Hide();f.point:Hide();f.arrow:Hide()
    f.flight:Hide();f.flightIcon:Hide();f.flightTip:Hide();M.Height(f,G.HEIGHT)
    if self.preview then
        self:SetHead("GUIDE PREVIEW","")
        self:SetNow("Course + point");f.target:SetText("Filled: route course\nHollow: guidance target")
        f.next:SetText("Example only");f.time:SetText("");f.clock:Hide()
        f.course:SetRotation(0);f.course:SetVertexColor(color("accent"));f.course:Show()
        local example=math.atan2(6,15)
        f.point:ClearAllPoints();M.Point(f.point,"CENTER",f.medal,"CENTER",-math.sin(example)*27,math.cos(example)*27)
        f.point:SetVertexColor(color("text"));f.point:Show()
        return
    end
    if N.busy and not N.steps then
        self:SetHead("FINDING THE WAY","")
        self:SetNow(N.goal and N.goal.name or "...");f.target:SetText("")
        f.next:SetText("");f.time:SetText("");f.clock:Hide()
        self:NeutralDirection("route")
        return
    end
    local i=N.current or 1
    local step=N.steps and N.steps[i]
    if not step then f:Hide();return end
    local parts=N:Parts(step)
    self:SetHead(parts.head:upper(),#N.steps>1 and string.format("%d/%d",i,#N.steps) or "")
    -- The shield shows the mode of this way: checked when safe, lit up.
    local safe=Routing:RouteMode()=="safe"
    -- (The button's icon is Core's symbol frame: its glyph texture and colour role.)
    local icon=f.safe.icon
    if icon and icon.glyph then
        symbol(icon.glyph,safe and "shield-check" or "shield",32)
        if self.style.materialProfile=="interface" then f.safe:SetIconRole(safe and "accent" or "muted")
        else icon.colorRole=safe and "accent" or "muted";icon:SetColor(color(icon.colorRole)) end
    end
    if step.kind=="walk" then
        local yards=N.left or step.yards
        self:SetNow(yards and (math.floor(yards+.5).." yd") or "Walk")
        f.target:SetText(parts.target)
    elseif step.kind=="flight" then
        self:SetNow("Fly "..parts.target)
        f.target:SetText("Talk to the flight master. Wait here until you land.")
    elseif step.kind=="transport" then
        self:SetNow(parts.verb.." "..parts.target)
        f.target:SetText(Routing.Timetable and Routing.Timetable:GuideText(step) or "Wait for it here and ride along until you are there.")
    else
        self:SetNow(parts.verb)
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
    -- One provider sample and one common facing for both heading-up markers.
    local snapshot=N.GuideSnapshot and N:GuideSnapshot() or nil
    local facing=Routing.Call("GetPlayerFacing")
    if step.kind=="flight" or step.kind=="transport" then
        self:NeutralDirection(G.RIDESYMBOL[step.kind=="flight" and "flight" or tostring(step.by and step.by.kind)] or "ship","accent")
        f.arrow:SetAlpha(.75+.25*math.sin(GetTime()*3));return
    end
    self:PaintDirections(snapshot,facing)
    if not f.course:IsShown() and not f.point:IsShown() and step.kind=="transition"
        and step.by and step.by.kind=="lift" then self:NeutralDirection("arrow-up-down") end
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
