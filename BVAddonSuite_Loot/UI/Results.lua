local _,L=...
if not L.ready then return end
-- Roll results: one card per finished roll, ranked by option priority and
-- roll. "toast" cards fade after the hold time (hover keeps them), "sticky"
-- cards stay until closed with X. Native rolls and BV requests alike.
local ns=L.ns
local UI,Theme,D=ns.UI,ns.Theme,ns.DesignSystem.Metrics
local W,R=L.Widgets,L.Rolls
local S={cards={},pool={}}
L.Results=S
local HEADER,ROW=28,17

-- parent: anchor cards come from the pool; history cards live in their window.
function S.Label(c,...) if c.game then return UI:GameLabel(L.ID,...) end;return UI:Label(...) end
function S.Color(c,key) if c.game then return UI:GameStyle(L.ID):Color(key) end;return Theme:Color(key) end
function S:Card(parent)
    local c=not parent and table.remove(self.pool)
    if c then return c end
    -- Cards take the module's in-game style (0.8.91): on screen and, since
    -- the form kit (Loot 0.8.91), in the history window too. Built
    -- inside UI:WithStyle, so the close button follows as well.
    if UI.styleOverride~=UI:GameStyle(L.ID) then return UI:WithStyle(UI:GameStyle(L.ID),self.Card,self,parent) end
    c={rows={},game=true}
    local f
    if parent then f=UI:GamePanel(L.ID,parent,290,60,"canvas")
    else f=UI:GamePanel(L.ID,self.anchor.frame,290,60,"canvas",nil,function() return L:Config().panelOpacity/100 end) end
    W.Owned(f);c.frame=f;f:Hide();f:EnableMouse(true)
    c.item=W:ItemIcon(f,22,c.game);UI:Place(c.item,f,6,3)
    c.name=S.Label(c,f,"",13,false,true);c.name:SetWordWrap(false)
    c.tag=S.Label(c,f,"",10,false);c.tag:SetJustifyH("RIGHT")
    c.close=UI:IconButton(f,"close",function() if c.history then S:HideHistoryCard(c) else S:Release(c) end end,"window")
    D.Size(c.close,18,18)
    c.rule=f:CreateTexture(nil,"ARTWORK");c.rule:SetColorTexture(1,1,1,.08)
    c.fader=W:Fader(f)
    c.item:SetScript("OnEnter",function(owner) if c.roll then W:ItemTooltip(owner,{link=c.roll.link,itemID=c.roll.itemID,roll=c.roll,source="results"}) end end)
    c.item:SetScript("OnLeave",function(owner) W:HideTooltip(owner) end)
    f:SetScript("OnEnter",function() S:Pause(c,true) end)
    f:SetScript("OnLeave",function() S:Pause(c,false) end)
    return c
end
function S:Row(c,index)
    local row=c.rows[index]
    if row then return row end
    row={}
    row.band=c.frame:CreateTexture(nil,"BACKGROUND",nil,2)
    row.rank=S.Label(c,c.frame,"",11,"muted");row.rank:SetJustifyH("RIGHT")
    row.crown=c.frame:CreateTexture(nil,"OVERLAY")
    local path,l,r,t,b=ns.Symbols:Coords("crown",32)
    if path then row.crown:SetTexture(path);row.crown:SetTexCoord(l,r,t,b) end
    row.crown:SetVertexColor(1,.82,.2)
    row.name=S.Label(c,c.frame,"",12,false,true);row.name:SetWordWrap(false)
    row.choice=S.Label(c,c.frame,"",11,false)
    row.value=S.Label(c,c.frame,"",12,false,true);row.value:SetJustifyH("RIGHT")
    c.rows[index]=row
    return row
