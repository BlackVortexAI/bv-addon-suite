local _,L=...
if not L.ready then return end
-- Status display (0.7.2, option "statusDisplay", off by default): a small
-- box, movable in the Layout Editor, that shows whether every source Combat
-- Text tells your hits by is in order: the Combat Log opened since login,
-- its filter, the line colours, lines arriving. A click puts it right with
-- the Start button's macro (opens the Combat Log for a moment, selects the BV
-- filter through its quick button, switches back). A secure macro button:
-- created, shown, hidden and moved out of combat only; its text and the
-- macro follow every second while it is shown (macro out of combat only).
-- Compact (Florian 2026-10-07): a symbol and a short text, every detail in
-- the tooltip; fixed size, only moved in the Layout Editor; by default in
-- the top left corner of the screen, always kept on screen.
local ns=L.ns
local M=ns.DesignSystem.Metrics
local S={NAME="BVCombatTextStatus",LAYOUT="bv:combattext_status",STEP=1,WIDTH=150,HEIGHT=22,MARGIN=4,PLACED=2}
S.ICON_OK="Interface\\RaidFrame\\ReadyCheck-Ready"
S.ICON_BAD="Interface\\RaidFrame\\ReadyCheck-NotReady"
L.StatusDisplay=S
local OK,BAD,DIM="|cff40d060","|cffff6060","|cffb0b0b0"

local function locked() return InCombatLockdown and InCombatLockdown() end
local function wanted() return S.enabled and L:Active() and (L:Config().statusDisplay==true or S.previewing==true) end

