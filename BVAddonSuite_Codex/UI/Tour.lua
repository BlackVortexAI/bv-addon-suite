local _,C=...
if not C.ready then return end
-- The tour window as a timeline: you at the top, then each stop as a
-- numbered circle on a line, with the place chosen for it, what it is and
-- the time to it; move up or down, take away. Below the whole time large,
-- "Best order" (the order may change too), Add stop, Clear, Navigate. While
-- leading, the stop you are on to lights up.
local ns=C.ns
local UI,M=ns.UI,ns.DesignSystem.Metrics
local T=C.Tour
local W={rows={}}
T.Window=W
W.ROWS=8
local ROW,WIDTH,TOP=52,500,64
local WHITE="Interface\\Buttons\\WHITE8X8"
local function color(key,alpha)
    local r,g,b=UI:GameStyle(nil):Color(key)
    return r,g,b,alpha or 1
end
function W:Build()
    if self.window then return self.window end
    UI:WithStyle(UI:GameStyle(nil),function()
        local w=UI:Window("BVCodexTour",WIDTH,TOP+W.ROWS*ROW+120,{title="Tour"})
        self.window=w
        local c=w.content
        -- You: where the tour begins.
        self.you=UI:Panel(c,30,30,"raised",15,.95);M.Point(self.you,"TOPLEFT",c,"TOPLEFT",20,-12)
        self.youIcon=UI:Icon(self.you,"locate",16,"accent");self.youIcon:ClearAllPoints();M.Point(self.youIcon,"CENTER",self.you,"CENTER",0,0)
        self.youText=UI:Label(c,"You",13,"text",true);M.Point(self.youText,"LEFT",self.you,"RIGHT",12,6)
        self.note=UI:Label(c,"",11,"muted");M.Point(self.note,"TOPLEFT",self.you,"TOPRIGHT",12,-17);M.Size(self.note,WIDTH-90,14)
        -- The line through the circles.
        self.line=c:CreateTexture(nil,"ARTWORK");self.line:SetTexture(WHITE);self.line:SetVertexColor(color("accent",.5))
        M.Width(self.line,2)
        for i=1,W.ROWS do self:Row(c,i) end
        -- The whole way, large.
        self.total=UI:Label(c,"",18,"text",true);M.Point(self.total,"BOTTOMLEFT",c,"BOTTOMLEFT",20,62)
        self.totalNote=UI:Label(c,"",11,"muted");M.Point(self.totalNote,"BOTTOMLEFT",c,"BOTTOMLEFT",20,46)
        self.bestLabel=UI:Label(c,"Best order",11,"text");M.Point(self.bestLabel,"BOTTOMRIGHT",c,"BOTTOMRIGHT",-64,62)
        self.best=UI:Switch(c,false,function(value) T:SetBest(value) end);M.Point(self.best,"BOTTOMRIGHT",c,"BOTTOMRIGHT",-18,58)
        UI:AttachTooltip(self.best,"Best order","Off: your order, only which place of a stop is chosen. On: every order is tried too (up to "..T.ORDERED.." stops).")
        self.add=UI:Button(c,"Add stop",100,function() C.Palette:Open() end,"ghost");M.Point(self.add,"BOTTOMLEFT",c,"BOTTOMLEFT",16,10)
        UI:AttachTooltip(self.add,"Add stop","Opens the search (/bv codex).")
        self.clear=UI:Button(c,"Clear",80,function() T:Stop();T:Clear() end,"ghost");M.Point(self.clear,"LEFT",self.add,"RIGHT",8,0)
        self.go=UI:Button(c,"Navigate",130,function() if T.running then T:Stop() else T:Navigate() end end,true);M.Point(self.go,"BOTTOMRIGHT",c,"BOTTOMRIGHT",-16,10)
        UI:AttachTooltip(self.go,"Navigate","BV Routing leads you to each stop in turn; arriving at one starts the next.")
        -- The points on the map go with the window.
        -- While open: walked off, the places are chosen anew.
        -- The guide of the way stands beside it while it is open.
        local function guide() local R=C.Routing();if R and R.Guide then R.Guide:Update() end end
        w:HookScript("OnShow",function()
            T:ShowMap()
            guide()
            if not W.ticker then W.ticker=C_Timer.NewTicker(2,function() if T:Moved() then T.plan=nil;W:Refresh();T:ShowMap() end end) end
        end)
        w:HookScript("OnHide",function()
            T:ShowMap()
            guide()
            if W.ticker then W.ticker:Cancel();W.ticker=nil end
        end)
        w:Hide()
    end)
    return self.window
