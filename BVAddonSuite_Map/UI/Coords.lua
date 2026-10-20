local _,P=...
if not P.ready then return end
-- Coordinates: a slim strip at the bottom of the map (player on the map shown,
-- cursor while it is over the map). Blizzard's minimap shows coordinates itself.
-- Refreshed by light tickers only while visible (tickers only, no per-frame scripts).
local ns=P.ns
local UI,M=ns.UI,ns.DesignSystem.Metrics
local C={}
P.Coords=C

function C:Build()
    local map=P:WorldMap()
    if self.strip or not map then return end
    local parent=map.ScrollContainer or map
    UI:WithStyle(P:Style(),function()
        self.strip=UI:GamePanel(P.ID,parent,260,20,"bg",3,function() return .75 end)
        P:AbovePins(self.strip,parent);self.strip:EnableMouse(false)
        self.strip.text=self.strip:CreateFontString(nil,"OVERLAY");self.strip.text:SetJustifyH("LEFT");self.strip.text:SetWordWrap(false)
    end)
end
local function font(region,size)
    ns.Styles:Font(P:Family(),region,M.ToNative(size),"regular","OUTLINE")
end

-- Text for the strip: what is switched on, cursor only while over the map.
function C:Text()
    local c,map=P:Config(),P:WorldMap()
    local parts={}
    local s=P:Style()
    local function hex(key) local r,g,b=s:Color(key);return string.format("|cff%02x%02x%02x",r*255,g*255,b*255) end
    local muted,text=hex("muted"),hex("text")
    local mapID=map and map.GetMapID and map:GetMapID()
    if c.coordsPlayer then
        local x,y=P:PlayerPosition(mapID)
        parts[#parts+1]=muted.."Player|r "..text..P:Format(x,y).."|r"
    end
    if c.coordsCursor then
        local container=map and (map.ScrollContainer or map)
        local x,y
        if container and container.GetNormalizedCursorPosition and container:IsMouseOver() then
            local ok,cx,cy=pcall(container.GetNormalizedCursorPosition,container)
            if ok and type(cx)=="number" and cx>=0 and cx<=1 and cy>=0 and cy<=1 then x,y=cx,cy end
        end
        parts[#parts+1]=muted.."Cursor|r "..text..P:Format(x,y).."|r"
    end
    return table.concat(parts,"    ")
end
function C:Update()
    local c,map=P:Config(),P:WorldMap()
    -- Another addon showing map coordinates keeps them (P.Guard).
    local show=P:Active() and c.coords and (c.coordsPlayer or c.coordsCursor) and map and map:IsShown() and not P.Guard:Owner("coords")
    if show then
        self:Build()
        local strip=self.strip
        font(strip.text,11)
        strip.text:SetText(self:Text())
        local width=c.coordsPlayer and c.coordsCursor and 250 or 130
        if c.coordsDecimals==2 then width=width+30 elseif c.coordsDecimals==0 then width=width-30 end
        strip:ClearAllPoints();M.Point(strip,"BOTTOMLEFT",strip:GetParent(),"BOTTOMLEFT",6,6);M.Size(strip,width,20)
        strip.text:ClearAllPoints();M.Point(strip.text,"LEFT",strip,"LEFT",8,0);M.Size(strip.text,width-12,18)
        strip:Show()
    elseif self.strip then self.strip:Hide() end
    self:Legend(P:Active() and c.legend and map and map:IsShown() or false)
    self:Tick(show and "map" or nil)
end
-- Map open: ten times a second (cursor).
function C:Tick(on)
    if on and not self.ticker then self.ticker=C_Timer.NewTicker(.1,function() C:Refresh() end)
    elseif not on and self.ticker then self.ticker:Cancel();self.ticker=nil end
end
function C:Refresh()
    local map=P:WorldMap()
    if not (self.strip and map and map:IsShown()) then return self:Update() end
    -- Once a second: another addon's map coordinates switched on while the
    -- map is open (Florian 2026-10-15: both showed, one over the other).
    self.checks=(self.checks or 0)+1
    if self.checks>=10 then self.checks=0;if P.Guard:Owner("coords") then return self:Update() end end
    self.strip.text:SetText(self:Text())
end

-- The legend (Florian 2026-10-16): the clicks this map knows, small and
-- quiet above the coordinates; only those that work now.
function C:LegendText()
    local c=P:Config()
    local parts={"Ctrl+click: waypoint"}
    if c.routeClick and P.Path and P.Path.Routing and P.Path:Routing() then parts[#parts+1]="Ctrl+Shift+click: route there" end
    if c.altClick then parts[#parts+1]="Alt+click: add to path" end
    return table.concat(parts,"  \194\183  ")
end
function C:Legend(show)
    if not show then if self.legendFrame then self.legendFrame:Hide() end;return end
    local map=P:WorldMap()
    local parent=map.ScrollContainer or map
    -- Its own frame above the map's canvas (a font string on the container
    -- lay under the canvas, Florian 2026-10-16: not shown).
    if not self.legendFrame then
        local f=CreateFrame("Frame",nil,parent)
        f:SetAllPoints(parent);P:AbovePins(f,parent);f:EnableMouse(false)
        self.legendFrame=f
        self.legend=f:CreateFontString(nil,"OVERLAY")
        self.legend:SetJustifyH("LEFT");self.legend:SetWordWrap(false)
    end
    P:AbovePins(self.legendFrame)
    self.legendFrame:Show()
    local legend=self.legend
    font(legend,10)
    local r,g,b=P:Style():Color("muted")
    legend:SetTextColor(r,g,b,.9)
    legend:SetText(self:LegendText())
    legend:ClearAllPoints()
    if self.strip and self.strip:IsShown() then M.Point(legend,"BOTTOMLEFT",self.strip,"TOPLEFT",8,4)
    else M.Point(legend,"BOTTOMLEFT",parent,"BOTTOMLEFT",14,10) end
    legend:Show()
end
function C:Enable(context)
    local map=P:WorldMap()
    if map and not self.hooked then
        self.hooked=true
        map:HookScript("OnShow",function() C:Update() end)
        map:HookScript("OnHide",function() C:Update() end)
    end
    ns.Styles:OnChanged(C,function() if P:Active() then C:Update() end end)
    context:Defer(function() C:Tick(false);if C.strip then C.strip:Hide() end;C:Legend(false) end)
    self:Update()
end
