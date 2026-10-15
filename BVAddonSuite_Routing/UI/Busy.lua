local _,Routing=...
if not Routing.ready then return end
-- A small note beside the mouse pointer while a way is calculated
-- (Florian 2026-10-14: "the user gets no visual feedback during the
-- calculation"): a turning symbol, what runs ("Finding the way",
-- "Calculating the route", ...) and the seconds so far. Every calculation in
-- slices (Grid.Run) shows it, from any package; the newest names it. The
-- mouse passes through. Built when first needed; its ticker (EVERY seconds)
-- runs only while it is shown.
local ns=Routing.ns
local UI,M=ns.UI,ns.DesignSystem.Metrics
local B={runs={},order={}}
Routing.Busy=B
B.OFFSET=18
B.HEIGHT=26
B.EVERY=.02
-- A calculation that may be stopped (handle.askStop, Navigate's): after
-- ASKAFTER seconds, then every ASKAGAIN, asked whether to go on (Florian
-- 2026-10-15: a far city with few flight masters calculated for minutes).
B.ASKAFTER=20
B.ASKAGAIN=40

local function style() return UI:GameStyle(nil) end
function B:Build()
    if self.frame then return self.frame end
    UI:WithStyle(style(),function()
        local f=UI:Panel(UIParent,180,B.HEIGHT,"panel",8,.92)
        f:Hide();f:SetFrameStrata("TOOLTIP");f:EnableMouse(false);f:SetClampedToScreen(true)
        if ns.ExternalFrames then ns.ExternalFrames:MarkOwned(f) end
        f.icon=f:CreateTexture(nil,"OVERLAY")
        local path,l,r,t,b=ns.Symbols:Coords("rotate-cw",32)
        if path then f.icon:SetTexture(path);f.icon:SetTexCoord(l,r,t,b) end
        f.icon:SetVertexColor(style():Color("accent"))
        M.Size(f.icon,14,14);M.Point(f.icon,"LEFT",f,"LEFT",8,0)
        f.text=UI:Label(f,"",11,"text");M.Point(f.text,"LEFT",f.icon,"RIGHT",6,0)
        self.frame=f
    end)
    return self.frame
end
-- A calculation began (handle: Grid.Run's, label: what runs).
function B:Start(handle,label)
    if not handle then return end
    self.runs[handle]={label=label or "Calculating",began=GetTime()}
    self.order[#self.order+1]=handle
    self:Build():Show()
    if not self.ticker then self.ticker=C_Timer.NewTicker(B.EVERY,function() B:Follow() end) end
    self:Follow()
end
function B:Stop(handle)
    if not (handle and self.runs[handle]) then return end
    self.runs[handle]=nil
    if self.asking==handle then self.asking,self.onYes,self.onNo=nil,nil,nil;if self.ask then self.ask:Hide() end end
    for i=#self.order,1,-1 do if self.order[i]==handle then table.remove(self.order,i) end end
    if #self.order==0 then
        if self.frame then self.frame:Hide() end
        if self.ticker then self.ticker:Cancel();self.ticker=nil end
    else self:Follow() end
end
function B:Active() return #self.order>0 end
-- Beside the pointer (right of it, a little below), turning, the newest
-- calculation's name and seconds.
function B:Follow()
    local f=self.frame
    local handle=self.order[#self.order]
    local run=handle and self.runs[handle]
    if not (f and run) then if f then f:Hide() end;return end
    local x,y=GetCursorPosition()
    local scale=UIParent:GetEffectiveScale()
    if type(x)=="number" and type(y)=="number" and scale and scale>0 then
        f:ClearAllPoints();f:SetPoint("TOPLEFT",UIParent,"BOTTOMLEFT",x/scale+B.OFFSET,y/scale-B.OFFSET/2)
    end
    local seconds=math.floor(GetTime()-run.began)
    f.text:SetText(seconds>=1 and string.format("%s ... %d s",run.label,seconds) or (run.label.." ..."))
    local width=f.text.GetStringWidth and f.text:GetStringWidth() or 100
    f:SetWidth(math.max(120,width+36))
    if f.icon.SetRotation then f.icon:SetRotation(-(GetTime()*4)%(2*math.pi)) end
    if handle.askStop and not self.asking and GetTime()-run.began>=(run.askAt or B.ASKAFTER) then self:Ask(handle,run) end
end
-- A question with two answers: a small panel at the top of the screen
-- (the long calculation's "go on?", the missing flight points before a way).
function B:Prompt(text,yes,no,onYes,onNo)
    if not self.ask then
        UI:WithStyle(style(),function()
            local a=UI:Panel(UIParent,360,100,"panel",10,.95)
            a:Hide();a:SetFrameStrata("DIALOG");a:SetPoint("TOP",UIParent,"TOP",0,-140);a:EnableMouse(true)
            if ns.ExternalFrames then ns.ExternalFrames:MarkOwned(a) end
            a.text=UI:Label(a,"",12,"text");M.Point(a.text,"TOPLEFT",a,"TOPLEFT",14,-12);M.Size(a.text,332,44)
            a.text:SetWordWrap(true)
            a.go=UI:Button(a,"",150,function() B:Answer(true) end,true);M.Point(a.go,"BOTTOMRIGHT",a,"BOTTOMRIGHT",-14,12)
            a.stop=UI:Button(a,"",110,function() B:Answer(false) end);M.Point(a.stop,"RIGHT",a.go,"LEFT",-8,0)
            self.ask=a
        end)
    end
    local a=self.ask
    a.text:SetText(text)
    a.go.label:SetText(yes)
    a.stop.label:SetText(no)
    self.onYes,self.onNo=onYes,onNo
    a:Show()
end
function B:Answer(yes)
    local f=yes and self.onYes or self.onNo
    self.onYes,self.onNo=nil,nil
    if self.ask then self.ask:Hide() end
    if f then f() end
end
-- Go on or stop (a long calculation; it runs on while asked).
function B:Ask(handle,run)
    self.asking=handle
    self:Prompt(string.format("%s for %d s now: a long way (few flight masters, a far city). Go on calculating?",run.label,math.floor(GetTime()-run.began)),
        "Go on","Stop",
        function() B.asking=nil;local r=B.runs[handle];if r then r.askAt=GetTime()-r.began+B.ASKAGAIN end end,
        function() B.asking=nil;if B.runs[handle] and handle.askStop then handle.askStop() end end)
end
