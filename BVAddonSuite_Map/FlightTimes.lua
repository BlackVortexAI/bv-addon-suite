local _,P=...
if not P.ready then return end
-- Flight times (Florian 2026-10-09, map plan phase 6): learned from your
-- own flights, no static data. Taking a flight remembers where from and to;
-- losing control on the taxi starts the clock, getting it back stops it.
-- The flight master's tooltip then shows the time for that destination.
local F={}
P.FlightTimes=F
F.KEEP=5   -- flights averaged per route
function F:Store()
    local c=P:Config()
    if type(c.flightTimes)~="table" then c.flightTimes={} end
    return c.flightTimes
end
function F.Key(from,to) return tostring(from).." > "..tostring(to) end
function F.Clock(seconds)
    seconds=math.floor(seconds+.5)
    return string.format("%d:%02d",math.floor(seconds/60),seconds%60)
end
-- The flight master you stand at (its node is of type CURRENT).
function F:Current()
    for i=1,(P.Call("NumTaxiNodes") or 0) do
        if P.Call("TaxiNodeGetType",i)=="CURRENT" then return P.Call("TaxiNodeName",i) end
    end
end
function F:Took(index)
    if not (self.active and P:Config().learnFlights) then return end
    local from,to=self:Current(),P.Call("TaxiNodeName",index)
    if type(from)=="string" and type(to)=="string" and from~=to then self.pending={from=from,to=to,taken=GetTime()} end
end
function F:Lost()
    local p=self.pending
    if p and not p.start and GetTime()-p.taken<15 then p.start=GetTime() end
end
function F:Gained()
    local p=self.pending
    if not (p and p.start) then return end
    if P.Call("UnitOnTaxi","player")==true then return end
    self.pending=nil
    local seconds=GetTime()-p.start
    if seconds<5 then return end
    local key=F.Key(p.from,p.to)
    local entry=self:Store()[key]
    local first=entry==nil
    entry=entry or {seconds=0,count=0}
    local n=math.min(entry.count,F.KEEP-1)
    entry.seconds=(entry.seconds*n+seconds)/(n+1);entry.count=n+1
    self:Store()[key]=entry
    if first then P:Print(string.format("Flight time learned: %s to %s, %s.",p.from,p.to,F.Clock(seconds))) end
end
-- The learned time from where you stand to a node, or nil.
function F:Time(index)
    local from,to=self:Current(),P.Call("TaxiNodeName",index)
    local entry=from and to and self:Store()[F.Key(from,to)]
    return entry and entry.seconds or nil
end
function F:Hint(index)
    if not (self.active and P:Config().learnFlights and index) then return end
    local seconds=self:Time(index)
    local tip=rawget(_G,"GameTooltip")
    if not (seconds and tip and tip.AddLine) then return end
    tip:AddLine("Flight time: "..F.Clock(seconds),1,1,1)
    tip:Show()
end
-- Hooks stay (they cannot be removed); they act only while the module runs.
function F:Hook()
    if self.hooked then return end
    self.hooked=true
    if type(rawget(_G,"TakeTaxiNode"))=="function" then hooksecurefunc("TakeTaxiNode",function(index) F:Took(index) end) end
    -- The old flight map (buttons) and the newer one (pins).
    if type(rawget(_G,"TaxiNodeOnButtonEnter"))=="function" then
        hooksecurefunc("TaxiNodeOnButtonEnter",function(button) F:Hint(button and button.GetID and button:GetID()) end)
    end
    local mixin=rawget(_G,"FlightPointPinMixin")
    if type(mixin)=="table" and type(mixin.OnMouseEnter)=="function" then
        hooksecurefunc(mixin,"OnMouseEnter",function(pin) F:Hint(pin and pin.taxiNodeData and pin.taxiNodeData.slotIndex) end)
    end
end
function F:Enable(context)
    self.active=true
    self:Hook()
    pcall(context.Subscribe,context,"PLAYER_CONTROL_LOST",function() F:Lost() end)
    pcall(context.Subscribe,context,"PLAYER_CONTROL_GAINED",function() F:Gained() end)
    context:Defer(function() F.active=false;F.pending=nil end)
end
