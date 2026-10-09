local _,Q=...
if not Q.ready then return end
-- Details of the selected quest (shown only for a selection; it widens the
-- whole, the map stays): objectives with bars, quest text (collapsible),
-- rewards with quality colours and an upgrade arrow, actions.
local ns=Q.ns
local UI,M=ns.UI,ns.DesignSystem.Metrics
local Det={objectives={},rewards={},textOpen=true}
Q.Details=Det
local PAD,ACTIONS=12,64
local function style() return Q:Style() end
local QUALITY={[0]={.62,.62,.62},[1]={1,1,1},[2]={.12,1,0},[3]={0,.44,.87},[4]={.64,.21,.93},[5]={1,.5,0}}

function Det:Build(pane)
    self.pane=pane
    local s=style()
    self.close=UI:IconButton(pane,"close",function() Det:Select(nil) end,"window");M.Size(self.close,22,22)
    self.title=UI:Label(pane,"",15,"text",true);self.title:SetWordWrap(true)
    self.sub=UI:Label(pane,"",11,"muted")
    self.scrollFrame=CreateFrame("ScrollFrame",nil,pane);self.scrollFrame:SetClipsChildren(true);self.scrollFrame:EnableMouseWheel(true)
    self.child=CreateFrame("Frame",nil,self.scrollFrame);self.scrollFrame:SetScrollChild(self.child)
    self.scroll=0
    self.scrollFrame:SetScript("OnMouseWheel",function(_,delta) Det:Scroll(-delta*40) end)
    local c=self.child
    self.objectivesHead=UI:Label(c,"OBJECTIVES",11,"accent",true)
    self.textHead=UI:Button(c,"Quest text",120,function() Det.textOpen=not Det.textOpen;Det:Refresh() end,"ghost")
    self.textHead:SetLabelInsets(0,8,"LEFT")
    self.text=UI:Label(c,"",12,"text");self.text:SetWordWrap(true);self.text:SetJustifyV("TOP")
    self.rewardsHead=UI:Label(c,"REWARDS",11,"accent",true)
    self.money=UI:Label(c,"",12,"text")
    self.choiceHead=UI:Label(c,"Choose one:",11,"muted")
    self.track=UI:Button(pane,"Track",96,function() Det:Action("track") end)
    self.share=UI:Button(pane,"Share",96,function() Det:Action("share") end)
    self.navigate=UI:Button(pane,"Navigate",96,function() Det:Action("navigate") end)
    UI:AttachTooltip(self.navigate,"Navigate","Sets this quest as the navigation target (arrow and distance on screen).")
    self.linkButton=UI:Button(pane,"Wowhead",96,function() Det:Action("link") end)
    self.abandon=UI:Button(pane,"Abandon",96,function() Det:Action("abandon") end,"danger")
    self.link=s:Input(pane,200,false,"",nil);self.link:Hide()
    self.link:SetScript("OnEscapePressed",function(box) box:ClearFocus();box:Hide() end)
end
function Det:Select(questID)
    self.questID=questID
    self.scroll=0
    if self.link then self.link:Hide() end
    if Q.Panes.frame then Q.Panes:Layout() end
    Q.List:Refresh()
end
function Det:Layout()
    if not self.pane then return end
    local pane,width=self.pane,M.GetWidth(self.pane)
    self.close:ClearAllPoints();M.Point(self.close,"TOPRIGHT",pane,"TOPRIGHT",-6,-6)
    UI:Place(self.title,pane,PAD,10);M.Width(self.title,width-PAD*2-26)
    self.scrollFrame:ClearAllPoints()
    M.Point(self.scrollFrame,"TOPLEFT",pane,"TOPLEFT",PAD,-60);M.Point(self.scrollFrame,"BOTTOMRIGHT",pane,"BOTTOMRIGHT",-PAD,ACTIONS+6)
    M.Width(self.child,width-PAD*2)
    local buttons={self.track,self.share,self.navigate,self.linkButton,self.abandon}
    local bw=(width-PAD*2-8)/3
    for i,b in ipairs(buttons) do
        local col,row=(i-1)%3,math.floor((i-1)/3)
        -- Two rows of actions at the bottom: row 0 above row 1.
        b:ClearAllPoints();M.Point(b,"BOTTOMLEFT",pane,"BOTTOMLEFT",PAD+col*(bw+4),8+(1-row)*30);M.Size(b,bw,26)
    end
    self.link:ClearAllPoints();M.Point(self.link,"BOTTOMLEFT",pane,"BOTTOMLEFT",PAD,ACTIONS+8);M.Size(self.link,width-PAD*2,24)
    self:Refresh()
