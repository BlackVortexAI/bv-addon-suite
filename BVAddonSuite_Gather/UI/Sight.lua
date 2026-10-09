local _,G=...
if not G.ready then return end
-- Sight circle (Florian 2026-10-09): a see-through ring around you on the
-- minimap with the sight radius of the route planning: what lies inside it
-- the minimap's Find Herbs / Find Minerals dots can show. Its size follows
-- the minimap's view radius (zoom, indoors) and its size on screen (the
-- HUD); only while the gather mode is on and the setting wants it.
local ns=G.ns
local S={}
G.Sight=S
S.SEGMENTS=72

function S:Wanted() return G:Active() and G:Config().mode and G:Config().sightCircle end
function S:Frame()
    if self.frame then return self.frame end
    local minimap=rawget(_G,"Minimap")
    if not minimap then return nil end
    -- On the pin layer: not faded with the HUD's map.
    local parent=ns.MapPins and ns.MapPins.MinimapLayer and ns.MapPins:MinimapLayer(minimap) or minimap
    local f=CreateFrame("Frame",nil,parent);f.bvKeep=true;f:EnableMouse(false)
    f:SetPoint("CENTER",minimap,"CENTER",0,0);f:SetFrameLevel(parent:GetFrameLevel()+1)
    f.fill=f:CreateTexture(nil,"BACKGROUND");f.fill:SetAllPoints(f);f.fill:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    -- The ring as short lines, so its thickness can be set.
    f.segments={}
    for i=1,S.SEGMENTS do
        local line=f:CreateLine(nil,"BORDER");line:SetTexture("Interface\\Buttons\\WHITE8X8")
        f.segments[i]=line
    end
    -- One of them answers for the colour (the tests read it).
    f.ring=f.segments[1]
    f:Hide()
    self.frame=f
    return f
end
function S:Update()
    local f=self:Frame()
    if not f then return end
    local minimap=rawget(_G,"Minimap")
    local view=G.Call("C_Minimap.GetViewRadius")
    if not self:Wanted() or type(view)~="number" or view<=0 then f:Hide();return self:Watch(false) end
    local size=G:Config().sightRadius/view*minimap:GetWidth()
    f:SetSize(size,size)
    -- Colour and opacity are settings (Florian 2026-10-09); the fill is a
    -- faint share of the ring's opacity.
    local c=G:Config()
    local r,g,b
    if c.sightColor~="" then r,g,b=ns.UI:RGBA(c.sightColor:sub(1,6).."FF") else r,g,b=G:Style():Color("accent") end
    local alpha=c.sightAlpha/100
    f.fill:SetVertexColor(r,g,b,alpha*.15)
    -- The lines go round anew only when size or thickness changed.
    local key=string.format("%.1f:%d",size,c.sightWidth)
    if key~=self.drawn then
        self.drawn=key
        local radius=size/2-c.sightWidth/2
        local step=2*math.pi/S.SEGMENTS
        for i,line in ipairs(f.segments) do
            local a1,a2=(i-1)*step,i*step+step*.1
            line:SetThickness(c.sightWidth)
            line:SetStartPoint("CENTER",f,math.cos(a1)*radius,math.sin(a1)*radius)
            line:SetEndPoint("CENTER",f,math.cos(a2)*radius,math.sin(a2)*radius)
        end
    end
    for _,line in ipairs(f.segments) do line:SetVertexColor(r,g,b,alpha) end
    f:Show()
    self:Watch(true)
end
-- Zoom and indoors change the view radius without telling us: a look every second.
function S:Watch(on)
    if on and not self.ticker then self.ticker=C_Timer.NewTicker(1,function() S:Update() end)
    elseif not on and self.ticker then self.ticker:Cancel();self.ticker=nil end
end
function S:Enable(context)
    context:Defer(function() S:Watch(false);if S.frame then S.frame:Hide() end end)
    self:Update()
end
