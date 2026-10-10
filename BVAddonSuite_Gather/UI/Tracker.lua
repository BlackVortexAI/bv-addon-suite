local _,G=...
if not G.ready then return end
-- The tracker's window: time, nodes, value and gold per hour; start, pause
-- and stop; the items of the session by value; the last sessions.
local ns=G.ns
local UI,M=ns.UI,ns.DesignSystem.Metrics
local W={rows={}}
G.TrackerWindow=W
local WIDTH,ROWS,ROW=290,8,20

function W:Build()
    if self.window then return self.window end
    UI:WithStyle(G:Style(),function()
        local w=UI:Window("BVGatherTracker",WIDTH,330,{title="Gather tracker",minWidth=WIDTH,minHeight=330,compact=true})
        for i=#UISpecialFrames,1,-1 do if UISpecialFrames[i]=="BVGatherTracker" then table.remove(UISpecialFrames,i) end end
        w:SetResizable(false);if w.resizeGrip then w.resizeGrip:Hide() end;if w.maximize then w.maximize:Hide() end
        self.window=w
        local c=w.content
        self.summary=UI:Label(c,"",13,"text",true);M.Point(self.summary,"TOPLEFT",c,"TOPLEFT",12,-8);M.Size(self.summary,WIDTH-24,20)
        self.detail=UI:Label(c,"",11,"muted");M.Point(self.detail,"TOPLEFT",c,"TOPLEFT",12,-30);M.Size(self.detail,WIDTH-24,18)
        local bw=(WIDTH-36)/3
        self.start=UI:Button(c,"Start",bw,function() if G.Tracker:State()=="running" then G.Tracker:Pause() else G.Tracker:Start() end end,true)
        M.Point(self.start,"TOPLEFT",c,"TOPLEFT",12,-54)
        self.stop=UI:Button(c,"Stop",bw,function() local entry=G.Tracker:Stop();if entry then W:Report(entry) end end,"ghost")
        M.Point(self.stop,"LEFT",self.start,"RIGHT",6,0)
        self.history=UI:Button(c,"Sessions",bw,function() W:Sessions() end,"ghost");M.Point(self.history,"LEFT",self.stop,"RIGHT",6,0)
        for i=1,ROWS do
            local row=CreateFrame("Frame",nil,c);M.Size(row,WIDTH-24,ROW);M.Point(row,"TOPLEFT",c,"TOPLEFT",12,-94-(i-1)*ROW)
            row.icon=row:CreateTexture(nil,"ARTWORK");M.Size(row.icon,16,16);M.Point(row.icon,"LEFT",row,"LEFT",0,0)
            row.name=UI:Label(row,"",11,"text");M.Point(row.name,"LEFT",row,"LEFT",22,0);M.Size(row.name,WIDTH-140,ROW);row.name:SetWordWrap(false)
            row.value=UI:Label(row,"",11,"muted");M.Point(row.value,"RIGHT",row,"RIGHT",0,0);M.Size(row.value,96,ROW);row.value:SetJustifyH("RIGHT")
            self.rows[i]=row
        end
        self.empty=UI:Label(c,"",11,"muted");M.Point(self.empty,"TOPLEFT",c,"TOPLEFT",12,-96);M.Size(self.empty,WIDTH-24,40);self.empty:SetWordWrap(true)
        w.drag:HookScript("OnDragStop",function() UI:SaveWindowPosition(w) end)
        w:HookScript("OnShow",function() W:Refresh();W:Watch(true) end)
        w:HookScript("OnHide",function() W:Watch(false) end)
        -- Closed with its X it stays closed after a reload (Florian 2026-10-10:
        -- only Show(false) remembered it). Not OnHide: hiding the interface
        -- (Alt+Z) or switching the module off hides it too.
        if w.close then w.close:HookScript("OnClick",function() G:Config().trackerWindow=false end) end
        if not UI:RestoreWindowPosition(w) then w:ClearAllPoints();w:SetPoint("RIGHT",UIParent,"RIGHT",-120,-260) end
        w:Hide()
    end)
    return self.window