end
function W:Row(c,i)
    local row=CreateFrame("Frame",nil,c)
    M.Size(row,WIDTH-36,ROW-6);M.Point(row,"TOPLEFT",c,"TOPLEFT",18,-(TOP-8+(i-1)*ROW))
    -- The card behind the stop; lit while leading to it.
    row.card=UI:Panel(row,WIDTH-90,ROW-8,"panel",8,.5);M.Point(row.card,"LEFT",row,"LEFT",46,0)
    -- The numbered circle on the line.
    row.circle=UI:Panel(row,30,30,"raised",15,1);M.Point(row.circle,"LEFT",row,"LEFT",2,0)
    row.ring=row.circle:CreateTexture(nil,"OVERLAY");row.ring:SetTexture(WHITE);row.ring:SetVertexColor(color("accent"))
    M.Point(row.ring,"BOTTOMLEFT",row.circle,"BOTTOMLEFT",6,2);M.Point(row.ring,"BOTTOMRIGHT",row.circle,"BOTTOMRIGHT",-6,2);M.Height(row.ring,2)
    row.index=UI:Label(row.circle,"",13,"accent",true);M.Point(row.index,"CENTER",row.circle,"CENTER",0,1)
    -- Its number switches it on or off (done ones are off).
    row.circle:EnableMouse(true)
    row.circle:SetScript("OnMouseUp",function() if row.stop then T:Toggle(row.stopIndex) end end)
    UI:AttachTooltip(row.circle,"On or off","Click: this stop off (left out of the way, kept in the list) or on again. Stops you arrived at are switched off by themselves.")
    row.name=UI:Label(row.card,"",13,"text",true);M.Point(row.name,"TOPLEFT",row.card,"TOPLEFT",12,-6);M.Size(row.name,WIDTH-310,16);row.name:SetWordWrap(false)
    row.detail=UI:Label(row.card,"",11,"muted");M.Point(row.detail,"TOPLEFT",row.card,"TOPLEFT",12,-24);M.Size(row.detail,WIDTH-250,14);row.detail:SetWordWrap(false)
    -- The time to it, quiet on the right of the name.
    row.badge=CreateFrame("Frame",nil,row.card);M.Size(row.badge,80,16);M.Point(row.badge,"TOPRIGHT",row.card,"TOPRIGHT",-140,-6)
    row.time=UI:Label(row.badge,"",12,"muted");M.Point(row.time,"RIGHT",row.badge,"RIGHT",0,0);row.time:SetJustifyH("RIGHT")
    -- On or off at a glance (Florian 2026-10-12: clicking the number was
    -- found only by its tooltip). On the row, not the card: bright when off.
    row.on=UI:Switch(row,true,function(value) if row.stop then T:SetOff(row.stopIndex,not value) end end)
    M.Point(row.on,"RIGHT",row.card,"RIGHT",-96,0)
    UI:AttachTooltip(row.on,"In the tour","On: led there. Off: kept in the list, left out of the way. Stops you arrived at switch off by themselves; switch them on to go again.")
    row.up=UI:IconButton(row.card,"arrow-up",function() T:Move(i,-1) end,"ghost");M.Size(row.up,26,26);M.Point(row.up,"RIGHT",row.card,"RIGHT",-62,0)
    row.down=UI:IconButton(row.card,"arrow-down",function() T:Move(i,1) end,"ghost");M.Size(row.down,26,26);M.Point(row.down,"RIGHT",row.card,"RIGHT",-34,0)
    row.remove=UI:IconButton(row.card,"x",function() T:Remove(i) end,"ghost");M.Size(row.remove,26,26);M.Point(row.remove,"RIGHT",row.card,"RIGHT",-6,0)
    UI:AttachTooltip(row.up,"Earlier","This stop one place earlier.")
    UI:AttachTooltip(row.down,"Later","This stop one place later.")
    UI:AttachTooltip(row.remove,"Take away","Takes this stop out of the tour.")
    self.rows[i]=row
