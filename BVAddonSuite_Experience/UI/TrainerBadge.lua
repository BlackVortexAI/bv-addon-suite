local _,E=...
if not E.ready then return end
-- The trainer badge (Florian 2026-10-16): a book and how many abilities
-- wait; the tooltip lists them; click: led to the class trainer (with BV
-- Codex); right-click: a menu (hide until the next level, back to its own
-- place); Shift-drag: where you want it.
-- Its own place is where your quests are shown (Florian: above the
-- experience bar it sat in other bars): with BV Quest's tracker none (that
-- tracker has the line); at Blizzard's quest tracker on its side towards the
-- middle of the screen; without one at the minimap, below it when the
-- minimap is in the upper half of the screen, above it when in the lower.
local ns=BVAddonSuiteCore
local UI,M=ns.UI,ns.DesignSystem.Metrics
local B={}
E.TrainerBadge=B
if ns.ExperienceLevelUp then ns.ExperienceLevelUp.TrainerBadge=B end
B.GAP=12
B.TRACKERS={"ObjectiveTrackerFrame","QuestWatchFrame","WatchFrame"}

local function cfg() return ns.Settings:Module("experience_bar") end
local function shown(frame) return type(frame)=="table" and frame.IsShown and frame:IsShown() and (frame:GetHeight() or 0)>0 end
-- BV Quest's tracker is up: its line says it.
function B:OurTracker()
    local Q=ns.Quest
    return Q~=nil and Q.Tracker~=nil and Q.Tracker:Shown()
end
function B:Tracker()
    for _,name in ipairs(self.TRACKERS) do
        local f=rawget(_G,name)
        if shown(f) then return f end
    end
end
-- Where against a frame centred at (cx, cy) on a screen of (w, h): for a
-- tracker its top, on the side towards the middle; for the minimap below
-- it in the upper half, above it in the lower. point, relativePoint, x, y.
function B.Side(kind,cx,cy,w,h)
    if kind=="tracker" then
        if cx>w/2 then return "TOPRIGHT","TOPLEFT",-B.GAP,0 end
        return "TOPLEFT","TOPRIGHT",B.GAP,0
    end
    if cy>h/2 then return "TOP","BOTTOM",0,-B.GAP end
    return "BOTTOM","TOP",0,B.GAP
end
function B:Place()
    local f=self.frame
    f:ClearAllPoints()
    local at=cfg().trainerAt
    if type(at)=="table" and type(at.x)=="number" and type(at.y)=="number" then f:SetPoint("CENTER",UIParent,"BOTTOMLEFT",at.x,at.y);return "free" end
    local w,h=UIParent:GetWidth(),UIParent:GetHeight()
    local tracker=self:Tracker()
    local target,kind=tracker,"tracker"
    if not target then target,kind=rawget(_G,"MinimapCluster") or rawget(_G,"Minimap"),"minimap" end
    if not shown(target) then f:SetPoint("TOP",UIParent,"TOP",0,-M.ToNative(120));return "screen" end
    local cx,cy=target:GetCenter()
    local point,rel,x,y=B.Side(kind,cx or w/2,cy or h/2,w,h)
    M.Point(f,point,target,rel,x,y)
    return kind
end

function B:Frame()
    if self.frame then return self.frame end
    UI:WithStyle(UI:GameStyle(nil),function()
        local f=UI:Panel(UIParent,52,22,"panel",11,.85)
        f:SetFrameStrata("MEDIUM");f:SetClampedToScreen(true);f:EnableMouse(true);f:SetMovable(true)
        if ns.ExternalFrames then ns.ExternalFrames:MarkOwned(f) end
        if f.RegisterForDrag then f:RegisterForDrag("LeftButton") end
        f.icon=UI:Icon(f,"book-open",14,"accent");M.Point(f.icon,"LEFT",f,"LEFT",8,0)
        f.count=UI:Label(f,"",13,"accent",true);M.Point(f.count,"LEFT",f.icon,"RIGHT",5,0)
        f:SetScript("OnDragStart",function(self) if IsShiftKeyDown and IsShiftKeyDown() then self.moving=true;self:StartMoving() end end)
        f:SetScript("OnDragStop",function(self)
            if not self.moving then return end
            self.moving=nil;self:StopMovingOrSizing()
            local x,y=self:GetCenter()
            if x and y then cfg().trainerAt={x=x,y=y} end
        end)
        f:SetScript("OnMouseUp",function(self,button)
            if self.moving then return end
            if button=="RightButton" then B:Menu()
            elseif E.Trainer:CanLead() then E.Trainer:Lead() end
        end)
        f:SetScript("OnEnter",function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self,"ANCHOR_BOTTOM");GameTooltip:SetText("New at your class trainer",1,1,1)
            GameTooltip:AddLine(E.Trainer:Tip(),.85,.85,.85,true)
            if E.Trainer:CanLead() then GameTooltip:AddLine("Click: lead me to my trainer.",.6,.6,.6,true) end
            GameTooltip:AddLine("Shift-drag: move it. Right-click: more.",.6,.6,.6,true)
            GameTooltip:Show()
        end)
        f:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end)
        self.frame=f
    end)
    return self.frame
end
function B:Menu()
    local options={{value="hide",label="Hide until my next level"}}
    if cfg().trainerAt then options[#options+1]={value="auto",label="Back to its own place"} end
    UI:ContextMenu(self.frame,options,function(value)
        if value=="hide" then E.Trainer:Hide()
        elseif value=="auto" then cfg().trainerAt=nil;B:Update() end
    end)
end
function B:Update()
    if not (E.Trainer:Shown() and not self:OurTracker()) then
        if self.frame then self.frame:Hide() end
        return
    end
    local f=self:Frame()
    f.count:SetText(tostring(#E.Trainer.list))
    self.where=self:Place()
    f:Show()
end
-- BV Quest's tracker and Blizzard's come and go: the badge follows.
local Q=ns.Quest
if Q and Q.On then Q:On("Changed",B,function() B:Update() end) end
for _,name in ipairs(B.TRACKERS) do
    local f=rawget(_G,name)
    if type(f)=="table" and f.HookScript then
        f:HookScript("OnShow",function() B:Update() end);f:HookScript("OnHide",function() B:Update() end)
    end
end
