local _,Q=...
if not Q.ready then return end
-- Quest tracker on screen (modelled on Horizon Focus, docs/map-quest-concept.md):
-- tracked quests plus the current zone (or tracked only, or the N nearest),
-- nearest first, objectives with thin bars, distance, ready line; full, compact
-- or minimal; shown, faded or hidden in combat and instances; mouseover only;
-- auto-focus sets the nearest quest as navigation target and pauses when you
-- pick one yourself. A Layout Editor element: its height is the most the
-- tracker grows to, taller content scrolls with the mouse wheel. Unlocked, the
-- title moves it and the corner resizes it without the editor.
local ns=Q.ns
local UI,M=ns.UI,ns.DesignSystem.Metrics
local T={blocks={},hover=0,scroll=0}
Q.Tracker=T
local ID="bv:questtracker"
local PAD,HEADER,GAP=8,20,7
local WHITE="Interface\\Buttons\\WHITE8X8"
local function cfg() return Q:Config() end
local function family() return Q:Family() end

-- Which quests and in which sections.
function T:Sections()
    local c=cfg()
    local current,tracked,all={},{},{}
    -- Dungeon quests in a section per dungeon (the log's header names it).
    local dungeons,dungeonNames={},{}
    for _,q in ipairs(Q.Data.quests) do
        local shown=c.trackerMode=="nearest" or (q.current and c.trackerMode=="watchedzone") or q.watched
        if c.trackerMode=="nearest" then all[#all+1]=q
        elseif shown and q.dungeon and c.trackerGroupDungeons then
            local name=q.zone or "Dungeons"
            if not dungeons[name] then dungeons[name]={};dungeonNames[#dungeonNames+1]=name end
            table.insert(dungeons[name],q)
        elseif q.current and c.trackerMode=="watchedzone" then current[#current+1]=q
        elseif q.watched then tracked[#tracked+1]=q end
    end
    local function nearest(a,b)
        if a.ready~=b.ready then return not a.ready end
        local da,db=a.distance or 1e9,b.distance or 1e9
        if da~=db then return da<db end
        return a.title<b.title
    end
    table.sort(current,nearest);table.sort(tracked,nearest);table.sort(all,nearest)
    if c.trackerMode=="nearest" then
        for i=#all,c.trackerCount+1,-1 do all[i]=nil end
        return {{title="Nearby",quests=all}}
    end
    local sections={}
    if #current>0 then sections[#sections+1]={title=Q.Data.zoneName or "Current zone",quests=current} end
    table.sort(dungeonNames)
    for _,name in ipairs(dungeonNames) do
        table.sort(dungeons[name],nearest)
        sections[#sections+1]={title=name,quests=dungeons[name],dungeon=true}
    end
    if #tracked>0 then sections[#sections+1]={title="Tracked",quests=tracked} end
    return sections
end

-- Frame -------------------------------------------------------------------------------
function T:Create()
    if self.frame then return end
    local f=CreateFrame("Frame",nil,UIParent);f:SetFrameStrata("MEDIUM");f:EnableMouse(false);f:SetSize(1,1)
    f:SetPoint("RIGHT",UIParent,"RIGHT",-M.ToNative(180),M.ToNative(60))
    f:SetClampedToScreen(true)
    if ns.ExternalFrames then ns.ExternalFrames:MarkOwned(f) end
    self.frame=f
    ns.Layout:Register(ID,{label="Quest Tracker",
        limits={minWidth=180,maxWidth=600,minHeight=120,maxHeight=1200},
        defaults=function() return {width=M.ToNative(260),height=M.ToNative(cfg().trackerMaxHeight),screen="RIGHT",x=-180,y=60} end,
        apply=function(rect)
            f:ClearAllPoints();f:SetPoint("CENTER",UIParent,"CENTER",rect.x,rect.y)
            f:SetSize(math.max(1,rect.width),math.max(1,rect.height))
            T:Layout()
        end,
        enabled=function() return Q:Active() and cfg().tracker end,
        preview=function(value) T.preview=value==true;T:Update() end})
end
local function hoverScripts(frame)
    frame:HookScript("OnEnter",function() T:Hover(1) end)
    frame:HookScript("OnLeave",function() T:Hover(-1) end)
end
function T:Build()
    if self.content then return end
    self:Create()
    UI:WithStyle(Q:Style(),function()
        local f=self.frame
        -- Background (optional) sized to the content; it also takes the mouse
        -- for mouseover-only, so the empty rest of the box never blocks clicks.
        self.content=UI:GamePanel(Q.ID,f,260,100,"bg",4,function() return cfg().trackerOpacity/100 end)
        self.content:SetPoint("TOPLEFT",f,"TOPLEFT",0,0);self.content:EnableMouse(true)
        hoverScripts(self.content)
        -- Header: title (drag handle when unlocked) and the auto-focus button.
        self.handle=CreateFrame("Button",nil,self.content);self.handle:RegisterForDrag("LeftButton")
        self.handle:SetScript("OnDragStart",function() T:StartMove() end)
        self.handle:SetScript("OnDragStop",function() T:StopMove() end)
        hoverScripts(self.handle)
        self.title=self.handle:CreateFontString(nil,"OVERLAY");self.title:SetJustifyH("LEFT")
        self.rule=self.content:CreateTexture(nil,"ARTWORK");self.rule:SetTexture(WHITE)
        self.focus=CreateFrame("Button",nil,self.content);M.Size(self.focus,16,16)
        self.focus.icon=self.focus:CreateTexture(nil,"ARTWORK");self.focus.icon:SetAllPoints(self.focus)
        local path,l,r,t,b=ns.Symbols:Coords("crosshair",64)
        if path then self.focus.icon:SetTexture(path);self.focus.icon:SetTexCoord(l,r,t,b) end
        self.focus:SetScript("OnClick",function() T:ToggleFocus() end)
        self.focus:SetScript("OnEnter",function(button) T:Hover(1)
            UI:ShowTooltip(button,"Auto-focus",cfg().autoFocus and (T.paused and "Paused: you picked a target yourself. Click to resume." or "On: the nearest quest is your navigation target. Click to turn off.")
                or "Off. Click to set the nearest quest as navigation target automatically. Also /bv quest focus (bindable as a macro).") end)
        self.focus:SetScript("OnLeave",function(button) T:Hover(-1);UI:HideTooltip(button) end)
        Q.Banner:Build(self.content)
        -- Quests scroll inside the box once they are taller than it.
        self.viewport=CreateFrame("ScrollFrame",nil,self.content);self.viewport:SetClipsChildren(true)
        self.viewport:SetScript("OnMouseWheel",function(_,delta) T:Scroll(delta) end)
        self.body=CreateFrame("Frame",nil,self.viewport);self.body:SetSize(1,1)
        self.viewport:SetScrollChild(self.body)
        self.thumb=self.content:CreateTexture(nil,"OVERLAY");self.thumb:SetTexture(WHITE);self.thumb:Hide()
        -- Unlocked: a resize grip in the corner and a thin outline while hovered.
        self.grip=CreateFrame("Button",nil,self.content);M.Size(self.grip,14,14)
        self.grip.icon=self.grip:CreateTexture(nil,"OVERLAY");self.grip.icon:SetAllPoints(self.grip)
        self.grip.icon:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
        self.grip:SetScript("OnMouseDown",function() T:StartSize() end)
        self.grip:SetScript("OnMouseUp",function() T:StopSize() end)
        hoverScripts(self.grip)
        self.edges={}
        for i=1,4 do local e=self.content:CreateTexture(nil,"OVERLAY");e:SetTexture(WHITE);e:Hide();self.edges[i]=e end
        f:SetScript("OnSizeChanged",function() if T.sizing then T:Layout() end end)
    end)
end

-- Blocks: one per quest (title, objectives, ready line).
function T:Block(index)
    local b=self.blocks[index]
    if b then return b end
    b=CreateFrame("Button",nil,self.body);b:RegisterForClicks("LeftButtonUp","RightButtonUp")
    b.mark=b:CreateTexture(nil,"ARTWORK");b.mark:SetTexture(WHITE)
    -- The pulse layer stays invisible through its colour's alpha: in the client
    -- SetAlpha and the vertex alpha are one value (docs/ai/LEARNINGS.md).
    b.flash=b:CreateTexture(nil,"BACKGROUND",nil,1);b.flash:SetTexture(WHITE);b.flash:SetAllPoints(b);b.flash:SetVertexColor(1,1,1,0)
    b.title=b:CreateFontString(nil,"OVERLAY");b.title:SetJustifyH("LEFT");b.title:SetWordWrap(false)
    b.distance=b:CreateFontString(nil,"OVERLAY");b.distance:SetJustifyH("RIGHT")
    b.lines,b.bars,b.backs={},{},{}
    -- Fade-in for new entries, a pulse when a quest is ready.
    b.fade=b:CreateAnimationGroup();b.fade:SetToFinalAlpha(true)
    b.fadeIn=b.fade:CreateAnimation("Alpha");b.fadeIn:SetFromAlpha(0);b.fadeIn:SetToAlpha(1);b.fadeIn:SetDuration(.25)
    b.pulse=b.flash:CreateAnimationGroup();b.pulse:SetToFinalAlpha(true)
    b.pulseIn=b.pulse:CreateAnimation("Alpha");b.pulseIn:SetFromAlpha(0);b.pulseIn:SetToAlpha(.25);b.pulseIn:SetDuration(.2);b.pulseIn:SetOrder(1)
    b.pulseOut=b.pulse:CreateAnimation("Alpha");b.pulseOut:SetFromAlpha(.25);b.pulseOut:SetToAlpha(0);b.pulseOut:SetDuration(.8);b.pulseOut:SetOrder(2)
    b:SetScript("OnClick",function(_,button) T:Click(b,button) end)
    hoverScripts(b)
    self.blocks[index]=b
    return b
end
function T:Line(b,index)
    local line=b.lines[index]
    if line then return line end
    line=b:CreateFontString(nil,"OVERLAY");line:SetJustifyH("LEFT");line:SetWordWrap(false)
    b.lines[index]=line
    b.backs[index]=b:CreateTexture(nil,"BORDER");b.backs[index]:SetTexture(WHITE)
    b.bars[index]=b:CreateTexture(nil,"ARTWORK");b.bars[index]:SetTexture(WHITE)
    return line
end
local function font(region,size,weight)
    ns.Styles:Font(family(),region,M.ToNative(size),weight or "regular","OUTLINE")
end

-- Paints the quest rows into the scroll body; returns their height.
function T:Rows(width)
    local c,s=cfg(),Q:Style()
    local size=c.fontSize
    local titleH,lineH=size+6,size+3
    local supertracked=Q.Call("C_SuperTrack.GetSuperTrackedQuestID")
    local ar,ag,ab=s:Color("accent")
    local tr,tg,tb=s:Color("text")
    local mr,mg,mb=s:Color("muted")
    local used,y=0,0
    local sections=self.preview and self:Sample() or self:Sections()
    self.sectionLabels,self.sectionRules=self.sectionLabels or {},self.sectionRules or {}
    for si,section in ipairs(sections) do
        local label,rule=self.sectionLabels[si],self.sectionRules[si]
        if not label then
            label=self.body:CreateFontString(nil,"OVERLAY");label:SetJustifyH("LEFT");label:SetWordWrap(false);self.sectionLabels[si]=label
            rule=self.body:CreateTexture(nil,"ARTWORK");rule:SetTexture(WHITE);self.sectionRules[si]=rule
        end
        if si>1 then y=y+4 end
        font(label,size-2,"bold");label:SetText(ns.Styles:Label(family(),section.title))
        if section.dungeon and c.dungeonColor then label:SetTextColor(Q.Data.DungeonColor(s)) else label:SetTextColor(mr,mg,mb) end
        label:ClearAllPoints();M.Point(label,"TOPLEFT",self.body,"TOPLEFT",0,-y);label:Show()
        local labelW=math.min(width*.7,(label.GetStringWidth and M.ToDesign(label:GetStringWidth() or 0) or 80)+6)
        M.Size(label,labelW,lineH)
        rule:ClearAllPoints();M.Point(rule,"TOPLEFT",self.body,"TOPLEFT",labelW+2,-y-math.floor(lineH/2));M.Size(rule,math.max(1,width-labelW-2),1)
        rule:SetVertexColor(mr,mg,mb,.25);rule:Show()
        y=y+lineH+3
        for _,q in ipairs(section.quests) do
            used=used+1
            local b=self:Block(used)
            local fresh=b.questID~=q.id
            local becameReady=not fresh and q.ready and not b.ready
            b.quest,b.questID,b.ready=q,q.id,q.ready
            local target=supertracked==q.id
            -- Title row: level in its difficulty colour, name, distance.
            font(b.title,size,"bold");font(b.distance,size-2)
            local r,g,bl=Q.Data.Color(q.difficulty)
            -- Tags as in the list (Florian 2026-10-08: no sign of a dungeon quest).
            local tags=c.showTags and Q.Data.Tags(q) or ""
            b.title:SetText(string.format("|cff%02x%02x%02x%s|r  %s%s",r*255,g*255,bl*255,q.level or "?",q.title,tags))
            if q.failed then b.title:SetTextColor(s:Color("danger"))
            elseif target then b.title:SetTextColor(ar,ag,ab)
            elseif q.dungeon and c.dungeonColor then b.title:SetTextColor(Q.Data.DungeonColor(s))
            else b.title:SetTextColor(tr,tg,tb) end
            local distance=""
            if c.showDistance and q.distance and not q.ready then distance=Q.List.Yards(q.distance) end
            b.distance:SetText(distance);b.distance:SetTextColor(mr,mg,mb)
            b.title:ClearAllPoints();M.Point(b.title,"TOPLEFT",b,"TOPLEFT",8,0);M.Size(b.title,width-8-(distance~="" and 58 or 0),titleH)
            b.distance:ClearAllPoints();M.Point(b.distance,"TOPRIGHT",b,"TOPRIGHT",0,0);M.Size(b.distance,56,titleH)
            local h=titleH
            local shown=0
            local function line(text,color,progress)
                shown=shown+1
                local l=self:Line(b,shown)
                font(l,size-1);l:SetText(text);l:SetTextColor(unpack(color))
                l:ClearAllPoints();M.Point(l,"TOPLEFT",b,"TOPLEFT",18,-h);M.Size(l,width-18,lineH);l:Show()
                h=h+lineH
                local back,bar=b.backs[shown],b.bars[shown]
                if progress then
                    -- A thin bar right under the text, only for counted objectives.
                    local barW=math.min(width-26,140)
                    back:ClearAllPoints();M.Point(back,"TOPLEFT",b,"TOPLEFT",18,-h);M.Size(back,barW,2);back:SetVertexColor(mr,mg,mb,.25);back:Show()
                    bar:ClearAllPoints();M.Point(bar,"TOPLEFT",back,"TOPLEFT",0,0);M.Size(bar,math.max(.01,barW*progress),2);bar:SetVertexColor(ar,ag,ab,.9);bar:Show()
                    h=h+4
                else back:Hide();bar:Hide() end
            end
            if q.ready then line("Ready to turn in",{.37,.82,.42})
            elseif c.trackerLayout~="minimal" then
                for _,o in ipairs(q.objectives) do
                    if not (o.finished and c.trackerLayout=="compact") then
                        local text,progress=o.text,nil
                        if o.need and o.need>1 then progress=(o.have or 0)/o.need end
                        if progress and c.trackerProgress=="percent" then text=text.."  "..math.floor(progress*100+.5).."%" end
                        local color=o.finished and {mr,mg,mb} or {tr,tg,tb}
                        line(text,color,c.trackerProgress=="bar" and not o.finished and progress or nil)
                    end
                end
            end
            for i=shown+1,#b.lines do b.lines[i]:Hide();b.backs[i]:Hide();b.bars[i]:Hide() end
            b:ClearAllPoints();M.Point(b,"TOPLEFT",self.body,"TOPLEFT",0,-y);M.Size(b,width,h)
            -- The navigation target: an accent mark along the block.
            b.mark:ClearAllPoints();M.Point(b.mark,"TOPLEFT",b,"TOPLEFT",0,-3);M.Size(b.mark,2,h-5)
            b.mark:SetVertexColor(ar,ag,ab,1);b.mark:SetShown(target)
            if not b.pulse:IsPlaying() then b.flash:SetVertexColor(ar,ag,ab,0) end
            b:Show()
            if fresh then b.fade:Stop();b.fade:Play() end
            if becameReady then b.flash:SetVertexColor(ar,ag,ab,0);b.pulse:Stop();b.pulse:Play() end
            y=y+h+GAP
        end
    end
    for si=#sections+1,#self.sectionLabels do self.sectionLabels[si]:Hide();self.sectionRules[si]:Hide() end
    for i=used+1,#self.blocks do self.blocks[i]:Hide();self.blocks[i].questID=nil end
    self.used=used
    return math.max(0,y-GAP)
end

-- Paints everything: header, banner, quests; the box height caps the content.
function T:Layout()
    if not (self.frame and self.content) then return end
    local c,s=cfg(),Q:Style()
    local width=math.max(180,M.GetWidth(self.frame))
    local box=M.GetHeight(self.frame)
    if box<HEADER*2 then box=c.trackerMaxHeight end
    local inner=width-PAD*2
    local unlocked=c.trackerUnlocked and not (ns.LayoutEditor and ns.LayoutEditor.active)
    -- Header.
    local y=PAD
    font(self.title,c.fontSize,"bold");self.title:SetText(ns.Styles:Label(family(),"Quests"));self.title:SetTextColor(s:Color("accent"))
    self.handle:ClearAllPoints();M.Point(self.handle,"TOPLEFT",self.content,"TOPLEFT",PAD,-y);M.Size(self.handle,inner-22,HEADER)
    self.handle:EnableMouse(unlocked)
    self.title:ClearAllPoints();M.Point(self.title,"TOPLEFT",self.handle,"TOPLEFT",0,0);M.Size(self.title,inner-22,HEADER)
    self.focus:ClearAllPoints();M.Point(self.focus,"TOPRIGHT",self.content,"TOPRIGHT",-PAD,-y-2)
    local fr,fg,fb=s:Color(c.autoFocus and (self.paused and "warning" or "accent") or "muted");self.focus.icon:SetVertexColor(fr,fg,fb,1)
    y=y+HEADER
    local ar,ag,ab=s:Color("accent")
    self.rule:ClearAllPoints();M.Point(self.rule,"TOPLEFT",self.content,"TOPLEFT",PAD,-y);M.Size(self.rule,inner,1);self.rule:SetVertexColor(ar,ag,ab,.35)
    y=y+6
    y=Q.Banner:Layout(self.content,y,width)
    -- Quests: everything that does not fit scrolls.
    local rows=self:Rows(inner)
    local room=math.max(HEADER,box-y-PAD)
    local overflow=rows>room
    local visible=overflow and room or rows
    self.maxScroll=overflow and rows-room or 0
    self.scroll=math.max(0,math.min(self.scroll,self.maxScroll))
    self.viewport:ClearAllPoints();M.Point(self.viewport,"TOPLEFT",self.content,"TOPLEFT",PAD,-y);M.Size(self.viewport,inner+2,math.max(1,visible))
    M.Size(self.body,inner+2,math.max(1,rows))
    self.viewport:SetVerticalScroll(M.ToNative(self.scroll))
    -- The wheel only belongs to the tracker while there is something to scroll.
    self.viewport:EnableMouseWheel(overflow)
    if overflow then
        local track=visible
        local size=math.max(16,track*room/rows)
        local top=(track-size)*self.scroll/self.maxScroll
        self.thumb:ClearAllPoints();M.Point(self.thumb,"TOPRIGHT",self.content,"TOPRIGHT",-2,-y-top);M.Size(self.thumb,2,size)
        local mr,mg,mb=s:Color("muted");self.thumb:SetVertexColor(mr,mg,mb,.5);self.thumb:Show()
    else self.thumb:Hide() end
    local height=y+visible+PAD
    if unlocked then height=box end
    M.Size(self.content,width,math.max(height,HEADER+PAD*2))
    -- Background: switch and opacity are read on every paint.
    self.content.surfaceHidden=not c.trackerBackground
    if self.content.RepaintSurface then self.content:RepaintSurface() end
    -- Unlocked: corner grip, and an outline while the mouse is over it.
    self.grip:SetShown(unlocked)
    self.grip:ClearAllPoints();M.Point(self.grip,"BOTTOMRIGHT",self.content,"BOTTOMRIGHT",-1,1)
    local outline=unlocked and (self.hover>0 or self.moving or self.sizing)
    local e=self.edges
    e[1]:ClearAllPoints();e[1]:SetPoint("TOPLEFT",self.content,"TOPLEFT");e[1]:SetPoint("TOPRIGHT",self.content,"TOPRIGHT");e[1]:SetHeight(1)
    e[2]:ClearAllPoints();e[2]:SetPoint("BOTTOMLEFT",self.content,"BOTTOMLEFT");e[2]:SetPoint("BOTTOMRIGHT",self.content,"BOTTOMRIGHT");e[2]:SetHeight(1)
    e[3]:ClearAllPoints();e[3]:SetPoint("TOPLEFT",self.content,"TOPLEFT");e[3]:SetPoint("BOTTOMLEFT",self.content,"BOTTOMLEFT");e[3]:SetWidth(1)
    e[4]:ClearAllPoints();e[4]:SetPoint("TOPRIGHT",self.content,"TOPRIGHT");e[4]:SetPoint("BOTTOMRIGHT",self.content,"BOTTOMRIGHT");e[4]:SetWidth(1)
    for _,edge in ipairs(e) do edge:SetVertexColor(ar,ag,ab,.6);edge:SetShown(outline) end
end
function T:Scroll(delta)
    if not self.maxScroll or self.maxScroll<=0 then return end
    self.scroll=math.max(0,math.min(self.maxScroll,self.scroll-delta*(cfg().fontSize+6)*2))
    self:Layout()
end
-- Layout Editor preview without quests.
function T:Sample()
    return {{title="Current zone",quests={
        {id=-1,title="Egg Hunt",level=22,difficulty=22,distance=804,objectives={{text="7/12 Silithid Egg",have=7,need=12}}},
        {id=-2,title="Mura Runetotem",level=15,difficulty=15,ready=true,objectives={}}}}}
end

-- Unlocked: move by the title, resize by the corner; the result goes into the
-- layout, so the Layout Editor and the tracker always agree.
function T:Unlocked() return cfg().trackerUnlocked and not (ns.LayoutEditor and ns.LayoutEditor.active) end
function T:StartMove()
    if not self:Unlocked() then return end
    self.moving=true
    self.frame:SetMovable(true);self.frame:StartMoving()
end
function T:StopMove()
    if not self.moving then return end
    self.moving=false
    self.frame:StopMovingOrSizing()
    self:Store(false)
end
function T:StartSize()
    if not self:Unlocked() then return end
    self.sizing=true
    local f=self.frame
    f:SetResizable(true)
    local minW,minH,maxW,maxH=M.ToNative(180),M.ToNative(120),M.ToNative(600),M.ToNative(1200)
    if f.SetResizeBounds then f:SetResizeBounds(minW,minH,maxW,maxH) end
    f:StartSizing("BOTTOMRIGHT")
end
function T:StopSize()
    if not self.sizing then return end
    self.frame:StopMovingOrSizing()
    self.sizing=false
    self:Store(true)
end
-- Writes the frame's centre (and size) back into the layout element.
function T:Store(size)
    local f=self.frame
    local cx,cy=f:GetCenter()
    local ux,uy=UIParent:GetCenter()
    if size then ns.Layout:Change(ID,{width=f:GetWidth(),height=f:GetHeight()}) end
    if cx and ux then ns.Layout:Move(ID,cx-ux,cy-uy) end
    self:Layout()
end

-- Visibility: module, setting, instance and combat rules, mouseover only.
function T:Shown() return self.frame~=nil and self.frame:IsShown() end
function T:Update()
    if not self.frame then return end
    local c=cfg()
    local on=Q:Active() and c.tracker
    -- Blizzard's tracker follows the switch at once, not only after a reload.
    self:Blizzard(on and c.trackerHideBlizzard or false)
    local show=self.preview or on
    if show and not self.preview then
        local inInstance=Q.Call("IsInInstance")
        if inInstance and c.trackerInstance=="hide" then show=false end
        if self.combat and c.trackerCombat=="hide" then show=false end
    end
    if not show then self.frame:Hide();self:Clock(false);Q.Banner:Clock(false);return end
    self:Build()
    self.frame:Show()
    self:Layout()
    local alpha=1
    if self.combat and c.trackerCombat=="fade" then alpha=.35 end
    if c.trackerMouseover and self.hover<=0 and not self.preview then alpha=0 end
    self.frame:SetAlpha(alpha)
    self:Clock(true)
end
function T:Hover(delta)
    self.hover=math.max(0,self.hover+delta)
    if cfg().trackerMouseover then self:Update()
    elseif cfg().trackerUnlocked and self.content then self:Layout() end
end
-- Distances change while you walk: re-read every 2 s, only while shown.
function T:Clock(on)
    if on and not self.clock then self.clock=C_Timer.NewTicker(2,function() if T:Shown() then Q:Dirty() end end)
    elseif not on and self.clock then self.clock:Cancel();self.clock=nil end
end

-- Clicks and actions.
function T:Click(b,button)
    local q=b.quest
    if not q or q.id<0 then return end
    if button=="RightButton" then self:Menu(b,q);return end
    if IsShiftKeyDown and IsShiftKeyDown() then Q.List:Track({q},false);return end
    if cfg().trackerLeft=="map" then self:OpenOnMap(q) else self:Navigate(q) end
end
function T:Navigate(q)
    self.setting=true
    Q.Call("C_SuperTrack.SetSuperTrackedQuestID",q.id)
    self.setting=false
    self:Layout()
end
function T:OpenOnMap(q)
    local map=rawget(_G,"WorldMapFrame")
    if map and not map:IsShown() and ToggleWorldMap then ToggleWorldMap() end
    Q.Details:Select(q.id)
end
function T:Menu(b,q)
    b.bvMenuStyle=Q:Style()
    local options={{value="navigate",label="Set as navigation target"},{value="map",label="Show in quest log"},
        {value="untrack",label=q.watched and "Stop tracking" or "Track"},{value="share",label="Share with group"},{value="abandon",label="Abandon…",danger=true}}
    if Q.MapWaypoints() then table.insert(options,2,{value="waypoint",label="Waypoint to the objective"}) end
    UI:ContextMenu(b,options,function(value)
        if value=="navigate" then T:Navigate(q)
        elseif value=="waypoint" then Q.MapWaypoints():Quest(q.id,q.title)
        elseif value=="map" then T:OpenOnMap(q)
        elseif value=="untrack" then Q.List:Track({q},not q.watched)
        elseif value=="share" then Q.Call("C_QuestLog.SetSelectedQuest",q.id);Q.Call("QuestLogPushQuest")
        elseif value=="abandon" then Q.Details:Abandon(q) end
    end)
end

-- Auto-focus: the nearest quest with open objectives becomes the navigation
-- target; a target you pick yourself pauses it until you toggle it again.
function T:AutoFocus()
    local c=cfg()
    if not c.autoFocus or self.paused then return end
    local best
    for _,q in ipairs(Q.Data.quests) do
        if not q.ready and q.distance and (not best or q.distance<best.distance) then best=q end
    end
    if best and Q.Call("C_SuperTrack.GetSuperTrackedQuestID")~=best.id then self:Navigate(best) end
end
function T:SuperTrackingChanged()
    if self.setting or not cfg().autoFocus then return end
    self.paused=true
    self:Layout()
end
function T:ToggleFocus()
    local c=cfg()
    if c.autoFocus and self.paused then self.paused=false
    else c.autoFocus=not c.autoFocus;self.paused=false end
    Q:Print("Auto-focus "..(c.autoFocus and "on" or "off"))
    self:AutoFocus();self:Update()
end

-- Blizzard's own tracker: hidden while ours is shown (option); given back
-- when off. ObjectiveTrackerFrame belongs to Edit Mode: Hide() and Show() are
-- blocked in combat. Blizzard shows it again on quest progress, mostly in
-- combat (Florian 2026-10-10: it came back now and then; nothing hid it again
-- after the fight). Like EllesmereUI's tracker: in combat it only turns
-- invisible (alpha 0), after the fight it is hidden for real.
local function combat() return InCombatLockdown and InCombatLockdown() end
function T:Blizzard(hide)
    local frame=rawget(_G,"ObjectiveTrackerFrame")
    if not frame then return end
    if hide and not self.blizzardHooked then
        self.blizzardHooked=true
        frame:HookScript("OnShow",function(own)
            if not T.hidingBlizzard then return end
            if combat() then own:SetAlpha(0);T.blizzardInCombat=true else own:Hide() end
        end)
    end
    if hide then
        self.hidingBlizzard=true
        if combat() then
            if frame:IsShown() then frame:SetAlpha(0);self.blizzardInCombat=true end
        else frame:SetAlpha(1);frame:Hide();self.blizzardInCombat=nil end
    elseif self.hidingBlizzard then
        self.hidingBlizzard=false
        frame:SetAlpha(1)
        if combat() then self.pendingBlizzard=false;return end
        frame:Show();self.blizzardInCombat=nil
        -- Blizzard lays its tracker out again on its own update.
        if ObjectiveTracker_Update then pcall(ObjectiveTracker_Update) end
        if frame.Update then pcall(frame.Update,frame) end
    end
end
-- After the fight: what Blizzard showed meanwhile is hidden for real, a
-- give-back from the fight is done now.
function T:BlizzardAfterCombat()
    local frame=rawget(_G,"ObjectiveTrackerFrame")
    if not frame then return end
    if self.pendingBlizzard==false then
        self.pendingBlizzard=nil;self.hidingBlizzard=true;self:Blizzard(false)
    elseif self.hidingBlizzard and (self.blizzardInCombat or frame:IsShown()) then
        frame:SetAlpha(1);frame:Hide();self.blizzardInCombat=nil
    end
end

function T:Enable(context)
    self:Build()
    Q:On("Changed",self,function() T:AutoFocus();if T:Shown() then T:Layout() end end)
    Q:On("Run",self,function() if T:Shown() then T:Layout() end end)
    pcall(context.Subscribe,context,"PLAYER_REGEN_DISABLED",function() T.combat=true;T:Update() end)
    pcall(context.Subscribe,context,"PLAYER_REGEN_ENABLED",function()
        T.combat=false
        T:BlizzardAfterCombat()
        T:Update()
    end)
    for _,event in ipairs({"PLAYER_ENTERING_WORLD","ZONE_CHANGED_NEW_AREA"}) do pcall(context.Subscribe,context,event,function() T:Update() end) end
    pcall(context.Subscribe,context,"SUPER_TRACKING_CHANGED",function() T:SuperTrackingChanged() end)
    context:Defer(function() T:Clock(false);Q.Banner:Clock(false);if T.frame then T.frame:Hide() end;T:Blizzard(false) end)
    self:Update()
end
T:Create()
