local _,E=...
if not E.ready then return end
-- The level-up card's look and motion (Florian 2026-10-16, preview
-- artifacts/levelup-preview/2026-10-16/levelup.html): a faint see-through box
-- in the upper middle; the card comes down, the level counts up, the line
-- opens from the middle; each value row shows the old value, then
-- "-> new +gain" opens left to right; then "New at your trainer", the
-- abilities pop in one by one, the talent point below. It stays its time
-- (paused while the mouse is over it, a click closes it) and fades out.
-- Motion runs on a short ticker only while it plays.
local ns=BVAddonSuiteCore
local UI,M=ns.UI,ns.DesignSystem.Metrics
local C={}
E.LevelCard=C
if ns.ExperienceLevelUp then ns.ExperienceLevelUp.Card=C end
C.WIDTH=460;C.PAD=22;C.ROW=24;C.ICON=34;C.TICK=.02
C.TOP=160            -- like the notification stage
C.ALPHA=.3           -- the box: faint (Florian: not heavy for an info window)
-- Timeline (seconds).
C.T={enter=.45,count=.42,rule0=.35,rule=.5,sub0=.55,rows=.9,rowStep=.13,rowIn=.25,wipe0=.26,wipe=.45,gap=.2,iconStep=.15,pop=.42,leave=.6}

local function shadow(label) if label.SetShadowOffset then label:SetShadowOffset(1,-1);label:SetShadowColor(0,0,0,.85) end end
local function width(label) return label.GetStringWidth and label:GetStringWidth() or 0 end
local function ease(t) t=math.max(0,math.min(1,t));return 1-(1-t)^3 end
-- A pop: 0 -> 1.15 -> 1.
local function pop(t)
    t=math.max(0,math.min(1,t))
    if t<.7 then return 1.15*ease(t/.7) end
    return 1.15-.15*ease((t-.7)/.3)
end

function C:Frame()
    if self.frame then return self.frame end
    UI:WithStyle(UI:GameStyle(nil),function()
        local f=UI:Panel(UIParent,C.WIDTH,200,"panel",14,C.ALPHA)
        f:Hide();f:SetFrameStrata("HIGH");f:SetClampedToScreen(true);f:EnableMouse(true)
        if ns.ExternalFrames then ns.ExternalFrames:MarkOwned(f) end
        f:SetScript("OnEnter",function() C.paused=true end)
        f:SetScript("OnLeave",function() C.paused=nil;C.leaveAt=C.clock+C.hold end)
        f:SetScript("OnMouseUp",function() C:Hide() end)
        f.title=UI:Label(f,"",34,"text",true);f.title:SetJustifyH("CENTER");shadow(f.title)
        f.rule=f:CreateTexture(nil,"ARTWORK");f.rule:SetTexture("Interface\\Buttons\\WHITE8X8")
        f.sub=UI:Label(f,"",15,"muted");f.sub:SetJustifyH("CENTER");shadow(f.sub)
        f.section=UI:Label(f,"NEW AT YOUR TRAINER",11,"accent",true);shadow(f.section)
        f.talent=UI:Label(f,"",14,"warning");shadow(f.talent)
        f.questHead=UI:Label(f,"NEW CLASS QUEST",11,"accent",true);shadow(f.questHead)
        f.rows,f.icons,f.quests={},{},{}
        self.frame=f
    end)
    return self.frame
