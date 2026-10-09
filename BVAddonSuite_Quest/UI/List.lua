local _,Q=...
if not Q.ready then return end
-- Compact quest list (left pane by default): search, grouping and sorting,
-- one row per quest with level, tags, progress and distance; the selected
-- quest shows its objectives below it. Click selects (details), Ctrl+click
-- adds to a multi-selection, right-click opens actions for the selection.
local ns=Q.ns
local UI,M=ns.UI,ns.DesignSystem.Metrics
local L={rows={},selection={},scroll=0}
Q.List=L
local TOP,FOOTER=64,22
local GROUPS={{value="currentzone",label="Current zone first"},{value="zone",label="By zone"},{value="status",label="By status"},{value="none",label="No groups"}}
local SORTS={{value="distance",label="Nearest objective"},{value="progress",label="Progress"},{value="ready",label="Ready first"},
    {value="level",label="Level"},{value="recent",label="Recent progress"},{value="title",label="Name"}}

local function style() return Q:Style() end
function L:Build(pane)
    self.pane=pane
    local s=style()
    self.search=s:Input(pane,200,false,"",function(text) Q.Data.search=text;Q.Data:Sort();L:Refresh() end)
    UI:AttachTooltip(self.search,"Search","Filters by quest name or zone.")
    self.group=UI:Dropdown(pane,140,GROUPS,function(value) Q:Config().groupBy=value;Q.Data:Sort();L:Refresh() end)
    UI:AttachTooltip(self.group,"Groups","Current zone first, by zone, by status (ready, in progress, failed) or no groups.")
    self.sort=UI:Dropdown(pane,140,SORTS,function(value) Q:Config().sortBy=value;Q.Data:Sort();L:Refresh() end)
    UI:AttachTooltip(self.sort,"Sort","Within each group: nearest open objective (ready quests last, their turn-in has no distance), progress, ready first, level, recent progress or name. Pinned quests stay on top.")
    self.scrollFrame=CreateFrame("ScrollFrame",nil,pane);self.scrollFrame:SetClipsChildren(true);self.scrollFrame:EnableMouseWheel(true)
    self.child=CreateFrame("Frame",nil,self.scrollFrame);self.scrollFrame:SetScrollChild(self.child)
    self.scrollFrame:SetScript("OnMouseWheel",function(_,delta) L:Scroll(-delta*Q.DENSITY[Q:Config().density]*3) end)
    self.footer=UI:Label(pane,"",11,"muted")
    self.empty=UI:Label(pane,"No quests in your log.",12,"muted")
end
function L:Layout()
    local pane=self.pane
    if not pane then return end
    local width=M.GetWidth(pane)
    UI:Place(self.search,pane,8,8);M.Size(self.search,width-16,24)
    local half=(width-20)/2
    UI:Place(self.group,pane,8,36);M.Size(self.group,half,24)
    UI:Place(self.sort,pane,12+half,36);M.Size(self.sort,half,24)
    local footer=Q:Config().showFooter and FOOTER or 0
    self.scrollFrame:ClearAllPoints()
    M.Point(self.scrollFrame,"TOPLEFT",pane,"TOPLEFT",4,-TOP-4);M.Point(self.scrollFrame,"BOTTOMRIGHT",pane,"BOTTOMRIGHT",-4,footer+4)
    M.Width(self.child,width-8)
    self.footer:ClearAllPoints();M.Point(self.footer,"BOTTOMLEFT",pane,"BOTTOMLEFT",10,6);M.Size(self.footer,width-20,14)
    self.footer:SetShown(Q:Config().showFooter)
    self.empty:ClearAllPoints();M.Point(self.empty,"TOPLEFT",pane,"TOPLEFT",10,-TOP-10);M.Size(self.empty,width-20,16)
    self:Refresh()
end

-- Rows -------------------------------------------------------------------------------
function L:Row(index)
    local row=self.rows[index]
    if row then return row end
    return UI:WithStyle(style(),function()
        row=CreateFrame("Button",nil,self.child);row:RegisterForClicks("LeftButtonUp","RightButtonUp")
        row.band=row:CreateTexture(nil,"BACKGROUND");row.band:SetAllPoints(row);row.band:SetTexture("Interface\\Buttons\\WHITE8X8")
        row.badge=row:CreateTexture(nil,"ARTWORK");row.badge:SetTexture("Interface\\Buttons\\WHITE8X8")
        row.level=UI:Label(row,"",11,false,true);row.level:SetJustifyH("CENTER")
        row.title=UI:Label(row,"",12,false);row.title:SetWordWrap(false)
        row.info=UI:Label(row,"",11,"muted");row.info:SetJustifyH("RIGHT");row.info:SetWordWrap(false)
        row.bar=row:CreateTexture(nil,"ARTWORK");row.bar:SetTexture("Interface\\Buttons\\WHITE8X8")
        row.barBack=row:CreateTexture(nil,"BORDER");row.barBack:SetTexture("Interface\\Buttons\\WHITE8X8")
        row.bvMenuStyle=style()
        row:SetScript("OnClick",function(_,button) L:Click(row,button) end)
        row:SetScript("OnEnter",function() row.hovered=true;L:Paint(row) end)
        row:SetScript("OnLeave",function() row.hovered=false;L:Paint(row) end)
        self.rows[index]=row
        return row
    end)