-- Lines {state, text}: state true (fine), false (needs a click) or nil (info).
function S:Lines()
    local G,F=L.Log,L.LogFilter
    local cfg=L:Config()
    local lines={}
    if not cfg.logSignal then
        lines[1]={nil,"Combat Log signal off (settings)"}
        return lines,true
    end
    local s=G:Status()
    lines[#lines+1]={s.opened,s.opened and "Combat Log opened" or "Combat Log not opened since login"}
    local name=s.filterName and "\""..s.filterName.."\"" or "Filter"
    local fits=G.USABLE[s.filter]==true
    lines[#lines+1]={fits,name..(fits and (s.filter=="colour" and ": told apart by colour" or ": fits") or ": does not fit")}
    if F:Selected() then
        lines[#lines+1]={true,"BV filter selected"}
    elseif F:Find() then
        lines[#lines+1]={false,"BV filter not selected"}
    else
        lines[#lines+1]={nil,"BV filter not set up (settings)"}
    end
    local c=G.colours
    if c and F:Usable(c) then
        lines[#lines+1]={nil,c.petUnique and "Yours and your pet's lines told apart" or "Your pet has your colour"}
    end
    if s.opened and fits then
        local flowing=s.state=="active"
        lines[#lines+1]={flowing,flowing and "Lines arriving" or "No lines right now"}
    end
    local all=true
    for _,line in ipairs(lines) do if line[1]==false then all=false end end
    return lines,all
end
-- Short text for the box; the lines go to the tooltip.
function S:Text()
    local lines,all=self:Lines()
    return all and OK.."Combat Text|r" or BAD.."Combat Text: fix|r",all,lines
end
function S:Tooltip(owner)
    if not GameTooltip then return end
    local _,all,lines=self:Text()
    GameTooltip:SetOwner(owner,"ANCHOR_BOTTOMRIGHT")
    GameTooltip:SetText(all and "Combat Text: all in order" or "Combat Text: click to fix")
    for _,line in ipairs(lines) do
        local r,g,b=.7,.7,.7
        if line[1]==true then r,g,b=.25,.82,.38 elseif line[1]==false then r,g,b=1,.38,.38 end
        GameTooltip:AddLine((line[1]==false and "x " or "- ")..line[2],r,g,b,true)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click: opens the Combat Log for a moment, selects the \"BV Combat Text\" filter if it is set up but not selected, and switches back. Move it in the Layout Editor.",1,1,1,true)
    GameTooltip:Show()
end

function S:Create()
    assert(not locked(),"Create the status display outside combat")
    local b=CreateFrame("Button",self.NAME,UIParent,"SecureActionButtonTemplate")
    b:Hide();b:SetFrameStrata("MEDIUM");b:SetClampedToScreen(true)
    b:SetSize(M.ToNative(self.WIDTH),M.ToNative(self.HEIGHT))
    b:RegisterForClicks("AnyUp","AnyDown")
    b:SetAttribute("type","macro")
    -- Background and border of the style family (0.7.4); red tint while something needs a click.
    local bg=ns.UI:GamePanel(L.ID,b,self.WIDTH,self.HEIGHT,"bg",4,.8)
    bg:SetAllPoints(b);bg:EnableMouse(false);bg:SetFrameLevel(b:GetFrameLevel())
    bg.bvFillOverride=function() if S.bad then return .2,.06,.08,1 end end
    b.bg=bg
    local icon=b:CreateTexture(nil,"ARTWORK")
    icon:SetSize(M.ToNative(16),M.ToNative(16));icon:SetPoint("LEFT",b,"LEFT",4,0)
    b.icon=icon
    local text=b:CreateFontString(nil,"OVERLAY")
    text:SetFont("Fonts\\FRIZQT__.TTF",11,"OUTLINE")
    ns.Styles:Font((ns.Styles:Family(L.ID)),text,11,"regular","OUTLINE")
    text:SetPoint("LEFT",icon,"RIGHT",4,0);text:SetPoint("RIGHT",b,"RIGHT",-4,0)
    text:SetJustifyH("LEFT")
    b.label=text
    b:SetScript("OnEnter",function(self) self.hover=true;S:Tooltip(self) end)
    b:SetScript("OnLeave",function(self) self.hover=nil;if GameTooltip then GameTooltip:Hide() end end)
    self.button=b
    self:Place()
    return b
end
-- Position from the layout (out of combat: a secure button).
function S:Place()
    local b,rect=self.button,self.rect
    if not (b and rect) then return end
    if locked() then self.pending=true;return end
    b:ClearAllPoints();b:SetPoint("CENTER",UIParent,"CENTER",rect.x,rect.y)
end
function S:Refresh()
    local b=self.button
    if not b then return end
    local text,all=self:Text()
    b.label:SetText(text)
    b.icon:SetTexture(all and self.ICON_OK or self.ICON_BAD)
    if self.bad~=(not all) then self.bad=not all;b.bg:RepaintSurface() end
    if b.hover then self:Tooltip(b) end
    if not locked() then b:SetAttribute("macrotext",L.Log:Macro()) end
end
-- Shows or hides it (out of combat), keeps it current while shown.
function S:Update()
    if locked() then self.pending=true;return end
    if self.pending then self.pending=nil;self:Place() end
    local want=wanted()
    if want and not self.button then self:Create() end
    local b=self.button
    if not b then return end
    if want then
        self:Refresh();b:Show()
        if not self.ticker then self.ticker=C_Timer.NewTicker(self.STEP,function() S:Refresh() end) end
    else
        b:Hide()
        if self.ticker then self.ticker:Cancel();self.ticker=nil end
    end
end
-- Once (marker 2): positions saved for the first, larger box move into the
-- corner (Florian 2026-10-07: "really into the corner"). Later moves stay.
function S:Settle()
    local db=L:DB()
    if db.statusPlaced==self.PLACED then return end
    local x,y=S.Corner()
    local ok=pcall(ns.Layout.Change,ns.Layout,self.LAYOUT,{screen="CENTER",x=x,y=y,width=M.ToNative(self.WIDTH),height=M.ToNative(self.HEIGHT)})
    if ok then db.statusPlaced=self.PLACED end
end
function S:Enable(context)
    self.enabled=true
    if not locked() then self:Settle() end
    context:Subscribe("PLAYER_REGEN_ENABLED",function() if S.pending then S:Update() end end)
    self:Update()
    context:Defer(function()
        S.enabled=false
        if locked() then S.pending=true
            ns.Events:Subscribe(S,"PLAYER_REGEN_ENABLED",function() ns.Events:Release(S);S:Update() end)
        else S:Update() end
    end)
end

-- Default: the top left corner of this screen.
local function corner()
    local w,h=M.ToNative(S.WIDTH),M.ToNative(S.HEIGHT)
    local okW,sw=pcall(UIParent.GetWidth,UIParent)
    local okH,sh=pcall(UIParent.GetHeight,UIParent)
    sw=okW and type(sw)=="number" and sw>0 and sw or 1920
    sh=okH and type(sh)=="number" and sh>0 and sh or 1080
    return -sw/2+w/2+S.MARGIN,sh/2-h/2-S.MARGIN
end
S.Corner=corner
ns.Layout:Register(S.LAYOUT,{label="Combat Text: Status",sizeLocked=true,
    limits={minWidth=40,maxWidth=500,minHeight=10,maxHeight=200},
    defaults=function() local x,y=corner();return {width=M.ToNative(S.WIDTH),height=M.ToNative(S.HEIGHT),screen="CENTER",x=x,y=y} end,
    apply=function(rect) S.rect=rect;S:Place() end,
    enabled=function() return L:Active() end,
    -- In the Layout Editor it shows even while turned off, to place it.
    preview=function(value) S.previewing=value==true;S:Update() end})
-- Style family changed (0.7.4): the box's font follows; border and background repaint themselves.
ns.Styles:OnChanged(S,function()
    local b=S.button
    if b then ns.Styles:Font((ns.Styles:Family(L.ID)),b.label,11,"regular","OUTLINE") end
end)