end
function W:Show(on)
    local w=self:Build()
    if on==nil then on=not w:IsShown() end
    G:Config().trackerWindow=on and true or false
    w:SetShown(on)
end
-- The clock ticks once a second while the window is open and a session runs.
function W:Watch(on)
    if on and not self.ticker then self.ticker=C_Timer.NewTicker(1,function() if G.Tracker:State()=="running" then W:Refresh() end end)
    elseif not on and self.ticker then self.ticker:Cancel();self.ticker=nil end
end
local function clock(seconds)
    seconds=math.floor(seconds)
    return string.format("%d:%02d:%02d",math.floor(seconds/3600),math.floor(seconds/60)%60,seconds%60)
end
function W:Refresh()
    local w=self.window
    if not (w and w:IsShown()) then return end
    local T=G.Tracker
    local s=T:Session()
    local state=T:State()
    self.start:SetText(state=="running" and "Pause" or (state=="paused" and "Resume" or "Start"))
    if s then self.stop:Enable() else self.stop:Disable() end
    self.summary:SetText(string.format("%s  ·  %s/h",T.Money(T:Value()),T.Money(T:PerHour())))
    self.detail:SetText(string.format("%s  ·  %d nodes%s%s",clock(T:Elapsed()),s and s.nodes or 0,
        s and s.route and ("  ·  "..s.route) or "",state=="paused" and "  ·  paused" or ""))
    local items={}
    for itemID,count in pairs(s and s.items or {}) do items[#items+1]={id=itemID,count=count,value=T.Price(itemID)*count} end
    table.sort(items,function(a,b) if a.value~=b.value then return a.value>b.value end return a.id<b.id end)
    for i,row in ipairs(self.rows) do
        local item=items[i]
        row:SetShown(item~=nil)
        if item then
            -- Items new to the client have no data yet (Florian 2026-10-09:
            -- "Item 2452" with a question mark): the icon comes at once by
            -- ID, the name from the loot line until the data arrives.
            local name,_,_,_,_,_,_,_,_,icon=G.Call("GetItemInfo",item.id)
            if not name then
                G.Call("C_Item.RequestLoadItemDataByID",item.id)
                name=s.names and s.names[item.id]
            end
            icon=icon or G.Call("C_Item.GetItemIconByID",item.id) or G.Call("GetItemIcon",item.id)
            row.icon:SetTexture(icon or 134400)
            row.name:SetText(string.format("%dx %s",item.count,name or ("Item "..item.id)))
            row.value:SetText(T.Money(item.value))
        end
    end
    self.empty:SetShown(#items==0)
    self.empty:SetText(s and "Nothing gathered yet this session." or "Start a session, then gather: loot from your nodes is counted with its value.")
end
function W:Report(entry)
    G:Print(string.format("Session: %s in %s, %d nodes, %s/h.",G.Tracker.Money(entry.value),clock(entry.duration),entry.nodes,
        G.Tracker.Money(entry.duration>0 and entry.value/entry.duration*3600 or 0)))
end
function W:Sessions()
    local list=G.Data.db.sessions or {}
    if #list==0 then G:Print("No finished sessions yet.");return end
    for i=1,math.min(5,#list) do
        local e=list[i]
        G:Print(string.format("%s: %s in %s, %d nodes, %s/h%s",date("%Y-%m-%d %H:%M",e.started),G.Tracker.Money(e.value),clock(e.duration),e.nodes,
            G.Tracker.Money(e.duration>0 and e.value/e.duration*3600 or 0),e.route and (" ("..e.route..")") or ""))
    end
end
function W:Enable(context)
    if G:Config().trackerWindow then self:Show(true) end
    context:Defer(function() if W.window then W.window:Hide() end;W:Watch(false) end)
end