end
-- Paints one row from its entry: header, quest or objective line.
function L:Paint(row)
    local e,cfg,s=row.entry,Q:Config(),style()
    if not e then return end
    local height=M.GetHeight(row)
    local width=M.GetWidth(row)
    local size=cfg.fontSize
    s:Font(row.title,e.header and size-1 or e.objective and size-1 or size,e.header and "bold" or "regular")
    s:Font(row.info,size-1);s:Font(row.level,size-2,"bold")
    row.badge:Hide();row.level:Hide();row.bar:Hide();row.barBack:Hide();row.info:SetText("")
    local x=6
    if e.header then
        row.title:SetText(ns.Styles:Label(Q:Family(),e.header));row.title:SetTextColor(s:Color("accent"))
        row.band:SetVertexColor(1,1,1,0)
    elseif e.objective then
        local o=e.objective
        row.title:SetText(o.text);row.title:SetTextColor(s:Color(o.finished and "muted" or "text"))
        if o.finished then row.title:SetTextColor(.45,.8,.45) end
        x=28
        row.band:SetVertexColor(1,1,1,0)
    else
        local q=e.quest
        local r,g,b=Q.Data.Color(q.difficulty)
        if cfg.levelMode=="badge" then
            row.badge:ClearAllPoints();M.Point(row.badge,"LEFT",row,"LEFT",4,0);M.Size(row.badge,24,height-6)
            row.badge:SetVertexColor(r,g,b,.25);row.badge:Show()
            row.level:ClearAllPoints();M.Point(row.level,"CENTER",row.badge,"CENTER",0,0);M.Size(row.level,24,height)
            row.level:SetText(q.level or "?");row.level:SetTextColor(r,g,b);row.level:Show()
            x=32
        end
        local tags=cfg.showTags and Q.Data.Tags(q) or ""
        row.title:SetText((q.pinned and "• " or "")..q.title..tags)
        if cfg.levelMode=="color" then row.title:SetTextColor(r,g,b)
        elseif q.failed then row.title:SetTextColor(s:Color("danger"))
        elseif q.dungeon and cfg.dungeonColor then row.title:SetTextColor(Q.Data.DungeonColor(s))
        else row.title:SetTextColor(s:Color("text")) end
        local info={}
        if q.ready then info[#info+1]="|cff5fd068"..ns.Styles:Label(Q:Family(),"Ready").."|r"
        elseif cfg.progressMode=="text" then
            local have,need=0,0
            for _,o in ipairs(q.objectives) do if o.need then have,need=have+(o.have or 0),need+o.need end end
            if need>0 then info[#info+1]=have.."/"..need end
        end
        if cfg.showDistance and q.distance and not q.ready then info[#info+1]=L.Yards(q.distance) end
        row.info:SetText(table.concat(info,"  "))
        if cfg.progressMode=="bar" and not q.ready then
            row.barBack:ClearAllPoints();M.Point(row.barBack,"BOTTOMLEFT",row,"BOTTOMLEFT",x,1);M.Size(row.barBack,width-x-6,2)
            row.barBack:SetVertexColor(1,1,1,.08);row.barBack:Show()
            row.bar:ClearAllPoints();M.Point(row.bar,"BOTTOMLEFT",row.barBack,"BOTTOMLEFT",0,0);M.Size(row.bar,math.max(.01,(width-x-6)*q.progress),2)
            local ar,ag,ab=s:Color("accent");row.bar:SetVertexColor(ar,ag,ab,.9);row.bar:Show()
        end
        local selected=Q.Details.questID==q.id
        local chosen=self.selection[q.id]
        local ar,ag,ab=s:Color("accent")
        row.band:SetVertexColor(ar,ag,ab,selected and .2 or chosen and .14 or row.hovered and .07 or 0)
    end
    row.title:ClearAllPoints();M.Point(row.title,"LEFT",row,"LEFT",x,0);M.Size(row.title,width-x-80,height)
    row.info:ClearAllPoints();M.Point(row.info,"RIGHT",row,"RIGHT",-6,0);M.Size(row.info,76,height)
end
function L.Yards(yards)
    if yards>=1000 then return string.format("%.1fk yd",yards/1000) end
    return math.floor(yards+.5).." yd"
end
-- Rebuilds the visible list: entries, then objective lines under the selected quest.
function L:Entries()
    local out={}
    for _,e in ipairs(Q.Data.list) do
        out[#out+1]=e
        if e.quest and Q.Details.questID==e.quest.id then
            for _,o in ipairs(e.quest.objectives) do out[#out+1]={objective=o,quest=e.quest} end
        end
    end
    return out
end
function L:Refresh()
    if not self.pane then return end
    local cfg=Q:Config()
    self.group:SetValue(cfg.groupBy);self.sort:SetValue(cfg.sortBy)
    local entries=self:Entries()
    local h=Q.DENSITY[cfg.density]
    local width=M.GetWidth(self.child)
    for index,e in ipairs(entries) do
        local row=self:Row(index)
        row.entry=e;M.Size(row,width,h);row:ClearAllPoints();M.Point(row,"TOPLEFT",self.child,"TOPLEFT",0,-(index-1)*h)
        self:Paint(row);row:Show()
    end
    for index=#entries+1,#self.rows do self.rows[index].entry=nil;self.rows[index]:Hide() end
    M.Height(self.child,math.max(1,#entries*h))
    self.empty:SetShown(#Q.Data.quests==0)
    local count,max,ready,xp=Q.Data:Summary()
    local xpText=""
    if xp>0 then xpText=" · "..(BreakUpLargeNumbers and BreakUpLargeNumbers(xp) or tostring(xp)).." XP" end
    self.footer:SetText(string.format("%d/%d quests · %d ready%s",count,max,ready,xpText))
    self:Scroll(0)
end
function L:Scroll(delta)
    local h=M.GetHeight(self.child)-M.GetHeight(self.scrollFrame)
    self.scroll=math.max(0,math.min(math.max(0,h),self.scroll+delta))
    self.scrollFrame:SetVerticalScroll(M.ToNative(self.scroll))
end

-- Interaction -------------------------------------------------------------------------
function L:Click(row,button)
    local e=row.entry
    if not e or e.header then return end
    local q=e.quest
    if button=="RightButton" then self:Menu(row,q);return end
    if IsControlKeyDown and IsControlKeyDown() then
        self.selection[q.id]=not self.selection[q.id] or nil
        self:Refresh();return
    end
    if IsShiftKeyDown and IsShiftKeyDown() then self:Track({q},not q.watched);return end
    for id in pairs(self.selection) do self.selection[id]=nil end
    -- A second click on the selected quest closes the details; objective lines keep them.
    if Q.Details.questID==q.id and not e.objective then Q.Details:Select(nil) else Q.Details:Select(q.id) end
end
-- The quests an action applies to: the multi-selection, else the clicked one.
function L:Targets(q)
    local out={}
    for id in pairs(self.selection) do local quest=Q.Data.byID[id];if quest then out[#out+1]=quest end end
    if #out==0 or not self.selection[q.id] then out={q} end
    return out
end
function L:Track(quests,on)
    for _,q in ipairs(quests) do
        if on then Q.Call("C_QuestLog.AddQuestWatch",q.id) else Q.Call("C_QuestLog.RemoveQuestWatch",q.id) end
    end
    Q:Dirty()
end
function L:Menu(row,q)
    local quests=self:Targets(q)
    local many=#quests>1
    local cfg=Q:Config()
    local options={}
    local suffix=many and (" ("..#quests..")") or ""
    options[#options+1]={value="pin",label=(cfg.pins[q.id] and "Unpin" or "Pin to top")..suffix}
    options[#options+1]={value="track",label=(q.watched and "Stop tracking" or "Track")..suffix}
    options[#options+1]={value="share",label="Share with group"..suffix}
    if not many then
        options[#options+1]={value="supertrack",label="Set as navigation target"}
        if Q.MapWaypoints() then options[#options+1]={value="waypoint",label="Waypoint to the objective"} end
        options[#options+1]={value="link",label="Wowhead link"}
        options[#options+1]={value="abandon",label="Abandon…",danger=true}
    end
    UI:ContextMenu(row,options,function(value)
        if value=="pin" then local on=not cfg.pins[q.id];for _,quest in ipairs(quests) do cfg.pins[quest.id]=on or nil end;Q.Data:Sort();L:Refresh()
        elseif value=="track" then L:Track(quests,not q.watched)
        elseif value=="share" then
            for _,quest in ipairs(quests) do Q.Call("C_QuestLog.SetSelectedQuest",quest.id);Q.Call("QuestLogPushQuest") end
            if Q.Details.questID then Q.Call("C_QuestLog.SetSelectedQuest",Q.Details.questID) end
        elseif value=="supertrack" then Q.Call("C_SuperTrack.SetSuperTrackedQuestID",q.id)
        elseif value=="waypoint" then Q.MapWaypoints():Quest(q.id,q.title)
        elseif value=="link" then Q.Details:Link(q)
        elseif value=="abandon" then Q.Details:Abandon(q) end
    end)
end
