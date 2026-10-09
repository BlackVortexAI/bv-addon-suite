local _,Q=...
if not Q.ready then return end
-- Dungeon run banner at the top of the tracker (party dungeons, Run.lua):
-- instance and time inside, XP and gold with rates per hour; the tooltip lists
-- bosses killed and the time to the next level at this pace; restart button.
local ns=Q.ns
local UI,M=ns.UI,ns.DesignSystem.Metrics
local B={}
Q.Banner=B
local HEIGHT=40

local function money(copper)
    copper=math.floor(copper or 0)
    if copper<=0 then return "0c" end
    local g,s,c=math.floor(copper/10000),math.floor(copper/100)%100,copper%100
    if g>0 then return g.."g "..s.."s" end
    if s>0 then return s.."s "..c.."c" end
    return c.."c"
end
local function large(value)
    value=math.floor(value or 0)
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(value) end
    return tostring(value)
end
local function clock(seconds)
    seconds=math.floor(seconds or 0)
    if seconds>=3600 then return string.format("%d:%02d:%02d",math.floor(seconds/3600),math.floor(seconds/60)%60,seconds%60) end
    return string.format("%d:%02d",math.floor(seconds/60),seconds%60)
end
function B:Build(parent)
    local f=CreateFrame("Button",nil,parent);f:Hide()
    f.band=f:CreateTexture(nil,"BACKGROUND");f.band:SetAllPoints(f);f.band:SetTexture("Interface\\Buttons\\WHITE8X8")
    f.stripe=f:CreateTexture(nil,"ARTWORK");f.stripe:SetTexture("Interface\\Buttons\\WHITE8X8")
    f.stripe:SetPoint("TOPLEFT",f,"TOPLEFT");f.stripe:SetPoint("BOTTOMLEFT",f,"BOTTOMLEFT");f.stripe:SetWidth(M.ToNative(2))
    f.name=f:CreateFontString(nil,"OVERLAY");f.name:SetJustifyH("LEFT");f.name:SetWordWrap(false)
    f.time=f:CreateFontString(nil,"OVERLAY");f.time:SetJustifyH("RIGHT")
    f.stats=f:CreateFontString(nil,"OVERLAY");f.stats:SetJustifyH("LEFT");f.stats:SetWordWrap(false)
    f.restart=CreateFrame("Button",nil,f);M.Size(f.restart,14,14)
    f.restart.icon=f.restart:CreateTexture(nil,"ARTWORK");f.restart.icon:SetAllPoints(f.restart)
    local path,l,r,t,b=ns.Symbols:Coords("rotate-ccw",64)
    if path then f.restart.icon:SetTexture(path);f.restart.icon:SetTexCoord(l,r,t,b) end
    f.restart:SetScript("OnClick",function() Q.Run:Restart() end)
    f.restart:SetScript("OnEnter",function(button) Q.Tracker:Hover(1);UI:ShowTooltip(button,"Start over","Starts the run's time, XP and gold from zero.") end)
    f.restart:SetScript("OnLeave",function(button) Q.Tracker:Hover(-1);UI:HideTooltip(button) end)
    f:SetScript("OnEnter",function(owner) Q.Tracker:Hover(1);B:Tooltip(owner) end)
    f:SetScript("OnLeave",function() Q.Tracker:Hover(-1);if GameTooltip then GameTooltip:Hide() end end)
    self.frame=f
end
-- The Layout Editor preview shows a sample run, so the banner can be seen outside dungeons.
function B:Shown()
    if Q.Tracker.preview then return Q:Config().banner end
    return Q:Config().banner and Q.Run.inside and Q.Run:State()~=nil
end
function B:Values()
    if Q.Tracker.preview then return {name="Shadowfang Keep",elapsed=754,xp=18450,xpRate=88000,money=31500,moneyRate=150000,bosses={"Rethilgore","Razorclaw the Butcher"}} end
    return Q.Run:Values()
end
-- Places the banner at y (design units) and returns the y below it.
function B:Layout(parent,y,width)
    local f=self.frame
    if not f then return y end
    if not self:Shown() then f:Hide();self:Clock(false);return y end
    local v=self:Values()
    local s,fam=Q:Style(),Q:Family()
    local size=Q:Config().fontSize
    local function font(region,px,weight) ns.Styles:Font(fam,region,M.ToNative(px),weight or "regular","OUTLINE") end
    font(f.name,size,"bold");font(f.time,size,"bold");font(f.stats,size-2)
    f.name:SetText(v.name);f.name:SetTextColor(s:Color("accent"))
    f.time:SetText(clock(v.elapsed));f.time:SetTextColor(s:Color("text"))
    f.stats:SetText(string.format("%s XP (%s/h)  ·  %s (%s/h)",large(v.xp),large(v.xpRate),money(v.money),money(v.moneyRate)))
    f.stats:SetTextColor(s:Color("muted"))
    local ar,ag,ab=s:Color("accent");f.band:SetVertexColor(ar,ag,ab,.16);f.stripe:SetVertexColor(ar,ag,ab,1)
    local r,g,b=s:Color("muted");f.restart.icon:SetVertexColor(r,g,b,1)
    f:ClearAllPoints();M.Point(f,"TOPLEFT",parent,"TOPLEFT",6,-y);M.Size(f,width-12,HEIGHT)
    f.name:ClearAllPoints();M.Point(f.name,"TOPLEFT",f,"TOPLEFT",6,-4);M.Size(f.name,width-110,16)
    f.time:ClearAllPoints();M.Point(f.time,"TOPRIGHT",f,"TOPRIGHT",-24,-4);M.Size(f.time,70,16)
    f.restart:ClearAllPoints();M.Point(f.restart,"TOPRIGHT",f,"TOPRIGHT",-5,-5)
    f.stats:ClearAllPoints();M.Point(f.stats,"TOPLEFT",f,"TOPLEFT",6,-22);M.Size(f.stats,width-24,14)
    f:Show()
    self:Clock(true)
    return y+HEIGHT+6
end
-- The time runs on while the banner is shown (one tick per second).
function B:Clock(on)
    if on and not self.clock then self.clock=C_Timer.NewTicker(1,function() if B.frame and B.frame:IsShown() then Q.Tracker:Layout() end end)
    elseif not on and self.clock then self.clock:Cancel();self.clock=nil end
end
function B:Tooltip(owner)
    if not GameTooltip then return end
    local v=self:Values()
    if not v then return end
    GameTooltip:SetOwner(owner,"ANCHOR_LEFT")
    GameTooltip:SetText(v.name)
    GameTooltip:AddDoubleLine("Time inside",clock(v.elapsed),1,1,1,1,1,1)
    GameTooltip:AddDoubleLine("Experience",large(v.xp).." ("..large(v.xpRate).."/h)",1,1,1,1,1,1)
    GameTooltip:AddDoubleLine("Gold",money(v.money).." ("..money(v.moneyRate).."/h)",1,1,1,1,1,1)
    if v.eta then GameTooltip:AddDoubleLine("Next level at this pace",ns.ProgressModel.Duration(v.eta),1,1,1,1,1,1) end
    if #v.bosses>0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Bosses killed",1,.82,0)
        for _,name in ipairs(v.bosses) do GameTooltip:AddLine(name,1,1,1) end
    end
    GameTooltip:Show()
end
