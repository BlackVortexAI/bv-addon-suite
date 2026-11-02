local _,Routing=...
if not Routing.ready then return end
-- A small note beside the mouse pointer while a way is calculated
-- (Florian 2026-10-14: "the user gets no visual feedback during the
-- calculation"): a turning symbol, what runs ("Finding the way",
-- "Calculating the route", ...) and the seconds so far. Every calculation in
-- slices (Scheduler.Run) shows it, from any package; the newest names it. The
-- mouse passes through. Built when first needed; its ticker (EVERY seconds)
-- runs while calculations are active or a question awaits its first presentation.
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

local function style() return B.style end
function B:Build()
    if self.frame then return self.frame end
    local captured=UI:InterfaceStyle();if not captured then return nil end
    self.style=captured
    UI:WithStyle(style(),function()
        local f=UI:Panel(UIParent,180,B.HEIGHT,"panel",8,.92)
        f.bvStyle=self.style;f.bvTooltipStyle=self.style
        f:Hide();f:SetFrameStrata("TOOLTIP");f:EnableMouse(false);f:SetClampedToScreen(true)
        if ns.ExternalFrames then ns.ExternalFrames:MarkOwned(f) end
        f.icon=f:CreateTexture(nil,"OVERLAY")
        local path,l,r,t,b=ns.Symbols:Coords("rotate-cw",32)
        if path then f.icon:SetTexture(path);f.icon:SetTexCoord(l,r,t,b) end
        self.style:Bind(function()
            f.icon:SetVertexColor(self.style:Color(self.style.materialProfile=="interface" and "accentText" or "accent"))
        end,f.icon)
        M.Size(f.icon,14,14);M.Point(f.icon,"LEFT",f,"LEFT",8,0)
        f.text=UI:Label(f,"",11,"text");M.Point(f.text,"LEFT",f.icon,"RIGHT",6,0)
        self.frame=f
    end)
    return self.frame
end
-- The existing follower owns active runs and not-yet-presented questions.
function B:UpdateTicker()
    local wanted=#self.order>0 or self.pendingPrompt~=nil
    if wanted and not self.ticker then self.ticker=C_Timer.NewTicker(B.EVERY,function() B:Follow() end)
    elseif not wanted and self.ticker then self.ticker:Cancel();self.ticker=nil end
end
-- A calculation began (handle: Scheduler.Run's, label: what runs).
function B:Start(handle,label)
    if not handle then return end
    self.runs[handle]={label=label or "Calculating",began=GetTime()}
    self.order[#self.order+1]=handle
    local f=self:Build();if f then f:Show() end
    self:UpdateTicker()
    self:Follow()
end
function B:Stop(handle)
    if not (handle and self.runs[handle]) then return end
    self.runs[handle]=nil
    if self.asking==handle then
        self.asking,self.onYes,self.onNo,self.question,self.pendingPrompt=nil,nil,nil,nil,nil
        if self.ask then self.ask:Hide() end
    end
    for i=#self.order,1,-1 do if self.order[i]==handle then table.remove(self.order,i) end end
    if #self.order==0 and self.frame then self.frame:Hide() end
    self:UpdateTicker()
    if #self.order>0 or self.pendingPrompt then self:Follow() end
end
function B:Active() return #self.order>0 end
-- Beside the pointer (right of it, a little below), turning, the newest
-- calculation's name and seconds.
function B:Follow()
    self:PresentPrompt()
    local handle=self.order[#self.order]
    local run=handle and self.runs[handle]
    if not run then
        if self.frame then self.frame:Hide() end
        self:UpdateTicker();return
    end
    local f=self.frame or self:Build()
    if f then
        f:Show()
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
    end
    if handle.askStop and not self.asking and not self.question and GetTime()-run.began>=(run.askAt or B.ASKAFTER) then self:Ask(handle,run) end
    self:UpdateTicker()
end
-- A question with two answers: a small panel at the top of the screen
-- (the long calculation's "go on?", the missing flight points before a way).
function B:Prompt(text,yes,no,onYes,onNo,handle)
    -- One current question, as before; capture its continuation before any UI work.
    self.question={text=text,yes=yes,no=no}
    self.pendingPrompt=self.question
    self.onYes,self.onNo,self.asking=onYes,onNo,handle
    self:PresentPrompt()
    self:UpdateTicker()
end
function B:PresentPrompt()
    local question=self.pendingPrompt;if not question then return end
    if not self.ask then
        -- Capture once so question reuse ignores unrelated callers.
        local promptStyle=UI:InterfaceStyle();if not promptStyle then return nil end
        UI:WithStyle(promptStyle,function()
            local a=UI:Panel(UIParent,360,100,"panel",10,.95)
            a.bvStyle=promptStyle
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
    a.text:SetText(question.text)
    a.go:SetLabelText(question.yes)
    a.stop:SetLabelText(question.no)
    self.pendingPrompt=nil
    a:Show()
end
function B:Answer(yes)
    local f=yes and self.onYes or self.onNo
    self.onYes,self.onNo,self.question,self.pendingPrompt,self.asking=nil,nil,nil,nil,nil
    if self.ask then self.ask:Hide() end
    self:UpdateTicker()
    if f then f() end
end
-- Go on or stop (a long calculation; it runs on while asked).
function B:Ask(handle,run)
    self:Prompt(string.format("%s for %d s now: a long way (few flight masters, a far city). Go on calculating?",run.label,math.floor(GetTime()-run.began)),
        "Go on","Stop",
        function() B.asking=nil;local r=B.runs[handle];if r then r.askAt=GetTime()-r.began+B.ASKAGAIN end end,
        function() B.asking=nil;if B.runs[handle] and handle.askStop then handle.askStop() end end,handle)
end