end
local function textHeight(label,width)
    M.Width(label,width)
    local h=label.GetStringHeight and label:GetStringHeight() or 0
    h=type(h)=="number" and M.ToDesign(h) or 0
    if h<=0 then h=math.ceil(#(label:GetText() or "")/math.max(1,width/7))*15 end
    M.Height(label,math.max(14,h));return math.max(14,h)
end
function Det:Objective(index)
    local o=self.objectives[index]
    if o then return o end
    return UI:WithStyle(style(),function()
        o={label=UI:Label(self.child,"",12,"text"),back=self.child:CreateTexture(nil,"BORDER"),bar=self.child:CreateTexture(nil,"ARTWORK")}
        o.back:SetTexture("Interface\\Buttons\\WHITE8X8");o.bar:SetTexture("Interface\\Buttons\\WHITE8X8")
        self.objectives[index]=o
        return o
    end)
end
function Det:Reward(index)
    local r=self.rewards[index]
    if r then return r end
    return UI:WithStyle(style(),function()
        r=CreateFrame("Button",nil,self.child)
        r.icon=r:CreateTexture(nil,"ARTWORK");r.icon:SetTexCoord(.08,.92,.08,.92)
        r.edge=r:CreateTexture(nil,"BORDER");r.edge:SetTexture("Interface\\Buttons\\WHITE8X8")
        r.name=UI:Label(r,"",12,false);r.name:SetWordWrap(false)
        r.upgrade=UI:Label(r,"",12,false,true);r.upgrade:SetText("▲");r.upgrade:SetTextColor(.3,.95,.3)
        r:SetScript("OnEnter",function(btn)
            if not (GameTooltip and btn.data) then return end
            GameTooltip:SetOwner(btn,"ANCHOR_RIGHT")
            if btn.data.kind=="choice" and GameTooltip.SetQuestLogItem then pcall(GameTooltip.SetQuestLogItem,GameTooltip,"choice",btn.data.index,Det.questID)
            elseif GameTooltip.SetQuestLogItem then pcall(GameTooltip.SetQuestLogItem,GameTooltip,"reward",btn.data.index,Det.questID) end
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end)
        self.rewards[index]=r
        return r
    end)
end
local function money(copper)
    if type(copper)~="number" or copper<=0 then return nil end
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    local g,s,c=math.floor(copper/10000),math.floor(copper/100)%100,copper%100
    return (g>0 and g.."g " or "")..((g>0 or s>0) and s.."s " or "")..c.."c"
end
function Det:Refresh()
    if not self.pane then return end
    local d=self.questID and Q.Data:Details(self.questID)
    if not d then if self.questID then self.questID=nil;Q.Panes:Layout() end;return end
    local q,cfg,s=d.quest,Q:Config(),style()
    local width=M.GetWidth(self.child)
    self.title:SetText(q.title);local r,g,b=Q.Data.Color(q.difficulty);self.title:SetTextColor(r,g,b)
    local sub={"Level "..(q.level or "?"),q.zone}
    if q.elite then sub[#sub+1]="Elite" end
    if q.group and q.group>1 then sub[#sub+1]="Group "..q.group end
    if q.distance and not q.ready then sub[#sub+1]=Q.List.Yards(q.distance) end
    self.sub:SetText(table.concat(sub," · "));UI:Place(self.sub,self.pane,PAD,36);M.Size(self.sub,width,14)
    local y=0
    UI:Place(self.objectivesHead,self.child,0,y);M.Size(self.objectivesHead,width,14);y=y+20
    local ar,ag,ab=s:Color("accent")
    local shown=0
    for index,o in ipairs(q.objectives) do
        local row=self:Objective(index);shown=index
        row.label:SetText(o.text);row.label:SetTextColor(s:Color(o.finished and "muted" or "text"))
        if o.finished then row.label:SetTextColor(.45,.8,.45) end
        UI:Place(row.label,self.child,0,y);local h=textHeight(row.label,width);y=y+h+2
        if o.need and o.need>1 then
            UI:Place(row.back,self.child,0,y);M.Size(row.back,width,4);row.back:SetVertexColor(1,1,1,.08);row.back:Show()
            UI:Place(row.bar,self.child,0,y);M.Size(row.bar,math.max(.01,width*(o.have or 0)/o.need),4);row.bar:SetVertexColor(ar,ag,ab,.9);row.bar:Show()
            y=y+8
        else row.back:Hide();row.bar:Hide() end
        row.label:Show();y=y+4
    end
    if #q.objectives==0 then
        local row=self:Objective(1);shown=1
        row.label:SetText(q.ready and "Ready to turn in." or "No objectives listed.");row.label:SetTextColor(s:Color("muted"))
        UI:Place(row.label,self.child,0,y);y=y+textHeight(row.label,width)+4;row.back:Hide();row.bar:Hide();row.label:Show()
    end
    for index=shown+1,#self.objectives do local o=self.objectives[index];o.label:Hide();o.back:Hide();o.bar:Hide() end
    -- Quest text, collapsible.
    self.textHead:SetShown(cfg.detailsText);self.text:SetShown(cfg.detailsText and self.textOpen)
    if cfg.detailsText then
        y=y+6
        self.textHead:SetLabelText((self.textOpen and "▾ " or "▸ ").."Quest text")
        UI:Place(self.textHead,self.child,0,y);M.Size(self.textHead,width,20);y=y+24
        if self.textOpen then
            local body=d.description
            if d.objectives~="" then body=d.objectives.."\n\n"..body end
            self.text:SetText(body);self.text:SetTextColor(s:Color("text"))
            UI:Place(self.text,self.child,0,y);y=y+textHeight(self.text,width)+8
        end
    end
    -- Rewards.
    local count=0
    local showRewards=cfg.detailsRewards
    self.rewardsHead:SetShown(showRewards);self.money:SetShown(showRewards);self.choiceHead:Hide()
    if showRewards then
        y=y+6
        UI:Place(self.rewardsHead,self.child,0,y);M.Size(self.rewardsHead,width,14);y=y+20
        local line={}
        if type(d.xp)=="number" and d.xp>0 then line[#line+1]=(BreakUpLargeNumbers and BreakUpLargeNumbers(d.xp) or d.xp).." XP" end
        local coins=money(d.money);if coins then line[#line+1]=coins end
        self.money:SetText(#line>0 and table.concat(line,"   ") or "No XP or money")
        UI:Place(self.money,self.child,0,y);M.Size(self.money,width,16);y=y+20
        local function item(data)
            count=count+1
            local r=self:Reward(count);r.data=data
            r.icon:SetTexture(data.texture);local c=QUALITY[data.quality or 1] or QUALITY[1]
            r.edge:SetVertexColor(c[1],c[2],c[3],1)
            r.name:SetText((data.count and data.count>1 and (data.count.."x ") or "")..data.name);r.name:SetTextColor(c[1],c[2],c[3])
            r.upgrade:SetShown(Q.Data.Upgrade(data.itemID))
            UI:Place(r,self.child,0,y);M.Size(r,width,26)
            r.edge:ClearAllPoints();M.Point(r.edge,"LEFT",r,"LEFT",0,0);M.Size(r.edge,26,26)
            r.icon:ClearAllPoints();M.Point(r.icon,"CENTER",r.edge,"CENTER",0,0);M.Size(r.icon,24,24)
            r.name:ClearAllPoints();M.Point(r.name,"LEFT",r,"LEFT",32,0);M.Size(r.name,width-56,26)
            r.upgrade:ClearAllPoints();M.Point(r.upgrade,"RIGHT",r,"RIGHT",-2,0);M.Size(r.upgrade,16,26)
            r:Show();y=y+30
        end
        for _,data in ipairs(d.rewards) do item(data) end
        if #d.choices>0 then
            UI:Place(self.choiceHead,self.child,0,y);M.Size(self.choiceHead,width,14);self.choiceHead:Show();y=y+18
            for _,data in ipairs(d.choices) do item(data) end
        end
    end
    for index=count+1,#self.rewards do self.rewards[index]:Hide() end
    M.Height(self.child,math.max(1,y))
    self:Scroll(0)
    -- Actions.
    self.track:SetLabelText(q.watched and "Untrack" or "Track")
    if d.pushable then self.share:Enable() else self.share:Disable() end
end
function Det:Scroll(delta)
    local h=M.GetHeight(self.child)-M.GetHeight(self.scrollFrame)
    self.scroll=math.max(0,math.min(math.max(0,h),self.scroll+delta))
    self.scrollFrame:SetVerticalScroll(M.ToNative(self.scroll))
end
function Det:Action(kind)
    local q=self.questID and Q.Data.byID[self.questID]
    if not q then return end
    if kind=="track" then Q.List:Track({q},not q.watched)
    elseif kind=="share" then Q.Call("C_QuestLog.SetSelectedQuest",q.id);Q.Call("QuestLogPushQuest")
    elseif kind=="navigate" then Q.Call("C_SuperTrack.SetSuperTrackedQuestID",q.id)
    elseif kind=="link" then self:Link(q)
    elseif kind=="abandon" then self:Abandon(q) end
end
-- The quest's Wowhead address, selected for Ctrl+C.
function Det:Link(q)
    if not self.link then return end
    self.link:SetText("https://www.wowhead.com/classic/quest="..q.id)
    self.link:Show();self.link:SetFocus();self.link:HighlightText()
end
-- Blizzard's own confirmation does the abandoning.
function Det:Abandon(q)
    Q.Call("C_QuestLog.SetSelectedQuest",q.id)
    Q.Call("C_QuestLog.SetAbandonQuest")
    if StaticPopup_Show then StaticPopup_Show("ABANDON_QUEST",q.title) else Q:Print("Abandon from Blizzard's quest log.") end
end