end
-- A value row: name, old value, and the part that opens ("-> new +gain").
function C:Row(i)
    local f=self.frame
    local r=f.rows[i]
    if r then return r end
    UI:WithStyle(UI:GameStyle(nil),function()
        r=CreateFrame("Frame",nil,f);M.Size(r,(C.WIDTH-2*C.PAD-20)/2,C.ROW)
        r.key=UI:Label(r,"",15,"muted");M.Point(r.key,"LEFT",r,"LEFT",0,0);shadow(r.key)
        r.old=UI:Label(r,"",15,"text");M.Point(r.old,"LEFT",r,"LEFT",78,0);shadow(r.old)
        r.clip=CreateFrame("Frame",nil,r);r.clip:SetClipsChildren(true);M.Height(r.clip,C.ROW)
        r.to=UI:Label(r.clip,"→",15,"muted");M.Point(r.to,"LEFT",r.clip,"LEFT",4,0);shadow(r.to)
        r.new=UI:Label(r.clip,"",15,"text",true);M.Point(r.new,"LEFT",r.to,"RIGHT",5,0);shadow(r.new)
        r.gain=UI:Label(r.clip,"",13,"success",true);M.Point(r.gain,"LEFT",r.new,"RIGHT",5,0);shadow(r.gain)
        f.rows[i]=r
    end)
    return r
end
function C:Icon(i)
    local f=self.frame
    local b=f.icons[i]
    if b then return b end
    b=CreateFrame("Frame",nil,f);M.Size(b,C.ICON,C.ICON);b:EnableMouse(true)
    -- The pop scales an inner frame centred on the slot: a scaled frame's
    -- anchor offsets scale too (Florian's video 2026-10-16: the icons jumped
    -- in from below right).
    b.pop=CreateFrame("Frame",nil,b);M.Size(b.pop,C.ICON,C.ICON);b.pop:SetPoint("CENTER",b,"CENTER",0,0)
    local p=b.pop
    b.tex=p:CreateTexture(nil,"ARTWORK");b.tex:SetAllPoints(p);b.tex:SetTexCoord(.08,.92,.08,.92)
    b.edge=p:CreateTexture(nil,"OVERLAY");b.edge:SetTexture("Interface\\Buttons\\WHITE8X8");b.edge:SetPoint("TOPLEFT",p,"TOPLEFT",-1,1);b.edge:SetPoint("BOTTOMRIGHT",p,"BOTTOMRIGHT",1,-1)
    b.edge:SetVertexColor(1,1,1,.18);b.edge:SetDrawLayer("BACKGROUND")
    UI:WithStyle(UI:GameStyle(nil),function() b.rank=UI:Label(p,"",10,"text",true);M.Point(b.rank,"BOTTOMRIGHT",p,"BOTTOMRIGHT",-1,1);shadow(b.rank) end)
    b:SetScript("OnEnter",function(self)
        C.paused=true
        if GameTooltip and self.spell then GameTooltip:SetOwner(self,"ANCHOR_BOTTOM");pcall(GameTooltip.SetSpellByID,GameTooltip,self.spell);GameTooltip:Show() end
    end)
    b:SetScript("OnLeave",function() C.paused=nil;C.leaveAt=C.clock+C.hold;if GameTooltip then GameTooltip:Hide() end end)
    f.icons[i]=b
    return b
end

-- A class quest row: its icon in a slot, the text.
function C:Quest(i)
    local f=self.frame
    local r=f.quests[i]
    if r then return r end
    UI:WithStyle(UI:GameStyle(nil),function()
        r=CreateFrame("Frame",nil,f);M.Size(r,C.WIDTH-2*C.PAD,24)
        r.slot=CreateFrame("Frame",nil,r);M.Size(r.slot,24,24);M.Point(r.slot,"LEFT",r,"LEFT",0,0)
        r.tex=r.slot:CreateTexture(nil,"ARTWORK");r.tex:SetAllPoints(r.slot);r.tex:SetTexCoord(.08,.92,.08,.92)
        r.text=UI:Label(r,"",15,"text",true);M.Point(r.text,"LEFT",r.slot,"RIGHT",10,0);shadow(r.text)
        f.quests[i]=r
    end)
    return r
