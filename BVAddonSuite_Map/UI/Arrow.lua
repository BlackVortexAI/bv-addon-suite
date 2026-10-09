local _,P=...
if not P.ready then return end
-- Navigation arrow (only without TomTom, whose Crazy Arrow stays in charge):
-- points to the active waypoint with distance and arrival time, turns green
-- close to it. A Layout Editor element; right-click for the next waypoint,
-- the list or clearing. Refreshed by a ticker only while a waypoint is active.
local ns=P.ns
local UI,M=ns.UI,ns.DesignSystem.Metrics
local A={}
P.Arrow=A
local ID="bv:maparrow"

function A:Create()
    if self.frame then return end
    local f=CreateFrame("Button",nil,UIParent);f:Hide();f:SetFrameStrata("MEDIUM");f:RegisterForClicks("RightButtonUp")
    f:SetSize(1,1);f:SetPoint("TOP",UIParent,"TOP",0,-M.ToNative(220))
    if ns.ExternalFrames then ns.ExternalFrames:MarkOwned(f) end
    f.icon=f:CreateTexture(nil,"ARTWORK")
    local path,l,r,t,b=ns.Symbols:Coords("navigation",64)
    if path then f.icon:SetTexture(path);f.icon:SetTexCoord(l,r,t,b) end
    f.title=f:CreateFontString(nil,"OVERLAY");f.title:SetJustifyH("CENTER");f.title:SetWordWrap(false)
    f.info=f:CreateFontString(nil,"OVERLAY");f.info:SetJustifyH("CENTER");f.info:SetWordWrap(false)
    f:SetScript("OnClick",function(owner) A:Menu(owner) end)
    self.frame=f
    ns.Layout:Register(ID,{label="Waypoint Arrow",
        limits={minWidth=80,maxWidth=400,minHeight=60,maxHeight=300},
        defaults=function() return {width=M.ToNative(160),height=M.ToNative(96),screen="TOP",x=0,y=-220} end,
        apply=function(rect)
            f:ClearAllPoints();f:SetPoint("CENTER",UIParent,"CENTER",rect.x,rect.y)
            f:SetSize(math.max(1,rect.width),math.max(1,rect.height))
            A:Layout()
        end,
        enabled=function() return P:Active() and P:Config().arrow end,
        preview=function(value) A.preview=value==true;A:Update() end})
end
local function font(region,size,weight) ns.Styles:Font(P:Family(),region,M.ToNative(size),weight or "regular","OUTLINE") end
function A:Layout()
    local f=self.frame
    if not f then return end
    local width,height=M.GetWidth(f),M.GetHeight(f)
    local size=math.max(24,math.min(width,height-34))
    f.icon:ClearAllPoints();M.Point(f.icon,"TOP",f,"TOP",0,0);M.Size(f.icon,size,size)
    font(f.title,12,"bold");font(f.info,11)
    f.title:ClearAllPoints();M.Point(f.title,"TOP",f.icon,"BOTTOM",0,-2);M.Size(f.title,width,16)
    f.info:ClearAllPoints();M.Point(f.info,"TOP",f.title,"BOTTOM",0,0);M.Size(f.info,width,14)
end
-- Shown for an active waypoint of ours (never with TomTom), outside instances.
function A:Wanted()
    if self.preview then return true end
    return P:Active() and P:Config().arrow and P.Waypoints.active~=nil and not P.Waypoints:TomTom()
end
function A:Update()
    if not self:Wanted() then
        if self.frame then self.frame:Hide() end
        self:Tick(false);P.Navigation:Reset()
        return
    end
    self:Create();self:Layout()
    self.frame:Show()
    self:Paint()
    self:Tick(not self.preview)
end
function A:Paint()
    local f=self.frame
    local s=P:Style()
    local point=self.preview and {title="Tarren Mill",mapID=0,x=0,y=0} or P.Waypoints.active
    if not point then return end
    f.title:SetText(P.Waypoints:Label(point));f.title:SetTextColor(s:Color("text"))
    local angle,distance
    if self.preview then angle,distance=.6,240 else angle,distance=P.Navigation:Vector(point) end
    if not distance then
        f.icon:SetRotation(0);f.icon:SetVertexColor(s:Color("muted"))
        f.info:SetText("No direction here");f.info:SetTextColor(s:Color("muted"))
        return
    end
    -- The symbol points to the upper right: a quarter turn back first.
    f.icon:SetRotation((angle or 0)+math.pi/4)
    local close=distance<=P:Config().arrival*3
    if close then f.icon:SetVertexColor(.37,.82,.42) else f.icon:SetVertexColor(s:Color("accent")) end
    local text=math.floor(distance+.5).." yd"
    local eta=not self.preview and P.Navigation:ETA(distance)
    if eta and eta<36000 then text=text.."  ·  "..P.Navigation.Clock(eta) end
    f.info:SetText(text);f.info:SetTextColor(s:Color("muted"))
end
-- Twenty times a second while a waypoint is active.
function A:Tick(on)
    if on and not self.ticker then self.ticker=C_Timer.NewTicker(.05,function() if A.frame and A.frame:IsShown() then A:Paint() end end)
    elseif not on and self.ticker then self.ticker:Cancel();self.ticker=nil end
end
function A:Menu(owner)
    owner.bvMenuStyle=P:Style()
    UI:ContextMenu(owner,{{value="next",label="Closest waypoint"},{value="list",label="Waypoint list"},{value="clear",label="Clear waypoints",danger=true}},function(value)
        if value=="next" then P.Waypoints:Closest()
        elseif value=="list" then P.WaypointList:Toggle()
        elseif value=="clear" then P.Waypoints:Clear() end
    end)
end

function A:Enable(context)
    self:Create()
    ns.Styles:OnChanged(A,function() if A.frame and A.frame:IsShown() then A:Layout();A:Paint() end end)
    context:Defer(function() A:Tick(false);if A.frame then A.frame:Hide() end end)
    self:Update()
end
A:Create()