end
function W:Open()
    T:Ensure()
    local w=self:Build()
    w:Show()
    self:Refresh()
end
function W:Toggle()
    local w=self:Build()
    if w:IsShown() then w:Hide() else self:Open() end
end
function W:Refresh()
    if not (self.window and self.window:IsShown()) then return end
    local stops=T.stops
    -- While led, the plan followed (its numbers are the leading's).
    local plan=T.running and T.running.plan or (#stops>0 and T:Plan() or nil)
    -- The rows: the plan's order (with Best order it may differ), then the
    -- stops off, faint.
    local order,at={},{}
    if plan then for k,stop in ipairs(plan.order) do order[#order+1]=stop;at[stop]=k end end
    for _,stop in ipairs(stops) do if not at[stop] then order[#order+1]=stop end end
    local running=T.running
    self.note:SetText(#stops==0 and "No stops yet: Add stop, or /bv codex."
        or running and string.format("Leading: stop %d of %d",running.at,#running.plan.places)
        or plan and "The places are chosen for the whole way." or "No position here: the places are chosen in the world.")
    local shown=0
    for i,row in ipairs(self.rows) do
        local stop=order[i]
        row:SetShown(stop~=nil)
        row.stop=stop
        if stop then
            shown=i
            for k,s in ipairs(stops) do if s==stop then row.stopIndex=k end end
            local k=at[stop]
            local p=plan and k and plan.places[k]
            row.index:SetText(k or "-")
            row.name:SetText(stop.entry.name)
            local parts={}
            if p then
                if #stop.entry.places>1 and not stop.fixed and p.name~=stop.entry.name then parts[#parts+1]=p.name end
                if p.label and p.label~="" and p.label~=p.name then parts[#parts+1]=p.label end
            end
            if #stop.entry.places>1 and not stop.fixed then parts[#parts+1]="best of "..#stop.entry.places end
            if stop.off then parts[#parts+1]=stop.off=="done" and "Done - switch it on to go again" or "Off - left out of the way" end
            row.detail:SetText(table.concat(parts,"  -  "))
            row.badge:SetShown(k~=nil)
            row.time:SetText(k and ("+"..T.Clock(plan.legs[k])) or "")
            local lit=running and k and running.at==k
            row.card:SetAlpha((stop.off or (running and k and running.at>k)) and .45 or 1)
            row.circle:SetAlpha(stop.off and .5 or 1)
            row.ring:SetShown(lit or false)
            row.up:SetShown(row.stopIndex>1);row.down:SetShown(row.stopIndex<#stops)
            row.on:SetValue(not stop.off)
        end
    end
    -- The line reaches the last stop's circle.
    self.line:ClearAllPoints()
    if shown>0 then
        M.Point(self.line,"TOP",self.you,"BOTTOM",0,0)
        M.Point(self.line,"BOTTOM",self.rows[shown].circle,"CENTER",0,0)
    end
    self.line:SetShown(shown>0)
    -- As tall as its stops (three at least).
    M.Height(self.window,TOP+math.max(3,shown)*ROW+124)
    self.total:SetText(plan and ("Whole way: about "..T.Clock(plan.seconds)) or "")
    local off=#stops-#T:Active()
    self.totalNote:SetText(plan and (#plan.order.." stops, estimated"..(T.best and ", best order" or ", your order")..(off>0 and (", "..off.." off") or "")) or (off>0 and "Every stop is done or off" or ""))
    self.best:SetValue(T.best==true)
    self.go:SetText(running and "Stop" or "Navigate")
    if #stops>0 then self.go:Enable() else self.go:Disable() end
end