end
-- Lays the card out for a level-up and plays it: data {level, stats =
-- {{name, old, new}}, abilities = {{id, name, icon, rank}}, talents, took}.
function C:Play(data,hold)
    local f=self:Frame()
    local T=C.T
    self.hold=math.max(1,hold or 8)
    local inner=C.WIDTH-2*C.PAD
    local y=18
    f.title:ClearAllPoints();M.Point(f.title,"TOP",f,"TOP",0,-y);M.Size(f.title,inner,38)
    y=y+44
    local ar,ag,ab=UI:GameStyle(nil):Color("accent")
    f.rule:SetVertexColor(ar,ag,ab,.7);f.rule:ClearAllPoints();M.Point(f.rule,"TOP",f,"TOP",0,-y);M.Size(f.rule,0.01,1)
    y=y+8
    f.sub:SetText(data.took and ("Level "..(data.level-1).." took "..data.took) or "A new level")
    f.sub:ClearAllPoints();M.Point(f.sub,"TOP",f,"TOP",0,-y);M.Size(f.sub,inner,18)
    y=y+30
    -- Two columns of values.
    local colW=(inner-20)/2
    for i,s in ipairs(data.stats) do
        local r=self:Row(i)
        r.key:SetText(s[1]);r.old:SetText(tostring(s[2]));r.new:SetText(tostring(s[3]));r.gain:SetText("+"..(s[3]-s[2]))
        local col,line=(i-1)%2,math.floor((i-1)/2)
        r:ClearAllPoints();M.Point(r,"TOPLEFT",f,"TOPLEFT",C.PAD+col*(colW+20),-(y+line*C.ROW))
        r.clip:ClearAllPoints();r.clip:SetPoint("LEFT",r.old,"RIGHT",0,0)
        r.full=M.ToDesign(width(r.to)+width(r.new)+width(r.gain))+20
        M.Width(r.clip,.01);r:SetAlpha(0);r:Show()
    end
    for i=#data.stats+1,#f.rows do f.rows[i]:Hide() end
    y=y+math.ceil(#data.stats/2)*C.ROW
    -- Abilities.
    local shown=math.min(#data.abilities,E.LevelUp.MAXICONS)
    f.section:SetShown(shown>0);f.section:SetAlpha(0)
    if shown>0 then
        y=y+14
        f.section:ClearAllPoints();M.Point(f.section,"TOPLEFT",f,"TOPLEFT",C.PAD,-y)
        y=y+20
        for i=1,shown do
            local a=data.abilities[i]
            local b=self:Icon(i)
            b.spell=a.id;b.tex:SetTexture(a.icon);b.rank:SetText(a.rank and tostring(a.rank) or "")
            b:ClearAllPoints();M.Point(b,"CENTER",f,"TOPLEFT",C.PAD+C.ICON/2+(i-1)*(C.ICON+8),-(y+C.ICON/2))
            b.pop:SetScale(.01);b:SetAlpha(0);b:Show()
        end
        y=y+C.ICON
    end
    for i=shown+1,#f.icons do f.icons[i]:Hide() end
    local more=#data.abilities-shown
    local talent=data.talents and data.talents>0 and ("+"..data.talents.." talent point"..(data.talents>1 and "s" or "")) or nil
    if more>0 then talent=(talent and (talent.."   ") or "").."+"..more.." more at your trainer" end
    f.talent:SetShown(talent~=nil);f.talent:SetAlpha(0)
    if talent then
        y=y+10
        f.talent:SetText(talent);f.talent:ClearAllPoints();M.Point(f.talent,"TOPLEFT",f,"TOPLEFT",C.PAD,-y)
        y=y+18
    end
    -- Class quests (ClassQuests.lua): their spell's icon or a symbol, the text.
    local quests=data.quests or {}
    f.questHead:SetShown(#quests>0);f.questHead:SetAlpha(0)
    if #quests>0 then
        y=y+14
        f.questHead:ClearAllPoints();M.Point(f.questHead,"TOPLEFT",f,"TOPLEFT",C.PAD,-y)
        y=y+20
        for i,q in ipairs(quests) do
            local r=self:Quest(i)
            r.tex:SetShown(q.icon~=nil)
            if q.icon then r.tex:SetTexture(q.icon) end
            if r.symbol then r.symbol:Hide() end
            if not q.icon and q.symbol then r.symbol=r.symbol or UI:Icon(r,q.symbol,16,"accent");M.Point(r.symbol,"CENTER",r.slot,"CENTER",0,0);r.symbol:Show() end
            r.text:SetText(q.text)
            r:ClearAllPoints();M.Point(r,"TOPLEFT",f,"TOPLEFT",C.PAD,-y);r:SetAlpha(0);r:Show()
            y=y+30
        end
    end
    for i=#quests+1,#f.quests do f.quests[i]:Hide() end
    y=y+20
    M.Height(f,y)
    -- The timeline.
    self.data=data;self.clock=0;self.paused=nil
    local rowsEnd=T.rows+#data.stats*T.rowStep+T.wipe0+T.wipe
    self.sectionAt=rowsEnd
    self.iconsAt=rowsEnd+T.gap
    self.talentAt=self.iconsAt+shown*T.iconStep+(shown>0 and T.pop or 0)
    self.questsAt=self.talentAt+(talent and .3 or 0)
    self.doneAt=self.questsAt+#quests*.2+.3
    self.leaveAt=self.doneAt+self.hold
    self.shown=shown
    f.title:SetText("Level "..math.max(1,data.level-1))
    f:SetAlpha(0);self:Place(-18);f:Show()
    if self.ticker then self.ticker:Cancel() end
    self.ticker=C_Timer.NewTicker(C.TICK,function() C:Step(C.TICK) end)
    self:Step(0)
end
function C:Place(dy)
    local f=self.frame
    f:ClearAllPoints();M.Point(f,"TOP",UIParent,"TOP",0,-(C.TOP+dy))
end
function C:Step(dt)
    local f,T,data=self.frame,C.T,self.data
    if not (f and data) then return end
    if not (self.paused and self.clock>=self.doneAt) then self.clock=self.clock+dt end
    local t=self.clock
    -- Enter, count up, line, subtitle.
    local e=ease(t/T.enter)
    f:SetAlpha(e);self:Place(-18*(1-e))
    f.title:SetText("Level "..(t>=T.count and data.level or math.max(1,data.level-1)))
    M.Width(f.rule,math.max(.01,(C.WIDTH-2*C.PAD)*ease((t-T.rule0)/T.rule)))
    f.sub:SetAlpha(ease((t-T.sub0)/.4))
    -- Value rows: in, then the gain opens left to right.
    for i=1,#data.stats do
        local r=f.rows[i]
        local at=T.rows+(i-1)*T.rowStep
        r:SetAlpha(ease((t-at)/T.rowIn))
        M.Width(r.clip,math.max(.01,r.full*ease((t-at-T.wipe0)/T.wipe)))
    end
    f.section:SetAlpha(ease((t-self.sectionAt)/.3))
    for i=1,self.shown do
        local b=f.icons[i]
        local p=(t-self.iconsAt-(i-1)*T.iconStep)/T.pop
        b.pop:SetScale(math.max(.01,pop(p)));b:SetAlpha(math.max(0,math.min(1,p*3)))
    end
    f.talent:SetAlpha(ease((t-self.talentAt)/.3))
    f.questHead:SetAlpha(ease((t-self.questsAt)/.3))
    for i=1,#(data.quests or {}) do f.quests[i]:SetAlpha(ease((t-self.questsAt-.15-(i-1)*.2)/.3)) end
    -- Stay, then leave.
    if t>=self.leaveAt then
        local l=(t-self.leaveAt)/T.leave
        f:SetAlpha(math.max(0,1-l));self:Place(10*ease(l))
        if l>=1 then self:Hide() end
    end
end
function C:Hide()
    if self.ticker then self.ticker:Cancel();self.ticker=nil end
    if self.frame then self.frame:Hide() end
    self.data=nil
end