end
local function hideRow(row) for _,k in ipairs({"band","rank","crown","name","choice","value"}) do row[k]:Hide() end end
function S:Paint(c)
    local roll,cfg,w=c.roll,L:Config(),c.bvWidth or self.anchor:Width()
    local info=roll.link and L.Item(roll.link) or {}
    local r,g,b=L.QualityColor(roll.quality or info.quality or 1)
    c.item:SetItem(roll.icon or info.icon,roll.quality or info.quality)
    UI:Place(c.name,c.frame,34,5);D.Size(c.name,w-110,18)
    c.name:SetText(roll.name or info.name or "?");c.name:SetTextColor(r,g,b)
    c.tag:ClearAllPoints();D.Point(c.tag,"TOPRIGHT",c.frame,"TOPRIGHT",-28,-7);D.Size(c.tag,70,14)
    -- Live card while the roll runs: "Rolling", answers so far, no winner yet.
    if not roll.done then
        local answered=#roll.names
        local total=roll.targetList and #roll.targetList>0 and #roll.targetList or nil
        c.tag:SetText(total and string.format("Rolling %d/%d",answered,total) or "Rolling…")
        c.tag:SetTextColor(S.Color(c,"warning"))
    else
        local source=roll.kind=="bv" and ("ML "..(roll.owner or "")) or (LOOT_ROLL or "Roll")
        if c.history and roll.at and date then source=date("%H:%M",roll.at).."  "..source end
        c.tag:SetText(source)
        c.tag:SetTextColor(S.Color(c,"muted"))
    end
    c.close:ClearAllPoints();D.Point(c.close,"TOPRIGHT",c.frame,"TOPRIGHT",-5,-5)
    -- WoW draws the header rule in its gold edge colour.
    if c.game and select(2,L:Family()).border=="gold" then local r,g,b=S.Color(c,"edge");c.rule:SetColorTexture(r,g,b,.6)
    else c.rule:SetColorTexture(1,1,1,.08) end
    c.rule:ClearAllPoints();D.Point(c.rule,"TOPLEFT",c.frame,"TOPLEFT",6,-HEADER);D.Point(c.rule,"TOPRIGHT",c.frame,"TOPRIGHT",-6,-HEADER);D.Height(c.rule,1)
    local list=R:Ranking(roll)
    local shown=math.min(#list,cfg.resultsRows)
    local y=HEADER+4
    for index=1,math.max(shown,1) do
        local row=self:Row(c,index)
        local entry=list[index]
        hideRow(row)
        if entry then
            local winner=roll.done==true and roll.winner==entry.name
            row.rank:ClearAllPoints();UI:Place(row.rank,c.frame,6,y);D.Size(row.rank,14,ROW);row.rank:SetText(index..".");row.rank:Show()
            row.name:ClearAllPoints();UI:Place(row.name,c.frame,24,y);D.Size(row.name,w-130,ROW)
            local cr,cg,cb=L.ClassColor(entry.class)
            row.name:SetText(entry.name..(entry.manual and " *" or ""));row.name:SetTextColor(cr,cg,cb);row.name:Show()
            local def=entry.choice and L.OptionDef(roll,entry.choice)
            row.choice:ClearAllPoints();D.Point(row.choice,"TOPRIGHT",c.frame,"TOPRIGHT",-62,-y);D.Size(row.choice,80,ROW);row.choice:SetJustifyH("RIGHT")
            row.choice:SetText(def and def.label or "");row.choice:SetTextColor(unpack(def and def.color or {.8,.8,.8}));row.choice:Show()
            row.value:ClearAllPoints();D.Point(row.value,"TOPRIGHT",c.frame,"TOPRIGHT",-8,-y);D.Size(row.value,34,ROW)
            row.value:SetText(entry.value and tostring(entry.value) or (roll.done and "–" or "…"))
            if winner then row.value:SetTextColor(S.Color(c,"accent")) else row.value:SetTextColor(1,1,1) end
            row.value:Show()
            if winner then
                row.band:ClearAllPoints();D.Point(row.band,"TOPLEFT",c.frame,"TOPLEFT",3,-y);D.Point(row.band,"TOPRIGHT",c.frame,"TOPRIGHT",-3,-y);D.Height(row.band,ROW)
                local ar,ag,ab=S.Color(c,"accent");row.band:SetColorTexture(ar,ag,ab,.14);row.band:Show()
                row.crown:ClearAllPoints();D.Point(row.crown,"RIGHT",row.value,"LEFT",-4,0);D.Size(row.crown,12,12);row.crown:Show()
            end
        else
            row.name:ClearAllPoints();UI:Place(row.name,c.frame,10,y);D.Size(row.name,w-20,ROW)
            row.name:SetText(roll.allPassed and "Everyone passed" or "No rolls")
            row.name:SetTextColor(.7,.7,.7);row.name:Show()
        end
        y=y+ROW
    end
    for index=math.max(shown,1)+1,#c.rows do hideRow(c.rows[index]) end
    if #list>shown then
        local row=self:Row(c,shown+1);hideRow(row)
        row.name:ClearAllPoints();UI:Place(row.name,c.frame,24,y);D.Size(row.name,w-40,ROW)
        row.name:SetText("+"..(#list-shown).." more");row.name:SetTextColor(.7,.7,.7);row.name:Show()
        y=y+ROW
    end
    D.Size(c.frame,w,y+6)
end
function S:Frames()
    local out={}
    for i,c in ipairs(self.cards) do out[i]=c.frame end
    return out
end
function S:Release(c)
    if c.timer then c.timer:Cancel();c.timer=nil end
    c.fader:Stop();c.frame:Hide();c.roll=nil
    for i,v in ipairs(self.cards) do if v==c then table.remove(self.cards,i);break end end
    self.pool[#self.pool+1]=c
    if self.anchor then self.anchor:Arrange(self:Frames()) end
end
function S:Hold(c,hold)
    if c.timer then c.timer:Cancel();c.timer=nil end
    -- Pending cards stay until the roll ends; the hold time starts then.
    if L:Config().resultsMode=="sticky" or c.preview or not c.roll.done then c.fader:Stop();return end
    hold=hold or L:Config().resultsDuration
    c.fader:Run(hold,.6)
    c.timer=C_Timer.NewTimer(hold+.8,function() c.timer=nil;S:Release(c) end)
end
function S:Pause(c,over)
    if c.history or not c.roll or not c.roll.done or L:Config().resultsMode=="sticky" or c.preview then return end
    if over then if c.timer then c.timer:Cancel();c.timer=nil end;c.fader:Stop()
    else self:Hold(c,math.max(3,L:Config().resultsDuration/3)) end
end
function S:Relevant(roll)
    if roll.reason=="cancelled" then return false end
    if roll.kind=="bv" then return roll.target==true or roll.owner==L.Me() end
    return #roll.names>0 or roll.winner~=nil or roll.allPassed==true
end
-- Mode "tooltip" (0.8.90): no cards; the same overview card as a tooltip at
-- the mouse while it is over a roll bar (RollFrame), updated live. It
-- follows the cursor with a short ticker that only runs while it is shown
-- (this project allows no per-frame update scripts).
local TIP_STEP,TIP_GAP=.03,16
function S:PlaceTip()
    local c=self.tip
    if not (c and c.frame:IsShown()) then return end
    local x,y=GetCursorPosition()
    local scale=c.frame:GetEffectiveScale()
    c.frame:ClearAllPoints()
    c.frame:SetPoint("TOPLEFT",UIParent,"BOTTOMLEFT",x/scale+TIP_GAP,y/scale-TIP_GAP)
end
function S:ShowTip(owner,roll)
    if not roll then return end
    local c=self.tip
    if not c then
        c=self:Card(UIParent);c.tipCard=true
        c.frame:EnableMouse(false);c.frame:SetFrameStrata("TOOLTIP");c.frame:SetClampedToScreen(true)
        self.tip=c
    end
    c.roll,c.bvWidth=roll,L:Config().resultsWidth
    self:Paint(c);c.close:Hide()
    c.fader:Stop();c.frame:SetAlpha(1);c.frame:Show()
    self.tipOwner=owner
    self:PlaceTip()
    if not self.tipTicker then self.tipTicker=C_Timer.NewTicker(TIP_STEP,function() S:PlaceTip() end) end
end
function S:HideTip(owner)
    if not self.tip or owner and self.tipOwner~=owner then return end
    self.tip.frame:Hide();self.tip.roll=nil;self.tipOwner=nil
    if self.tipTicker then self.tipTicker:Cancel();self.tipTicker=nil end
end
function S:Add(roll,preview)
    if not self.anchor or not L:Config().results and not preview then return end
    if L:Config().resultsMode=="tooltip" and not preview then
        if self.tip and self.tip.roll==roll then self:Paint(self.tip);self.tip.close:Hide() end
        return nil
    end
    for _,c in ipairs(self.cards) do
        if c.roll==roll then
            self:Paint(c)
            if roll.done then self:Hold(c) end
            self.anchor:Arrange(self:Frames())
            return c
        end
    end
    local c=self:Card()
    c.roll,c.preview=roll,preview
    table.insert(self.cards,1,c)
    while #self.cards>L:Config().resultsMax do self:Release(self.cards[#self.cards]) end
    self:Paint(c);c.frame:Show();self:Hold(c)
    self.anchor:Arrange(self:Frames())
    return c
end
function S:Clear() for i=#self.cards,1,-1 do self:Release(self.cards[i]) end end
function S:Repaint() for _,c in ipairs(self.cards) do self:Paint(c) end;if self.anchor then self.anchor:Arrange(self:Frames()) end end

function S:Preview(on)
    self:Clear()
    if not on then return end
    local roll={key="preview:results",kind="native",link="item:19019",itemID=19019,name="Thunderfury, Blessed Blade of the Windseeker",quality=5,
        icon="Interface\\Icons\\INV_Sword_39",options=L.NATIVE_ORDER,choices={},names={},winner="Thalya",done=true}
    for _,row in ipairs({{"Thalya","need",94,"PRIEST"},{"Brokk","need",61,"WARRIOR"},{"Mirelle","greed",88,"MAGE"},{"Orrin","pass",nil,"ROGUE"}}) do
        roll.names[#roll.names+1]=row[1];roll.choices[row[1]]={name=row[1],choice=row[2],value=row[3],class=row[4]}
    end
    self:Add(roll,true)
end
-- History: the last 50 results per profile, as plain copies (survives /reload).
local KEEP=50
function S:Store()
    local cfg=L:Config()
    if type(cfg.history)~="table" then cfg.history={} end
    return cfg.history
end
function S:Remember(roll)
    local entries={}
    for i,e in ipairs(R:Ranking(roll)) do entries[i]={name=e.name,class=e.class,choice=e.choice,value=e.value,manual=e.manual==true} end
    local options={}
    for i,o in ipairs(roll.options or {}) do options[i]=o end
    local store=self:Store()
    table.insert(store,1,{kind=roll.kind,link=roll.link,name=roll.name,quality=roll.quality,icon=roll.icon,owner=roll.owner,
        winner=roll.winner,allPassed=roll.allPassed==true,options=options,
        custom=roll.custom and {label=roll.custom.label,symbol=roll.custom.symbol} or nil,
        at=time and time() or 0,entries=entries})
    while #store>KEEP do table.remove(store) end
end
-- A stored result as a roll the card painter understands.
function S.Rehydrate(saved)
    local roll={key="history",kind=saved.kind,link=saved.link,name=saved.name,quality=saved.quality,icon=saved.icon,owner=saved.owner,
        winner=saved.winner,allPassed=saved.allPassed,options=saved.options or L.NATIVE_ORDER,custom=saved.custom,
        done=true,at=saved.at,names={},choices={},targetList={},itemID=L.ItemID(saved.link)}
    for _,e in ipairs(type(saved.entries)=="table" and saved.entries or {}) do
        if type(e.name)=="string" then
            roll.names[#roll.names+1]=e.name
            roll.choices[e.name]={name=e.name,class=e.class,choice=e.choice,value=e.value,manual=e.manual}
        end
    end
    return roll
end
local HISTORY_W,HISTORY_H=340,640
function S:HistoryWindow()
    if self.history then return self.history end
    return UI:WithStyle(UI:GameStyle(L.ID),self.BuildHistory,self)
end
function S:BuildHistory()
    local w=W.Owned(UI:Dialog("BVLootHistoryWindow",HISTORY_W,HISTORY_H))
    self.history=w;w.cards={}
    w.list=CreateFrame("ScrollFrame",nil,w.content);UI:Place(w.list,w.content,8,8);D.Size(w.list,HISTORY_W-16,HISTORY_H-36-16)
    w.list:SetClipsChildren(true);w.list:EnableMouseWheel(true)
    w.child=CreateFrame("Frame",nil,w.list);D.Size(w.child,HISTORY_W-24,10);w.list:SetScrollChild(w.child)
    w.list:SetScript("OnMouseWheel",function(_,delta) S:ScrollHistory(-delta*60) end)
    w.empty=UI:Label(w.content,"No roll results yet.",12,"muted");UI:Place(w.empty,w.content,16,16);D.Size(w.empty,HISTORY_W-32,18)
    return w
end
function S:ScrollHistory(delta)
    local w=self.history
    local range=math.max(0,D.GetHeight(w.child)-D.GetHeight(w.list))
    w.scroll=math.max(0,math.min(range,(w.scroll or 0)+delta))
    w.list:SetVerticalScroll(D.ToNative(w.scroll))
end
function S:LayoutHistory()
    local w=self.history
    local y=0
    for _,c in ipairs(w.cards) do
        if c.frame:IsShown() then UI:Place(c.frame,w.child,0,y);y=y+D.GetHeight(c.frame)+6 end
    end
    D.Height(w.child,math.max(10,y))
    w.empty:SetShown(y==0)
    self:ScrollHistory(0)
end
function S:HideHistoryCard(c) c.frame:Hide();c.roll=nil;self:LayoutHistory() end
-- Shows the last count results (default 10) in their own window.
function S:ShowHistory(count)
    count=math.max(1,math.min(KEEP,math.floor(tonumber(count) or 10)))
    local w=self:HistoryWindow()
    local store=self:Store()
    local shown=math.min(count,#store)
    w.title:SetText(string.format("Roll results · last %d",shown))
    for index=1,math.max(shown,#w.cards) do
        local c=w.cards[index]
        if index<=shown then
            if not c then c=self:Card(w.child);c.history=true;c.bvWidth=HISTORY_W-28;w.cards[index]=c end
            c.roll=S.Rehydrate(store[index]);self:Paint(c);c.frame:SetAlpha(1);c.frame:Show()
        elseif c then c.roll=nil;c.frame:Hide() end
    end
    w.scroll=0
    w:Show()
    self:LayoutHistory()
    return shown
end
function S:Create()
    if self.anchor then return end
    self.anchor=W:Anchor({layout="bv:lootresults",label="Loot Results",screen="TOPRIGHT",x=-260,y=-260,
        width=function() return L:Config().resultsWidth end,height=function() return HEADER+ROW+10 end,
        grow=function() return L:Config().resultsGrow end,spacing=function() return 6 end,
        enabled=function() return L:Config().results and L:Config().resultsMode~="tooltip" end,
        resized=function(width)
            if ns.Layout.draft then return end
            L:Config().resultsWidth=math.floor(width+.5)
            S:Repaint()
        end,
        preview=function(on) S:Preview(on) end})
end
function S:Enable(context)
    self:Create()
    L:On("RollFinished",self,function(roll)
        if not S:Relevant(roll) then return end
        S:Remember(roll)
        S:Add(roll)
    end)
    -- A card appears with the first answer and updates live until the end.
    L:On("RollUpdated",self,function(roll)
        if S.tip and S.tip.roll==roll then S:Paint(S.tip);S.tip.close:Hide() end
        for _,c in ipairs(S.cards) do if c.roll==roll then S:Paint(c);S.anchor:Arrange(S:Frames());return end end
        if not roll.done and #roll.names>0 and S:Relevant(roll) then S:Add(roll) end
    end)
    context:Defer(function() L:Off(self);S:Clear();S:HideTip() end)
    W:Refresh()
end
-- The layout element exists from load on, so the Layout Editor knows it.
S:Create()
